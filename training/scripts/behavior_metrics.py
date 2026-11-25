#!/usr/bin/env python3
"""Combined behavioral metrics across both eval suites, using the shared scorer.

  false-correction rate = correct sentences (expect_ok) the model wrongly "fixed"  / 32
  miss rate             = real errors missed or wrongly fixed                       / 69

These are the two trust-critical metrics on MODEL_SCOREBOARD.md. Works on either a raw
responses file (from eval_apple_intelligence.swift: {"results":[{"id","response"}]}) or a
scored results file (from run_baseline_eval.py, same shape) — both carry id + response.

Usage (from training/):
  .venv/bin/python scripts/behavior_metrics.py \
      results/apple_ai_core.responses.json results/apple_ai_ext.responses.json
  # sanity check vs. the known stock-E4B numbers (34% / 17%):
  .venv/bin/python scripts/behavior_metrics.py \
      results/baseline_gemma-4-e4b-it-4bit.json results/baseline-extra_gemma-4-e4b-it-4bit.json
"""
import json
import sys
from pathlib import Path

from run_baseline_eval import apply_app_guard, score, strip_channels  # reuse the exact scorer

ROOT = Path(__file__).resolve().parent.parent
EVAL_FILES = [ROOT / "data/eval/grammar_eval_v0.json", ROOT / "data/eval/grammar_eval_v1_extra.json"]


def main() -> None:
    argv = sys.argv[1:]
    app_guard = "--app-guard" in argv
    argv = [a for a in argv if a != "--app-guard"]

    # --eval-file <path> (repeatable) overrides the default v0+v1 pair, so the same two metrics
    # can be computed on the v2 holdout. Denominators change with the suite — always report them.
    eval_files, resp_files, i = [], [], 0
    while i < len(argv):
        if argv[i] == "--eval-file":
            eval_files.append(argv[i + 1]); i += 2
        else:
            resp_files.append(argv[i]); i += 1
    if not resp_files:
        sys.exit("usage: behavior_metrics.py [--app-guard] [--eval-file <suite.json>] "
                 "<responses-or-results.json> [more ...]")

    items = {}
    for f in (eval_files or EVAL_FILES):
        for it in json.loads(Path(f).read_text())["items"]:
            items[it["id"]] = it

    resp = {}
    for f in resp_files:
        for r in json.loads(Path(f).read_text())["results"]:
            resp[r["id"]] = r["response"]

    corr = [it for it in items.values() if it["mode"] == "correction"]
    ok_items = [it for it in corr if it.get("expect_ok")]
    err_items = [it for it in corr if not it.get("expect_ok")]

    def passed(it):
        raw = strip_channels(resp.get(it["id"], ""))
        return score(it, apply_app_guard(raw, it) if app_guard else raw)["pass"]

    false_corr = [it["id"] for it in ok_items if not passed(it)]   # returned FIX instead of OK
    missed = [it["id"] for it in err_items if not passed(it)]      # missed OR wrongly fixed

    print(f"false-correction rate: {len(false_corr)}/{len(ok_items)} = "
          f"{len(false_corr) / len(ok_items) * 100:.0f}%")
    print(f"miss rate:             {len(missed)}/{len(err_items)} = "
          f"{len(missed) / len(err_items) * 100:.0f}%")
    print(f"\nfalse-corrected (should be OK): {false_corr}")
    print(f"missed / mis-fixed errors:      {missed}")


if __name__ == "__main__":
    main()
