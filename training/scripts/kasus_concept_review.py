#!/usr/bin/env python3
"""Turn a batch of written Verstehen items into files a person can review, and a candidate file
the app can load.

Reads the writers' `out_*.jsonl` (BRIEF.md format: plan, raw, english, phrasesEnglish,
questionEnglish) in a batch folder, runs them through the app's gate (`kasus-cli concept-check`)
and exporter (`kasus-cli concept-export`), audits the export the way the app audits its bundle
(`kasus-cli audit-concepts <file>`), and writes:

  review.csv            every item, one row: unit, exercise, German, English, planned roles,
                        what the writer added, the gate's verdict, and empty `reads_right` and
                        `note` columns to fill in
  review.md             the same, grouped by unit and exercise, passing items first
  candidates.json       the passing items in kasus_concepts.json format (ids kc-<prefix>-…);
                        nothing goes into the app until it's been read
  summary.json          counts per unit and exercise

Usage (from training/):
    .venv/bin/python scripts/kasus_concept_review.py data/kasus-concepts-sonnet --prefix s
"""
import argparse
import collections
import csv
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "kasus_cli" / "build" / "kasus-cli"
UNITS = ["nominativ", "akkusativ", "dativ", "genitiv", "alleFaelle"]
UNIT_NAMES = {"nominativ": "Nominativ", "akkusativ": "Akkusativ", "dativ": "Dativ", "genitiv": "Genitiv",
              "alleFaelle": "Alle Fälle"}
KINDS = ["roles", "wer", "probe"]
KIND_NAMES = {"roles": "Rollen", "wer": "Wer macht was?", "probe": "Die Probe"}
CASE = {"nominativ": "Nom", "akkusativ": "Akk", "dativ": "Dat", "genitiv": "Gen"}
SHORT = {"nominativ": "nom", "akkusativ": "akk", "dativ": "dat", "genitiv": "gen", "alleFaelle": "alle"}


def run(args: list[str], stdin: str) -> tuple[str, str, int]:
    proc = subprocess.run([str(CLI)] + args, input=stdin, capture_output=True, text=True)
    return proc.stdout, proc.stderr, proc.returncode


def roles(plan: dict) -> str:
    out = []
    for p in plan["phrases"]:
        expr = (p.get("preposition") + " " if p.get("preposition") else "") + p["phrase"]
        out.append(f"{expr} = {CASE.get(p['caseRaw'], p['caseRaw'])} ({p['reasonRaw']})")
    return "; ".join(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--prefix", default="s")
    args = ap.parse_args()
    folder = Path(args.folder)

    lines = []
    for path in sorted(folder.glob("out_*.jsonl")):
        for line in path.read_text().splitlines():
            if line.strip():
                json.loads(line)  # fail loudly on a broken line
                lines.append(line)
    if not lines:
        sys.exit(f"no out_*.jsonl in {folder}")
    inputs = [json.loads(l) for l in lines]

    out, err, code = run(["concept-check"], "\n".join(lines))
    if code != 0:
        sys.exit(f"concept-check failed:\n{err}")
    verdicts = [json.loads(l) for l in out.splitlines() if l.strip()]
    print(err.strip())

    export, err, code = run(["concept-export", "--prefix", args.prefix], "\n".join(lines))
    if code != 0:
        sys.exit(f"concept-export failed:\n{err}")
    (folder / "candidates.json").write_text(export)
    exported = {i["id"]: i for i in json.loads(export)["items"]}
    print(err.strip().splitlines()[-1] if err.strip() else "")
    notes = [l for l in err.splitlines() if not l.startswith("concept-export:")]

    audit, _, code = run(["audit-concepts", str(folder / "candidates.json")], "")
    print(audit.strip().splitlines()[-1] if audit.strip() else "audit printed nothing")
    if code != 0:
        print(audit)

    rows = []
    for inp, v in zip(inputs, verdicts):
        plan = inp["plan"]
        kind = v["kind"]
        cid = f"kc-{args.prefix}-{SHORT[plan['unitRaw']]}-{kind}-{plan['seed']}"
        rows.append({
            "id": cid,
            "unit": plan["unitRaw"],
            "exercise": kind,
            "level": plan["level"],
            "german": v["sentence"] or v["raw"],
            "english": inp.get("english", ""),
            "question_en": inp.get("questionEnglish", "") if kind == "wer" else "",
            "planned_roles": roles(plan),
            "added": "; ".join(v.get("extras") or []),
            "gate": "pass" if v["passes"] else (v["firstReject"] or "reject"),
            "in_candidates": "yes" if cid in exported else "no",
            "reads_right": "",
            "note": "",
        })
    rows.sort(key=lambda r: (UNITS.index(r["unit"]), KINDS.index(r["exercise"]), r["gate"] != "pass", r["id"]))

    with (folder / "review.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    counts = collections.OrderedDict()
    for r in rows:
        c = counts.setdefault(f"{r['unit']}/{r['exercise']}", {"written": 0, "pass": 0, "candidates": 0})
        c["written"] += 1
        c["pass"] += r["gate"] == "pass"
        c["candidates"] += r["in_candidates"] == "yes"
    total = {k: sum(c[k] for c in counts.values()) for k in ("written", "pass", "candidates")}
    rejects = collections.Counter(r["gate"] for r in rows if r["gate"] != "pass")

    md = ["# Verstehen items written by Claude Sonnet: review sheet", "",
          f"{total['written']} written, {total['pass']} pass the app's gate, {total['candidates']} in "
          "`candidates.json` (a duplicate sentence or missing English drops an item).", "",
          "Mark each passing item: does it read as right, natural German, and do the planned roles match "
          "what the sentence says? The same rows are in `review.csv` with `reads_right` and `note` columns "
          "to fill in instead.", "",
          "| unit | exercise | written | pass | in candidates |", "|---|---|---:|---:|---:|"]
    for key, c in counts.items():
        unit, kind = key.split("/")
        md.append(f"| {UNIT_NAMES[unit]} | {KIND_NAMES[kind]} | {c['written']} | {c['pass']} | {c['candidates']} |")
    md.append(f"| **all** | | {total['written']} | {total['pass']} | {total['candidates']} |")
    if rejects:
        md += ["", "Rejects: " + ", ".join(f"{k} {v}" for k, v in rejects.most_common())]
    if notes:
        md += ["", "Exporter notes:", ""] + [f"- {n}" for n in notes]
    for unit in UNITS:
        for kind in KINDS:
            group = [r for r in rows if r["unit"] == unit and r["exercise"] == kind]
            if not group:
                continue
            md += ["", f"## {UNIT_NAMES[unit]} · {KIND_NAMES[kind]}", "",
                   "| ✓/✗ | German | English | planned roles | id |", "|---|---|---|---|---|"]
            for r in group:
                if r["gate"] != "pass":
                    continue
                en = r["english"] + (f" · Q: {r['question_en']}" if r["question_en"] else "")
                md.append(f"|  | {r['german']} | {en} | {r['planned_roles']} | {r['id']} |")
            failed = [r for r in group if r["gate"] != "pass"]
            if failed:
                md += ["", "Turned away by the gate:", ""]
                md += [f"- {r['german']} ({r['gate']})" for r in failed]
    (folder / "review.md").write_text("\n".join(md) + "\n")
    (folder / "summary.json").write_text(json.dumps({"total": total, "slots": counts, "rejects": rejects},
                                                    ensure_ascii=False, indent=2) + "\n")
    print(f"wrote review.csv, review.md, candidates.json, summary.json in {folder}")


if __name__ == "__main__":
    main()
