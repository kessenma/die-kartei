#!/usr/bin/env python3
"""Read a Kasus bake-off drop (KASUS_STORY_DATA.md §4) and print the tables the decision needs.

Stories (`stories_*.jsonl`): every file through `kasus-cli check`, then per teacher config:
pass rate, planned phrases verbatim / altered / missing, gradable answers per case, the top
rejecting codes, tokens (and reasoning tokens), stories that ended early, and how many passing
stories the student could write inside the app's own budget (counted with the shipped tutor's
tokenizer). Writes 20 passing stories per config to `hand_read_<label>.md` for reading by hand,
since the check's blind spots are where a weak teacher hides.

Tail (`tail_*.jsonl`): the raw replies parsed into correction rows the way `generate_bulk.py`
does (manifest metadata forced), written to `tail_rows_<label>.jsonl`, with rows per job,
fix/ok per phenomenon and the no-op rate. Then run the usual gates on each rows file:
`scripts/validate_data.py`, `scripts/check_batch_composition.py`.

No pass bars here: the tables are read, not judged.

Usage:
    python scripts/kasus_bakeoff_report.py data/bakeoff/kasus-2026-10/drop
"""
import collections
import glob
import json
import os
import random
import statistics
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "kasus_cli" / "build" / "kasus-cli"
sys.path.insert(0, str(ROOT / "runpod" / "bakeoff"))
from generate_bulk import parse_rows  # noqa: E402

VERBATIM = {"placed", "triggerMissing", "shadowed"}


# Shape: does a fix row change the thing its phenomenon is about? The validator answers "is this
# correct German"; this answers "does it teach the skill" (training/CLAUDE.md lesson 2). Rough
# token tests, one per tail phenomenon, read next to a hand sample, not as a gate.
HABEN = {"habe", "hast", "hat", "haben", "habt", "hatte", "hattest", "hatten", "hattet"}
SEIN = {"bin", "bist", "ist", "sind", "seid", "war", "warst", "waren", "wart"}
K2 = {"hätte", "hättest", "hätten", "hättet", "wäre", "wärst", "wären", "wärt", "würde", "würdest",
      "würden", "würdet", "könnte", "könntest", "könnten", "könntet", "müsste", "müssten", "sollte",
      "sollten", "dürfte", "dürften", "möchte", "möchtest", "möchten", "ginge", "käme", "wüsste"}


def words(text):
    return [w.strip(".,!?;:„“\"'()").lower() for w in (text or "").split()]


def shape_ok(row):
    s, f = words(row.get("student")), words(row.get("fix"))
    phen = row["phenomenon"]
    if phen == "aux":
        return (bool(set(s) & HABEN) and bool(set(f) & SEIN)) or (bool(set(s) & SEIN) and bool(set(f) & HABEN))
    if phen == "k2":
        return sorted(w for w in s if w in K2) != sorted(w for w in f if w in K2)
    if phen == "negation":
        neg = lambda ws: sorted(w for w in ws if w == "nicht" or w.startswith("kein"))
        moved = "nicht" in s and "nicht" in f and s.index("nicht") != f.index("nicht")   # placement
        return neg(s) != neg(f) or moved
    if phen == "imperativ":
        changed = set(s) ^ set(f)
        return bool(changed & set(s[:2] + f[:2]))
    return None


def student_tokenizer():
    """The shipped tutor's tokenizer, to ask whether the student could write a story in budget."""
    snaps = glob.glob(os.path.expanduser(
        "~/.cache/huggingface/hub/models--kessenma--gemma4-e4b-german-tutor-v4-4bit/snapshots/*/"))
    if not snaps:
        return None
    from transformers import AutoTokenizer
    return AutoTokenizer.from_pretrained(snaps[0])


