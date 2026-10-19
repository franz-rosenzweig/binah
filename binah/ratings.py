"""Ratings: Elo for you (one rating per skill) and for every item.

Every answer is a match between you and the item. The update shrinks as answers
pile up (Pelánek 2016: U(n) = a / (1 + b·n)), so a new skill or item finds its
level quickly and then settles. Items move more gently than you do, because a
single person plays each item only a few times.

Items are picked so you'd be expected to score about 75%: an item rated about
190 points below your rating. That's what Math Garden aims for.
"""
import math
import random
from datetime import datetime, timezone

START = 1200.0
TARGET = 0.75
CALIBRATING_UNDER = 8


def expected(you, item):
    return 1.0 / (1.0 + math.pow(10.0, (item - you) / 400.0))


def k_you(n):
    return max(16.0, 64.0 / (1.0 + 0.05 * n))


def k_item(n):
    return max(6.0, 24.0 / (1.0 + 0.05 * n))


def get(c, skill):
    r = c.execute("select rating, n from ratings where skill=?", (skill,)).fetchone()
    return (r["rating"], r["n"]) if r else (START, 0)


def all_ratings(c):
    return {r["skill"]: {"rating": round(r["rating"]), "n": r["n"], "calibrating": r["n"] < CALIBRATING_UNDER}
            for r in c.execute("select skill, rating, n from ratings")}


def update(c, skill, item_id, score):
    """Apply one result (score 0..1). Returns (you_before, you_after, item_before)."""
    you, n = get(c, skill)
    it = c.execute("select rating, n from items where id=?", (item_id,)).fetchone()
    item_r, item_n = (it["rating"], it["n"]) if it else (START, 0)
    e = expected(you, item_r)
    you_after = you + k_you(n) * (score - e)
    item_after = item_r - k_item(item_n) * (score - e)
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    c.execute("insert into ratings(skill, rating, n, last) values(?,?,?,?) "
              "on conflict(skill) do update set rating=excluded.rating, n=excluded.n, last=excluded.last",
              (skill, you_after, n + 1, now))
    if it:
        c.execute("update items set rating=?, n=n+1 where id=?", (item_after, item_id))
    return round(you), round(you_after), round(item_r)


def pick(c, game, skill, exclude=(), target=TARGET):
    """The live item for this game whose rating best fits the target success rate.
    Unplayed items first; among those, the one closest to the target rating."""
    you, _ = get(c, skill)
    want = you - 400.0 * math.log10(target / (1.0 - target))
    rows = c.execute("select id, rating, n from items where game=? and status='live' "
                     "and id not in (select item_id from golden)", (game,)).fetchall()
    rows = [r for r in rows if r["id"] not in exclude]
    if not rows:
        return None
    least = min(r["n"] for r in rows)
    fresh = [r for r in rows if r["n"] == least]
    fresh.sort(key=lambda r: (abs(r["rating"] - want), random.random()))
    return fresh[0]["id"]
