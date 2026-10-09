#!/usr/bin/env python3
"""One chat turn per record (system + user), through an OpenAI-compatible server or transformers.

Written for the Kasus story bake-off (KASUS_STORY_DATA.md §4), and generic enough for correction
jobs: a record is any JSON object with `id`, `system`, `user` and optionally `maxTokens`. The
output line is the input record plus what came back, so a story line goes straight into
`kasus-cli check` (it carries `plan`, `system`, `user`; `model` is set to `--label`, which is what
the Lab summary groups by), and a correction line goes through `generate_bulk.parse_rows` later.

Backends
--------
openai        a running server (vLLM, mlx_lm.server). Kolibri-1 serves ONLY through vLLM with
              `aleph-alpha-inference`; its reasoning arrives in `reasoning_content`/`reasoning`
              when vLLM runs `--reasoning-parser kolibri1`. Requests run concurrently and the
              server batches them.
transformers  batched local generation, the `generate_bulk.py` path: bf16, left padding,
              `enable_thinking=False`. For gemma-4-31B, which vLLM can't load (bakeoff/README.md).

Budget: `maxTokens × --budget-factor + --reasoning-budget`, or a fixed `--max-tokens`. The app's
`maxTokens` is the tutor's budget in Gemma tokens; a teacher gets headroom and step 3 drops stories
the student couldn't write inside the app's budget.

Resumable: finished ids go to `<out>.done`, and a rerun skips them.

Usage:
    # Kolibri via vLLM, thinking off
    python generate_chat.py --in prompts.jsonl --out kolibri_nothink.jsonl --backend openai \
        --base-url http://127.0.0.1:8000/v1 --model Aleph-Alpha/Kolibri-1 --label kolibri1-nothink \
        --temperature 1.0 --top-p 0.97 --top-k 128 --reasoning-effort none --enable-thinking false
    # gemma-4-31B via transformers
    python generate_chat.py --in prompts.jsonl --out gemma31b.jsonl --backend transformers \
        --model google/gemma-4-31B-it --label gemma4-31b --batch 16 --temperature 0.9 --top-p 0.95
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed


def budget(rec, args):
    if args.max_tokens:
        return args.max_tokens
    base = int(rec.get("maxTokens") or 1024)
    return int(base * args.budget_factor) + args.reasoning_budget


def sampling(args):
    s = {"temperature": args.temperature, "top_p": args.top_p}
    if args.top_k:
        s["top_k"] = args.top_k
    return s


def template_kwargs(args):
    kw = {}
    if args.reasoning_effort:
        kw["reasoning_effort"] = args.reasoning_effort
    if args.enable_thinking is not None:
        kw["enable_thinking"] = args.enable_thinking == "true"
    if args.template_kwargs:
        kw.update(json.loads(args.template_kwargs))
    return kw


# MARK: - openai

def openai_one(rec, args):
    body = {
        "model": args.model,
        "messages": [{"role": "system", "content": rec["system"]},
                     {"role": "user", "content": rec["user"]}],
        "max_tokens": budget(rec, args),
        **sampling(args),
    }
    kw = template_kwargs(args)
    if kw:
        body["chat_template_kwargs"] = kw
    data = json.dumps(body).encode()
    last = None
    for attempt in range(3):
        t0 = time.time()
        try:
            req = urllib.request.Request(args.base_url.rstrip("/") + "/chat/completions", data=data,
                                         headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=args.timeout) as resp:
                out = json.loads(resp.read())
            choice = out["choices"][0]
            msg = choice.get("message") or {}
            usage = out.get("usage") or {}
            reasoning = msg.get("reasoning_content") or msg.get("reasoning") or ""
            return {
                "raw": msg.get("content") or "",
                "reasoning": reasoning,
                "finishReason": choice.get("finish_reason"),
                "endedEarly": choice.get("finish_reason") == "length",
                "tokens": usage.get("completion_tokens"),
                "reasoningTokens": (usage.get("completion_tokens_details") or {}).get("reasoning_tokens"),
                "promptTokens": usage.get("prompt_tokens"),
                "seconds": round(time.time() - t0, 2),
                "error": None,
            }
        except (urllib.error.URLError, TimeoutError, ConnectionError, KeyError, json.JSONDecodeError) as e:
            last = f"{type(e).__name__}: {e}"
            time.sleep(2 * (attempt + 1))
    return {"raw": "", "reasoning": "", "finishReason": None, "endedEarly": True, "tokens": 0,
            "reasoningTokens": None, "promptTokens": None, "seconds": None, "error": last}


def run_openai(todo, args, emit):
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = {pool.submit(openai_one, rec, args): rec for rec in todo}
        for fut in as_completed(futures):
            emit(futures[fut], fut.result())


# MARK: - transformers

def run_transformers(todo, args, emit):
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    print(f"loading {args.model} ...", flush=True)
    t0 = time.time()
    tok = AutoTokenizer.from_pretrained(args.model)
    tok.padding_side = "left"                      # required for correct batched generation
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    model = AutoModelForCausalLM.from_pretrained(args.model, device_map="auto", dtype=torch.bfloat16)
    model.eval()
    if torch.cuda.is_available():
        print(f"loaded in {time.time()-t0:.0f}s, {torch.cuda.memory_allocated()/1e9:.1f} GB", flush=True)

    gen_eos = getattr(model.generation_config, "eos_token_id", None)
    eos_ids = set(gen_eos if isinstance(gen_eos, list) else [gen_eos]) | {tok.eos_token_id}
    eos_ids.discard(None)

    def build(rec):
        msgs = [{"role": "system", "content": rec["system"]}, {"role": "user", "content": rec["user"]}]
        try:
            return tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False,
                                           enable_thinking=False)
        except TypeError:
            return tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False)

    # Similar budgets batch together.
    todo = sorted(todo, key=lambda r: budget(r, args))
    for start in range(0, len(todo), args.batch):
        chunk = todo[start:start + args.batch]
        enc = tok([build(r) for r in chunk], return_tensors="pt", padding=True,
                  truncation=True, max_length=4096).to(model.device)
        max_new = max(budget(r, args) for r in chunk)
        t1 = time.time()
        with torch.no_grad():
            gen = model.generate(**enc, max_new_tokens=max_new, do_sample=True,
                                 pad_token_id=tok.pad_token_id, **sampling(args))
        dt = time.time() - t1
        width = enc["input_ids"].shape[1]
        for row, (rec, seq) in enumerate(zip(chunk, gen)):
            new = seq[width:].tolist()
            stop = next((i for i, t in enumerate(new) if t in eos_ids), None)
            # A row shares the batch's longest budget; cut it to its own, as a server would.
            own = budget(rec, args)
            finished = stop is not None and stop <= own
            used = new[:stop] if finished else new[:own]
            emit(rec, {
                "raw": tok.decode(used, skip_special_tokens=True),
                "reasoning": "",
                "finishReason": "stop" if finished else "length",
                "endedEarly": not finished,
                "tokens": len(used),
                "reasoningTokens": None,
                "promptTokens": int(enc["attention_mask"][row].sum()),
                "seconds": round(dt / len(chunk), 2),
                "error": None,
            })


# MARK: - main

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--backend", choices=["openai", "transformers"], required=True)
    ap.add_argument("--model", required=True, help="served model name, or the HF repo for transformers")
    ap.add_argument("--label", required=True, help="written as `model` on every line (the Lab groups by it)")
    ap.add_argument("--base-url", default="http://127.0.0.1:8000/v1")
    ap.add_argument("--concurrency", type=int, default=32)
    ap.add_argument("--timeout", type=float, default=900)
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--temperature", type=float, default=0.9)
    ap.add_argument("--top-p", type=float, default=0.95)
    ap.add_argument("--top-k", type=int, default=0)
    ap.add_argument("--max-tokens", type=int, default=0, help="fixed budget; overrides the factor")
    ap.add_argument("--budget-factor", type=float, default=2.0)
    ap.add_argument("--reasoning-budget", type=int, default=0)
    ap.add_argument("--reasoning-effort", default=None)
    ap.add_argument("--enable-thinking", choices=["true", "false"], default=None)
    ap.add_argument("--template-kwargs", default=None, help="extra chat_template_kwargs as JSON")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    records = [json.loads(l) for l in open(args.inp) if l.strip()]
    if args.limit:
        records = records[:args.limit]
    done_path = args.out + ".done"
    done = set(l.strip() for l in open(done_path)) if os.path.exists(done_path) else set()
    todo = [r for r in records if str(r["id"]) not in done]
    print(f"{len(todo)} of {len(records)} records to run ({args.backend}, {args.label})", flush=True)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    out_fh, done_fh = open(args.out, "a"), open(done_path, "a")
    meta = {"model": args.label, "modelRepo": args.model, "backend": args.backend,
            "sampling": sampling(args), "templateKwargs": template_kwargs(args) or None}
    state = {"n": 0, "tokens": 0, "errors": 0, "t0": time.time()}

    def emit(rec, result):
        line = {**rec, **meta, **result}
        out_fh.write(json.dumps(line, ensure_ascii=False) + "\n")
        done_fh.write(str(rec["id"]) + "\n")
        out_fh.flush(); done_fh.flush()
        state["n"] += 1
        state["tokens"] += result.get("tokens") or 0
        state["errors"] += result["error"] is not None
        if state["n"] % 10 == 0 or state["n"] == len(todo):
            el = time.time() - state["t0"]
            print(f"[{state['n']}/{len(todo)}] {state['tokens']/el:.0f} tok/s aggregate | "
                  f"{state['errors']} errors | {el/60:.1f} min", flush=True)

    if todo:
        (run_openai if args.backend == "openai" else run_transformers)(todo, args, emit)
    out_fh.close(); done_fh.close()
    print(f"done: {state['n']} lines, {state['errors']} errors -> {args.out}", flush=True)
    return 0 if state["errors"] < max(1, len(todo) // 10) else 1


if __name__ == "__main__":
    sys.exit(main())
