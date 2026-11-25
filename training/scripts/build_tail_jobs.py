#!/usr/bin/env python3
"""Correction jobs for the thin tail, the same number per phenomenon, for a teacher bake-off.

Builds jobs with `build_gen_jobs.py`'s own prompt (CORRECTION_SYS / CORRECTION_USER / PHEN_DESC /
HINT_RULE), so a bake-off row is comparable with the v4 corpus. Unlike `--limit N` on a full
manifest, which takes the head and can skip a phenomenon entirely (bakeoff/README.md §4), every
phenomenon here gets exactly `--per` jobs.

The defaults are the four phenomena DATA_GAP_PLAN.md assigns to Sonnet for judgment
(imperativ, k2, negation) plus aux, the one short of `ok` rows. See KASUS_STORY_DATA.md §4b.

Usage:
    python scripts/build_tail_jobs.py --per 12 --out data/bakeoff/kasus-2026-10/tail_jobs.jsonl
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_gen_jobs as g  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--phenomena", default="imperativ,k2,negation,aux")
    ap.add_argument("--per", type=int, default=12, help="jobs per phenomenon")
    ap.add_argument("--seed", type=int, default=20261004)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    per_job = g.PER_JOB["correction"]
    jobs = []
    for phen in args.phenomena.split(","):
        if phen not in g.PHEN_DESC:
            sys.exit(f"unknown phenomenon {phen}")
        for i in range(args.per):
            level = g.pick(rng, g.LEVELS, g.LEVEL_W)
            formality = g.pick(rng, g.FORMALITY, g.FORMALITY_W)
            n_fix = 0 if phen == "verdict" else round(per_job * 0.65)
            n_ok = per_job - n_fix
            n_hint = round(n_fix * 0.4)
            jobs.append({
                "id": f"tail-{phen}-{i:03d}",
                "slice": "correction", "phenomenon": phen, "level": level, "formality": formality,
                "system": g.CORRECTION_SYS,
                "user": g.CORRECTION_USER.format(
                    n=per_job, phen=phen, phen_desc=g.PHEN_DESC[phen], target="",
                    level=level, formality=formality, n_fix=n_fix, n_ok=n_ok,
                    hint_rule=g.HINT_RULE.format(n_hint=n_hint) if n_hint else 'Setze "hint":null.',
                    meta="{}"),
                "expect": per_job, "meta": {},
                "maxTokens": 1400,
            })

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("".join(json.dumps(j, ensure_ascii=False) + "\n" for j in jobs))
    print(f"wrote {len(jobs)} jobs ({args.per} × {args.phenomena}) to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
