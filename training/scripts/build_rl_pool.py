#!/usr/bin/env python3
"""Build the GRPO prompt pool — REINFORCEMENT_LEARNING.md Part A §4.

Two stages, both from training/:

  build   raw validated correction rows → data/rl_pool_v1/candidates.jsonl
          * sources: the 31B bulk run, the v1-era Sonnet rows, the 26B salvage (vmp/dawo only),
            plus data/rl_pool_v1/hard_negatives.jsonl if present (Sonnet-written OK traps)
          * prompt rendered with scripts/app_prompts.py so it is byte-identical to the app's
            (strictness sampled 60/20/20 like pack_dataset.py; tellMe style — no HINT line in v1)
          * exact-overlap guard against every data/eval/*.json input (v3 included); the v3 suite
            was itself built to be ≥ Jaccard-0.6 away from every corpus sentence, so exact is
            enough here. The packed-v4 val split is deliberately NOT excluded (see build())
          * balanced 50/50 ok/fix, per-phenomenon cap, deterministic seed

  mine    candidates → data/rl_pool_v1/{train.jsonl, meta.json}
          * the current policy (default: models/gemma4-e4b-german-v4-4bit, MLX) samples K
            completions per prompt at temperature T; each is scored with rl_rewards.explain
          * keep every prompt the model gets wrong (0/K) or is unsure about (1..K-1 of K) —
            those are the groups with reward variance, i.e. the ones GRPO learns from — plus an
            `easy_keep` fraction of the 4/4 prompts so the run does not forget them
          * writes the DPO fallback for free: chosen = gold, rejected = the worst sample

Output row shape (TRL conversational GRPO + the reward's kwargs):
  {"prompt": [{"role":"system",...},{"role":"user",...}],
   "student": str, "verdict": "ok"|"fix", "fix": str|null, "hint_expected": false,
   "phenomenon": str, "source": str, "mined": {"correct": k, "of": K, "mean_reward": float}}

Usage:
  .venv/bin/python scripts/build_rl_pool.py build [--cap 400] [--seed 7]
  .venv/bin/python scripts/build_rl_pool.py mine  [--model models/gemma4-e4b-german-v4-4bit]
                                                  [--k 4] [--temp 0.8] [--batch 24] [--limit N]
"""

from __future__ import annotations

import argparse
import glob
import json
import random
import re
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POOL = ROOT / "data" / "rl_pool_v1"
sys.path.insert(0, str(ROOT / "scripts"))

from app_prompts import correction_system, correction_user  # noqa: E402
from rl_rewards import explain  # noqa: E402

SOURCES = [
    ("gemma31b", "data/generated_gemma31b/bulk_live.valid.jsonl", None),
    ("sonnet_v1", "data/generated/*.valid.jsonl", None),
    ("gemma26b_salvage", "data/salvage_gemma26b/vmp_dawo.valid.jsonl", {"vmp", "dawo"}),
    ("hard_negatives", "data/rl_pool_v1/hard_negatives.jsonl", None),
]
STRICTNESS = (["balanced", "gentle", "strict"], [60, 20, 20])


def norm(s: str) -> str:
    return re.sub(r"[^a-zäöüß ]", "", (s or "").lower()).strip()


def eval_inputs() -> set[str]:
    out = set()
    for f in glob.glob(str(ROOT / "data" / "eval" / "*.json")):
        try:
            d = json.loads(Path(f).read_text())
        except Exception:
            continue
        for it in d.get("items", []):
            if it.get("input"):
                out.add(norm(it["input"]))
            for turn in it.get("history", []) or []:
                if isinstance(turn, dict) and turn.get("content"):
                    out.add(norm(turn["content"]))
    return out


def val_students() -> set[str]:
    out = set()
    p = ROOT / "data" / "packed-v4" / "val.jsonl"
    if not p.exists():
        return out
    for line in open(p, encoding="utf-8"):
        d = json.loads(line)
        if d.get("meta", {}).get("task") == "correction":
            m = re.search(r'(?:The student (?:said|replied)): "(.+?)"\n', d["messages"][1]["content"], re.S)
            if m:
                out.add(norm(m.group(1)))
    return out


# --------------------------------------------------------------------------- build

