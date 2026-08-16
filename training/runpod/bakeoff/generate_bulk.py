#!/usr/bin/env python3
"""Batched bulk generation from a `build_gen_jobs.py` manifest, using transformers.

Why not vLLM
------------
vLLM (through 0.27.1, the newest) **cannot load `google/gemma-4-31B-it`**:

    AmbiguousGlobalPerLayerAttributeError: 'head_dim' is a per-layer attribute

Gemma 4 carries a heterogeneous per-layer config; vLLM's config convertor reads `head_dim`
globally. There is no upstream fix, and forcing `allow_global_per_layer_attribute_access=True`
is NOT an acceptable workaround — its own warning says homogeneous-assuming code "may use the
global value incorrectly", which for attention head dimensions means silently wrong inference
and a corpus that passes every downstream gate while being quietly garbage.

Why batched
-----------
The bake-off script (`generate_hardcase.py`) generates ONE prompt at a time. Its measured
50 rows / 35 min was therefore batch-size-1, and extrapolating that to "bulk is ~90 hours" was
wrong — batching is the single biggest throughput lever in generation and it had simply never
been tried. This script batches, and on an 80 GB card runs bf16 with no quantization penalty
(bitsandbytes int8 was the other half of the slowness: it is memory-bound and pinned the GPU
at 5-20% utilisation).

Resumable: completed job ids are appended to `<out>.done` and a rerun skips them.

Usage:
    python generate_bulk.py --jobs jobs_corr.jsonl --out candidates.jsonl \
        --model google/gemma-4-31B-it --batch 16 [--limit 25] [--max-new-tokens 1400]
"""
import argparse
import json
import os
import re
import sys
import time

# Anchored to key position. The unanchored version of this regex (§1.5b) rewrote
# `"verdict":"fix","fix":"..."` into invalid JSON and silently destroyed every correction row
# while the pass rate went UP.
_DUP_KEY_RE = re.compile(r'([,{])\s*"(\w+)"\s*,\s*"\2"\s*:')


def repair(line: str) -> str:
    return _DUP_KEY_RE.sub(r'\1"\2":', line)


def parse_rows(text: str) -> list:
    """Teachers emit bare JSONL, ```json fences, a German preamble, or pretty-printed objects."""
    rows = []
    text = re.sub(r"```(?:json|jsonl)?", "", text)
    for line in text.splitlines():
        line = line.strip().rstrip(",")
        if not line.startswith("{"):
            continue
        try:
            rows.append(json.loads(repair(line)))
        except json.JSONDecodeError:
            continue
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", default="google/gemma-4-31B-it")
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--limit", type=int, default=0, help="only run the first N jobs (pilot)")
    ap.add_argument("--max-new-tokens", type=int, default=1400)
    ap.add_argument("--temp", type=float, default=0.9)
    ap.add_argument("--top-p", type=float, default=0.95)
    ap.add_argument("--load-8bit", action="store_true", help="only if the card can't hold bf16")
    args = ap.parse_args()

    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    jobs = [json.loads(l) for l in open(args.jobs) if l.strip()]
    if args.limit:
        jobs = jobs[: args.limit]

    done_path = args.out + ".done"
    done = set()
    if os.path.exists(done_path):
        done = {l.strip() for l in open(done_path) if l.strip()}
    jobs = [j for i, j in enumerate(jobs) if str(j.get("id", i)) not in done]
    print(f"{len(jobs)} jobs to run (batch {args.batch})", flush=True)

    print(f"loading {args.model} ...", flush=True)
    t0 = time.time()
    tok = AutoTokenizer.from_pretrained(args.model)
    tok.padding_side = "left"                      # required for correct batched generation
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    kw = {"device_map": "auto", "dtype": torch.bfloat16}
    if args.load_8bit:
        from transformers import BitsAndBytesConfig
        kw["quantization_config"] = BitsAndBytesConfig(load_in_8bit=True)
        kw.pop("dtype")
    model = AutoModelForCausalLM.from_pretrained(args.model, **kw)
    model.eval()
    print(f"loaded in {time.time()-t0:.0f}s, "
          f"{torch.cuda.memory_allocated()/1e9:.1f} GB", flush=True)

    def build(job):
        msgs = [{"role": "system", "content": job["system"]},
                {"role": "user", "content": job["user"]}]
        try:
            return tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False,
                                           enable_thinking=False)
        except TypeError:
            # Templates that don't take the kwarg. `enable_thinking=False` matters for Qwen3.x,
            # whose template otherwise opens a <think> block and burns the whole token budget
            # before emitting any JSON — it looks exactly like a capability failure.
            return tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False)

    out_fh = open(args.out, "a")
    done_fh = open(done_path, "a")
    total_rows, total_tokens, t_start = 0, 0, time.time()

    for start in range(0, len(jobs), args.batch):
        chunk = jobs[start : start + args.batch]
        prompts = [build(j) for j in chunk]
        enc = tok(prompts, return_tensors="pt", padding=True, truncation=True,
                  max_length=3072).to(model.device)
        t1 = time.time()
        with torch.no_grad():
            gen = model.generate(**enc, max_new_tokens=args.max_new_tokens,
                                 do_sample=True, temperature=args.temp, top_p=args.top_p,
                                 pad_token_id=tok.pad_token_id)
        dt = time.time() - t1
        new_tok = (gen.shape[1] - enc["input_ids"].shape[1]) * gen.shape[0]
        total_tokens += new_tok

        batch_rows = 0
        for j, seq in zip(chunk, gen):
            text = tok.decode(seq[enc["input_ids"].shape[1]:], skip_special_tokens=True)
            for r in parse_rows(text):
                # The manifest is authoritative about its own metadata. The v2 teacher rewrote
                # "phenomenon":"verdict" as "none" on every verdict job and the validator's
                # whitelist then rejected all of them (§1.4). Force, don't setdefault.
                r["task"] = "correction"
                r["phenomenon"] = j["phenomenon"]
                r["level"] = j.get("level", r.get("level"))
                r["formality"] = j.get("formality", r.get("formality"))
                if j.get("meta"):
                    r.setdefault("meta", {}).update(j["meta"])
                out_fh.write(json.dumps(r, ensure_ascii=False) + "\n")
                batch_rows += 1
            done_fh.write(str(j.get("id", "")) + "\n")
        out_fh.flush(); done_fh.flush()
        total_rows += batch_rows

        elapsed = time.time() - t_start
        pct = (start + len(chunk)) / len(jobs)
        eta = elapsed / pct - elapsed if pct else 0
        print(f"[{start+len(chunk)}/{len(jobs)}] +{batch_rows} rows "
              f"({total_rows} total) | {new_tok/dt:.0f} tok/s | "
              f"eta {eta/60:.0f} min", flush=True)

    out_fh.close(); done_fh.close()
    print(f"\nwrote {total_rows} rows to {args.out}")
    print(f"aggregate {total_tokens/(time.time()-t_start):.0f} tok/s over "
          f"{(time.time()-t_start)/60:.1f} min")
    return 0


if __name__ == "__main__":
    sys.exit(main())
