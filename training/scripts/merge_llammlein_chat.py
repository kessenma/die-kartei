#!/usr/bin/env python3
"""Merge a LLäMmlein chat LoRA into its base and write a plain HF model MLX can convert.

Three vocab numbers are in play and none of them agree, which is the whole reason this script
exists rather than a one-line `mlx_lm convert`:

    LLaMmlein_1B_prerelease  config vocab_size  32000   <- what adapter_config.json names as base
    the adapter's tokenizer  len(tokenizer)     32003   <- adds <|im_start|> 32001, <|im_end|> 32002
    the adapter's tensors    embed_tokens/lm_head 32064 <- 32003 padded up to a multiple of 64

`adapter_config.json` claims `modules_to_save: null`, which would mean the three new ChatML rows
were never trained — and an untrained `<|im_end|>` row is fatal, because that is the only token the
chat template terminates on (the ELMOD failure exactly). It turns out to be a mislabel: the adapter
ships FULL `embed_tokens` and `lm_head` tensors, so those rows are trained and simply overwrite the
base's. That is why the resize below is safe — every resized row is replaced, none is left random.

NB the adapter targets `LLaMmlein_1B_prerelease`, NOT `LLaMmlein_1B`. They are different weights
(32000 vs 32064 vocab); merging onto the wrong one silently produces garbage.

Usage (from training/):
  .venv/bin/python scripts/merge_llammlein_chat.py --adapter LSX-UniWue/LLaMmlein_1B_chat_all \
      --out models/llammlein-1b-chat-all-merged
"""
import argparse
import glob
import json
from pathlib import Path

import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer, PreTrainedTokenizerFast


def load_tokenizer(adapter_dir: str):
    """Load the chat tokenizer WITHOUT trusting its declared `tokenizer_class`.

    The 1B chat repos ship a ByteLevel-BPE `tokenizer.json` (vocab uses `Ġ` for space and `Ã¼` for
    `ü`) but label it `tokenizer_class: "LlamaTokenizer"` in tokenizer_config.json. transformers
    honours the label, builds a SentencePiece-style LlamaTokenizer over a ByteLevel vocab, and
    silently reinterprets every word-boundary marker:

        AutoTokenizer         "Ich warte für den Bus."  ->  "IchwartefrdenBus."   <- spaces and ü gone
        PreTrainedTokenizerFast                          ->  "Ich warte für den Bus."  round-trips

    mlx_lm loads with AutoTokenizer, so the mislabel silently corrupts BOTH the prompt and the
    decode. Scored that way the model returns `FIX:IchwartefrdenBusan.` and lands at 0/60 — a
    measurement of the loader, not the model. Bypass the label; keep the file's own components.
    """
    fast = PreTrainedTokenizerFast(tokenizer_file=str(Path(adapter_dir) / "tokenizer.json"))
    cfg = json.loads((Path(adapter_dir) / "tokenizer_config.json").read_text())
    for attr in ("bos_token", "eos_token", "unk_token", "pad_token"):
        val = cfg.get(attr)
        if isinstance(val, dict):
            val = val.get("content")
        if val:
            setattr(fast, attr, val)
    fast.chat_template = cfg.get("chat_template")
    probe = "Ich warte für den Bus."
    got = fast.decode(fast.encode(probe, add_special_tokens=False))
    if got != probe:
        raise SystemExit(f"tokenizer still does not round-trip: {got!r}")
    return fast


def local_snapshot(repo: str) -> str:
    """Resolve a cached snapshot dir. We download with ignore_patterns=['*.bin'], which makes
    snapshot_download(local_files_only=True) raise IncompleteSnapshotError, so glob instead."""
    if Path(repo).exists():
        return str(repo)
    cache = Path.home() / ".cache/huggingface/hub" / f"models--{repo.replace('/', '--')}" / "snapshots"
    hits = sorted(glob.glob(str(cache / "*/")))
    if not hits:
        raise SystemExit(f"{repo} not in the local cache — download it first")
    return hits[-1]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--adapter", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    adapter_dir = local_snapshot(args.adapter)
    base_repo = json.loads((Path(adapter_dir) / "adapter_config.json").read_text())["base_model_name_or_path"]
    base_dir = local_snapshot(base_repo)
    print(f"adapter : {args.adapter}\nbase    : {base_repo}")

    tok = load_tokenizer(adapter_dir)
    base = AutoModelForCausalLM.from_pretrained(base_dir, torch_dtype=torch.float32)
    print(f"base embedding {base.get_input_embeddings().weight.shape[0]} -> resizing to 32064")
    base.resize_token_embeddings(32064)  # rows are all overwritten by the adapter's full tensors

    merged = PeftModel.from_pretrained(base, adapter_dir).merge_and_unload()

    # Make the chat contract explicit in the config so mlx_lm stops on <|im_end|> rather than
    # running to max_tokens — the single most common way a merged chat model looks "broken".
    im_end = tok.convert_tokens_to_ids("<|im_end|>")
    merged.config.eos_token_id = im_end
    merged.config.bos_token_id = tok.bos_token_id
    merged.generation_config.eos_token_id = im_end
    merged.generation_config.pad_token_id = im_end

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    merged.save_pretrained(out, safe_serialization=True)
    tok.save_pretrained(out)
    print(f"\nsaved {out}  (eos <|im_end|> = {im_end}, vocab {merged.config.vocab_size})")
    print("next: .venv/bin/python -m mlx_lm convert --hf-path", out, "-q --q-bits 4 --mlx-path", str(out).replace("-merged", "-4bit"))


if __name__ == "__main__":
    main()