def build(args) -> None:
    rng = random.Random(args.seed)
    # NOT the packed-v4 val split: pack_dataset splits by template family, so whole phenomena
    # (all 181 k2 and all 130 adjend fix rows) live in val. RL never reads eval_loss, so there is
    # nothing to protect there; the eval suites are the only held-out set that matters.
    banned = eval_inputs()
    rows, seen = [], set()
    stats = Counter()
    for name, pattern, phen_filter in SOURCES:
        for f in sorted(glob.glob(str(ROOT / pattern))):
            for line in open(f, encoding="utf-8"):
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if d.get("task") != "correction" or not d.get("student"):
                    continue
                phen = d.get("phenomenon")
                if phen_filter and phen not in phen_filter:
                    continue
                verdict = d.get("verdict")
                if verdict not in ("ok", "fix"):
                    continue
                if verdict == "fix" and (not d.get("fix") or norm(d["fix"]) == norm(d["student"])):
                    stats["dropped_noop"] += 1
                    continue
                key = (norm(d["student"]), norm(d.get("fix") or ""))
                if key in seen:
                    stats["dropped_dup"] += 1
                    continue
                if norm(d["student"]) in banned:
                    stats["dropped_eval_or_val"] += 1
                    continue
                seen.add(key)
                rows.append({"source": name, "phenomenon": phen or "verdict", "level": d.get("level") or "B1",
                             "formality": d.get("formality") or "du", "partner": d.get("partner"),
                             "student": d["student"], "verdict": verdict,
                             "fix": d.get("fix") if verdict == "fix" else None})
    stats["candidates_raw"] = len(rows)

    # per-phenomenon cap, balanced 50/50 inside each phenomenon where possible
    by = defaultdict(lambda: {"ok": [], "fix": []})
    for r in rows:
        by[r["phenomenon"]][r["verdict"]].append(r)
    kept = []
    for phen, g in sorted(by.items()):
        rng.shuffle(g["ok"]); rng.shuffle(g["fix"])
        half = args.cap // 2
        n_fix = min(len(g["fix"]), half)
        n_ok = min(len(g["ok"]), half)
        # if one side is short, let the other fill up to the cap but never past 65/35
        if n_fix < half:
            n_ok = min(len(g["ok"]), int(min(args.cap - n_fix, n_fix * 65 / 35 if n_fix else half)))
        if n_ok < half:
            n_fix = min(len(g["fix"]), int(min(args.cap - n_ok, n_ok * 65 / 35 if n_ok else half)))
        kept += g["fix"][:n_fix] + g["ok"][:n_ok]
        stats[f"{phen}:fix"] = n_fix
        stats[f"{phen}:ok"] = n_ok
    rng.shuffle(kept)

    for r in kept:
        strictness = rng.choices(*STRICTNESS)[0]
        sys_p = correction_system({"level": r["level"], "formality": r["formality"],
                                   "strictness": strictness, "feedback_style": "tellMe"})
        r["prompt"] = [{"role": "system", "content": sys_p},
                       {"role": "user", "content": correction_user(r.get("partner"), r["student"])}]
        r["hint_expected"] = False
        r["strictness"] = strictness
        for k in ("level", "formality", "partner"):
            r.pop(k, None)

    POOL.mkdir(parents=True, exist_ok=True)
    out = POOL / "candidates.jsonl"
    with open(out, "w", encoding="utf-8") as fh:
        for r in kept:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    n_ok = sum(r["verdict"] == "ok" for r in kept)
    print(f"candidates: {len(kept)} ({n_ok} ok / {len(kept) - n_ok} fix) from {stats['candidates_raw']} raw rows")
    print(f"dropped: no-op {stats['dropped_noop']}, dup {stats['dropped_dup']}, eval/val overlap {stats['dropped_eval_or_val']}")
    print("per phenomenon (fix/ok):", {p: f"{stats[p + ':fix']}/{stats[p + ':ok']}" for p in sorted(by)})
    print(f"wrote {out.relative_to(ROOT)}")


# --------------------------------------------------------------------------- mine

