"""The grading queue: answers that need Claude wait here, and a background thread works them.

Each job calls claude_cli.ask (the subscription CLI, tools off). A daily cap keeps
a bug, or a friend, from eating the subscription: past the cap, jobs wait until
tomorrow and the answer shows "grading later" instead of a made-up score.
"""
import json
import logging
import threading
import time
import traceback

from . import benchmark, claude_cli, config, db, exporter, games, golden, ratings

log = logging.getLogger(__name__)
SYSTEM = ("You are the grader for Binah, a private reading, reasoning and writing trainer. You grade one answer "
          "against a hidden key and a written rubric. Reply only by filling in the required JSON structure.")
_wake = threading.Event()


def wake():
    _wake.set()


def enqueue(c, kind, ref):
    c.execute('insert into jobs(kind, ref) values(?, ?)', (kind, ref))
    wake()


def _used_today(c):
    return c.execute("select count(*) from jobs where status='done' and date(done)=date('now')").fetchone()[0]


def _claim(c):
    cap = int(config.settings().get('daily_grading_cap') or 60)
    if _used_today(c) >= cap:
        c.execute("update jobs set status='later' where status='queued'")
        return None
    c.execute("update jobs set status='queued' where status='later' and date(created) < date('now')")
    row = c.execute("select * from jobs where status='queued' order by id limit 1").fetchone()
    if not row:
        return None
    n = c.execute("update jobs set status='running', tries=tries+1 where id=? and status='queued'", (row['id'],)).rowcount
    return row if n else None


def _ask(req):
    prompt, schema, kind = req
    return claude_cli.ask(prompt, schema, SYSTEM, model=config.model(kind))


def _do_grade(c, job, revise=False):
    a = c.execute('select * from attempts where id=?', (job['ref'],)).fetchone()
    item = c.execute('select * from items where id=?', (a['item_id'],)).fetchone()
    answer = json.loads(a['revision'] if revise else a['answer'])
    inst = json.loads(a['instant'] or '{}')
    req = games.grade_request(item, answer, anchors=golden.anchors(c, item['game']),
                              revision_of=json.loads(a['answer']) if revise else None)
    out, meta = _ask(req)
    if revise:
        c.execute("update attempts set grade2=?, score2=?, model=? where id=?",
                  (json.dumps(out), games.final_score(item, inst, out), meta['model'], a['id']))
        return
    if games.GAMES[item['game']]['lane'] == 'instant':
        # Code already scored it and moved the rating; Claude only adds feedback (e.g. on a reason).
        c.execute("update attempts set grade=?, model=? where id=?", (json.dumps(out), meta['model'], a['id']))
        return
    score = games.final_score(item, inst, out)
    before, after, item_before = ratings.update(c, item['skill'], item['id'], score)
    c.execute("update attempts set grade=?, score=?, rating_before=?, rating_after=?, item_before=?, status='done', model=? "
              "where id=?", (json.dumps(out), score, before, after, item_before, meta['model'], a['id']))
    exporter.attempt(c, a['id'])


def _do_jam(c, job):
    from . import speech
    a = c.execute('select * from attempts where id=?', (job['ref'],)).fetchone()
    item = c.execute('select * from items where id=?', (a['item_id'],)).fetchone()
    ans = json.loads(a['answer'])
    topic = json.loads(item['payload']).get('topic', '')
    t = speech.transcribe(ans['audio'], topic=topic)
    inst = {'metrics': t['metrics'], 'duration': t['duration'], 'model': t['model'], 'seconds': t['seconds'],
            'verbatim_used': t['verbatim_used']}
    inst.update(games.jam_code_scores(inst))
    ans.update({'text': t['text'], 'text_verbatim': t['text_verbatim'], 'metrics': t['metrics']})
    c.execute('update attempts set answer=?, instant=? where id=?', (json.dumps(ans), json.dumps(inst), a['id']))
    c.commit()
    if not t['text'].strip():
        c.execute("update attempts set status='done', score=0, grade=? where id=?",
                  (json.dumps({'evidence': 'No speech was heard.', 'strength': '', 'work_on': 'Try again, a little closer to the microphone.'}), a['id']))
        return
    _do_grade(c, job)


def _do_golden(c, job):
    g = c.execute('select * from golden where id=?', (job['ref'],)).fetchone()
    item = c.execute('select * from items where id=?', (g['item_id'],)).fetchone()
    req = games.grade_request(item, json.loads(g['answer']), anchors=None)   # blind: no anchors
    out, meta = _ask(req)
    crit = list(games.RUBRICS[item['game']]['criteria'])
    c.execute('update golden set claude=?, model=? where id=?',
              (json.dumps({k: games.clamp4(out.get(k)) for k in crit}), meta['model'], g['id']))


