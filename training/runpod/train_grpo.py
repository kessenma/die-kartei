#!/usr/bin/env python3
"""Unsloth GRPO on the German-tutor correction task — REINFORCEMENT_LEARNING.md Part A §6–7.

Run on a RunPod GPU pod (A40 48 GB or A100 80 GB; see runpod/README.md §1–4 for the pod/venv):
    /workspace/venv/bin/pip install unsloth            # inside the --system-site-packages venv
    cd /root/train && python train_grpo.py             # expects train.jsonl + rl_rewards.py +
                                                       # run_baseline_eval.py next to it

Env vars (all optional; defaults are the Part A §7 recipe):
    MODEL_NAME=kessenma/gemma4-e4b-german-v4-fp16   policy init AND the KL reference (Part A §6 B)
    CHAT_TEMPLATE=gemma-4 | native                   same guard as train_gemma4_e4b.py
    POOL=train.jsonl                                 from scripts/build_rl_pool.py mine
    LORA_R=16  LORA_ALPHA=16  LR=5e-6  BETA=0.02
    NUM_GEN=8  BATCH_SIZE=16  GRAD_ACCUM=4           → 64 completions / 8 prompts per optimizer step
    MAX_PROMPT=512  MAX_COMPLETION=96  TEMP=1.0
    EPOCHS=2  MAX_STEPS=0 (0 = use EPOCHS)  SAVE_STEPS=150  WARMUP_RATIO=0.1
    LOSS_TYPE=dapo                                   TRL default; "grpo" / "dr_grpo" also valid
    OUT_PREFIX=gemma4-e4b-german-rl1
    CONTINUOUS_BATCHING=0                            1 → transformers continuous batching (>= 5.8)
    PAD_MULTIPLE=64                                  pad prompts/completions to a multiple → few shapes → few Triton compiles
    GRAD_CKPT=none | unsloth | hf                    gradient checkpointing. Default none: on Gemma 4 E-series
                                                     the "unsloth" recompute path disagrees with the saved
                                                     forward under GRPO (per-layer-embedding tensors, measured
                                                     2026-09-05 smoke #2). 300-token sequences fit an 80 GB card
                                                     without it; on a 48 GB card try hf, then BATCH_SIZE=8.
    SMOKE=0                                          1 → MAX_STEPS=SMOKE_STEPS (default 10), prints every diagnostic
    LOAD_4BIT=0                                      1 → QLoRA on bnb-4bit weights. Default 0 = LoRA on bf16:
                                                     measured 2026-09-05 smoke #3, 4-bit = 173 s/step (bnb dequant
                                                     on every matmul in generation AND training) at only 30 GB
                                                     peak — an 80 GB card has the room for bf16, use it.

Outputs (local container disk — NOT /workspace, see runbook §6.3/§6.5):
    ./<OUT_PREFIX>-lora      LoRA adapters
    ./<OUT_PREFIX>-merged    merged fp16 → scp off the pod → mlx_lm convert

Smoke-run checklist (Part A §7) — all five must be true before the real run:
    1. rendered prompt ends in the model-turn marker with NO thinking channel token
    2. reward components non-degenerate: reward/format_ok ≈ 1, frac_reward_zero_std < 0.7
    3. trainable params ≈ the r=16 LoRA
    4. s/step and peak VRAM printed at the end — size the real run from them
    5. `runpodctl pod list` empty afterwards
"""

import json
import os
import sys
import time

# unsloth must be imported before trl so its patches land
from unsloth import FastModel
from unsloth.chat_templates import get_chat_template

import torch
from datasets import load_dataset
from trl import GRPOConfig, GRPOTrainer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rl_rewards import tutor_reward  # noqa: E402  (imports run_baseline_eval — ship both files)

