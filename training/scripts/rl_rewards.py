#!/usr/bin/env python3
"""Composite GRPO reward for the correction task — REINFORCEMENT_LEARNING.md Part A §3.

One function, `tutor_reward`, in the TRL `reward_funcs` signature. It sees each completion exactly
the way the app does (channels stripped, echo-FIX discarded by the same guard the app applies) and
scores it against the row's gold `student` / `verdict` / `fix`, which TRL forwards from the dataset
columns as keyword arguments.

    format gate    exactly "OK", or "FIX: …" + "WHY: …" (+ "HINT: …" only when asked) and nothing
                   else, WHY 2–18 words                         → fail: -1.0, nothing else counts
    gold = ok      model OK  → +1.0      model FIX (real change) → -1.0   [false correction]
    gold = fix     model OK  → -1.0 [miss]                model FIX → +0.3 + 0.7 × fix_score
    why            +0.1 when the WHY line is well-formed (fix replies only)

`fix_score ∈ [0, 1]` is derived from the gold fix automatically (no hand labels):
    * normalised candidate == normalised gold → 1.0
    * else a position-aware word diff (difflib) of student→gold and student→candidate:
      coverage = how much of the gold edit the candidate reproduces, excess = candidate edits
      outside the gold edit; fix_score = coverage × max(0, 1 − 0.25 × excess)
    * contractions are expanded first (am = an dem, ins = in das, …) so "am Kurs" and "an dem Kurs"
      are the same edit
This is `require_any` / `forbid_any` generated from the diff, plus a penalty for the evasive rewrite
(`Ich wasche mich die Hände` → "Ich wasche meine Hände") the dataset was built to remove.

Known gap, accepted for v1: a *valid alternative* fix scores low (≈0.3–0.5 total, i.e. above a miss,
below the gold). Audit after the run — §3 of the plan says how.

Symmetric penalties (miss = FC = −1.0) are the v1 calibration; `MISS_PENALTY` / `FC_PENALTY` are
the knobs the plan says to turn if FC rises past 6%.

Run the tests:  .venv/bin/python scripts/test_rl_rewards.py
"""

from __future__ import annotations

import difflib
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from run_baseline_eval import _guard_normalize, apply_app_guard, strip_channels  # the app's own guard

# --------------------------------------------------------------------------- knobs
FORMAT_PENALTY = -1.0
MISS_PENALTY = -1.0
FC_PENALTY = -1.0
OK_REWARD = 1.0
CAUGHT_BONUS = 0.3          # said FIX on a real error, regardless of fix quality
FIX_WEIGHT = 0.7            # × fix_score
WHY_BONUS = 0.1
EXCESS_PENALTY = 0.25       # per edited word outside the gold edit
WHY_MIN_WORDS, WHY_MAX_WORDS = 2, 18

MAX_REWARD = CAUGHT_BONUS + FIX_WEIGHT + WHY_BONUS   # 1.1 — a gold fix with a good WHY

# --------------------------------------------------------------------------- parsing

_CONTRACTIONS = {
    "am": "an dem", "ans": "an das", "im": "in dem", "ins": "in das", "vom": "von dem",
    "zum": "zu dem", "zur": "zu der", "beim": "bei dem", "aufs": "auf das", "fürs": "für das",
    "durchs": "durch das", "übers": "über das", "ums": "um das", "hinterm": "hinter dem",
    "unterm": "unter dem", "vorm": "vor dem",
}


def tokens(s: str) -> list[str]:
    """Lower-cased word tokens with contractions expanded, so `am`/`an dem` diff as equal."""
    out = []
    for w in re.findall(r"[a-zA-ZäöüÄÖÜß]+", s.lower()):
        out.extend(_CONTRACTIONS.get(w, w).split())
    return out


