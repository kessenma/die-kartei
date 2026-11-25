#!/usr/bin/env python3
"""Score variety-probe responses (from run_variety_probe.py) against the marker inventory.

Deterministic classification only — no LLM judge, matching the rest of the repo:
  elicit/request : which side of each target marker pair fired ->
                   variety-form / standard-DE-form / both / neither
  aux            : sein-perfect / haben-perfect / both / neither (variant vs counterpart
                   patterns of the aux markers), split by neutral vs AT framing
  correction     : apply run_baseline_eval.apply_app_guard (the app's real parser), then
                   OK / corrected-to-DE / corrected-other / malformed; broken controls are
                   additionally checked with require_all/require_any/forbid_any
  dialect        : comprehension items pass/fail via matches(); production items are NEVER
                   auto-judged — printed verbatim under MANUAL REVIEW with dialect
                   hint-marker annotations only

Usage (from training/):
  .venv/bin/python scripts/score_variety_probe.py results/variety-v4_<model>.responses.json
  .venv/bin/python scripts/score_variety_probe.py --compare \
      results/variety-base_<model>.responses.json results/variety-v4_<model>.responses.json --markdown
"""

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_baseline_eval as rbe  # apply_app_guard, matches — the app-faithful pieces

ROOT = Path(__file__).resolve().parent.parent
MARKERS_FILE = ROOT / "data" / "eval" / "variety_markers_v0.json"
PROBE_FILE = ROOT / "data" / "eval" / "variety_probe_v0.json"


def load_markers(path: Path) -> dict:
    markers = {}
    for m in json.loads(path.read_text())["markers"]:
        m["_variant_re"] = re.compile(m["variant"]["pattern"], re.IGNORECASE)
        if m.get("counterpart"):
            m["_counterpart_re"] = re.compile(m["counterpart"]["pattern"], re.IGNORECASE)
        markers[m["id"]] = m
    return markers


def variant_present(text: str, m: dict) -> str | None:
    """Standalone match, or a compound containing the marker (Kaisersemmel, Marillenknödel,
    Brettljause) — compounds are genuine variety evidence in a response, unlike in the
    corpus scan where they are tallied separately."""
    if m["_variant_re"].search(text):
        return "standalone"
    sub = m.get("compound_substring")
    if sub:
        low = text.lower()
        n = low.count(sub) - sum(low.count(x) for x in m.get("compound_exclude", []))
        if n > 0:
            return "compound"
    return None


def sides_fired(text: str, marker_ids: list[str], markers: dict) -> tuple[list, list]:
    variant_hits, counterpart_hits = [], []
    for mid in marker_ids:
        m = markers[mid]
        how = variant_present(text, m)
        if how:
            variant_hits.append(mid if how == "standalone" else f"{mid}(compound)")
        if "_counterpart_re" in m and m["_counterpart_re"].search(text):
            counterpart_hits.append(mid)
    return variant_hits, counterpart_hits


def classify_sides(variant_hits: list, counterpart_hits: list) -> str:
    if variant_hits and counterpart_hits:
        return "both"
    if variant_hits:
        return "variety-form"
    if counterpart_hits:
        return "standard-DE-form"
    return "neither"


def score_row(row: dict, item: dict, markers: dict) -> dict:
    text = row["response"]
    out = {"id": row["id"], "kind": row["kind"], "framing": row.get("framing"),
           "variety": row.get("variety"), "repeat": row.get("repeat", 0)}
    kind = row["kind"]

    if kind in ("elicit", "request"):
        v, c = sides_fired(text, item.get("target_markers", []), markers)
        out.update({"class": classify_sides(v, c), "variant_hits": v, "counterpart_hits": c})
        if item.get("require_any"):
            out["require_any_pass"] = any(rbe.matches(n, text) for n in item["require_any"])
        return out

    if kind == "aux":
        v, c = sides_fired(text, item["target_markers"], markers)
        out["class"] = {"variety-form": "sein-perfect", "standard-DE-form": "haben-perfect",
                        "both": "both", "neither": "neither"}[classify_sides(v, c)]
        return out

    if kind == "correction":
        guarded = rbe.apply_app_guard(text, item)
        out["control"] = bool(item.get("control"))
        if guarded == "OK":
            out["class"] = "OK"
            return out
        fix_match = re.search(r"FIX:\s*(.+)", guarded)
        if not fix_match:
            out["class"] = "malformed"
            return out
        fix = fix_match.group(1).strip()
        out["fix"] = fix
        # corrected-to-DE: a variety form present in the INPUT is gone from the fix,
        # or the DE counterpart appears in the fix where the input had the variety form
        to_de = False
        for mid in item.get("target_markers", []):
            m = markers[mid]
            if not variant_present(item["input"], m):
                continue
            gone = not variant_present(fix, m)
            swapped = "_counterpart_re" in m and m["_counterpart_re"].search(fix)
            if gone or swapped:
                to_de = True
        out["class"] = "corrected-to-DE" if to_de else "corrected-other"
        if item.get("require_all") or item.get("require_any"):
            out["fix_correct"] = (
                all(rbe.matches(n, fix) for n in item.get("require_all", []))
                and (not item.get("require_any") or any(rbe.matches(n, fix) for n in item["require_any"]))
                and not any(rbe.matches(n, fix) for n in item.get("forbid_any", []))
            )
        return out

    if kind == "dialect":
        if item.get("manual_review"):
            hints, _ = sides_fired(text, item.get("target_markers", []), markers)
            out.update({"class": "manual-review", "hint_markers": hints, "response": text})
        else:
            ok = (all(rbe.matches(n, text) for n in item.get("require_all", []))
                  and (not item.get("require_any") or any(rbe.matches(n, text) for n in item["require_any"])))
            out["class"] = "pass" if ok else "fail"
        return out

    raise ValueError(f"unknown kind {kind}")


