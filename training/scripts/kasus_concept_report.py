#!/usr/bin/env python3
"""Read a Verstehen-item probe (KASUS_CONCEPT_PROBE.md) and print the tables the decision needs.

Every `raw_<label>.jsonl` from kasus_concept_probe.py goes through `kasus-cli concept-check`
(the app's own gate), next to the no-model template baseline. Per model and exercise: pass rate,
passes with nothing added ("bare": no extra phrase behind a preposition, the strict variant),
planned phrases kept verbatim, Wer order honoured, median seconds, and the reject codes split
into the two families that matter:

  * German about cases: a planned article changed (der→den, a case moved), a possessive in its
    place, the verb in the wrong form, a validator error
  * instructions ignored: a second clause, an extra phrase, two sentences, the wrong order
  * unprovable: an added phrase behind a preposition whose case the gate can't prove („am
    Wochenende“, „zum neuen Job“ with a noun the lexicon lacks); not wrong, just not vouched for

Writes `hand_read_<label>.md` (20 passing items per model, seeded, with the planned roles beside
each) for reading by hand: a passing item that still reads wrong is what a learner would see, and
only a person can count those. Also a sample of rejects, and `summary.json`, copied to
`results/kasus-concept-probe_<date>.json`.

No pass bars here: the tables are read, not judged.

Usage (from training/):
    .venv/bin/python scripts/kasus_concept_report.py [results/kasus-concept-probe]
"""
import collections
import datetime
import json
import random
import re
import statistics
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "kasus_cli" / "build" / "kasus-cli"
ORDER = ["template", "e4b", "e2b", "granite41-3b", "granite33-2b"]
KINDS = ["roles", "wer", "probe"]

CASE_FAMILY = {"concept.phraseAltered", "concept.verbMissing", "concept.roleUnsure"}
INSTRUCTION_FAMILY = {"concept.notSimple", "concept.extraPhrase", "concept.notOneSentence",
                      "concept.orderIgnored", "concept.ambiguousRoles", "concept.empty", "concept.extraPerson"}
DETERMINERS = {"der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines"}
POSSESSIVE = re.compile(r"^(mein|dein|sein|ihr|unser|euer|ihr)(e|en|em|er|es)?$", re.I)


def check(lines: list[str], template: bool) -> tuple[list[dict], str]:
    args = [str(CLI), "concept-check"] + (["--template"] if template else [])
    proc = subprocess.run(args, input="\n".join(lines), capture_output=True, text=True)
    if proc.returncode not in (0,):
        sys.exit(f"concept-check failed ({proc.returncode}):\n{proc.stderr}")
    return [json.loads(l) for l in proc.stdout.splitlines() if l.strip()], proc.stderr


def article_change(record: dict) -> list[str]:
    """For each planned phrase not found verbatim: what stands in front of its noun instead
    („den Hund“ → „der Hund“, or a possessive)."""
    sentence = record.get("sentence") or ""
    words = re.findall(r"[\wäöüÄÖÜß]+", sentence)
    out = []
    for expression in record["phrases"]:
        if re.search(r"(?<![\wäöüß])" + re.escape(expression) + r"(?![\wäöüß])", sentence, re.I):
            continue
        parts = expression.split()
        noun, article = parts[-1], parts[-2] if len(parts) >= 2 else ""
        for i, w in enumerate(words):
            if w == noun and i > 0:
                before = words[i - 1]
                if before.lower() in DETERMINERS and before.lower() != article.lower():
                    out.append(f"{article} {noun} → {before.lower()} {noun}")
                elif POSSESSIVE.match(before):
                    out.append(f"{article} {noun} → {before} {noun} (possessive)")
                break
        else:
            out.append(f"{expression} → missing")
    return out


def family(code: str | None) -> str:
    if code is None:
        return "pass"
    if code == "concept.extraUnproven":
        return "unprovable"
    if code in INSTRUCTION_FAMILY:
        return "instructions"
    if code in CASE_FAMILY or not code.startswith("concept."):
        return "german"
    return "facts" if code == "concept.facts" else "other"


