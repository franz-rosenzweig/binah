"""Speech: turn a recorded answer into a transcript and a few honest numbers.

A voice answer arrives as a browser recording (WebM/Opus from Chrome and
Android, MP4/AAC from Safari). We decode it once to 16 kHz mono and then:

1. Find where the speaker is actually talking with Silero voice activity
   detection (VAD). Pauses come from here, never from the gaps between
   Whisper's words, because Whisper stretches words over silences and its
   word timings show almost no gaps.
2. Transcribe it twice with faster-whisper:
   - a PLAIN pass, the clean text that gets graded, with word timings;
   - a VERBATIM pass, steered by a hesitant-sounding style prompt so Whisper
     writes down the "um"s and "uh"s it normally leaves out. Prompts like this
     can make Whisper skip whole stretches of audio, so the verbatim pass is
     thrown away if it comes back with noticeably fewer real words than the
     plain pass, or if it repeats the prompt back.

What we measure, and why. The goal is not zero fillers: short fillers help
listeners follow along. What tends to make speech sound confident is

- a clean start: no filler or long pause in the first few words;
- few long pauses (one second or more) once speech has begun;
- a steady pace, judged against the speaker's own usual pace, not a norm;
- a modest rate of filled pauses ("um", "uh") per minute;
- not leaning on the same content word again and again.

So the metrics are: word count and words per minute (over the whole
recording and over the time actually spent speaking), filler and crutch-word
counts ("you know", "I mean", "like" used as a filler ...), the silent gaps
of a second or more between stretches of speech, how long the speaker took
to start, whether the first sentence started cleanly, and content words used
three or more times that aren't simply words from the topic.

Time bases, so the numbers are easy to read:
    duration       the whole recording
    speaking_time  the sum of the VAD speech stretches (talking, no pauses)
    span           first speech to last speech (talking plus the pauses
                   between), used for fillers per minute and silence ratio,
                   so silence before starting or after finishing doesn't count

Everything runs on the CPU. The model loads once per process, and only one
transcription runs at a time.
"""
import os
import re
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

SAMPLE_RATE = 16000
MODEL_NAME = os.environ.get("BINAH_WHISPER_MODEL", "small.en")

# A pause this long or longer, between two stretches of speech, is "long".
LONG_PAUSE = 1.0
# How many opening words must be clean for a clean first sentence.
OPENING_WORDS = 6
# The verbatim pass is kept only if it has at least this share of the plain
# pass's real (non-filler) words.
VERBATIM_MIN_RATIO = 0.90
# Run the plain and verbatim passes side by side (2) or one after the other
# (1). Side by side took about half the time on an 8-core desktop CPU.
PASSES = 2

# Whisper copies the style of its prompt, so a hesitant prompt makes it keep
# the fillers. (Longer or busier prompts made it skip stretches of audio more
# often in testing; this one held up best.)
DISFLUENT_PROMPT = "Umm, so, uh, let me think. I mean, like, hmm, okay. Uh, the thing is, um, you know..."

# Settings for our own pause-finding VAD run. Silero's defaults are made for
# cutting audio into chunks for Whisper (wait 2 s before ending a stretch, pad
# each side by 0.4 s), which would hide most pauses. Here we end a stretch
# after 0.3 s of silence and pad by only 30 ms, so the gaps we measure are
# close to the real silence.
PAUSE_VAD = dict(threshold=0.5, min_speech_duration_ms=100,
                 min_silence_duration_ms=300, speech_pad_ms=30)

# Fillers we count: um, uh, er, erm, ah, hmm, mm. Whisper spells them many
# ways ("Umm", "Uhm", "Hmmm", "Mm-hmm"), so each pattern maps to one spelling.
_FILLER_PATTERNS = [
    (re.compile(r"^u+h+m+$"), "um"),
    (re.compile(r"^u+m+$"), "um"),
    (re.compile(r"^u+h+$"), "uh"),
    (re.compile(r"^e+r+m+$"), "erm"),
    (re.compile(r"^e+r+$"), "er"),
    (re.compile(r"^a+h+$"), "ah"),
    (re.compile(r"^h+m+$"), "hmm"),
    (re.compile(r"^m+h?m+$|^m+-?h+m+$"), "mm"),   # mm, mmm, mhm, mm-hmm
]

