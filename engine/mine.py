"""Mine the Calibre library for Binah passages.

    .venv/bin/python engine/mine.py            # whole library
    .venv/bin/python engine/mine.py --limit 5  # quick test

Reads Calibre (and, if configured, Daf's highlights) read-only and never
writes to either. Output goes to STATE/engine/passages.db. It holds copyrighted
text from your own books, so it stays private: never in git, never served publicly.
"""
import argparse
import json
import os
import re
import sqlite3
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import epub  # noqa: E402
import features as F  # noqa: E402
from binah import config  # noqa: E402

_S = config.settings()
CALIBRE_DIR = _S['calibre_dir']
CALIBRE_DB = os.path.join(CALIBRE_DIR, 'metadata.db') if CALIBRE_DIR else ''
DAF_DB = _S['daf_db']
DAF_SETTINGS = _S['daf_settings']
OUT = str(config.PASSAGES_DB)

JUNK_RE = re.compile(r'(ISBN|All rights reserved|Copyright ©|Printed in|Library of Congress|www\.|http|@)', re.I)
NOTE_RE = re.compile(r'^\s*(\d{1,3}[.)]?\s|\[\d+\]|\*\s|†)')


def ro(path):
    return sqlite3.connect(f'file:{path}?mode=ro', uri=True)


def private_terms():
    """Books never mined: Daf's private_titles (if configured) plus settings.private_terms.
    Matched against title + tags, lower case."""
    try:
        daf = [t.lower() for t in json.load(open(DAF_SETTINGS)).get('private_titles', [])] if DAF_SETTINGS else []
    except Exception:
        daf = []
    return daf + [t.lower() for t in _S.get('private_terms', [])]


def library(limit=None, only=None):
    terms = private_terms()
    c = ro(CALIBRE_DB)
    rows = c.execute('''
        select b.id, b.title, b.path, d.name, substr(b.pubdate,1,4),
               (select group_concat(a.name, ' & ') from books_authors_link ba join authors a on a.id=ba.author where ba.book=b.id),
               (select group_concat(t.name, ', ') from books_tags_link bt join tags t on t.id=bt.tag where bt.book=b.id),
               (select group_concat(l.lang_code) from books_languages_link bl join languages l on l.id=bl.lang_code where bl.book=b.id)
        from books b join data d on d.book=b.id and d.format='EPUB' order by b.id''').fetchall()
    daf_private = set()
    try:
        for (cid,) in (ro(DAF_DB).execute('select calibre_id from books where private=1 and calibre_id is not null') if DAF_DB else []):
            daf_private.add(cid)
    except Exception:
        pass
    books, skipped = [], 0
    for bid, title, path, name, year, authors, tags, langs in rows:
        hay = f'{title} {tags or ""}'.lower()
        if bid in daf_private or any(t in hay for t in terms):
            skipped += 1
            continue
        if langs and 'eng' not in langs:
            continue
        if only and only.lower() not in title.lower():
            continue
        books.append({'id': bid, 'title': title, 'authors': authors or '', 'tags': tags or '',
                      'year': int(year) if year and year.isdigit() else None,
                      'file': os.path.join(CALIBRE_DIR, path, name + '.epub')})
    if limit:
        books = books[:limit]
    return books, skipped


def daf_highlights():
    """calibre_id -> list of normalised highlight snippets (only non-private books)."""
    out = {}
    if not DAF_DB:
        return out
    try:
        q = '''select b.calibre_id, h.text from highlights h join books b on b.id=h.book_id
               where b.calibre_id is not null and coalesce(b.private,0)=0 and coalesce(h.deleted,0)=0'''
        for cid, text in ro(DAF_DB).execute(q):
            n = norm(text or '')
            if len(n) >= 24:
                out.setdefault(cid, []).append(n[:60])
    except Exception:
        pass
    return out


def norm(s):
    return re.sub(r'[^a-z0-9]+', '', s.lower())


def clean_paras(paras):
    good = []
    for p in paras:
        w = len(F.WORD_RE.findall(p))
        if w < 4 or JUNK_RE.search(p) or NOTE_RE.match(p) or p.isupper():
            good.append(None)
        else:
            good.append(p)
    return good