# ---------------------------------------------------------------- fixed shapes: pad to a multiple of N
# Measured 2026-09-05 (Part B, smoke #6/#7 + the first real-run steps): with zero dynamo recompiles,
# two steps in three still stalled 90–180 s while the inductor cache kept growing — Triton compiling
# kernels for every new (prompt_len, completion_len) the trainer produced. TRL pads prompts (left)
# and completions (right) to the batch max, so every step is a new shape. Rounding every pad up to a
# multiple of PAD_MULTIPLE collapses that to a handful of shapes (completions ≤ 80 → always 128;
# prompts → 192/256/320), each compiled once. Masks are padded with 0, so the loss is unchanged.
# Unsloth's generated trainer imports `pad` by name from trl.trainer.grpo_trainer and calls it at
# run time, so patching the module attribute is enough (verified by reading the generated file).
PAD_MULTIPLE = int(os.environ.get("PAD_MULTIPLE", 64))
if PAD_MULTIPLE > 1:
    import trl.trainer.utils as _tu
    import trl.trainer.grpo_trainer as _tg
    _orig_pad = _tu.pad

    def _pad_to_multiple(tensors, padding_value=0, padding_side="right", pad_to_multiple_of=None):
        return _orig_pad(tensors, padding_value=padding_value, padding_side=padding_side,
                         pad_to_multiple_of=pad_to_multiple_of or PAD_MULTIPLE)

    _tu.pad = _pad_to_multiple
    _tg.pad = _pad_to_multiple
    for _name, _mod in list(sys.modules.items()):
        if _name.endswith("UnslothGRPOTrainer") and hasattr(_mod, "pad"):
            _mod.pad = _pad_to_multiple
    print(f"== pad_to_multiple_of={PAD_MULTIPLE} installed on trl.trainer.utils / grpo_trainer ==")

env = os.environ.get
SMOKE = env("SMOKE", "0") == "1"
MODEL_NAME = env("MODEL_NAME", "kessenma/gemma4-e4b-german-v4-fp16")
CHAT_TEMPLATE = env("CHAT_TEMPLATE", "gemma-4")
POOL = env("POOL", "train.jsonl")
OUT_PREFIX = env("OUT_PREFIX", "gemma4-e4b-german-rl1")
LORA_R = int(env("LORA_R", 16))
LORA_ALPHA = int(env("LORA_ALPHA", LORA_R))
MAX_PROMPT = int(env("MAX_PROMPT", 512))
MAX_COMPLETION = int(env("MAX_COMPLETION", 80))   # valid replies terminate at 15–60 tokens (smoke #3); clipped = malformed anyway
NUM_GEN = int(env("NUM_GEN", 8))
BATCH_SIZE = int(env("BATCH_SIZE", 16))
GRAD_ACCUM = int(env("GRAD_ACCUM", 4))
MAX_STEPS = int(env("SMOKE_STEPS", 10)) if SMOKE else int(env("MAX_STEPS", 0))
LOAD_4BIT = env("LOAD_4BIT", "0") == "1"
GRAD_CKPT = {"none": False, "unsloth": "unsloth", "hf": True}[env("GRAD_CKPT", "none")]

# ---------------------------------------------------------------- guard (same as the SFT script)
_fam = MODEL_NAME.lower()
if CHAT_TEMPLATE == "gemma-4" and not ("gemma-4" in _fam or "gemma4" in _fam):
    raise SystemExit(f"REFUSING: CHAT_TEMPLATE='gemma-4' but MODEL_NAME='{MODEL_NAME}'. "
                     f"Set CHAT_TEMPLATE=native for non-Gemma-4 families (see train_gemma4_e4b.py).")
if BATCH_SIZE % NUM_GEN:
    raise SystemExit(f"BATCH_SIZE ({BATCH_SIZE}) must be a multiple of NUM_GEN ({NUM_GEN})")

# ---------------------------------------------------------------- model
print(f"== loading {MODEL_NAME} ({'bnb-4bit' if LOAD_4BIT else 'bf16'}, fast_inference=False — vLLM cannot load Gemma 4 for RL) ==")
model, tokenizer = FastModel.from_pretrained(
    model_name=MODEL_NAME,
    max_seq_length=MAX_PROMPT + MAX_COMPLETION,
    load_in_4bit=LOAD_4BIT,
    dtype=torch.bfloat16,
    fast_inference=False,
    full_finetuning=False,
)
try:
    model = FastModel.get_peft_model(
        model,
        finetune_vision_layers=False, finetune_language_layers=True,
        finetune_attention_modules=True, finetune_mlp_modules=True,
        r=LORA_R, lora_alpha=LORA_ALPHA, lora_dropout=0, bias="none",
        use_gradient_checkpointing=GRAD_CKPT, random_state=7,
    )
except TypeError:  # text-only architectures (granite) take classic target_modules
    model = FastModel.get_peft_model(
        model, r=LORA_R, lora_alpha=LORA_ALPHA, lora_dropout=0, bias="none",
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
        use_gradient_checkpointing=GRAD_CKPT, random_state=7,
    )
