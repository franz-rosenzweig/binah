"""Sealed benchmark forms.

The monthly benchmark is a test I never practise on, so its forms are written
to the private state folder (config.BENCH_DIR / "forms"), never to the repo,
and this script prints only counts and pass rates, never an item.

    .venv/bin/python -m binah.benchgen --forms 3

A form has six sections: argument (LSAT-style logical reasoning), discern
(technique or fair move), inference (questions on public-domain essays),
essay, talk and vocab. Every multiple-choice item is drafted by the main model
and kept only if a different model, answering blind, picks the same key.
Inference questions must also fail a no-passage check: shown only the
question and its options (twice, in two different orders), the validator
must not find the key both times.

The essays are downloaded once from Project Gutenberg into
config.BENCH_DIR / "sources" and reused. Every passage sent to Claude is
recorded there too, so later forms always get fresh ones.

Drafts and blind answers are cached in config.BENCH_DIR / "work" while a run
is going, so a crash can be resumed without paying for the same calls twice.
The cache is deleted once the forms are written.

The technique definitions and the drafting and checking helpers here are
also used by tools/gen_content.py for the practice items in content/.
"""
import argparse
import concurrent.futures
import datetime
import json
import math
import random
import re
import shutil
import threading
import time
import urllib.request

from . import claude_cli, config

FORMS_DIR = config.BENCH_DIR / "forms"
SOURCES_DIR = config.BENCH_DIR / "sources"
WORK_DIR = config.BENCH_DIR / "work"
USED_PATH = SOURCES_DIR / "used.json"
TECHNIQUE_FILE = config.CONTENT_DIR / "technique.json"

LETTERS = "ABCDE"
PARALLEL = 3          # Claude calls in flight at once; the subscription is shared
FORM_VERSION = 1

# Per form.
N_ARGUMENT, N_DISCERN, N_PASSAGES, N_QUESTIONS, N_VOCAB = 8, 8, 2, 3, 6

# ---------------------------------------------------------------- shared text

TECHNIQUES = {
    "emotional manipulation": (
        "stirs fear, outrage, pity, guilt or flattery out of proportion to the facts given, "
        "or in place of them, to push a belief or an action",
        "strong feeling that the stated facts warrant: the emotion is proportionate, and the "
        "concrete facts that justify it are right there in the text"),
    "false choice": (
        "presents two options as the only ones when others plainly exist",
        "a genuinely binary choice: the situation really allows only two options (a yes-or-no "
        "ballot question, a deadline with exactly two real outcomes)"),
    "scapegoating": (
        "blames a person or group for a problem they did not cause, or caused only in small "
        "part, without evidence; often a convenient outsider",
        "blames the party actually responsible and gives the evidence that ties them to it"),
    "fake or irrelevant expert": (
        "leans on an authority who is vague ('scientists say'), unqualified, self-styled, or "
        "an expert in an unrelated field",
        "cites a relevant expert speaking within their own field, ideally with the basis for "
        "the claim"),
    "attack on the person": (
        "attacks someone's character, looks, background or motives instead of their argument",
        "criticises someone's documented conduct when that conduct is exactly the point at "
        "issue (a treasurer candidate's record of misused funds)"),
    "cherry-picking": (
        "picks the convenient slice of the data (one good month, one study, the best case) and "
        "hides the baseline or the full picture",
        "gives a representative statistic together with its baseline or comparison, so the "
        "number can be judged"),
    "slippery slope": (
        "claims one modest step will inevitably lead, through a chain of unsupported steps, to "
        "an extreme outcome",
        "lays out a causal chain where each step is backed by evidence or precedent, and the "
        "conclusion stays proportionate"),
    "conspiracy framing": (
        "implies hidden, coordinated plotting by powerful insiders, often unfalsifiable "
        "('they don't want you to know'), with no documentation",
        "points to real, documented coordination: a court finding, published minutes, a "
        "settlement, confirmed records"),
}
LABELS = list(TECHNIQUES)

TOPICS = ["health", "money", "tech", "local politics", "sport", "food", "science",
          "consumer goods", "workplace", "environment", "education", "housing", "transport",
          "pets", "travel", "arts"]
GENRES = ["a headline", "an ad line", "a social post", "a line from a speech", "an op-ed sentence",
          "a product review", "a fundraising email", "a newsletter", "a company memo",
          "a comment under an article", "a flyer", "a podcast blurb"]

SAFE_RULES = (
    "Everything you write must be original and fictional. Invent every name: people, towns, "
    "companies, products, brands, teams, parties and organisations. Never name a real living "
    "person, a real company or brand, a real product or a real political party, and never quote "
    "real text. Keep away from sensitive or painful subjects (violence, abuse, suicide, "
    "self-harm, eating disorders, alcohol, drugs, gambling, addiction, religion, race).")

DRAFT_SYSTEM = ("You write original, carefully checked items for a reading and reasoning "
                "training app. You follow counts, length limits and formats exactly.")
CHECK_SYSTEM = ("You are a careful test-taker. Answer every item on its own merits, "
                "exactly in the format asked.")


def technique_defs():
    return "\n".join(f"- {name}\n    technique: {t}\n    fair counterpart: {f}"
                     for name, (t, f) in TECHNIQUES.items())


def technique_prompt(counts, political=0, avoid=""):
    """Prompt for technique-or-fair items. counts: {label: (n_technique, n_fair)}."""
    want = "\n".join(f"- {label}: {nt} technique + {nf} fair" for label, (nt, nf) in counts.items())
    total = sum(nt + nf for nt, nf in counts.values())
    politics = (f"Exactly {political} items should be left-coded and {political} right-coded "
                "(their message would mostly appeal to one side), spread across both kinds and "
                "all the techniques, so each side gets both technique and fair items and neither "
                "looks like the only manipulator. The rest are apolitical."
                if political else "Keep most items apolitical; any political ones must balance "
                "left- and right-coded.")
    return f"""You are writing items for "Technique or Fair Move?", a game that trains people to tell manipulation from fair persuasion.

Research on misinformation games found that when every item is fake, players just learn to call everything fake. So half the items USE a manipulation technique, and the other half make a structurally similar move LEGITIMATELY. The fair items must look tempting: they share the surface features of the technique (strong feeling, two options, a named culprit, an expert, criticism of a person, a statistic, a chain of consequences, a claim of coordination), but the snippet itself contains what makes the move fair, so a careful reader can tell.

The techniques and their fair counterparts:
{technique_defs()}

Write exactly these {total} items:
{want}

Fields for each item:
- text: 1 to 3 sentences, realistic, as it would appear in the world: {", ".join(GENRES)}. Vary the genre and the sentence shapes.
- context: where it appears, short, e.g. "A headline", "From a city council speech", "A product review", "A fundraising email".
- kind: "technique" or "fair".
- technique: the label from the list (for a fair item, the technique it resembles).
- tell: the words that give it away or show it's fair, AT MOST 12 words, quoted exactly from the text where possible.
- why: AT MOST 35 words of plain English saying what makes it manipulative or what makes it fair.
- topic: one of {", ".join(TOPICS)}.
- lean: "left", "right" or "none".

Rules:
- Technique items are realistic, not cartoonish, and a careful reader should see ONE technique as the main move. Avoid blends: a conspiracy item shouldn't mostly be fear, a scapegoat item shouldn't mostly be a personal attack, a cherry-picking item shouldn't need an expert.
- Fair items must be clearly legitimate on the evidence in the text itself (numbers with their baseline, a named document or ruling, dates, the expert's actual field), and still look like the technique at a glance. Make them as punchy and tempting as the technique items, never bland or hedged.
- Never use the technique's name, or words like "manipulation", "fallacy" or "fair", in the text.
- Spread topics widely; no two items should share both topic and angle.
- Politics: {politics}
- {SAFE_RULES}
{avoid}"""