def parse_reply(text: str, hint_expected: bool = False) -> dict:
    """Classify a raw completion the way the app's parser would, but strictly.

    Returns {"kind": "ok" | "fix" | "malformed", "fix": str|None, "why": str|None, "hint": str|None,
             "reason": str}.  Strict on purpose: anything the app would have to *ignore* (a preamble,
    a trailing paragraph, an unrequested HINT) is malformed, so the policy cannot drift there.
    """
    t = strip_channels(text or "").strip()
    if not t:
        return {"kind": "malformed", "fix": None, "why": None, "hint": None, "reason": "empty"}
    if t.upper().rstrip(".!") == "OK":
        return {"kind": "ok", "fix": None, "why": None, "hint": None, "reason": ""}
    lines = [ln.strip() for ln in t.splitlines() if ln.strip()]
    want = 3 if hint_expected else 2
    if len(lines) != want:
        return {"kind": "malformed", "fix": None, "why": None, "hint": None,
                "reason": f"{len(lines)} lines, expected {want}"}
    if not lines[0].startswith("FIX:") or not lines[1].startswith("WHY:"):
        return {"kind": "malformed", "fix": None, "why": None, "hint": None, "reason": "line labels"}
    hint = None
    if hint_expected:
        if not lines[2].startswith("HINT:"):
            return {"kind": "malformed", "fix": None, "why": None, "hint": None, "reason": "no HINT line"}
        hint = lines[2][5:].strip()
    fix, why = lines[0][4:].strip(), lines[1][4:].strip()
    if not fix:
        return {"kind": "malformed", "fix": None, "why": why, "hint": hint, "reason": "empty FIX"}
    return {"kind": "fix", "fix": fix, "why": why, "hint": hint, "reason": ""}


def why_ok(why: str | None, fix: str | None) -> bool:
    if not why:
        return False
    n = len(why.split())
    if not (WHY_MIN_WORDS <= n <= WHY_MAX_WORDS):
        return False
    return _guard_normalize(why) != _guard_normalize(fix or "")


# --------------------------------------------------------------------------- fix quality

def edit_sets(src: list[str], dst: list[str]) -> tuple[Counter, Counter]:
    """(added, removed) word multisets of the position-aware edit src→dst."""
    added, removed = Counter(), Counter()
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(a=src, b=dst, autojunk=False).get_opcodes():
        if op in ("delete", "replace"):
            removed.update(src[i1:i2])
        if op in ("insert", "replace"):
            added.update(dst[j1:j2])
    return added, removed


def fix_score(student: str, gold: str, candidate: str) -> float:
    """How well `candidate` reproduces the gold edit of `student`. 1.0 = the gold fix."""
    if _guard_normalize(candidate) == _guard_normalize(gold):
        return 1.0
    s, g, c = tokens(student), tokens(gold), tokens(candidate)
    if c == s:
        return 0.0                        # an echo; upstream this is already an OK verdict
    g_add, g_rem = edit_sets(s, g)
    c_add, c_rem = edit_sets(s, c)
    sides = []
    if g_add:
        sides.append(sum((g_add & c_add).values()) / sum(g_add.values()))
    if g_rem:
        sides.append(sum((g_rem & c_rem).values()) / sum(g_rem.values()))
    if not sides:                         # gold == student at the token level (should not happen)
        return 0.0
    coverage = sum(sides) / len(sides)
    excess = sum((c_add - g_add).values()) + sum((c_rem - g_rem).values())
    return coverage * max(0.0, 1.0 - EXCESS_PENALTY * excess)


# --------------------------------------------------------------------------- the reward

