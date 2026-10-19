#!/usr/bin/env python3
"""Draft the practice content in content/ with Claude, check it blind, write the files.

    .venv/bin/python tools/gen_content.py --work /some/scratch/folder all
    .venv/bin/python tools/gen_content.py --work /some/scratch/folder technique

Steps: jam (Just a Minute topics), table (Table Topics with follow-ups) and
technique (Technique or Fair Move?). Technique items are drafted by the main
model, then a different model labels every item blind (technique or fair, and
which technique); only items where the blind label matches the key are kept,
and short buckets get one top-up round.

Raw drafts and blind answers are cached in the work folder, so a rerun only pays
for what's missing. Read the output over before committing it.
"""
import argparse
import json
import math
import random
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from binah import benchgen as bg  # noqa: E402

CONTENT = ROOT / "content"
PER = 10            # final items per technique per kind
DRAFT_EACH = 13     # first-round drafts per technique per kind
JAM_TARGET, TABLE_TARGET = 200, 120
STYLE_EXAMPLES = ["Lighthouses", "My first job", "The perfect sandwich",
                  "Why I'd make a terrible spy", "Things I learned from my grandmother", "Maps"]

AVOID_TOPICS = ("No sensitive or painful topics: illness, death, grief, trauma, money worries, "
                "politics, religion, break-ups, bodies and weight, alcohol, drugs, gambling. "
                "No real people, brands or trademarks.")


def write_json(name, data):
    CONTENT.mkdir(exist_ok=True)
    path = CONTENT / name
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote {path.relative_to(ROOT)}: {len(data)} items")


# ---------------------------------------------------------------- Just a Minute

def jam(budget, work):
    n = JAM_TARGET + 30
    prompt = f"""Write {n} topics for "Just a Minute", the radio panel game in which a speaker must talk for sixty seconds on a subject without hesitation, repetition or deviation.

The topics should be in the show's style: short (1 to 6 words), open, concrete or playful, giving a speaker plenty of directions to go. Examples of the style (don't reuse them): {"; ".join(STYLE_EXAMPLES)}.

Fields:
- topic
- level: "easy" (concrete and everyday, lots to say), "medium", or "hard" (abstract ideas, or subjects that are hard to fill for a minute without repeating yourself)
- kind: "everyday", "ideas", "places", "memory" (starts from the speaker's own life) or "playful"

Mix: about 30% everyday, 20% ideas, 15% places (kinds of places, or famous places anyone could talk about), 15% memory, 20% playful. Levels about 40% easy, 40% medium, 20% hard; ideas should mostly be medium or hard.

{AVOID_TOPICS} Every topic distinct; avoid near-repeats."""
    schema = bg._obj({"items": bg._arr(bg._obj({
        "topic": bg.S, "level": bg._enum(["easy", "medium", "hard"]),
        "kind": bg._enum(["everyday", "ideas", "places", "memory", "playful"])}))})
    out = bg.call(budget, "jam", prompt, schema, bg.DRAFT_SYSTEM, cache_dir=work)
    if not out:
        print("jam: drafting failed")
        return
    seen, items = {e.lower() for e in STYLE_EXAMPLES}, []
    for it in out["items"]:
        topic = it["topic"].strip().rstrip(".")
        key = topic.lower()
        if key in seen or not 1 <= len(topic.split()) <= 6:
            continue
        seen.add(key)
        items.append({"topic": topic, "level": it["level"], "kind": it["kind"]})
    items = trim_balanced(items, JAM_TARGET, "kind")
    write_json("jam_topics.json", [{"id": f"j{i + 1:03d}", **it} for i, it in enumerate(items)])
    return {"drafted": len(out["items"]), "kept": len(items)}


def trim_balanced(items, target, field):
    """Drop from the most common groups until target is reached, keeping the order."""
    items = list(items)
    while len(items) > target:
        counts = Counter(it[field] for it in items)
        big = counts.most_common(1)[0][0]
        last = max(i for i, it in enumerate(items) if it[field] == big)
        items.pop(last)
    return items


# ---------------------------------------------------------------- Table Topics

