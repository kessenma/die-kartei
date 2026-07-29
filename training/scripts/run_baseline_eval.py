#!/usr/bin/env python3
"""Run the grammar eval against a local MLX model and report per-phenomenon scores.

Usage (from training/):
  .venv/bin/python scripts/run_baseline_eval.py                 # full run (downloads model on first use)
  .venv/bin/python scripts/run_baseline_eval.py --dry-run       # validate items + show prompts, no model
  .venv/bin/python scripts/run_baseline_eval.py --limit 5       # quick spot-check
  .venv/bin/python scripts/run_baseline_eval.py --model <hf-id-or-local-path>

Default model is the exact repo the app ships for "Gemma 4 E4B".
Results are written to results/<tag>_<model-shortname>.json.
"""

import argparse
import json
import re
import sys
from pathlib import Path

DEFAULT_MODEL = "mlx-community/gemma-4-e4b-it-4bit"
ROOT = Path(__file__).resolve().parent.parent
EVAL_FILE = ROOT / "data" / "eval" / "grammar_eval_v0.json"
RESULTS_DIR = ROOT / "results"

# Mirrors ConversationPrompts.correctionSystemPrompt (B1 / du / medium strictness).
CORRECTION_SYSTEM = (
    "You are a meticulous German teacher reviewing one line a student said during a spoken conversation. "
    "The student's level is B1. Correct clear grammar mistakes, but ignore minor style issues. "
    "The student uses the du form. "
    "They may have mixed in an English word they didn't know — in your correction, replace it with the correct German word.\n\n"
    "If the sentence is already correct and natural German, reply with exactly:\nOK\n\n"
    "Otherwise reply in EXACTLY this format and nothing else:\n"
    "FIX: <the full corrected sentence in natural German>\n"
    "WHY: <one short explanation in English, at most 18 words>"
)

CLOZE_SYSTEM = (
    "Du bist ein präziser Deutschlehrer. Antworte nur mit dem fehlenden Wort oder der fehlenden Form, "
    "ohne Erklärung und ohne zusätzliche Wörter."
)


def build_messages(item: dict) -> list[dict]:
    if item["mode"] == "correction":
        partner = item.get("partner")
        if partner:
            user = (
                f'The conversation partner just said: "{partner}"\n'
                f'The student replied: "{item["input"]}"\n\nEvaluate only the student\'s reply.'
            )
        else:
            user = f'The student said: "{item["input"]}"\n\nEvaluate the student\'s sentence.'
        return [
            {"role": "system", "content": CORRECTION_SYSTEM},
            {"role": "user", "content": user},
        ]
    return [
        {"role": "system", "content": CLOZE_SYSTEM},
        {"role": "user", "content": item["input"]},
    ]


def strip_channels(text: str) -> str:
    """Remove thinking blocks (Gemma 4 channels, Qwen <think>), like the app's stripThinkBlocks."""
    text = re.sub(r"<\|channel>.*?<channel\|>", "", text, flags=re.S)
    text = text.split("<|channel>")[0]  # drop an unclosed (truncated) block
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S)
    return text.split("<think>")[0].strip()


def _guard_normalize(text: str) -> str:
    """Fold the differences that don't constitute a correction: wrapping quotes, whitespace,
    case, trailing sentence punctuation. Deliberately NOT diacritic-insensitive — for a German
    tutor an umlaut fix (Madchen → Mädchen) is a real correction, not an echo."""
    t = text.strip().strip('"“”„«»\'')
    t = re.sub(r"\s+", " ", t).strip()
    return t.rstrip(".!?").strip().casefold()


def apply_app_guard(response: str, item: dict) -> str:
    """Mirror the app's echo guard (ConversationPrompts.parseCorrection): a FIX line that
    restates the student's sentence verbatim is not a correction — the app shows nothing,
    so the honest eval verdict is OK. Pure post-process; can only ever turn a spurious FIX
    into OK, never the reverse."""
    m = re.search(r"FIX:\s*(.+)", response)
    if m and _guard_normalize(m.group(1)) == _guard_normalize(item["input"]):
        return "OK"
    return response


def matches(needle: str, haystack: str) -> bool:
    """Case-insensitive; word-boundary for single words, substring for phrases."""
    haystack = haystack.lower()
    needle = needle.lower()
    if " " in needle:
        return needle in haystack
    return re.search(rf"(?<!\w){re.escape(needle)}(?!\w)", haystack) is not None


def score(item: dict, response: str) -> dict:
    resp = response.strip()
    result = {"id": item["id"], "phenomenon": item["phenomenon"], "mode": item["mode"],
              "response": resp, "pass": False, "format_ok": True}

    if item["mode"] == "cloze":
        result["pass"] = all(matches(n, resp) for n in item.get("require_all", [])) and (
            not item.get("require_any") or any(matches(n, resp) for n in item["require_any"])
        )
        return result

    # correction mode
    is_ok = resp.upper().rstrip(".!") == "OK" or resp.upper().startswith("OK\n")
    fix_match = re.search(r"FIX:\s*(.+)", resp)
    if item.get("expect_ok"):
        result["pass"] = is_ok
        result["format_ok"] = is_ok or fix_match is not None
        return result

    if not fix_match:
        result["format_ok"] = is_ok  # "OK" is well-formed output, just the wrong verdict
        return result
    fix_line = fix_match.group(1).strip()
    result["fix"] = fix_line
    req_all = item.get("require_all", [])
    req_any = item.get("require_any", [])
    forbid = item.get("forbid_any", [])
    result["pass"] = (
        all(matches(n, fix_line) for n in req_all)
        and (not req_any or any(matches(n, fix_line) for n in req_any))
        and not any(matches(n, fix_line) for n in forbid)
    )
    return result


