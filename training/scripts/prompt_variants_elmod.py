#!/usr/bin/env python3
"""Prompt-condition variants of the core suite — why ELMOD's first number was wrong.

The app's correction prompt is in English. ELMOD is German-first. Scored with the English
zero-shot prompt it emitted free-form prose and hit 12% core / 2% format adherence; the same
contract in German took format adherence to 100%, and three worked examples took core to 72%.
So the original "0 of 101" measured English instruction-following, not German grammar.

Three modes, identical items / scorer / --app-guard / exact-gelu patch:

  --mode german    the same contract, translated to German (zero-shot)
  --mode fewshot   the English contract with 3 worked examples prepended
  --mode english   the app's real prompt, unchanged (baseline; same as eval_elmod.py)

The SauerkrautLM control matters as much as the result: run `--mode german --model
models/sauerkraut-gemma2-2b-4bit` and it goes 53% -> 50%, i.e. no lift. The German-prompt effect
is specific to German-first pretraining, so the rest of the scoreboard's English numbers stand.

Usage (from training/):
  .venv/bin/python scripts/prompt_variants_elmod.py --mode german
  .venv/bin/python scripts/prompt_variants_elmod.py --mode fewshot
  .venv/bin/python scripts/prompt_variants_elmod.py --mode german \
      --model models/sauerkraut-gemma2-2b-4bit --tag control
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from transformers import AutoTokenizer  # noqa: E402

_orig = AutoTokenizer.register


def _safe(*a, **k):
    try:
        _orig(*a, **k)
    except Exception:
        pass


AutoTokenizer.register = _safe

import mlx.nn as nn  # noqa: E402
from mlx_lm.models import gpt_neox  # noqa: E402

# Faithful GPT-NeoX activation — see scripts/eval_elmod.py. No-op for non-NeoX models.
gpt_neox.MLP.__call__ = lambda self, x: self.dense_4h_to_h(nn.gelu(self.dense_h_to_4h(x)))

import run_baseline_eval as rbe  # noqa: E402
from mlx_lm import generate, load  # noqa: E402

# Faithful German translation of ConversationPrompts.correctionSystemPrompt.
GERMAN_CORRECTION_SYSTEM = (
    "Du bist ein sorgfältiger Deutschlehrer und prüfst einen Satz, den ein Lernender in einem "
    "Gespräch gesagt hat. Das Niveau des Lernenden ist B1. Korrigiere klare Grammatikfehler, "
    "ignoriere aber kleinere Stilfragen. Der Lernende benutzt die du-Form. "
    "Möglicherweise hat der Lernende ein englisches Wort eingestreut, das er nicht kannte — "
    "ersetze es in deiner Korrektur durch das richtige deutsche Wort.\n\n"
    "Wenn der Satz bereits korrektes und natürliches Deutsch ist, antworte mit genau:\nOK\n\n"
    "Andernfalls antworte GENAU in diesem Format und mit nichts anderem:\n"
    "FIX: <der vollständige korrigierte Satz in natürlichem Deutsch>\n"
    "WHY: <eine kurze Erklärung, höchstens 18 Wörter>"
)

# Three demos, none in v0/v1. Covers BOTH verdicts deliberately: a fix-only demo set teaches the
# model to always fix, which is exactly how packed-v2 regressed (MODEL_SCOREBOARD.md §2.6).
SHOTS = [
    ('The student said: "Ich habe gestern einen Film gesehen."\n\nEvaluate the student\'s sentence.',
     "OK"),
    ('The student said: "Ich interessiere für Musik."\n\nEvaluate the student\'s sentence.',
     "FIX: Ich interessiere mich für Musik.\nWHY: interessieren is reflexive and needs mich."),
    ('The student said: "Er ruft seine Mutter an jeden Sonntag."\n\nEvaluate the student\'s sentence.',
     "FIX: Er ruft seine Mutter jeden Sonntag an.\nWHY: The separable prefix an goes to the end."),
]


def german_messages(item: dict) -> list[dict]:
    if item["mode"] != "correction":
        return rbe.build_messages(item)  # the cloze prompt is already German
    partner = item.get("partner")
    if partner:
        user = (f'Der Gesprächspartner hat gerade gesagt: "{partner}"\n'
                f'Der Lernende hat geantwortet: "{item["input"]}"\n\n'
                "Bewerte nur die Antwort des Lernenden.")
    else:
        user = f'Der Lernende hat gesagt: "{item["input"]}"\n\nBewerte den Satz des Lernenden.'
    return [{"role": "system", "content": GERMAN_CORRECTION_SYSTEM},
            {"role": "user", "content": user}]


def fewshot_messages(item: dict) -> list[dict]:
    base = rbe.build_messages(item)
    if item["mode"] != "correction":
        return base
    msgs = [base[0]]
    for u, a in SHOTS:
        msgs += [{"role": "user", "content": u}, {"role": "assistant", "content": a}]
    return msgs + [base[1]]


BUILDERS = {"english": rbe.build_messages, "german": german_messages, "fewshot": fewshot_messages}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=sorted(BUILDERS), required=True)
    ap.add_argument("--model", default="models/elmod-2.7b-it-4bit")
    ap.add_argument("--eval-file", default=str(ROOT / "data/eval/grammar_eval_v0.json"))
    ap.add_argument("--tag", default=None)
    args = ap.parse_args()

    build = BUILDERS[args.mode]
    items = json.loads(Path(args.eval_file).read_text())["items"]

    print(f"loading {args.model} ...")
    model, tokenizer = load(args.model)

    def build_prompt(messages):
        """Gemma 2 templates reject a system role — same fallback run_baseline_eval.py uses."""
        try:
            return tokenizer.apply_chat_template(messages, add_generation_prompt=True)
        except Exception:
            merged = [{"role": "user",
                       "content": messages[0]["content"] + "\n\n" + messages[1]["content"]}]
            return tokenizer.apply_chat_template(merged, add_generation_prompt=True)

    # The 2048-token window is the binding constraint in fewshot mode — check before generating,
    # so a context overflow can't be mistaken for a model failure.
    longest = max(len(build_prompt(build(it))) for it in items)
    print(f"longest prompt: {longest} tok (+400 generation) against a 2048 window")
    if longest + 400 > 2048:
        sys.exit("prompt exceeds the window — this would measure the window, not the model")

    results = []
    for i, item in enumerate(items, 1):
        prompt = build_prompt(build(item))
        max_tokens = 150 if item["mode"] == "cloze" else 400
        raw = rbe.strip_channels(generate(model, tokenizer, prompt=prompt,
                                          max_tokens=max_tokens, verbose=False))
        r = rbe.score(item, rbe.apply_app_guard(raw, item))
        r["response"] = raw
        results.append(r)
        print(f"[{i}/{len(items)}] {item['id']}: {'PASS' if r['pass'] else 'FAIL'}")

    tag = args.tag or args.mode
    short = args.model.rstrip("/").split("/")[-1]
    out = ROOT / "results" / f"{tag}_{short}.json"
    out.write_text(json.dumps({"model": args.model, "app_guard": True, "prompt_mode": args.mode,
                               "results": results}, ensure_ascii=False, indent=1), encoding="utf-8")

    by_id = {it["id"]: it for it in items}
    corr = [r for r in results if r["mode"] == "correction"]
    ok = [r for r in corr if by_id[r["id"]].get("expect_ok")]
    err = [r for r in corr if not by_id[r["id"]].get("expect_ok")]
    fmt = sum(bool(re.search(r"FIX:\s*\S", r["response"]))
              or r["response"].strip().upper().rstrip(".!") == "OK" for r in corr)
    strict = sum(r["pass"] for r in results)

    print("\n" + "=" * 60)
    print(f"{args.mode.upper()} — {Path(args.eval_file).name} ({len(items)} items), guarded")
    print(f"  strict            {strict}/{len(items)} ({strict / len(items) * 100:.0f}%)")
    print(f"  false-correction  {sum(not r['pass'] for r in ok)}/{len(ok)}")
    print(f"  miss              {sum(not r['pass'] for r in err)}/{len(err)}")
    print(f"  format adherence  {fmt}/{len(corr)} ({fmt / len(corr) * 100:.0f}%)")
    print(f"\nsaved: {out}")


if __name__ == "__main__":
    main()