def mine_book(book, hl):
    try:
        chaps = epub.chapters(book['file'])
    except Exception as e:
        return book, [], [], f'{type(e).__name__}: {e}'
    passages, sents = [], []
    for ci, (title, paras) in enumerate(chaps):
        paras = clean_paras(paras)
        counts = [len(F.WORD_RE.findall(p)) if p else 0 for p in paras]
        i = 0
        while i < len(paras):
            if not paras[i]:
                i += 1
                continue
            total, k = 0, 0
            while i + k < len(paras) and paras[i + k] and total < 110 and k < 4:
                total += counts[i + k]
                k += 1
            if 80 <= total <= 340:
                text = '\n\n'.join(paras[i:i + k])
                f = F.measure(text)
                n = norm(text)
                highlighted = any(h in n for h in hl)
                passages.append({'chapter': ci, 'chapter_title': title, 'para': i, 'n_paras': k, 'text': text,
                                 'f': f, 'fits': F.fits(f, highlighted), 'highlighted': highlighted})
            i += max(1, k // 2) if k > 1 else 1
            # sentence-level candidates from this paragraph
        for pi, p in enumerate(paras):
            if not p:
                continue
            for s in F.sentences(p):
                sf = F.sentence_fits(s)
                if sf and (sf.get('motjuste', 0) > 0.55 or sf['tight'] > 0.7):
                    sents.append({'chapter': ci, 'para': pi, 'text': s, 'fits': sf})
    return book, passages, sents, None


SCHEMA = '''
create table if not exists books(id integer primary key, title text, authors text, tags text, year int, file text,
  passages int, sentences int, highlights int, error text, profile text, mined_at text);
create table if not exists passages(id integer primary key autoincrement, book_id int, chapter int, chapter_title text,
  para int, n_paras int, text text, kind text, words int, difficulty real, start_rating int, highlighted int,
  fit_gist real, fit_argument real, fit_subtext real, fit_blueprint real, fit_listen real, features text);
create table if not exists sentences(id integer primary key autoincrement, book_id int, chapter int, para int, text text,
  words int, motjuste real, target text, target_zipf real, tight real);
create index if not exists p_book on passages(book_id);
'''


def profile(passages):
    if not passages:
        return {}
    kinds = {}
    for p in passages:
        kinds[p['f']['kind']] = kinds.get(p['f']['kind'], 0) + 1
    n = len(passages)
    avg = lambda key: round(sum(p['f'][key] for p in passages) / n, 2)
    best = {g: round(max(p['fits'][g] for p in passages), 3) for g in passages[0]['fits']}
    return {'kinds': {k: round(v / n, 3) for k, v in kinds.items()}, 'difficulty': avg('difficulty'),
            'fkgl': avg('fkgl'), 'rare': avg('rare'), 'dialogue': avg('dialogue'), 'arg_per100': avg('arg_per100'),
            'best': best}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--limit', type=int)
    ap.add_argument('--only')
    ap.add_argument('--workers', type=int, default=6)
    a = ap.parse_args()
    books, skipped = library(a.limit, a.only)
    hls = daf_highlights()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    if os.path.exists(OUT) and not a.only:
        os.remove(OUT)
    db = sqlite3.connect(OUT)
    db.executescript(SCHEMA)
    t0 = time.time()
    print(f'{len(books)} books to mine ({skipped} private skipped)', flush=True)
    done = 0
    with ProcessPoolExecutor(max_workers=a.workers) as ex:
        futs = [ex.submit(mine_book, b, hls.get(b['id'], [])) for b in books]
        for fut in as_completed(futs):
            book, passages, sents, err = fut.result()
            done += 1
            db.execute('delete from passages where book_id=?', (book['id'],))
            db.execute('delete from sentences where book_id=?', (book['id'],))
            for p in passages:
                f = p['f']
                db.execute('''insert into passages(book_id,chapter,chapter_title,para,n_paras,text,kind,words,difficulty,
                    start_rating,highlighted,fit_gist,fit_argument,fit_subtext,fit_blueprint,fit_listen,features)
                    values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
                           (book['id'], p['chapter'], p['chapter_title'], p['para'], p['n_paras'], p['text'], f['kind'],
                            f['words'], f['difficulty'], F.start_rating(f), int(p['highlighted']),
                            p['fits']['gist'], p['fits']['argument'], p['fits']['subtext'], p['fits']['blueprint'],
                            p['fits']['listen'], json.dumps(f)))
            for s in sents:
                sf = s['fits']
                db.execute('insert into sentences(book_id,chapter,para,text,words,motjuste,target,target_zipf,tight) values(?,?,?,?,?,?,?,?,?)',
                           (book['id'], s['chapter'], s['para'], s['text'], sf['words'], sf.get('motjuste'), sf.get('target'),
                            sf.get('target_zipf'), sf['tight']))
            db.execute('insert or replace into books values(?,?,?,?,?,?,?,?,?,?,?,datetime("now"))',
                       (book['id'], book['title'], book['authors'], book['tags'], book['year'], book['file'],
                        len(passages), len(sents), sum(p['highlighted'] for p in passages), err,
                        json.dumps(profile(passages))))
            db.commit()
            if done % 20 == 0 or done == len(books):
                print(f'  {done}/{len(books)} books, {time.time() - t0:.0f}s', flush=True)
    n_p = db.execute('select count(*) from passages').fetchone()[0]
    n_s = db.execute('select count(*) from sentences').fetchone()[0]
    errs = db.execute('select count(*) from books where error is not null').fetchone()[0]
    print(f'done: {n_p} passages, {n_s} sentences, {errs} books failed, {time.time() - t0:.0f}s')


if __name__ == '__main__':
    main()
