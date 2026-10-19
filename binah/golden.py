"""The golden set: answers I wrote and scored by hand, so I know whether Claude's grades deserve trust.

Two uses:
  - anchors: up to three of my scored answers per game (low, middle, high) go into
    every grading prompt, which the research found is the biggest lever on agreement;
  - the report: Claude grades each golden answer BLIND (no anchors), and the report
    compares its scores with mine, criterion by criterion: exact agreement, within one
    point, mean difference (a positive number means Claude is more lenient than me),
    and quadratic weighted kappa.
"""
import json

from . import games

GOLDEN_GAMES = ['gist', 'subtext', 'bloat']
TARGET = 50


def anchors(c, game, k=3):
    rows = c.execute('select answer, mine from golden where game=? and mine is not null', (game,)).fetchall()
    if not rows:
        return []
    scored = sorted(rows, key=lambda r: sum(json.loads(r['mine']).values()))
    picks = [scored[0], scored[len(scored) // 2], scored[-1]] if len(scored) >= 3 else scored
    seen, out = set(), []
    for r in picks:
        if r['answer'] in seen:
            continue
        seen.add(r['answer'])
        out.append({'answer': json.loads(r['answer']), 'mine': json.loads(r['mine'])})
    return out[:k]


def add(c, item_id, game, answer, mine):
    crit = games.RUBRICS[game]['criteria']
    clean = {k: games.clamp4(mine.get(k)) for k in crit}
    cur = c.execute('insert into golden(item_id, game, answer, mine, rubric) values(?,?,?,?,?)',
                    (item_id, game, json.dumps(answer, ensure_ascii=False), json.dumps(clean),
                     games.RUBRICS[game]['version']))
    return cur.lastrowid


def _qwk(a, b, k=5):
    n = len(a)
    if n < 2:
        return None
    O = [[0] * k for _ in range(k)]
    for x, y in zip(a, b):
        O[x][y] += 1
    ha = [sum(O[i]) for i in range(k)]
    hb = [sum(O[i][j] for i in range(k)) for j in range(k)]
    num = den = 0.0
    for i in range(k):
        for j in range(k):
            w = (i - j) ** 2 / (k - 1) ** 2
            num += w * O[i][j]
            den += w * ha[i] * hb[j] / n
    return round(1 - num / den, 3) if den else None


def report(c):
    out = {'target': TARGET, 'total': c.execute('select count(*) from golden where mine is not null').fetchone()[0],
           'games': {}}
    for game in GOLDEN_GAMES:
        rows = c.execute('select mine, claude from golden where game=? and mine is not null', (game,)).fetchall()
        crit = list(games.RUBRICS[game]['criteria'])
        per = {}
        for name in crit:
            pairs = [(json.loads(r['mine'])[name], json.loads(r['claude'])[name]) for r in rows
                     if r['claude'] and name in json.loads(r['claude'])]
            if not pairs:
                per[name] = {'n': 0}
                continue
            mine, cl = [p[0] for p in pairs], [p[1] for p in pairs]
            per[name] = {'n': len(pairs),
                         'exact': round(sum(1 for x, y in pairs if x == y) / len(pairs), 2),
                         'within1': round(sum(1 for x, y in pairs if abs(x - y) <= 1) / len(pairs), 2),
                         'lenient': round(sum(y - x for x, y in pairs) / len(pairs), 2),
                         'qwk': _qwk(mine, cl)}
        out['games'][game] = {'scored': len(rows), 'graded': sum(1 for r in rows if r['claude']), 'criteria': per}
    return out
