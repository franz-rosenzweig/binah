"""Binah's web API and static app.

Everything under /api needs the login cookie except /api/me and /api/login.
The order inside every open answer is fixed by the API, not just the screen:
answer (with a self-rating) -> verdict -> one revision -> reference. The hidden
key is never sent before the answer is in.
"""
import json
import logging
import re
import statistics
import subprocess
import time
import uuid
from datetime import datetime, timezone

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse

from . import auth, benchmark, config, db, edition, games, golden, grader, items, ratings

log = logging.getLogger(__name__)
app = FastAPI(title='Binah', docs_url=None, redoc_url=None, openapi_url=None)


@app.middleware('http')
async def headers(request: Request, call_next):
    resp = await call_next(request)
    path = request.url.path
    if path.startswith('/fonts/'):
        resp.headers['Cache-Control'] = 'public, max-age=2592000, immutable'
    elif path.startswith('/api/'):
        resp.headers['Cache-Control'] = 'private, no-cache'
    else:
        resp.headers['Cache-Control'] = 'private, no-cache'   # Cloudflare rewrites plain no-cache on .js
    resp.headers.setdefault('X-Content-Type-Options', 'nosniff')
    resp.headers.setdefault('Referrer-Policy', 'same-origin')
    resp.headers.setdefault('X-Frame-Options', 'SAMEORIGIN')
    resp.headers.setdefault('Permissions-Policy', 'microphone=(self)')
    return resp


# ── sign-in (the same design as Daf: scrypt, signed cookie, throttle, alert) ──

def _via_tunnel(request):
    host = request.client.host if request.client else ''
    return host in ('127.0.0.1', '::1') and bool(request.headers.get('cf-connecting-ip'))


def client_ip(request):
    return request.headers['cf-connecting-ip'] if _via_tunnel(request) else (request.client.host if request.client else '?')


def is_https(request):
    return _via_tunnel(request) and (request.headers.get('x-forwarded-proto') == 'https'
                                     or 'https' in request.headers.get('cf-visitor', ''))


_fails, _paused = {}, [0.0]
_last_alert = [0.0]