# Two-word crutches, and the words right before them that mean the phrase is
# being used literally ("do you know", "a kind of tree", "what I mean is").
CRUTCH_PAIRS = {
    ("you", "know"): {"do", "did", "don't", "didn't", "if", "would", "could", "will",
                      "won't", "as", "let", "whether", "you'd", "to"},
    ("i", "mean"): {"what", "if", "do", "did", "don't", "didn't"},
    ("sort", "of"): None,
    ("kind", "of"): None,
}
DETERMINERS = {"a", "an", "the", "this", "that", "these", "those", "what", "which", "some",
               "any", "every", "each", "no", "one", "same", "other", "different", "certain",
               "particular", "my", "your", "his", "her", "its", "our", "their", "whatever"}
CRUTCH_SINGLE = {"basically", "actually", "literally"}
BE_FORMS = {"is", "was", "were", "are", "am", "be", "been", "it's", "that's", "he's", "she's",
            "i'm", "you're", "we're", "they're", "i'd", "i'll"}
NO_FOLD = {"series", "species", "lens", "always", "sometimes", "perhaps", "whereas",
           "besides", "towards", "afterwards", "nowadays", "process", "progress"}

# Words too common to count as repetition. Short words (under 4 letters) are
# skipped anyway, so this is mostly 4+ letter function words and contractions.
STOP_WORDS = set("""
about above after again against also although among another anybody anyone anything
anyway anywhere around away back because been before behind being below beside besides
between beyond both came cannot come comes could couldn't does doesn't doing done don't
down during each either else enough even ever every from further gets give given gives
goes going gone gonna gotta have haven't having he'd he'll he's hence here here's hers
herself himself however i'd i'll i'm i've into isn't it'd it'll it's itself just kinda
less let's made make makes many maybe might mine more most much must myself near need
needs neither never next none nope nothing okay once only onto other others otherwise
ours ourselves over perhaps quite rather said same says shall she'd she'll she's should
shouldn't since some somebody someone somehow sorta still such sure take than that
that'd that'll that's their theirs them themselves then there there'd there'll there's
these they they'd they'll they're they've this those though through thus till together
toward towards under unless unlike until upon very want wanna wasn't we'd we'll we're
we've well went were weren't what what's whatever when whenever where where's whereas
wherever whether which while whoever whole whom whose will with within without won't
would wouldn't yeah yes yet you'd you'll you're you've your yours yourself yourselves
again ago almost alone along already always anyhow became become becomes bunch etc
lots often per kind sort like know mean basically actually literally
""".split())

_lock_model = threading.Lock()
_lock_run = threading.Lock()
_model = None


# ---------------------------------------------------------------- model + audio

