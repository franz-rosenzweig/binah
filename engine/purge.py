"""Remove every trace of private books from data/passages.db.

    .venv/bin/python engine/purge.py          # apply mine.private_terms() to what's already mined

Used when the private list grows after a run: deletes the books' passages,
sentences, drafts, blind checks and book cards.
"""
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mine import OUT, private_terms  # noqa: E402


def main():
    terms = private_terms()
    c = sqlite3.connect(OUT)
    gone = []
    for bid, title, tags in c.execute('select id, title, tags from books').fetchall():
        hay = f'{title} {tags or ""}'.lower()
        if any(t in hay for t in terms):
            gone.append((bid, title))
    for bid, title in gone:
        pids = [r[0] for r in c.execute('select id from passages where book_id=?', (bid,))]
        sids = [r[0] for r in c.execute('select id from sentences where book_id=?', (bid,))]
        for table in ('drafts', 'validations'):
            if c.execute("select 1 from sqlite_master where name=?", (table,)).fetchone():
                for g in ('gist', 'argument', 'subtext'):
                    c.executemany(f'delete from {table} where game=? and ref_id=?', [(g, p) for p in pids])
                for g in ('motjuste', 'bloat'):
                    c.executemany(f'delete from {table} where game=? and ref_id=?', [(g, s) for s in sids])
        if c.execute("select 1 from sqlite_master where name='book_cards'").fetchone():
            c.execute('delete from book_cards where book_id=?', (bid,))
        c.execute('delete from passages where book_id=?', (bid,))
        c.execute('delete from sentences where book_id=?', (bid,))
        c.execute('delete from books where id=?', (bid,))
        print(f'removed {bid}: {title[:70]} ({len(pids)} passages, {len(sids)} sentences)')
    c.commit()
    c.execute('vacuum')
    print(f'{len(gone)} books removed')


if __name__ == '__main__':
    main()