def _bench_set(c, run_id, section, grade):
    r = c.execute('select results from bench_runs where id=?', (run_id,)).fetchone()
    res = db.j(r['results']) or {}
    res.setdefault(section, {})['grade'] = grade
    c.execute('update bench_runs set results=? where id=?', (json.dumps(res), run_id))


def _do_bench_essay(c, job):
    """Open lane: graded twice and averaged, with a frozen rubric."""
    prompt, schema = benchmark.essay_request(job['ref'], c)
    a, meta = claude_cli.ask(prompt, schema, SYSTEM, model=config.model('main'))
    b, _ = claude_cli.ask(prompt + '\n\n(Independent second reading.)', schema, SYSTEM, model=config.model('main'))
    crit = ('structure', 'accuracy', 'understanding')
    grade = {k: round((games.clamp4(a.get(k)) + games.clamp4(b.get(k))) / 2, 1) for k in crit}
    grade.update({'strength': a.get('strength', ''), 'work_on': a.get('work_on', ''), 'model': meta['model'],
                  'spread': max(abs(games.clamp4(a.get(k)) - games.clamp4(b.get(k))) for k in crit)})
    _bench_set(c, job['ref'], 'essay', grade)


def _do_bench_talk(c, job):
    from . import speech
    r = c.execute('select * from bench_runs where id=?', (job['ref'],)).fetchone()
    form = benchmark.load(r['form'])
    sec = next(s for s in form['sections'] if s['kind'] == 'talk')
    talk = (db.j(r['answers']) or {}).get('talk') or {}
    t = speech.transcribe(talk['audio'], topic=sec['prompt'])
    inst = {'metrics': t['metrics']}
    inst.update(games.jam_code_scores(inst))
    prompt = (f'Grade a two-minute impromptu spoken answer from a reasoning benchmark. Judge DEVIATION (off-topic, untrue '
              f'or illogical) and STRUCTURE, each 0-4, using these anchors:\n' + games._rubric_text('jam')
              + f'\n\nPROMPT: "{sec["prompt"]}"\nTRANSCRIPT: "{t["text"]}"\n\nFirst write "evidence", then the '
                'scores, any deviating phrases, one strength and one thing to work on (25 words max each).')
    schema = games.grade_request({'game': 'jam', 'payload': json.dumps({'topic': sec['prompt']}), 'key': None},
                                 {'text': t['text'], 'metrics': t['metrics']})[1]
    out, meta = claude_cli.ask(prompt, schema, SYSTEM, model=config.model('main')) if t['text'].strip() else ({}, {'model': ''})
    _bench_set(c, job['ref'], 'talk', {'metrics': t['metrics'], 'hesitation': inst['hesitation'], 'repetition': inst['repetition'],
                                       'deviation': games.clamp4(out.get('deviation')), 'structure': games.clamp4(out.get('structure')),
                                       'strength': out.get('strength', ''), 'work_on': out.get('work_on', ''), 'text': t['text'],
                                       'model': meta['model']})


HANDLERS = {'bench_essay': _do_bench_essay, 'bench_talk': _do_bench_talk, 'grade': _do_grade, 'revise': lambda c, j: _do_grade(c, j, revise=True), 'jam': _do_jam, 'golden': _do_golden}


def _fail(c, job, err):
    if job['tries'] < 2:
        c.execute("update jobs set status='queued', error=? where id=?", (err[:500], job['id']))
        return
    c.execute("update jobs set status='failed', error=?, done=datetime('now') where id=?", (err[:500], job['id']))
    if job['kind'] in ('grade', 'jam'):
        c.execute("update attempts set status='later' where id=?", (job['ref'],))
    elif job['kind'] in ('bench_essay', 'bench_talk'):
        _bench_set(c, job['ref'], job['kind'][6:], {'failed': True})


def work_once():
    c = db.connect()
    try:
        job = _claim(c)
        c.commit()
        if not job:
            return False
        try:
            HANDLERS[job['kind']](c, job)
            c.execute("update jobs set status='done', done=datetime('now'), error=null where id=?", (job['id'],))
        except Exception as e:  # keep the queue alive; the attempt shows "grading later"
            log.warning('job %s failed: %s', job['id'], e)
            log.debug(traceback.format_exc())
            _fail(c, job, f'{type(e).__name__}: {e}')
        c.commit()
        return True
    finally:
        c.close()


def _loop():
    while True:
        try:
            if work_once():
                continue
        except Exception:
            log.exception('grader loop')
        _wake.wait(timeout=30)
        _wake.clear()


def start(workers=2):
    c = db.connect()
    c.execute("update jobs set status='queued' where status='running'")   # interrupted by a restart
    c.commit()
    c.close()
    for i in range(workers):
        threading.Thread(target=_loop, name=f'grader-{i}', daemon=True).start()
