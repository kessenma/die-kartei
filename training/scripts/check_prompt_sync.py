#!/usr/bin/env python3
"""Fail if the Python prompt builders have drifted from the Swift app.

`app_prompts.py` extracts the *variable* strings (scenario roles, focus hints, level/formality/
strictness instructions) straight from the Swift enums, so those cannot drift. What CAN drift is
the hand-ported **assembly**: the fixed connective sentences and the order they're joined in.

This checks that every fixed sentence the Python builders emit still exists verbatim in
ConversationPrompts.swift. It is the guard that would have caught the 2026-07-28 finding — that
the training data had been built for months against the 2026-07-09 prompt shape, missing the
HINT: line, the focus-area steering, and the 23 typed scenario roles.

Run it before any generation run, and in CI if this ever gets one:
    .venv/bin/python scripts/check_prompt_sync.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_prompts as ap

SWIFT = ap.PROMPTS_SWIFT.read_text(encoding="utf-8")


def swift_has(fragment: str) -> bool:
    """Is this sentence present in the Swift source? Swift wraps long literals across lines with
    a trailing backslash, so compare with whitespace collapsed."""
    norm = " ".join(SWIFT.split())
    return " ".join(fragment.split()) in norm


# Fixed connective sentences the Python builders emit. Each must exist in the Swift.
FIXED = [
    # conversation_system
    "You are Lena, a warm and patient German conversation partner helping someone practice spoken German.",
    "Speak ONLY in German.",
    "Keep your replies short — usually one to three sentences — and end most replies with a question so the conversation keeps flowing.",
    "The learner is speaking out loud, so their words may contain small transcription glitches and they may mix in an English word when they don't know the German one. Understand them charitably and simply continue the conversation in natural German.",
    "Do NOT correct the learner, and do NOT add translations, explanations, or any English in your replies. Just have a natural conversation.",
    "Gently steer the conversation so the learner naturally practices these structures:",
    "The learner is studying these German words; weave a few of them naturally into your questions and replies, and encourage the learner to use them:",
    "You are role-playing the following situation with a German learner:",
    # correction_system
    "You are a meticulous German teacher reviewing one line a student said during a spoken conversation.",
    "Pay particular attention to:",
    "They may have mixed in an English word they didn't know — in your correction, replace it with the correct German word.",
    "If the sentence is already correct and natural German, reply with exactly:",
    "Otherwise reply in EXACTLY this format and nothing else:",
    "FIX: <the full corrected sentence in natural German>",
    "WHY: <one short explanation in English, at most 18 words>",
    # correction_user
    "The conversation partner just said:",
    "The student replied:",
    "Evaluate only the student's reply.",
    "Evaluate the student's sentence.",
]


def main() -> int:
    failures = []

    for frag in FIXED:
        if not swift_has(frag):
            failures.append(f"MISSING FROM SWIFT: {frag[:90]!r}")

    # The nudgeMe HINT line, checked by its distinctive core rather than the whole literal
    # (it contains nested quotes that Swift escapes).
    for frag in ["HINT: <a SHORT German question that points the student at their single main mistake",
                 "Name the grammar category, but do NOT reveal the corrected word or sentence."]:
        if not swift_has(frag):
            failures.append(f"MISSING FROM SWIFT (nudgeMe): {frag[:90]!r}")

    # Assembly check: for representative configs, the rendered prompt must contain exactly the
    # parts that config should produce — no missing paragraph, no extra one. Combined with the
    # FIXED-exists-in-Swift loop above, that pins both halves: every sentence we emit is a real
    # app sentence, and every config emits the right set of them.
    #
    # (Deliberately NOT doing residue-subtraction on prose — an earlier version stripped commas
    #  to handle joined lists and corrupted every comparison. Counting paragraphs is coarser and
    #  actually correct.)
    CONV_ALWAYS = 5   # role + core rules(4)

    def check_conv(label: str, cfg: dict, extra: int) -> None:
        p = ap.conversation_system(cfg)
        paras = p.split("\n\n")
        want = CONV_ALWAYS + extra
        if len(paras) != want:
            failures.append(f"{label}: {len(paras)} paragraphs, expected {want}")
        role = paras[0]
        if cfg.get("scenario"):
            if role != ap.SCENARIOS[cfg["scenario"]]:
                failures.append(f"{label}: role paragraph is not the scenario's roleInstruction")
        elif not role.startswith("You are Lena"):
            failures.append(f"{label}: expected the Lena persona, got {role[:60]!r}")
        for f in cfg.get("focus_areas") or []:
            if ap.FOCUS_HINTS[f] not in p:
                failures.append(f"{label}: steering hint for {f} missing")
            if ap.FOCUS_LABELS[f] not in p:
                failures.append(f"{label}: german label for {f} missing")
        if ap.LEVELS[ap.LEVEL_KEY[cfg["level"]]] not in p:
            failures.append(f"{label}: level instruction missing")
        if ap.FORMALITY[ap.FORMALITY_KEY[cfg["formality"]]] not in p:
            failures.append(f"{label}: formality instruction missing")

    check_conv("conv/lena", {"level": "B1", "formality": "du"}, 0)
    check_conv("conv/scenario", {"level": "B1", "formality": "du", "scenario": "bakery"}, 0)
    check_conv("conv/focus1", {"level": "A2", "formality": "Sie", "focus_areas": ["dativ"]}, 1)
    check_conv("conv/focus2", {"level": "B2", "formality": "du",
                               "focus_areas": ["perfekt", "akkusativ"]}, 1)
    check_conv("conv/decks", {"level": "A2", "formality": "Sie",
                              "deck_words": ["der Tisch", "kochen"]}, 1)
    check_conv("conv/scenario+focus+decks",
               {"level": "B1", "formality": "du", "scenario": "doctor",
                "focus_areas": ["dativ"], "deck_words": ["das Rezept"]}, 2)

    # correction: the HINT line must appear iff nudgeMe, and focus text iff focus_areas
    for style, want_hint in [("tellMe", False), ("nudgeMe", True)]:
        for focus in [[], ["dativ"]]:
            s = ap.correction_system({"level": "B1", "formality": "du", "strictness": "balanced",
                                      "focus_areas": focus, "feedback_style": style})
            has_hint = "HINT:" in s
            if has_hint != want_hint:
                failures.append(f"correction/{style}: HINT present={has_hint}, expected {want_hint}")
            has_focus = "Pay particular attention to:" in s
            if has_focus != bool(focus):
                failures.append(f"correction/{style}: focus text present={has_focus}, "
                                f"expected {bool(focus)}")
            if "FIX: <the full corrected sentence in natural German>" not in s:
                failures.append(f"correction/{style}: FIX line missing")

    u_solo = ap.correction_user(None, "Ich warte für den Bus.")
    u_pair = ap.correction_user("Wohin gehst du?", "Ich warte für den Bus.")
    if "Evaluate the student's sentence." not in u_solo:
        failures.append("correction_user(solo): wrong tail")
    if "Evaluate only the student's reply." not in u_pair:
        failures.append("correction_user(pair): wrong tail")

    # Every extracted string must exist verbatim in the Swift it claims to come from. This closes
    # the case where the extractor mangles a literal, or someone "helpfully" hardcodes a value
    # back into app_prompts.py — which is exactly how the generic role-play string outlived the
    # typed scenarios last time.
    config_src = " ".join(ap.CONFIG_SWIFT.read_text(encoding="utf-8").split())
    focus_src = " ".join(ap.FOCUS_SWIFT.read_text(encoding="utf-8").split())

    def in_src(src: str, s: str) -> bool:
        # Swift escapes embedded quotes; compare against both forms.
        n = " ".join(s.split())
        return n in src or n.replace('"', '\\"') in src

    for name, role in ap.SCENARIOS.items():
        if not in_src(config_src, role):
            failures.append(f"scenario {name!r} roleInstruction not found verbatim in "
                            f"{ap.CONFIG_SWIFT.name} — extracted value is not the app's")
    for name, hint in ap.FOCUS_HINTS.items():
        if not in_src(focus_src, hint):
            failures.append(f"focus {name!r} steeringHint not found verbatim in "
                            f"{ap.FOCUS_SWIFT.name}")
    for label, table, src, fname in [("level", ap.LEVELS, config_src, ap.CONFIG_SWIFT.name),
                                     ("formality", ap.FORMALITY, config_src, ap.CONFIG_SWIFT.name),
                                     ("strictness", ap.STRICTNESS, config_src, ap.CONFIG_SWIFT.name)]:
        for name, text in table.items():
            if not in_src(src, text):
                failures.append(f"{label} {name!r} instruction not found verbatim in {fname}")

    # Counts — a sudden drop means the extractor silently matched fewer cases.
    if len(ap.SCENARIOS) < 20:
        failures.append(f"only {len(ap.SCENARIOS)} scenarios extracted (expected 20+)")
    if len(ap.FOCUS_AREAS) != 12:
        failures.append(f"{len(ap.FOCUS_AREAS)} focus areas extracted (expected 12)")
    if len(ap.LEVELS) != 5 or len(ap.FORMALITY) != 2 or len(ap.STRICTNESS) != 3:
        failures.append(f"enum sizes off: levels={len(ap.LEVELS)} "
                        f"formality={len(ap.FORMALITY)} strictness={len(ap.STRICTNESS)}")

    if failures:
        print("PROMPT SYNC FAILED\n")
        for f in failures:
            print("  ✗", f)
        print(f"\n{len(failures)} problem(s). The app's prompts changed — update "
              f"scripts/app_prompts.py before generating any training data.")
        return 1

    print("prompt sync OK")
    print(f"  scenarios      {len(ap.SCENARIOS)}")
    print(f"  focus areas    {len(ap.FOCUS_AREAS)}")
    print(f"  levels/form/strict  {len(ap.LEVELS)}/{len(ap.FORMALITY)}/{len(ap.STRICTNESS)}")
    print(f"  fixed sentences verified against {ap.PROMPTS_SWIFT.name}: {len(FIXED) + 2}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
