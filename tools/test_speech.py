#!/usr/bin/env python3
"""Smoke test for binah.speech.

Cuts a 60-second excerpt from any spoken-word file, re-encodes it the way
browsers record (WebM/Opus 48 kHz mono like Chrome and Android, fragmented
MP4/AAC like Safari), runs transcribe() on each and prints a short report.
Also checks that silent, empty and corrupt files behave.

    .venv/bin/python tools/test_speech.py SOURCE_AUDIO [--start 600] [--length 60] [--topic "..."]

Test clips go to a temporary folder that is deleted afterwards.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from binah import speech  # noqa: E402

FORMATS = {
    # name: (file extension, ffmpeg codec args, PyAV codec, container options)
    "webm-opus": ("webm", ["-c:a", "libopus", "-b:a", "64k", "-f", "webm", "-live", "1"],
                  "libopus", {}),
    "mp4-aac": ("mp4", ["-c:a", "aac", "-b:a", "96k", "-f", "mp4",
                        "-movflags", "frag_keyframe+empty_moov+default_base_moof"],
                "aac", {"movflags": "frag_keyframe+empty_moov+default_base_moof"}),
}


def make_clip(src, out, start, length, fmt):
    """Excerpt + re-encode at 48 kHz mono, with ffmpeg if present, else PyAV."""
    ext, ff_args, av_codec, av_opts = FORMATS[fmt]
    if shutil.which("ffmpeg"):
        cmd = ["ffmpeg", "-v", "error", "-y", "-ss", str(start), "-t", str(length), "-i", src,
               "-vn", "-ac", "1", "-ar", "48000", *ff_args, out]
        subprocess.run(cmd, check=True)
        return
    import av
    with av.open(src) as inp, av.open(out, "w", format="webm" if ext == "webm" else "mp4",
                                      options=av_opts) as outp:
        ost = outp.add_stream(av_codec, rate=48000, layout="mono")
        res = av.AudioResampler(format=ost.format.name if ost.format else "fltp",
                                layout="mono", rate=48000)
        inp.seek(int(start * 1_000_000))
        for frame in inp.decode(audio=0):
            if frame.time is None or frame.time < start:
                continue
            if frame.time > start + length:
                break
            frame.pts = None
            for f in res.resample(frame):
                outp.mux(ost.encode(f))
        outp.mux(ost.encode(None))


def make_silence(out, seconds=5):
    if shutil.which("ffmpeg"):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        f"anullsrc=r=48000:cl=mono", "-t", str(seconds),
                        "-c:a", "libopus", "-f", "webm", out], check=True)
    else:
        import av
        import numpy as np
        with av.open(out, "w", format="webm") as o:
            st = o.add_stream("libopus", rate=48000, layout="mono")
            frame = av.AudioFrame.from_ndarray(np.zeros((1, 48000 * seconds), dtype=np.int16),
                                               format="s16", layout="mono")
            frame.sample_rate = 48000
            for p in st.encode(frame):
                o.mux(p)
            o.mux(st.encode(None))


def report(name, r):
    m = r["metrics"]
    reps = ", ".join(f'{x["word"]}x{x["count"]}' for x in m["repeats"][:6]) or "-"
    print(f"\n== {name}")
    print(f"  duration {r['duration']}s   processed in {r['seconds']}s   model {r['model']}")
    print(f"  words {m['words']}   wpm {m['wpm']}   wpm_speaking {m['wpm_speaking']}   "
          f"speaking_time {m['speaking_time']}s   start_delay {m['start_delay']}s")
    print(f"  verbatim_used {r['verbatim_used']}   fillers {m['fillers']} "
          f"({m['fillers_per_min']}/min) {json.dumps(m['filler_words'])}   "
          f"crutch {m['crutch']} {json.dumps(m['crutch_words'])}")
    print(f"  long_pauses {m['long_pauses']} {[(p['at'], p['len']) for p in m['pauses']]}   "
          f"longest {m['longest_pause']}s   silence_ratio {m['silence_ratio']}   "
          f"segments {len(r['segments'])}")
    print(f"  first_sentence_clean {m['first_sentence_clean']}   repeats {reps}")
    print(f"  text: {r['text'][:200]!r}")
    if r["verbatim_used"]:
        print(f"  verbatim: {r['text_verbatim'][:200]!r}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", nargs="?", help="any spoken-word audio file")
    ap.add_argument("--start", type=float, default=600, help="excerpt start, seconds")
    ap.add_argument("--length", type=float, default=60, help="excerpt length, seconds")
    ap.add_argument("--topic", default="", help="topic words to leave out of repeats")
    ap.add_argument("--json", action="store_true", help="also dump the full result as JSON")
    args = ap.parse_args()

    tmp = tempfile.mkdtemp(prefix="binah-speech-")
    try:
        # Edge cases first: they're quick and must never crash.
        empty = os.path.join(tmp, "empty.webm")
        open(empty, "wb").close()
        r = speech.transcribe(empty)
        assert r["duration"] == 0 and r["text"] == "" and r["metrics"]["words"] == 0, r
        print("empty file: ok (zeros)")

        silent = os.path.join(tmp, "silent.webm")
        make_silence(silent)
        r = speech.transcribe(silent)
        assert r["text"] == "" and r["metrics"]["words"] == 0 and not r["segments"], r
        json.dumps(r)
        print(f"silent 5 s: ok (duration {r['duration']}s, no speech)")

        corrupt = os.path.join(tmp, "corrupt.webm")
        with open(corrupt, "wb") as f:
            f.write(os.urandom(4096))
        try:
            speech.transcribe(corrupt)
            print("corrupt file: FAILED (no error raised)")
        except ValueError as e:
            print(f"corrupt file: ok (ValueError: {e})")

        if not args.source:
            print("\nNo source audio given, so only the edge cases ran.")
            return

        for fmt in FORMATS:
            out = os.path.join(tmp, f"clip.{FORMATS[fmt][0]}")
            t = time.time()
            make_clip(args.source, out, args.start, args.length, fmt)
            enc = time.time() - t
            r = speech.transcribe(out, topic=args.topic)
            json.dumps(r)               # must be JSON-serialisable
            report(f"{fmt}  ({os.path.getsize(out) // 1024} KB, encoded in {enc:.1f}s)", r)
            if args.json:
                print(json.dumps(r, indent=1)[:4000])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