CLASSIFY_PROMPT = """Each snippet below either USES a manipulation technique or makes a structurally similar move FAIRLY. Judge each one on its own; the mix is unknown.

The techniques and their fair counterparts:
{defs}

For each snippet give:
- kind: "technique" if the move is manipulative as written, "fair" if the text itself gives what makes the move legitimate (proportionate feeling backed by stated facts, a genuinely two-way choice, evidence tying blame to the responsible party, an expert in their own field, documented conduct that is the point, a statistic with its baseline, a chain with evidence for each step, documented coordination).
- technique: the single label from the list that fits best (for a fair snippet, the technique it most resembles).

Snippets:
"""


def _obj(props, required=None):
    return {"type": "object", "properties": props, "required": required or list(props)}


def _arr(item):
    return {"type": "array", "items": item}


def _enum(values):
    return {"type": "string", "enum": list(values)}


S, INT = {"type": "string"}, {"type": "integer"}
TECH_ITEM = _obj({"text": S, "context": S, "kind": _enum(["technique", "fair"]),
                  "technique": _enum(LABELS), "tell": S, "why": S, "topic": S,
                  "lean": _enum(["left", "right", "none"])})
TECH_FIELDS = ["id", "text", "context", "kind", "technique", "tell", "why"]

# ---------------------------------------------------------------- calls


def log(msg):
    print(msg, flush=True)


_SLOTS = threading.BoundedSemaphore(PARALLEL)   # caps calls in flight, even from nested pools


class Budget:
    """Counts Claude calls so one run can't eat the shared subscription."""

    def __init__(self, limit):
        self.limit, self.used, self.failed = limit, 0, 0
        self._lock = threading.Lock()

    def take(self):
        with self._lock:
            if self.used >= self.limit:
                return False
            self.used += 1
            return True


def call(budget, label, prompt, schema, system, kind="main", cache_dir=None):
    """One Claude call, retried once, cached under cache_dir/label.json. None on failure.
    Only the label and timing are printed: error messages can quote model output."""
    path = cache_dir / f"{label}.json" if cache_dir else None
    if path and path.exists():
        log(f"  {label}: cached")
        return json.loads(path.read_text())
    for attempt in (1, 2):
        if not budget.take():
            log(f"  {label}: skipped, call budget spent")
            return None
        try:
            with _SLOTS:
                out, meta = claude_cli.ask(prompt, schema, system, model=config.model(kind))
        except Exception as e:  # ClaudeError, timeout
            log(f"  {label}: attempt {attempt} failed ({type(e).__name__})")
            continue
        log(f"  {label}: ok in {meta['seconds']}s ({meta['model']})")
        if path:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(out, ensure_ascii=False))
        return out
    budget.failed += 1
    return None


def parallel(jobs):
    """Run [(fn, *args), ...] at most PARALLEL at a time; results in the same order."""
    if not jobs:
        return []
    with concurrent.futures.ThreadPoolExecutor(PARALLEL) as ex:
        futures = [ex.submit(job[0], *job[1:]) for job in jobs]
        return [f.result() for f in futures]


def words(text):
    return len(text.split())


def _shingles(text, n=4):
    w = re.findall(r"[a-z0-9']+", text.lower())
    return {tuple(w[i:i + n]) for i in range(max(0, len(w) - n + 1))}


def too_similar(a, b, limit=0.3):
    sa, sb = _shingles(a), _shingles(b)
    return bool(sa and sb) and len(sa & sb) / min(len(sa), len(sb)) > limit


def technique_ok(it):
    """Format check for a drafted technique-or-fair item."""
    return (it.get("kind") in ("technique", "fair") and it.get("technique") in LABELS
            and 5 <= words(it.get("text", "")) <= 80 and it.get("context")
            and 1 <= words(it.get("tell", "")) <= 12 and 1 <= words(it.get("why", "")) <= 35)


def classify(budget, label, items, cache_dir=None):
    """Blind pass: the validator labels each item (kind and technique) without seeing the key.
    items need "id", "context" and "text". Returns {id: (kind, technique)}."""
    order = list(items)
    random.Random(label).shuffle(order)
    lines = "\n".join(f"[{it['id']}] ({it['context']}) {it['text']}" for it in order)
    schema = _obj({"items": _arr(_obj({"id": S, "kind": _enum(["technique", "fair"]),
                                       "technique": _enum(LABELS)}))})
    out = call(budget, label, CLASSIFY_PROMPT.format(defs=technique_defs()) + lines, schema,
               CHECK_SYSTEM, kind="validator", cache_dir=cache_dir)
    return {r["id"]: (r["kind"], r["technique"]) for r in (out or {}).get("items", [])}


def technique_passes(item, verdict):
    """Kept if the blind kind matches and, for technique items, the label matches too."""
    if not verdict or verdict[0] != item["kind"]:
        return False
    return item["kind"] == "fair" or verdict[1] == item["technique"]

# ---------------------------------------------------------------- sources

# Essay collections, all published before 1930 by authors who died before 1956.
# (Gutenberg id, author, title, year, author's death year)
SOURCES = [
    (2944, "Ralph Waldo Emerson", "Essays: First Series", 1841, 1882),
    (2945, "Ralph Waldo Emerson", "Essays: Second Series", 1844, 1882),
    (34901, "John Stuart Mill", "On Liberty", 1859, 1873),
    (205, "Henry David Thoreau", "Walden, and On the Duty of Civil Disobedience", 1854, 1862),
    (575, "Francis Bacon", "Essays", 1625, 1626),
    (3600, "Michel de Montaigne", "Essays, translated by Charles Cotton", 1686, 1592),
    (10343, "Charles Lamb", "Elia and The Last Essays of Elia", 1833, 1834),
    (3020, "William Hazlitt", "Table-Talk", 1822, 1830),
    (70, "Mark Twain", "What Is Man? and Other Essays", 1917, 1910),
    (386, "Robert Louis Stevenson", "Virginibus Puerisque", 1881, 1894),
]

# Where the author's own text starts and ends in a download, to leave out editors'
# introductions, dedications and notes: (start pattern, end pattern), either may be None.
BOUNDS = {
    34901: (r"^INTRODUCTORY\.\s*$", None),
    3600: (r"^BOOK THE FIRST\s*$", None),
    10343: (r"^THE SOUTH-SEA HOUSE\s*$", r"^NOTES\s*$"),
    575: (r"^FR\. ST\. ALBAN\s*$", None),
}

