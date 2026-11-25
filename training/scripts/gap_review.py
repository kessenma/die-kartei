#!/usr/bin/env python3
"""Plan a batch of gap-choice items (the reflexive packs), gate them, and write the files a person
reads before anything reaches the app.

Runs the app's own planner and gate through `kasus-cli` (build/kasus-cli; built here if missing):

  gap-plans   the planner writes the German and English from the tables in ReflexivForms.swift,
              a pack per focus, reproducible from --seed; never a sentence the bundle has
  gap-check   the gate's verdict per item and the pack's composition
  gap-export  the passing items in gap_choice_items.json format
  audit-gaps  the export audited the way the app audits its bundle

and writes, in the batch folder:

  candidates.jsonl      the planner's items, one per line
  check.jsonl           the gate's verdict per item
  candidates.json       the passing items in bundle format (ids rx-<prefix>-…)
  review.csv            every item, one row: focus, person, case, presentation, German, English,
                        the answer and options, the verb, the object, the gate's verdict, and
                        empty `reads_right` and `note` columns to fill in
  review.md             the same, grouped by focus and verb, passing items first
  summary.json          counts per focus, case, person and verb
  README.md             the run log (written once; edit it by hand afterwards)

A bad sentence is fixed in the table (ReflexivForms.swift), never in these files: rerun this
script with the same seed and the pack regenerates.

Usage (from training/):
    python3 scripts/gap_review.py data/gap-choice/reflexiv-2026-10 --focus case:120 person:100 --seed 7
    python3 scripts/gap_review.py data/gap-choice/reflexiv-2026-10 --merge     # after the read

--merge appends candidates.json to german-ai-flashcards/Resources/gap_choice_items.json (ids and
sentences already there are skipped), then prints the golden rows for GapChoiceFixtures.golden.
"""
import argparse
import collections
import csv
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
CLI = ROOT / "kasus_cli" / "build" / "kasus-cli"
BUNDLE = REPO / "german-ai-flashcards" / "Resources" / "gap_choice_items.json"
FOCUS_NAMES = {"case": "Akkusativ oder Dativ?", "person": "Die richtige Person"}
CASE = {"akkusativ": "Akk", "dativ": "Dat"}


def run(args: list[str], stdin: str = "") -> tuple[str, str, int]:
    proc = subprocess.run([str(CLI)] + args, input=stdin, capture_output=True, text=True)
    return proc.stdout, proc.stderr, proc.returncode


def ensure_cli() -> None:
    if CLI.exists():
        return
    print("building kasus-cli …")
    proc = subprocess.run([str(ROOT / "kasus_cli" / "build.sh")], capture_output=True, text=True)
    if proc.returncode != 0 or not CLI.exists():
        sys.exit(f"build.sh failed:\n{proc.stderr[-2000:]}")


def person(item: dict) -> str:
    return f"{item['subject']['person']}{item['subject']['number']}"