def mine(args) -> None:
    from transformers import AutoTokenizer  # mlx-lm 0.31 + transformers 5 registration quirk (see run_baseline_eval)
    _orig = AutoTokenizer.register
    AutoTokenizer.register = lambda *a, **k: (lambda: None)() if _orig is None else _safe(_orig, *a, **k)
    from mlx_lm import batch_generate, load
    from mlx_lm.sample_utils import make_sampler

    cands = [json.loads(l) for l in open(POOL / "candidates.jsonl", encoding="utf-8")]
    if args.limit:
        cands = cands[: args.limit]
    print(f"mining {len(cands)} candidates with {args.model}: K={args.k} temp={args.temp} batch={args.batch}")
    model, tokenizer = load(args.model)

    def render(prompt_msgs):
        try:
            return tokenizer.apply_chat_template(prompt_msgs, add_generation_prompt=True, enable_thinking=False)
        except Exception:
            merged = [{"role": "user", "content": prompt_msgs[0]["content"] + "\n\n" + prompt_msgs[1]["content"]}]
            return tokenizer.apply_chat_template(merged, add_generation_prompt=True, enable_thinking=False)

    sampler = make_sampler(temp=args.temp)
    t0 = time.time()
    results = []
    for start in range(0, len(cands), args.batch):
        chunk = cands[start:start + args.batch]
        prompts = []
        for r in chunk:
            ids = render(r["prompt"])
            prompts += [ids] * args.k
        resp = batch_generate(model, tokenizer, prompts, max_tokens=args.max_tokens, sampler=sampler, verbose=False)
        texts = resp.texts
        for i, r in enumerate(chunk):
            samples = texts[i * args.k:(i + 1) * args.k]
            scored = [explain(s, r["student"], r["verdict"], r["fix"]) for s in samples]
            correct = sum(1 for e in scored if e["kind"] != "malformed" and (
                (r["verdict"] == "ok" and e["guarded_ok"]) or (r["verdict"] == "fix" and e["guarded_ok"] is False)))
            worst = min(range(args.k), key=lambda j: scored[j]["reward"])
            r["mined"] = {"correct": correct, "of": args.k,
                          "mean_reward": round(sum(e["reward"] for e in scored) / args.k, 3),
                          "samples": samples, "rewards": [round(e["reward"], 3) for e in scored],
                          "rejected": samples[worst]}
            results.append(r)
        done = start + len(chunk)
        el = time.time() - t0
        print(f"  [{done}/{len(cands)}] {el / 60:.1f} min, {done / el * 60:.0f} prompts/min, eta {(len(cands) - done) / (done / el) / 60:.0f} min", flush=True)

    rng = random.Random(args.seed)
    buckets = {"wrong": [], "uncertain": [], "easy": []}
    for r in results:
        c = r["mined"]["correct"]
        buckets["wrong" if c == 0 else "easy" if c == args.k else "uncertain"].append(r)
    easy_kept = [r for r in buckets["easy"] if rng.random() < args.easy_keep]
    pool = buckets["wrong"] + buckets["uncertain"] + easy_kept
    rng.shuffle(pool)

    POOL.mkdir(parents=True, exist_ok=True)
    with open(POOL / "train.jsonl", "w", encoding="utf-8") as fh:
        for r in pool:
            row = {k: v for k, v in r.items() if k != "mined"}
            row["mined"] = {k: v for k, v in r["mined"].items() if k not in ("samples", "rewards", "rejected")}
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")
    with open(POOL / "dpo_pairs.jsonl", "w", encoding="utf-8") as fh:  # the fallback, free
        for r in buckets["wrong"] + buckets["uncertain"]:
            chosen = "OK" if r["verdict"] == "ok" else f"FIX: {r['fix']}\nWHY: (see gold)"
            fh.write(json.dumps({"prompt": r["prompt"], "chosen": chosen, "rejected": r["mined"]["rejected"]},
                                ensure_ascii=False) + "\n")
    with open(POOL / "mined_full.jsonl", "w", encoding="utf-8") as fh:  # every sample, for audits
        for r in results:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")

    n_ok = sum(r["verdict"] == "ok" for r in pool)
    zero_std = sum(1 for r in results if r["mined"]["correct"] in (0, args.k)) / max(1, len(results))
    by_phen = Counter(r["phenomenon"] for r in pool)
    meta = {
        "model": args.model, "k": args.k, "temp": args.temp, "max_tokens": args.max_tokens,
        "candidates": len(results), "wrong": len(buckets["wrong"]), "uncertain": len(buckets["uncertain"]),
        "easy": len(buckets["easy"]), "easy_kept": len(easy_kept), "easy_keep_frac": args.easy_keep,
        "pool": len(pool), "pool_ok": n_ok, "pool_fix": len(pool) - n_ok,
        "candidate_accuracy": round(sum(r["mined"]["correct"] for r in results) / (args.k * max(1, len(results))), 4),
        "frac_zero_std_on_candidates": round(zero_std, 3),
        "frac_zero_std_on_pool_est": round(len(buckets["wrong"] + easy_kept) / max(1, len(pool)), 3),
        "per_phenomenon": dict(sorted(by_phen.items())),
        "minutes": round((time.time() - t0) / 60, 1),
    }
    (POOL / "meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False))
    print(json.dumps(meta, indent=2, ensure_ascii=False))


def _safe(orig, *a, **k):
    try:
        return orig(*a, **k)
    except Exception:
        return None


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="stage", required=True)
    b = sub.add_parser("build")
    b.add_argument("--cap", type=int, default=400, help="max rows per phenomenon (split ok/fix)")
    b.add_argument("--seed", type=int, default=7)
    m = sub.add_parser("mine")
    m.add_argument("--model", default="models/gemma4-e4b-german-v4-4bit")
    m.add_argument("--k", type=int, default=4)
    m.add_argument("--temp", type=float, default=0.8)
    m.add_argument("--batch", type=int, default=24, help="prompts per batch (× k completions)")
    m.add_argument("--max-tokens", type=int, default=80)
    m.add_argument("--easy-keep", type=float, default=0.2)
    m.add_argument("--limit", type=int, default=0)
    m.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    build(args) if args.stage == "build" else mine(args)


if __name__ == "__main__":
    main()