def explain(completion: str, student: str, verdict: str, fix: str | None,
            hint_expected: bool = False) -> dict:
    """Score one completion and return every component (for tests, logging, and audits)."""
    parsed = parse_reply(completion, hint_expected=hint_expected)
    out = {"kind": parsed["kind"], "reason": parsed["reason"], "guarded_ok": None,
           "fix_score": None, "why_ok": None, "reward": 0.0}
    if parsed["kind"] == "malformed":
        out["reward"] = FORMAT_PENALTY
        return out
    # the app's guard: a FIX that echoes the student's sentence is shown as nothing → OK
    guarded = apply_app_guard(strip_channels(completion), {"input": student})
    guarded_ok = guarded.strip().upper() == "OK"
    out["guarded_ok"] = guarded_ok
    gold_ok = (verdict or "").lower() == "ok"
    if gold_ok:
        out["reward"] = OK_REWARD if guarded_ok else FC_PENALTY
        return out
    if guarded_ok:
        out["reward"] = MISS_PENALTY
        return out
    fs = fix_score(student, fix or "", parsed["fix"] or "")
    w = why_ok(parsed["why"], parsed["fix"])
    out.update(fix_score=fs, why_ok=w,
               reward=CAUGHT_BONUS + FIX_WEIGHT * fs + (WHY_BONUS if w else 0.0))
    return out


def _text(completion) -> str:
    """TRL passes a string (standard format) or a list of messages (conversational)."""
    if isinstance(completion, str):
        return completion
    if isinstance(completion, list) and completion and isinstance(completion[0], dict):
        return completion[-1].get("content", "") or ""
    return str(completion)


def tutor_reward(completions, student, verdict, fix, hint_expected=None, log_metric=None, **kwargs):
    """TRL reward function. `student` / `verdict` / `fix` (and optional `hint_expected`) are the
    dataset columns, repeated per generation by the trainer. Returns one float per completion."""
    n = len(completions)
    hints = hint_expected if hint_expected is not None else [False] * n
    rewards, comps = [], []
    for i in range(n):
        e = explain(_text(completions[i]), student[i], verdict[i], fix[i], hint_expected=bool(hints[i]))
        rewards.append(float(e["reward"]))
        comps.append(e)
    if log_metric is not None:  # component logging, when the trainer offers it
        try:
            log_metric("reward/format_ok", sum(c["kind"] != "malformed" for c in comps) / n)
            fixes = [c for c in comps if c["fix_score"] is not None]
            if fixes:
                log_metric("reward/fix_score", sum(c["fix_score"] for c in fixes) / len(fixes))
            gold_ok = [c for c, v in zip(comps, verdict) if (v or "").lower() == "ok" and c["guarded_ok"] is not None]
            if gold_ok:
                log_metric("reward/false_correction_rate", sum(not c["guarded_ok"] for c in gold_ok) / len(gold_ok))
            gold_fix = [c for c, v in zip(comps, verdict) if (v or "").lower() != "ok" and c["guarded_ok"] is not None]
            if gold_fix:
                log_metric("reward/miss_rate", sum(bool(c["guarded_ok"]) for c in gold_fix) / len(gold_fix))
        except Exception:
            pass
    return rewards


if __name__ == "__main__":
    demo = [
        ("Ich nehme bei dem Kurs teil.", "fix", "Ich nehme an dem Kurs teil.", "FIX: Ich nehme am Kurs teil.\nWHY: 'teilnehmen' takes 'an'."),
        ("Ich nehme bei dem Kurs teil.", "fix", "Ich nehme an dem Kurs teil.", "OK"),
        ("Ich nehme bei dem Kurs teil.", "fix", "Ich nehme an dem Kurs teil.", "FIX: Ich nehme bei dem Kurs teil.\nWHY: fine"),
        ("Sie besteht auf ihrem Recht.", "ok", None, "FIX: Sie besteht auf ihr Recht.\nWHY: accusative"),
        ("Sie besteht auf ihrem Recht.", "ok", None, "OK"),
        ("Ich wasche mich die Hände.", "fix", "Ich wasche mir die Hände.", "FIX: Ich wasche meine Hände.\nWHY: possessive"),
    ]
    for s, v, f, c in demo:
        print(f"{explain(c, s, v, f)}   <- {c!r}")
