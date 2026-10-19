"""The daily edition: a finite set, the week's rhythm, and counts that only go up.

An edition is planned once per day (in your home time zone) and never expires:
a recall card on yesterday's passage, then one Understand game, one Reason game,
and one Express or Speak game. When those are done, it says so and stops.
"""
import json
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from . import config, db, games, ratings

UNDERSTAND = ['gist', 'gist', 'subtext']              # gist most days, subtext every third
REASON = ['weak', 'tech']
EXPRESS = ['word', 'bloat', 'jam']


def home_today():
    tz = ZoneInfo(config.settings().get('home_tz') or 'UTC')
    return datetime.now(tz).date()


def _has_live(c, game):
    return c.execute("select 1 from items where game=? and status='live' limit 1", (game,)).fetchone() is not None


def _choose(c, options, n_day, fallback):
    order = options[n_day % len(options):] + options[:n_day % len(options)]
    for g in order + fallback:
        if _has_live(c, g):
            return g
    return None


def _played_today(c, day):
    return {r['item_id'] for r in c.execute('select item_id from attempts where day=?', (day,))}


def plan(c, day):
    n = (date.fromisoformat(day) - date(2026, 1, 1)).days
    used = _played_today(c, day)
    slots = []
    for pillar, opts, fb in (('u', UNDERSTAND, ['subtext', 'gist']), ('r', REASON, ['tech', 'weak']),
                             ('e', EXPRESS, ['word', 'bloat', 'jam'])):
        g = _choose(c, opts, n, fb)
        if not g:
            continue
        skill = games.GAMES[g]['skill']
        if g == 'tech':
            ids = _tech_round(c, used)
            if ids:
                slots.append({'game': g, 'pillar': pillar, 'items': ids})
                used.update(ids)
            continue
        item = ratings.pick(c, g, skill, exclude=used)
        if item:
            slots.append({'game': g, 'pillar': pillar, 'items': [item]})
            used.add(item)
    return slots


def _tech_round(c, used, size=6):
    """Half manipulation, half fair: a round that only had fakes would teach suspicion, not judgment."""
    out = []
    for kind in ('technique', 'fair'):
        rows = c.execute("select id, rating, n, key from items where game='tech' and status='live'").fetchall()
        rows = [r for r in rows if r['id'] not in used and r['id'] not in out and json.loads(r['key'])['kind'] == kind]
        rows.sort(key=lambda r: (r['n'], abs(r['rating'] - (ratings.get(c, 'discern')[0] - 190))))
        out += [r['id'] for r in rows[:size // 2]]
    return games.stable_shuffle(out, 'tech-round-' + ','.join(out)) if out else []


def get_edition(c, day=None):
    day = day or home_today().isoformat()
    row = c.execute('select * from editions where day=?', (day,)).fetchone()
    if not row:
        slots = plan(c, day)
        recall = _recall_for(c, day)
        c.execute('insert into editions(day, plan, recall) values(?,?,?)',
                  (day, json.dumps(slots), json.dumps(recall) if recall else None))
        row = c.execute('select * from editions where day=?', (day,)).fetchone()
    slots = json.loads(row['plan'])
    done_items = {r['item_id']: r for r in c.execute('select * from attempts where day=? order by id', (day,))}
    out = []
    for i, s in enumerate(slots):
        g = games.GAMES[s['game']]
        att = [done_items[x] for x in s['items'] if x in done_items]
        first = c.execute('select * from items where id=?', (s['items'][0],)).fetchone()
        src = json.loads(first['source']) if first and first['source'] else {}
        out.append({'slot': i, 'game': s['game'], 'name': g['name'], 'pillar': s['pillar'], 'skill': g['skill'],
                    'minutes': g['minutes'], 'items': s['items'], 'done': len(att) >= len(s['items']),
                    'answered': len(att), 'source': src.get('book') or src.get('set') or '',
                    'scores': [a['score'] for a in att]})
    recall = db.j(row['recall'])
    finished = all(s['done'] for s in out) and out
    if finished and not row['finished']:
        c.execute("update editions set finished=datetime('now') where day=?", (day,))
    return {'day': day, 'slots': out, 'recall': recall, 'finished': bool(finished)}


def _recall_for(c, day):
    """Yesterday's reading passage comes back as a quick recall card, before you see it again."""
    y = (date.fromisoformat(day) - timedelta(days=1)).isoformat()
    r = c.execute("select a.item_id, i.source, i.key from attempts a join items i on i.id=a.item_id "
                  "where a.day=? and a.game in ('gist','subtext') order by a.id limit 1", (y,)).fetchone()
    if not r:
        return None
    src = json.loads(r['source'] or '{}')
    key = json.loads(r['key'] or '{}')
    return {'item': r['item_id'], 'book': src.get('book', ''), 'reference': key.get('gist') or key.get('answer', ''),
            'key_points': key.get('key_points', []), 'mark': None}


def mark_recall(c, day, answer, mark):
    row = c.execute('select recall from editions where day=?', (day,)).fetchone()
    if not row or not row['recall']:
        return None
    r = json.loads(row['recall'])
    r.update({'answer': answer[:500], 'mark': mark})
    c.execute('update editions set recall=? where day=?', (json.dumps(r), day))
    return r


def week(c):
    """This week's rhythm against the goal, with the rest day counting as on track."""
    s = config.settings()
    today = home_today()
    monday = today - timedelta(days=today.weekday())
    days = []
    active = 0
    for i in range(7):
        d = monday + timedelta(days=i)
        n = c.execute("select count(*) from attempts where day=? and status in ('done','later','grading')",
                      (d.isoformat(),)).fetchone()[0]
        rest = s.get('rest_weekday') is not None and i == s.get('rest_weekday')
        days.append({'day': d.isoformat(), 'answers': n, 'rest': rest, 'future': d > today, 'today': d == today})
        if n:
            active += 1
    rests = sum(1 for d in days if d['rest'] and not d['answers'] and not d['future'])
    goal = int(s.get('weekly_goal_days') or 4)
    return {'days': days, 'active': active, 'goal': goal, 'on_track': active + rests >= min(goal, today.weekday() + 1)}


def counts(c):
    """Counts that only go up. No streak to break."""
    q = lambda sql: c.execute(sql).fetchone()[0]
    return {'editions': q("select count(*) from editions where finished is not null"),
            'answers': q("select count(*) from attempts where status='done'"),
            'passages': q("select count(*) from attempts where game in ('gist','subtext') and status='done'"),
            'arguments': q("select count(*) from attempts where game='weak' and status='done'"),
            'minutes_spoken': round((q("select coalesce(sum(json_extract(instant,'$.metrics.speaking_time')),0) from attempts "
                                       "where game='jam'") or 0) / 60, 1),
            'active_weeks': q("select count(distinct strftime('%Y-%W', day)) from attempts where day is not null")}
