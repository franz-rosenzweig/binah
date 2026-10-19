"""Second stage: Claude looks only at the best candidates the measurements found.

    .venv/bin/python engine/rate.py books      # book cards + editor's picks located in the text
    .venv/bin/python engine/rate.py items      # draft items for each game from top candidates
    .venv/bin/python engine/rate.py validate   # blind second opinion on argument and gist drafts
    .venv/bin/python engine/rate.py all

Every call goes through claude_cli.ask (subscription CLI, tools off). Calls
are batched (several passages per call) to keep usage down.
"""
import json
import os
import re
import sqlite3
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from binah import claude_cli, config  # noqa: E402

DB = str(config.PASSAGES_DB)
VALIDATOR = config.model('validator')   # a different tier than the generator, per the research
WORKERS = 3

SYSTEM = ("You are the item editor for Binah, a private reading, reasoning and writing trainer for one reader: "
          + config.settings()['reader'] + ". You judge passages taken from the reader's own books and draft "
          "practice items from them. Be strict: reject passages that depend on context outside the excerpt, "
          "have no clear point, or would make a dull exercise. Write plainly. Quotes you give must be copied "
          "exactly from the passage.")

FLAWS = ['unsupported claim', 'overgeneralization', 'false cause', 'false choice', 'loaded or vague word',
         'appeal to authority', 'attack on a person', 'straw man', 'slippery slope', 'circular',
         'irrelevant point', 'none (sound)']

R04 = {'type': 'integer', 'minimum': 0, 'maximum': 4}
VERDICT = {'type': 'string', 'enum': ['use', 'maybe', 'reject']}
STR = {'type': 'string'}


def arr(item_props, required):
    return {'type': 'object', 'properties': {'items': {'type': 'array', 'items': {
        'type': 'object', 'properties': item_props, 'required': required}}}, 'required': ['items']}


SCHEMAS = {
    'gist': arr({'id': {'type': 'integer'}, 'self_contained': R04, 'main_idea_clear': R04, 'interest': R04,
                 'gist': STR, 'key_points': {'type': 'array', 'items': STR}, 'inference_q': STR, 'inference_a': STR,
                 'verdict': VERDICT, 'why': STR},
                ['id', 'self_contained', 'main_idea_clear', 'interest', 'gist', 'key_points', 'inference_q',
                 'inference_a', 'verdict', 'why']),
    'argument': arr({'id': {'type': 'integer'}, 'is_argument': {'type': 'boolean'}, 'conclusion': STR,
                     'premises': {'type': 'array', 'items': STR}, 'weakest_step_quote': STR,
                     'flaw': {'type': 'string', 'enum': FLAWS}, 'flaw_explain': STR, 'hidden_assumption': STR,
                     'strength': R04, 'verdict': VERDICT, 'why': STR},
                    ['id', 'is_argument', 'conclusion', 'premises', 'weakest_step_quote', 'flaw', 'flaw_explain',
                     'hidden_assumption', 'strength', 'verdict', 'why']),
    'subtext': arr({'id': {'type': 'integer'}, 'has_subtext': R04, 'question': STR, 'answer': STR,
                    'evidence_quote': STR, 'verdict': VERDICT, 'why': STR},
                   ['id', 'has_subtext', 'question', 'answer', 'evidence_quote', 'verdict', 'why']),
    'motjuste': arr({'id': {'type': 'integer'}, 'target': STR, 'fits_well': R04,
                     'decoys': {'type': 'array', 'items': STR}, 'why_target': STR, 'verdict': VERDICT},
                    ['id', 'target', 'fits_well', 'decoys', 'why_target', 'verdict']),
    'bloat': arr({'id': {'type': 'integer'}, 'bloated': STR, 'model_quality': R04, 'verdict': VERDICT, 'why': STR},
                 ['id', 'bloated', 'model_quality', 'verdict', 'why']),
}

