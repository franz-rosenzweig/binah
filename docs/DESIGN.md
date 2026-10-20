# Binah — design

Binah is my training app for understanding what I read, weighing what I hear, and saying what I mean. It's phone first (my Android), with a proper Mac app for the longer work, and it lives at a public address with a sign-in, the same way Daf does. The name is the Hebrew word for understanding, which is basically the whole point.

This document is the plan. The research behind it is in a private research report, *Binah games and learning science* (about 7,000 words, 183 sources), and the passage engine that mines my own books is described in [`ENGINE.md`](ENGINE.md).

## What the research changed

I started out picturing a Lumosity for language. The research talked me out of that, and I think it's right. Brain games make you better at the brain games and not much else, so every game in Binah has to be a small, honest slice of the REAL skill, done on real text: I summarize an actual passage, I find the actual weak step in an actual argument, I cut an actual padded sentence back down, I talk for an actual minute.

The second thing it changed is where the effort goes. The games are the easy part. What makes or breaks an app like this is whether I trust the grades, so the hidden answer keys, the blind checking of every generated item, my own hand-scored "golden set" of answers, and a sealed monthly benchmark matter more than any single game. One wrong grade on something I worked hard at costs more than a missing game.

The third thing is the motivation design. The research says the same things that work for me personally (finite, forgiving, story-driven, no streak to break) are also what works in general, which is a nice surprise. So there are no streaks, no points for opening the app, no leagues, and no "brain age". There's a short daily edition, a weekly case, a season with a story, and a skill map that tells the truth.

## The three pillars

Everything I train sits under one of three pillars, and each pillar has a handful of skills. Each skill has its own rating.

| Pillar | Skills | What it means in practice |
|---|---|---|
| **Understand** | Gist, Inference, Structure, Listening | Get the point, read what's implied, see how a piece is built, hold onto what I heard |
| **Reason** | Weak steps, Hidden premises, Manipulation vs fair moves, Calibration, Steelmanning | Find where an argument breaks, say what it quietly assumes, tell a trick from a fair move, know how sure to be, state the other side fairly |
| **Express** | Concision, Precision, Clarity, Fluency | Fewer words, the exact word, explain it so a newcomer gets it, speak on the spot in order |

## The games

These are the games worth building, with where each one comes from. The ones marked FIRST are the first three the research recommends, and the ones marked LIBRARY run on passages the engine mines from my own books.

### Understand

- **Gist & Infer** (FIRST, LIBRARY). I read a 150–250 word passage at my own pace, then write its main point in 20 words or fewer from memory, then answer one bridging question whose answer is implied and never stated, with a confidence. Claude grades the gist against hidden key points, and the confidence gets a Brier score. Built from Kintsch's situation model and Quill's Reading for Evidence.
- **Relay.** I squeeze a passage into one sentence, and a separate Claude call rebuilds the passage from my sentence alone. My score is how many of the key points survived the trip. It's the telephone game, and it punishes vague summaries automatically.
- **Fill the Story.** Three short documents and a summary with blanks. I tap names and verbs into the blanks, and a sentence only locks when every word in it is right, with a "two or fewer wrong" hint. Scored by code. Borrowed from The Case of the Golden Idol and Return of the Obra Dinn, which use exactly this to stop guessing.
- **Objection!** A witness statement and a few evidence cards. I pair the statement with the card that breaks it and say why in one line. Code checks the pair and Claude checks the reason. Straight from Ace Attorney.
- **Subtext** (LIBRARY). A scene, mostly dialogue, from a novel I own. "What's really going on?" in one line, then I tap the line that gives it away. This is the Public Scribe mechanic, and the engine finds dialogue-heavy scenes for it.
- **Blueprint** (LIBRARY). A paragraph arrives with its sentences shuffled. I put them back and label each one (claim, reason, example, turn). Scored by code.
- **Listen.** A passage read aloud once by the same Kokoro voice Daf uses, no replay, then questions. Later.

### Reason

