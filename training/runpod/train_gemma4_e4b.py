#!/usr/bin/env python3
"""Unsloth QLoRA fine-tune of Gemma 4 E4B on the German grammar dataset.

Run on a RunPod GPU pod (>=16 GB VRAM, 24 GB recommended, >=60 GB disk):
    pip install unsloth
    python train_gemma4_e4b.py

Env vars (all optional):
    EPOCHS=2                 number of epochs
    MAX_SEQ_LEN=2048         max sequence length
    HF_TOKEN=hf_...          HuggingFace write token — enables push
    HF_REPO=you/gemma4-e4b-german-tutor   private repo to push merged model to
    INSTRUCTION_PART / RESPONSE_PART      override chat-template turn markers
                             (only needed if auto-detection fails)

Outputs:
    ./gemma4-e4b-german-lora     LoRA adapters only (small)
    ./gemma4-e4b-german-merged   merged fp16 model (~16 GB) -> convert with mlx_lm
"""

import os

from unsloth import FastModel
from unsloth.chat_templates import get_chat_template, train_on_responses_only
from datasets import load_dataset
from trl import SFTConfig, SFTTrainer

# 1024 is enough for the v2 corpus (max observed 1000 tokens) and halves the attention cost
# versus the v1 default of 2048. Raise it if a future dataset has longer rows.
MAX_SEQ_LEN = int(os.environ.get("MAX_SEQ_LEN", 1024))

print("== loading base model (4-bit) ==")
MODEL_NAME = os.environ.get("MODEL_NAME", "unsloth/gemma-4-E4B-it")
CHAT_TEMPLATE = os.environ.get("CHAT_TEMPLATE", "gemma-4")
OUT_PREFIX = os.environ.get("OUT_PREFIX", "gemma4-e4b-german")

model, tokenizer = FastModel.from_pretrained(
    model_name=MODEL_NAME,
    max_seq_length=MAX_SEQ_LEN,
    load_in_4bit=True,
    full_finetuning=False,
)

try:
    model = FastModel.get_peft_model(
        model,
        finetune_vision_layers=False,     # text-only fine-tune (Unsloth-recommended)
        finetune_language_layers=True,
        finetune_attention_modules=True,
        finetune_mlp_modules=True,
        r=8, lora_alpha=16, lora_dropout=0, bias="none",
        use_gradient_checkpointing="unsloth", random_state=7,
    )
except TypeError:  # text-only architectures take classic target_modules
    model = FastModel.get_peft_model(
        model,
        r=8, lora_alpha=16, lora_dropout=0, bias="none",
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
        use_gradient_checkpointing="unsloth", random_state=7,
    )

if CHAT_TEMPLATE != "native":
    tokenizer = get_chat_template(tokenizer, chat_template=CHAT_TEMPLATE)

print("== preparing dataset ==")
ds = load_dataset("json", data_files={"train": "train.jsonl", "val": "val.jsonl"})


def render(example):
    msgs = example["messages"]
    try:
        text = tokenizer.apply_chat_template(msgs, tokenize=False, add_generation_prompt=False)
    except Exception:
        # template without system-role support: merge system into first user turn
        if msgs and msgs[0]["role"] == "system":
            merged = [{"role": "user", "content": msgs[0]["content"] + "\n\n" + msgs[1]["content"]}] + msgs[2:]
            text = tokenizer.apply_chat_template(merged, tokenize=False, add_generation_prompt=False)
        else:
            raise
    return {"text": text}


# Drop every source column, not just "messages" — train.jsonl also carries a `meta` block
# (task/phenomenon/level/formality/template_family) from pack_dataset.py, and any column that
# survives here is handed to the trainer as a stray feature.
ds = ds.map(render, remove_columns=ds["train"].column_names)
print(ds)
print("--- sample rendered example ---")
print(ds["train"][0]["text"][:600])

# --- find the turn markers for response-only loss masking ---
probe = tokenizer.apply_chat_template(
    [{"role": "user", "content": "PROBE_USER"}, {"role": "assistant", "content": "PROBE_MODEL"}],
    tokenize=False, add_generation_prompt=False,
)
CANDIDATES = [
    ("<start_of_turn>user\n", "<start_of_turn>model\n"),   # gemma <= 3n
    ("<|turn>user\n", "<|turn>model\n"),                    # gemma 4 (verified)
    ("<|turn|>user\n", "<|turn|>model\n"),
    ("<|im_start|>user\n", "<|im_start|>assistant\n"),      # ChatML (qwen)
]
instruction_part = os.environ.get("INSTRUCTION_PART")
response_part = os.environ.get("RESPONSE_PART")
if not (instruction_part and response_part):
    for ins, res in CANDIDATES:
        if ins in probe and res in probe:
            instruction_part, response_part = ins, res
            break
if not (instruction_part and response_part):
    print("!! could not auto-detect turn markers. Rendered probe follows — set INSTRUCTION_PART/RESPONSE_PART env vars accordingly:")
    print(repr(probe))
    raise SystemExit(1)
print(f"turn markers: {instruction_part!r} / {response_part!r}")

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=ds["train"],
    eval_dataset=ds["val"],
    args=SFTConfig(
        dataset_text_field="text",
        max_seq_length=MAX_SEQ_LEN,
        # v2 defaults keep the EFFECTIVE batch at 8 (same as v1) but do it in one forward/backward
        # instead of four. Safe here because the v2 corpus is short: p50 284 tokens, p99 840, max
        # 1000 — so MAX_SEQ_LEN=1024 truncates nothing and 8x1024 fits comfortably in 24 GB.
        # Override with BATCH_SIZE / GRAD_ACCUM if VRAM complains.
        per_device_train_batch_size=int(os.environ.get("BATCH_SIZE", 8)),
        gradient_accumulation_steps=int(os.environ.get("GRAD_ACCUM", 1)),
        warmup_steps=int(os.environ.get("WARMUP", 20)),
        num_train_epochs=float(os.environ.get("EPOCHS", 1)),
        learning_rate=float(os.environ.get("LR", 2e-4)),
        logging_steps=25,
        eval_strategy="steps",
        eval_steps=int(os.environ.get("EVAL_STEPS", 250)),
        per_device_eval_batch_size=int(os.environ.get("BATCH_SIZE", 8)),
        optim="adamw_8bit",
        weight_decay=0.01,
        lr_scheduler_type="linear",
        seed=7,
        output_dir="outputs",
        report_to="none",
    ),
)
trainer = train_on_responses_only(trainer, instruction_part=instruction_part, response_part=response_part)

print("== training ==")
stats = trainer.train()
print(stats)

print("== saving ==")
model.save_pretrained(f"{OUT_PREFIX}-lora")
tokenizer.save_pretrained(f"{OUT_PREFIX}-lora")
model.save_pretrained_merged(f"{OUT_PREFIX}-merged", tokenizer, save_method="merged_16bit")
print(f"merged fp16 model saved to ./{OUT_PREFIX}-merged")

hf_repo = os.environ.get("HF_REPO")
if hf_repo and os.environ.get("HF_TOKEN"):
    print(f"== pushing merged model to {hf_repo} (private) ==")
    model.push_to_hub_merged(hf_repo, tokenizer, save_method="merged_16bit",
                             token=os.environ["HF_TOKEN"], private=True)
    print("push complete")
else:
    print("HF_REPO/HF_TOKEN not set — skipping hub push (download ./gemma4-e4b-german-merged manually)")
