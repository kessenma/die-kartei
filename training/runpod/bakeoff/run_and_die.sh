#!/bin/bash
# run_and_die.sh — generate -> checksum -> upload to HF -> verify bytes -> terminate the pod.
#
# Run detached ON the pod:  setsid nohup bash run_and_die.sh > /workspace/run.log 2>&1 < /dev/null &
# Arm the deadline backstop BEFORE this (see bakeoff/README.md §4) — a wedged generator can't block it.
#
# Requires at pod creation: env.HF_TOKEN (write-scoped). RunPod injects RUNPOD_POD_ID and a
# pod-scoped RUNPOD_API_KEY, and runpodctl is preinstalled, so self-termination needs no extra setup.
#
# The termination gate is "bytes verified on HF", NOT "generator exited". Killing the process saves
# nothing — the GPU bills until the POD dies. And on mismatch we deliberately leave the pod up:
# an idle pod costs dollars; terminating with an unshipped corpus costs the run (containerDisk is wiped).
set -x
cd /workspace

JOBS=${JOBS:-jobs.jsonl}
OUT=${OUT:-/workspace/out/bulk_raw.jsonl}
MODEL=${MODEL:-google/gemma-4-31B-it}
DATASET_REPO=${DATASET_REPO:-kessenma/teacher-drops}   # private HF *dataset* repo

mkdir -p "$(dirname "$OUT")"
env HF_HOME=/workspace/hf PYTHONUNBUFFERED=1 \
  /workspace/venv/bin/python generate_bulk.py \
    --jobs "$JOBS" --out "$OUT" --model "$MODEL" --batch 6 --max-new-tokens 1400

md5sum "$OUT" > "$OUT.md5"
/workspace/venv/bin/hf upload "$DATASET_REPO" "$(dirname "$OUT")" . --repo-type dataset

LOCAL=$(stat -c%s "$OUT")
REMOTE=$(/workspace/venv/bin/python - "$DATASET_REPO" "$(basename "$OUT")" <<'PY'
import sys
from huggingface_hub import HfApi
repo, name = sys.argv[1], sys.argv[2]
for f in HfApi().list_repo_tree(repo, repo_type="dataset", recursive=True):
    if f.path.endswith(name):
        print(f.size)
        break
PY
)

if [ -n "$REMOTE" ] && [ "$LOCAL" = "$REMOTE" ]; then
  echo "UPLOAD VERIFIED ($LOCAL bytes) — terminating pod $RUNPOD_POD_ID"
  runpodctl remove pod "$RUNPOD_POD_ID"
else
  echo "UPLOAD MISMATCH local=$LOCAL remote=$REMOTE — POD LEFT RUNNING, retrieve manually"
fi
