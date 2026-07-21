# RunPod training runbook — Gemma 4 E4B German tutor

## 1. Create the pod
- Template: **RunPod PyTorch 2.x** (any recent CUDA 12 image)
- GPU: **RTX 4090 (24 GB)** or A40 — ~$0.30–0.70/hr. Anything ≥16 GB VRAM works;
  24 GB lets batch size 2 breathe.
- Volume: **≥ 60 GB** (base model ~8 GB + 4-bit cache + merged fp16 output ~16 GB + headroom)

## 2. Upload this bundle
Either drag `gemma4_finetune_runpod.tar.gz` into Jupyter Lab (pod's web UI), or:
```bash
# on your Mac (runpodctl from https://github.com/runpod/runpodctl)
runpodctl send gemma4_finetune_runpod.tar.gz
# in the pod terminal: paste the receive command it prints
```
Then in the pod:
```bash
tar -xzf gemma4_finetune_runpod.tar.gz && cd runpod_bundle
```

## 3. Install + train
```bash
pip install unsloth
export HF_TOKEN=hf_...                                   # write token (optional but recommended)
export HF_REPO=<your-hf-username>/gemma4-e4b-german-tutor  # private repo to push to
python train_gemma4_e4b.py
```
- Expect a couple of hours on a 4090 for 2 epochs over ~1.4k examples.
- Initial loss around 13–15 is NORMAL for Gemma 4 (per Unsloth docs).
- If the script exits with "could not auto-detect turn markers", it prints the rendered
  chat template — read the user/model turn prefixes from it and rerun with
  `INSTRUCTION_PART='...' RESPONSE_PART='...' python train_gemma4_e4b.py`.
  (Cross-check the official Unsloth Gemma4_(E4B)-Text notebook if unsure.)

## 4. Get the model out
Pushing to HF (step 3 env vars) is strongly recommended — the merged model is ~16 GB
and a hub push from the pod is much faster than a local download.

## 5. Back on the Mac (Phase 5 in PLAN.md)
```bash
cd training
.venv/bin/python -m mlx_lm convert --hf-path <HF_REPO> -q --q-bits 4 --q-group-size 64 \
    --upload-repo <you>/gemma4-e4b-german-tutor-4bit    # or leave off to keep local
.venv/bin/python scripts/run_baseline_eval.py --tag finetuned --model <you>/gemma4-e4b-german-tutor-4bit
.venv/bin/python scripts/run_baseline_eval.py --tag finetuned-extra --model <you>/gemma4-e4b-german-tutor-4bit \
    --eval-file data/eval/grammar_eval_v1_extra.json
```
Compare against baseline: core 43/60 (refl/dawo 60%), extension 53/61, FIX-echo 36%.
If 4-bit quality drops vs fp16: `--q-group-size 32`, then `--quant-predicate mixed_4_6`, then DWQ.

**Before the app downloads the -4bit repo:** it must contain exactly ONE `.safetensors`
(`model.safetensors`). MLX Swift merges every `*.safetensors` in the snapshot recursively,
so a stray `lora/adapter_model.safetensors` (PEFT `base_model.*` keys) breaks loading with
`Unhandled keys ["base_model"] in Gemma4Model`. If `lora/` rode along from the training
push, delete it from the hub repo (keep adapters local or in a separate `-lora` repo):
```bash
.venv/bin/python -c "from huggingface_hub import HfApi; HfApi().delete_folder(
    repo_id='<you>/gemma4-e4b-german-tutor-4bit', path_in_repo='lora',
    commit_message='remove LoRA adapters from inference repo')"
```

## Stop the pod when done — it bills while running.
