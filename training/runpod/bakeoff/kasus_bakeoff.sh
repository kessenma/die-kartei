#!/bin/bash
# kasus_bakeoff.sh — the Kasus story + correction-tail bake-off in one pod session
# (KASUS_STORY_DATA.md §4): Kolibri-1 through vLLM (thinking off, then reasoning_effort medium),
# then gemma-4-31B through transformers, each on the same story prompts and tail jobs.
# Uploads to HF after every phase, verifies the bytes, then removes the pod.
#
# On the pod, from /workspace, with generate_chat.py, story_prompts.jsonl and tail_jobs.jsonl
# next to it:
#   setsid nohup bash kasus_bakeoff.sh > /workspace/run.log 2>&1 < /dev/null &
# Arm the deadline backstop first (bakeoff/README.md §4).
#
# Secrets come from /workspace/.env.run (written over SSH, mode 600; not pod env, so they aren't
# stored in the pod's config): HF_TOKEN (write-scoped), DATASET_REPO (a private dataset), and for
# self-termination SELF_POD_ID + RUNPOD_API_KEY set to a RESTRICTED key. Without those two it
# uploads and leaves the pod up, loudly, and something outside must remove it.
#
# A phase that fails doesn't stop the next: Kolibri failing to serve still leaves the gemma
# phases worth their GPU time. Termination is gated on every file in out/ matching on HF.
set -u
cd /workspace
[ -f /workspace/.env.run ] && { set -a; . /workspace/.env.run; set +a; }

OUT=/workspace/out
mkdir -p "$OUT"
export HF_HOME=/workspace/hf PYTHONUNBUFFERED=1 HF_XET_HIGH_PERFORMANCE=1
# The venv's tools (ninja for any JIT build) must be on PATH; and vLLM's FlashInfer sampler JIT-compiles
# its top-k kernel at warm-up, which crashed the 2026-10-04 run ("No such file or directory: 'ninja'"),
# so use vLLM's PyTorch sampler instead.
export PATH=/workspace/venv/bin:$PATH VLLM_USE_FLASHINFER_SAMPLER=0
PY=/workspace/venv/bin/python
HF=/workspace/venv/bin/hf
STATUS=$OUT/status.txt

stamp() { echo "$(date -u +%FT%TZ) $*" | tee -a "$STATUS"; }

upload() {
  if $HF upload "$DATASET_REPO" "$OUT" . --repo-type dataset --commit-message "$1" >> /workspace/upload.log 2>&1; then
    echo "uploaded: $1"
  else
    stamp "UPLOAD FAILED: $1"
  fi
}

wait_gpu_free() {
  for _ in $(seq 1 24); do
    used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
    [ "${used:-99999}" -lt 2000 ] && return 0
    sleep 5
  done
  stamp "GPU still holds ${used} MiB after 2 min"
}

phase_install() {
  python3 -m venv /workspace/venv || return 1
  /workspace/venv/bin/pip install -q --upgrade pip >> /workspace/install.log 2>&1
  /workspace/venv/bin/pip install -q "vllm==0.29.0" "aleph-alpha-inference==1.0.0" accelerate \
    >> /workspace/install.log 2>&1 || return 1
  $PY -c "import vllm, torch, transformers; print('vllm', vllm.__version__, 'torch', torch.__version__, 'cuda ok', torch.cuda.is_available(), 'transformers', transformers.__version__)" \
    | tee -a "$STATUS"
}

