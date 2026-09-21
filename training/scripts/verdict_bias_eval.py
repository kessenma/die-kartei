#!/usr/bin/env python3
"""Step 0b — the zero-cost control: bias the FIRST generated token toward `FIX` and re-score.

REINFORCEMENT_LEARNING.md Part A §2/§5: if a decode-time logit bias alone takes E4B v4 from
miss 16% → ≤ 9% at FC ≤ 6%, RL is unnecessary for E4B. The app's echo guard makes over-FIXing
cheap, so this is the number RL has to beat. The bias is applied ONLY at the first generated
position (where the model chooses between `OK` and `FIX`), so the rest of the correction is
untouched.

Same prompts, scorer, and --app-guard semantics as run_baseline_eval.py; results land in
results/guarded-<suite>_<model>+bias<b>.json so rescore/behavior_metrics work unchanged.

Usage (from training/):
  .venv/bin/python scripts/verdict_bias_eval.py --model models/gemma4-e4b-german-v4-4bit \
      --bias 1.0 2.0 4.0 --suites v0 v1ext v2 v3 [--limit N]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from run_baseline_eval import apply_app_guard, build_messages, score, strip_channels, summarize  # noqa: E402

SUITES = {"v0": "grammar_eval_v0.json", "v1ext": "grammar_eval_v1_extra.json",
          "v2": "grammar_eval_v2_holdout.json", "v3": "grammar_eval_v3.json"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="models/gemma4-e4b-german-v4-4bit")
    ap.add_argument("--bias", type=float, nargs="+", default=[1.0, 2.0, 4.0])
    ap.add_argument("--suites", nargs="+", default=["v0", "v1ext", "v2", "v3"])
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    from transformers import AutoTokenizer
    _orig = AutoTokenizer.register

    def _safe(*a, **k):
        try:
            _orig(*a, **k)
        except Exception:
            pass
    AutoTokenizer.register = _safe
    import mlx.core as mx
    from mlx_lm import generate, load

    model, tokenizer = load(args.model)
    # the first token of "FIX" and of "OK" as the model would emit them at the start of a reply
    fix_ids = tokenizer.encode("FIX", add_special_tokens=False)
    ok_ids = tokenizer.encode("OK", add_special_tokens=False)
    print(f"first-token ids: FIX={fix_ids} OK={ok_ids}")
    fix_id, ok_id = fix_ids[0], ok_ids[0]

    shortname = args.model.rstrip("/").split("/")[-1]
    for b in args.bias:
        for suite in args.suites:
            items = json.loads((ROOT / "data" / "eval" / SUITES[suite]).read_text())["items"]
            items = [it for it in items if it["mode"] == "correction"]  # the bias is about verdicts
            if args.limit:
                items = items[: args.limit]
            results = []
            for it in items:
                msgs = build_messages(it)
                try:
                    prompt = tokenizer.apply_chat_template(msgs, add_generation_prompt=True, enable_thinking=False)
                except Exception:
                    merged = [{"role": "user", "content": msgs[0]["content"] + "\n\n" + msgs[1]["content"]}]
                    prompt = tokenizer.apply_chat_template(merged, add_generation_prompt=True, enable_thinking=False)
                calls = [0]

                def first_token_bias(tokens, logits, b=b):
                    # mlx_lm 0.31 hands the processor only the tokens generated so far (shape (1,) on
                    # the first call, holding the last prompt token) — NOT the full history. A
                    # "tokens.shape == prompt length" check therefore never fires (measured 2026-09-05:
                    # three bias values, 466 items, zero changes). Fire on the first call instead.
                    calls[0] += 1
                    if calls[0] == 1:
                        logits = logits.at[..., fix_id].add(b)
                        logits = logits.at[..., ok_id].add(-b)
                    return logits

                raw = strip_channels(generate(model, tokenizer, prompt=prompt, max_tokens=120, verbose=False,
                                              logits_processors=[first_token_bias]))
                r = score(it, apply_app_guard(raw, it))
                r["response"] = raw
                results.append(r)
            summary = summarize(results)
            out = ROOT / "results" / f"guarded-{suite}_{shortname}+bias{b:g}.json"
            out.write_text(json.dumps({"model": f"{args.model}+bias{b:g}", "app_guard": True, "bias": b,
                                       "summary": summary, "results": results}, ensure_ascii=False, indent=1))
            ok_items = [r for r, it in zip(results, items) if it.get("expect_ok")]
            err_items = [r for r, it in zip(results, items) if not it.get("expect_ok")]
            fc = sum(not r["pass"] for r in ok_items)
            miss = sum(not r["pass"] for r in err_items)
            print(f"bias {b:+.1f}  {suite:6s} {summary['overall']:>8s}  FC {fc}/{len(ok_items)}  "
                  f"miss {miss}/{len(err_items)}  format_errors {summary['format_errors']}  -> {out.name}", flush=True)


if __name__ == "__main__":
    main()