INSTRUCTIONS = {
    'gist': ("For each passage: rate it (0-4) as a self-contained excerpt, for how clear its main idea is, and for "
             "interest. Then draft a Gist item: a gist of 20 words or fewer stating the main point (not a topic "
             "label); 3-5 key points, each a short proposition of 12 words or fewer; and one bridging-inference "
             "question whose answer is implied but never stated, so it can't be answered by copying a sentence, "
             "with its answer. verdict 'use' only if a careful reader could state the point from this excerpt alone."),
    'argument': ("For each passage: decide whether it actually argues for something. Give the conclusion and premises "
                 "in short plain words. Quote, exactly, the sentence or clause where the reasoning is weakest, label the "
                 "flaw from the fixed list (use 'none (sound)' if the reasoning holds up; good arguments are welcome), "
                 "explain in 25 words or fewer, and state the hidden assumption the argument needs. strength 0-4 is "
                 "how good the argument is. verdict 'use' if it makes a fair 'find the weak step' exercise."),
    'subtext': ("For each passage: rate 0-4 how much it implies something important that it never says outright (a "
                "feeling, a motive, a tension, what a character really means). Write the question 'What's really going "
                "on?' made specific to the passage, the answer, and the shortest exact quote that gives it away. "
                "verdict 'use' if a careful reader can infer it from this excerpt alone."),
    'motjuste': ("Each sentence comes with the author's word (target). Rate 0-4 how clearly that word beats near "
                 "alternatives here. Write exactly 4 decoys: real near-synonyms that fit the grammar but are a worse "
                 "fit in shade of meaning, tone or precision. Explain in 20 words or fewer why the author's word is "
                 "right. verdict 'use' if the choice is teachable and not a coin flip."),
    'bloat': ("Each sentence is a tight original by a good writer. Write a padded version of the SAME meaning that is "
              "about 1.6 to 1.8 times as long, padded the way real prose gets padded (wordy phrases, redundancy, "
              "needless hedges, nominalisations, passive voice), still grammatical and plausible. Rate 0-4 how good "
              "the original is as a model of concision. The player will cut your version back toward the original."),
}


def db():
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    c.executescript('''
      create table if not exists book_cards(book_id int primary key, card text, picks text, model text);
      create table if not exists drafts(game text, ref_id int, draft text, verdict text, model text,
        primary key(game, ref_id));
      create table if not exists validations(game text, ref_id int, blind text, agree text, detail text,
        primary key(game, ref_id));
      create table if not exists runs(job text, calls int, seconds real, cost_usd real, at text default (datetime('now')));
    ''')
    return c


def norm(s):
    return re.sub(r'[^a-z0-9 ]+', '', re.sub(r'\s+', ' ', s.lower())).strip()


def shingles(s, n=4):
    w = norm(s).split()
    return {' '.join(w[i:i + n]) for i in range(max(0, len(w) - n + 1))}


