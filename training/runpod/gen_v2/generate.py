#!/usr/bin/env python3
"""Phase 1 teacher generation — runs ON the RunPod pod, offline-batched through vLLM.

Reads the manifest built by `scripts/build_gen_jobs.py`, asks the teacher for each job, parses the
JSONL it returns, and writes candidate rows that `scripts/validate_data.py` can gate locally.

Why offline batching and not an HTTP server: vLLM's `LLM.generate` schedules the whole batch itself
and keeps the GPU saturated, and a multi-hour run over the public internet is a fragility we don't
need. Everything lands on pod disk and gets pulled down at the end.

**Resumable.** Completed job_ids are appended to `<out>.done`; a rerun skips them. A pod that dies
at hour 3 costs you hour 3, not the run. This matters more than it sounds — community-cloud pods
are interruptible.

Usage on the pod:
    pip install vllm
    python generate.py --jobs jobs.jsonl --out candidates.jsonl
    python generate.py --jobs jobs.jsonl --out candidates.jsonl --limit 40   # smoke test first
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from collections import Counter
from pathlib import Path

# bf16, 51.6 GB — needs an 80 GB card. There is NO w4a16 build for 26B-A4B (checked 2026-07-28);
# the 48 GB-card alternative is the dense google/gemma-4-31B-it-qat-w4a16-ct, which is slower.
DEFAULT_MODEL = "google/gemma-4-26B-A4B-it"

# Per-slice output budget. A flat 1600 was the single biggest yield problem in the 2026-07-28
# smoke test: yield tracked output length almost perfectly — flashcards 100%, correction 88%,
# recovery 62%, conversation 38%, native_instruction 33% — because long generations were being
# truncated mid-JSON and the trailing objects never parsed. These are sized from the measured
# output lengths with ~60% headroom.
SLICE_MAX_TOKENS = {
    "flashcards": 2200,
    "correction": 2400,
    "recovery": 2600,
    "conversation": 4000,
    "native_instruction": 3600,
}
DEFAULT_MAX_TOKENS = 2400


# The teacher duplicates a key when emitting long repetitive JSON:
#     {"role":"assistant","content","content":"Einen neuen Schrank ..."}
#                          ^^^^^^^^^^^^^^^^^^ bare string where a value belongs
# One occurrence invalidates the whole dialogue object, and it hit 2 of 4 conversation jobs in
# the 2026-07-28 smoke run — the single biggest cause of that slice's 33% yield. The pattern is
# unambiguous (same key repeated, comma between, colon after the second), so repairing it is safe:
# there is no valid JSON in which `"x","x":` is correct.
# The first occurrence must be in KEY position — preceded by `{` or `,`. Without that anchor the
# pattern also matches a VALUE followed by an identically-named key, which is extremely common here:
#
#     "verdict":"fix","fix":"Er hat lange mit seinem Bruder telefoniert."
#                ^^^^^ ^^^^^ value, then the key of the same name
#
# The unanchored version rewrote that to `"verdict":"fix":"Er hat …"` — invalid JSON — and so
# destroyed EVERY correction row with verdict "fix" while leaving `verdict":"ok","fix":null`
# untouched. That produced a 48k-item corpus with 0% corrections, which the validator happily
# passed because each surviving row was well-formed. Anchoring is what makes the repair safe.
_DUP_KEY_RE = re.compile(r'([,{])\s*"(\w+)"\s*,\s*"\2"\s*:')


def repair_json(text: str) -> str:
    return _DUP_KEY_RE.sub(r'\1"\2":', text)


def parse_jsonl_block(text: str) -> list:
    """Pull JSON objects out of a teacher response.

    Teachers wrap output in ```json fences, prepend "Hier sind die Beispiele:", or emit one
    pretty-printed object per block despite being asked for JSONL. Handle all three rather than
    discarding otherwise-good generations: at 40k items a 10% parse loss is 4k items.
    """
    text = re.sub(r"^```(?:json|jsonl)?\s*|\s*```$", "", text.strip(), flags=re.M)
    text = repair_json(text)
    out = []
    # fast path: one object per line
    for line in text.splitlines():
        line = line.strip().rstrip(",")
        if line.startswith("{") and line.endswith("}"):
            try:
                out.append(json.loads(line))
                continue
            except json.JSONDecodeError:
                pass
    if out:
        return out
    # slow path: brace-matched scan, for pretty-printed or concatenated objects
    depth, start, in_str, esc = 0, None, False, False
    for i, ch in enumerate(text):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                try:
                    out.append(json.loads(text[start:i + 1]))
                except json.JSONDecodeError:
                    pass
                start = None
    return out


def attach(row: dict, job: dict) -> dict | None:
    """Stamp job provenance onto a generated row, and drop rows of the wrong shape early."""
    slice_ = job["slice"]
    task = row.get("task")
    if slice_ == "correction" and task != "correction":
        return None
    if slice_ == "conversation" and task != "conversation":
        return None
    if slice_ == "flashcards" and task != "flashcards":
        return None
    if slice_ == "recovery" and task not in ("correction", "conversation"):
        return None
    if slice_ == "native_instruction" and task != "native_instruction":
        return None

    # The MANIFEST is authoritative for these, not the teacher. Using setdefault here let the
    # teacher's own values win, and it rewrote `"phenomenon":"verdict"` as `"none"` on every
    # verdict job (understandably — that job's prompt describes the type as "KEIN Fehler"),
    # which then failed the validator's phenomenon whitelist. 16 of 156 smoke items died on it.
    if job.get("level"):
        row["level"] = job["level"]
    if job.get("formality"):
        row["formality"] = job["formality"]
    if slice_ == "correction":
        # the teacher regularly omits meta even when it is in the schema — restore it, since the
        # validator's structural checks are driven by meta.verb / meta.prep
        if not row.get("meta"):
            row["meta"] = dict(job.get("meta") or {})
        if job.get("phenomenon"):
            row["phenomenon"] = job["phenomenon"]
    if task == "conversation":
        # validate_conversation requires the dialogue to start AND end on the assistant. The
        # teacher ignores the requested odd turn count and overwhelmingly emits even ones (12 is
        # its favourite), so the dialogue ends on the learner and the whole thing is rejected —
        # 11 of 20 remaining rejects in the 2026-07-28 smoke run. Trimming is lossless and
        # deterministic; prompting for odd counts demonstrably is not.
        msgs = row.get("messages")
        if isinstance(msgs, list) and msgs:
            while msgs and msgs[0].get("role") != "assistant":
                msgs.pop(0)
            while msgs and msgs[-1].get("role") != "assistant":
                msgs.pop()
            row["messages"] = msgs
    if slice_ == "conversation" and job.get("role_scenario"):
        row.setdefault("role_scenario", job["role_scenario"])
    if job.get("focus_areas"):
        row.setdefault("focus_areas", job["focus_areas"])
    row["_gen"] = {"job_id": job["job_id"], "slice": slice_}
    return row


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--jobs", default="jobs.jsonl")
    p.add_argument("--out", default="candidates.jsonl")
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--limit", type=int, default=0, help="only run the first N jobs (smoke test)")
    p.add_argument("--max-tokens", type=int, default=0,
                   help="override the per-slice budget below; 0 = use per-slice")
    p.add_argument("--temp", type=float, default=0.9,
                   help="high on purpose: this is diversity generation, not evaluation")
    p.add_argument("--top-p", type=float, default=0.95)
    p.add_argument("--max-model-len", type=int, default=4096)
    p.add_argument("--gpu-mem-util", type=float, default=0.92)
    p.add_argument("--chunk", type=int, default=512, help="jobs per flush to disk")
    args = p.parse_args()

    jobs = [json.loads(l) for l in open(args.jobs, encoding="utf-8")]
    if args.limit:
        jobs = jobs[: args.limit]

    done_path = Path(args.out + ".done")
    done = set(done_path.read_text().split()) if done_path.exists() else set()
    if done:
        jobs = [j for j in jobs if j["job_id"] not in done]
        print(f"resuming: {len(done)} jobs already done, {len(jobs)} remain")
    if not jobs:
        print("nothing to do")
        return

    from vllm import LLM, SamplingParams
    from transformers import AutoTokenizer

    print(f"loading {args.model} ...")
    tok = AutoTokenizer.from_pretrained(args.model)
    llm = LLM(model=args.model, max_model_len=args.max_model_len,
              gpu_memory_utilization=args.gpu_mem_util, trust_remote_code=True)

    def budget(slice_: str) -> int:
        return args.max_tokens or SLICE_MAX_TOKENS.get(slice_, DEFAULT_MAX_TOKENS)

    out_f = open(args.out, "a", encoding="utf-8")
    done_f = open(done_path, "a", encoding="utf-8")
    stats = Counter()
    t0 = time.time()

    for start in range(0, len(jobs), args.chunk):
        batch = jobs[start:start + args.chunk]
        prompts = [
            tok.apply_chat_template(
                [{"role": "system", "content": j["system"]},
                 {"role": "user", "content": j["user"]}],
                tokenize=False, add_generation_prompt=True)
            for j in batch
        ]
        # One SamplingParams per prompt so each slice gets its own output budget.
        sps = [SamplingParams(temperature=args.temp, top_p=args.top_p,
                              max_tokens=budget(j["slice"])) for j in batch]
        outs = llm.generate(prompts, sps)
        for job, o in zip(batch, outs):
            gen = o.outputs[0]
            rows = parse_jsonl_block(gen.text)
            # A response that stopped on the length cap almost certainly lost its trailing object.
            # Count it: a rising truncation rate is the early warning that a slice's budget is too
            # small, and it is invisible in the yield number alone.
            if getattr(gen, "finish_reason", None) == "length":
                stats["truncated"] += 1
                stats[f"truncated_{job['slice']}"] += 1
            kept = 0
            for r in rows:
                if not isinstance(r, dict):
                    continue
                a = attach(r, job)
                if a is None:
                    stats["wrong_shape"] += 1
                    continue
                out_f.write(json.dumps(a, ensure_ascii=False) + "\n")
                kept += 1
            stats[f"items_{job['slice']}"] += kept
            stats["items"] += kept
            stats["jobs"] += 1
            if kept == 0:
                stats["empty_jobs"] += 1
            done_f.write(job["job_id"] + "\n")
        out_f.flush()
        done_f.flush()
        el = time.time() - t0
        pct = (start + len(batch)) / len(jobs)
        eta = el / max(pct, 1e-9) - el
        print(f"[{start + len(batch)}/{len(jobs)} jobs] items={stats['items']} "
              f"empty={stats['empty_jobs']} trunc={stats['truncated']} "
              f"wrong_shape={stats['wrong_shape']} "
              f"elapsed={el/60:.1f}m eta={eta/60:.1f}m", flush=True)

    out_f.close()
    done_f.close()
    print("\n=== generation summary ===")
    for k, v in sorted(stats.items()):
        print(f"  {k}: {v}")
    if stats["jobs"]:
        print(f"  yield: {stats['items'] / stats['jobs']:.2f} items/job")
        empty_rate = stats["empty_jobs"] / stats["jobs"]
        print(f"  empty-job rate: {empty_rate:.1%}")
        if empty_rate > 0.10:
            print("  ⚠️  >10% of jobs produced nothing — check the parse path before a full run")
    print(f"\ncandidates: {args.out}")
    print("Next, LOCALLY:  .venv/bin/python scripts/validate_data.py <candidates.jsonl> "
          "--out-dir data/generated")


if __name__ == "__main__":
    sys.exit(main())
