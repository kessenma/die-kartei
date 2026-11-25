#!/bin/bash
# kasus_bakeoff_reasoning.sh — Kolibri's reasoning pass again, with room to think.
# The main run gave `reasoning_effort: medium` 2× maxTokens + 8,192 tokens, and 246 of 306 stories ran
# out mid-reasoning (median 9,291 reasoning tokens). Here: 66 prompts (the six probe specs + seeds
# 2001-2004 of every unit and level), `low` and `medium`, 32k reasoning budget, max-model-len 40,960.
# Run after kasus_bakeoff.sh, with /workspace/HOLD set so that run doesn't remove the pod; this script
# removes HOLD and terminates once its own upload is verified.
set -u
cd /workspace
[ -f /workspace/.env.run ] && { set -a; . /workspace/.env.run; set +a; }
export HF_HOME=/workspace/hf PYTHONUNBUFFERED=1 HF_XET_HIGH_PERFORMANCE=1
export PATH=/workspace/venv/bin:$PATH VLLM_USE_FLASHINFER_SAMPLER=0
OUT=/workspace/out
STATUS=$OUT/status.txt
stamp() { echo "$(date -u +%FT%TZ) $*" | tee -a "$STATUS"; }

python3 - <<'PY'
import json
keep = {1001, 1002, 1003, 1004, 1005, 1006, 2001, 2002, 2003, 2004}
rows = [json.loads(l) for l in open("/workspace/story_prompts.jsonl")]
sub = [r for r in rows if r["seed"] in keep]
open("/workspace/story_prompts_sub.jsonl", "w").write("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in sub))
print(len(sub), "prompts")
PY

hf download Aleph-Alpha/Kolibri-1 > /workspace/dl_kolibri2.log 2>&1 || stamp "Kolibri re-download failed"
vllm serve Aleph-Alpha/Kolibri-1 --kv-cache-dtype fp8 --reasoning-parser kolibri1 \
  --max-model-len 40960 --gpu-memory-utilization 0.90 --port 8000 > /workspace/vllm2.log 2>&1 &
pid=$!
for _ in $(seq 1 180); do
  curl -sf -m 5 http://127.0.0.1:8000/health > /dev/null && break
  kill -0 "$pid" 2> /dev/null || break
  sleep 10
done
if curl -sf -m 5 http://127.0.0.1:8000/health > /dev/null; then
  stamp "vLLM healthy (reasoning rerun)"
  common=(--backend openai --base-url http://127.0.0.1:8000/v1 --model Aleph-Alpha/Kolibri-1
          --concurrency 66 --temperature 1.0 --top-p 0.97 --top-k 128 --enable-thinking true
          --budget-factor 2 --reasoning-budget 32768)
  for effort in low medium; do
    timeout 1h python generate_chat.py --in story_prompts_sub.jsonl \
      --out "$OUT/stories_kolibri1-think-$effort-32k.jsonl" --label "kolibri1-think-$effort-32k" \
      "${common[@]}" --reasoning-effort "$effort"
    stamp "kolibri reasoning $effort (32k) exit $?"
  done
  kill "$pid"
else
  stamp "vLLM not healthy (reasoning rerun)"; tail -40 /workspace/vllm2.log >> "$STATUS"
fi
stamp "reasoning rerun done, final upload"
hf upload "$DATASET_REPO" "$OUT" . --repo-type dataset --commit-message "kolibri reasoning rerun" >> /workspace/upload.log 2>&1
python - "$DATASET_REPO" "$OUT" <<'PY' && { rm -f /workspace/HOLD; bash /workspace/pod_terminate.sh "reasoning rerun done, upload verified"; } || echo "UPLOAD NOT VERIFIED — POD LEFT RUNNING"
import os, sys
from huggingface_hub import HfApi
repo, out = sys.argv[1], sys.argv[2]
remote = {f.path: getattr(f, "size", None) for f in HfApi().list_repo_tree(repo, repo_type="dataset", recursive=True)}
bad = [n for n in sorted(os.listdir(out)) if os.path.isfile(os.path.join(out, n)) and remote.get(n) != os.path.getsize(os.path.join(out, n))]
print("VERIFY OK" if not bad else f"VERIFY MISMATCH {bad}")
sys.exit(1 if bad else 0)
PY
