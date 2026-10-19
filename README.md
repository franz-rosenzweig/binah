# Binah

Binah (בינה, Hebrew for understanding) is my daily training app for understanding what I read, weighing what I hear, and saying what I mean. It's a phone-first web app with Mac and Android shells, it runs on my own server behind a login, and the code is here in case it's useful to someone else.

I started out wanting a Lumosity for language, and the research talked me out of it. Brain games make you better at brain games and not much else, so every game in Binah is a small, honest slice of the REAL skill, done on real text: I summarize an actual passage from memory, I find the actual weak step in an actual argument, I cut a padded sentence back to what a good writer actually wrote, and I talk for an actual minute without hesitating. Claude grades the answers that need judgment, always against a hidden key that was written and checked the night before, and code scores everything that can be counted.

## What's in it

- **A daily edition.** Five to eight minutes, and then it's done: a recall card on yesterday's passage, one game for understanding, one for reasoning, and one for writing or speaking. Past editions never expire, and there's no streak to break, only a weekly rhythm I set myself.
- **Seven games so far:**
  - **Gist & Infer:** read a passage, write its point in 20 words from memory, answer one question whose answer is implied.
  - **Subtext:** what's really going on in a scene?
  - **Find the Weak Step:** tap where an argument breaks, name the flaw, or call it sound.
  - **Technique or Fair Move?:** six quick calls. Half are manipulation and half are the same move done fairly, so you learn judgment, not suspicion.
  - **The Author's Word:** pick the word the writer actually chose.
  - **Cut the Bloat:** cut a padded sentence back toward the author's own line.
  - **Just a Minute:** sixty seconds on a topic without hesitation, repetition or deviation, recorded and transcribed on the server.
- **Answer, verdict, revise, reference.** Every open answer goes in that order. I rate myself first, Claude gives one strength and one thing to work on, I get ONE revision, and only then do I see the reference. The research says the learning lives in the revision.
- **Honest ratings.** Each skill has an Elo-style rating, and so does every item. Items are picked so I'd be expected to get about 75% right, and a rating says "calibrating" until there's enough to go on.
- **A golden set.** I write answers and score them myself with the same rubric Claude uses, and the app reports how well Claude agrees with me (exact, within one point, leniency, and quadratic weighted kappa). That's how I know whether to trust the grades.
- **A passage engine** (`engine/`) that mines my own ebooks for good passages: it measures every passage with plain, checkable numbers, has Claude draft items from only the best candidates, and has a second model check them blind. See [docs/ENGINE.md](docs/ENGINE.md).

The design and the reasons behind it are in [docs/DESIGN.md](docs/DESIGN.md).

## How it works

- **Server:** Python (FastAPI) with SQLite. Everything personal lives in a state folder outside the repo (`/srv/docker/binah` by default): the database, the login, the settings, and anything mined from my own books.
- **Web app:** vanilla JavaScript with no build step (`web/`), with a service worker so it opens offline.
- **Grading:** done by the Claude Code CLI (`claude -p`) on the owner's own subscription, through one small wrapper (`binah/claude_cli.py`). Tools, settings and session history are switched off, the output is structured JSON, and a missing result gets a retry and then "grading later", never a made-up score. There's a daily cap on graded calls.
- **Speech:** faster-whisper on the server's CPU, with voice detection for pauses, and filler and repetition counts done by code.
- **Two pools of material, kept strictly apart.** Items from your own books stay private to your account. The public pool is original content written for Binah (`content/`) plus public-domain text.

## Running it yourself

You'll need Python 3.12 and the Claude Code CLI logged in on the same machine. faster-whisper brings its own audio decoding, so there's no ffmpeg to install. A Calibre library is optional; it's what the passage engine reads.

```
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m binah.cli set-password --user me
.venv/bin/python -m binah.server          # http://127.0.0.1:8470
```

Settings live in `STATE/settings.json` (see `binah/config.py` for every option, including where your Calibre library is and a private list of title terms the engine must never mine). To mine your own books and draft items:

```
.venv/bin/python engine/mine.py
.venv/bin/python engine/rate.py all
.venv/bin/python -m binah.cli import
```

Running it as a service, the native shells and the rest are in [docs/OPERATIONS.md](docs/OPERATIONS.md) and [docs/SHELL.md](docs/SHELL.md).

## License

MIT, see [LICENSE](LICENSE). The fonts in `web/fonts` are under the SIL Open Font License. The content in `content/` was written for Binah and is under the same MIT license.
