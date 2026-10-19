"""Paths, constants and the private settings file.

Code is public; everything personal lives in STATE (default /srv/docker/binah),
which never goes into git:

    binah.db        the app's database (items, attempts, ratings, editions, golden set)
    auth.json       the login (scrypt hash, cookie secret)
    settings.json   private settings: where the library lives, private title terms,
                    a one-line description of the reader for prompts, vault export path
    engine/         passages.db, the passage engine's output from your own books
    benchmark/      sealed benchmark forms you never practise on
    audio/          voice answers, kept so a grade can be re-checked

Any setting can also come from an environment variable (BINAH_STATE, BINAH_PORT, ...).
"""
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE = Path(os.environ.get("BINAH_STATE", "/srv/docker/binah"))
DB_PATH = STATE / "binah.db"
AUTH_PATH = STATE / "auth.json"
SETTINGS_PATH = STATE / "settings.json"
PASSAGES_DB = Path(os.environ.get("BINAH_PASSAGES", str(STATE / "engine" / "passages.db")))
BENCH_DIR = STATE / "benchmark"
AUDIO_DIR = STATE / "audio"

WEB_DIR = ROOT / "web"
CONTENT_DIR = ROOT / "content"

HOSTS = [h for h in os.environ.get("BINAH_HOSTS", "127.0.0.1").split(",") if h]
PORT = int(os.environ.get("BINAH_PORT", "8470"))

DEFAULTS = {
    "home_tz": "UTC",
    # Who the prompts are grading. Keep it to a line; it's sent with every grading call.
    "reader": "an adult reader who wants to read more closely, reason more carefully and write more clearly",
    # Calibre library (read only) and an optional Daf database for highlights (read only).
    "calibre_dir": "",
    "daf_db": "",
    "daf_settings": "",
    # Extra terms: any book whose title or tags contain one of these is never mined.
    "private_terms": [],
    # Model for drafting and open grading; a .env file with CLAUDE_MODEL=... wins if given.
    "model": "sonnet",
    "model_env_file": "",
    "validator_model": "sonnet",
    "quick_model": "haiku",
    # Optional: write what you write to a folder of dated Markdown files (e.g. an Obsidian vault).
    "export_dir": "",
    # Optional: a script called as `notify TITLE TEXT` for sign-in alerts.
    "notify_cmd": "",
    "public_url": "",
    "weekly_goal_days": 4,
    "rest_weekday": None,          # 0=Mon ... 5=Sat, 6=Sun; counts as on track
    "grading_tone": "balanced",    # soft, balanced, strict
    "daily_grading_cap": 60,       # graded calls per day, so friends or a bug can't eat the subscription
}


def settings():
    s = dict(DEFAULTS)
    try:
        s.update(json.loads(SETTINGS_PATH.read_text()))
    except (FileNotFoundError, ValueError):
        pass
    return s


def save_settings(changes):
    s = settings()
    s.update(changes)
    STATE.mkdir(parents=True, exist_ok=True)
    tmp = SETTINGS_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps({k: v for k, v in s.items()}, indent=2, ensure_ascii=False))
    tmp.replace(SETTINGS_PATH)
    return s


def model(kind="main"):
    """The Claude model for a job: 'main' (drafting, open grading), 'validator', or 'quick'."""
    s = settings()
    if kind == "validator":
        return s.get("validator_model") or "sonnet"
    if kind == "quick":
        return s.get("quick_model") or "haiku"
    env = s.get("model_env_file")
    if env:
        try:
            for line in open(env):
                if line.startswith("CLAUDE_MODEL="):
                    return line.split("=", 1)[1].strip().strip("\"'")
        except OSError:
            pass
    return s.get("model") or "sonnet"