phase_kolibri() {
  $HF download Aleph-Alpha/Kolibri-1 > /workspace/dl_kolibri.log 2>&1 || { stamp "Kolibri download failed"; return 1; }
  stamp "Kolibri downloaded"
  /workspace/venv/bin/vllm serve Aleph-Alpha/Kolibri-1 --kv-cache-dtype fp8 --reasoning-parser kolibri1 \
    --max-model-len 16384 --gpu-memory-utilization 0.90 --port 8000 > /workspace/vllm.log 2>&1 &
  local pid=$!
  local healthy=""
  for _ in $(seq 1 270); do                       # up to 45 min
    if curl -sf -m 5 http://127.0.0.1:8000/health > /dev/null; then healthy=1; break; fi
    if ! kill -0 "$pid" 2> /dev/null; then
      stamp "vLLM exited during startup"; tail -60 /workspace/vllm.log >> "$STATUS"; return 1
    fi
    sleep 10
  done
  if [ -z "$healthy" ]; then
    stamp "vLLM not healthy after 45 min"; tail -60 /workspace/vllm.log >> "$STATUS"; kill "$pid"; return 1
  fi
  stamp "vLLM healthy"

  local common=(--backend openai --base-url http://127.0.0.1:8000/v1 --model Aleph-Alpha/Kolibri-1
                --concurrency 64 --temperature 1.0 --top-p 0.97 --top-k 128)
  timeout 2h $PY generate_chat.py --in story_prompts.jsonl --out "$OUT/stories_kolibri1-nothink.jsonl" \
    --label kolibri1-nothink "${common[@]}" --reasoning-effort none --enable-thinking false --budget-factor 2
  stamp "kolibri stories (thinking off) exit $?"
  upload "kolibri stories, thinking off"

  timeout 2h $PY generate_chat.py --in story_prompts.jsonl --out "$OUT/stories_kolibri1-think.jsonl" \
    --label kolibri1-think-medium "${common[@]}" --reasoning-effort medium --enable-thinking true \
    --budget-factor 2 --reasoning-budget 8192
  stamp "kolibri stories (reasoning medium) exit $?"
  upload "kolibri stories, reasoning medium"

  timeout 1h $PY generate_chat.py --in tail_jobs.jsonl --out "$OUT/tail_kolibri1-nothink.jsonl" \
    --label kolibri1-nothink "${common[@]}" --reasoning-effort none --enable-thinking false --budget-factor 1
  stamp "kolibri tail exit $?"
  upload "kolibri tail"

  kill "$pid"; wait "$pid" 2> /dev/null
  tail -300 /workspace/vllm.log > "$OUT/vllm_tail.log"
  rm -rf /workspace/hf/hub/models--Aleph-Alpha--Kolibri-1     # room for gemma
  wait_gpu_free
}

phase_gemma() {
  $HF download google/gemma-4-31B-it > /workspace/dl_gemma.log 2>&1 || { stamp "gemma download failed"; return 1; }
  stamp "gemma downloaded"
  local common=(--backend transformers --model google/gemma-4-31B-it --label gemma4-31b
                --temperature 0.9 --top-p 0.95)
  timeout 2h $PY generate_chat.py --in story_prompts.jsonl --out "$OUT/stories_gemma4-31b.jsonl" \
    "${common[@]}" --batch 16 --budget-factor 2
  stamp "gemma stories exit $?"
  upload "gemma stories"

  timeout 1h $PY generate_chat.py --in tail_jobs.jsonl --out "$OUT/tail_gemma4-31b.jsonl" \
    "${common[@]}" --batch 12 --budget-factor 1
  stamp "gemma tail exit $?"
  upload "gemma tail"
}

verify() {
  $PY - "$DATASET_REPO" "$OUT" << 'PY'
import os, sys
from huggingface_hub import HfApi
repo, out = sys.argv[1], sys.argv[2]
remote = {f.path: getattr(f, "size", None)
          for f in HfApi().list_repo_tree(repo, repo_type="dataset", recursive=True)}
bad = [(n, os.path.getsize(os.path.join(out, n)), remote.get(n))
       for n in sorted(os.listdir(out))
       if os.path.isfile(os.path.join(out, n)) and remote.get(n) != os.path.getsize(os.path.join(out, n))]
print("VERIFY OK" if not bad else f"VERIFY MISMATCH {bad}")
sys.exit(1 if bad else 0)
PY
}

terminate() { bash /workspace/pod_terminate.sh "run finished, upload verified"; }

stamp "start"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader | tee -a "$STATUS"
if phase_install; then
  stamp "install ok"
  phase_kolibri || stamp "KOLIBRI PHASE FAILED"
  phase_gemma || stamp "GEMMA PHASE FAILED"
else
  stamp "INSTALL FAILED"; tail -40 /workspace/install.log >> "$STATUS"
fi
cp /workspace/install.log /workspace/dl_*.log "$OUT/" 2> /dev/null
stamp "done, final upload"
upload "final"
# Nothing writes to out/ after this line, so the byte check is final.
if verify; then
  terminate
else
  echo "UPLOAD NOT VERIFIED — POD LEFT RUNNING, retrieve /workspace/out manually"
fi
