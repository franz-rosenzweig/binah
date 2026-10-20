<sub>[Binah docs](README.md) › Under the hood</sub>

# Developing Binah

This is the page for working on Binah's code: how it's laid out, how the pieces fit, how to run a copy you can break, and the tools and checks that come with it. The plan and the reasons behind it are in [DESIGN.md](DESIGN.md), and the passage engine has its own page, [ENGINE.md](ENGINE.md).

## How it works

- **Server:** Python (FastAPI) with SQLite. Everything personal lives in a state folder outside the repo (`/srv/docker/binah` by default, or `BINAH_STATE`): the database, the login, the settings, and anything mined from your own books.
- **Web app:** vanilla JavaScript with no build step (`web/`), with a service worker so it opens offline. One stylesheet has two looks: the page puts `m3` on `<html>` when the window is under 900px wide, and always in the Android shell, and gets Material 3 (a large title, a tonal Continue card, a bottom bar); otherwise it looks like Apple's own apps, with a sidebar (`/api/nav` gives its counts), a 52px toolbar row, and games split into a reading pane and an answer panel at 1100px and up. In the Mac shell, `shell-vibrant` leaves the sidebar transparent for the window's sidebar material (see [SHELL.md](SHELL.md)).
- **Grading:** done by the Claude Code CLI (`claude -p`) on the owner's own subscription, through one small wrapper (`binah/claude_cli.py`). Tools, settings and session history are switched off, the output is structured JSON, and a missing result gets a retry and then "grading later", never a made-up score. There's a daily cap on graded calls.
- **Speech:** faster-whisper on the server's CPU, with voice detection for pauses, and filler and repetition counts done by code.
- **Two pools of material, kept strictly apart.** Items from your own books are the private pool and stay in your own copy. The public pool is the original content written for Binah (`content/`), and the benchmark draws on public-domain essays. Every item carries its pool and licence from the moment it's made.

## The layout

| | |
|---|---|
| `binah/app.py` | the web API and the static app. The order inside every open answer (answer with a self-rating, verdict, one revision, reference) is enforced here, and the hidden key is never sent before the answer is in |
| `binah/games.py` | the games: what each one shows, how code scores it, the rubrics, and the grading prompts |
| `binah/grader.py` | the grading queue, a background thread that works jobs through `claude_cli.ask`, with the daily cap |
| `binah/edition.py` | the daily edition, the week and the counts |
| `binah/ratings.py` | Elo for skills and items, and picking the next item |
| `binah/golden.py` | anchors for grading prompts, and the agreement report |
| `binah/benchmark.py`, `binah/benchgen.py` | scoring a sitting, and writing sealed forms |
| `binah/speech.py` | transcription and the speech numbers |
| `binah/items.py` | importing items from the engine and `content/` (an upsert that keeps ratings) |
| `binah/auth.py`, `binah/config.py`, `binah/db.py`, `binah/exporter.py`, `binah/cli.py` | the login and device tokens, paths and settings, the schema, the Markdown export, the command line |
| `engine/` | the passage engine: `epub.py`, `mine.py`, `features.py`, `rate.py`, `export.py`, `purge.py` |
| `web/` | `style.css` (both looks), `app.js` (routing, the sidebar and bottom bar, Today, Practice, Skills, the golden set, Settings), `play.js` (the games), `bench.js` (the benchmark), `shell.js` (the page's half of the shell contract) |
| `content/` | `technique.json`, `jam_topics.json`, and `table_topics.json` for Table Topics, which isn't built yet |
| `mac/`, `android/` | the two native shells, each with its own README |
| `deploy/` | systemd user units for the server and the nightly run |
| `demo/` | the public taste: Technique or Fair Move? played entirely in the browser (`index.html`, `demo.js`, `demo.css`, `shots/`) |
| `tools/` | content and icon tools, the demo builder, and a speech smoke test |

## Running it from source

You'll need Python 3.12 and the Claude Code CLI logged in on the same machine. faster-whisper brings its own audio decoding, so there's no ffmpeg to install. A Calibre library is optional; it's what the passage engine reads.

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m binah.cli set-password --user me
.venv/bin/python -m binah.server          # http://127.0.0.1:8470
```

Settings live in `STATE/settings.json` (see `binah/config.py` for every option, including where your Calibre library is and a private list of title terms the engine must never mine). To mine your own books and draft items:

```sh
.venv/bin/python engine/mine.py
.venv/bin/python engine/rate.py all
.venv/bin/python -m binah.cli import
```

The command line:

```sh
.venv/bin/python -m binah.cli doctor          # what's configured, live items, the queue
.venv/bin/python -m binah.cli import          # reload items from the engine and content/
.venv/bin/python -m binah.cli golden          # the golden-set agreement report
.venv/bin/python -m binah.cli set-password    # new password (signs out every browser)
.venv/bin/python -m binah.benchgen --forms 3  # write sealed benchmark forms into STATE/benchmark/forms
```

## A sandbox

Work against a copy, never against a state folder you care about. Point `BINAH_STATE` at a fresh folder (or a copy) and use another port:

```sh
BINAH_STATE=/tmp/binah-sandbox BINAH_PORT=8471 BINAH_HOSTS=127.0.0.1 .venv/bin/python -m binah.server
```

A fresh folder starts empty: set a password in it with `BINAH_STATE=... python -m binah.cli set-password`, and the server imports `content/` when it starts. Grading calls the real `claude` on your subscription, so a sandbox that you click through costs real calls. The shells' self-tests are written to run against a sandbox like this, never the real copy, because they make device tokens and save passages.

## Tools

- `tools/gen_content.py` drafts the practice content in `content/` with Claude and checks it blind (`--work FOLDER all`, or one of `jam`, `table`, `technique`). Read the output over before committing it.
- `tools/content_stats.py` prints counts and field spreads for `content/` and, for the sealed forms, only counts, types and answer positions, never an item.
- `tools/make_icons.py` draws the icons (the letter ב in Frank Ruhl Libre on a parchment tile). It needs fontTools, Brotli and Pillow, which are commented in `requirements.txt`.
- `tools/build_demo.py OUT_DIR` puts the public taste together: `demo/`, the app's `style.css` with its font paths made relative, the fonts, the icon and `content/technique.json`. Every file comes from the repo, with no server and nothing from the state folder, so the folder can be served as plain static files. Its screenshots live in `demo/shots/`.
- `tools/test_speech.py` cuts a 60-second clip from any spoken-word file you have, re-encodes it the way browsers record, runs `transcribe()` on it, and checks that silent, empty and broken files behave.

## The shells

The page is the whole interface, and the Mac and Android apps are windows around it plus the few things a page can't do. [SHELL.md](SHELL.md) is the contract: the user agent, `window.binahShell`, `window.binahCommand`, device tokens, the widget endpoint, Train on this, and deep links. Building and testing each one is in [mac/README.md](../mac/README.md) (`mac/build.sh`, `mac/selftest.sh`) and [android/README.md](../android/README.md) (`android/release.sh`, `android/check.sh`).

Keep signing identities, team IDs, keystores and tokens out of the repo. It's public.
