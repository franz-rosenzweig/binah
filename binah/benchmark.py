"""The monthly benchmark: sealed forms I never practise on, scored the same way every time.

Forms live in STATE/benchmark/forms/ (written by binah.benchgen, never in git). A run
sends the form without its answers, saves each answer as I go (so a sitting can be
paused), and scores on finish:
  - multiple choice (argument, inference, vocabulary): accuracy per section, plus a
    Brier score on the confidences;
  - fair-or-trick: discernment d' and bias, from signal detection, so getting more
    suspicious doesn't look like getting sharper;
  - the essay and the two-minute talk: graded by Claude (the essay twice, averaged),
    with a frozen rubric.
Practice scores and benchmark scores are kept on separate tracks.
"""
import json
import statistics
from datetime import datetime, timezone

from . import config, db

MC = ('argument', 'inference', 'vocab')


def forms():
    d = config.BENCH_DIR / 'forms'
    out = []
    for p in sorted(d.glob('form-*.json')) if d.exists() else []:
        try:
            f = json.loads(p.read_text())
            out.append({'id': f['id'], 'created': f.get('created'), 'sections': [s['kind'] for s in f['sections']]})
        except (ValueError, KeyError):
            continue
    return out


def load(form_id):
    p = config.BENCH_DIR / 'forms' / f'{form_id}.json'
    return json.loads(p.read_text())


def strip(form):
    """The form as the player sees it: no answers, no explanations, no technique keys."""
    out = {'id': form['id'], 'sections': []}
    for s in form['sections']:
        k = s['kind']
        if k in ('argument', 'vocab'):
            out['sections'].append({'kind': k, 'items': [{x: it[x] for x in it if x not in ('answer', 'explanation')} for it in s['items']]})
        elif k == 'discern':
            out['sections'].append({'kind': k, 'items': [{'id': it['id'], 'text': it['text'], 'context': it.get('context', '')} for it in s['items']]})
        elif k == 'inference':
            out['sections'].append({'kind': k, 'passages': [{'source': p.get('source', ''), 'text': p['text'],
                                                              'questions': [{x: q[x] for x in q if x not in ('answer', 'explanation')} for q in p['questions']]}
                                                             for p in s['passages']]})
        elif k == 'essay':
            out['sections'].append({'kind': k, 'prompt': s['prompt'], 'minutes': s.get('minutes', 15)})
        elif k == 'talk':
            out['sections'].append({'kind': k, 'prompt': s['prompt'], 'seconds': s.get('seconds', 120)})
    return out


def runs(c):
    return [{'id': r['id'], 'form': r['form'], 'started': r['started'], 'finished': r['finished'],
             'results': db.j(r['results'])} for r in c.execute('select * from bench_runs order by id')]


def save_answer(c, run_id, key, value):
    r = c.execute('select answers, finished from bench_runs where id=?', (run_id,)).fetchone()
    if not r or r['finished']:
        return False
    a = db.j(r['answers']) or {}
    a[key] = value
    c.execute('update bench_runs set answers=? where id=?', (json.dumps(a, ensure_ascii=False), run_id))
    return True


def score(c, run_id):
    r = c.execute('select * from bench_runs where id=?', (run_id,)).fetchone()
    form = load(r['form'])
    ans = db.j(r['answers']) or {}
    res, briers = {}, []
    for s in form['sections']:
        k = s['kind']
        if k in ('argument', 'vocab'):
            right = 0
            for it in s['items']:
                a = ans.get(f'{k}:{it["id"]}') or {}
                ok = a.get('choice') == it['answer']
                right += ok
                if isinstance(a.get('confidence'), (int, float)):
                    p = a['confidence'] / 100
                    briers.append((1 - p) ** 2 if ok else p ** 2)
            res[k] = {'right': right, 'of': len(s['items'])}
        elif k == 'inference':
            right = n = 0
            for p in s['passages']:
                for q in p['questions']:
                    n += 1
                    a = ans.get(f'inference:{q["id"]}') or {}
                    ok = a.get('choice') == q['answer']
                    right += ok
                    if isinstance(a.get('confidence'), (int, float)):
                        pp = a['confidence'] / 100
                        briers.append((1 - pp) ** 2 if ok else pp ** 2)
            res[k] = {'right': right, 'of': n}
        elif k == 'discern':
            h = f = nt = nf = 0
            for it in s['items']:
                a = ans.get(f'discern:{it["id"]}') or {}
                said = a.get('kind') == 'technique'
                if it['kind'] == 'technique':
                    nt += 1
                    h += said
                else:
                    nf += 1
                    f += said
                if isinstance(a.get('confidence'), (int, float)):
                    p = a['confidence'] / 100
                    ok = a.get('kind') == it['kind']
                    briers.append((1 - p) ** 2 if ok else p ** 2)
            z = statistics.NormalDist().inv_cdf
            H, F = (h + 0.5) / (nt + 1), (f + 0.5) / (nf + 1)
            res[k] = {'hits': h, 'of_tricks': nt, 'false_alarms': f, 'of_fair': nf,
                      'dprime': round(z(H) - z(F), 2), 'bias': round(-(z(H) + z(F)) / 2, 2)}
        elif k == 'essay':
            res[k] = {'words': len((ans.get('essay') or {}).get('text', '').split()), 'grade': None}
        elif k == 'talk':
            res[k] = {'grade': None}
    res['brier'] = round(sum(briers) / len(briers), 3) if briers else None
    return res


def finish(c, run_id):
    res = score(c, run_id)
    c.execute("update bench_runs set results=?, finished=? where id=?",
              (json.dumps(res), datetime.now(timezone.utc).isoformat(timespec='seconds'), run_id))
    return res


ESSAY_SCHEMA = {'type': 'object', 'properties': {
    'evidence': {'type': 'string'},
    'structure': {'type': 'integer', 'minimum': 0, 'maximum': 4},
    'accuracy': {'type': 'integer', 'minimum': 0, 'maximum': 4},
    'understanding': {'type': 'integer', 'minimum': 0, 'maximum': 4},
    'strength': {'type': 'string'}, 'work_on': {'type': 'string'}},
    'required': ['evidence', 'structure', 'accuracy', 'understanding', 'strength', 'work_on']}


def essay_request(run_id, c):
    r = c.execute('select * from bench_runs where id=?', (run_id,)).fetchone()
    form = load(r['form'])
    sec = next(s for s in form['sections'] if s['kind'] == 'essay')
    text = ((db.j(r['answers']) or {}).get('essay') or {}).get('text', '')
    rub = sec.get('rubric') or {}
    prompt = (f'Grade a timed 15-minute essay written for a reasoning benchmark. Use this frozen rubric, each 0-4:\n'
              + '\n'.join(f'- {k}: {v}' for k, v in rub.items())
              + f'\n\nPROMPT: "{sec["prompt"]}"\n\nESSAY:\n"""\n{text}\n"""\n\n'
                'First write "evidence" (2-3 sentences on what the essay does), then the three scores, then one strength '
                'and one thing to work on, 25 words max each. Grade the reasoning and the writing, not the length.')
    return prompt, ESSAY_SCHEMA
