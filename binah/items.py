"""Load playable items into the app database.

Two pools, kept apart from the moment an item exists:
  private  items built from your own books by the passage engine (STATE/engine/passages.db)
  public   original content in content/ (written for Binah, MIT) or public-domain text

Importing is an upsert: re-running it updates text and keys but keeps each item's
rating and play count. An item the engine marked "use" (and that the blind check
agreed with, where there was one) goes live; a "maybe" is kept as a draft.
"""
import json
import os
import re
import sqlite3

from . import config, db
from .games import stable_shuffle

UPSERT = """insert into items(id, game, skill, pool, license, source, payload, key, rating, status)
            values(?,?,?,?,?,?,?,?,?,?)
            on conflict(id) do update set payload=excluded.payload, key=excluded.key, source=excluded.source,
              license=excluded.license, status=case when items.status='retired' then 'retired' else excluded.status end"""


def _put(c, id, game, skill, pool, license, source, payload, key, rating, status):
    c.execute(UPSERT, (id, game, skill, pool, license, json.dumps(source, ensure_ascii=False),
                       json.dumps(payload, ensure_ascii=False), json.dumps(key, ensure_ascii=False) if key is not None else None,
                       float(rating), status))


def import_library(c):
    """Items from the passage engine's drafts (your own books, private pool)."""
    path = config.PASSAGES_DB
    if not os.path.exists(path):
        return {}
    e = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
    e.row_factory = sqlite3.Row
    has = lambda t: e.execute("select 1 from sqlite_master where name=?", (t,)).fetchone()
    if not has('drafts'):
        return {}
    checks = {}
    if has('validations'):
        for r in e.execute('select game, ref_id, agree from validations'):
            checks[(r['game'], r['ref_id'])] = r['agree']
    counts = {}
    lic = 'your own library (private)'

    def bump(game, status):
        counts[f'{game}:{status}'] = counts.get(f'{game}:{status}', 0) + 1

    for r in e.execute('select * from drafts'):
        d = json.loads(r['draft'])
        verdict = r['verdict']
        if verdict == 'reject':
            continue
        if r['game'] in ('gist', 'argument', 'subtext'):
            p = e.execute('select p.*, b.title, b.authors from passages p join books b on b.id=p.book_id where p.id=?',
                          (r['ref_id'],)).fetchone()
            if not p:
                continue
            src = {'book': p['title'], 'author': p['authors'], 'chapter': p['chapter_title'], 'passage': p['id'],
                   'highlighted': bool(p['highlighted'])}
            agree = checks.get((r['game'], r['ref_id']))
            live = verdict == 'use' and (r['game'] == 'subtext' or agree == 'yes')
            status = 'live' if live else 'draft'
            if r['game'] == 'gist':
                _put(c, f'gist:p{p["id"]}', 'gist', 'gist', 'private', lic, src,
                     {'passage': p['text'], 'inference_q': d['inference_q']},
                     {'gist': d['gist'], 'key_points': d['key_points'], 'inference_a': d['inference_a']},
                     p['start_rating'], status)
                bump('gist', status)
            elif r['game'] == 'argument':
                _put(c, f'weak:p{p["id"]}', 'weak', 'weak', 'private', lic, src, {'passage': p['text']},
                     {'quote': d['weakest_step_quote'], 'flaw': d['flaw'], 'explain': d['flaw_explain'],
                      'assumption': d['hidden_assumption'], 'conclusion': d['conclusion']},
                     p['start_rating'], status)
                bump('weak', status)
            else:
                _put(c, f'subtext:p{p["id"]}', 'subtext', 'inference', 'private', lic, src,
                     {'passage': p['text'], 'question': d['question']},
                     {'answer': d['answer'], 'evidence_quote': d['evidence_quote']},
                     p['start_rating'], status)
                bump('subtext', status)
        elif r['game'] in ('motjuste', 'bloat'):
            s = e.execute('select s.*, b.title, b.authors from sentences s join books b on b.id=s.book_id where s.id=?',
                          (r['ref_id'],)).fetchone()
            if not s:
                continue
            src = {'book': s['title'], 'author': s['authors'], 'sentence': s['id']}
            status = 'live' if verdict == 'use' else 'draft'
            if r['game'] == 'motjuste':
                target = d.get('target') or s['target']
                pat = re.compile(r'\b' + re.escape(target) + r'\b')
                if not pat.search(s['text']) or len(d.get('decoys') or []) < 3:
                    continue
                blanked = pat.sub('_____', s['text'], count=1)
                opts = stable_shuffle([target] + d['decoys'][:4], f'word:{s["id"]}')
                zipf = s['target_zipf'] or 3.2
                _put(c, f'word:s{s["id"]}', 'word', 'precision', 'private', lic, src,
                     {'sentence': blanked, 'options': opts},
                     {'target': target, 'why': d.get('why_target', ''), 'sentence': s['text']},
                     900 + 90 * (5 - min(5.0, zipf)), status)
                bump('word', status)
            else:
                _put(c, f'bloat:s{s["id"]}', 'bloat', 'concision', 'private', lic, src,
                     {'padded': d['bloated'], 'par': s['words']}, {'original': s['text']},
                     1150 + 4 * min(50, s['words']), status)
                bump('bloat', status)
    return counts


def import_content(c):
    """Original public content shipped in content/ (technique items, Just a Minute topics)."""
    counts = {}
    tp = config.CONTENT_DIR / 'technique.json'
    if tp.exists():
        data = json.loads(tp.read_text())
        for it in (data['items'] if isinstance(data, dict) else data):
            _put(c, f'tech:{it["id"]}', 'tech', 'discern', 'public', 'original (MIT)', {'set': 'technique'},
                 {'text': it['text'], 'context': it.get('context', '')},
                 {'kind': it['kind'], 'technique': it['technique'], 'tell': it.get('tell', ''), 'why': it.get('why', '')},
                 1200, 'live')
            counts['tech'] = counts.get('tech', 0) + 1
    jp = config.CONTENT_DIR / 'jam_topics.json'
    if jp.exists():
        data = json.loads(jp.read_text())
        for it in (data['items'] if isinstance(data, dict) else data):
            lvl = it.get('level', 'medium')
            _put(c, f'jam:{it["id"]}', 'jam', 'fluency', 'public', 'original (MIT)', {'set': 'jam topics'},
                 {'topic': it['topic'], 'level': lvl, 'kind': it.get('kind', '')}, None,
                 {'easy': 1100, 'medium': 1200, 'hard': 1320}.get(lvl, 1200), 'live')
            counts['jam'] = counts.get('jam', 0) + 1
    return counts


def import_all():
    c = db.connect()
    try:
        out = {'library': import_library(c), 'content': import_content(c)}
        c.commit()
        out['live'] = dict(c.execute("select game, count(*) from items where status='live' group by game").fetchall())
        return out
    finally:
        c.close()
