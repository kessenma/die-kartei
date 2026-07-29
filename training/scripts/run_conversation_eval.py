#!/usr/bin/env python3
"""Generate conversation-mode responses for the naturalness bench.

Companion to run_baseline_eval.py, which covers the grammar suites. This one runs the app's
*conversation* mode — the Lena / role-play partner — and only generates. Scoring is a separate
step (scripts/naturalness_metrics.py), because naturalness has no pass/fail: it is a set of
proxies compared between models.

System prompts are imported from pack_dataset.py rather than restated, so the bench can never
silently drift from what the model was actually trained on.

Usage (from training/):
  .venv/bin/python scripts/run_conversation_eval.py --dry-run
  .venv/bin/python scripts/run_conversation_eval.py --model kessenma/gemma4-e4b-german-tutor-4bit \
      --tag e4b-v1
  .venv/bin/python scripts/naturalness_metrics.py results/conv_e4b-v1_*.responses.json
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pack_dataset import conversation_system  # the app's exact strings, single source of truth

ROOT = Path(__file__).resolve().parent.parent
EVAL_FILE = ROOT / "data" / "eval" / "conversation_v0.json"
RESULTS_DIR = ROOT / "results"

# ConversationPrompts.openerSeed — the hidden user turn the app sends so the model speaks first.
OPENER_SEED = ("Beginne jetzt das Gespräch auf Deutsch mit einer kurzen, freundlichen "
               "Begrüßung und einer Frage an mich.")


def build_messages(item: dict) -> list[dict]:
    """Reproduce the exact turn sequence the app sends: system, opener seed, then history."""
    spec = {"level": item["level"], "formality": item["formality"],
            "scenario": item.get("scenario"), "deck_words": item.get("deck_words")}
    msgs = [{"role": "system", "content": conversation_system(spec)},
            {"role": "user", "content": OPENER_SEED}]
    msgs += [{"role": m["role"], "content": m["content"]} for m in item.get("history", [])]
    return msgs


def strip_channels(text: str) -> str:
    """Same thinking-block strip as run_baseline_eval.py / the app's stripThinkBlocks."""
    import re
    text = re.sub(r"<\|channel>.*?<channel\|>", "", text, flags=re.S)
    text = text.split("<|channel>")[0]
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S)
    return text.split("<think>")[0].strip()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="kessenma/gemma4-e4b-german-tutor-4bit")
    ap.add_argument("--eval-file", default=str(EVAL_FILE))
    ap.add_argument("--tag", default="conv")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--max-tokens", type=int, default=220)
    ap.add_argument("--temp", type=float, default=0.0,
                    help="0 = greedy. Naturalness proxies are sensitive to sampling, so keep "
                         "this identical across every model you intend to compare.")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    items = json.loads(Path(args.eval_file).read_text())["items"]
    if args.limit:
        items = items[: args.limit]
    print(f"{len(items)} conversation items loaded from {Path(args.eval_file).name}")

    if args.dry_run:
        for item in items:
            msgs = build_messages(item)
            assert msgs[0]["role"] == "system" and msgs[1]["content"] == OPENER_SEED, item["id"]
            # a reply item must hand the model a user turn to answer
            if item.get("history"):
                assert msgs[-1]["role"] == "user", f"{item['id']}: history must end on a user turn"
        print("dry run: all items build valid prompts.")
        print(f"\nexample ({items[0]['id']}):\n" +
              json.dumps(build_messages(items[0]), ensure_ascii=False, indent=2))
        ex = next(i for i in items if i.get("history"))
        print(f"\nexample reply item ({ex['id']}):\n" +
              json.dumps(build_messages(ex), ensure_ascii=False, indent=2))
        return

    from transformers import AutoTokenizer  # mlx-lm 0.31.3 / transformers 5.x registration guard
    _orig = AutoTokenizer.register

    def _safe(*a, **k):
        try:
            _orig(*a, **k)
        except Exception:
            pass

    AutoTokenizer.register = _safe

    from mlx_lm import load, generate
    from mlx_lm.sample_utils import make_sampler

    print(f"loading {args.model} ...")
    model, tokenizer = load(args.model)
    sampler = make_sampler(temp=args.temp)

    results = []
    for i, item in enumerate(items, 1):
        messages = build_messages(item)
        try:
            prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True,
                                                   enable_thinking=False)
        except Exception:  # template without system-role support: merge system into first user turn
            merged = [{"role": "user",
                       "content": messages[0]["content"] + "\n\n" + messages[1]["content"]}] + messages[2:]
            prompt = tokenizer.apply_chat_template(merged, add_generation_prompt=True,
                                                   enable_thinking=False)
        raw = generate(model, tokenizer, prompt=prompt, max_tokens=args.max_tokens,
                       sampler=sampler, verbose=False)
        response = strip_channels(raw)
        results.append({"id": item["id"], "kind": item["kind"], "level": item["level"],
                        "formality": item["formality"], "scenario": item.get("scenario"),
                        "topic": item.get("topic"), "response": response})
        print(f"[{i}/{len(items)}] {item['id']}: {response[:70].replace(chr(10), ' ')}...")

    RESULTS_DIR.mkdir(exist_ok=True)
    shortname = args.model.rstrip("/").split("/")[-1]
    out = RESULTS_DIR / f"conv_{args.tag}_{shortname}.responses.json"
    out.write_text(json.dumps({"model": args.model, "temp": args.temp,
                               "eval_file": Path(args.eval_file).name, "results": results},
                              ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\nresponses: {out}")
    print(f"score with: .venv/bin/python scripts/naturalness_metrics.py {out}")


if __name__ == "__main__":
    main()
