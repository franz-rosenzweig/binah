# The API

Everything the web app does goes through this JSON API, and the Mac and Android apps are native clients of it. This is the shape of each request and answer as of October 2026. Field names are stable: new fields can appear at any time (ignore what you don't know), but a field that changes shape or goes away gets announced first.

## Signing in

- `POST /api/login` `{"user": "...", "password": "..."}` sets the `binah` cookie. Wrong passwords are throttled (5 per address per 15 minutes, 20 an hour in all) and send me an alert.
- `GET /api/me` → `{"signed_in": true, "has_password": true, "user": "..."}`
- `POST /api/logout` `{}`, `POST /api/account` `{"current", "password"}` (10+ characters; signs out every other browser).
- An app signs in once with the cookie and then uses a bearer token of its own; see [Devices](#devices). Every `/api/` route takes `Authorization: Bearer <token>` instead of the cookie.

Any `401` means "sign in again". Errors are `{"detail": "a sentence a person can read"}` with a 4xx status.

## Today

`GET /api/today` →

```json
{
  "edition": {
    "day": "2026-10-20", "finished": false,
    "slots": [{"slot": 0, "game": "gist", "name": "Gist & Infer", "pillar": "u", "skill": "gist", "minutes": 2,
               "items": ["gist:p15393"], "done": false, "answered": 0, "scores": [], "source": "On Writing Well…"}],
    "recall": {"item": "gist:p361", "book": "…", "reference": "…", "key_points": ["…"], "mark": null}
  },
  "week": {"active": 1, "goal": 4, "days": [{"day": "2026-10-20", "answers": 0, "rest": false, "future": false, "today": true}]},
  "counts": {"editions": 1, "answers": 3, "passages": 1, "arguments": 1, "minutes_spoken": 0.0, "active_weeks": 1},
  "ratings": {"gist": {"rating": 1180, "n": 1, "calibrating": true}},
  "skills": {"gist": {"name": "Gist", "pillar": "u"}},
  "games": {"gist": {"name": "Gist & Infer", "skill": "gist", "lane": "graded", "minutes": 2, "blurb": "…"}}
}
```

- A slot is one game in today's edition. `items` is usually one id; Technique or Fair Move has six. Play a slot by passing `day` and `slot` with each answer, so it counts for today.
- `pillar` is `u` (Understand), `r` (Reason), `e` (Express) or `s` (Speak).
- `recall` is yesterday's passage, or `null`. Once it has a `mark`, don't show it again. `POST /api/today/recall` `{"answer": "what I remembered", "mark": "yes" | "partly" | "no"}`.
- `GET /api/nav` → `{"today": {"done", "total"}, "golden": {"n", "target"}, "bench_due": false, "week": {"active", "goal"}, "rest_weekday": 5}`, for a sidebar or menu bar.
- `GET /api/widget` is the at-a-glance version, for a home-screen widget or a menu bar ([below](#the-widget)).

## Practice

- `GET /api/practice` → `[{"game": "gist", "name", "skill", "lane", "minutes", "blurb", "live": 11}]`
- `GET /api/practice/{game}` → `{"items": ["gist:p…"]}`, picked so you'd get about 75% right. Six ids for `tech`. A `404` with a `detail` when there's nothing to play.

## Items

`GET /api/item/{id}` → the item without its key. Every item has `id`, `game`, `skill` and `source`. For items from my books, `source` is `{"book", "author", "chapter", "passage" or "sentence", "highlighted"}`; for the written-for-Binah ones it's `{"set": "technique"}` or `{"set": "jam topics"}`. Then, by game:

| Game | Fields | The answer you send |
| --- | --- | --- |
| `gist` Gist & Infer | `passage`, `inference_q` | `{"gist": "20 words or fewer", "inference": "…"}` |
| `subtext` | `passage`, `question` | `{"text": "…"}` |
| `bloat` Cut the Bloat | `padded`, `par` (the author's word count) | `{"text": "my cut"}` |
| `weak` Find the Weak Step | `passage`, `sentences` (the passage split into sentences; `"¶"` marks a paragraph break), `flaws` (the labels to choose from; `"none (sound)"` means it holds up) | `{"index": 3, "flaw": "false cause", "why": "optional, one line"}` (`index` may be `null` when the flaw is `"none (sound)"`) |
| `word` The Author's Word | `sentence` (with `_____` for the gap), `options` | `{"choice": "the word"}` |
| `tech` Technique or Fair Move? | `text`, `context`, `techniques` (the labels) | `{"kind": "technique" | "fair", "technique": "label" or null, "confidence": 50–100}` |
| `jam` Just a Minute | `topic`, `level`, `kind` | a recording, below |

## Answering

`POST /api/attempts` `{"item_id", "answer", "self_rating": 0–4 or null, "ms": time taken, "day": "YYYY-MM-DD" or null, "slot": 0 or null}` → an attempt:

```json
{"id": 41, "item_id": "weak:p4057", "game": "weak", "skill": "weak", "status": "done",
 "self_rating": null, "answer": {…}, "instant": {…}, "grade": null, "revision": null, "grade2": null,
 "score": 0.5, "score2": null, "rating_before": 1200, "rating_after": 1184, "revising": false, "disputed": null,
 "key": {…}}
```

- **Instant games** (`weak`, `word`, `tech`) come back `"status": "done"` with the score, the rating change and the `key`, all at once. `instant` holds what code scored:
  - weak: `{"score", "spot_ok", "flaw_ok", "key_index"}`, where `key_index` is the sentence the key points at (`null` when the argument is sound). If you sent a `why`, Claude reads it afterwards: poll until `grade` is set (or `grading_later` is true), which gives `{"reason": 0–4, "work_on"}`. That doesn't change the score.
  - word: `{"score"}`.
  - tech: `{"score", "kind_ok", "label_ok", "brier"}`.
- **Graded games** (`gist`, `subtext`, `bloat`, `jam`) come back `"status": "grading"`. Poll `GET /api/attempts/{id}` (every 1.5 s, then every 3 s) until the status is `done` or `later`. `later` means Claude couldn't grade it now: say so, don't invent a score, and offer the reference. Past the day's grading cap it turns `later` within a second or two, and the grade arrives the next day (the status then becomes `done`).
- **`grading_later`** (true or false) is on every attempt: a grade, a revision's grade or the feedback on a reason is waiting for tomorrow because of the cap. Stop polling when you see it.
  - The `grade` for gist has `main_idea`, `accuracy`, `concision`, `inference` (each 0–4), `covered` (which key points it got, counting from 1), `strength`, `work_on` and `hint`. Subtext has `inference`, `precision`, `strength`, `work_on` and `hint`. Bloat has `meaning`, `strength` and `work_on`, and its `instant` has `{"words", "par", "diff", "golf", "par_factor"}`. Every grade also carries `evidence`, which is Claude's own working, not for display.
  - Show `strength` and `work_on`. Show the criteria as chips (every integer field except `covered`). Show `hint` only before the revision.
- **One revision:** `POST /api/attempts/{id}/revise` `{"answer": {same shape}}`, allowed once and only when the status is `done`. Poll until `grade2` is set, or `grading_later` is true. `score2` is the revised score. The rating moves only on the first answer.
- **The reference:** the `key` appears on the attempt once it has been revised. To skip the revision, `POST /api/attempts/{id}/reveal` `{}` (status `done` or `later`) returns the attempt with its `key`. Keys by game:
  - gist `{"gist", "key_points", "inference_a"}`
  - subtext `{"answer", "evidence_quote"}`
  - bloat `{"original"}`
  - weak `{"quote", "flaw", "explain", "assumption", "conclusion"}`
  - word `{"target", "why", "sentence"}`
  - tech `{"kind", "technique", "tell", "why"}` (`tell` is the phrase that gives it away; highlight it in the text)
- **Disputing a grade:** `POST /api/attempts/{id}/dispute` `{"note": "…"}` sends it to the golden set's disputed list.

### Just a Minute (voice)

`POST /api/audio` as `multipart/form-data` with `item_id`, `day` (or empty), `slot` (or `-1`), `ms`, and `file`. The file must be at least 1 KB and at most 15 MB. The server decodes it with PyAV, which reads what's actually in the file, so the container doesn't really matter. AAC in MP4/M4A (`audio/mp4`, what Safari records), Opus in WebM or Ogg, and WAV all work, with 16 kHz or more and mono being plenty. Send the right `Content-Type` on the part anyway. The answer is an attempt with `"status": "grading"`. When it's `done`:

- `instant.metrics` has `words`, `speaking_time`, `wpm`, `wpm_speaking`, `fillers`, `fillers_per_min`, `filler_words`, `crutch`, `crutch_words`, `long_pauses`, `pauses`, `longest_pause`, `silence_ratio`, `first_sentence_clean`, `repeats` (`[{"word", "count"}]`) and `start_delay`.
- `instant.hesitation` and `instant.repetition` (0–4) are scored by code.
- `grade` has `deviation`, `structure` (0–4), `deviations` (the phrases that wandered), `strength` and `work_on`.
- `answer.text` is the transcript.

## Skills

`GET /api/skills` →

- `ratings` (`{skill: {"rating", "n", "calibrating"}}`) and `skills` (names and pillars).
- `recent` (`{skill: [scores 0–1, oldest first]}` for sparklines).
- `discern` (`{"n"}` alone, until there's enough; then `"dprime", "bias", "hit_rate", "false_alarms", "brier"`).
- `self_gap` (the average distance between the self-rating and the grade, on 0–4, or null), `bench_due`, `counts` and `week`.

## The golden set

- `GET /api/golden` → `{"report": {"target", "total", "games": {game: {"criteria": {criterion: {"n", "exact", "within1", "lenient", "qwk"}}}}}, "next": [item ids to score], "rubrics": {game: {"criteria": {criterion: ["what 0 means", …, "what 4 means"]}}}, "disputed": [attempts]}`
- Answer the item yourself first (same fields as above), then `GET /api/golden/key/{item_id}` → `{"key"}` to see the key, then `POST /api/golden` `{"item_id", "answer", "mine": {criterion: 0–4}}`. Claude grades the same answer blind in the background.

## The monthly benchmark

- `GET /api/benchmark` → `{"forms": [{"id", "created", "sections"}], "runs": [{"id", "form", "started", "finished", "results"}]}`
- `POST /api/benchmark/start` `{}` → `{"run", "form", "answers"}`. It continues an open sitting if there is one; otherwise it opens the next unused form (a `404` with a `detail` when none is left). The form comes without answers. Its sections, in order:
  - `argument` `{items: [{id, type, stimulus, stem, options[5]}]}`
  - `discern` `{items: [{id, text, context}]}`
  - `inference` `{passages: [{source, text, questions: [{id, stem, options[4]}]}]}`
  - `essay` `{prompt, minutes}` and `talk` `{prompt, seconds}`
  - `vocab` `{items: [{id, word, sentence, options[4]}]}`
- Save each answer as it's given: `POST /api/benchmark/{run}/answer` `{"key", "value"}`.
  - Multiple choice: `key` is `section:item_id`, `value` is `{"choice": index, "confidence": 20–100}`.
  - Fair or trick: `{"kind": "technique" | "fair", "confidence": 50–100}`.
  - The essay: key `essay`, value `{"text", "started": ms epoch, "done": bool}`. Save the draft as you go; `done` closes it.
  - Skipping the talk: key `talk`, value `{"skipped": true}`.
- `POST /api/benchmark/{run}/talk` (multipart, `file`) uploads the two-minute talk.
- `POST /api/benchmark/{run}/finish` `{}` → `{"run", "results"}`. `results` has per-section `{"right", "of"}`, `discern` (`hits`, `of_tricks`, `false_alarms`, `of_fair`, `dprime`, `bias`), `brier`, `essay` (`words`, `grade`) and `talk` (`grade`). The essay and talk grades arrive later, so poll the next call until they're filled in, or show `{"failed": true}` as "couldn't grade".
- `GET /api/benchmark/{run}` (after finishing) → `{"form" (with answers and explanations), "answers", "results", "started", "finished"}`, for the review. A form is never sat twice.

## Settings and the rest

- `GET /api/settings` → `{"weekly_goal_days", "rest_weekday" (0 = Monday … 6, or null), "grading_tone" ("soft" | "balanced" | "strict")}`; `POST /api/settings` with any of those.

## Devices

- `POST /api/devices` `{"name": "android-sm-s926u"}` with the cookie → `{"name", "token"}`. The token is shown only this once, so keep it in the Keychain (Mac) or encrypted storage (Android). Posting the same name again replaces that device's token. The apps name themselves `mac` and `android-<model>`, so two phones don't replace each other's token.
- `GET /api/devices` → `[{"name", "created", "last_seen"}]` (seconds since 1970). Settings in the web app lists them.
- `DELETE /api/devices/{name}` disconnects one. A changed password signs out every browser but leaves device tokens alone.

## The widget

`GET /api/widget` (bearer) →

```json
{"day": "2026-10-19", "done": 1, "total": 3, "finished": false, "minutes_left": 3,
 "next": {"game": "weak", "name": "Find the Weak Step"}, "week": {"active": 2, "goal": 4},
 "url": "https://binah.tiresia.xyz/#today", "deeplink": "binah://go/today"}
```

Poll it gently: once when the widget is shown, at most every 15 minutes in the background, and once after the app comes to the front.

## Train on this

`POST /api/save` with either `{"url": "https://…", "title": "…"}` or `{"text": "a paragraph or more", "title": "…"}` → `{"ok": true, "id": 12, "open": "today", "message": "Saved for later. Binah doesn't turn saved passages into practice yet."}`. Show the message. Text under 20 words without a URL is refused with a `400` and a plain message.

## Deep links

The apps open `binah://go/<room>`, where a room is `today`, `practice`, `skills`, `golden`, `bench` or `settings`, for example `binah://go/practice`. On the web the same rooms are the page's hash routes (`/#practice`).
