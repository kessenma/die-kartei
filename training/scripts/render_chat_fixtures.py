#!/usr/bin/env python3
"""Render the tutors' real chat templates into fixtures for the Android prompt-format test.

The Android app builds prompts in Swift (`ChatPromptFormat`, DieKarteiCore/Sources/DieKarteiCore/
Tutor/) because llama.cpp has no Jinja engine. The evals ran through each model's own
chat_template.jinja. This renders those templates for a set of histories; the core test
`ChatPromptFormatTests` must reproduce every one byte for byte, so the phone sends exactly the
text that was scored.

Rerun after a new model or template (needs jinja2; the llama.cpp convert venv has it):
    ~/ws/llama.cpp/.venv/bin/python training/scripts/render_chat_fixtures.py
"""

import json
import sys
from datetime import datetime
from pathlib import Path

import jinja2

ROOT = Path(__file__).resolve().parents[2]
MODELS = Path.home() / "ws" / "models"
OUT = ROOT / "DieKarteiCore" / "Tests" / "DieKarteiCoreTests" / "chat_template_fixtures.json"

# Template source per format family: each release's chat_template.jinja (dequantized repo copies).
TEMPLATES = {
    "gemma4": ["e2b-v1-dequant", "e4b-v4-fp16"],
    "granite": ["granite33-v4-dequant", "granite41-v4-dequant"],
}

CASES = {
    "chat": [
        {"role": "system", "content": "Du bist ein freundlicher Tutor."},
        {"role": "user", "content": "Hallo!"},
        {"role": "assistant", "content": "Wie geht's?"},
        {"role": "user", "content": "Gut, danke."},
    ],
    "check": [
        {"role": "system", "content": "Correct the sentence.\nFIX: <sentence>\nWHY: <reason>"},
        {"role": "user", "content": "STUDENT: Ich warte für den Bus."},
    ],
    "padded": [
        {"role": "system", "content": "  System mit Leerzeichen \n"},
        {"role": "user", "content": "\nZeile eins\nZeile zwei  "},
    ],
    "no_system": [
        {"role": "user", "content": "Mach bitte weiter."},
    ],
}


def render(template: str, messages):
    env = jinja2.Environment(trim_blocks=True, lstrip_blocks=True, extensions=["jinja2.ext.loopcontrols"])

    def raise_exception(message):
        raise jinja2.TemplateError(message)

    env.globals["raise_exception"] = raise_exception
    env.globals["strftime_now"] = lambda fmt: datetime(2026, 11, 26).strftime(fmt)
    out = env.from_string(template).render(
        messages=messages, add_generation_prompt=True, bos_token="<bos>", eos_token="<eos>")
    # llama.cpp adds BOS itself when tokenizing, so the app's prompt starts after it.
    return out[len("<bos>"):] if out.startswith("<bos>") else out


def main() -> int:
    fixtures = []
    for family, repos in TEMPLATES.items():
        rendered = {}
        for repo in repos:
            path = MODELS / repo / "chat_template.jinja"
            template = path.read_text(encoding="utf-8")
            for name, messages in CASES.items():
                if family == "granite" and name == "no_system":
                    # Granite injects a dated default system prompt (3.3 and 4.1 differ); the
                    # app always sends its own.
                    continue
                text = render(template, messages)
                if name in rendered and rendered[name] != text:
                    print(f"{family}: {repo} renders {name!r} differently from its sibling", file=sys.stderr)
                    return 1
                rendered[name] = text
        for name, messages in CASES.items():
            if name not in rendered:
                continue
            fixtures.append({"family": family, "case": name, "messages": messages, "prompt": rendered[name]})
    OUT.write_text(json.dumps(fixtures, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {len(fixtures)} fixtures to {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
