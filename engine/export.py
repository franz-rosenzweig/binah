"""Export the engine's results as one JSON file for the explorer page.

    .venv/bin/python engine/export.py > STATE/engine/explorer.json

Private: the output holds excerpts from your own books. It feeds a private
page only; never commit it or serve it publicly.
"""
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from binah import config  # noqa: E402

DB = str(config.PASSAGES_DB)
GAMES = ['gist', 'argument', 'subtext', 'blueprint', 'listen']
KEEP_F = ['words', 'sentences', 'avg_sent', 'fkgl', 'zipf_mean', 'rare', 'dialogue', 'arg_per100', 'abstract',
          'pronoun_open', 'conj_open', 'refers_back', 'kind', 'difficulty', 'conn']


def main():
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    has = lambda t: c.execute("select 1 from sqlite_master where name=?", (t,)).fetchone()
    drafts = {}
    if has('drafts'):
        for r in c.execute('select * from drafts'):
            drafts[(r['game'], r['ref_id'])] = json.loads(r['draft'])
    vals = {}
    if has('validations'):
        for r in c.execute('select * from validations'):
            vals[(r['game'], r['ref_id'])] = {'agree': r['agree'], 'blind': json.loads(r['blind'] or 'null'),
                                              'detail': json.loads(r['detail'] or 'null')}
    cards = {}
    if has('book_cards'):
        for r in c.execute('select * from book_cards'):
            cards[r['book_id']] = {'card': json.loads(r['card']), 'picks': json.loads(r['picks'])}

    books = []
    for r in c.execute('select * from books where passages > 0 order by title'):
        p = json.loads(r['profile'] or '{}')
        books.append({'id': r['id'], 'title': r['title'], 'authors': r['authors'], 'year': r['year'],
                      'tags': (r['tags'] or '')[:160], 'passages': r['passages'], 'sentences': r['sentences'],
                      'highlights': r['highlights'], 'profile': p, **cards.get(r['id'], {})})

    wanted = set()
    for g in GAMES:
        for (pid,) in c.execute(f'select id from passages order by fit_{g} desc, highlighted desc limit 60'):
            wanted.add(pid)
    for (g, pid) in drafts:
        if g in ('gist', 'argument', 'subtext'):
            wanted.add(pid)
    for b in cards.values():
        for k in b['picks']:
            if k.get('passage_id'):
                wanted.add(k['passage_id'])
    for (pid,) in c.execute('select id from passages where highlighted=1 order by fit_gist desc limit 40'):
        wanted.add(pid)

    passages = []
    for pid in sorted(wanted):
        r = c.execute('select * from passages where id=?', (pid,)).fetchone()
        f = json.loads(r['features'])
        passages.append({
            'id': r['id'], 'book': r['book_id'], 'chapter': r['chapter_title'], 'text': r['text'],
            'rating': r['start_rating'], 'highlighted': bool(r['highlighted']),
            'fits': {g: r['fit_' + g] for g in GAMES}, 'f': {k: f[k] for k in KEEP_F},
            'items': {g: drafts[(g, pid)] for g in ('gist', 'argument', 'subtext') if (g, pid) in drafts},
            'checks': {g: vals[(g, pid)] for g in ('gist', 'argument') if (g, pid) in vals},
        })
    sentences = []
    ids = {pid for (g, pid) in drafts if g in ('motjuste', 'bloat')}
    for sid in sorted(ids):
        r = c.execute('select * from sentences where id=?', (sid,)).fetchone()
        if not r:
            continue
        sentences.append({'id': r['id'], 'book': r['book_id'], 'text': r['text'], 'words': r['words'],
                          'target': r['target'], 'target_zipf': r['target_zipf'],
                          'items': {g: drafts[(g, sid)] for g in ('motjuste', 'bloat') if (g, sid) in drafts}})
    stats = {
        'books': c.execute('select count(*) from books').fetchone()[0],
        'passages': c.execute('select count(*) from passages').fetchone()[0],
        'sentences': c.execute('select count(*) from sentences').fetchone()[0],
        'kinds': dict(c.execute('select kind, count(*) from passages group by kind').fetchall()),
        'highlighted': c.execute('select count(*) from passages where highlighted=1').fetchone()[0],
        'difficulty_hist': [c.execute('select count(*) from passages where difficulty>=? and difficulty<?', (lo, lo + 10)).fetchone()[0]
                            for lo in range(0, 100, 10)],
        'runs': [dict(r) for r in c.execute('select * from runs')] if has('runs') else [],
        'drafts': dict(c.execute('select game||":"||coalesce(verdict,"?"), count(*) from drafts group by 1').fetchall()) if has('drafts') else {},
        'agree': dict(c.execute('select game||":"||coalesce(agree,"?"), count(*) from validations group by 1').fetchall()) if has('validations') else {},
    }
    json.dump({'stats': stats, 'books': books, 'passages': passages, 'sentences': sentences}, sys.stdout,
              ensure_ascii=False, separators=(',', ':'))


if __name__ == '__main__':
    main()
