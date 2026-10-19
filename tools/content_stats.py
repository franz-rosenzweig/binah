#!/usr/bin/env python3
"""Counts and field distributions for the game content and the sealed benchmark forms.

    .venv/bin/python tools/content_stats.py

For content/*.json it prints item counts and how each short field is spread.
For benchmark forms (config.BENCH_DIR / "forms") it prints only counts, types,
answer positions and lengths, never any item text, so the forms stay sealed.
"""
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from binah import config  # noqa: E402

# Fields whose values are labels worth tallying (free text is only measured).
LABEL_FIELDS = {"kind", "technique", "level", "type", "lean"}


def words(text):
    return len(str(text).split())


def spread(counter):
    return ", ".join(f"{k} {v}" for k, v in sorted(counter.items(), key=lambda kv: (-kv[1], kv[0])))


def length_line(values):
    if not values:
        return "-"
    values = sorted(values)
    return f"min {values[0]}, median {values[len(values) // 2]}, max {values[-1]} words"


def content_file(path):
    try:
        items = json.loads(path.read_text())
    except ValueError as e:
        print(f"\n{path.name}: not valid JSON ({e})")
        return
    print(f"\n{path.name}: {len(items)} items")
    if not items or not isinstance(items, list):
        return
    fields = list(items[0])
    ids = [it.get("id") for it in items]
    if len(set(ids)) != len(ids):
        print(f"  WARNING: {len(ids) - len(set(ids))} duplicate ids")
    missing = Counter(f for it in items for f in fields if f not in it)
    if missing:
        print(f"  WARNING: missing fields: {spread(missing)}")
    for f in fields:
        if f == "id":
            continue
        values = [it.get(f) for it in items if f in it]
        if f in LABEL_FIELDS:
            print(f"  {f}: {spread(Counter(values))}")
        elif all(isinstance(v, str) for v in values):
            print(f"  {f} length: {length_line([words(v) for v in values])}")
    if "kind" in fields and "technique" in fields:
        pairs = Counter((it["technique"], it["kind"]) for it in items)
        print("  per technique (technique / fair):")
        for tech in sorted({t for t, _ in pairs}):
            print(f"    {tech}: {pairs[(tech, 'technique')]} / {pairs[(tech, 'fair')]}")


def benchmark_forms(forms_dir):
    forms = sorted(forms_dir.glob("form-*.json")) if forms_dir.exists() else []
    print(f"\nbenchmark forms in {forms_dir}: {len(forms)} (sealed: counts only)")
    for path in forms:
        try:
            form = json.loads(path.read_text())
        except ValueError:
            print(f"  {path.name}: not valid JSON")
            continue
        print(f"  {form.get('id')} (v{form.get('version')}, created {form.get('created')}, "
              f"confidence {form.get('confidence')})")
        for sec in form.get("sections", []):
            kind = sec.get("kind")
            if kind == "argument":
                items = sec["items"]
                print(f"    argument: {len(items)} items; types {spread(Counter(i['type'] for i in items))}; "
                      f"answers {spread(Counter('ABCDE'[i['answer']] for i in items))}; "
                      f"stimulus {length_line([words(i['stimulus']) for i in items])}")
            elif kind == "discern":
                items = sec["items"]
                print(f"    discern: {len(items)} items; {spread(Counter(i['kind'] for i in items))}; "
                      f"{len({i['technique'] for i in items})} different techniques")
            elif kind == "inference":
                ps = sec["passages"]
                qs = [q for p in ps for q in p["questions"]]
                print(f"    inference: {len(ps)} passages ({', '.join(str(words(p['text'])) for p in ps)} "
                      f"words), {len(qs)} questions; answers "
                      f"{spread(Counter('ABCD'[q['answer']] for q in qs))}")
            elif kind == "essay":
                print(f"    essay: {sec.get('minutes')} min, rubric {', '.join(sec.get('rubric', {}))}")
            elif kind == "talk":
                print(f"    talk: {sec.get('seconds')} s")
            elif kind == "vocab":
                items = sec["items"]
                print(f"    vocab: {len(items)} items; answers "
                      f"{spread(Counter('ABCD'[i['answer']] for i in items))}")
            else:
                print(f"    {kind}: unknown section")


def main():
    content = config.CONTENT_DIR
    files = sorted(content.glob("*.json")) if content.exists() else []
    print(f"content in {content.relative_to(ROOT)}: {len(files)} files")
    for path in files:
        content_file(path)
    benchmark_forms(config.BENCH_DIR / "forms")


if __name__ == "__main__":
    main()