BAD_START = {"but", "and", "or", "for", "so", "yet", "nor", "this", "that", "these", "those",
             "it", "he", "she", "they", "his", "her", "its", "their", "them", "him", "such",
             "thus", "hence", "therefore", "here", "there", "then", "again", "also", "now",
             "still", "besides", "moreover", "indeed", "yes", "no", "which", "whereas"}
ARCHAIC = {"doth", "hath", "thee", "thou", "thy", "thine", "ye", "wilt", "shalt", "hast",
           "dost", "art", "canst", "whereof", "thereof", "wherein", "therein", "betwixt",
           "methinks", "nay", "ere", "oft", "saith", "unto", "wherefore"}
BACKREF = {"this", "that", "these", "those", "such", "it", "he", "she", "they", "them", "him",
           "her", "his", "its", "their", "latter", "former", "same", "aforesaid", "above",
           "thus", "hence", "therefore", "again", "also", "too"}
SENSITIVE = ("tortur", "racked", "the rack", "murder", "suicide", "corpse", "execution",
             "gallows", "slaughter", "bloodshed", "drunk", "intoxicat", "opium", "liquor",
             "slave", "negro", "savage", "massacre", "rape", "whip", "assassin", "funeral",
             "coffin", "deathbed")
JUNK = ("gutenberg", "http", "www.", "transcriber", "footnote", "e-text", "etext",
        "illustration", "copyright", "[", "]", "{", "}", "produced by", "chapter")


def _header_field(raw, name):
    m = re.search(rf"^{name}:\s*(.+)$", raw[:6000], re.M)
    return m.group(1).strip() if m else ""


def _strip_boilerplate(raw):
    start = re.search(r"^\*\*\* ?START OF.*$", raw, re.M | re.I)
    end = re.search(r"^\*\*\* ?END OF.*$", raw, re.M | re.I)
    body = raw[start.end() if start else 0:end.start() if end else len(raw)]
    return body.replace("\r\n", "\n").strip() + "\n"


