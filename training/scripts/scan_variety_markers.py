#!/usr/bin/env python3
"""Scan packed corpora for regional-variety markers (data/eval/variety_markers_v0.json).

Part of the variety study written up in DIALECT_EVAL.md. Counts, per corpus and split,
how often each Austrian/Swiss/regional-German marker and its Bundesdeutsch counterpart
appear, attributed by role and by meta.source / meta.task.

Methodology notes (why this scan is legitimate where grepping for phenomena is not):
- training/CLAUDE.md warns against inferring *phenomenon coverage* by grepping the packed
  JSONL — coverage lives in meta labels. Variety, by contrast, IS a surface-lexical
  property of the text itself, so surface scanning is the correct instrument here.
- Assistant turns and user turns are counted separately and never merged: assistant text
  is the imitation target (what the student model learns to produce); user text is input
  exposure only. Headline numbers are assistant-side.
- Counts are also reported per 100k tokens (tokenizer shared with naturalness_metrics.py)
  because raw counts across corpora of very different sizes are meaningless.
- Cross-version (v1 Sonnet vs v4 gemma-31B) differences are teacher-confounded; the
  within-v4 per-source split is the primary evidence, the v1->v4 trend is descriptive
  only (see TEACHER_GENERATION_FIX.md lesson on same-source controls).

Usage (from training/):
  .venv/bin/python scripts/scan_variety_markers.py                      # v4, train+val
  .venv/bin/python scripts/scan_variety_markers.py --split val          # smoke (tracked file)
  .venv/bin/python scripts/scan_variety_markers.py --all-corpora --samples 5 --markdown
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from naturalness_metrics import tokens  # shared word tokenizer -> comparable per-100k rates

ROOT = Path(__file__).resolve().parent.parent
MARKERS_FILE = ROOT / "data" / "eval" / "variety_markers_v0.json"
RESULTS_DIR = ROOT / "results"

CORPORA = {
    "v1": "data/packed",
    "v2": "data/packed-v2",
    "v3": "data/packed-v2-balanced",
    "v4": "data/packed-v4",
}


def load_markers(path: Path) -> list[dict]:
    markers = json.loads(path.read_text())["markers"]
    for m in markers:
        m["_variant_re"] = re.compile(m["variant"]["pattern"], re.IGNORECASE)
        if m.get("counterpart"):
            m["_counterpart_re"] = re.compile(m["counterpart"]["pattern"], re.IGNORECASE)
    return markers


def iter_rows(jsonl: Path):
    with jsonl.open() as f:
        for idx, line in enumerate(f):
            line = line.strip()
            if line:
                yield idx, json.loads(line)


def scan_corpus(corpus_dir: Path, splits: list[str], markers: list[dict], n_samples: int) -> dict:
    """Return {split: {role: {token_total, marker_counts...}}} for one packed corpus."""
    out = {}
    for split in splits:
        jsonl = corpus_dir / f"{split}.jsonl"
        if not jsonl.exists():
            print(f"  (skip: {jsonl} missing)")
            continue
        stats = {
            role: {
                "rows": 0,
                "token_total": 0,
                "markers": defaultdict(lambda: {"variant": 0, "counterpart": 0, "compound": 0,
                                                "by_source": defaultdict(int), "by_task": defaultdict(int),
                                                "samples": []}),
            }
            for role in ("assistant", "user")
        }
        for idx, row in iter_rows(jsonl):
            meta = row.get("meta", {})
            source = meta.get("source", "?")
            task = meta.get("task", "?")
            for msg in row.get("messages", []):
                role = msg.get("role")
                if role not in ("assistant", "user"):
                    continue
                text = msg.get("content", "")
                st = stats[role]
                st["token_total"] += len(tokens(text))
                low = text.lower()
                for m in markers:
                    rec = None
                    hits = list(m["_variant_re"].finditer(text))
                    if hits:
                        rec = st["markers"][m["id"]]
                        rec["variant"] += len(hits)
                        rec["by_source"][source] += len(hits)
                        rec["by_task"][task] += len(hits)
                        if len(rec["samples"]) < n_samples:
                            h = hits[0]
                            lo, hi = max(0, h.start() - 80), min(len(text), h.end() + 80)
                            rec["samples"].append({"row": idx, "role": role, "source": source,
                                                   "task": task, "text": "…" + text[lo:hi] + "…"})
                    if "_counterpart_re" in m:
                        c = len(m["_counterpart_re"].findall(text))
                        if c:
                            (rec or st["markers"][m["id"]])["counterpart"] += c
                    sub = m.get("compound_substring")
                    if sub and sub in low:
                        total_sub = low.count(sub)
                        standalone = len(hits)
                        excluded = sum(low.count(x) for x in m.get("compound_exclude", []))
                        compound = max(0, total_sub - standalone - excluded)
                        if compound:
                            st["markers"][m["id"]]["compound"] += compound
            for role in ("assistant", "user"):
                stats[role]["rows"] += 1
        # freeze defaultdicts into plain dicts
        for role in ("assistant", "user"):
            stats[role]["markers"] = {
                k: {**v, "by_source": dict(v["by_source"]), "by_task": dict(v["by_task"])}
                for k, v in sorted(stats[role]["markers"].items())
            }
        out[split] = stats
    return out


def summarize(scan: dict, markers: list[dict]) -> dict:
    """Roll splits together and add rates + ratios per role."""
    by_id = {m["id"]: m for m in markers}
    roll = {}
    for role in ("assistant", "user"):
        token_total = sum(s[role]["token_total"] for s in scan.values())
        merged = defaultdict(lambda: {"variant": 0, "counterpart": 0, "compound": 0})
        for s in scan.values():
            for mid, rec in s[role]["markers"].items():
                for k in ("variant", "counterpart", "compound"):
                    merged[mid][k] += rec[k]
        rows = {}
        for mid, rec in sorted(merged.items()):
            m = by_id[mid]
            v, c = rec["variant"], rec["counterpart"]
            rows[mid] = {
                "variety": m["variety"], "tier": m["tier"], "category": m["category"],
                "variant_label": m["variant"]["label"], "variant": v,
                "counterpart": c if m.get("counterpart") else None,
                "compound": rec["compound"],
                "per_100k": round(v / token_total * 100_000, 3) if token_total else 0.0,
                "ratio": round(v / (v + c), 3) if m.get("counterpart") and (v + c) else None,
            }
        # aggregate variety totals over standard-tier markers only
        agg = defaultdict(int)
        for mid, r in rows.items():
            if r["tier"] == "standard":
                agg[r["variety"]] += r["variant"]
        roll[role] = {"token_total": token_total, "markers": rows,
                      "variety_totals_standard_tier": dict(sorted(agg.items()))}
    return roll


def markdown_table(name: str, roll: dict, markers: list[dict]) -> str:
    by_id = {m["id"]: m for m in markers}
    lines = [f"### {name} — assistant turns ({roll['assistant']['token_total']:,} tokens)", "",
             "| marker | variety | variant hits | /100k tok | counterpart | ratio | compounds |",
             "|---|---|---:|---:|---:|---:|---:|"]
    for mid, r in roll["assistant"]["markers"].items():
        if by_id[mid]["tier"] != "standard":
            continue
        cp = "—" if r["counterpart"] is None else r["counterpart"]
        ratio = "—" if r["ratio"] is None else f"{r['ratio']:.2f}"
        lines.append(f"| {r['variant_label']} ({mid}) | {r['variety']} | {r['variant']} "
                     f"| {r['per_100k']} | {cp} | {ratio} | {r['compound']} |")
    lines.append("")
    lines.append(f"user turns: {roll['user']['token_total']:,} tokens; standard-tier totals "
                 f"assistant={roll['assistant']['variety_totals_standard_tier']} "
                 f"user={roll['user']['variety_totals_standard_tier']}")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--markers", default=str(MARKERS_FILE))
    ap.add_argument("--corpus", action="append", default=None,
                    help="packed corpus dir (repeatable); default data/packed-v4")
    ap.add_argument("--all-corpora", action="store_true",
                    help=f"scan all of: {', '.join(CORPORA.values())}")
    ap.add_argument("--split", choices=["train", "val", "both"], default="both")
    ap.add_argument("--samples", type=int, default=3,
                    help="matched lines kept per marker per corpus/split/role (audit trail)")
    ap.add_argument("--out", default=str(RESULTS_DIR / "variety_corpus.json"))
    ap.add_argument("--markdown", action="store_true", help="print GitHub tables to stdout")
    args = ap.parse_args()

    markers = load_markers(Path(args.markers))
    splits = ["train", "val"] if args.split == "both" else [args.split]
    if args.all_corpora:
        corpora = {name: ROOT / rel for name, rel in CORPORA.items()}
    else:
        dirs = args.corpus or ["data/packed-v4"]
        corpora = {Path(d).name: (ROOT / d if not Path(d).is_absolute() else Path(d)) for d in dirs}

    report = {"markers_file": str(Path(args.markers).name), "splits": splits, "corpora": {}}
    for name, cdir in corpora.items():
        print(f"scanning {name} ({cdir.relative_to(ROOT)}) …")
        scan = scan_corpus(cdir, splits, markers, args.samples)
        roll = summarize(scan, markers)
        report["corpora"][name] = {"detail": scan, "summary": roll}
        for role in ("assistant", "user"):
            nz = {mid: r["variant"] for mid, r in roll[role]["markers"].items() if r["variant"]}
            print(f"  {role}: {roll[role]['token_total']:,} tokens; nonzero variants: {nz or '(none)'}")
        if args.markdown:
            print("\n" + markdown_table(name, roll, markers) + "\n")

    RESULTS_DIR.mkdir(exist_ok=True)
    out = Path(args.out)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\nfull report: {out}")


if __name__ == "__main__":
    main()