- **Technique or Fair Move?** (FIRST). Half the items use a manipulation technique and half use the same move legitimately, and I call each one. It's scored by code as discernment (d′), with my bias shown separately, because the research found that misinformation games with only fake items just teach you to call everything fake.
- **Clarify, Back, Relevant.** An opponent's argument, one step at a time. For each step I can ask what it means, what backs it, or why it's relevant, and asking never costs points. Then I write or say one challenge and Claude grades it. This is Socrates Jones's design, and it's the strongest critical-thinking template the research found.
- **Find the Weak Step** (LIBRARY). A real argument from one of my books. I tap the sentence where the reasoning is weakest and say why in a line, or I say it's sound, because about a quarter of these should be sound. Claude drafted the key the night before and a second, blind pass agreed with it.
- **Argument Gym.** LSAT-style: I write the hidden assumption or the strongest weakener in one sentence, plus a confidence. Accuracy is tracked by question type, the way 7Sage does it.
- **Silent Rule.** A hidden rule, written as code. I test sentences against it, then state the rule in words, and my wording gets tested on held-out cases. A vague rule fails on the edge cases, so precise wording is what scores. From Zendo and Eleusis.
- **Calibrate.** A confidence wager sits on top of most games (Jeopardy-style), scored with a Brier score, so calibration trains on the side. There's also a standalone version for warm-ups.
- **Lateral Reading** (Mac). A claim and a source, and the task is to leave the page and check who's behind it. Short and very effective in the research. It belongs on the Mac.

### Express

- **Cut the Bloat** (LIBRARY). A padded paragraph, cut by about 30% without losing meaning. Code counts the words and Claude checks the meaning survived. The library twist is that the padded version is a real sentence from a good writer that Claude inflated overnight, so par is the AUTHOR'S word count and the answer key is the author's own line.
- **The Author's Word** (LIBRARY). A sentence from one of my books with one precise word blanked out, plus four near-synonym decoys. I pick the author's word, then see why it was right. It's instant, and the engine picks words that are moderately rare and actually choosable.
- **Decrypto Duel / Wavelength.** I give clues an AI teammate can decode but an AI interceptor can't, or I clue a point on a spectrum for an AI listener. Scored by the AI listener's guesses and how sure it was. This trains precision relative to a listener, which is what translation actually is.
- **Pass as Them.** I defend a view I reject in 120 words, and a judge persona tries to spot mine among three genuine answers. The Ideological Turing Test, as a game.
- **Combine** (because / but / so). Quill's best activity: complete the same stem three ways with evidence from the passage. Sentence combining has good evidence for writing.

### Speak

- **Just a Minute** (FIRST). Talk for 60 seconds on a topic without hesitation, repetition or deviation, like the BBC Radio 4 show. Pauses come from voice detection, repetition is counted by code, and only deviation needs Claude. In challenge mode I catch the faults planted in an AI speaker's minute.
- **Table Topics with a follow-up.** Pick one of three prompts, 30 seconds to plan, 90 to answer, then one follow-up question, Toastmasters style. Feedback is one strength and one thing to work on.
- **Teach the Novice.** I explain a passage or idea to an AI "novice" who holds one to three hidden misconceptions, and Claude checks which ones I actually cleared up.
- **Sight Summary** (Hebrew, later). Read a Hebrew paragraph, summarize it aloud in English. Nobody has tested this exact format, but it's what bilingual readers do all day.

### What I'm leaving out, on purpose

