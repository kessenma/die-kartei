#!/usr/bin/env python3
"""Gate a generated correction batch on the SHAPE of its errors, not just their validity.

Why this exists
---------------
Three times now a gate that answers "is this data valid?" has sailed past data that was the wrong
shape for the job:

  §1.5b  a repair regex destroyed every `verdict:"fix"` row. The pass rate went UP, because an
         `ok` row full of correct German is perfectly well-formed data.
  §2.6   the correction slice shipped at 44% fix against v1's 69%, and `sep` at 20%. The model
         learned to answer OK.
  here   `sep` rows were 26% plain word-order drill mislabelled as separable verbs, and 88% of
         `refl` rows taught "add sich" when half the eval tests "mich vs mir".

Every one of those batches passed LanguageTool, spaCy and the composition gate. Validity and
usefulness are different questions. This script asks the second one.

Measured reference points (see TEACHER_GENERATION_FIX.md):

    teacher              refl case-change    sep pure-reorder    resulting core score
    Claude Sonnet (v1)              65%                  0%                   54/60
    gemma-4-26B-A4B (v2/v3)         12%                 26%              42–46/60

Usage:
    python scripts/check_hard_case_share.py <batch.jsonl> [<batch2.jsonl> ...]
    python scripts/check_hard_case_share.py --strict ...     # exit 1 if a gate fails
"""
import argparse
import json
import re
import sys
from collections import Counter

REFL_PRONOUNS = {"mich", "mir", "dich", "dir", "sich", "uns", "euch"}

# Gates. Set from what the teacher that actually produced a 54/60 model achieved.
REFL_CASE_CHANGE_MIN = 0.60
SEP_PURE_REORDER_MAX = 0.05


def toks(s: str) -> list:
    return re.findall(r"\w+", (s or "").lower())


def is_noop(student: str, fix: str) -> bool:
    """The "correction" is identical to the input. A degenerate row, not a teaching example.

    Kept separate from `is_pure_reorder` because the two are different failures with different
    remedies, and conflating them hides which teacher you are dealing with:

      no-op       loud and trivially filterable. gemma-4-31B emits ~18% of these and every
                  surviving row is correctly shaped.
      reorder     silent. The row is fluent, plausible, correctly labelled, and teaches the
                  wrong skill. gemma-4-26B-A4B emitted 26% of these and they cost two
                  training runs before anyone noticed.

    A teacher with a high no-op rate is usable at a yield cost. A teacher with a high reorder
    rate is not usable at any yield.
    """
    return (student or "").strip() == (fix or "").strip()


def is_pure_reorder(student: str, fix: str) -> bool:
    """A fix that only MOVES existing words teaches word order, not verb morphology.

    `Du machst das Licht aus im Wohnzimmer.` -> `Du machst das Licht im Wohnzimmer aus.`
    is a legitimate German correction and completely useless as a *separable verb* example.
    Excludes no-ops, which are counted separately.
    """
    if is_noop(student, fix):
        return False
    return sorted(toks(student)) == sorted(toks(fix))


def refl_kind(student: str, fix: str) -> str:
    """Does the fix CHANGE a reflexive pronoun, or merely INSERT one?

    Insert  (`interessiere` -> `interessiere mich`) is the trivial case.
    Change  (`wasche mich die Hände` -> `wasche mir die Hände`) is the one learners actually
    get wrong and the one the core suite spends half its reflexive items on.
    """
    s = set(toks(student)) & REFL_PRONOUNS
    f = set(toks(fix)) & REFL_PRONOUNS
    if s and f and s != f:
        return "case_change"
    if not s and f:
        return "insert_only"
    if s and f and s == f:
        return "unchanged"
    return "other"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--strict", action="store_true",
                    help="exit non-zero if any gate fails (use in CI / before a training run)")
    args = ap.parse_args()

    rows = []
    for path in args.files:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if d.get("task") == "correction":
                    rows.append(d)

    if not rows:
        print("no correction rows found")
        return 1

    verdict = Counter(d.get("verdict") for d in rows)
    phen = Counter(d.get("phenomenon") for d in rows)
    n_fix = verdict.get("fix", 0)
    print(f"correction rows: {len(rows)}   fix: {n_fix} ({100*n_fix/len(rows):.0f}%)   "
          f"ok: {verdict.get('ok', 0)}")
    print(f"phenomena: {dict(phen.most_common())}\n")

    failures = []

    refl = [d for d in rows if d.get("phenomenon") == "refl" and d.get("verdict") == "fix"]
    if refl:
        noop = [d for d in refl if is_noop(d.get("student", ""), d.get("fix", ""))]
        live = [d for d in refl if not is_noop(d.get("student", ""), d.get("fix", ""))]
        kinds = Counter(refl_kind(d.get("student", ""), d.get("fix", "")) for d in live)
        share = kinds["case_change"] / max(len(live), 1)
        ok = share >= REFL_CASE_CHANGE_MIN
        failures.append(ok)
        print(f"refl  n={len(refl)}   live {len(live)}   no-op {len(noop)} "
              f"({100*len(noop)/len(refl):.0f}%, filterable)")
        print(f"   case-change  {kinds['case_change']:4d} ({100*share:.0f}%)   "
              f"gate >= {100*REFL_CASE_CHANGE_MIN:.0f}%   {'PASS' if ok else 'FAIL'}")
        print(f"   insert-only  {kinds['insert_only']:4d} ({100*kinds['insert_only']/max(len(live),1):.0f}%)")
        for k in ("unchanged", "other"):
            if kinds[k]:
                print(f"   {k:12s} {kinds[k]:4d}  <- malformed, the fix changes no reflexive")
        print()

    sep = [d for d in rows if d.get("phenomenon") == "sep" and d.get("verdict") == "fix"]
    if sep:
        noop = [d for d in sep if is_noop(d.get("student", ""), d.get("fix", ""))]
        live = [d for d in sep if not is_noop(d.get("student", ""), d.get("fix", ""))]
        bad = [d for d in live if is_pure_reorder(d.get("student", ""), d.get("fix", ""))]
        share = len(bad) / max(len(live), 1)
        ok = share <= SEP_PURE_REORDER_MAX
        failures.append(ok)
        print(f"sep   n={len(sep)}   live {len(live)}   no-op {len(noop)} "
              f"({100*len(noop)/len(sep):.0f}%, filterable)")
        print(f"   pure reorder {len(bad):4d} ({100*share:.0f}%)   "
              f"gate <= {100*SEP_PURE_REORDER_MAX:.0f}%   {'PASS' if ok else 'FAIL'}")
        print(f"   morphological {len(live)-len(bad):3d} ({100*(1-share):.0f}%)")
        for d in bad[:3]:
            print(f"      e.g. {d.get('student','')!r} -> {d.get('fix','')!r}")
        print()

    passed = all(failures) if failures else False
    print("RESULT:", "PASS — batch teaches the skill the eval measures"
          if passed else "FAIL — batch is valid German that does not teach the target skill")
    return 0 if passed or not args.strict else 1


if __name__ == "__main__":
    sys.exit(main())