def plan(folder: Path, focuses: list[tuple[str, int]], seed: int, prefix: str) -> list[dict]:
    lines: list[str] = []
    log: list[str] = []
    for focus, count in focuses:
        out, err, code = run(["gap-plans", focus, "--count", str(count), "--seed", str(seed), "--prefix", prefix])
        if code != 0:
            sys.exit(f"gap-plans {focus} failed:\n{err}")
        lines += [l for l in out.splitlines() if l.strip()]
        log.append(err.strip())
        print(err.strip())
    (folder / "candidates.jsonl").write_text("\n".join(lines) + "\n")
    (folder / "plan.log").write_text("\n".join(log) + "\n")
    return [json.loads(l) for l in lines]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--focus", nargs="*", default=["case:120", "person:100"], help="focus:count …")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--prefix", default="s")
    ap.add_argument("--merge", action="store_true", help="append candidates.json to the bundle after the read")
    args = ap.parse_args()
    folder = Path(args.folder)
    folder.mkdir(parents=True, exist_ok=True)
    ensure_cli()

    if args.merge:
        merge(folder)
        return

    focuses = []
    for spec in args.focus:
        name, _, count = spec.partition(":")
        focuses.append((name, int(count or 100)))
    items = plan(folder, focuses, args.seed, args.prefix)
    text = (folder / "candidates.jsonl").read_text()

    out, err, code = run(["gap-check"], text)
    (folder / "check.jsonl").write_text(out)
    print(err.strip())
    verdicts = {v["id"]: v for v in (json.loads(l) for l in out.splitlines() if l.strip())}

    export, err, code = run(["gap-export"], text)
    if code != 0:
        sys.exit(f"gap-export failed:\n{err}")
    (folder / "candidates.json").write_text(export)
    exported = {i["id"] for i in json.loads(export)["items"]}
    print(err.strip().splitlines()[-1] if err.strip() else "")

    audit, _, code = run(["audit-gaps", str(folder / "candidates.json")])
    print(audit.strip().splitlines()[-1] if audit.strip() else "audit printed nothing")
    if code != 0:
        print(audit)

    rows = []
    for item in items:
        v = verdicts.get(item["id"], {})
        gap = item["gaps"][0]
        rows.append({
            "id": item["id"],
            "focus": item["focus"],
            "person": person(item),
            "case": CASE.get(gap.get("kasus", ""), gap.get("kasus", "")),
            "presentation": item.get("presentation", "buttons"),
            "german": v.get("sentence") or item["sentence"].replace("{1}", gap["answer"]),
            "english": item["english"],
            "answer": gap["answer"],
            "options": " / ".join(gap["options"]),
            "verb": "sich " + item["verb"]["lemma"],
            "object": (item.get("secondObject") or {}).get("text", ""),
            "tail": item.get("tail") or "",
            "gate": "pass" if v.get("passes") else (v.get("firstReject") or "reject"),
            "warnings": "; ".join(v.get("warnings") or []),
            "in_candidates": "yes" if item["id"] in exported else "no",
            "reads_right": "",
            "note": "",
        })
    order = {"case": 0, "person": 1}
    rows.sort(key=lambda r: (order.get(r["focus"], 9), r["verb"], r["person"], r["id"]))

    with (folder / "review.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    counts = collections.OrderedDict()
    for r in rows:
        c = counts.setdefault(r["focus"], {"written": 0, "pass": 0, "candidates": 0, "akk": 0, "dat": 0, "inline": 0,
                                           "persons": collections.Counter(), "verbs": collections.Counter()})
        c["written"] += 1
        c["pass"] += r["gate"] == "pass"
        c["candidates"] += r["in_candidates"] == "yes"
        c["akk"] += r["case"] == "Akk"
        c["dat"] += r["case"] == "Dat"
        c["inline"] += r["presentation"] == "inline"
        c["persons"][r["person"]] += 1
        c["verbs"][r["verb"]] += 1
    rejects = collections.Counter(r["gate"] for r in rows if r["gate"] != "pass")

    md = ["# Reflexive items from the planner: review sheet", "",
          f"Seed {args.seed}. " + ", ".join(f"{c['written']} {FOCUS_NAMES.get(k, k)}" for k, c in counts.items())
          + f"; {sum(c['pass'] for c in counts.values())} pass the gate, "
          f"{sum(c['candidates'] for c in counts.values())} in `candidates.json`.", "",
          "The German comes from the verb table, never from a model. Read each row: is it natural German a "
          "teacher would put on a worksheet, and is the English twin right? Mark `reads_right` (✓/✗) and a "
          "`note` in `review.csv`. A ✗ names a table row to fix (the verb's forms, its objects, a tail, the "
          "English pattern); then the pack is regenerated with the same seed.", "",
          "| focus | items | pass | candidates | Akk | Dat | inline |", "|---|---:|---:|---:|---:|---:|---:|"]
    for k, c in counts.items():
        md.append(f"| {FOCUS_NAMES.get(k, k)} | {c['written']} | {c['pass']} | {c['candidates']} | {c['akk']} | {c['dat']} | {c['inline']} |")
    if rejects:
        md += ["", "Rejects: " + ", ".join(f"{k} {v}" for k, v in rejects.most_common())]
    for k in counts:
        md += ["", f"## {FOCUS_NAMES.get(k, k)}", "",
               "persons: " + ", ".join(f"{p} {n}" for p, n in sorted(counts[k]["persons"].items())), ""]
        for verb in sorted(counts[k]["verbs"]):
            group = [r for r in rows if r["focus"] == k and r["verb"] == verb]
            md += [f"### {verb}", "", "| ✓/✗ | German | English | options | id |", "|---|---|---|---|---|"]
            for r in group:
                if r["gate"] != "pass":
                    continue
                md.append(f"|  | {r['german']} | {r['english']} | {r['options']}{' (inline)' if r['presentation'] == 'inline' else ''} | {r['id']} |")
            failed = [r for r in group if r["gate"] != "pass"]
            if failed:
                md += ["", "Turned away by the gate:", ""] + [f"- {r['german']} ({r['gate']})" for r in failed]
            md.append("")
    (folder / "review.md").write_text("\n".join(md) + "\n")
    summary = {k: {kk: (dict(vv) if isinstance(vv, collections.Counter) else vv) for kk, vv in c.items()} for k, c in counts.items()}
    (folder / "summary.json").write_text(json.dumps({"seed": args.seed, "focuses": summary, "rejects": rejects},
                                                    ensure_ascii=False, indent=2) + "\n")
    readme = folder / "README.md"
    if not readme.exists():
        readme.write_text(
            f"# Reflexive items from the planner ({folder.name})\n\n"
            f"Planned by `kasus-cli gap-plans` from the tables in `ReflexivForms.swift` (seed {args.seed}), gated by "
            "`gap-check`, exported by `gap-export`, audited by `audit-gaps`. No model wrote any of the German.\n\n"
            "**Nothing is in the app until it has been read.** Fill in `reads_right` and `note` in `review.csv`; a ✗ "
            "names a table row to fix, then rerun:\n\n"
            f"```bash\npython3 scripts/gap_review.py {folder.relative_to(ROOT) if folder.is_relative_to(ROOT) else folder} "
            f"--focus {' '.join(args.focus)} --seed {args.seed}\n```\n\n"
            "When the read is clean, `--merge` appends `candidates.json` to `Resources/gap_choice_items.json` and prints "
            "the golden rows for `GapChoiceFixtures.golden`.\n\n## Read\n\n(notes from the read go here)\n")
    print(f"wrote review.csv, review.md, candidates.json, summary.json in {folder}")


def merge(folder: Path) -> None:
    candidates = json.loads((folder / "candidates.json").read_text())["items"]
    bundle = json.loads(BUNDLE.read_text())
    ids = {i["id"] for i in bundle["items"]}
    sentences = {i["focus"] + ": " + i["sentence"].replace("{1}", i["gaps"][0]["answer"]).lower() for i in bundle["items"]}
    added = 0
    for item in candidates:
        sentence = item["focus"] + ": " + item["sentence"].replace("{1}", item["gaps"][0]["answer"]).lower()
        if item["id"] in ids or sentence in sentences:
            continue
        bundle["items"].append(item)
        ids.add(item["id"])
        sentences.add(sentence)
        added += 1
    BUNDLE.write_text(json.dumps(bundle, ensure_ascii=False, indent=2) + "\n")
    print(f"merged {added} items into {BUNDLE.name} ({len(bundle['items'])} now)")
    out, _, code = run(["audit-gaps", "--golden"])
    print(out.strip())
    if code != 0:
        sys.exit("audit-gaps failed after the merge")


if __name__ == "__main__":
    main()
