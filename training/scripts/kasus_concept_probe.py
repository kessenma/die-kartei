#!/usr/bin/env python3
"""Sample the app's tutors on tutor-written Verstehen items (KASUS_CONCEPT_PROBE.md).

Each prompt record comes from `kasus-cli concept-prompts` (the app's own planner and prompt), so
what a model sees here is what it would see in the app. This script only generates; the gate
(`kasus-cli concept-check`) and the tables live in kasus_concept_report.py.

Sampling matches the app: system + user chat turns, enable_thinking=False, temperature 0.75,
top_p 1 (the app's MLX default), the prompt's own max tokens. Each generation is seeded with
mx.random.seed(<plan seed> + <repeat> * 1000) so a run can be repeated exactly. Never through
mlx_lm.server (it looped in the Kasus dry run): mlx_lm.generate in this process.

Output: one JSON line per generation, appended to <out>/raw_<label>.jsonl:
    {id, model, label, repeat, seed, plan, raw, seconds, tokens, error}
A rerun skips (id, repeat) pairs already in the file, so an interrupted run resumes.

Usage (from training/):
    kasus_cli/build/kasus-cli concept-prompts all:all:1-10 > results/kasus-concept-probe/prompts.jsonl
    .venv/bin/python scripts/kasus_concept_probe.py --model e4b --limit 5          # dry run
    .venv/bin/python scripts/kasus_concept_probe.py --model all
"""

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "results" / "kasus-concept-probe"

# The four tutors the app ships (german-ai-flashcards/Services/MLXModel*.swift), by short label.
MODELS = {
    "e4b": "kessenma/gemma4-e4b-german-tutor-v4-4bit",
    "e2b": "kessenma/gemma4-e2b-german-tutor-4bit",
    "granite41-3b": "kessenma/granite41-3b-german-tutor-v4-4bit",
    "granite33-2b": "kessenma/granite33-2b-german-tutor-v4-4bit",
}


def done_keys(path: Path) -> set:
    if not path.exists():
        return set()
    keys = set()
    for line in path.read_text().splitlines():
        if line.strip():
            r = json.loads(line)
            keys.add((r["id"], r["repeat"]))
    return keys


def run_model(label: str, repo: str, records: list, repeats: int, out: Path) -> None:
    from transformers import AutoTokenizer
    _orig = AutoTokenizer.register

    def _safe(*a, **k):  # the same guard run_variety_probe.py needs for Gemma 4 tokenizers
        try:
            _orig(*a, **k)
        except Exception:
            pass

    AutoTokenizer.register = _safe

    import mlx.core as mx
    from mlx_lm import load, generate
    from mlx_lm.sample_utils import make_sampler

    path = out / f"raw_{label}.jsonl"
    skip = done_keys(path)
    todo = [(r, k) for r in records for k in range(repeats) if (r["id"], k) not in skip]
    if not todo:
        print(f"{label}: nothing to do ({len(skip)} already in {path.name})")
        return
    print(f"{label}: loading {repo} …", flush=True)
    model, tokenizer = load(repo)

    def to_prompt(system: str, user: str):
        messages = [{"role": "system", "content": system}, {"role": "user", "content": user}]
        try:
            return tokenizer.apply_chat_template(messages, add_generation_prompt=True, enable_thinking=False)
        except Exception:  # a template without a system role: merged into the user turn
            merged = [{"role": "user", "content": system + "\n\n" + user}]
            return tokenizer.apply_chat_template(merged, add_generation_prompt=True, enable_thinking=False)

    with path.open("a") as f:
        for n, (record, repeat) in enumerate(todo, 1):
            seed = int(record["seed"]) + repeat * 1000
            mx.random.seed(seed)
            prompt = to_prompt(record["system"], record["user"])
            sampler = make_sampler(temp=float(record["temperature"]), top_p=1.0)
            start = time.time()
            raw, error, tokens = "", None, None
            try:
                raw = generate(model, tokenizer, prompt=prompt, max_tokens=int(record["maxTokens"]),
                               sampler=sampler, verbose=False)
                tokens = len(tokenizer.encode(raw))
            except Exception as e:  # recorded, never fatal: a crash is a result too
                error = f"{type(e).__name__}: {e}"
            seconds = round(time.time() - start, 2)
            f.write(json.dumps({"id": record["id"], "model": label, "repo": repo, "repeat": repeat, "seed": seed,
                                "kind": record["kind"], "unit": record["unit"], "plan": record["plan"],
                                "raw": raw, "seconds": seconds, "tokens": tokens, "error": error},
                               ensure_ascii=False) + "\n")
            f.flush()
            first = raw.strip().splitlines()[0] if raw.strip() else (error or "")
            print(f"{label} {n}/{len(todo)} {record['id']} {seconds}s  {first[:90]}", flush=True)
    del model


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="all", help="a label (" + ", ".join(MODELS) + ") or all")
    ap.add_argument("--prompts", default=str(OUT / "prompts.jsonl"))
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--limit", type=int, default=0, help="only the first N prompts (a dry run)")
    ap.add_argument("--repeats", type=int, default=1)
    args = ap.parse_args()

    records = [json.loads(l) for l in Path(args.prompts).read_text().splitlines() if l.strip()]
    if args.limit:
        records = records[: args.limit]
    labels = list(MODELS) if args.model == "all" else [args.model]
    for label in labels:
        if label not in MODELS:
            sys.exit(f"unknown model {label}: {', '.join(MODELS)}")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    print(f"{len(records)} prompts × {args.repeats} × {len(labels)} model(s)")
    for label in labels:
        run_model(label, MODELS[label], records, args.repeats, out)


if __name__ == "__main__":
    main()