def score_file(path: Path, markers: dict, items_by_id: dict) -> dict:
    payload = json.loads(path.read_text())
    scored = [score_row(r, items_by_id[r["id"]], markers) for r in payload["results"]
              if r["id"] in items_by_id]
    return {"file": str(path), "model": payload["model"], "temp": payload.get("temp", 0.0),
            "repeats": payload.get("repeats", 1), "scored": scored}


def aggregate(scored: list[dict]) -> dict:
    agg = {}
    for kind in ("elicit", "request", "aux", "correction", "dialect"):
        rows = [r for r in scored if r["kind"] == kind and r.get("repeat", 0) == 0]
        if not rows:
            continue
        if kind == "elicit":
            agg["elicit"] = {f: dict(Counter(r["class"] for r in rows if r["framing"] == f))
                             for f in ("neutral", "regional")}
        elif kind == "aux":
            agg["aux"] = {f: dict(Counter(r["class"] for r in rows if r["framing"] == f))
                          for f in ("neutral", "regional", "meta")}
        elif kind == "correction":
            agg["correction"] = {
                "variety_items": dict(Counter(r["class"] for r in rows if not r["control"])),
                "controls": dict(Counter(r["class"] for r in rows if r["control"])),
            }
        elif kind == "dialect":
            agg["dialect"] = dict(Counter(r["class"] for r in rows))
        else:
            agg[kind] = dict(Counter(r["class"] for r in rows))
    return agg


def print_report(result: dict, markers: dict, items_by_id: dict, markdown: bool) -> None:
    scored = result["scored"]
    print(f"\n=== {result['model']} (temp {result['temp']}) ===")
    for kind in ("elicit", "request", "aux", "correction", "dialect"):
        rows = [r for r in scored if r["kind"] == kind]
        if not rows:
            continue
        print(f"\n-- {kind} --")
        for r in rows:
            if r["class"] == "manual-review":
                continue
            extra = ""
            if r.get("variant_hits"):
                extra += f"  variety={','.join(r['variant_hits'])}"
            if r.get("counterpart_hits"):
                extra += f"  DE={','.join(r['counterpart_hits'])}"
            if "fix" in r:
                extra += f"  FIX: {r['fix'][:60]}"
            if "fix_correct" in r:
                extra += f"  fix_correct={r['fix_correct']}"
            rep = f" (rep {r['repeat']})" if r.get("repeat") else ""
            print(f"  {r['id']}{rep}: {r['class']}{extra}")

    manual = [r for r in scored if r["class"] == "manual-review" and r.get("repeat", 0) == 0]
    if manual:
        print("\n" + "=" * 24 + " MANUAL REVIEW " + "=" * 24)
        for r in manual:
            hints = f" [dialect hints fired: {', '.join(r['hint_markers'])}]" if r["hint_markers"] else " [no dialect hints fired]"
            print(f"\n### {r['id']}{hints}\n{r['response']}")
        print("=" * 63)

    agg = aggregate(scored)
    print("\n=== aggregates (repeat 0) ===")
    print(json.dumps(agg, ensure_ascii=False, indent=1))


def print_compare(a: dict, b: dict, markdown: bool) -> None:
    name_a = a["model"].rstrip("/").split("/")[-1]
    name_b = b["model"].rstrip("/").split("/")[-1]
    rows_a = {(r["id"], r.get("repeat", 0)): r for r in a["scored"]}
    print(f"\n=== compare: A={name_a}  B={name_b} ===\n")
    if markdown:
        print(f"| item | kind | {name_a} | {name_b} |")
        print("|---|---|---|---|")
    for r in b["scored"]:
        if r.get("repeat", 0) != 0:
            continue
        ra = rows_a.get((r["id"], 0))
        ca = ra["class"] if ra else "—"
        if markdown:
            print(f"| {r['id']} | {r['kind']} | {ca} | {r['class']} |")
        else:
            mark = "  " if ca == r["class"] else "≠ "
            print(f"{mark}{r['id']:26s} {r['kind']:10s} A={ca:18s} B={r['class']}")
    print("\naggregates A:", json.dumps(aggregate(a["scored"]), ensure_ascii=False))
    print("aggregates B:", json.dumps(aggregate(b["scored"]), ensure_ascii=False))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("responses", nargs="*", help="responses JSON from run_variety_probe.py")
    ap.add_argument("--compare", nargs=2, metavar=("A", "B"),
                    help="two responses files to diff (A = baseline, B = candidate)")
    ap.add_argument("--markers", default=str(MARKERS_FILE))
    ap.add_argument("--probe-file", default=str(PROBE_FILE))
    ap.add_argument("--markdown", action="store_true")
    ap.add_argument("--out", default=None, help="write scored JSON here (default: <input>.scored.json)")
    args = ap.parse_args()

    markers = load_markers(Path(args.markers))
    items_by_id = {i["id"]: i for i in json.loads(Path(args.probe_file).read_text())["items"]}

    if args.compare:
        a = score_file(Path(args.compare[0]), markers, items_by_id)
        b = score_file(Path(args.compare[1]), markers, items_by_id)
        print_compare(a, b, args.markdown)
        return

    if not args.responses:
        sys.exit("pass one or more responses files, or --compare A B")
    for path in args.responses:
        result = score_file(Path(path), markers, items_by_id)
        print_report(result, markers, items_by_id, args.markdown)
        out = Path(args.out) if args.out else Path(path).with_suffix("").with_suffix(".scored.json")
        out.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"\nscored: {out}")


if __name__ == "__main__":
    main()
