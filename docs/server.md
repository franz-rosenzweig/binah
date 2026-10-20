<sub>[Binah docs](README.md) › Running your own copy</sub>

# Your own server

Running your own copy of Binah means one Python process on a machine that stays on, with the Claude Code CLI logged in beside it, and this page takes you from a fresh checkout to a copy you can reach from your phone. I run mine on my home server, and everything here is how it's meant to be set up, with my own specifics left out (those are in [OPERATIONS.md](OPERATIONS.md)).

## What you need

- **Python 3.12** on Linux or a Mac.
- **The Claude Code CLI**, installed and logged in on the same machine with a Claude subscription, because every grade is a `claude -p` call on that subscription. Binah never needs an API key.
- **A Calibre library** (optional) of EPUBs, which is what the five reading games are made from. Without it you get Technique or Fair Move? and Just a Minute, which ship with the code.
- **A little CPU** for speech. faster-whisper brings its own audio decoding, so there's no ffmpeg to install, and it downloads its model the first time someone speaks.

## Setting it up

```sh
git clone https://github.com/franz-rosenzweig/binah.git && cd binah
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m binah.cli set-password --user me
.venv/bin/python -m binah.server          # http://127.0.0.1:8470
```

`set-password` asks for a password of at least 10 characters, and running it again later signs out every browser. Open the address, sign in, and you'll see Today, with a first edition of whatever has items: at this point that's Technique or Fair Move? and Just a Minute.

Then check what it sees with `.venv/bin/python -m binah.cli doctor`, which prints the state folder, the address, whether the login is set, the models, the passage database, how many items are live per game, and the grading queue.

## The state folder

Everything personal lives in one folder outside the code, `/srv/docker/binah` by default, or wherever `BINAH_STATE` points:

| | |
|---|---|
| `binah.db` | the database: items, answers, grades, ratings, editions, the golden set, benchmark sittings |
| `auth.json` | the login (a scrypt hash and the cookie secret) |
| `settings.json` | your settings (below) |
| `engine/passages.db` | what the passage engine made from your own books |
| `benchmark/` | the sealed benchmark forms, and the public-domain essays they're written from |
| `audio/` | spoken answers, kept so a grade can be checked again |

None of it goes into git, and none of it is ever served publicly. Basically, the code is something you can share, and the state folder is something you never do.

## Settings

`STATE/settings.json` holds the settings. Every key is optional, and [`binah/config.py`](../binah/config.py) has the defaults:

| Key | What it does |
|---|---|
| `home_tz` | your time zone, for when a new day's edition starts, e.g. `"Europe/London"` (default `UTC`) |
| `calibre_dir` | the folder of your Calibre library, read only, for the passage engine |
| `private_terms` | a private list of terms: any book whose title or tags contain one is never mined |
| `daf_db`, `daf_settings` | if you use Daf, its database for highlights and its settings for its private titles, both read only |
| `reader` | one line describing who's being graded, sent with every grading call |
| `model`, `validator_model`, `quick_model` | the Claude models for drafting and open grading (`sonnet`), the blind checks (`sonnet`), and the quick grades (`haiku`) |
| `model_env_file` | a `.env` file whose `CLAUDE_MODEL=` line wins over `model`, so one setting can serve several tools |
| `daily_grading_cap` | graded calls per day (default 60). Past it, the queue stops for the day and the rest are graded the next day |
| `export_dir` | a folder for one dated Markdown file a day of what you write |
| `notify_cmd` | a command called as `notify TITLE TEXT` when someone keeps getting the password wrong |
| `public_url` | your public address, which the widget and the menu bar link to |
| `weekly_goal_days`, `rest_weekday`, `grading_tone` | the three things the app's own Settings page changes (it also changes the password and lists connected devices) |

The address comes from the environment: `BINAH_HOSTS` (comma-separated, default `127.0.0.1`) and `BINAH_PORT` (default `8470`).

## Making the reading games from your books

With `calibre_dir` set, the passage engine measures every passage in your library, has Claude draft items from the best ones, and has a second model check them blind:

```sh
.venv/bin/python engine/mine.py             # measure the whole library (about 30 seconds for 160 books)
.venv/bin/python engine/rate.py all         # book cards, drafts, the blind check (Claude, batched)
.venv/bin/python -m binah.cli import        # load them into the app
```

`mine.py --limit 5` is a quick test. The engine skips books that aren't in English for now, and any book matching your private terms, and the first full run took 25 Claude calls on my subscription. How it works, and what came out of my own library, is in [ENGINE.md](ENGINE.md).

## The benchmark forms

The monthly benchmark needs sealed forms, which are written on the server:

```sh
.venv/bin/python -m binah.benchgen --forms 3
```

It downloads a handful of public-domain essays from Project Gutenberg into `STATE/benchmark/sources` once, drafts every question with Claude, keeps only the ones a second model answers the same way blind, and prints counts and pass rates, never a question, so you can't have seen them.

## Running it for good

`deploy/` has three systemd user units to start from. `binah.service` runs the server, `binah-nightly.service` runs `engine/rate.py nightly`, which drafts fresh items, checks them blind, loads them and keeps two unused benchmark forms in hand, and `binah-nightly.timer` runs that at 03:15. The paths in them are mine, so change `WorkingDirectory`, `ExecStart` and `BINAH_STATE` to yours, and keep the folder where `claude` lives on the `PATH`, or grading can't find it.

```sh
cp deploy/binah*.service deploy/binah-nightly.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now binah binah-nightly.timer
```

## Reaching it from your phone

Your phone needs to reach the server, and for the microphone it needs https. A private network like Tailscale, with its address added to `BINAH_HOSTS`, is the quickest way in, though on a plain `http://` address you can play everything except the spoken games. For https, put it behind a tunnel or a reverse proxy with a certificate. Binah is built to sit behind a Cloudflare tunnel: requests that arrive that way get a Secure cookie, and the sign-in throttle uses the visitor's real address. Behind any other proxy it still works, but the cookie isn't marked Secure, and the throttle sees the proxy's address.

The sign-in is one username and password. Five wrong tries from one address make that address wait 15 minutes, twenty wrong tries in an hour pause sign-in for everyone for 15 minutes, and `notify_cmd` (if you set one) hears about both, at most every six hours.

## The subscription

Every Claude call goes through one wrapper, `binah/claude_cli.py`: `claude -p` with tools, settings, MCP and session history switched off, run from an empty folder, with Binah's own short system prompt. It insists on structured output and retries once, and if both tries fail the answer says "grading later" instead of getting a made-up score. Your subscription's limits are shared with everything else you use Claude for, which is what `daily_grading_cap` is for, and the engine batches eight to twelve items per call.

## Backups

`binah.db` is the record of everything you've answered. It's small, so copy it with the rest of the state folder in your nightly backup. Everything else can be rebuilt: the engine can re-mine, items can be re-imported, and forms can be written again.

If something doesn't work, `binah.cli doctor` is the first thing to run, and after that, feel free to open an issue.

<sub>Next: [Design](DESIGN.md) →</sub>
