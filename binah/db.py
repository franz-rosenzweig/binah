"""The app's SQLite database (STATE/binah.db).

Items are what you play, attempts are what you answered, ratings are per skill.
Everything else (editions, jobs, the golden set, benchmark runs) hangs off those.
"""
import json
import sqlite3
import threading

from . import config

SCHEMA = """
create table if not exists items(
  id text primary key,            -- e.g. gist:p10889, tech:t001, jam:j012
  game text not null,             -- gist, subtext, weak, word, bloat, tech, jam, topics
  skill text not null,
  pool text not null,             -- private (your own books) or public (original or public domain)
  license text,
  source text,                    -- JSON: where it came from
  payload text not null,          -- JSON the player sees
  key text,                       -- JSON hidden key, never sent before you answer
  rating real not null default 1200,
  n integer not null default 0,
  status text not null default 'live',   -- live, draft, retired
  created text default (datetime('now'))
);
create index if not exists items_game on items(game, status);

create table if not exists attempts(
  id integer primary key autoincrement,
  item_id text not null,
  game text not null,
  day text,                       -- the edition day it belongs to (home time zone), or null for practice
  slot integer,                   -- position in that day's edition
  ms integer,
  answer text,                    -- JSON
  self_rating integer,
  instant text,                   -- JSON: what code scored
  grade text,                     -- JSON: Claude's first verdict
  revision text,                  -- JSON: the revised answer
  grade2 text,                    -- JSON: verdict on the revision
  score real,                     -- 0..1, from the FIRST try (ratings measure unaided skill)
  score2 real,                    -- 0..1 after revising
  rating_before real, rating_after real, item_before real,
  status text not null default 'done',   -- grading, done, later, error
  disputed text,
  model text,
  created text default (datetime('now'))
);
create index if not exists attempts_day on attempts(day);
create index if not exists attempts_item on attempts(item_id);

create table if not exists ratings(skill text primary key, rating real not null, n integer not null default 0, last text);

create table if not exists editions(day text primary key, plan text not null, recall text, created text default (datetime('now')), finished text);

create table if not exists jobs(
  id integer primary key autoincrement,
  kind text not null,             -- grade, revise, jam, golden
  ref integer,                    -- attempt id or golden id
  status text not null default 'queued',   -- queued, running, done, failed, later
  tries integer not null default 0,
  error text,
  created text default (datetime('now')),
  done text
);

create table if not exists golden(
  id integer primary key autoincrement,
  item_id text not null,
  game text not null,
  answer text not null,           -- JSON
  mine text,                      -- JSON: my own scores per criterion
  claude text,                    -- JSON: Claude's scores per criterion (graded blind, no anchors)
  rubric integer not null default 1,
  model text,
  created text default (datetime('now'))
);

create table if not exists bench_runs(
  id integer primary key autoincrement,
  form text not null, started text default (datetime('now')), finished text,
  answers text, results text
);

create table if not exists saved(
  id integer primary key autoincrement,
  url text, title text, text text,         -- something sent with "train on this" (share sheet, the Mac)
  status text not null default 'new',      -- new, used, skipped
  created text default (datetime('now'))
);

create table if not exists kv(k text primary key, v text);
create table if not exists devices(token_hash text primary key, name text, created integer, last_seen integer);
"""

_init_lock = threading.Lock()
_ready = False


def connect():
    global _ready
    config.STATE.mkdir(parents=True, exist_ok=True)
    c = sqlite3.connect(config.DB_PATH, timeout=30, check_same_thread=False)
    c.row_factory = sqlite3.Row
    c.execute("pragma journal_mode=wal")
    c.execute("pragma foreign_keys=on")
    if not _ready:
        with _init_lock:
            if not _ready:
                c.executescript(SCHEMA)
                c.commit()
                _ready = True
    return c


def j(value):
    """Load a JSON column (None stays None)."""
    return json.loads(value) if value else None


def kv_get(c, k, default=None):
    r = c.execute("select v from kv where k=?", (k,)).fetchone()
    return json.loads(r["v"]) if r else default


def kv_set(c, k, v):
    c.execute("insert into kv(k, v) values(?, ?) on conflict(k) do update set v=excluded.v", (k, json.dumps(v)))