def median(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def stories(drop: Path, tok):
    files = sorted(f for f in drop.glob("stories_*.jsonl") if not f.name.endswith(".checked.jsonl"))
    if not files:
        return
    print("## Stories\n")
    rows = []
    for f in files:
        checked = f.with_suffix(".checked.jsonl")
        with open(checked, "w") as out:
            proc = subprocess.run([str(CLI), "check", str(f)], stdout=out, stderr=subprocess.PIPE, text=True)
        print(proc.stderr.strip(), "\n")
        gen = {json.loads(l)["id"]: json.loads(l) for l in open(f) if l.strip()}
        recs = [json.loads(l) for l in open(checked) if l.strip()]
        label = recs[0]["model"] if recs else f.stem
        passing = [r for r in recs if r["passed"]]
        places = [p["status"] for r in recs for p in r["report"]["placements"]]
        fit = None
        if tok is not None:
            fit = sum(1 for r in passing
                      if len(tok(r["raw"])["input_ids"]) <= gen[r["id"]].get("maxTokens", 10**9))
        codes = collections.Counter(c for r in recs if not r["passed"] for c in r["report"]["errorCodes"])
        rows.append({
            "label": label,
            "stories": len(recs),
            "pass": f"{len(passing)} ({len(passing) / max(1, len(recs)):.0%})",
            "verbatim": f"{sum(s in VERBATIM for s in places) / max(1, len(places)):.0%}",
            "altered": f"{places.count('altered') / max(1, len(places)):.0%}",
            "missing": f"{places.count('missing') / max(1, len(places)):.0%}",
            "pass+fits": fit if fit is not None else "?",
            "ended early": sum(1 for g in gen.values() if g.get("endedEarly")),
            "errors": sum(1 for g in gen.values() if g.get("error")),
            "med tokens": median([g.get("tokens") for g in gen.values()]),
            "med reasoning": median([g.get("reasoningTokens") for g in gen.values()]),
            "top rejects": ", ".join(f"{c} {n}" for c, n in codes.most_common(4)),
        })
        # A reproducible sample of passing stories, with the plan beside each.
        sample = random.Random(7).sample(passing, min(20, len(passing)))
        lines = [f"# Hand read · {label}\n", "Read for German the check can't see: prepositional objects "
                 "off the 42 pairs, nouns off the Goethe lists, adjective endings, anything unnatural.\n"]
        for r in sample:
            phrases = " · ".join(p["expression"] for p in r["plan"]["phrases"])
            lines += [f"## {r['id']} ({r['report']['summary']})", f"Plan: {phrases}", "", r["raw"].strip(), ""]
        (drop / f"hand_read_{label}.md").write_text("\n".join(lines))

    keys = list(rows[0].keys())
    print("| " + " | ".join(keys) + " |")
    print("|" + "---|" * len(keys))
    for r in rows:
        print("| " + " | ".join(str(r[k]) for k in keys) + " |")
    print("\n`pass+fits`: passing stories the shipped tutor's tokenizer fits inside the app's maxTokens.")
    print(f"Hand-read samples: {drop}/hand_read_<label>.md\n")


def tail(drop: Path):
    files = sorted(f for f in drop.glob("tail_*.jsonl") if not f.name.startswith("tail_rows_"))
    if not files:
        return
    print("## Correction tail\n")
    for f in files:
        jobs = [json.loads(l) for l in open(f) if l.strip()]
        label = jobs[0]["model"] if jobs else f.stem
        rows = []
        for j in jobs:
            for r in parse_rows(j.get("raw") or ""):
                r["task"] = "correction"
                r["phenomenon"] = j["phenomenon"]
                r["level"] = j.get("level", r.get("level"))
                r["formality"] = j.get("formality", r.get("formality"))
                if not isinstance(r.get("meta"), dict):
                    r["meta"] = {}
                r["meta"]["teacher"] = label
                rows.append(r)
        out = drop / f"tail_rows_{label}.jsonl"
        out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
        print(f"### {label}: {len(rows)} rows from {len(jobs)} jobs ({len(rows) / max(1, len(jobs)):.1f}/job, "
              f"asked 8) → {out.name}")
        print("| phenomenon | rows | fix | ok | no-op fix rows | right shape (of non-no-op fix) |\n|---|---|---|---|---|---|")
        by = collections.defaultdict(list)
        for r in rows:
            by[r["phenomenon"]].append(r)
        for phen, rs in sorted(by.items()):
            fix = [r for r in rs if r.get("verdict") == "fix"]
            noop = sum(1 for r in fix if (r.get("student") or "").strip() == (r.get("fix") or "").strip())
            live = [r for r in fix if (r.get("student") or "").strip() != (r.get("fix") or "").strip()]
            shaped = sum(1 for r in live if shape_ok(r))
            print(f"| {phen} | {len(rs)} | {len(fix)} | {sum(r.get('verdict') == 'ok' for r in rs)} | {noop} | "
                  f"{shaped}/{len(live)} ({shaped / max(1, len(live)):.0%}) |")
        print(f"\nGates: `.venv/bin/python scripts/validate_data.py {out}` and "
              f"`.venv/bin/python scripts/check_batch_composition.py {out}`\n")


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    drop = Path(sys.argv[1])
    if not CLI.exists():
        sys.exit(f"build kasus-cli first: {ROOT}/kasus_cli/build.sh")
    stories(drop, student_tokenizer())
    tail(drop)
    return 0


if __name__ == "__main__":
    sys.exit(main())
