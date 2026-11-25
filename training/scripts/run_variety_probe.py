#!/usr/bin/env python3
"""Generate model responses for the regional-variety probe battery (variety_probe_v0.json).

Companion to scan_variety_markers.py (corpus side) — this is the model side of the variety
study in DIALECT_EVAL.md. Generate-only, like run_conversation_eval.py: scoring lives in
scripts/score_variety_probe.py so the classifier can iterate without re-running generation.

correction-mode items are built with run_baseline_eval.build_messages(), i.e. the app's
real English correction contract; every other item gets one fixed minimal German system
prompt, identical across models, so base-vs-fine-tune deltas are attributable to the model.

Usage (from training/):
  .venv/bin/python scripts/run_variety_probe.py --dry-run
  .venv/bin/python scripts/run_variety_probe.py --limit 3 --model models/gemma4-e4b-german-v4-4bit
  .venv/bin/python scripts/run_variety_probe.py --model models/gemma4-e4b-german-v4-4bit --tag variety-v4
  .venv/bin/python scripts/run_variety_probe.py --model mlx-community/gemma-4-e4b-it-4bit --tag variety-base
  .venv/bin/python scripts/run_variety_probe.py --model … --tag variety-v4-sampled \
      --only elicit --temp 0.7 --repeats 3
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_baseline_eval as rbe  # build_messages, strip_channels; single source of truth

ROOT = Path(__file__).resolve().parent.parent
EVAL_FILE = ROOT / "data" / "eval" / "variety_probe_v0.json"
RESULTS_DIR = ROOT / "results"

CHAT_SYSTEM = "Du bist ein hilfreicher Assistent. Antworte auf Deutsch."

MAX_TOKENS_BY_KIND = {"elicit": 400, "request": 250, "aux": 200, "correction": 400, "dialect": 300}


def build_messages(item: dict) -> list[dict]:
    if item["mode"] == "correction":
        return rbe.build_messages(item)
    return [{"role": "system", "content": CHAT_SYSTEM},
            {"role": "user", "content": item["prompt"]}]


def validate(items: list[dict]) -> None:
    kinds = {"elicit", "request", "aux", "correction", "dialect"}
    for item in items:
        assert item["kind"] in kinds, item["id"]
        if item["mode"] == "correction":
            assert "input" in item, f"{item['id']}: correction item needs input"
            assert item.get("expect_ok") or item.get("require_all") or item.get("require_any"), \
                f"{item['id']}: correction item needs expect_ok or fix criteria"
        else:
            assert item.get("prompt"), f"{item['id']}: chat item needs prompt"
        if item["kind"] == "dialect" and not item.get("manual_review"):
            assert item.get("require_any") or item.get("require_all"), \
                f"{item['id']}: dialect comprehension item needs require_any/require_all"
        build_messages(item)  # raises if malformed


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="models/gemma4-e4b-german-v4-4bit")
    ap.add_argument("--eval-file", default=str(EVAL_FILE))
    ap.add_argument("--tag", default="variety")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--only", default=None, help="run only items of this kind")
    ap.add_argument("--temp", type=float, default=0.0,
                    help="0 = greedy (the primary condition; matches every prior number in "
                         "this repo). Sampled runs are robustness footnotes only.")
    ap.add_argument("--repeats", type=int, default=1,
                    help=">1 requires --temp > 0; each repeat is seeded and the seed recorded")
    ap.add_argument("--max-tokens", type=int, default=0, help="override the per-kind defaults")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.repeats > 1 and args.temp <= 0:
        sys.exit("--repeats > 1 makes no sense at temp 0 (identical generations); set --temp")

    items = json.loads(Path(args.eval_file).read_text())["items"]
    if args.only:
        items = [i for i in items if i["kind"] == args.only]
    if args.limit:
        items = items[: args.limit]
    print(f"{len(items)} probe items loaded from {Path(args.eval_file).name}"
          + (f" (kind={args.only})" if args.only else ""))

    if args.dry_run:
        validate(items)
        print("dry run: all items build valid prompts.")
        shown = set()
        for item in items:
            if item["kind"] in shown:
                continue
            shown.add(item["kind"])
            print(f"\nexample {item['kind']} prompt ({item['id']}):\n"
                  + json.dumps(build_messages(item), ensure_ascii=False, indent=2))
        return

    validate(items)

    # rbe already installed the AutoTokenizer.register guard at import time if needed;
    # replicate it here anyway since importing rbe does NOT run its main().
    from transformers import AutoTokenizer
    _orig = AutoTokenizer.register

    def _safe(*a, **k):
        try:
            _orig(*a, **k)
        except Exception:
            pass

    AutoTokenizer.register = _safe

    import mlx.core as mx
    from mlx_lm import load, generate
    from mlx_lm.sample_utils import make_sampler

    print(f"loading {args.model} ...")
    model, tokenizer = load(args.model)

    def to_prompt(messages: list[dict]):
        try:
            return tokenizer.apply_chat_template(messages, add_generation_prompt=True,
                                                 enable_thinking=False)
        except Exception:  # template without system-role support: merge into user turn
            merged = [{"role": "user",
                       "content": messages[0]["content"] + "\n\n" + messages[1]["content"]}]
            return tokenizer.apply_chat_template(merged, add_generation_prompt=True,
                                                 enable_thinking=False)

    # pre-flight: longest prompt must fit the context window, so an overflow can never be
    # mistaken for a model failure (eval_llammlein.py pattern; trivial for E4B's 131k)
    prompts = {item["id"]: to_prompt(build_messages(item)) for item in items}
    longest = max(len(p) for p in prompts.values())
    cfg = Path(args.model) / "config.json"
    if cfg.exists():
        ctx = json.loads(cfg.read_text()).get("max_position_embeddings")
        if ctx and longest >= ctx:
            sys.exit(f"longest prompt ({longest} tokens) exceeds context window ({ctx})")
        print(f"pre-flight: longest prompt {longest} tokens, context {ctx or 'unknown'}")
    else:
        print(f"pre-flight: longest prompt {longest} tokens (no local config.json; HF-cache model)")

    results = []
    total = len(items) * args.repeats
    n = 0
    for item in items:
        max_tokens = args.max_tokens or MAX_TOKENS_BY_KIND[item["kind"]]
        for rep in range(args.repeats):
            n += 1
            seed = None
            if args.temp > 0:
                seed = 1000 + rep
                mx.random.seed(seed)
            sampler = make_sampler(temp=args.temp)
            raw = generate(model, tokenizer, prompt=prompts[item["id"]],
                           max_tokens=max_tokens, sampler=sampler, verbose=False)
            response = rbe.strip_channels(raw)
            results.append({"id": item["id"], "kind": item["kind"],
                            "framing": item.get("framing"), "variety": item.get("variety"),
                            "repeat": rep, "seed": seed, "response": response})
            print(f"[{n}/{total}] {item['id']}"
                  + (f" (rep {rep})" if args.repeats > 1 else "")
                  + f": {response[:70].replace(chr(10), ' ')}…")

    RESULTS_DIR.mkdir(exist_ok=True)
    shortname = args.model.rstrip("/").split("/")[-1]
    out = RESULTS_DIR / f"{args.tag}_{shortname}.responses.json"
    out.write_text(json.dumps({"model": args.model, "temp": args.temp, "repeats": args.repeats,
                               "eval_file": Path(args.eval_file).name, "results": results},
                              ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\nresponses: {out}")
    print(f"score with: .venv/bin/python scripts/score_variety_probe.py {out}")


if __name__ == "__main__":
    main()