def _alert(text):
    cmd = config.settings().get('notify_cmd')
    if not cmd or time.time() - _last_alert[0] < 6 * 3600:
        return
    _last_alert[0] = time.time()
    try:
        subprocess.Popen([cmd, 'Binah', text], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        log.warning("couldn't send the sign-in alert")


def _throttled(ip):
    now = time.time()
    _fails[ip] = [t for t in _fails.get(ip, []) if now - t < 900]
    return now < _paused[0] or len(_fails[ip]) >= 5


def _failed(ip):
    now = time.time()
    _fails.setdefault(ip, []).append(now)
    everyone = sum(1 for ts in _fails.values() for t in ts if now - t < 3600)
    if len([t for t in _fails[ip] if now - t < 900]) == 5:
        _alert(f'Five wrong sign-ins to Binah from {ip}. That address waits 15 minutes.')
    if everyone >= 20 and now >= _paused[0]:
        _paused[0] = now + 900
        _alert(f'{everyone} wrong sign-ins to Binah in the last hour. Sign-in is paused for 15 minutes.')


def conn():
    c = db.connect()
    try:
        yield c
        c.commit()
    finally:
        c.close()


def user(request: Request):
    if auth.check_cookie(request.cookies.get(auth.COOKIE)):
        return
    h = request.headers.get('authorization', '')
    if h.lower().startswith('bearer '):
        c = db.connect()
        try:
            if auth.check_device(c, h[7:].strip()):
                c.commit()
                return
        finally:
            c.close()
    raise HTTPException(401, 'Sign in first')


async def body(request: Request):
    try:
        return await request.json()
    except ValueError:
        return {}


@app.get('/api/me')
def me(request: Request):
    signed = auth.check_cookie(request.cookies.get(auth.COOKIE))
    return {'signed_in': signed, 'has_password': auth.has_password(), **({'user': auth.username()} if signed else {})}


@app.post('/api/login')
async def login(request: Request):
    ip = client_ip(request)
    if _throttled(ip):
        raise HTTPException(429, 'Too many tries. Wait 15 minutes and try again.')
    b = await body(request)
    if not auth.check_login(str(b.get('user', '')), str(b.get('password', ''))):
        _failed(ip)
        raise HTTPException(401, "That username or password isn't right")
    _fails.pop(ip, None)
    r = JSONResponse({'ok': True})
    r.set_cookie(auth.COOKIE, auth.make_cookie(), max_age=auth.COOKIE_DAYS * 86400, httponly=True,
                 samesite='lax', secure=is_https(request))
    return r


@app.post('/api/logout')
def logout():
    r = JSONResponse({'ok': True})
    r.delete_cookie(auth.COOKIE)
    return r


@app.post('/api/account', dependencies=[Depends(user)])
async def account(request: Request):
    ip = client_ip(request)
    if _throttled(ip):
        raise HTTPException(429, 'Too many tries. Wait 15 minutes and try again.')
    b = await body(request)
    if not auth.check_password(str(b.get('current', ''))):
        _failed(ip)
        raise HTTPException(403, "Your current password isn't right")
    pw = str(b.get('password') or '')
    if len(pw) < 10:
        raise HTTPException(400, 'Make the new password at least 10 characters')
    auth.set_password(pw, rotate=True)
    r = JSONResponse({'ok': True})
    r.set_cookie(auth.COOKIE, auth.make_cookie(), max_age=auth.COOKIE_DAYS * 86400, httponly=True,
                 samesite='lax', secure=is_https(request))
    return r


# ── today ──

@app.get('/api/today', dependencies=[Depends(user)])
def today(c=Depends(conn)):
    return {'edition': edition.get_edition(c), 'week': edition.week(c), 'counts': edition.counts(c),
            'ratings': ratings.all_ratings(c), 'skills': games.SKILLS, 'games': games.GAMES}


@app.post('/api/today/recall', dependencies=[Depends(user)])
async def recall(request: Request, c=Depends(conn)):
    b = await body(request)
    if b.get('mark') not in ('yes', 'partly', 'no'):
        raise HTTPException(400, 'mark must be yes, partly or no')
    return edition.mark_recall(c, edition.home_today().isoformat(), str(b.get('answer', '')), b['mark'])


@app.get('/api/item/{item_id}', dependencies=[Depends(user)])
def get_item(item_id: str, c=Depends(conn)):
    it = c.execute("select * from items where id=? and status != 'retired'", (item_id,)).fetchone()
    if not it:
        raise HTTPException(404, 'No such item')
    return games.public_payload(it)


# ── attempts: answer -> verdict -> one revision -> reference ──

def _attempt_out(c, a):
    item = c.execute('select * from items where id=?', (a['item_id'],)).fetchone()
    out = {'id': a['id'], 'item_id': a['item_id'], 'game': a['game'], 'status': a['status'],
           'self_rating': a['self_rating'], 'answer': db.j(a['answer']), 'instant': db.j(a['instant']),
           'grade': db.j(a['grade']), 'revision': db.j(a['revision']), 'grade2': db.j(a['grade2']),
           'score': a['score'], 'score2': a['score2'],
           'rating_before': round(a['rating_before']) if a['rating_before'] is not None else None,
           'rating_after': round(a['rating_after']) if a['rating_after'] is not None else None,
           'skill': item['skill'] if item else None,
           'revising': bool(a['revision']) and a['grade2'] is None, 'disputed': a['disputed']}
    instant_game = games.GAMES.get(a['game'], {}).get('lane') == 'instant'
    if item and (instant_game or a['grade2'] or db.kv_get(c, f'revealed:{a["id"]}')):
        out['key'] = games.reveal(item)
    if out['answer'] and 'audio' in out['answer']:
        out['answer'].pop('audio', None)
    return out


@app.post('/api/attempts', dependencies=[Depends(user)])
async def new_attempt(request: Request, c=Depends(conn)):
    b = await body(request)
    item = c.execute("select * from items where id=? and status != 'retired'", (b.get('item_id'),)).fetchone()
    if not item:
        raise HTTPException(404, 'No such item')
    answer = b.get('answer') or {}
    if item['game'] == 'gist' and games.words(answer.get('gist', '')) > 20:
        raise HTTPException(400, 'Keep the gist to 20 words')
    inst = games.instant(item, answer)
    day = b.get('day') or None
    self_rating = b.get('self_rating')
    self_rating = int(self_rating) if isinstance(self_rating, (int, float)) and 0 <= self_rating <= 4 else None
    lane = games.GAMES[item['game']]['lane']
    cur = c.execute('insert into attempts(item_id, game, day, slot, ms, answer, self_rating, instant, status) '
                    'values(?,?,?,?,?,?,?,?,?)',
                    (item['id'], item['game'], day, b.get('slot'), b.get('ms'), json.dumps(answer, ensure_ascii=False),
                     self_rating, json.dumps(inst), 'grading' if lane == 'graded' else 'done'))
    aid = cur.lastrowid
    if lane == 'instant':
        score = games.final_score(item, inst, None)
        before, after, item_before = ratings.update(c, item['skill'], item['id'], score)
        c.execute('update attempts set score=?, rating_before=?, rating_after=?, item_before=? where id=?',
                  (score, before, after, item_before, aid))
        if games.grade_request(item, answer):        # e.g. a one-line reason on Find the Weak Step
            grader.enqueue(c, 'grade', aid)
    else:
        grader.enqueue(c, 'grade', aid)
    return _attempt_out(c, c.execute('select * from attempts where id=?', (aid,)).fetchone())


@app.get('/api/attempts/{aid}', dependencies=[Depends(user)])
def get_attempt(aid: int, c=Depends(conn)):
    a = c.execute('select * from attempts where id=?', (aid,)).fetchone()
    if not a:
        raise HTTPException(404, 'No such answer')
    return _attempt_out(c, a)


@app.post('/api/attempts/{aid}/revise', dependencies=[Depends(user)])
async def revise(aid: int, request: Request, c=Depends(conn)):
    a = c.execute('select * from attempts where id=?', (aid,)).fetchone()
    if not a or a['status'] != 'done' or a['revision']:
        raise HTTPException(400, 'One revision, after the verdict')
    b = await body(request)
    ans = b.get('answer') or {}
    if a['game'] == 'gist' and games.words(ans.get('gist', '')) > 20:
        raise HTTPException(400, 'Keep the gist to 20 words')
    c.execute('update attempts set revision=? where id=?', (json.dumps(ans, ensure_ascii=False), aid))
    grader.enqueue(c, 'revise', aid)
    return _attempt_out(c, c.execute('select * from attempts where id=?', (aid,)).fetchone())


@app.post('/api/attempts/{aid}/reveal', dependencies=[Depends(user)])
def reveal(aid: int, c=Depends(conn)):
    a = c.execute('select * from attempts where id=?', (aid,)).fetchone()
    if not a or a['status'] not in ('done', 'later'):
        raise HTTPException(400, 'Answer first')
    db.kv_set(c, f'revealed:{aid}', True)
    return _attempt_out(c, a)


@app.post('/api/attempts/{aid}/dispute', dependencies=[Depends(user)])
async def dispute(aid: int, request: Request, c=Depends(conn)):
    b = await body(request)
    c.execute('update attempts set disputed=? where id=?', (str(b.get('note') or 'disputed')[:500], aid))
    return {'ok': True}


@app.post('/api/audio', dependencies=[Depends(user)])
async def audio(item_id: str = Form(...), day: str = Form(''), slot: int = Form(-1), ms: int = Form(0),
                file: UploadFile = File(...), c=Depends(conn)):
    item = c.execute("select * from items where id=? and game='jam'", (item_id,)).fetchone()
    if not item:
        raise HTTPException(404, 'No such topic')
    data = await file.read()
    if len(data) < 1000:
        raise HTTPException(400, "That recording is empty. Check the microphone and try again.")
    if len(data) > 15 * 1024 * 1024:
        raise HTTPException(400, 'That recording is too long')
    ext = 'mp4' if 'mp4' in (file.content_type or '') else 'ogg' if 'ogg' in (file.content_type or '') else 'webm'
    config.AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    path = config.AUDIO_DIR / f'{uuid.uuid4().hex}.{ext}'
    path.write_bytes(data)
    cur = c.execute("insert into attempts(item_id, game, day, slot, ms, answer, status) values(?,?,?,?,?,?, 'grading')",
                    (item_id, 'jam', day or None, slot if slot >= 0 else None, ms,
                     json.dumps({'audio': str(path), 'mime': file.content_type})))
    grader.enqueue(c, 'jam', cur.lastrowid)
    return _attempt_out(c, c.execute('select * from attempts where id=?', (cur.lastrowid,)).fetchone())


# ── practice, skills ──

@app.get('/api/practice', dependencies=[Depends(user)])
def practice(c=Depends(conn)):
    live = dict(c.execute("select game, count(*) from items where status='live' group by game").fetchall())
    return [{'game': g, **meta, 'live': live.get(g, 0)} for g, meta in games.GAMES.items()]


@app.get('/api/practice/{game}', dependencies=[Depends(user)])
def practice_next(game: str, c=Depends(conn)):
    if game not in games.GAMES:
        raise HTTPException(404, 'No such game')
    if game == 'tech':
        played = {r['item_id'] for r in c.execute("select item_id from attempts where game='tech' order by id desc limit 60")}
        ids = edition._tech_round(c, played)
        return {'items': ids}
    item = ratings.pick(c, game, games.GAMES[game]['skill'])
    if not item:
        raise HTTPException(404, 'Nothing left to play in this game yet')
    return {'items': [item]}


def _dprime(c):
    rows = c.execute("select a.answer, i.key from attempts a join items i on i.id=a.item_id where a.game='tech'").fetchall()
    h = f = nt = nf = 0
    briers = []
    for r in rows:
        ans, key = json.loads(r['answer'] or '{}'), json.loads(r['key'] or '{}')
        said = ans.get('kind') == 'technique'
        if key.get('kind') == 'technique':
            nt += 1
            h += said
        else:
            nf += 1
            f += said
        conf = ans.get('confidence')
        if isinstance(conf, (int, float)) and 50 <= conf <= 100:
            right = (ans.get('kind') == key.get('kind'))
            briers.append((1 - conf / 100) ** 2 if right else (conf / 100) ** 2)
    if nt < 3 or nf < 3:
        return {'n': nt + nf}
    z = statistics.NormalDist().inv_cdf
    H, F = (h + 0.5) / (nt + 1), (f + 0.5) / (nf + 1)
    return {'n': nt + nf, 'dprime': round(z(H) - z(F), 2), 'bias': round(-(z(H) + z(F)) / 2, 2),
            'hit_rate': round(h / nt, 2), 'false_alarms': round(f / nf, 2),
            'brier': round(sum(briers) / len(briers), 3) if briers else None}


@app.get('/api/skills', dependencies=[Depends(user)])
def skills(c=Depends(conn)):
    hist = {}
    for r in c.execute("select a.created, a.score, i.skill from attempts a join items i on i.id=a.item_id "
                       "where a.score is not null order by a.id desc limit 400"):
        hist.setdefault(r['skill'], []).append(round(r['score'], 2))
    gap = [abs(r['self_rating'] - round(4 * r['score'])) for r in c.execute(
        "select self_rating, score from attempts where self_rating is not null and score is not null order by id desc limit 50")]
    return {'ratings': ratings.all_ratings(c), 'skills': games.SKILLS, 'recent': {k: v[:20][::-1] for k, v in hist.items()},
            'discern': _dprime(c), 'self_gap': round(sum(gap) / len(gap), 2) if gap else None,
            'counts': edition.counts(c), 'week': edition.week(c), 'bench_due': _bench_due(c)}


def _bench_due(c):
    """A sitting is due when an unused form exists and the last one was 28 or more days ago."""
    used = {r['form'] for r in c.execute('select form from bench_runs')}
    if not any(f['id'] not in used for f in benchmark.forms()):
        return False
    last = c.execute("select max(finished) from bench_runs where finished is not null").fetchone()[0]
    if not last:
        return True
    return (datetime.now(timezone.utc) - datetime.fromisoformat(last)).days >= 28


# ── golden set ──

@app.get('/api/golden', dependencies=[Depends(user)])
def golden_status(c=Depends(conn)):
    done = {r['item_id'] for r in c.execute('select item_id from golden')}
    nxt = []
    for g in golden.GOLDEN_GAMES:
        for r in c.execute("select id from items where game=? and status in ('live','draft') order by random()", (g,)):
            if r['id'] not in done:
                nxt.append(r['id'])
                break
    disputed = [_attempt_out(c, a) for a in c.execute(
        'select * from attempts where disputed is not null order by id desc limit 10')]
    return {'report': golden.report(c), 'next': nxt, 'rubrics': games.RUBRICS, 'disputed': disputed}


@app.get('/api/golden/key/{item_id}', dependencies=[Depends(user)])
def golden_key(item_id: str, c=Depends(conn)):
    """The key, for scoring your own golden answer. Golden items never appear in editions."""
    item = c.execute('select * from items where id=?', (item_id,)).fetchone()
    if not item or item['game'] not in golden.GOLDEN_GAMES:
        raise HTTPException(404, 'Not a golden-set item')
    return {'key': games.reveal(item), 'payload': games.public_payload(item)}


@app.post('/api/golden', dependencies=[Depends(user)])
async def golden_add(request: Request, c=Depends(conn)):
    b = await body(request)
    item = c.execute('select * from items where id=?', (b.get('item_id'),)).fetchone()
    if not item or item['game'] not in golden.GOLDEN_GAMES:
        raise HTTPException(400, 'That item is not in a golden-set game')
    gid = golden.add(c, item['id'], item['game'], b.get('answer') or {}, b.get('mine') or {})
    grader.enqueue(c, 'golden', gid)
    return {'ok': True, 'id': gid, 'key': games.reveal(item)}


# ── devices, widget, "train on this" (docs/SHELL.md) ──

@app.post('/api/devices')
async def add_device(request: Request, c=Depends(conn)):
    """A shell's "Connect this device": needs the browser cookie, answers a bearer token once."""
    if not auth.check_cookie(request.cookies.get(auth.COOKIE)):
        raise HTTPException(401, 'Sign in first')
    b = await body(request)
    name = re.sub(r'[^a-zA-Z0-9 ._-]', '', str(b.get('name') or 'device'))[:40] or 'device'
    c.execute('delete from devices where name=?', (name,))
    return {'name': name, 'token': auth.new_device_token(c, name)}


@app.get('/api/devices', dependencies=[Depends(user)])
def list_devices(c=Depends(conn)):
    return [dict(r) for r in c.execute('select name, created, last_seen from devices order by created')]


@app.delete('/api/devices/{name}', dependencies=[Depends(user)])
def drop_device(name: str, c=Depends(conn)):
    c.execute('delete from devices where name=?', (name,))
    return {'ok': True}


@app.get('/api/widget', dependencies=[Depends(user)])
def widget(c=Depends(conn)):
    """What a home-screen widget or the Mac's menu bar shows: today's edition at a glance."""
    ed = edition.get_edition(c)
    nxt = next((s for s in ed['slots'] if not s['done']), None)
    wk = edition.week(c)
    base = (config.settings().get('public_url') or '').rstrip('/')
    return {'day': ed['day'], 'done': sum(1 for s in ed['slots'] if s['done']), 'total': len(ed['slots']),
            'finished': ed['finished'], 'minutes_left': sum(s['minutes'] for s in ed['slots'] if not s['done']),
            'next': {'game': nxt['game'], 'name': nxt['name']} if nxt else None,
            'week': {'active': wk['active'], 'goal': wk['goal']},
            'url': f'{base}/#today' if base else '/#today', 'deeplink': 'binah://go/today'}


@app.get('/api/nav', dependencies=[Depends(user)])
def nav(c=Depends(conn)):
    """The counts beside the sidebar's sections: today's edition, the golden set, the benchmark, the week."""
    ed = edition.get_edition(c)
    wk = edition.week(c)
    g = c.execute('select count(*) from golden where mine is not null').fetchone()[0]
    return {'today': {'done': sum(1 for s in ed['slots'] if s['done']), 'total': len(ed['slots'])},
            'golden': {'n': g, 'target': golden.TARGET}, 'bench_due': _bench_due(c),
            'week': {'active': wk['active'], 'goal': wk['goal']}, 'rest_weekday': config.settings().get('rest_weekday')}


@app.post('/api/save', dependencies=[Depends(user)])
async def save(request: Request, c=Depends(conn)):
    """Train on this: a link or a passage sent from the share sheet. It waits for the next
    nightly item run, which turns a good passage into items (private pool)."""
    b = await body(request)
    url, text, title = str(b.get('url') or '')[:2000], str(b.get('text') or '')[:20000], str(b.get('title') or '')[:300]
    if not url and len(text.split()) < 20:
        raise HTTPException(400, 'Send a link, or at least a paragraph of text')
    cur = c.execute('insert into saved(url, title, text) values(?,?,?)', (url or None, title or None, text or None))
    return {'ok': True, 'id': cur.lastrowid, 'open': 'today',
            'message': 'Saved. It becomes practice items in the next nightly run.'}


# ── the monthly benchmark (sealed forms, separate track) ──

@app.get('/api/benchmark', dependencies=[Depends(user)])
def bench_status(c=Depends(conn)):
    return {'forms': benchmark.forms(), 'runs': benchmark.runs(c)}


@app.post('/api/benchmark/start', dependencies=[Depends(user)])
async def bench_start(request: Request, c=Depends(conn)):
    open_run = c.execute('select * from bench_runs where finished is null order by id desc limit 1').fetchone()
    if open_run:
        return {'run': open_run['id'], 'form': benchmark.strip(benchmark.load(open_run['form'])),
                'answers': db.j(open_run['answers']) or {}}
    taken = {r['form'] for r in c.execute('select form from bench_runs')}
    avail = [f['id'] for f in benchmark.forms()]
    nxt = next((f for f in avail if f not in taken), None)
    if not nxt:
        raise HTTPException(404, 'No unused benchmark forms left. Write more with python -m binah.benchgen.'
                            if avail else 'No benchmark forms yet. Write some with python -m binah.benchgen.')
    cur = c.execute('insert into bench_runs(form, answers) values(?, ?)', (nxt, '{}'))
    return {'run': cur.lastrowid, 'form': benchmark.strip(benchmark.load(nxt)), 'answers': {}}


@app.get('/api/benchmark/{run_id}', dependencies=[Depends(user)])
def bench_review(run_id: int, c=Depends(conn)):
    """A finished sitting with its key, so I can see what I missed. A form is never sat twice."""
    r = c.execute('select * from bench_runs where id=?', (run_id,)).fetchone()
    if not r:
        raise HTTPException(404, 'No such sitting')
    if not r['finished']:
        raise HTTPException(400, 'Finish the sitting first')
    form = benchmark.load(r['form'])
    for s in form['sections']:
        s.pop('rubric', None)
    ans = db.j(r['answers']) or {}
    if isinstance(ans.get('talk'), dict):
        ans['talk'] = {k: v for k, v in ans['talk'].items() if k != 'audio'}
    return {'run': run_id, 'form': form, 'answers': ans, 'results': db.j(r['results']),
            'started': r['started'], 'finished': r['finished']}


@app.post('/api/benchmark/{run_id}/answer', dependencies=[Depends(user)])
async def bench_answer(run_id: int, request: Request, c=Depends(conn)):
    b = await body(request)
    if not benchmark.save_answer(c, run_id, str(b.get('key', ''))[:80], b.get('value')):
        raise HTTPException(400, 'That sitting is closed')
    return {'ok': True}


@app.post('/api/benchmark/{run_id}/talk', dependencies=[Depends(user)])
async def bench_talk(run_id: int, file: UploadFile = File(...), c=Depends(conn)):
    data = await file.read()
    if len(data) < 1000:
        raise HTTPException(400, 'That recording is empty')
    config.AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    ext = 'mp4' if 'mp4' in (file.content_type or '') else 'webm'
    path = config.AUDIO_DIR / f'bench-{run_id}-{uuid.uuid4().hex[:8]}.{ext}'
    path.write_bytes(data)
    benchmark.save_answer(c, run_id, 'talk', {'audio': str(path)})
    return {'ok': True}


@app.post('/api/benchmark/{run_id}/finish', dependencies=[Depends(user)])
def bench_finish(run_id: int, c=Depends(conn)):
    r = c.execute('select * from bench_runs where id=?', (run_id,)).fetchone()
    if not r or r['finished']:
        raise HTTPException(400, 'That sitting is closed')
    res = benchmark.finish(c, run_id)
    ans = db.j(r['answers']) or {}
    if (ans.get('essay') or {}).get('text'):
        grader.enqueue(c, 'bench_essay', run_id)
    if (ans.get('talk') or {}).get('audio'):
        grader.enqueue(c, 'bench_talk', run_id)
    return {'run': run_id, 'results': res}


# ── settings ──

EDITABLE = {'weekly_goal_days', 'rest_weekday', 'grading_tone'}


@app.get('/api/settings', dependencies=[Depends(user)])
def get_settings():
    s = config.settings()
    return {k: s.get(k) for k in EDITABLE}


@app.post('/api/settings', dependencies=[Depends(user)])
async def set_settings(request: Request):
    b = await body(request)
    ch = {}
    if 'weekly_goal_days' in b and isinstance(b['weekly_goal_days'], int) and 1 <= b['weekly_goal_days'] <= 7:
        ch['weekly_goal_days'] = b['weekly_goal_days']
    if 'rest_weekday' in b and (b['rest_weekday'] is None or (isinstance(b['rest_weekday'], int) and 0 <= b['rest_weekday'] <= 6)):
        ch['rest_weekday'] = b['rest_weekday']
    if b.get('grading_tone') in games.TONES:
        ch['grading_tone'] = b['grading_tone']
    s = config.save_settings(ch)
    return {k: s.get(k) for k in EDITABLE}


# ── static app ──

STATIC = re.compile(r'^[a-z0-9._/-]+$')


@app.get('/')
def index():
    return HTMLResponse((config.WEB_DIR / 'index.html').read_text())


@app.get('/{path:path}')
def static(path: str):
    if not STATIC.match(path) or '..' in path:
        raise HTTPException(404)
    p = (config.WEB_DIR / path).resolve()
    if not str(p).startswith(str(config.WEB_DIR.resolve())) or not p.is_file():
        if '.' not in path.rsplit('/', 1)[-1]:
            return HTMLResponse((config.WEB_DIR / 'index.html').read_text())
        raise HTTPException(404)
    types = {'.js': 'text/javascript', '.css': 'text/css', '.webmanifest': 'application/manifest+json',
             '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.png': 'image/png'}
    return FileResponse(p, media_type=types.get(p.suffix))


def startup():
    out = items.import_all()
    log.info('items: %s', out.get('live'))
    grader.start()