def summarize(results: list[dict]) -> dict:
    def rate(items):
        return f"{sum(r['pass'] for r in items)}/{len(items)}" if items else "n/a"

    summary = {}
    for phen in sorted({r["phenomenon"] for r in results}):
        sub = [r for r in results if r["phenomenon"] == phen]
        corr = [r for r in sub if r["mode"] == "correction"]
        cloze = [r for r in sub if r["mode"] == "cloze"]
        summary[phen] = {"correction": rate(corr), "cloze": rate(cloze), "total": rate(sub)}
    summary["overall"] = rate(results)
    summary["format_errors"] = sum(not r["format_ok"] for r in results)
    return summary


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--dry-run", action="store_true", help="validate items and print prompts without loading a model")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--tag", default="baseline")
    ap.add_argument("--eval-file", default=str(EVAL_FILE))
    ap.add_argument("--app-guard", action="store_true",
                    help="score as the app behaves: drop FIX lines that echo the input verbatim "
                         "(mirrors ConversationPrompts.parseCorrection). Raw generation is unchanged "
                         "and still saved, so a run can be re-scored either way.")
    ap.add_argument("--responses", default=None,
                    help="score a pre-generated responses JSON (e.g. from eval_apple_intelligence.swift) "
                         "instead of running an MLX model; uses the identical scorer")
    args = ap.parse_args()

    def score_response(item: dict, raw: str) -> dict:
        """Score a raw generation, optionally through the app's echo guard. The saved
        `response` stays the model's real output either way."""
        r = score(item, apply_app_guard(raw, item) if args.app_guard else raw)
        r["response"] = raw
        return r

    items = json.loads(Path(args.eval_file).read_text())["items"]
    if args.limit:
        items = items[: args.limit]
    print(f"{len(items)} eval items loaded from {Path(args.eval_file).name}")

    if args.dry_run:
        for item in items:
            msgs = build_messages(item)  # raises if an item is malformed
            assert item["mode"] in ("correction", "cloze"), item["id"]
            if not item.get("expect_ok"):
                assert item.get("require_any") or item.get("require_all"), f"{item['id']}: no scoring criteria"
        print("dry run: all items build valid prompts and have scoring criteria.")
        ex = build_messages(items[0])
        print(f"\nexample prompt ({items[0]['id']}):\n" + json.dumps(ex, ensure_ascii=False, indent=2))
        return

    if args.responses:
        # Score pre-generated responses (e.g. from the Swift FoundationModels harness,
        # eval_apple_intelligence.swift) with the exact same rubric as an MLX run — the
        # only honest way to put Apple Intelligence on the same scoreboard.
        payload = json.loads(Path(args.responses).read_text())
        resp_map = {r["id"]: r["response"] for r in payload["results"]}
        missing = [item["id"] for item in items if item["id"] not in resp_map]
        results = [score_response(item, strip_channels(resp_map.get(item["id"], ""))) for item in items]
        for i, r in enumerate(results, 1):
            print(f"[{i}/{len(items)}] {r['id']}: {'PASS' if r['pass'] else 'FAIL'}")
        if missing:
            print(f"warning: {len(missing)} items had no response: {missing[:5]}")
    else:
        # mlx-lm 0.31.3 crashes importing under transformers 5.x while registering its
        # "NewlineTokenizer" (unrelated to Gemma). Make that registration non-fatal.
        from transformers import AutoTokenizer

        _orig_register = AutoTokenizer.register

        def _safe_register(*a, **k):
            try:
                _orig_register(*a, **k)
            except Exception:
                pass

        AutoTokenizer.register = _safe_register

        from mlx_lm import load, generate  # deferred so --dry-run works without model deps

        print(f"loading {args.model} ... (first run downloads the weights)")
        model, tokenizer = load(args.model)

        results = []
        for i, item in enumerate(items, 1):
            messages = build_messages(item)
            try:
                prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True, enable_thinking=False)
            except Exception:  # template without system-role support: merge into user turn
                merged = [{"role": "user", "content": messages[0]["content"] + "\n\n" + messages[1]["content"]}]
                prompt = tokenizer.apply_chat_template(merged, add_generation_prompt=True, enable_thinking=False)
            max_tokens = 150 if item["mode"] == "cloze" else 400  # headroom in case thinking still fires
            response = strip_channels(generate(model, tokenizer, prompt=prompt, max_tokens=max_tokens, verbose=False))
            r = score_response(item, response)
            results.append(r)
            print(f"[{i}/{len(items)}] {item['id']}: {'PASS' if r['pass'] else 'FAIL'}")

    summary = summarize(results)
    RESULTS_DIR.mkdir(exist_ok=True)
    shortname = args.model.rstrip("/").split("/")[-1]
    out = RESULTS_DIR / f"{args.tag}_{shortname}.json"
    out.write_text(json.dumps({"model": args.model, "app_guard": args.app_guard,
                               "summary": summary, "results": results},
                              ensure_ascii=False, indent=1), encoding="utf-8")

    print("\n=== summary ===")
    for phen, s in summary.items():
        print(f"  {phen}: {s}")
    print(f"\nfull results: {out}")


if __name__ == "__main__":
    main()