def table(budget, work):
    n = TABLE_TARGET + 15
    prompt = f"""Write {n} Table Topics questions in the Toastmasters style: an impromptu question a speaker answers for one to two minutes with no preparation.

Fields:
- prompt: one or two sentences, a direct question or a "tell us about..." request.
- follow_up: ONE probing question a good interviewer would ask after hearing the answer. It must work whatever the speaker said, and push for a reason, an example, a counter-case or a deeper layer.
- level: "easy" (personal and concrete), "medium" (an opinion or a choice to defend) or "hard" (an abstract idea, a small dilemma or a hypothetical that needs structure).

Mix: about 40% easy, 40% medium, 20% hard. Vary the ground widely: work, childhood, travel, food, learning, skills, technology, nature, habits, cities, books and stories, small everyday dilemmas, hypotheticals.

{AVOID_TOPICS} Every question distinct."""
    schema = bg._obj({"items": bg._arr(bg._obj({
        "prompt": bg.S, "follow_up": bg.S, "level": bg._enum(["easy", "medium", "hard"])}))})
    out = bg.call(budget, "table", prompt, schema, bg.DRAFT_SYSTEM, cache_dir=work)
    if not out:
        print("table: drafting failed")
        return
    items = []
    for it in out["items"]:
        if any(bg.too_similar(it["prompt"], k["prompt"], 0.5) for k in items):
            continue
        items.append({"prompt": it["prompt"].strip(), "follow_up": it["follow_up"].strip(),
                      "level": it["level"]})
    items = trim_balanced(items, TABLE_TARGET, "level")
    write_json("table_topics.json",
               [{"id": f"tt{i + 1:03d}", **it} for i, it in enumerate(items)])
    return {"drafted": len(out["items"]), "kept": len(items)}


# ---------------------------------------------------------------- Technique or Fair Move?

def _collect(outs, pool, stats):
    for out in outs:
        for it in (out or {}).get("items", []):
            stats["drafted"] += 1
            if not bg.technique_ok(it):
                stats["format"] += 1
                continue
            if any(bg.too_similar(it["text"], p["text"]) for p in pool):
                stats["duplicate"] += 1
                continue
            it["id"] = f"c{len(pool) + stats['format'] + stats['duplicate'] + 1}"
            pool.append(it)


def _check(budget, work, items, tag):
    halves = [items[i::2] for i in range(2)] if len(items) > 110 else [items]
    jobs = [(bg.classify, budget, f"{tag}-check-{k + 1}", h, work) for k, h in enumerate(halves)]
    verdicts = {}
    for v in bg.parallel(jobs):
        verdicts.update(v)
    for it in items:
        it["blind"] = verdicts.get(it["id"])
        it["passed"] = bg.technique_passes(it, it["blind"])