def pick(c, game, n, per_book=2):
    """Top candidates for a game, diversified by book, chapter and difficulty."""
    col = {'gist': 'fit_gist', 'argument': 'fit_argument', 'subtext': 'fit_subtext'}[game]
    rows = c.execute(f'''select p.*, b.title from passages p join books b on b.id=p.book_id
                         where {col} >= 0.6 and p.id not in (select ref_id from drafts where game=?)
                         order by {col} desc, highlighted desc limit 4000''', (game,)).fetchall()
    bands = {0: [], 1: [], 2: []}
    for r in rows:
        bands[0 if r['difficulty'] < 30 else 1 if r['difficulty'] < 50 else 2].append(r)
    chosen, per, spots = [], {}, set()
    i = 0
    while len(chosen) < n and any(bands.values()):
        band = bands[i % 3]
        i += 1
        while band:
            r = band.pop(0)
            spot = (r['book_id'], r['chapter'], r['para'] // 4)
            if per.get(r['book_id'], 0) >= per_book or spot in spots:
                continue
            per[r['book_id']] = per.get(r['book_id'], 0) + 1
            spots.add(spot)
            chosen.append(r)
            break
    return chosen


def pick_sentences(c, game, n):
    col, where = ('motjuste', 'target is not null and motjuste >= 0.6') if game == 'motjuste' else ('tight', 'tight >= 0.85')
    rows = c.execute(f'select s.*, b.title from sentences s join books b on b.id=s.book_id where {where} '
                     f'and s.id not in (select ref_id from drafts where game=?) '
                     f'order by {col} desc, random() limit 3000', (game,)).fetchall()
    chosen, per = [], {}
    for r in rows:
        if per.get(r['book_id'], 0) >= 2:
            continue
        per[r['book_id']] = per.get(r['book_id'], 0) + 1
        chosen.append(r)
        if len(chosen) >= n:
            break
    return chosen


def batches(xs, k):
    return [xs[i:i + k] for i in range(0, len(xs), k)]


def run_calls(jobs):
    """jobs: list of (prompt, schema, model, on_result). Runs a few at a time."""
    stats = {'calls': 0, 'seconds': 0.0, 'cost': 0.0}

    def go(job):
        prompt, schema, model, cb = job
        try:
            out, meta = claude_cli.ask(prompt, schema, SYSTEM, model=model)
        except Exception as e:  # keep going; report at the end
            return job, None, None, str(e)
        return job, out, meta, None

    errors = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for job, out, meta, err in ex.map(go, jobs):
            if err:
                errors.append(err)
                continue
            stats['calls'] += 1
            stats['seconds'] += meta['seconds']
            stats['cost'] += meta.get('cost_usd') or 0
            job[3](out, meta)
    return stats, errors


def job_items(c, sizes):
    jobs = []
    for game, n in sizes.items():
        if game in ('motjuste', 'bloat'):
            rows = pick_sentences(c, game, n)
            def fmt(r, game=game):
                extra = f' | target: "{r["target"]}"' if game == 'motjuste' else ''
                return f'[{r["id"]}] {r["text"]}{extra}'
        else:
            rows = pick(c, game, n)
            fmt = lambda r: f'[{r["id"]}] (from "{r["title"]}")\n{r["text"]}'
        for b in batches(rows, 8 if game not in ('motjuste', 'bloat') else 12):
            prompt = INSTRUCTIONS[game] + '\n\nItems, each with its id in brackets:\n\n' + '\n\n---\n\n'.join(fmt(r) for r in b)

            def save(out, meta, game=game):
                for it in out.get('items', []):
                    c.execute('insert or replace into drafts values(?,?,?,?,?)',
                              (game, it['id'], json.dumps(it), it.get('verdict'), meta['model']))
                c.commit()
            jobs.append((prompt, SCHEMAS[game], None, save))
    return jobs


CARD_SCHEMA = {'type': 'object', 'properties': {'books': {'type': 'array', 'items': {'type': 'object', 'properties': {
    'id': {'type': 'integer'}, 'kind': {'type': 'string', 'enum': ['fiction', 'nonfiction', 'mixed']},
    'field': STR, 'voice': STR, 'difficulty_guess': {'type': 'integer', 'minimum': 1, 'maximum': 5},
    'best_games': {'type': 'array', 'items': {'type': 'string', 'enum': ['gist', 'argument', 'subtext', 'motjuste', 'bloat', 'listen', 'blueprint']}},
    'why': STR, 'known_passages': {'type': 'array', 'items': {'type': 'object', 'properties': {
        'quote': STR, 'where': STR, 'why': STR, 'game': STR}, 'required': ['quote', 'where', 'why', 'game']}}},
    'required': ['id', 'kind', 'field', 'voice', 'difficulty_guess', 'best_games', 'why', 'known_passages']}}},
    'required': ['books']}


def job_books(c, n_books):
    rows = c.execute('''select b.*, (select count(*) from passages p where p.book_id=b.id and (p.fit_gist>0.8 or p.fit_argument>0.8 or p.fit_subtext>0.8)) good
                        from books b where b.passages > 50 order by good desc limit ?''', (n_books,)).fetchall()
    jobs = []
    for b in batches(rows, 6):
        listing = '\n'.join(f'[{r["id"]}] "{r["title"]}" by {r["authors"]} (tags: {r["tags"][:120]})' for r in b)
        prompt = ("From what you know about each book (no web), write a short card: fiction or nonfiction, field, the "
                  "author's voice in 15 words or fewer, a difficulty guess 1-5, which Binah games it suits best and why "
                  "(gist = state the point of an excerpt; argument = find the weak step; subtext = infer what's unsaid; "
                  "motjuste = the author's exact word; bloat = cut padding back to the author's line; listen = read aloud; "
                  "blueprint = rebuild a paragraph's order). Then up to 4 known_passages: well-known or especially "
                  "teachable passages, each with the opening words of the passage quoted as exactly as you can recall "
                  "them (8-16 words; only include ones you're fairly sure of), where it is, why it's good, and which game.\n\n"
                  + listing)

        def save(out, meta):
            for card in out.get('books', []):
                picks = locate(c, card['id'], card.get('known_passages', []))
                c.execute('insert or replace into book_cards values(?,?,?,?)',
                          (card['id'], json.dumps(card), json.dumps(picks), meta['model']))
            c.commit()
        jobs.append((prompt, CARD_SCHEMA, None, save))
    return jobs


def locate(c, book_id, known):
    """Find each recalled passage in the actual text by 4-word shingle overlap."""
    rows = c.execute('select id, text from passages where book_id=?', (book_id,)).fetchall()
    found = []
    for k in known:
        q = shingles(k['quote'])
        if not q:
            continue
        best, score = None, 0.0
        for r in rows:
            s = len(q & shingles(r['text'])) / len(q)
            if s > score:
                best, score = r['id'], s
        found.append({**k, 'passage_id': best if score >= 0.5 else None, 'match': round(score, 2)})
    return found


BLIND_ARG = arr({'id': {'type': 'integer'}, 'conclusion': STR, 'weakest_step_quote': STR,
                 'flaw': {'type': 'string', 'enum': FLAWS}}, ['id', 'conclusion', 'weakest_step_quote', 'flaw'])
BLIND_GIST = arr({'id': {'type': 'integer'}, 'gist': STR}, ['id', 'gist'])
COMPARE = arr({'id': {'type': 'integer'}, 'same_point': {'type': 'string', 'enum': ['yes', 'partly', 'no']},
               'note': STR}, ['id', 'same_point', 'note'])


def job_validate(c):
    jobs = []
    arg = c.execute("select d.ref_id, d.draft, p.text from drafts d join passages p on p.id=d.ref_id "
                    "where d.game='argument' and d.verdict in ('use','maybe') "
                    "and d.ref_id not in (select ref_id from validations where game='argument')").fetchall()
    for b in batches(arg, 8):
        prompt = ("For each passage: state its conclusion, quote exactly the sentence or clause where the reasoning is "
                  "weakest, and label the flaw from the fixed list ('none (sound)' if it holds up).\n\n"
                  + '\n\n---\n\n'.join(f'[{r["ref_id"]}]\n{r["text"]}' for r in b))

        def save(out, meta, b=b):
            drafts = {r['ref_id']: json.loads(r['draft']) for r in b}
            for it in out.get('items', []):
                d = drafts.get(it['id'])
                if not d:
                    continue
                qa, qb = shingles(d['weakest_step_quote'], 3), shingles(it['weakest_step_quote'], 3)
                span = len(qa & qb) / max(1, min(len(qa), len(qb))) if qa and qb else 0.0
                same_flaw = d['flaw'] == it['flaw']
                agree = 'yes' if span >= 0.5 and same_flaw else 'partly' if span >= 0.5 or same_flaw else 'no'
                c.execute('insert or replace into validations values(?,?,?,?,?)',
                          ('argument', it['id'], json.dumps(it), agree,
                           json.dumps({'span_overlap': round(span, 2), 'same_flaw': same_flaw})))
            c.commit()
        jobs.append((prompt, BLIND_ARG, VALIDATOR, save))
    gist = c.execute("select d.ref_id, d.draft, p.text from drafts d join passages p on p.id=d.ref_id "
                     "where d.game='gist' and d.verdict in ('use','maybe') "
                     "and d.ref_id not in (select ref_id from validations where game='gist')").fetchall()
    for b in batches(gist, 8):
        prompt = ("For each passage, write its gist in 20 words or fewer: the main point, not a topic label.\n\n"
                  + '\n\n---\n\n'.join(f'[{r["ref_id"]}]\n{r["text"]}' for r in b))

        def save(out, meta, b=b):
            for it in out.get('items', []):
                c.execute('insert or replace into validations(game, ref_id, blind) values(?,?,?)',
                          ('gist', it['id'], json.dumps(it)))
            c.commit()
        jobs.append((prompt, BLIND_GIST, VALIDATOR, save))
    return jobs


def job_compare(c):
    rows = c.execute("select v.ref_id, v.blind, d.draft, p.text from validations v join drafts d on d.game='gist' and d.ref_id=v.ref_id "
                     "join passages p on p.id=v.ref_id where v.game='gist' and v.agree is null").fetchall()
    jobs = []
    for b in batches(rows, 10):
        prompt = ("Two people each wrote a gist of the same passage without seeing each other's. For each, say whether "
                  "they state the same main point (yes / partly / no) and note the difference in 15 words or fewer.\n\n"
                  + '\n\n---\n\n'.join(f'[{r["ref_id"]}]\nPassage: {r["text"]}\nGist A: {json.loads(r["draft"])["gist"]}\n'
                                       f'Gist B: {json.loads(r["blind"])["gist"]}' for r in b))

        def save(out, meta):
            for it in out.get('items', []):
                c.execute('update validations set agree=?, detail=? where game=? and ref_id=?',
                          (it['same_point'], json.dumps({'note': it['note']}), 'gist', it['id']))
            c.commit()
        jobs.append((prompt, COMPARE, VALIDATOR, save))
    return jobs


def log(c, job, stats, errors):
    c.execute('insert into runs(job, calls, seconds, cost_usd) values(?,?,?,?)',
              (job, stats['calls'], stats['seconds'], stats['cost']))
    c.commit()
    print(f'{job}: {stats["calls"]} calls, {stats["seconds"]:.0f}s of model time, {len(errors)} errors', flush=True)
    for e in errors[:5]:
        print('  error:', e[:300])


NIGHTLY = {'gist': 8, 'argument': 16, 'subtext': 8, 'motjuste': 12, 'bloat': 8}


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    c = db()
    if what == 'nightly':
        # Fresh drafts from passages nobody has drafted yet, the blind check, then load into the app.
        log(c, 'items', *run_calls(job_items(c, NIGHTLY)))
        log(c, 'validate', *run_calls(job_validate(c)))
        log(c, 'compare', *run_calls(job_compare(c)))
        from binah import items
        print('imported:', items.import_all().get('live'))
        # Keep two sealed benchmark forms in hand, a few calls a night at most.
        from binah import benchgen, benchmark, db as bdb
        bc = bdb.connect()
        used = {r['form'] for r in bc.execute('select form from bench_runs')}
        bc.close()
        if sum(f['id'] not in used for f in benchmark.forms()) < 2:
            try:
                benchgen.main(['--forms', '2', '--max-calls', '4', '--partial'])
            except SystemExit:
                pass
        return
    if what in ('books', 'all'):
        log(c, 'books', *run_calls(job_books(c, 30)))
    if what in ('items', 'all'):
        log(c, 'items', *run_calls(job_items(c, {'gist': 24, 'argument': 24, 'subtext': 16, 'motjuste': 24, 'bloat': 24})))
    if what in ('validate', 'all'):
        log(c, 'validate', *run_calls(job_validate(c)))
        log(c, 'compare', *run_calls(job_compare(c)))


if __name__ == '__main__':
    main()
