# The passage engine

The passage engine is how Binah gets its reading material out of my own books. It goes through my Calibre library, measures every passage with simple numbers anyone can check, picks the best candidates for each game, and only then hands those few to Claude to turn into items. A second, different model then checks Claude's work blind.

Basically, the cheap measuring does the sifting, and the expensive judgment only touches the top of the pile.

## What it reads, and what it leaves alone

It reads a Calibre library (its path is in the private `settings.json`) and, if you use Daf, Daf's highlights, both READ-ONLY. It never writes to either one.

It skips any book Daf marks private, and any book whose title or tags contain a term from the private list (`private_terms` in settings, plus Daf's `private_titles`), so nothing personal ever shows up anywhere in Binah. It also skips books that aren't in English for now (Hebrew comes later).

Everything it produces goes to `STATE/engine/passages.db` (STATE is `/srv/docker/binah` by default). It holds copyrighted text from my own books, so it lives outside the repo and is never served publicly.

## How it works

1. **Extract** (`engine/epub.py`). An EPUB is a zip of web pages plus a file that gives the reading order. The extractor walks that order, keeps paragraphs and headings, drops footnote markers, scripts and navigation, and tags each part as front matter, body or back matter, so copyright pages, contents, notes, indexes and acknowledgments are skipped. It uses only the standard library.
2. **Cut** (`engine/mine.py`). Inside each chapter it slides a window over the paragraphs and keeps passages of 80 to 340 words (one to four paragraphs), skipping junk like ISBN lines and numbered notes. It also pulls out single sentences for the sentence games.
3. **Measure** (`engine/features.py`). Every passage gets a set of numbers:
   - **readability:** Flesch-Kincaid grade, plus average and longest sentence length
   - **rare words:** each content word's frequency in everyday English, from the `wordfreq` library
   - **argument density:** connectives per 100 words, in families (because/therefore, but/however, admittedly, should/must, for example, in short) plus hedges
   - **dialogue share:** how much of the passage sits inside quotation marks
   - **self-containment:** whether it opens with "He", "This", "But" and the like, which point back to text the reader can't see, and whether it ends cleanly
   - **abstraction:** the rate of words like "-tion", "-ness", "-ity"
   - **tense and person:** past against present, and I, we or you
   - **proper nouns and digits**

   From those it decides what kind of passage it is (argument, exposition, narrative or dialogue) and gives it a difficulty from 0 to 100. That difficulty becomes the item's starting rating, from 800 for easy to 1600 for dense, before play calibrates it.
4. **Score fit** (`features.fits`). Each game gets a fit score from 0 to 1.2:
   - **Gist:** 140–230 words, self-contained, explaining or arguing, little dialogue.
   - **Argument:** an actual argument, dense in claims and reasons.
   - **Subtext:** a scene that's 30–75% dialogue.
   - **Blueprint:** five to seven linked sentences.
   - **Listen:** readable aloud, few names and numbers.

   A passage I highlighted in Daf gets a 15% boost, because I already found it worth marking.
5. **Sentence games.** For "The Author's Word" the engine finds the most choosable word in a sentence: lower-case, at least five letters, and moderately rare (Zipf 2.4 to 4.0, which means words like "appease", "expanse", "synchronized"). For "Cut the Bloat" it finds tight sentences, the ones where most of the words carry meaning.
6. **Book cards** (`engine/rate.py books`). Claude writes a short card for each top book from what it already knows: fiction or nonfiction, the author's voice, a difficulty guess, which games the book suits, and up to four well-known or especially teachable passages, with their opening words quoted as exactly as it can recall them. The engine then FINDS those passages in my actual copy by matching overlapping four-word chunks. Located passages become editor's picks.
7. **Item drafts** (`engine/rate.py items`). Claude gets the top candidates for each game, spread across books and difficulty bands, in batches of 8 to 12, and drafts real items:
   - **Gist:** a gist, 3–5 key points and a bridging-inference question with its answer.
   - **Argument:** the conclusion, the premises, the exact weakest step, a flaw label from a fixed everyday list (including "none (sound)"), and the hidden assumption.
   - **Subtext:** a specific "what's really going on?" question, the answer, and the line that gives it away.
   - **The Author's Word:** four near-synonym decoys.
   - **Cut the Bloat:** a padded version about 1.7 times as long.

   Each draft gets a verdict (use, maybe or reject), and Claude is told to be strict.
8. **Blind check** (`engine/rate.py validate`). A different model tier (Sonnet) solves the same argument and gist items without seeing the drafts. For arguments, the engine compares the two answers mechanically: do the weak-step quotes overlap, and do the flaw labels match? For gists, a third call judges whether the two gists make the same point. Only items where the two agree go live.
9. **Export** (`engine/export.py`). Everything goes out as one JSON file for the explorer page.

## Running it

```
.venv/bin/python engine/mine.py               # measure the whole library (about 30 seconds)
.venv/bin/python engine/rate.py all           # book cards, drafts, blind check (Claude, batched)
.venv/bin/python engine/export.py > /srv/docker/binah/engine/explorer.json
```

`mine.py --limit 5` or `--only "Federalist"` runs a quick test. `rate.py` takes `books`, `items` or `validate` to run one stage.

Every Claude call goes through `binah/claude_cli.py`:

- It uses `claude -p` on my subscription, NOT `--bare`, which needs an API key.
- Tools, settings, MCP and session history are switched off, and it runs from an empty folder.
- Our own short system prompt replaces the default one, which saves a lot of tokens per call.
- It requires `structured_output` and retries once.
- The model comes from settings (`model`, or `CLAUDE_MODEL` in the env file that `model_env_file` points to, so one setting can serve several tools). The blind checker is pinned to a different tier on purpose.

## First run (19 October 2026)

- **Library:** 165 English EPUBs went in and 25 private books were skipped up front. Five more came out afterwards when I extended the private list (`engine/purge.py` removes them from what's already mined). That left **160 books, 132,698 candidate passages and 139,392 candidate sentences**, measured in about 30 seconds on my home server, with no book failing to parse. 317 passages contain one of my Daf highlights.
- **Mix:** 44% exposition, 33% narrative, 14% dialogue, 9% argument.
- **Sanity check:**
  - densest: Kant's Critique of Judgement, How Poems Get Made, The Federalist Papers
  - easiest: Killing Floor, The Perks of Being a Wallflower
  - most argumentative: Kant, Mastering Logical Fallacies, Julia Driver's Ethics
  - most dialogue: The Last Wish, A Wind in the Door, Shōgun

  That's what you'd expect, which tells me the numbers measure something real.
- **Book cards:** 30 books in 5 calls. Claude recalled 32 well-known passages and the engine found **24 of them in my actual copies**, almost all word for word (Thinking, Fast and Slow 4 of 4, Justice 3 of 3, 12 Rules 3 of 3, Federalist 3 of 4).
- **Drafts:** 12 calls, strict verdicts:

  | Game | Use | Maybe | Reject |
  |---|---|---|---|
  | Gist | 17 | 3 | 2 |
  | Argument | 9 | 5 | 8 |
  | Subtext | 7 | — | 9 |
  | Author's Word | 6 | 10 | 7 |
  | Cut the Bloat | 9 | 7 | 7 |

  Basically, the measuring is already good at finding gist passages and weak at finding real subtext, since dialogue share alone doesn't mean a scene has something unsaid. The word picker for The Author's Word needs work too.
- **Blind check (Sonnet):**
  - gists: 13 agreed, 7 partly, none disagreed
  - arguments: 7 agreed, 5 partly, 2 disagreed

  Only full agreements go live.
- **Cost:** 25 Claude calls and about 14 minutes of model time on my subscription, all batched.

## What to improve next

- **Subtext:** look for scenes where dialogue meets a gap. Hedges, questions that go unanswered, a character saying less than the narration shows. Then let Claude pre-screen a bigger pool cheaply.
- **The Author's Word:** prefer verbs and adjectives over nouns, check that the word has real near-synonyms (Open English WordNet), and skip words that only fit one way.
- **Book cards:** search all of a book's passages for the recalled quotes, not just the mined windows, so famous single sentences get found too.
- **Public domain:** add a public-domain flag. The Federalist Papers and the 1892 Bernard translation of Kant are candidates for the public pool.
- **Daily sampling:** sample the daily edition from what I'm reading in Daf this week, not just the global top.