n_train = sum(p.numel() for p in model.parameters() if p.requires_grad)
n_all = sum(p.numel() for p in model.parameters())
print(f"== LoRA r={LORA_R} alpha={LORA_ALPHA}: trainable {n_train:,} of {n_all:,} ({n_train / n_all * 100:.2f}%) ==")
print(f"== gradient checkpointing: {env('GRAD_CKPT', 'none')} ==")

if CHAT_TEMPLATE != "native":
    tokenizer = get_chat_template(tokenizer, chat_template=CHAT_TEMPLATE)

# Thinking must be OFF, exactly as the eval and the app run it (CLAUDE.md lesson 4). TRL renders
# prompts through tokenizer.apply_chat_template; default the kwarg here so every render gets it.
_orig_act = tokenizer.apply_chat_template


def _apply_no_thinking(*a, **k):
    k.setdefault("enable_thinking", False)
    return _orig_act(*a, **k)


tokenizer.apply_chat_template = _apply_no_thinking

# ---------------------------------------------------------------- data
ds = load_dataset("json", data_files={"train": POOL})["train"]
keep = ["prompt", "student", "verdict", "fix", "hint_expected", "phenomenon"]
ds = ds.remove_columns([c for c in ds.column_names if c not in keep])
print(f"== pool: {len(ds)} prompts; columns {ds.column_names} ==")

probe = tokenizer.apply_chat_template(ds[0]["prompt"], tokenize=False, add_generation_prompt=True)
print("--- rendered prompt tail (must end in the model-turn marker, no <|channel>) ---")
print(repr(probe[-160:]))
if "<|channel>" in probe or "<think>" in probe:
    raise SystemExit("thinking channel present in the rendered prompt — fix the template kwarg before training")
# FastModel returns a *processor* for Gemma 4 (multimodal); its __call__ wants text=..., so count tokens
# with the inner tokenizer. (Measured 2026-09-05 smoke #1: tokenizer(probe) -> TypeError in processing_gemma4.)
_tok = getattr(tokenizer, "tokenizer", tokenizer)
plen = len(_tok(probe)["input_ids"])
print(f"prompt tokens for row 0: {plen} (MAX_PROMPT={MAX_PROMPT})")

# ---------------------------------------------------------------- reward sanity on gold, pre-training
_gold = ["OK" if r["verdict"] == "ok" else f"FIX: {r['fix']}\nWHY: gold" for r in ds.select(range(min(8, len(ds))))]
_rw = tutor_reward([[{"role": "assistant", "content": g}] for g in _gold],
                   student=[r["student"] for r in ds.select(range(len(_gold)))],
                   verdict=[r["verdict"] for r in ds.select(range(len(_gold)))],
                   fix=[r["fix"] for r in ds.select(range(len(_gold)))])
print(f"reward on gold answers (expect 1.0 for ok rows, 1.0 for fix rows with the 2-word WHY): {_rw}")

# ---------------------------------------------------------------- config
cfg = dict(
    output_dir="outputs-grpo",
    learning_rate=float(env("LR", 5e-6)),
    beta=float(env("BETA", 0.02)),
    per_device_train_batch_size=BATCH_SIZE,
    gradient_accumulation_steps=GRAD_ACCUM,
    num_generations=NUM_GEN,
    max_prompt_length=MAX_PROMPT,
    max_completion_length=MAX_COMPLETION,
    temperature=float(env("TEMP", 1.0)),
    loss_type=env("LOSS_TYPE", "dapo"),
    scale_rewards="group",
    mask_truncated_completions=True,
    num_train_epochs=float(env("EPOCHS", 2)),
    max_steps=MAX_STEPS if MAX_STEPS else -1,
    warmup_ratio=float(env("WARMUP_RATIO", 0.1)),
    lr_scheduler_type="cosine",
    optim="adamw_8bit",
    weight_decay=0.01,
    max_grad_norm=0.5,
    logging_steps=1 if SMOKE else int(env("LOG_STEPS", 5)),
    save_steps=int(env("SAVE_STEPS", 150)),
    save_total_limit=3,
    log_completions=True,
    num_completions_to_print=4 if SMOKE else 2,
    bf16=torch.cuda.is_bf16_supported(),
    fp16=not torch.cuda.is_bf16_supported(),
    report_to="none",
    seed=7,
)
if env("CONTINUOUS_BATCHING", "0") == "1":
    cfg.update(use_transformers_continuous_batching=True,
               transformers_continuous_batching_config={"use_cuda_graph": False, "max_memory_percent": 0.4})

