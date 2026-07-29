#!/usr/bin/env python3
"""The app's live prompt strings, extracted from the Swift source at import time.

WHY THIS EXISTS: `pack_dataset.py` used to hand-copy the prompt strings out of
ConversationPrompts.swift. On 2026-07-28 an audit found they had silently drifted to the
2026-07-09 shape — the training data was being built against a prompt the app no longer sends:

  * 5 conversation modes now (freestyle/decks/scenario/interview/paper); the copy knew 2 shapes
  * 24 typed scenarios each with their own `roleInstruction`; the copy used one generic sentence
  * 12 GrammarFocus areas inject steering into BOTH prompts; the copy had none
  * FeedbackStyle.nudgeMe adds a third `HINT:` line; the copy had none — so a SHIPPED feature had
    zero training examples teaching its output format

Copies drift. So this module parses the literals straight out of the Swift enums instead. If the
Swift changes shape the extractor raises at import — loudly wrong beats silently stale.

The *assembly* logic (order of parts, conditionals) is still a hand-port of
`ConversationPrompts.systemPrompt` / `.correctionSystemPrompt`; `scripts/check_prompt_sync.py`
guards that half.

Usage:
    from app_prompts import (conversation_system, correction_system, correction_user,
                             SCENARIOS, FOCUS_AREAS, LEVELS, FORMALITY, STRICTNESS)
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT.parent / "german-ai-flashcards"

CONFIG_SWIFT = APP / "Models" / "ConversationConfig.swift"
FOCUS_SWIFT = APP / "Models" / "GrammarFocus.swift"
PROMPTS_SWIFT = APP / "Services" / "ConversationPrompts.swift"


# --------------------------------------------------------------------------- extraction

def _enum_body(source: str, enum_name: str) -> str:
    """The text of `enum <name> { ... }`, ending at the first closing brace in column 0."""
    m = re.search(rf"^enum {re.escape(enum_name)}\b.*?\{{$", source, re.M)
    if not m:
        raise RuntimeError(f"app_prompts: enum {enum_name} not found — Swift source changed shape")
    tail = source[m.end():]
    end = re.search(r"^\}", tail, re.M)
    return tail[: end.start()] if end else tail


def _swift_string(raw: str) -> str:
    """Unescape a Swift string literal body."""
    return (raw.replace('\\"', '"').replace("\\\\", "\\")
               .replace("\\n", "\n").replace("\\t", "\t"))


def _switch_map(body: str, prop: str) -> dict:
    """Map `case .x: "str"` pairs inside `var <prop>: ... { switch self { ... } }`.

    Handles both layouts the codebase uses (literal on the same line as the case, and on the
    following line) plus `nil` payloads. Stops at the end of the property's switch block.
    """
    m = re.search(rf"var {re.escape(prop)}\s*:\s*[^\{{]*\{{", body)
    if not m:
        raise RuntimeError(f"app_prompts: property `{prop}` not found — Swift source changed shape")
    # take a generous window, then cut at the next `var ` / `func ` / `static ` declaration
    window = body[m.end():]
    stop = re.search(r"^\s{0,4}(var|func|static|private)\s", window, re.M)
    if stop:
        window = window[: stop.start()]

    out = {}
    for cm in re.finditer(r"case\s+\.(\w+)\s*:\s*(.*?)(?=\n\s*case\s+\.|\Z)", window, re.S):
        name, payload = cm.group(1), cm.group(2).strip()
        if payload.startswith("nil"):
            out[name] = None
            continue
        sm = re.match(r'"((?:[^"\\]|\\.)*)"', payload)
        if sm:
            out[name] = _swift_string(sm.group(1))
    if not out:
        raise RuntimeError(f"app_prompts: property `{prop}` yielded no cases — parser out of date")
    return out


def _literal(source: str, anchor: str) -> str:
    """A standalone `let x = "…"` string literal, matched by its declaration text."""
    m = re.search(rf'{re.escape(anchor)}\s*=\s*"((?:[^"\\]|\\.)*)"', source)
    if not m:
        raise RuntimeError(f"app_prompts: literal `{anchor}` not found — Swift source changed shape")
    return _swift_string(m.group(1))


_config_src = CONFIG_SWIFT.read_text(encoding="utf-8")
_focus_src = FOCUS_SWIFT.read_text(encoding="utf-8")
_prompts_src = PROMPTS_SWIFT.read_text(encoding="utf-8")

LEVELS = _switch_map(_enum_body(_config_src, "CEFRLevel"), "promptInstruction")
FORMALITY = _switch_map(_enum_body(_config_src, "Formality"), "promptInstruction")
STRICTNESS = _switch_map(_enum_body(_config_src, "CorrectionStrictness"), "promptInstruction")

_scenario_body = _enum_body(_config_src, "ConversationScenario")
SCENARIOS = {k: v for k, v in _switch_map(_scenario_body, "roleInstruction").items() if v}

_focus_body = _enum_body(_focus_src, "GrammarFocus")
FOCUS_HINTS = _switch_map(_focus_body, "steeringHint")
FOCUS_LABELS = _switch_map(_focus_body, "germanLabel")
FOCUS_EN = _switch_map(_focus_body, "englishLabel")
FOCUS_AREAS = sorted(FOCUS_HINTS)

OPENER_SEED = _literal(_prompts_src, "static let openerSeed")

# Level keys are lowercased Swift cases (a1, a2, …); callers speak CEFR.
LEVEL_KEY = {"A1": "a1", "A2": "a2", "B1": "b1", "B2": "b2", "C1": "c1"}
FORMALITY_KEY = {"du": "du", "Sie": "sie"}


# --------------------------------------------------------------------------- builders

def conversation_system(cfg: dict) -> str:
    """Mirror of ConversationPrompts.systemPrompt for the modes we generate data for.

    cfg: {level, formality, scenario?, deck_words?, focus_areas?, custom_scenario?}
    `.paper` / `.interview` are deliberately not modelled — their prompt is dominated by a pasted
    document, so they are out of scope for synthetic training data (see DATA_V2_DISTILL_PLAN.md).
    """
    parts = []
    scenario = cfg.get("scenario")
    custom = cfg.get("custom_scenario")
    if custom:
        parts.append(f"You are role-playing the following situation with a German learner: "
                     f"{custom}. Stay fully in character and set the scene.")
    elif scenario:
        if scenario not in SCENARIOS:
            raise KeyError(f"unknown scenario {scenario!r}; known: {sorted(SCENARIOS)}")
        parts.append(SCENARIOS[scenario])
    else:
        parts.append("You are Lena, a warm and patient German conversation partner helping "
                     "someone practice spoken German.")

    parts.append("Speak ONLY in German. " + LEVELS[LEVEL_KEY[cfg["level"]]] + " "
                 + FORMALITY[FORMALITY_KEY[cfg["formality"]]])
    parts.append("Keep your replies short — usually one to three sentences — and end most replies "
                 "with a question so the conversation keeps flowing.")
    parts.append("The learner is speaking out loud, so their words may contain small transcription "
                 "glitches and they may mix in an English word when they don't know the German one. "
                 "Understand them charitably and simply continue the conversation in natural German.")
    parts.append("Do NOT correct the learner, and do NOT add translations, explanations, or any "
                 "English in your replies. Just have a natural conversation.")

    focus = cfg.get("focus_areas") or []
    if focus:
        names = ", ".join(FOCUS_LABELS[f] for f in focus)
        hints = "\n".join(f"- {FOCUS_HINTS[f]}" for f in focus)
        example = "" if len(focus) == 1 else "for example "
        parts.append(f"Gently steer the conversation so the learner naturally practices these "
                     f"structures: {names}. To do that, {example}ask questions like:\n{hints}")

    deck = cfg.get("deck_words") or []
    if deck:
        parts.append("The learner is studying these German words; weave a few of them naturally "
                     "into your questions and replies, and encourage the learner to use them: "
                     + ", ".join(deck[:24]) + ".")
    return "\n\n".join(parts)


def correction_system(cfg: dict) -> str:
    """Mirror of ConversationPrompts.correctionSystemPrompt.

    cfg: {level, formality, strictness, focus_areas?, feedback_style?}
    feedback_style "nudgeMe" adds the HINT: line the app parses but v1 never trained.
    """
    s = ("You are a meticulous German teacher reviewing one line a student said during a spoken "
         "conversation. ")
    s += f"The student's level is {cfg['level']}. "
    s += STRICTNESS[cfg.get("strictness", "balanced")] + " "
    focus = cfg.get("focus_areas") or []
    if focus:
        names = ", ".join(f"{FOCUS_LABELS[f]} ({FOCUS_EN[f]})" for f in focus)
        s += f"Pay particular attention to: {names}. "
    s += f"The student uses the {cfg['formality']} form. "
    s += ("They may have mixed in an English word they didn't know — in your correction, replace "
          "it with the correct German word.\n\n")
    s += "If the sentence is already correct and natural German, reply with exactly:\nOK\n\n"
    s += "Otherwise reply in EXACTLY this format and nothing else:\n"
    s += "FIX: <the full corrected sentence in natural German>\n"
    s += "WHY: <one short explanation in English, at most 18 words>"
    if cfg.get("feedback_style") == "nudgeMe":
        s += ("\nHINT: <a SHORT German question that points the student at their single main "
              "mistake so they can fix it themselves — e.g. \"Welcher Fall kommt nach 'mit'?\" or "
              "\"Wo steht das Verb in einem Nebensatz?\". Name the grammar category, but do NOT "
              "reveal the corrected word or sentence.>")
    return s


def correction_user(partner: str | None, student: str) -> str:
    """Mirror of ConversationPrompts.correctionUserPrompt."""
    if partner:
        return (f'The conversation partner just said: "{partner}"\n'
                f'The student replied: "{student}"\n\nEvaluate only the student\'s reply.')
    return f'The student said: "{student}"\n\nEvaluate the student\'s sentence.'


if __name__ == "__main__":
    print(f"scenarios      : {len(SCENARIOS)}")
    print(f"focus areas    : {len(FOCUS_AREAS)} -> {FOCUS_AREAS}")
    print(f"levels         : {sorted(LEVELS)}")
    print(f"formality      : {sorted(FORMALITY)}")
    print(f"strictness     : {sorted(STRICTNESS)}")
    print(f"opener seed    : {OPENER_SEED!r}")
    print("\n--- correction_system(nudgeMe + focus) ---")
    print(correction_system({"level": "B1", "formality": "du", "strictness": "balanced",
                             "focus_areas": ["dativ"], "feedback_style": "nudgeMe"}))
    print("\n--- conversation_system(scenario=bakery, focus=perfekt) ---")
    print(conversation_system({"level": "A2", "formality": "Sie", "scenario": "bakery",
                               "focus_areas": ["perfekt"]}))