def fetch_source(pg_id, author):
    """The body text of one book, downloaded once (politely) and cached. None if it fails
    or the download isn't the book we expected."""
    SOURCES_DIR.mkdir(parents=True, exist_ok=True)
    path = SOURCES_DIR / f"{pg_id}.txt"
    if path.exists():
        return path.read_text(encoding="utf-8")
    url = f"https://www.gutenberg.org/cache/epub/{pg_id}/pg{pg_id}.txt"
    req = urllib.request.Request(url, headers={
        "User-Agent": "binah-benchgen/1 (personal study tool; each book fetched once and cached)"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode("utf-8-sig", errors="replace")
    except OSError as e:
        log(f"  source {pg_id}: download failed ({type(e).__name__})")
        return None
    finally:
        time.sleep(2)
    surname = author.split(",")[0].split()[-1].lower()
    if surname not in _header_field(raw, "Author").lower():
        log(f"  source {pg_id}: skipped, header names a different author")
        return None
    text = _strip_boilerplate(raw)
    path.write_text(text, encoding="utf-8")
    (SOURCES_DIR / f"{pg_id}.meta.json").write_text(json.dumps(
        {k: _header_field(raw, k) for k in ("Title", "Author", "Translator", "Release date")}))
    return text


def book_text(pg_id, author):
    """The author's own text from a cached download, trimmed to BOUNDS."""
    text = fetch_source(pg_id, author)
    if not text:
        return None
    start, end = BOUNDS.get(pg_id, (None, None))
    if start and (m := re.search(start, text, re.M)):
        text = text[m.end():]
    if end and (m := re.search(end, text, re.M)):
        text = text[:m.start()]
    return text


def _clean(line):
    line = line.replace("_", "").replace("--", "—")
    return re.sub(r"\s+", " ", line).strip()


def paragraphs(text):
    """[(lines, cleaned text, is_body)] for each blank-line-separated block."""
    out = []
    for block in re.split(r"\n\s*\n", text):
        lines = [ln for ln in block.split("\n") if ln.strip()]
        if not lines:
            continue
        clean = _clean(" ".join(ln.strip() for ln in lines))
        out.append((lines, clean, _is_body(lines, clean)))
    return out


def _zipf():
    try:
        from wordfreq import zipf_frequency
        return lambda w: zipf_frequency(w, "en")
    except ImportError:
        return None


_ZIPF = _zipf()


def _is_body(lines, text):
    if words(text) < 40:
        return False
    if any(ln.startswith("  ") for ln in lines):          # indented: verse or a block quote
        return False
    if len(lines) >= 3 and sum(len(ln) for ln in lines[:-1]) / (len(lines) - 1) < 50:
        return False                                        # short lines: verse
    low = text.lower()
    if any(j in low for j in JUNK):
        return False
    letters = [c for c in text if c.isalpha()]
    if sum(c.isupper() for c in letters) > 0.12 * len(letters):
        return False
    if sum(c.isdigit() for c in text) > 8:
        return False
    if _ZIPF:
        toks = re.findall(r"[a-z]+", low)
        if sum(1 for t in toks if _ZIPF(t) < 1.5) > 0.03 * len(toks):
            return False                                    # foreign-language quotation
    return True


def sentences(text):
    return [s for s in re.split(r"(?<=[.!?])[\"'”’)]*\s+(?=[A-Z\"'“‘(])",
                                text) if s.strip()]


def _score(text):
    sents = sentences(text)
    lens = [words(s) for s in sents]
    if len(lens) < 4:
        return None
    avg, longest = sum(lens) / len(lens), max(lens)
    if longest > 80 or avg > 40:
        return None
    toks = re.findall(r"[a-z]+", text.lower())
    archaic = sum(t in ARCHAIC for t in toks)
    quotes = sum(text.count(q) for q in "\"“”")
    return (100 - abs(avg - 24) * 1.5 - archaic * 4 - quotes * 1.5 - text.count("(") * 2
            - text.count(";") * 0.7 - abs(words(text) - 320) / 8)


def _avoid_terms():
    """Words that rule a passage out: painful subjects, plus the private terms in settings."""
    try:
        extra = [t.lower() for t in config.settings().get("private_terms", []) if t]
    except Exception:
        extra = []
    return tuple(SENSITIVE) + tuple(extra)


def candidates(text, lo=250, hi=400):
    """Self-contained stretches of one to three body paragraphs, best first:
    [(score, start, end, passage)]."""
    paras = paragraphs(text)
    avoid = _avoid_terms()
    found = []
    for i, (_, first, body) in enumerate(paras):
        if not body:
            continue
        head = [w.lower() for w in re.findall(r"[A-Za-z]+", (sentences(first) or [first])[0])]
        if (not head or head[0] in BAD_START or not first[0].isupper()
                or BACKREF & set(head[:8]) or {"latter", "former", "aforesaid"} & set(head)):
            continue
        chunk = []
        for j in range(i, min(i + 3, len(paras))):
            if not paras[j][2]:
                break
            chunk.append(paras[j][1])
            n = sum(words(c) for c in chunk)
            if n > hi:
                break
            if n >= lo and chunk[-1].rstrip()[-1:] in ".!?\"'”’":
                passage = "\n\n".join(chunk)
                if any(a in passage.lower() for a in avoid):
                    break
                s = _score(passage)
                if s is not None:
                    found.append((s, i, j, passage))
    found.sort(key=lambda c: -c[0])
    return found


def load_used():
    try:
        return json.loads(USED_PATH.read_text())
    except (FileNotFoundError, ValueError):
        return []


def mark_used(passages, status):
    used = load_used()
    today = datetime.date.today().isoformat()
    for p in passages:
        used.append({"pg": p["pg"], "start": p["start"], "end": p["end"], "date": today,
                     "status": status})
    SOURCES_DIR.mkdir(parents=True, exist_ok=True)
    USED_PATH.write_text(json.dumps(used, indent=1))


def _overlaps(pg, start, end, used, margin=2):
    return any(u["pg"] == pg and start <= u["end"] + margin and u["start"] <= end + margin
               for u in used)


def pick_passages(n, rng, exclude=()):
    """n fresh passages, one per book where possible, from the top of each book's pile."""
    used = load_used() + list(exclude)
    books = []
    for pg, author, title, year, died in SOURCES:
        if year >= 1930 or died >= 1956:
            continue
        text = book_text(pg, author)
        if not text:
            continue
        pool = [c for c in candidates(text) if not _overlaps(pg, c[1], c[2], used)]
        if pool:
            books.append({"pg": pg, "author": author, "title": title, "year": year,
                          "pool": pool[:max(12, len(pool) // 5)]})
    rng.shuffle(books)
    picked, rounds = [], 0
    while len(picked) < n and rounds < 4 and books:
        for b in books:
            if len(picked) >= n:
                break
            free = [c for c in b["pool"] if not _overlaps(b["pg"], c[1], c[2], picked)]
            if not free:
                continue
            s, start, end, passage = rng.choice(free[:12])
            picked.append({"pg": b["pg"], "start": start, "end": end, "text": passage,
                           "author": b["author"], "words": words(passage),
                           "source": f"{b['author']}, {b['title']} ({b['year']}), public domain"})
        rounds += 1
    for k, p in enumerate(picked):
        p["pid"] = f"p{len(exclude) + k + 1}"
    return picked

# ---------------------------------------------------------------- drafting

ARG_TYPES = {
    "assumption": "Which one of the following is an assumption on which the argument depends? "
                  "(or: ...an assumption that would allow the conclusion to be properly drawn?)",
    "flaw": "The reasoning in the argument is most vulnerable to criticism on the grounds that it",
    "weaken": "Which one of the following, if true, most seriously weakens the argument?",
    "strengthen": "Which one of the following, if true, most strengthens the argument?",
    "conclusion": "Which one of the following most accurately expresses the main conclusion of "
                  "the argument?",
    "inference": "If the statements above are true, which one of the following must also be "
                 "true? (or: ...is most strongly supported by the information above?)",
}

ARG_ITEM = _obj({"type": _enum(ARG_TYPES), "stimulus": S, "stem": S,
                 "options": _arr(S), "answer": INT, "explanation": S})


def draft_arguments(budget, label, types):
    want = "\n".join(f"- {t}: {n} items" for t, n in types.items())
    stems = "\n".join(f"- {t}: {s}" for t, s in ARG_TYPES.items())
    prompt = f"""Write {sum(types.values())} original logical-reasoning items in the style of a standardized law-school admission test.

Counts by question type:
{want}

Typical stems (vary the wording a little):
{stems}

Each item:
- stimulus: 60 to 110 words, an original short argument or set of statements on an everyday topic ({", ".join(TOPICS)}): a letter to a local paper, a manager's reasoning, a consumer study, a scientist's claim, a town planner's proposal. Invented names only.
- type, stem.
- options: exactly 5 answer choices of similar length and style.
- answer: the index (0 to 4) of the single best answer. Exactly one choice must be defensibly best; a careful expert would agree.
- explanation: at most 60 words, why the key is right and why the most tempting wrong choice is wrong.

Make them medium to hard: each wrong choice should tempt for a real reason (out of scope, reverses the logic, too strong, irrelevant comparison, merely restates a premise, true but not required). For conclusion items the conclusion should not simply be the first or last sentence. Do not reproduce any published test question. {SAFE_RULES}"""
    out = call(budget, label, prompt, _obj({"items": _arr(ARG_ITEM)}), DRAFT_SYSTEM,
               cache_dir=WORK_DIR)
    items = []
    for it in (out or {}).get("items", []):
        if (it.get("type") in ARG_TYPES and len(it.get("options", [])) == 5
                and isinstance(it.get("answer"), int) and 0 <= it["answer"] < 5
                and 45 <= words(it.get("stimulus", "")) <= 130):
            items.append(it)
    return items


def draft_discern(budget, label, counts):
    out = call(budget, label, technique_prompt(counts, political=max(1, sum(
        a + b for a, b in counts.values()) // 8)), _obj({"items": _arr(TECH_ITEM)}),
        DRAFT_SYSTEM, cache_dir=WORK_DIR)
    return [it for it in (out or {}).get("items", []) if technique_ok(it)]


VOCAB_ITEM = _obj({"word": S, "sentence": S, "options": _arr(S), "answer": INT})


def draft_vocab_and_talks(budget, label, n_vocab, n_talk, n_essay_fallback):
    prompt = f"""Write three things.

1. {n_vocab} vocabulary items for an educated adult reader: words met in serious prose that people often half-know or misuse (the level of words like "fulsome", "enervate", "restive", "noisome"; do not use those four). Mix nouns, verbs and adjectives. Each item:
- word
- sentence: an original sentence of 15 to 30 words that uses the word in a context that fits its true meaning without defining it or making the answer obvious.
- options: exactly 4 short definitions (at most 10 words each). One is correct for the word as used. The three wrong ones must tempt: the common misuse, the meaning of a look-alike word, a related but wrong sense.
- answer: index 0 to 3 of the correct definition.

2. {n_talk} prompts for a two-minute impromptu talk. Each 1 to 2 sentences, specific, everyday and non-sensitive, asking for a structured answer: explain something to a newcomer, make a case, compare two things, describe a process, or tell a short story and draw a lesson.

3. {n_essay_fallback} prompts for a 15-minute essay of about 300 words that asks the writer to take and defend a position on an everyday question of judgement, considering the strongest objection.

{SAFE_RULES}"""
    schema = _obj({"vocab": _arr(VOCAB_ITEM), "talks": _arr(S), "essays": _arr(S)})
    out = call(budget, label, prompt, schema, DRAFT_SYSTEM, cache_dir=WORK_DIR) or {}
    vocab = []
    for it in out.get("vocab", []):
        stem = it.get("word", "").lower()[:max(4, len(it.get("word", "")) - 3)]
        if (len(it.get("options", [])) == 4 and isinstance(it.get("answer"), int)
                and 0 <= it["answer"] < 4 and stem and stem in it.get("sentence", "").lower()):
            vocab.append(it)
    return vocab, out.get("talks", []), out.get("essays", [])


INFER_Q = _obj({"stem": S, "options": _arr(S), "answer": INT, "trap": INT, "explanation": S})


def draft_inference(budget, label, passages, n_q=6, avoid=None):
    """Questions for each passage. avoid: {pid: [stems already kept]} for a top-up."""
    blocks = []
    for p in passages:
        extra = ""
        if avoid and avoid.get(p["pid"]):
            extra = ("\n(Questions already written for this passage, which yours must not "
                     "repeat or overlap: " + " | ".join(avoid[p["pid"]]) + ")")
        blocks.append(f"=== {p['pid']} ===\n{p['text']}{extra}")
    prompt = f"""Below are {len(passages)} passages of classic English prose. For each passage:

- suitable: false if it starts or ends mid-thought, leans on context the reader can't see, is mostly quotation, a list or plain narrative with nothing to infer, is too archaic for a modern reader, or dwells on cruelty, violence, death, disease or contempt for a group of people; otherwise true. An unsuitable passage gets no questions.
- questions: {n_q} multiple-choice questions that need INFERENCE, not literal recall: what the passage implies but doesn't state, the author's attitude or purpose, an unstated assumption, the job a particular sentence does, what a phrase means in context, which claim the author would most likely accept, or which situation best fits the author's principle.
  - options: exactly 4, alike in length, tone and hedging; no extreme or crude option. answer: index 0 to 3.
  - The key must be clearly right to someone who read the passage closely, and must paraphrase rather than copy its wording.

  THE HARD PART. Every question is later shown, WITHOUT the passage, to a strong reader. If that reader picks the key, the question is thrown away. In trials nearly every question failed: the key was the longest, most insightful or most nuanced option, so it could be spotted without reading. What works:
  - PARALLEL OPTIONS. Write the four options as one set, in the same grammatical frame and within two words of the same length, differing ONLY in the point the passage settles: which of two things, the direction of an effect, which reason, which kind of person, approval or disapproval, what an example is meant to show. No option may be wiser, subtler, more balanced, more qualified or better phrased than the others; if you swapped the passage for one arguing the opposite, a different option should become the key just as naturally.
  - The key must NOT be the longest option.
  - trap: the index of the option a smart reader who has NOT read the passage would pick: the view a modern reader would expect. The passage must clearly rule it out.
  - Keep the passage's claims OUT of the stem. Point to parts of it by position ("the second paragraph", "the final sentence") or by an unremarkable quotation of at most 6 words, never by summarising the argument.
  - Prefer the passage's particulars (an example, a comparison, a concession, a turn in the argument) over its famous main thesis.
  - Never name the author or the work in a question.
  - explanation: at most 50 words, pointing to the part of the passage that settles it and saying why the trap is wrong.
- essay_prompt: a 15-minute writing task (1 to 3 sentences) that asks the writer to state the passage's central claim in their own words, explain how the author supports it, and test it against an example or objection of their own. Call it "the passage".

{chr(10).join(blocks)}"""
    schema = _obj({"passages": _arr(_obj({"pid": S, "suitable": {"type": "boolean"},
                                          "essay_prompt": S, "questions": _arr(INFER_Q)}))})
    out = call(budget, label, prompt, schema, DRAFT_SYSTEM, cache_dir=WORK_DIR) or {}
    result = {}
    for r in out.get("passages", []):
        qs = [q for q in r.get("questions", []) if len(q.get("options", [])) == 4
              and isinstance(q.get("answer"), int) and 0 <= q["answer"] < 4
              and q.get("trap") != q["answer"] and not _key_stands_out(q)]
        result[r.get("pid")] = {"suitable": bool(r.get("suitable")) and bool(qs),
                                "essay_prompt": r.get("essay_prompt", ""), "questions": qs}
    return result


def _key_stands_out(q):
    """The classic tell: a key clearly longer than every other option."""
    lens = [words(o) for o in q["options"]]
    return lens[q["answer"]] > max(n for i, n in enumerate(lens) if i != q["answer"]) + 2


def shuffle_options(item, rng):
    order = list(range(len(item["options"])))
    rng.shuffle(order)
    item["answer"] = order.index(item["answer"])
    if isinstance(item.get("trap"), int) and 0 <= item["trap"] < len(order):
        item["trap"] = order.index(item["trap"])
    item["options"] = [item["options"][i] for i in order]
    return item

# ---------------------------------------------------------------- blind checks


def _letters(options):
    return "\n".join(f"{LETTERS[i]}. {o}" for i, o in enumerate(options))


ANSWER_SCHEMA = _obj({"answers": _arr(_obj({"id": S, "answer": _enum(LETTERS)}))})


def _answers(out):
    return {a["id"]: LETTERS.index(a["answer"]) for a in (out or {}).get("answers", [])
            if a.get("answer") in LETTERS}


def check_arguments(budget, label, items):
    body = "\n\n".join(f"[{it['id']}]\n{it['stimulus']}\n\n{it['stem']}\n{_letters(it['options'])}"
                       for it in items)
    prompt = ("Answer each logical-reasoning question below. Pick the single best answer "
              "letter for every item.\n\n" + body)
    return _answers(call(budget, label, prompt, ANSWER_SCHEMA, CHECK_SYSTEM, kind="validator",
                         cache_dir=WORK_DIR))


def check_vocab(budget, label, items):
    body = "\n\n".join(f"[{it['id']}] {it['sentence']}\nAs used here, \"{it['word']}\" means:\n"
                       f"{_letters(it['options'])}" for it in items)
    prompt = ("For each item, pick the definition that matches the word as it is used in the "
              "sentence.\n\n" + body)
    return _answers(call(budget, label, prompt, ANSWER_SCHEMA, CHECK_SYSTEM, kind="validator",
                         cache_dir=WORK_DIR))


def check_inference(budget, label, passages, questions):
    """With the passage: {qid: picked index}."""
    blocks = []
    for p in passages:
        qs = [q for q in questions if q["pid"] == p["pid"]]
        if qs:
            blocks.append(f"=== Passage {p['pid']} ===\n{p['text']}\n\n" + "\n\n".join(
                f"[{q['id']}] {q['stem']}\n{_letters(q['options'])}" for q in qs))
    prompt = ("Read each passage closely and answer its questions. Pick the single best answer "
              "letter for every question.\n\n" + "\n\n".join(blocks))
    return _answers(call(budget, label, prompt, ANSWER_SCHEMA, CHECK_SYSTEM, kind="validator",
                         cache_dir=WORK_DIR))


def check_no_passage(budget, label, questions, rng):
    """Without the passage, each question twice in two option orders (key moved).
    Returns {qid: {"key": times the key was picked (0-2), "trap": times the trap was}};
    a missing answer counts as picking the key."""
    entries = []
    for q in questions:
        first = list(range(4))
        rng.shuffle(first)
        second = list(first)
        while second.index(q["answer"]) == first.index(q["answer"]):
            rng.shuffle(second)
        for perm in (first, second):
            entries.append({"q": q, "perm": perm})
    rng.shuffle(entries)
    for k, e in enumerate(entries):
        e["eid"] = f"n{k + 1}"
    body = "\n\n".join(f"[{e['eid']}] {e['q']['stem']}\n"
                       f"{_letters([e['q']['options'][i] for i in e['perm']])}" for e in entries)
    prompt = ("Each question below is about a short passage of classic prose that you cannot "
              "see. Pick the option you think is most likely correct anyway. You must answer "
              "every item with one letter.\n\n" + body)
    picks = _answers(call(budget, label, prompt, ANSWER_SCHEMA, CHECK_SYSTEM, kind="validator",
                          cache_dir=WORK_DIR))
    hits = {q["id"]: {"key": 0, "trap": 0} for q in questions}
    for e in entries:
        pick = picks.get(e["eid"])
        if pick is None or e["perm"][pick] == e["q"]["answer"]:
            hits[e["q"]["id"]]["key"] += 1
        elif e["perm"][pick] == e["q"].get("trap"):
            hits[e["q"]["id"]]["trap"] += 1
    return hits

# ---------------------------------------------------------------- the run


class Pools:
    """Everything drafted and checked so far, with pass/fail tallies."""

    def __init__(self):
        self.argument, self.discern, self.vocab = [], [], []
        self.passages, self.questions = [], []    # questions carry "pid"
        self.talks, self.essays = [], []
        self.stats = {k: {"drafted": 0, "passed": 0} for k in
                      ("argument", "discern", "vocab", "inference")}
        self.stats["inference"]["no_passage_drops"] = 0
        self.stats["inference"]["trap_picks"] = 0      # no-passage answers that took the trap
        self.stats["inference"]["no_passage_answers"] = 0
        self.stats["discern"]["too_close_to_practice"] = 0
        self.unsuitable = 0
        self.seq = 0

    def next_id(self, prefix):
        self.seq += 1
        return f"{prefix}{self.seq}"

    def good(self, kind):
        return [it for it in getattr(self, kind) if it.get("passed")]

    def good_passages(self):
        out = []
        for p in self.passages:
            qs = [q for q in self.questions if q["pid"] == p["pid"] and q.get("passed")]
            if p.get("suitable") and len(qs) >= N_QUESTIONS:
                out.append(p)
        return out


def _practice_texts():
    try:
        return [it["text"] for it in json.loads(TECHNIQUE_FILE.read_text())]
    except (FileNotFoundError, ValueError, KeyError, TypeError):
        return []


def run_round(budget, pools, need, rng, tag):
    """Draft what's missing (need: counts per section), then check it blind."""
    drafts = []
    if need["argument"]:
        have = {t: sum(1 for it in pools.good("argument") if it["type"] == t) for t in ARG_TYPES}
        order = []
        for _ in range(need["argument"]):          # fill the scarcest types first, round robin
            t = min(ARG_TYPES, key=lambda t: have[t] + order.count(t))
            order.append(t)
        chunks = []
        for i in range(0, len(order), 18):
            part = order[i:i + 18]
            chunks.append({t: part.count(t) for t in ARG_TYPES if part.count(t)})
        drafts += [(draft_arguments, budget, f"{tag}-argument-{i + 1}", c)
                   for i, c in enumerate(chunks)]
    if need["discern_technique"] or need["discern_fair"]:
        nt, nf = need["discern_technique"], need["discern_fair"]
        counts = {lab: (math.ceil(nt / len(LABELS)), math.ceil(nf / len(LABELS)))
                  for lab in LABELS}
        drafts.append((draft_discern, budget, f"{tag}-discern", counts))
    if need["vocab"] or need["talk"]:
        drafts.append((draft_vocab_and_talks, budget, f"{tag}-vocab", max(need["vocab"], 4),
                       max(need["talk"], 2), 2))
    if need["passages"]:
        for i in range(0, len(need["passages"]), 5):
            batch = need["passages"][i:i + 5]
            drafts.append((draft_inference, budget, f"{tag}-inference-{i // 5 + 1}", batch,
                           5, need.get("avoid")))

    new_args, new_disc, new_vocab, new_q = [], [], [], []
    practice = _practice_texts()
    for job, result in zip(drafts, parallel(drafts)):
        fn = job[0]
        if fn is draft_arguments:
            for it in result:
                it["id"] = pools.next_id("a")
                new_args.append(shuffle_options(it, rng))
        elif fn is draft_discern:
            for it in result:
                others = practice + [d["text"] for d in pools.discern + new_disc]
                if any(too_similar(it["text"], t) for t in others):
                    pools.stats["discern"]["too_close_to_practice"] += 1
                    continue
                it["id"] = pools.next_id("d")
                new_disc.append(it)
        elif fn is draft_vocab_and_talks:
            vocab, talks, essays = result
            seen = {v["word"].lower() for v in pools.vocab}
            for it in vocab:
                if it["word"].lower() in seen:
                    continue
                seen.add(it["word"].lower())
                it["id"] = pools.next_id("v")
                new_vocab.append(shuffle_options(it, rng))
            pools.talks += talks
            pools.essays += essays
        elif fn is draft_inference:
            batch = job[3]
            for p in batch:
                r = result.get(p["pid"])
                if not r:
                    continue
                if p not in pools.passages:
                    p["suitable"] = r["suitable"]
                    p["essay_prompt"] = r["essay_prompt"]
                    pools.passages.append(p)
                    if not r["suitable"]:
                        pools.unsuitable += 1
                        continue
                for q in r["questions"]:
                    q["id"], q["pid"] = pools.next_id("q"), p["pid"]
                    new_q.append(shuffle_options(q, rng))
            for p in batch:                          # a passage the model skipped entirely
                if p not in pools.passages:
                    p["suitable"] = False
                    pools.passages.append(p)

    pools.stats["argument"]["drafted"] += len(new_args)
    pools.stats["discern"]["drafted"] += len(new_disc)
    pools.stats["vocab"]["drafted"] += len(new_vocab)
    pools.stats["inference"]["drafted"] += len(new_q)

    checks = []
    for i in range(0, len(new_args), 40):
        checks.append((check_arguments, budget, f"{tag}-check-argument-{i // 40 + 1}",
                       new_args[i:i + 40]))
    if new_vocab:
        checks.append((check_vocab, budget, f"{tag}-check-vocab", new_vocab))
    if new_disc:
        checks.append((classify, budget, f"{tag}-check-discern", new_disc, WORK_DIR))
    if new_q:
        q_passages = [p for p in pools.passages if any(q["pid"] == p["pid"] for q in new_q)]
        checks.append((check_inference, budget, f"{tag}-check-inference", q_passages, new_q))
        checks.append((check_no_passage, budget, f"{tag}-check-nopassage", new_q,
                       random.Random(tag)))
    results = parallel(checks)

    blind, hits = {}, {}
    for job, result in zip(checks, results):
        if job[0] is check_no_passage:
            hits = result
        else:
            blind.update(result)
    for it in new_args + new_vocab:
        it["passed"] = blind.get(it["id"]) == it["answer"]
    for it in new_disc:
        it["passed"] = technique_passes(it, blind.get(it["id"]))
    for q in new_q:
        answered = blind.get(q["id"]) == q["answer"]
        h = hits.get(q["id"], {"key": 2, "trap": 0})
        guessable = h["key"] >= 2
        pools.stats["inference"]["trap_picks"] += h["trap"]
        pools.stats["inference"]["no_passage_answers"] += 2
        if answered and guessable:
            pools.stats["inference"]["no_passage_drops"] += 1
        q["passed"] = answered and not guessable

    pools.argument += new_args
    pools.discern += new_disc
    pools.vocab += new_vocab
    pools.questions += new_q
    for kind, new in (("argument", new_args), ("discern", new_disc), ("vocab", new_vocab),
                      ("inference", new_q)):
        pools.stats[kind]["passed"] += sum(1 for it in new if it["passed"])


def shortfall(pools, n_forms, rng, first):
    """What still has to be drafted to fill n_forms, with some slack for the blind check."""
    slack = 1.5 if first else 2.0
    good_t = sum(1 for d in pools.good("discern") if d["kind"] == "technique")
    good_f = sum(1 for d in pools.good("discern") if d["kind"] == "fair")
    half = N_DISCERN // 2
    need = {
        "argument": max(0, math.ceil((N_ARGUMENT * n_forms - len(pools.good("argument")))
                                     * slack)),
        "discern_technique": max(0, math.ceil((half * n_forms - good_t) * slack)),
        "discern_fair": max(0, math.ceil((half * n_forms - good_f) * slack)),
        "vocab": max(0, math.ceil((N_VOCAB * n_forms - len(pools.good("vocab"))) * slack)),
        "talk": max(0, n_forms * 2 - len(pools.talks)),
        "passages": [],
        "avoid": {},
    }
    if first:
        need["discern_technique"] = max(need["discern_technique"], len(LABELS) * n_forms)
        need["discern_fair"] = max(need["discern_fair"], len(LABELS) * n_forms)
    missing = N_PASSAGES * n_forms - len(pools.good_passages())
    if missing > 0:
        if first:
            need["passages"] = pick_passages(N_PASSAGES * n_forms + n_forms, rng)
        else:
            near = []
            for p in pools.passages:
                kept = [q for q in pools.questions if q["pid"] == p["pid"] and q.get("passed")]
                if p.get("suitable") and 0 < len(kept) < N_QUESTIONS:
                    near.append((len(kept), p, kept))
            near.sort(key=lambda x: -x[0])
            for _, p, kept in near[:missing + 1]:
                need["passages"].append(p)
                need["avoid"][p["pid"]] = [q["stem"] for q in kept]
            # Fresh passages too: twice what's missing, up to two drafting calls' worth.
            fresh = min(10, max(missing + 1, 2 * missing)) - len(need["passages"])
            if fresh > 0:
                need["passages"] += pick_passages(fresh, rng, exclude=pools.passages)
    return need


def _any_need(need):
    return any(need[k] for k in ("argument", "discern_technique", "discern_fair", "vocab",
                                 "passages")) or need["talk"]


def _take_arguments(pool, n):
    picked = []
    for t in ARG_TYPES:                              # one of each type first
        for it in pool:
            if it["type"] == t and it not in picked:
                picked.append(it)
                break
    for t in ("assumption", "flaw", "weaken", "strengthen", "inference", "conclusion"):
        for it in pool:
            if len(picked) >= n:
                break
            if it["type"] == t and it not in picked:
                picked.append(it)
                break
    for it in pool:
        if len(picked) >= n:
            break
        if it not in picked:
            picked.append(it)
    picked = picked[:n]
    for it in picked:
        pool.remove(it)
    return picked


def _take_discern(pool, half):
    picked, labels = [], set()
    for kind in ("technique", "fair"):
        chosen = []
        for it in pool:                              # different techniques where possible
            if it["kind"] == kind and it["technique"] not in labels and len(chosen) < half:
                chosen.append(it)
                labels.add(it["technique"])
        for it in pool:
            if it["kind"] == kind and it not in chosen and len(chosen) < half:
                chosen.append(it)
        picked += chosen
    for it in picked:
        pool.remove(it)
    return picked


RUBRIC = {
    "structure": ("0: no discernible plan. 1: a point appears, but the order is hard to follow. "
                  "2: a clear point with some organisation, though steps are missing or out of "
                  "order. 3: a clear claim, paragraphs that each do one job, sensible order. "
                  "4: a sharp claim, every paragraph advancing it, transitions that show how "
                  "the ideas connect, and a close that lands."),
    "accuracy": ("0: misreads the passage or invents what it says. 1: gets the topic but "
                 "misstates the central claim. 2: the central claim is right but key details "
                 "or the author's reasons are wrong or missing. 3: claim and reasons are "
                 "represented fairly, with minor slips. 4: faithful throughout, with every "
                 "paraphrase and reference true to the passage."),
    "understanding": ("0: summary or opinion with no grasp of the argument. 1: restates without "
                      "seeing how the reasons support the claim. 2: explains the reasoning but "
                      "the test is weak or generic. 3: explains the reasoning and tests it with "
                      "a relevant example or objection. 4: sees what the passage implies or "
                      "assumes, and the example or objection genuinely sharpens or limits the "
                      "claim."),
}

ESSAY_FALLBACK = ("About the second reading passage: state its central claim in your own "
                  "words, explain how the author supports it, and test it against one example "
                  "or objection of your own.")


def _strip(it, fields):
    return {k: it[k] for k in fields}


def assemble(pools, n_forms, start, rng):
    args = pools.good("argument")
    disc = pools.good("discern")
    vocab = pools.good("vocab")
    passages = pools.good_passages()
    rng.shuffle(args), rng.shuffle(disc), rng.shuffle(vocab), rng.shuffle(passages)
    talks = pools.talks
    forms = []
    for k in range(n_forms):
        if (len(args) < N_ARGUMENT or len(vocab) < N_VOCAB or len(passages) < N_PASSAGES
                or not talks
                or sum(1 for d in disc if d["kind"] == "technique") < N_DISCERN // 2
                or sum(1 for d in disc if d["kind"] == "fair") < N_DISCERN // 2):
            break
        pair = [passages.pop(0)]
        other = next((p for p in passages if p["author"] != pair[0]["author"]), passages[0])
        passages.remove(other)
        pair.append(other)
        form_id = f"form-{start + k}"
        a_items = _take_arguments(args, N_ARGUMENT)
        d_items = _take_discern(disc, N_DISCERN // 2)
        rng.shuffle(d_items)
        v_items = [vocab.pop(0) for _ in range(N_VOCAB)]
        qn = 0
        inf = []
        for p in pair:
            qs = [q for q in pools.questions if q["pid"] == p["pid"] and q.get("passed")]
            out_q = []
            for q in qs[:N_QUESTIONS]:
                q["form"] = form_id
                qn += 1
                out_q.append({"id": f"i{qn}", "stem": q["stem"], "options": q["options"],
                              "answer": q["answer"], "explanation": q["explanation"]})
            inf.append({"source": p["source"], "text": p["text"], "questions": out_q})
        author = pair[1]["author"].split(",")[0]
        if pair[1].get("essay_prompt"):
            essay = f"About the second reading passage ({author}): {pair[1]['essay_prompt']}"
        else:
            essay = pools.essays.pop(0) if pools.essays else ESSAY_FALLBACK
        forms.append({
            "id": form_id, "version": FORM_VERSION,
            "created": datetime.date.today().isoformat(),
            "sections": [
                {"kind": "argument", "items": [
                    dict(_strip(it, ["type", "stimulus", "stem", "options", "answer",
                                     "explanation"]), id=f"a{i + 1}")
                    for i, it in enumerate(a_items)]},
                {"kind": "discern", "items": [
                    dict(_strip(it, TECH_FIELDS[1:]), id=f"d{i + 1}")
                    for i, it in enumerate(d_items)]},
                {"kind": "inference", "passages": inf},
                {"kind": "essay", "prompt": essay, "minutes": 15, "rubric": RUBRIC},
                {"kind": "talk", "prompt": talks.pop(0), "seconds": 120},
                {"kind": "vocab", "items": [
                    dict(_strip(it, ["word", "sentence", "options", "answer"]), id=f"v{i + 1}")
                    for i, it in enumerate(v_items)]},
            ],
            "confidence": True,
        })
        for it in pair + a_items + d_items + v_items:
            it["form"] = form_id
    for form in forms:      # put "id" first in every item, for readability
        for sec in form["sections"]:
            if "items" in sec:
                sec["items"] = [{"id": it["id"], **{k: v for k, v in it.items() if k != "id"}}
                                for it in sec["items"]]
    return forms


SNAPSHOT = WORK_DIR / "pools.json"


def drop_used(pools):
    """Take everything that went into a written form out of the pools."""
    for kind in ("argument", "discern", "vocab"):
        setattr(pools, kind, [it for it in getattr(pools, kind) if not it.get("form")])
    used = {p["pid"] for p in pools.passages if p.get("form")}
    pools.passages = [p for p in pools.passages if p["pid"] not in used]
    pools.questions = [q for q in pools.questions if q["pid"] not in used]


def save_snapshot(pools, rounds, rng):
    """Everything drafted and checked so far, so a rerun carries on after the last round."""
    version, state, gauss = rng.getstate()
    SNAPSHOT.write_text(json.dumps({"rounds": rounds, "pools": vars(pools),
                                    "rng": [version, list(state), gauss]}, ensure_ascii=False))


def load_snapshot(rng):
    pools = Pools()
    try:
        snap = json.loads(SNAPSHOT.read_text())
    except (FileNotFoundError, ValueError):
        return pools, 0
    vars(pools).update(snap["pools"])
    version, state, gauss = snap["rng"]
    rng.setstate((version, tuple(state), gauss))
    return pools, snap["rounds"]


def _pct(stat):
    d, p = stat["drafted"], stat["passed"]
    return f"{p}/{d} passed ({100 * p / d:.0f}%)" if d else "none drafted"


def main(argv=None):
    ap = argparse.ArgumentParser(description="Write sealed benchmark forms (prints counts only).")
    ap.add_argument("--forms", type=int, default=3, help="how many forms to write")
    ap.add_argument("--max-calls", type=int, default=22, help="Claude call budget for this run")
    ap.add_argument("--rounds", type=int, default=3, help="draft-and-check rounds at most")
    ap.add_argument("--partial", action="store_true",
                    help="write the forms that could be filled even if some couldn't")
    ap.add_argument("--dry-run", action="store_true",
                    help="only fetch the sources and count passage candidates (no Claude calls)")
    args = ap.parse_args(argv)

    if args.dry_run:
        used = load_used()
        for pg, author, title, year, died in SOURCES:
            text = book_text(pg, author)
            n = len([c for c in candidates(text) if not _overlaps(pg, c[1], c[2], used)]) \
                if text else 0
            try:
                meta = json.loads((SOURCES_DIR / f"{pg}.meta.json").read_text())
            except (FileNotFoundError, ValueError):
                meta = {}
            log(f"source {pg}: {n} fresh passage candidates  [{meta.get('Title', '?')[:50]} / "
                f"{meta.get('Author', '?')}]")
        return

    FORMS_DIR.mkdir(parents=True, exist_ok=True)
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    seed_path = WORK_DIR / "seed.json"      # same seed on a resume, so cached answers still fit
    if not seed_path.exists():
        seed_path.write_text(json.dumps({"seed": random.randrange(1 << 30), "forms": args.forms}))
    seed = json.loads(seed_path.read_text())
    if seed["forms"] != args.forms:
        raise SystemExit(f"a run for {seed['forms']} forms is half done in {WORK_DIR}; "
                         "rerun with that --forms, or delete the folder")
    rng = random.Random(seed["seed"])
    existing = [int(m.group(1)) for f in FORMS_DIR.glob("form-*.json")
                if (m := re.match(r"form-(\d+)\.json$", f.name))]
    start = max(existing, default=0) + 1
    budget = Budget(args.max_calls)
    pools, done = load_snapshot(rng)
    if done:
        log(f"resuming after round {done}")
    t0 = time.time()
    rounds_done = done
    for r in range(done, done + args.rounds):
        need = shortfall(pools, args.forms, rng, first=(r == 0))
        if not _any_need(need):
            break
        log(f"round {r + 1}: drafting argument {need['argument']}, discern "
            f"{need['discern_technique']}+{need['discern_fair']}, vocab {need['vocab']}, "
            f"talk {need['talk']}, passages {len(need['passages'])}")
        run_round(budget, pools, need, rng, f"r{r + 1}")
        rounds_done = r + 1
        save_snapshot(pools, rounds_done, rng)
        if budget.used >= budget.limit:
            break

    forms = assemble(pools, args.forms, start, rng)
    complete = len(forms) == args.forms
    if forms and (complete or args.partial):
        for form in forms:
            path = FORMS_DIR / f"{form['id']}.json"
            tmp = path.with_suffix(".tmp")
            tmp.write_text(json.dumps(form, indent=1, ensure_ascii=False))
            tmp.replace(path)
        mark_used([p for p in pools.passages if p.get("form")], "form")
    if complete:
        mark_used([p for p in pools.passages if not p.get("form")], "seen")
    elif forms and args.partial:            # carry the unused checked items to the next run
        drop_used(pools)
        save_snapshot(pools, rounds_done, rng)
        seed["forms"] = args.forms - len(forms)
        seed_path.write_text(json.dumps(seed))
    else:
        forms = []

    st = pools.stats
    log("")
    log(f"argument   {_pct(st['argument'])}")
    log(f"discern    {_pct(st['discern'])}; {st['discern']['too_close_to_practice']} dropped "
        "before the check for being too close to a practice item")
    log(f"vocab      {_pct(st['vocab'])}")
    log(f"inference  {_pct(st['inference'])}; {st['inference']['no_passage_drops']} answered "
        "without the passage and dropped; without the passage the trap was taken "
        f"{st['inference']['trap_picks']} times of {st['inference']['no_passage_answers']}")
    log(f"passages   {len(pools.passages)} sent, {pools.unsuitable} judged unsuitable, "
        f"{len(pools.good_passages())} with {N_QUESTIONS}+ good questions")
    log(f"calls      {budget.used} used of {budget.limit} ({budget.failed} failed), "
        f"{(time.time() - t0) / 60:.1f} min")
    log(f"forms      {len(forms)} of {args.forms} written to {FORMS_DIR}"
        + (f" ({', '.join(f['id'] for f in forms)})" if forms else ""))
    if complete:
        shutil.rmtree(WORK_DIR, ignore_errors=True)
    elif forms:
        log(f"the unused checked items stay in {WORK_DIR}; finish with "
            f"--forms {seed['forms']} (a rerun drafts only what's still missing)")
    else:
        log(f"not enough checked items for every form; the work cache is kept in {WORK_DIR}, "
            "so a rerun (perhaps with a larger --max-calls) resumes, or use --partial")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
