# Running Binah

This is how my copy runs. The paths are my defaults; everything can be changed with environment variables (see `binah/config.py`).

## Where things live

| | |
| --- | --- |
| `/srv/dev/binah` | the source, a git checkout of the public repo, where I edit |
| `/srv/dev/binah-live` | a detached worktree pinned to the commit that's running, so a restart never loads half-edited code |
| `/srv/docker/binah` | private state, never in git: `binah.db`, `auth.json`, `settings.json`, `engine/passages.db` (from my own books), `benchmark/` (sealed forms), `audio/` (voice answers) |

## The service

A systemd user unit, `binah.service` (a copy is in `deploy/binah.service`), runs `python -m binah.server` from the live worktree with the source checkout's virtualenv. It listens on port 8470 on localhost and the Tailscale address, and it needs `~/.local/bin` on its PATH so it can find the `claude` CLI.

```
systemctl --user status binah
journalctl --user -u binah -f
```

## Deploying a change

1. Commit and push in `/srv/dev/binah`.
2. Pin the live worktree to it and restart:

```
git -C /srv/dev/binah-live checkout --detach <commit>
systemctl --user restart binah
```

Then check that `curl -s http://127.0.0.1:8470/api/me` answers.

## The public address

The app is reachable at `https://binah.tiresia.xyz` through the host's cloudflared tunnel. The ingress rule lives in the root-owned cloudflared config, so adding it is a root step:

```yaml
- hostname: binah.tiresia.xyz
  service: http://localhost:8470
```

Then route the DNS name to the tunnel and restart cloudflared. Requests that come through the tunnel arrive from loopback with Cloudflare's headers, which is how Binah knows to set a Secure cookie and to take the client address from `CF-Connecting-IP` for the sign-in throttle.

## The command line

```
.venv/bin/python -m binah.cli doctor          # what's configured, live items, the queue
.venv/bin/python -m binah.cli import          # reload items from the engine and content/
.venv/bin/python -m binah.cli golden          # the golden-set agreement report
.venv/bin/python -m binah.cli set-password    # new password (signs out every browser)
.venv/bin/python -m binah.benchgen --forms 3   # write sealed benchmark forms into STATE/benchmark/forms
```

## The monthly benchmark

The sealed forms are written by `binah/benchgen.py` from public-domain sources it downloads and caches in `STATE/benchmark/sources`, and they live in `STATE/benchmark/forms`, never in git, so I can't have seen them. Each form is sat once. The app's Skills screen says when a sitting is due (28 days after the last), and a finished sitting shows its key and explanations, which is fine because that form never comes back. The essay is graded twice and averaged; the talk is transcribed and graded once. Write new forms when the app says none are left.

## A sandbox

Run a second copy against a copy of the state on another port, never against the live database:

```
cp -r /srv/docker/binah /tmp/binah-sandbox
BINAH_STATE=/tmp/binah-sandbox BINAH_PORT=8471 BINAH_HOSTS=127.0.0.1 .venv/bin/python -m binah.server
```

## Grading and the subscription

Every Claude call goes through `binah/claude_cli.py`: `claude -p` with tools, settings, MCP and session history off, from an empty folder, with Binah's own short system prompt. The subscription's limits are shared with everything else I use Claude for, so `daily_grading_cap` in settings stops the queue for the day once it's reached (answers then say "grading later"), and the passage engine batches eight to twelve items per call.

## Backups

`binah.db` is the record of what I've answered. It's small; copy it with the rest of `/srv/docker/binah` in the nightly backup. Everything else in state can be rebuilt (the engine can re-mine, items can be re-imported).
