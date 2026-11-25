#!/bin/bash
# run_and_die.sh — generate -> checksum -> upload to HF -> verify bytes -> terminate the pod.
#
# Run detached ON the pod:  setsid nohup bash run_and_die.sh > /workspace/run.log 2>&1 < /dev/null &
# Arm the deadline backstop BEFORE this (see bakeoff/README.md §4) — a wedged generator can't block it.
#
# Requires at pod creation: env.HF_TOKEN (write-scoped), env.SELF_POD_ID, and env.RUNPOD_API_KEY
# set to a RESTRICTED key (pod-scope only — never the full account key on a community host).
# Measured 2026-08-17: RunPod does NOT inject RUNPOD_POD_ID/RUNPOD_API_KEY on the standard pytorch
# image; only runpodctl itself is preinstalled. Without both env vars this script cannot terminate
# the pod and will say so — an external watchdog must then do it.
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
  if [ -n "${SELF_POD_ID:-}" ] && [ -n "${RUNPOD_API_KEY:-}" ]; then
    echo "UPLOAD VERIFIED ($LOCAL bytes) — terminating pod $SELF_POD_ID"
    runpodctl config --apiKey "$RUNPOD_API_KEY"
    runpodctl remove pod "$SELF_POD_ID"
  else
    echo "UPLOAD VERIFIED but SELF_POD_ID/RUNPOD_API_KEY not set — CANNOT SELF-TERMINATE."
    echo "POD STILL BILLING: an external watchdog must remove it."
  fi
else
  echo "UPLOAD MISMATCH local=$LOCAL remote=$REMOTE — POD LEFT RUNNING, retrieve manually"
fi
