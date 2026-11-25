#!/usr/bin/env python3
"""Unit tests for scripts/rl_rewards.py against the eval suites (never the RL pool).

Fixtures: every error item in grammar_eval_v3.json carries `gold_fix`; v0/v1/v2 supply the app's
own scorer criteria. The invariants the reward must hold before a single GPU-minute is rented:

  1. the gold fix scores MAX on every v3 error item
  2. an echo (FIX: <input>) on an error item is a MISS  (the app guard turns it into OK)
  3. a bare OK on an error item is a miss; on an OK item it is +1
  4. a real FIX on an OK item is a false correction (−1)
  5. malformed output (preamble, OK+FIX, three lines, missing WHY) is −1 regardless of gold
  6. the evasive rewrite scores well below the gold and above a miss
  7. a valid alternative fix (documented gap) lands between a miss and the gold, never as a miss
  8. contraction-equivalent fixes (am / an dem) score as the gold
  9. list-in / list-out with both TRL completion shapes; length preserved

Run:  .venv/bin/python scripts/test_rl_rewards.py      (pytest also picks it up)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from rl_rewards import (FC_PENALTY, FORMAT_PENALTY, MAX_REWARD, MISS_PENALTY, OK_REWARD,
                        explain, fix_score, tutor_reward)

V3 = json.loads((ROOT / "data/eval/grammar_eval_v3.json").read_text())["items"]
ERR = [it for it in V3 if not it["expect_ok"]]
OKS = [it for it in V3 if it["expect_ok"]]
WHY = "WHY: The verb takes a different preposition here."


def r(completion, item):
    gold = None if item["expect_ok"] else item["gold_fix"]
    return explain(completion, item["input"], "ok" if item["expect_ok"] else "fix", gold)["reward"]


def test_gold_fix_scores_max():
    bad = [it["id"] for it in ERR if r(f"FIX: {it['gold_fix']}\n{WHY}", it) < MAX_REWARD - 1e-9]
    assert not bad, f"gold fix not max on {len(bad)} items: {bad[:8]}"


def test_echo_is_a_miss():
    bad = [it["id"] for it in ERR if r(f"FIX: {it['input']}\n{WHY}", it) != MISS_PENALTY]
    assert not bad, f"echo not scored as miss on {bad[:8]}"
    # echo with cosmetic differences (quotes, trailing period) is still an echo
    it = ERR[0]
    assert r(f'FIX: "{it["input"].rstrip(".")}"\n{WHY}', it) == MISS_PENALTY


def test_bare_ok():
    assert all(r("OK", it) == MISS_PENALTY for it in ERR)
    assert all(r("OK", it) == OK_REWARD for it in OKS)
    assert all(r("OK.", it) == OK_REWARD for it in OKS)


def test_false_correction():
    # a real change to a correct sentence is penalised, whatever the change
    bad = [it["id"] for it in OKS if r(f"FIX: {it['input']} wirklich\n{WHY}", it) != FC_PENALTY]
    assert not bad, bad[:8]


def test_malformed():
    it = ERR[0]
    cases = [
        f"Sure! Here is the correction:\nFIX: {it['gold_fix']}\n{WHY}",   # preamble
        f"OK\nFIX: {it['gold_fix']}\n{WHY}",                              # the Gemma-3-1B pattern
        f"FIX: {it['gold_fix']}",                                         # no WHY
        f"FIX: {it['gold_fix']}\n{WHY}\nHINT: Welcher Fall?",             # HINT not requested
        f"FIX: {it['gold_fix']}\n{WHY}\nHope this helps!",                # trailing chatter
        "",                                                               # empty
        f"FIX: {it['gold_fix']}\nWHY: " + " ".join(["word"] * 25),        # WHY too long -> not malformed, but no bonus
    ]
    for c in cases[:-1]:
        assert r(c, it) == FORMAT_PENALTY, f"not malformed: {c!r}"
        assert r(c, OKS[0]) == FORMAT_PENALTY, f"not malformed on OK item: {c!r}"
    long_why = explain(cases[-1], it["input"], "fix", it["gold_fix"])
    assert long_why["kind"] == "fix" and long_why["why_ok"] is False
    assert abs(long_why["reward"] - (MAX_REWARD - 0.1)) < 1e-9


def test_hint_expected():
    it = ERR[0]
    with_hint = f"FIX: {it['gold_fix']}\n{WHY}\nHINT: Welche Präposition passt hier?"
    e = explain(with_hint, it["input"], "fix", it["gold_fix"], hint_expected=True)
    assert e["kind"] == "fix" and e["reward"] >= MAX_REWARD - 1e-9
    e2 = explain(f"FIX: {it['gold_fix']}\n{WHY}", it["input"], "fix", it["gold_fix"], hint_expected=True)
    assert e2["kind"] == "malformed"


def test_evasive_rewrite():
    s, g = "Ich wasche mich die Hände.", "Ich wasche mir die Hände."
    evasive = fix_score(s, g, "Ich wasche meine Hände.")
    assert evasive < 0.5, evasive
    gold = explain(f"FIX: {g}\n{WHY}", s, "fix", g)["reward"]
    ev = explain("FIX: Ich wasche meine Hände.\n" + WHY, s, "fix", g)["reward"]
    assert MISS_PENALTY < ev < gold - 0.3, (ev, gold)
    # swapping the verb instead of adding the pronoun (the documented E2B failure)
    s2, g2 = "Ich kann das teure Auto nicht leisten.", "Ich kann mir das teure Auto nicht leisten."
    assert fix_score(s2, g2, "Ich kann das teure Auto nicht bezahlen.") < 0.3


def test_alternative_fix_is_not_a_miss():
    s, g = "Er leidet von Kopfschmerzen.", "Er leidet an Kopfschmerzen."
    alt = explain("FIX: Er leidet unter Kopfschmerzen.\n" + WHY, s, "fix", g)["reward"]
    gold = explain(f"FIX: {g}\n{WHY}", s, "fix", g)["reward"]
    assert MISS_PENALTY < 0 < alt < gold, (alt, gold)   # documented gap: above a miss, below gold


def test_contractions_equivalent():
    s, g = "Ich nehme bei dem Kurs teil.", "Ich nehme an dem Kurs teil."
    assert fix_score(s, g, "Ich nehme am Kurs teil.") == 1.0
    s, g = "Wir gehen heute Abend im Kino.", "Wir gehen heute Abend ins Kino."
    assert fix_score(s, g, "Wir gehen heute Abend in das Kino.") == 1.0


def test_word_order_fix():
    s, g = "Gestern ich habe meinen Onkel besucht.", "Gestern habe ich meinen Onkel besucht."
    assert fix_score(s, g, g) == 1.0
    assert fix_score(s, g, "Ich habe gestern meinen Onkel besucht.") < 1.0   # different (valid) reorder
    assert fix_score(s, g, s) == 0.0


def test_extra_edits_penalised():
    s, g = "Ich nehme bei dem Kurs teil.", "Ich nehme an dem Kurs teil."
    assert fix_score(s, g, "Ich nehme an dem Kurs teil, und du?") < 1.0
    assert fix_score(s, g, "Ich nehme an dem Kurs teil, und du?") > 0.3


def test_trl_shapes():
    it = ERR[0]
    comps_str = [f"FIX: {it['gold_fix']}\n{WHY}", "OK", "garbage"]
    comps_msg = [[{"role": "assistant", "content": c}] for c in comps_str]
    kw = dict(student=[it["input"]] * 3, verdict=["fix"] * 3, fix=[it["gold_fix"]] * 3)
    a, b = tutor_reward(comps_str, **kw), tutor_reward(comps_msg, **kw)
    assert a == b and len(a) == 3
    assert a[0] >= MAX_REWARD - 1e-9 and a[1] == MISS_PENALTY and a[2] == FORMAT_PENALTY
    logged = {}
    tutor_reward(comps_msg, log_metric=lambda k, v: logged.__setitem__(k, v), **kw)
    assert "reward/format_ok" in logged and abs(logged["reward/format_ok"] - 2 / 3) < 1e-9


def test_channels_stripped():
    it = ERR[0]
    c = f"<|channel>thinking about it<channel|>FIX: {it['gold_fix']}\n{WHY}"
    assert r(c, it) >= MAX_REWARD - 1e-9


if __name__ == "__main__":
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        try:
            fn()
            print(f"  ok    {name}")
        except AssertionError as e:
            failed += 1
            print(f"  FAIL  {name}: {e}")
    print(f"\n{len(tests) - failed}/{len(tests)} passed on {len(ERR)} error + {len(OKS)} ok v3 items")
    sys.exit(1 if failed else 0)