# older/newer TRL versions differ in accepted keys — drop what this one does not know, loudly
while True:
    try:
        args = GRPOConfig(**cfg)
        break
    except TypeError as e:
        bad = str(e).split("'")[1] if "'" in str(e) else None
        if not bad or bad not in cfg:
            raise
        print(f"!! GRPOConfig does not accept {bad!r} in this TRL — dropped")
        cfg.pop(bad)

# ---- where does a step go? time every generate() call (the only opaque phase of a GRPO step)
_gen_stats = {"calls": 0, "seconds": 0.0, "tokens": 0}
_orig_generate = model.generate


def _timed_generate(*a, **k):
    t = time.time()
    out = _orig_generate(*a, **k)
    dt = time.time() - t
    try:
        n_new = int(out.shape[0] * (out.shape[1] - (a[0].shape[1] if a else k.get("input_ids").shape[1])))
    except Exception:
        n_new = 0
    _gen_stats["calls"] += 1; _gen_stats["seconds"] += dt; _gen_stats["tokens"] += n_new
    print(f"[gen] call {_gen_stats['calls']}: {dt:.1f}s, out shape {tuple(out.shape)}", flush=True)
    return out


model.generate = _timed_generate

from transformers import TrainerCallback


class StepTimer(TrainerCallback):
    """Per-step wall-clock, so compile warm-up steps are distinguishable from steady state."""
    def __init__(self):
        self.t = None
        self.times = []

    def on_step_end(self, args, state, control, **kwargs):
        now = time.time()
        if self.t is not None:
            self.times.append(now - self.t)
            print(f"[step {state.global_step}] {now - self.t:.1f}s  (gen so far {_gen_stats['seconds']:.0f}s in {_gen_stats['calls']} calls)", flush=True)
        self.t = now


_timer = StepTimer()

trainer = GRPOTrainer(
    model=model,
    processing_class=tokenizer,
    reward_funcs=[tutor_reward],
    args=args,
    train_dataset=ds,
    callbacks=[_timer],
)

if PAD_MULTIPLE > 1:
    for _name, _mod in list(sys.modules.items()):
        if _name.endswith("UnslothGRPOTrainer") and getattr(_mod, "pad", None) is not _pad_to_multiple:
            _mod.pad = _pad_to_multiple
            print(f"== pad patched into {_name} ==")
print(f"== training: {len(ds)} prompts, {NUM_GEN} gens, {BATCH_SIZE}x{GRAD_ACCUM} = "
      f"{BATCH_SIZE * GRAD_ACCUM} completions / {BATCH_SIZE * GRAD_ACCUM // NUM_GEN} prompts per step, "
      f"{'MAX_STEPS=' + str(MAX_STEPS) if MAX_STEPS else 'EPOCHS=' + env('EPOCHS', '2')} ==")
torch.cuda.reset_peak_memory_stats()
t0 = time.time()
stats = trainer.train()
el = time.time() - t0
steps = max(1, int(stats.metrics.get("train_steps", 0) or trainer.state.global_step or 1))
print(stats)
print(f"== {steps} steps in {el / 60:.1f} min = {el / steps:.1f} s/step; "
      f"peak VRAM {torch.cuda.max_memory_allocated() / 2**30:.1f} GB ==")
if len(_timer.times) > 3:
    tail = _timer.times[3:]
    print(f"== steady-state (steps 5+): {sum(tail) / len(tail):.1f} s/step over {len(tail)} steps; first 3 steps {[round(t) for t in _timer.times[:3]]} ==")
print(f"== generation: {_gen_stats['calls']} calls, {_gen_stats['seconds']:.0f}s total = {_gen_stats['seconds'] / max(1, el) * 100:.0f}% of wall-clock ==")

# the reward-hacking watch (Part A §3): last logged values of the component metrics
tail = [h for h in trainer.state.log_history if "reward" in json.dumps(h)][-3:]
for h in tail:
    print({k: (round(v, 4) if isinstance(v, float) else v) for k, v in h.items()
           if k.startswith(("reward", "rewards", "frac_reward", "completions", "kl", "loss", "step"))})

print("== saving ==")
model.save_pretrained(f"{OUT_PREFIX}-lora")
tokenizer.save_pretrained(f"{OUT_PREFIX}-lora")
if not SMOKE:
    model.save_pretrained_merged(f"{OUT_PREFIX}-merged", tokenizer, save_method="merged_16bit")
    print(f"merged fp16 saved to ./{OUT_PREFIX}-merged — scp it off, do NOT push_to_hub_merged (runbook §6.5)")
print("DONE")
