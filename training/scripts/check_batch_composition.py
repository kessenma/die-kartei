#!/usr/bin/env python3
"""Composition gate for a generated batch — the check that pass rate cannot make.

WHY THIS EXISTS: on 2026-07-28 a one-paragraph prompt tweak made the teacher emit **only**
`verdict:"ok"` correction rows. Every one was valid German, so the validator passed them and the
pass rate went UP (82.9% -> 84.8%) while the correction slice became useless — a model trained on
it learns to rubber-stamp everything, which is the exact failure mode the scoreboard records for
Llama-3.2-1B ("answered OK to all 69 errors"). The full 19,210-job run produced 16,128 correction
rows, 0 of them corrections.

Pass rate answers "is each row well-formed?". This answers "is the SET the right shape?".
Run it on every smoke batch, before the full run, and on the full run's output.

    .venv/bin/python scripts/check_batch_composition.py data/gen_v2/candidates.jsonl
    .venv/bin/python scripts/check_batch_composition.py smoke.jsonl --min-rows 50
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_prompts as ap

# Each check: (label, predicate over the stats dict, human explanation of why it matters)
CORRECTION_FIX_MIN = 0.35      # target mix is ~65% fix / 35% ok; alarm well before it inverts
CORRECTION_FIX_MAX = 0.85
HINT_MIN_SHARE_OF_FIX = 0.10   # HINT_RULE asks for ~40% of fix rows; 10% is a generous floor
PHENOMENON_MIN_SHARE = 0.02    # no target phenomenon should nearly vanish


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("infile")
    p.add_argument("--min-rows", type=int, default=0,
                   help="fail if the batch has fewer rows than this")
    args = p.parse_args()

    rows = [json.loads(l) for l in open(args.infile, encoding="utf-8") if l.strip()]
    tasks = collections.Counter(r.get("task") for r in rows)
    corr = [r for r in rows if r.get("task") == "correction"]
    verdicts = collections.Counter(r.get("verdict") for r in corr)
    n_fix = verdicts.get("fix", 0)
    n_ok = verdicts.get("ok", 0)
    hints = sum(1 for r in corr
                if isinstance(r.get("hint"), str) and r["hint"].strip())
    phen = collections.Counter(r.get("phenomenon") for r in corr)
    convs = [r for r in rows if r.get("task") == "conversation"]
    scenarios = {r.get("role_scenario") for r in rows if r.get("role_scenario")}
    focus = collections.Counter(f for r in rows for f in (r.get("focus_areas") or []))
    bad_focus = {f: c for f, c in focus.items() if f not in ap.FOCUS_AREAS}

    print(f"rows: {len(rows):,}")
    print(f"tasks: {dict(tasks)}")
    print(f"correction verdicts: fix={n_fix:,} ok={n_ok:,}"
          + (f"  ({n_fix / len(corr):.1%} fix)" if corr else ""))
    print(f"correction hints: {hints:,}"
          + (f"  ({hints / n_fix:.1%} of fix rows)" if n_fix else ""))
    print(f"phenomena: {dict(phen)}")
    print(f"conversations: {len(convs):,} | scenarios covered: {len(scenarios)}/{len(ap.SCENARIOS)}")
    print(f"focus areas used: {len(set(focus) & set(ap.FOCUS_AREAS))}/{len(ap.FOCUS_AREAS)}")
    if bad_focus:
        print(f"  ⚠️  {len(bad_focus)} invented focus values (dropped at pack time): "
              f"{list(bad_focus)[:6]}")

    fail = []
    if args.min_rows and len(rows) < args.min_rows:
        fail.append(f"only {len(rows)} rows, expected >= {args.min_rows}")

    if corr:
        share = n_fix / len(corr)
        if share < CORRECTION_FIX_MIN:
            fail.append(
                f"only {share:.1%} of correction rows are verdict=fix (floor {CORRECTION_FIX_MIN:.0%}). "
                f"A corpus of pure 'ok' rows teaches the model to rubber-stamp every sentence — "
                f"it is valid data that produces a useless tutor.")
        if share > CORRECTION_FIX_MAX:
            fail.append(
                f"{share:.1%} of correction rows are verdict=fix (ceiling {CORRECTION_FIX_MAX:.0%}). "
                f"Too few 'ok' rows and the model over-corrects — the trust-critical failure.")
        if n_fix and hints / n_fix < HINT_MIN_SHARE_OF_FIX:
            fail.append(
                f"only {hints}/{n_fix} fix rows carry a HINT ({hints / n_fix:.1%}, floor "
                f"{HINT_MIN_SHARE_OF_FIX:.0%}). FeedbackStyle.nudgeMe ships with no training data "
                f"unless this slice exists.")
        for want in ("vmp", "sep", "refl", "dawo"):
            if phen.get(want, 0) / len(corr) < PHENOMENON_MIN_SHARE:
                fail.append(f"core phenomenon '{want}' is {phen.get(want, 0)}/{len(corr)} — "
                            f"below {PHENOMENON_MIN_SHARE:.0%}")

    # Scenario diversity only means something once the batch is big enough to express it — a
    # 40-job smoke has ~12 conversation jobs and cannot cover 23 scenarios. Scale the expectation.
    if len(convs) >= 200:
        want_scen = min(len(ap.SCENARIOS), 15)
        if len(scenarios) < want_scen:
            fail.append(f"only {len(scenarios)} distinct scenarios across {len(convs):,} "
                        f"conversations; expected >= {want_scen} of {len(ap.SCENARIOS)}")

    print()
    if fail:
        print("COMPOSITION CHECK FAILED\n")
        for f in fail:
            print("  ✗", f)
        print(f"\n{len(fail)} problem(s). Fix the generation prompts before training on this.")
        return 1
    print("composition OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
