"""Hammer a running Binah (a sandbox, never the live one) for two races.

    python3 tools/check_races.py http://127.0.0.1:8471 STATE_DIR USER PASSWORD

1. The first load of a day: /api/today and /api/nav arrive together and both try to create
   the day's edition. It drops today's edition from STATE_DIR/binah.db and fires them at
   once, twenty times over.
2. Read after write: an answer is posted and read back at once, two hundred times. The
   read must never 404.
Exits non-zero if either race shows up.
"""
import http.cookiejar
import json
import sqlite3
import sys
import threading
import urllib.error
import urllib.request
from datetime import date

BASE, STATE, USER, PW = sys.argv[1].rstrip('/'), sys.argv[2], sys.argv[3], sys.argv[4]
if '8470' in BASE or 'binah.tiresia.xyz' in BASE:
    sys.exit('Point this at a sandbox, not the live app.')
jar = http.cookiejar.CookieJar()
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def call(path, body=None):
    req = urllib.request.Request(BASE + path, json.dumps(body).encode() if body is not None else None,
                                 {'Content-Type': 'application/json'} if body is not None else {})
    try:
        with op.open(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b'null')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]


call('/api/login', {'user': USER, 'password': PW})
bad = 0

# 1. first load of the day
fails = 0
for _ in range(20):
    db = sqlite3.connect(f'{STATE}/binah.db')
    db.execute('delete from editions where day >= ?', (date.fromordinal(date.today().toordinal() - 1).isoformat(),))
    db.commit()
    db.close()
    out = []
    ts = [threading.Thread(target=lambda p=p: out.append(call(p)[0])) for p in ('/api/today', '/api/nav', '/api/widget')]
    [t.start() for t in ts]
    [t.join() for t in ts]
    fails += sum(1 for s in out if s != 200)
print(f'first load of a day: {fails} failed requests out of 60')
bad += fails

# 2. read right after write
status, items = call('/api/practice/word')
item = items['items'][0] if status == 200 else None
misses = 0
if item:
    for _ in range(200):
        s, a = call('/api/attempts', {'item_id': item, 'answer': {'choice': 'x'}, 'self_rating': None, 'ms': 1})
        if s != 200:
            misses += 1
            continue
        s2, _ = call(f'/api/attempts/{a["id"]}')
        misses += s2 != 200
    print(f'read after write: {misses} misses out of 200')
else:
    print('read after write: skipped (no word items)')
bad += misses
sys.exit(1 if bad else 0)
