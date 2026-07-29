#!/usr/bin/env python3
"""Negative tests for scripts/check_prompt_sync.py — does the guard actually catch drift?

A drift guard that cannot fail is worse than none: it certifies staleness. Each case below
simulates a real way the Python port could fall behind the Swift app, including the exact drift
found on 2026-07-28 (the nudgeMe HINT: line and the focus-area steering going missing while the
training data was generated anyway).

    .venv/bin/python scripts/test_prompt_sync_guard.py     # exits non-zero if any guard misses
"""
import sys, importlib
sys.path.insert(0, "scripts")
import app_prompts as ap

fails = 0
def expect_fail(name, patch, restore):
    global fails
    patch()
    import check_prompt_sync
    importlib.reload(check_prompt_sync)
    # re-apply patches the reload may have reset
    patch()
    rc = check_prompt_sync.main()
    restore()
    ok = rc != 0
    print(f"  {'PASS' if ok else 'FAIL'} — guard {'caught' if ok else 'MISSED'}: {name}")
    if not ok: fails += 1

orig_cs = ap.correction_system
expect_fail("nudgeMe HINT line silently dropped",
            lambda: setattr(ap, "correction_system",
                            lambda cfg: orig_cs({k:v for k,v in cfg.items() if k!="feedback_style"})),
            lambda: setattr(ap, "correction_system", orig_cs))

orig_conv = ap.conversation_system
expect_fail("focus-area steering paragraph dropped",
            lambda: setattr(ap, "conversation_system",
                            lambda cfg: orig_conv({k:v for k,v in cfg.items() if k!="focus_areas"})),
            lambda: setattr(ap, "conversation_system", orig_conv))

orig_scen = dict(ap.SCENARIOS)
expect_fail("typed scenario role replaced with the old generic string",
            lambda: ap.SCENARIOS.__setitem__("bakery",
                "You are role-playing the following situation with a German learner: bakery."),
            lambda: (ap.SCENARIOS.clear(), ap.SCENARIOS.update(orig_scen)))

orig_lv = dict(ap.LEVELS)
expect_fail("a level instruction reworded away from the app's",
            lambda: ap.LEVELS.__setitem__("b1", "The learner is intermediate. Keep it simple."),
            lambda: (ap.LEVELS.clear(), ap.LEVELS.update(orig_lv)))

orig_fh = dict(ap.FOCUS_HINTS)
expect_fail("a focus steering hint reworded away from the app's",
            lambda: ap.FOCUS_HINTS.__setitem__("dativ", "ask about the dative case"),
            lambda: (ap.FOCUS_HINTS.clear(), ap.FOCUS_HINTS.update(orig_fh)))

print(f"\n{'ALL GUARD TESTS PASSED' if fails==0 else f'{fails} GUARD TEST(S) FAILED'}")
raise SystemExit(1 if fails else 0)
import sys, importlib
sys.path.insert(0, "scripts")
import app_prompts as ap

fails = 0
def expect_fail(name, patch, restore):
    global fails
    patch()
    import check_prompt_sync
    importlib.reload(check_prompt_sync)
    # re-apply patches the reload may have reset
    patch()
    rc = check_prompt_sync.main()
    restore()
    ok = rc != 0
    print(f"  {'PASS' if ok else 'FAIL'} — guard {'caught' if ok else 'MISSED'}: {name}")
    if not ok: fails += 1

orig_cs = ap.correction_system
expect_fail("nudgeMe HINT line silently dropped",
            lambda: setattr(ap, "correction_system",
                            lambda cfg: orig_cs({k:v for k,v in cfg.items() if k!="feedback_style"})),
            lambda: setattr(ap, "correction_system", orig_cs))

orig_conv = ap.conversation_system
expect_fail("focus-area steering paragraph dropped",
            lambda: setattr(ap, "conversation_system",
                            lambda cfg: orig_conv({k:v for k,v in cfg.items() if k!="focus_areas"})),
            lambda: setattr(ap, "conversation_system", orig_conv))

orig_scen = dict(ap.SCENARIOS)
expect_fail("typed scenario role replaced with the old generic string",
            lambda: ap.SCENARIOS.__setitem__("bakery",
                "You are role-playing the following situation with a German learner: bakery."),
            lambda: (ap.SCENARIOS.clear(), ap.SCENARIOS.update(orig_scen)))

orig_lv = dict(ap.LEVELS)
expect_fail("a level instruction reworded away from the app's",
            lambda: ap.LEVELS.__setitem__("b1", "The learner is intermediate. Keep it simple."),
            lambda: (ap.LEVELS.clear(), ap.LEVELS.update(orig_lv)))

orig_fh = dict(ap.FOCUS_HINTS)
expect_fail("a focus steering hint reworded away from the app's",
            lambda: ap.FOCUS_HINTS.__setitem__("dativ", "ask about the dative case"),
            lambda: (ap.FOCUS_HINTS.clear(), ap.FOCUS_HINTS.update(orig_fh)))

print(f"\n{'ALL GUARD TESTS PASSED' if fails==0 else f'{fails} GUARD TEST(S) FAILED'}")
raise SystemExit(1 if fails else 0)
