#!/bin/bash
# Bundle everything train_grpo.py needs on the pod — REINFORCEMENT_LEARNING.md Part A §11.
#   runpod/gemma4_grpo_runpod.tar.gz  ->  scp to the pod, extract into /root/train, run train_grpo.py there
# The reward imports run_baseline_eval (stdlib-only at import time), so both scripts ship.
set -euo pipefail
cd "$(dirname "$0")/.."
POOL=${POOL:-data/rl_pool_v1/train.jsonl}
[ -f "$POOL" ] || { echo "no pool at $POOL — run scripts/build_rl_pool.py mine first"; exit 1; }
STAGE=$(mktemp -d)/runpod_bundle
mkdir -p "$STAGE"
cp runpod/train_grpo.py scripts/rl_rewards.py scripts/run_baseline_eval.py "$STAGE/"
cp "$POOL" "$STAGE/train.jsonl"
cp data/rl_pool_v1/meta.json "$STAGE/pool_meta.json" 2>/dev/null || true
md5 -q "$STAGE/train.jsonl" > "$STAGE/train.jsonl.md5"
tar -C "$(dirname "$STAGE")" -czf runpod/gemma4_grpo_runpod.tar.gz runpod_bundle
echo "runpod/gemma4_grpo_runpod.tar.gz: $(du -h runpod/gemma4_grpo_runpod.tar.gz | cut -f1), pool $(wc -l < "$POOL") prompts, md5 $(cat "$STAGE/train.jsonl.md5")"
echo "on the pod: md5sum /root/train/train.jsonl must equal $(cat "$STAGE/train.jsonl.md5")"