def pct(a: int, b: int) -> str:
    return "–" if b == 0 else f"{round(100 * a / b)}%"


def roles_line(record: dict, plan: dict) -> str:
    names = {"nominativ": "Nom", "akkusativ": "Akk", "dativ": "Dat", "genitiv": "Gen"}
    bits = []
    for p in plan["phrases"]:
        expr = (p.get("preposition") + " " if p.get("preposition") else "") + p["phrase"]
        bits.append(f"„{expr}“ {names.get(p['caseRaw'], p['caseRaw'])} ({p['reasonRaw']})")
    return " · ".join(bits)


def main() -> None:
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results" / "kasus-concept-probe"
    prompts = [l for l in (folder / "prompts.jsonl").read_text().splitlines() if l.strip()]
    plans = {json.loads(l)["id"]: json.loads(l)["plan"] for l in prompts}

    records, raws = [], {}
    tpl, _ = check(prompts, template=True)
    records += tpl
    for path in sorted(folder.glob("raw_*.jsonl")):
        lines = [l for l in path.read_text().splitlines() if l.strip()]
        for l in lines:
            r = json.loads(l)
            raws[(r["model"], r["id"], r.get("repeat", 0))] = r
        out, _ = check(lines, template=False)
        records += out
    for r in records:
        r["family"] = family(r["firstReject"])
        r["changes"] = article_change(r) if r["firstReject"] == "concept.phraseAltered" else []

    models = [m for m in ORDER if any(r["model"] == m for r in records)]
    summary = {"date": datetime.date.today().isoformat(), "prompts": len(prompts), "models": {}}

    print(f"Verstehen-item probe · {len(prompts)} plans · {folder}\n")
    print("model          exercise  n    pass        bare   verbatim  order   german  instr.  unprov.  facts  median s")
    for m in models:
        summary["models"][m] = {}
        for kind in KINDS + ["all"]:
            g = [r for r in records if r["model"] == m and (kind == "all" or r["kind"] == kind)]
            if not g:
                continue
            passed = sum(r["passes"] for r in g)
            verbatim = sum(r["placed"] == len(r["phrases"]) for r in g)
            asked = [r for r in g if r["kind"] == "wer"]
            order = sum("concept.orderIgnored" not in r["codes"] for r in asked)
            fam = collections.Counter(r["family"] for r in g)
            secs = sorted(r["seconds"] for r in g if r.get("seconds") is not None)
            median = f"{statistics.median(secs):.1f}" if secs else "–"
            rejects = collections.Counter(r["firstReject"] for r in g if r["firstReject"])
            bare = sum(r["passes"] and not r.get("extras") for r in g)
            print(f"{m:<14} {kind:<9} {len(g):<4} {passed:>3} ({pct(passed, len(g)):>4})  {bare:>4}  {pct(verbatim, len(g)):>8}  "
                  f"{(f'{order}/{len(asked)}' if asked else '–'):>6}  {fam['german']:>6}  {fam['instructions']:>6}  "
                  f"{fam['unprovable']:>7}  {fam['facts']:>5}  {median:>8}")
            summary["models"][m][kind] = {
                "n": len(g), "pass": passed, "passNothingAdded": bare, "verbatim": verbatim, "orderAsked": len(asked), "orderKept": order,
                "families": dict(fam), "rejects": dict(rejects.most_common()), "medianSeconds": median,
            }
        print()

    # The app would retry once: a plan yields an item when either of its first two samples passes.
    print("Plans that yield an item: first try / with one retry (needs --repeats 2)")
    for m in models:
        if m == "template":
            continue
        tries = collections.defaultdict(list)
        for r in records:
            if r["model"] == m:
                tries[(r["kind"], r["id"])].append(r["passes"])
        row = []
        for kind in KINDS + ["all"]:
            g = [v for (k, _), v in tries.items() if kind == "all" or k == kind]
            if g:
                first, retry = sum(v[0] for v in g), sum(any(v[:2]) for v in g)
                row.append(f"{kind} {pct(first, len(g))} / {pct(retry, len(g))}")
                summary["models"][m].setdefault(kind, {})["planYield"] = {"plans": len(g), "firstTry": first, "withRetry": retry}
        print(f"  {m}: " + " · ".join(row))
    print()

    print("Top rejects per model (first reason only)")
    for m in models:
        rej = collections.Counter(r["firstReject"] for r in records if r["model"] == m and r["firstReject"])
        print(f"  {m}: " + (", ".join(f"{k} {v}" for k, v in rej.most_common(6)) or "none"))
    print("\nArticles changed in planned phrases (case moved or possessive), per model")
    for m in models:
        ch = collections.Counter(c for r in records if r["model"] == m for c in r["changes"])
        moved = sum(v for k, v in ch.items() if "missing" not in k and "possessive" not in k)
        poss = sum(v for k, v in ch.items() if "possessive" in k)
        missing = sum(v for k, v in ch.items() if "missing" in k)
        summary["models"].setdefault(m, {})["articleChanges"] = {"caseMoved": moved, "possessive": poss,
                                                                "missing": missing, "examples": dict(ch.most_common(8))}
        print(f"  {m}: case moved {moved}, possessive {poss}, phrase dropped {missing}"
              + (f"  e.g. {', '.join(k for k, _ in ch.most_common(3))}" if ch else ""))

    # Hand-read sheets: 20 passing items per model, and 10 rejects to see what the gate caught.
    rng = random.Random(20261006)
    for m in models:
        if m == "template":
            continue
        mine = [r for r in records if r["model"] == m]
        passing = [r for r in mine if r["passes"]]
        failing = [r for r in mine if not r["passes"]]
        pick = rng.sample(passing, min(20, len(passing)))
        pick.sort(key=lambda r: (KINDS.index(r["kind"]), r["unit"], r["seed"]))
        lines = [f"# Hand read · {m}", "",
                 f"{len(passing)} of {len(mine)} items passed the gate. Below: {len(pick)} of the passing ones,",
                 "picked at random. Mark each: does the sentence read right, and are the planned roles what the",
                 "sentence really says? Anything a learner would be taught wrong is a ✗.", "",
                 "| # | exercise | sentence | planned roles | reads right? | note |", "|---|---|---|---|---|---|"]
        for i, r in enumerate(pick, 1):
            lines.append(f"| {i} | {r['kind']} {r['unit']} | {r['sentence']} | {roles_line(r, plans[r['id']])} |  |  |")
        lines += ["", "## Ten rejects, for what the gate caught", "",
                  "| exercise | output | first reject | detail |", "|---|---|---|---|"]
        for r in rng.sample(failing, min(10, len(failing))):
            out = (r.get("sentence") or r["raw"]).replace("\n", " ").replace("|", "\\|")[:140]
            detail = "; ".join(r["changes"] or r["facts"] or r["errors"])
            lines.append(f"| {r['kind']} {r['unit']} | {out} | {r['firstReject']} | {detail} |")
        (folder / f"hand_read_{m}.md").write_text("\n".join(lines) + "\n")
        summary["models"][m]["handRead"] = {"sheet": f"hand_read_{m}.md", "items": len(pick), "readWrong": None}

    (folder / "verdicts.jsonl").write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in records) + "\n")
    text = json.dumps(summary, ensure_ascii=False, indent=2)
    (folder / "summary.json").write_text(text + "\n")
    (ROOT / "results" / f"kasus-concept-probe_{summary['date']}.json").write_text(text + "\n")
    print(f"\nwrote hand_read_*.md, verdicts.jsonl, summary.json in {folder}")


if __name__ == "__main__":
    main()