def _get_model():
    """Load the Whisper model the first time it's needed, then reuse it.

    Two workers, so the plain and verbatim passes can run side by side; the
    CPU threads (all cores but two) are split between them.
    """
    global _model
    with _lock_model:
        if _model is None:
            from faster_whisper import WhisperModel
            threads = max(1, (os.cpu_count() or 1) - 2)
            opts = dict(device="cpu", compute_type="int8", num_workers=PASSES,
                        cpu_threads=max(1, threads // PASSES))
            try:
                # Use the cached copy without asking the network first.
                _model = WhisperModel(MODEL_NAME, local_files_only=True, **opts)
            except Exception:
                _model = WhisperModel(MODEL_NAME, **opts)   # not cached yet: download
        return _model


def _decode(path):
    """Decode any browser recording to 16 kHz mono float32 samples.

    Returns an empty array for an empty file or one with no audio frames.
    Raises ValueError if the file can't be read as audio at all.

    This does the same job as faster_whisper.audio.decode_audio, but that
    helper passes an argument (metadata_errors) that PyAV 19 removed, so we
    talk to PyAV directly. Damaged packets are skipped, like it does.
    """
    import av
    import numpy as np

    if os.path.getsize(path) == 0:
        return np.zeros(0, dtype=np.float32)
    chunks = []
    try:
        with av.open(path, mode="r") as container:
            if not container.streams.audio:
                raise ValueError("no audio track")
            stream = container.streams.audio[0]
            resampler = av.AudioResampler(format="s16", layout="mono", rate=SAMPLE_RATE)
            for packet in container.demux(stream):
                try:
                    frames = packet.decode()
                except av.error.InvalidDataError:
                    continue
                for frame in frames:
                    frame.pts = None            # browser files can have odd timestamps
                    chunks.extend(f.to_ndarray().reshape(-1) for f in resampler.resample(frame))
            chunks.extend(f.to_ndarray().reshape(-1) for f in resampler.resample(None))
    except Exception as e:
        # PyAV errors carry the file path in str(e); keep just the reason.
        reason = getattr(e, "strerror", None) or str(e)[:100] or type(e).__name__
        raise ValueError(f"could not decode audio: {reason}") from None
    if not chunks:
        return np.zeros(0, dtype=np.float32)
    return np.concatenate(chunks).astype(np.float32) / 32768.0


def _speech_segments(audio):
    """Stretches of speech in seconds, from Silero VAD with pause-friendly settings."""
    from faster_whisper.vad import VadOptions, get_speech_timestamps

    if audio.size < SAMPLE_RATE // 10:          # under 0.1 s: nothing to find
        return []
    stamps = get_speech_timestamps(audio, VadOptions(**PAUSE_VAD), sampling_rate=SAMPLE_RATE)
    return [{"start": round(s["start"] / SAMPLE_RATE, 2), "end": round(s["end"] / SAMPLE_RATE, 2)}
            for s in stamps]


def _run_whisper(model, audio, prompt=None):
    """One transcription pass. Returns (text, words)."""
    opts = dict(language="en", beam_size=5, vad_filter=True, word_timestamps=True,
                condition_on_previous_text=False)
    if prompt:
        # The style prompt only reaches the first 30-second window, so for this
        # pass each window is also shown the text of the one before it
        # (condition_on_previous_text). That text is full of "um"s too, so the
        # hesitant style carries through the whole answer. Without it, fillers
        # after the first 30 seconds went missing again. (Sending the prompt
        # with every window via `hotwords` made Whisper skip whole stretches.)
        opts["initial_prompt"] = prompt
        opts["condition_on_previous_text"] = True
        # No temperature fallback: when a window fails Whisper's checks it
        # retries by sampling, which with this prompt could spend half a minute
        # on garbage. We drop failed windows below instead; if that costs too
        # many words, the whole pass is discarded.
        opts["temperature"] = 0.0
    segments, _info = model.transcribe(audio, **opts)
    texts, words = [], []
    for seg in segments:            # a generator: the work happens here
        if prompt and (seg.compression_ratio > 2.4 or seg.avg_logprob < -1.0):
            continue                # Whisper's own "this went wrong" thresholds
        texts.append(seg.text.strip())
        for w in seg.words or []:
            if w.word.strip():
                words.append({"w": w.word.strip(), "start": round(float(w.start), 2),
                              "end": round(float(w.end), 2)})
    return " ".join(t for t in texts if t), words


# ---------------------------------------------------------------- text helpers

def _norm(word):
    """Lowercase a Whisper word and strip surrounding punctuation."""
    return re.sub(r"^[^a-z0-9']+|[^a-z0-9']+$", "", word.lower().replace("’", "'"))


def _filler(norm):
    """The canonical filler ("um", "uh", ...) this word is, or None."""
    if not norm:
        return None
    for pattern, canon in _FILLER_PATTERNS:
        if pattern.match(norm):
            return canon
    return None


def _real_word_count(words):
    """Words that aren't fillers or bare punctuation."""
    return sum(1 for w in words if (n := _norm(w["w"])) and not _filler(n))


def _find_disfluencies(words):
    """Find fillers and crutch words.

    Returns (fillers, crutches, hits) where fillers and crutches are Counters
    and hits lists the word index where each one starts.
    """
    toks = [_norm(w["w"]) for w in words]
    raw = [w["w"] for w in words]
    fillers, crutches, hits = Counter(), Counter(), []
    i = 0
    while i < len(toks):
        t = toks[i]
        prev = toks[i - 1] if i > 0 else ""
        nxt = toks[i + 1] if i + 1 < len(toks) else ""
        f = _filler(t)
        if f:
            fillers[f] += 1
            hits.append(i)
            i += 1
            continue
        pair = (t, nxt)
        if pair in CRUTCH_PAIRS:
            literal = CRUTCH_PAIRS[pair]
            if literal is None:          # "sort of" / "kind of": not after a determiner
                literal = DETERMINERS
            if prev not in literal and not (pair == ("i", "mean") and
                                            i + 2 < len(toks) and toks[i + 2] == "it"):
                crutches[" ".join(pair)] += 1
                hits.append(i)
                i += 2
                continue
        if t in CRUTCH_SINGLE:
            crutches[t] += 1
            hits.append(i)
        elif t == "like":
            # "like" is a filler only in filler positions: after a comma, at a
            # sentence start, before a comma or sentence end, or next to a
            # filler. Not straight after "it's" / "was" ("it's like, wow"
            # is reported speech, not a filler); "it was, like, huge" still counts.
            prev_raw = raw[i - 1] if i > 0 else ""
            if prev in BE_FORMS and not prev_raw.endswith(","):
                pass
            elif (i == 0 or prev_raw.endswith((",", ".", "?", "!", "-", "—"))
                    or raw[i].endswith((",", ".", "?", "!", "...", "-", "—"))
                    or _filler(nxt) or _filler(prev)):
                crutches["like"] += 1
                hits.append(i)
        i += 1
    return fillers, crutches, hits


def _fold(word):
    """Very simple plural folding: stories->story, boxes->box, books->book."""
    if word.endswith("'s"):
        word = word[:-2]
    if word in NO_FOLD or word.endswith(("ics", "ews")):      # physics, news: not plurals
        return word
    if len(word) > 4 and word.endswith("ies"):
        return word[:-3] + "y"
    if len(word) > 4 and word.endswith(("sses", "xes", "zes", "ches", "shes")):
        return word[:-2]
    if len(word) > 3 and word.endswith("s") and not word.endswith(("ss", "us", "is")):
        return word[:-1]
    return word


def _repeats(words, topic):
    """Content words used 3+ times that aren't from the topic, most used first."""
    topic_forms = {_fold(_norm(t)) for t in topic.split()} - {""}

    def from_topic(form):
        for t in topic_forms:
            if form == t:
                return True
            short, long_ = sorted((form, t), key=len)
            if len(short) >= 4 and long_.startswith(short):     # read / reading
                return True
        return False

    groups, surfaces = Counter(), {}
    for w in words:
        n = _norm(w["w"])
        if n.endswith("'s"):
            n = n[:-2]
        # Skip short words, numbers, contractions (didn't, they're) and fillers.
        if len(n) < 4 or not re.fullmatch(r"[a-z][a-z-]*", n) or n in STOP_WORDS or _filler(n):
            continue
        form = _fold(n)
        if form in STOP_WORDS or from_topic(form):
            continue
        groups[form] += 1
        surfaces.setdefault(form, Counter())[n] += 1
    out = [{"word": surfaces[f].most_common(1)[0][0], "count": c}
           for f, c in groups.items() if c >= 3]
    out.sort(key=lambda r: (-r["count"], r["word"]))
    return out


# ---------------------------------------------------------------- metrics

def _per_min(count, seconds):
    return round(count * 60.0 / seconds, 1) if seconds > 0 else 0.0


def _metrics(duration, segments, plain_words, source_words, topic):
    """All the numbers. source_words is the verbatim pass if kept, else the plain pass."""
    speaking = sum((s["end"] - s["start"] for s in segments), 0.0)
    start_delay = segments[0]["start"] if segments else 0.0
    span = (segments[-1]["end"] - segments[0]["start"]) if segments else 0.0

    gaps = [{"at": round(a["end"], 2), "len": round(b["start"] - a["end"], 2)}
            for a, b in zip(segments, segments[1:])]
    pauses = [g for g in gaps if g["len"] >= LONG_PAUSE]

    n_words = _real_word_count(plain_words)
    fillers, crutches, hits = _find_disfluencies(source_words)

    # Clean first sentence: something was said, no filler or crutch in the
    # opening words, and no long pause before the last of those words starts.
    clean = bool(source_words)
    if clean:
        real = [i for i, w in enumerate(source_words) if _norm(w["w"])]
        cut = real[OPENING_WORDS - 1] if len(real) >= OPENING_WORDS else (real[-1] if real else 0)
        if any(h <= cut for h in hits):
            clean = False
        cut_time = source_words[cut]["start"]
        if any(p["at"] < cut_time for p in pauses):
            clean = False

    return {
        "words": n_words,
        "speaking_time": round(speaking, 2),
        "wpm": _per_min(n_words, duration),
        "wpm_speaking": _per_min(n_words, speaking),
        "fillers": sum(fillers.values()),
        "fillers_per_min": _per_min(sum(fillers.values()), span or duration),
        "filler_words": dict(fillers.most_common()),
        "crutch": sum(crutches.values()),
        "crutch_words": dict(crutches.most_common()),
        "long_pauses": len(pauses),
        "pauses": pauses,
        "longest_pause": max((g["len"] for g in gaps), default=0.0),
        "silence_ratio": round(1 - speaking / span, 3) if span > 0 else 0.0,
        "first_sentence_clean": clean,
        "repeats": _repeats(plain_words, topic),
        "start_delay": round(start_delay, 2),
    }


def _prompt_echoed(verbatim_words, plain_words):
    """True if the verbatim pass parroted a run of the style prompt (about six
    words or more) that the plain pass didn't hear: a sign it transcribed the
    prompt, not the audio. Fillers are left out first, and a short overlap
    like "the thing is, you know" is allowed, since people really say that."""
    def grams(tokens):
        tokens = [n for n in (_norm(t) for t in tokens) if n and not _filler(n)]
        return {tuple(tokens[i:i + 4]) for i in range(len(tokens) - 3)}
    echoed = grams(DISFLUENT_PROMPT.split()) & grams(w["w"] for w in verbatim_words)
    return len(echoed - grams(w["w"] for w in plain_words)) >= 3


# ---------------------------------------------------------------- public API

def transcribe(path: str, topic: str = "") -> dict:
    """Transcribe one recorded answer and measure how it was spoken.

    `topic` is the prompt the speaker was given; its words don't count as
    repetition. Returns a JSON-serialisable dict (see the module docstring).
    Empty or silent audio gives zeros and empty text. Audio that can't be
    decoded raises ValueError.
    """
    t0 = time.time()
    audio = _decode(path)
    duration = round(audio.size / SAMPLE_RATE, 2)

    with _lock_run:
        segments = _speech_segments(audio)
        plain_text, plain_words = "", []
        verb_text, verb_words, verbatim_used = "", [], False
        if segments:
            model = _get_model()
            with ThreadPoolExecutor(max_workers=1) as pool:
                verbatim = pool.submit(_run_whisper, model, audio, DISFLUENT_PROMPT) \
                    if PASSES > 1 else None
                plain_text, plain_words = _run_whisper(model, audio)
                try:
                    verb_text, verb_words = verbatim.result() if verbatim else \
                        _run_whisper(model, audio, DISFLUENT_PROMPT)
                    verbatim_used = bool(plain_words) and (
                        _real_word_count(verb_words) >= VERBATIM_MIN_RATIO * _real_word_count(plain_words)
                        and not _prompt_echoed(verb_words, plain_words))
                except Exception:
                    verbatim_used = False
            if not verbatim_used:
                verb_text, verb_words = "", []

    metrics = _metrics(duration, segments, plain_words,
                       verb_words if verbatim_used else plain_words, topic)
    return {
        "duration": duration,
        "text": plain_text,
        "text_verbatim": verb_text,
        "verbatim_used": verbatim_used,
        "words": plain_words,
        "segments": segments,
        "metrics": metrics,
        "model": MODEL_NAME,
        "seconds": round(time.time() - t0, 2),
    }
