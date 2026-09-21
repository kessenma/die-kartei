#!/usr/bin/env python3
"""Score a Gemma 4 E-series *merged bf16* checkpoint (no 4-bit) with the exact eval scorer.

Why this exists (REINFORCEMENT_LEARNING.md Part A §9 row 6): an RL update can be real in bf16 and
erased by 4-bit quantisation. Scoring the unquantised merge on the same suites, greedy, tells
"quantisation erased it" apart from "it never moved the greedy mode" — before paying for another run.

Loads the HF safetensors directly through mlx_lm (bf16, ~16 GB unified memory) with the same
KV-shared-layer sanitize patch as scripts/convert_gemma4_patched.py. Results land in
results/<tag>_<name>-bf16.json in run_baseline_eval's format, so behavior_metrics.py and the
McNemar scripts work unchanged.

Usage (from training/):
  .venv/bin/python scripts/eval_unquantized_gemma4.py --model models/gemma4-e4b-german-rl1-merged \\
      --suites v0 v1ext v2 v3 [--limit N]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from run_baseline_eval import apply_app_guard, build_messages, score, strip_channels, summarize  # noqa: E402

SUITES = {"v0": "grammar_eval_v0.json", "v1ext": "grammar_eval_v1_extra.json",
          "v2": "grammar_eval_v2_holdout.json", "v3": "grammar_eval_v3.json"}
TAGS = {"v0": "guarded-v0", "v1ext": "guarded-v1ext", "v2": "guarded-v2", "v3": "guarded-v3"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="merged HF checkpoint dir (bf16 safetensors)")
    ap.add_argument("--suites", nargs="+", default=["v0", "v1ext", "v2", "v3"])
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    from transformers import AutoTokenizer
    AutoTokenizer.register = lambda *a, **k: None  # mlx-lm 0.31 + transformers 5 registration quirk
    import mlx_lm.models.gemma4 as g
    from mlx_lm import generate, load

    cfg = json.load(open(Path(args.model) / "config.json"))
    tc = cfg.get("text_config", cfg)
    first_shared = tc.get("num_hidden_layers", 42) - tc.get("num_kv_shared_layers", 18)
    _orig = g.Model.sanitize

    def sanitize(self, weights):
        w = _orig(self, weights)
        pat = re.compile(r"language_model\.model\.layers\.(\d+)\.self_attn\.(k_proj|v_proj|k_norm)\.weight$")
        for k in [k for k in w if (m := pat.match(k)) and int(m.group(1)) >= first_shared]:
            w.pop(k)
        return w
    g.Model.sanitize = sanitize

    t0 = time.time()
    model, tokenizer = load(args.model)
    print(f"loaded {args.model} unquantised in {time.time() - t0:.0f}s", flush=True)
    shortname = args.model.rstrip("/").split("/")[-1].replace("-merged", "") + "-bf16"

    for suite in args.suites:
        items = json.loads((ROOT / "data" / "eval" / SUITES[suite]).read_text())["items"]
        if args.limit:
            items = items[: args.limit]
        results, t1 = [], time.time()
        for it in items:
            msgs = build_messages(it)
            try:
                prompt = tokenizer.apply_chat_template(msgs, add_generation_prompt=True, enable_thinking=False)
            except Exception:
                merged = [{"role": "user", "content": msgs[0]["content"] + "\n\n" + msgs[1]["content"]}]
                prompt = tokenizer.apply_chat_template(merged, add_generation_prompt=True, enable_thinking=False)
            max_tokens = 150 if it["mode"] == "cloze" else 400
            raw = strip_channels(generate(model, tokenizer, prompt=prompt, max_tokens=max_tokens, verbose=False))
            r = score(it, apply_app_guard(raw, it))
            r["response"] = raw
            results.append(r)
        summary = summarize(results)
        out = ROOT / "results" / f"{TAGS[suite]}_{shortname}.json"
        out.write_text(json.dumps({"model": args.model + " (bf16, unquantised)", "app_guard": True,
                                   "summary": summary, "results": results}, ensure_ascii=False, indent=1))
        print(f"{TAGS[suite]:14s} {summary['overall']:>8s}  format_errors {summary['format_errors']}  "
              f"({(time.time() - t1) / 60:.1f} min) -> {out.name}", flush=True)


if __name__ == "__main__":
    main()