def technique(budget, work):
    stats = Counter()
    pool = []
    pairs = [bg.LABELS[i:i + 2] for i in range(0, len(bg.LABELS), 2)]
    jobs = [(bg.call, budget, f"tech-draft-{k + 1}",
             bg.technique_prompt({lab: (DRAFT_EACH, DRAFT_EACH) for lab in pair}, political=5),
             bg._obj({"items": bg._arr(bg.TECH_ITEM)}), bg.DRAFT_SYSTEM, "main", work)
            for k, pair in enumerate(pairs)]
    _collect(bg.parallel(jobs), pool, stats)
    _check(budget, work, pool, "tech")

    def passing(label, kind):
        return [it for it in pool if it["technique"] == label and it["kind"] == kind
                and it["passed"]]

    first_round = {"checked": len(pool), "passed": sum(it["passed"] for it in pool)}
    deficit = {}
    for lab in bg.LABELS:
        need = [max(0, PER - len(passing(lab, k))) for k in ("technique", "fair")]
        if any(need):
            deficit[lab] = tuple(math.ceil(n * 1.7) + 1 if n else 0 for n in need)
    if deficit:
        before = len(pool)
        avoid = ("\nThese items must be fresh: avoid these topics and angles, already used:\n"
                 + "\n".join(f"- {it['text'][:90]}" for it in pool if it["technique"] in deficit))
        out = bg.call(budget, "tech-topup", bg.technique_prompt(deficit, avoid=avoid),
                      bg._obj({"items": bg._arr(bg.TECH_ITEM)}), bg.DRAFT_SYSTEM,
                      cache_dir=work)
        _collect([out], pool, stats)
        _check(budget, work, pool[before:], "tech-topup")

    # Choose PER per bucket, then balance left- and right-coded items by swapping.
    chosen = {}
    for lab in bg.LABELS:
        for kind in ("technique", "fair"):
            items = passing(lab, kind)
            topics = Counter()
            pick = []                             # draft order, but prefer topic variety
            for it in items:
                if len(pick) < PER and topics[it["topic"]] < 2:
                    pick.append(it)
                    topics[it["topic"]] += 1
            for it in items:
                if len(pick) < PER and it not in pick:
                    pick.append(it)
            chosen[(lab, kind)] = pick
    for _ in range(40):
        lean = Counter(it["lean"] for pick in chosen.values() for it in pick)
        if abs(lean["left"] - lean["right"]) <= 1:
            break
        heavy, light = ("left", "right") if lean["left"] > lean["right"] else ("right", "left")
        swapped = False
        for key, pick in chosen.items():
            spare = [it for it in passing(*key) if it not in pick and it["lean"] != heavy]
            spare.sort(key=lambda it: it["lean"] != light)
            out = [it for it in pick if it["lean"] == heavy]
            if spare and out:
                pick[pick.index(out[0])] = spare[0]
                swapped = True
                break
        if not swapped:
            break

    final = []
    for lab in bg.LABELS:
        t, f = chosen[(lab, "technique")], chosen[(lab, "fair")]
        for a, b in zip(t + [None] * len(f), f + [None] * len(t)):
            final += [x for x in (a, b) if x]
    out_items = [{"id": f"t{i + 1:03d}", **{k: it[k] for k in bg.TECH_FIELDS[1:]}}
                 for i, it in enumerate(final)]
    write_json("technique.json", out_items)

    checked = pool
    report = {
        "drafted": stats["drafted"], "format_drops": stats["format"],
        "duplicate_drops": stats["duplicate"], "checked": len(checked),
        "passed": sum(it["passed"] for it in checked), "first_round": first_round,
        "pass_by_kind": {k: f"{sum(it['passed'] for it in checked if it['kind'] == k)}/"
                            f"{sum(1 for it in checked if it['kind'] == k)}"
                         for k in ("technique", "fair")},
        "pass_by_label": {lab: f"{sum(it['passed'] for it in checked if it['technique'] == lab)}/"
                               f"{sum(1 for it in checked if it['technique'] == lab)}"
                          for lab in bg.LABELS},
        "fail_reasons": dict(Counter(
            ("kind" if not it["blind"] or it["blind"][0] != it["kind"] else "label")
            + ":" + it["kind"] for it in checked if not it["passed"])),
        "final": len(out_items),
        "final_buckets": {f"{lab}/{kind}": len(chosen[(lab, kind)])
                          for lab in bg.LABELS for kind in ("technique", "fair")},
        "final_lean": dict(Counter(it["lean"] for it in final)),
        "final_lean_by_kind": dict(Counter(f"{it['lean']}/{it['kind']}" for it in final)),
    }
    (work / "technique-report.json").write_text(json.dumps(report, indent=1))
    (work / "technique-pool.json").write_text(json.dumps(pool, indent=1, ensure_ascii=False))
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("step", choices=["jam", "table", "technique", "all"])
    ap.add_argument("--work", required=True, help="scratch folder for raw drafts (not the repo)")
    ap.add_argument("--max-calls", type=int, default=14)
    args = ap.parse_args()
    work = Path(args.work)
    work.mkdir(parents=True, exist_ok=True)
    budget = bg.Budget(args.max_calls)
    random.seed(1)
    steps = {"jam": jam, "table": table, "technique": technique}
    chosen = list(steps) if args.step == "all" else [args.step]
    if args.step == "all":   # bg.call caps the calls in flight, so these can overlap
        results = bg.parallel([(steps[s], budget, work) for s in chosen])
    else:
        results = [steps[args.step](budget, work)]
    for name, r in zip(chosen, results):
        print(f"{name}: {json.dumps(r, indent=1)}")
    print(f"Claude calls this run: {budget.used} ({budget.failed} failed)")


if __name__ == "__main__":
    main()