No speed reading or one-word-at-a-time reading (it hurts comprehension), no "name the Latin fallacy" quizzes (humans can't even agree on the labels), no misinformation games with only fake items, no vague tone buttons like L.A. Noire, no Werewolf or Avalon, no leagues, and no n-back or pattern matrices.

## A day, a week, a season

**The daily edition** is the heart of it, and it's FINITE: five to eight minutes, and then it says "Today's edition is done." It opens with a quick recall card on yesterday's passage before I see it again, then one Understand game, one Reason game, and one Express or Speak game, then one insight and a line about tomorrow's case. Past editions never expire, so missing a day costs nothing.

Inside every open answer the order is fixed: I answer, I rate myself 0 to 4, I see Claude's verdict with one prioritised point and a hint, I revise once, and only then do I see the reference answer. The research is clear that the learning lives in the revision, not in the comment, and tracking the gap between my self-rating and Claude's grade gives me something visible to shrink.

**The weekly case** is 20 to 40 minutes of deliberate practice, rotating between four formats: a Franklin reconstruction (keyword notes on a model essay, rewrite it from the notes two days later, compare line by line), mapping a real op-ed and writing a rebuttal, Teach It (explain something aloud for three minutes, then two follow-ups), and a Socratic or double-crux session. This is where the Mac app earns its place.

**The monthly benchmark** is a sealed test I never practise on (see "Measuring real progress" below).

**Seasons** run four to six weeks, with a story that ties the items together, because I finish serialized fiction and I drift away from curricula. The exercises are the plot's verbs: the reading items are documents in the case, the reasoning items are flaws in a witness's argument, the writing items are the summary I hand in. Season 1 can be the Public Scribe (San Bartolo, 1957, the folding table under the arcade), since that prototype already exists. Each episode ends on an open question, and the next one waits with no countdown. The season arcs are written by hand, and generation only fills the items inside them.

## Keeping me coming back without nagging

These are rules, not suggestions:

1. A **weekly rhythm goal** that I set (say four days out of seven), with Shabbat counting as on track. No daily streak.
2. **Counts that only go up** ("Cases solved: 143"). If a run length shows at all, it repairs silently.
3. No points for opening the app or for minutes spent. The reward is specific feedback about my reasoning.
4. **One reminder at most**, opt-in, tied to the morning edition on the desk ("After I read the morning edition, I do today's Binah"), and it offers to switch itself off after a few steady weeks.
5. After a gap, "Welcome back, here's a three-minute case to pick up the thread." Never "you broke your streak."
6. No wagers, countdowns, sad mascots, expiring content or fake urgency.
7. Every grade has an "I think this is wrong" button that triggers a regrade and feeds my golden set.
8. No claims anywhere that Binah makes me smarter. It makes me better at the moves I practise, on the kinds of text I read.
9. One tap to pause, and everything I write exports to the vault.
10. If friends join later: the same daily case for everyone, a spoiler-free share card like Wordle's, cooperative goals, and no leaderboards.

## Ratings and difficulty

Each skill has an Elo-style rating, and so does every item. When I play an item, both move: mine up and the item's down if I do better than expected, and the reverse if I do worse. Open answers count as partial credit, with the rubric score from 0 to 1 as the result. The update size shrinks as answers pile up, U(n) = 1 / (1 + 0.05n), which is Pelánek's setup, and uncertainty grows a little with each day away so a few answers re-place me quickly after a gap.

The engine aims for an expected score of about 75%, which is what Math Garden uses. It goes up to 85% in the first two weeks or on a tired day, down to 65% for the weekly case, and it slips in an easier item after two low scores in a row. A rating shows "calibrating" until it settles, and "Mastered" can only be earned on a mixed-skill check, with demotion when I miss, the way Khan Academy does it.

Because I'm one user, items don't get played enough to rate themselves from scratch, so every item starts from the passage engine's difficulty estimate (see ENGINE.md) and updates gently while my rating moves faster.

Spaced review comes from FSRS (py-fsrs on the server). The "cards" are skill categories, not facts: a false choice, a buried claim, a register shift. Every review draws a fresh example, and Binah maps Claude's grade to the four FSRS buttons itself so I never have to. Each category comes back at roughly one, two and four weeks, because the research found boosters are what make gains last.

## Grading

Grading runs in two lanes:

- The **keyed lane** (a gist against key points, a weak step's location and reason, a hidden assumption) is where Claude grades about as well as a person, so a fast model does it.
- The **open lane** (how strong a steelman is, how persuasive a spoken answer is) is noisy. It gets graded twice, with a third pass if the two disagree by more than a point. The middle score counts, and it moves my rating less.

Every task type has an analytic rubric scored one criterion at a time, returned as JSON in the order evidence, then rationale, then score. The grader gets the item's hidden key plus three to five anchor answers I scored myself, low, middle and high, which is the single biggest lever in the research. Hard length caps keep wordiness from paying, and I see bands and comments, never decimals.

Feedback is one strength and one thing to work on, content before mechanics, with a named move and a tiny example ("hedge stacking: 'it could perhaps be argued' → 'arguably'"). It never says "you're a strong writer." There's a strictness dial (soft, balanced, strict).

Everything goes through one wrapper (`binah/claude_cli.py`). It runs `claude -p` on my subscription with tools, settings, MCP and session history switched off, from an empty folder, with our own short system prompt instead of the default one. It insists on `structured_output` and retries once, because the CLI can report success without it. If both tries fail, I see "grading later" instead of a made-up score. The model is pinned and saved next to every grade.

The golden set comes FIRST. Before I build anything else, I write 50 answers across the first three games and score them by hand. That set gets re-run every week and whenever the model changes, with agreement and leniency tracked, and it tells me whether Claude's grades deserve my trust.

## Where the passages come from

There are two pools, kept strictly apart:

- **My private pool** is my own books (Calibre), my Daf highlights, and the articles I save in FreshRSS and Karakeep. This is copyrighted material, so it only ever appears in MY account, behind the sign-in, never in a shared pool and never on a cached public path.
- **The public pool** is public-domain books (Standard Ebooks, Project Gutenberg with its name stripped), US government text, Wikinews, Wikidata and Our World in Data, plus a few CC0 or CC BY argument sets (Argotario, args.me, IBM debate speeches). If friends ever join, this is all they see.

Every item carries a `license` field and a `visibility` field from the moment it's generated, and the public generator can only read safe sources. The research-only datasets (RACE, ReClor, LogiQA, LOGIC, MAFALDA) are useful for item FORMATS, never for text. Some of my own books are actually public domain (The Federalist Papers, the Bernard translation of Kant's Critique of Judgement), so the engine flags those as candidates for the public pool once I've checked the edition.

The engine that mines my books is in `engine/` and described in ENGINE.md. The short version is that it measures every passage in my library with cheap, explainable numbers (difficulty, rare words, argument density, dialogue, how self-contained it is), picks the best candidates for each game, then has Claude draft items from only those and a different model check them blind.

## Speech

Speech is turn-based voice notes, not live calls. Grading takes a few seconds, and the best commercial designs (Duolingo's Video Call, Speak) work that way anyway.

The web app records with the standard browser APIs, and the native Mac and Android apps record with their own and upload the file the same way. The server transcribes with faster-whisper small.en, which took about 7 to 10 seconds for a 60-second answer on my server's CPU. It does two passes: a plain one for the text Claude grades, and one with a disfluent style prompt for counting fillers. The second pass gets thrown out if it's under 90% of the first one's word count, because that prompt once made a model drop a whole opening. Pauses come from voice detection, not from the gaps between Whisper's words.

The target is not zero fillers, since short, well-placed fillers actually help listeners. What I'm after is a clean first sentence, fewer long pauses in the middle of a clause, and a steady pace compared with my own baseline. Claude gets the clean transcript plus a small JSON of numbers, never the audio.

## Measuring real progress

In-game scores will climb two to five times faster than my real skill, and that's normal. So the honest number comes from a sealed benchmark: about six parallel forms of roughly 40 items that never appear in training. Each form has LSAT-style argument items, technique discernment with equal numbers of manipulative and fair items, inference on unseen passages, a confidence on every item, a 15-minute essay on a frozen rubric, a two-minute impromptu talk, and a vocabulary probe. It runs every four to six weeks, with two or three baseline runs before daily use so I can see how much of any later gain is just getting used to the test. Each run includes one held-out field (legal or science abstracts if I train on op-eds), which is the closest Binah gets to measuring transfer.

The progress screen keeps two tracks apart, practice scores and benchmark scores, and shows changes with their uncertainty ("+0.3 SD, could be anywhere from −0.1 to +0.7"). For one person, a single before and after needs a change of about 1.24 SD to count as real, so the trend over many sittings is what matters. Every few months, an editor colleague blind-scoring a sample of essays is the check on the checker.

Instead of app-style stats, I track active weeks out of the last eight, how long it takes me to come back after a gap, whether I finished the season, skill change per season, and a monthly "was this worth your time?".

## How it's built

Binah follows Daf's shape, because Daf works:

- **Server:** a Python FastAPI app running as a systemd user unit on my home server, like Daf. Running on the host (not in a container) means it can call the Claude CLI directly, read Calibre and Daf read-only, and run faster-whisper in-process. State lives in `/srv/docker/binah` (SQLite, settings, auth), separate from the source.
- **Web app:** vanilla JS with ES modules and no build step, like Daf, with a service worker so item packs for the instant games work offline and answers queue up when I'm on the train.
- **Apps:** native on both, over the same JSON API. The Mac app is SwiftUI, with a menu bar and Train on This in the Services menu. The Android app is Kotlin and Jetpack Compose, with haptics, a home-screen widget for today's edition, and a share target, so I can send a passage from anywhere and say "train on this". (They started as WebView shells built from Daf's, and went native in October 2026.)
- **Address:** binah.tiresia.xyz through the host cloudflared, with username and password sign-in like Daf (login throttle, Signal alert on attempts).
- **Grading:** an in-process job queue in SQLite, worked by a thread that calls `claude_cli.ask`, two or three at a time.
- **Nightly:** a timer at 03:00 that generates and validates items for both pools, retires stale ones, and re-runs the golden set weekly. It stays inside a fixed window and a hard call cap, so it never eats into my daytime Claude use.
- **Speech:** faster-whisper small.en resident in the server process, with Silero VAD.
- **Listening:** the Kokoro voice that Daf already uses.
- **Vault:** everything I write goes to `Notes/Binah/` as dated Markdown, plus a running commonplace book of my best lines. "File over app" for the writing, like Dvarim.
- **My dashboard and assistant:** a card on my morning page ("Today's Binah: 3 games, about 6 minutes"), and a Sunday report by message.
- **Daf:** Binah reads Daf's highlights and current book read-only, so a week's passages can come from what I'm actually reading. Later, Daf's highlight toolbar gets a "Train on this" action.

If friends sign in later, every graded answer they submit draws on MY Claude subscription limits. So friends get the instant games freely, graded games under a small daily cap, and only the public pool.

### Data model

| Table | Holds |
|---|---|
| `item` | One playable item: game, pool, license, visibility, payload, hidden key, rating and uncertainty, source passage, status (draft, live, retired) |
| `passage` | Mined text with its measurements and fit scores (private pool, in `STATE/engine/passages.db`) |
| `attempt` | My answer, time taken, self-rating, counted scores, the grade JSON, final 0–1 score, ratings before the update, model id |
| `rating` | One row per skill: rating, uncertainty, attempts |
| `card` | FSRS state per skill category |
| `session` | A daily edition, weekly case or benchmark: planned items, start, finish |
| `job` | Grading, generation and validation work: status, tries, result |
| `golden` | My hand-scored anchor answers per game and rubric version |
| `benchmark` | Sealed forms and results, stamped with the rubric and model that scored them |

## Build order

The gate between phases is USE, not code. If a phase isn't being played, the next one doesn't get built.

1. **Groundwork (one weekend).** The grading wrapper, the golden set (50 answers I score by hand), one benchmark form, and two or three baseline runs.
2. **The first edition.** Gist & Infer, Technique or Fair Move, and Just a Minute, in a daily edition with ratings, the revise-once loop, and items from the passage engine. Done when I've played it on four days a week for two weeks.
3. **The week and the story.** The weekly case, Season 1, FSRS boosters, and the library games (Find the Weak Step, The Author's Word, Cut the Bloat, Subtext).
4. **More voice.** Table Topics, Teach the Novice, and the Just a Minute challenge mode.
5. **The Mac's deep work.** Argument mapping, lateral reading, Franklin reconstructions.
6. **Later, if it's earned.** Friends with caps, Hebrew (Ben-Yehuda, Sefaria filtered by license, a Hebrew Whisper model, Sight Summary), more seasons.

## Still open

- Which season story first: the Public Scribe, or something new like a junior examiner at an archive?
- How strict should the default grading tone be?
- Should Daf's "Train on this" go in early, since it's cheap?
- When friends come, do they get graded games at all, or instant games only?
