# Bulk teacher generation on RunPod — copy-paste runbook

For generating German correction training data at scale with an open model. Measured results and
the reasoning behind the gates: [`../../TEACHER_GENERATION_FIX.md`](../../TEACHER_GENERATION_FIX.md).

> ✅ **2026-08-16: `google/gemma-4-31B-it` IS viable for bulk — batched.** The 2026-08-15 "not
> viable" verdict here was wrong: it extrapolated from `generate_hardcase.py`, which generates one
> prompt at a time, so its 50 rows / 35 min was a batch-size-1 number. `generate_bulk.py` batches.
> Measured on an A100 80 GB SXM, bf16, batch 6:
>
> | path | result |
> |---|---|
> | **transformers bf16, batched** (`generate_bulk.py --batch 6`, A100 80 GB) | ✅ **~50 tok/s aggregate ≈ 30 rows/min. 5,223 raw rows in ~2.9 h, ~$5 of GPU.** refl case-change 98%, sep pure-reorder 3%, no-ops 3.8% — both gates PASS |
> | transformers bf16/8-bit, unbatched (`generate_hardcase.py`) | ⚠️ ~1.4 rows/min — pilot/bake-off only |
> | transformers + QAT `w4a16` | ❌ OOM on a 48 GB A40 — `compressed-tensors` **dequantizes** on load |
> | **vLLM 0.27.1** (newest) | ❌ **cannot load it at all.** `AmbiguousGlobalPerLayerAttributeError: 'head_dim' is a per-layer attribute`. Gemma 4's per-layer config vs vLLM's homogeneous-config assumption. No upstream fix; batching makes vLLM unnecessary anyway |
>
> **Do not** force `allow_global_per_layer_attribute_access=True` to get past the vLLM error. Its
> own warning says homogeneous-assuming code "may use the global value incorrectly" — for attention
> head dimensions that is silently wrong inference, which would poison the corpus in a way none of
> the gates below can detect.
>
> ⚠️ **Batch 16 OOMs even on 80 GB.** Gemma 4 31B's KV cache is ~1.3 MB/token (60 layers × 32 KV
> heads); at `--max-new-tokens 1400` plus prompt, batch 16 is ~40 GB of KV on top of 62 GB of
> weights. **Batch 6 is the measured ceiling** at that generation length.

**Teacher selection, as measured.** `gemma-4-31B` is the quality leader AND the bulk path (batched,
above). `gemma-4-26B-A4B-it` is retired as a teacher: it is a ~4B-active MoE and produces 12%
hard-case reflexives and 26% word-order rows mislabelled as separable verbs — its v2 corpus is
salvageable only for `vmp`/`dawo` (98%/90% correctly shaped; the extracted slice lives in
`data/salvage_gemma26b/vmp_dawo.valid.jsonl`, 10,139 validated rows). Qwen3.8-27B, with thinking
mode correctly disabled, passes the shape gates (refl case-change 84%) but wastes **39% of its rows
as no-ops** vs gemma's 3.8% — half the usable rows per GPU-minute. Fallback, not first choice.

---

## 1. Pod

- **Bulk (the normal case): A100 SXM 80 GB**, ~$1.39/hr community. bf16 31B (62 GB) + batch-6 KV
  fits; nothing smaller runs the batched bf16 path.
- Pilot / bake-off only: A40 48 GB, **$0.44/hr**, usually HIGH stock. 8-bit fits a 31B in ~32 GB
  but is unbatched-slow (~1.4 rows/min) — fine for 50-row quality checks, never for bulk.

```
image           runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404
containerDisk   40 GB          # LOCAL, wiped on stop — put outputs here if you'll stop the pod
volume          150 GB @ /workspace   # NETWORK fs, persists; holds the HF cache
ports           22/tcp, 8888/http
env.PUBLIC_KEY  <~/.runpod/ssh/runpodctl-ssh-key.pub>   # REQUIRED or sshd never starts
env.HF_TOKEN    <write-scoped HF token>   # REQUIRED for the auto-shutdown path (§6) to upload results
```

⚠️ **Two bf16 downloads do not fit one 150 GB volume** (31B = 62.5 GB, 27B = 55.6 GB). Free the
first cache before pulling the second: `rm -rf /workspace/hf/hub/models--<org>--<model>`.

⚠️ **A40 is Ampere (sm_86) — no FP8.** FP8 builds need Ada (sm_89+). Use bf16 + `--load-8bit`, or a
w4a16/w8a16 pre-quant.

## 2. Connect

```bash
SSHK=~/.runpod/ssh/runpodctl-ssh-key
# direct SSH only — the ssh.runpod.io proxy needs a PTY and hangs on scripted commands
ssh -i $SSHK -p <port> -o BatchMode=yes -o ConnectTimeout=10 \
    -o ServerAliveInterval=10 -o ServerAliveCountMax=3 root@<ip> 'nvidia-smi'
```

⚠️ zsh does **not** word-split unquoted vars — `$SSHOPTS` collapses into one `-i` argument. Inline
the flags or use an array.

## 3. Install

```bash
python -m venv --system-site-packages /workspace/venv     # PEP 668 blocks the system python
setsid nohup /workspace/venv/bin/pip install -q transformers accelerate bitsandbytes \
  > /workspace/install.log 2>&1 < /dev/null &
```

## 4. Generate — launch it so the pod kills itself

Jobs come from `scripts/build_gen_jobs.py`. **Size the manifest to what you actually want** — the
2026-08 run submitted 2,000 jobs wanting ~5,000 rows, hit the target at job 630, and the "stop at
row count" script killed the *generator* but not the *pod*, which then idled ~5 h ≈ **$5.50 of a
$10.40 run**. A right-sized manifest ends by itself; the wrapper below then ships the data and
terminates the pod with nobody awake.

```bash
scp -i $SSHK -P <port> runpod/bakeoff/generate_bulk.py runpod/bakeoff/run_and_die.sh \
    training/data/gen_v2/jobs.jsonl root@<ip>:/workspace/

# absolute-deadline backstop FIRST — a wedged generator cannot block this
ssh ... 'setsid nohup bash -c "sleep 21600; runpodctl remove pod \$RUNPOD_POD_ID" \
  > /workspace/deadline.log 2>&1 < /dev/null &'          # ~2× the run's ETA

# then the run itself: generate -> md5 -> upload to HF -> verify bytes -> self-terminate
ssh ... 'cd /workspace && setsid nohup bash run_and_die.sh \
  > /workspace/run.log 2>&1 < /dev/null &'
```

`run_and_die.sh` (kept next to this README) does, in order: `generate_bulk.py --batch 6`,
`md5sum` the output, `hf upload` the output dir to a private HF **dataset** repo, re-list the repo
and compare the uploaded byte count to the local file, and **only if they match**
`runpodctl remove pod $RUNPOD_POD_ID`. On mismatch it leaves the pod up — an idle pod costs
dollars; a terminated pod with an unshipped corpus costs the whole run (containerDisk is wiped).

Why this shape:

- **Termination is gated on the data being off the box, not on the generator exiting.** Killing the
  process saves nothing; the GPU bills until the *pod* dies.
- **The pod terminates itself.** RunPod injects `RUNPOD_POD_ID` and a pod-scoped `RUNPOD_API_KEY`
  into every pod, and `runpodctl` is preinstalled — `runpodctl remove pod $RUNPOD_POD_ID` works
  from inside. No Mac-side watchdog to leave running overnight; results go to HF, not scp, for the
  same reason (the laptop can sleep).
- **The deadline backstop is a separate process armed before the run.** §6.9 of the main runbook:
  failsafes here have failed in both directions, so the backstop must be something a hung child
  cannot block.
- **Verify from the outside anyway, every time**: `runpodctl pod list` on the Mac must print an
  empty table. Never trust that a shutdown script fired — check that it did.

Monitoring while it runs:

- `PYTHONUNBUFFERED=1` (set inside `run_and_die.sh`) or the log stays 0 bytes for minutes and looks
  hung. `nvidia-smi` is ground truth.
- Progress: `tail -3 /workspace/run.log` — the batched script prints `[N/total] +rows | tok/s | eta`.
- Expected: ~50 tok/s aggregate, ~30 rows/min, GPU pinned >90%. If GPU sits at 5–20% you are
  memory-bound (8-bit) or unbatched — stop and fix; do not pay A100 rates for A40 throughput.

⚠️ **Pilots: `--limit N` takes the manifest HEAD.** `build_gen_jobs.py` writes jobs in phenomenon
blocks, so a `--limit 12` pilot can test zero `refl`/`sep` and bless a teacher on the easy slice —
exactly what happened on 2026-08-15. Pilot with per-phenomenon job files or a stratified sample.

## 5. Filter and gate — do not skip

```bash
scp -i $SSHK -P <port> root@<ip>:/workspace/out/batch.jsonl data/bakeoff/

# 1. drop degenerate rows (gemma-4-31B emits ~18%)
python - <<'PY'
import json
rows=[json.loads(l) for l in open('data/bakeoff/batch.jsonl') if l.strip()]
live=[d for d in rows if (d.get('student') or '').strip() != (d.get('fix') or '').strip()]
print(f"{len(rows)} -> {len(live)} ({len(rows)-len(live)} no-ops dropped)")
open('data/bakeoff/batch.live.jsonl','w').write(
    ''.join(json.dumps(d,ensure_ascii=False)+'\n' for d in live))
PY

# 2. SHAPE gate — the one that catches "valid German that teaches nothing"
python scripts/check_hard_case_share.py --strict data/bakeoff/batch.live.jsonl

# 3. correctness gate
python scripts/validate_data.py data/bakeoff/batch.live.jsonl
```

Gates, set from the teacher that actually produced a 54/60 model:

```
refl case-change  >= 60%      sep pure-reorder <= 5%
```

**Both gates, every batch.** LanguageTool and spaCy answer "is this correct German?" — they cannot
answer "does this teach the skill the eval measures", and the difference has cost two training runs.

## 6. Terminate — do not "stop", and do not trust the script

Disk bills while a pod is stopped (measured: $0.61 disk on a $0-GPU day). Stopping also kills the
running process, so it preserves only the downloaded weights — which re-download in ~10 min. Pausing
is worse than terminating after roughly four hours.

The §4 launch pattern makes termination automatic, but the failsafe family has now failed **three**
times here (stopped a healthy pod; never fired and idled ~6 h; killed the generator but not the pod,
~5 h idle ≈ $5.50). So the last step of every run is manual and non-negotiable:

```bash
runpodctl pod list        # must print an empty table
```

If a pod survived, `runpodctl remove pod <id>` (or MCP `delete-pod`) — *remove*, not *stop*.

---

## Model-specific traps

| model | trap |
|---|---|
| **Qwen3.x** (incl. Qwen3.8-27B) | Chat template defaults to thinking mode (`Reasoning effort is set to xhigh`, opens `<think>`). It burns the whole token budget reasoning and emits **zero** JSON — looks exactly like a capability failure. **Pass `enable_thinking=False`** (handled in both generators). With that fixed it passes the shape gates (refl case-change 84%) but produces **39% no-ops** — half gemma-31B's usable throughput. |
| **gemma-4-31B** | Some rows come back `student == fix` — **3.8%** at bf16 batched (the 18% previously noted here was the 8-bit bake-off config). Filter them; everything else is clean. KV ≈ 1.3 MB/token: **batch 6 max** at 1400 new tokens on 80 GB, batch 16 OOMs. |
| **gemma-4-26B-A4B** | MoE, ~4B active. Fine for `vmp`/`dawo` (98%/90% correctly shaped), unusable for `refl`/`sep`. Retired as a teacher; salvage slice extracted to `data/salvage_gemma26b/`. |
| **Granite** | Unsloth drops `rope_theta`/`rope_scaling` on merge every time; restore from the base repo before converting. |
| any new architecture | Check `transformers` can load it before renting. `AutoModelForCausalLM.from_pretrained(..., trust_remote_code=True)` on a small download first. |

## Which teacher for bulk

| need | teacher | how | note |
|---|---|---|---|
| **bulk, ANY phenomenon — incl. `refl`/`sep`** | **gemma-4-31B** | `generate_bulk.py --batch 6`, bf16, A100 80 GB | proven 2026-08: 5,223 raw rows in ~2.9 h, ~$5. refl 98% case-change, sep 3% reorder, 3.8% no-op |
| `verdict` + judgment-heavy, no infra | Claude Sonnet (subagents) | ~1,200 rows/hr | 1,344 rows in ~40 min; a wrong `verdict` row teaches the model to accept errors, so keep Sonnet on these |
| small pilot / bake-off, any phenomenon | gemma-4-31B | `generate_hardcase.py --load-8bit`, A40 | ~50 rows / 35 min, ~$0.30 |
| fallback if gemma is unavailable | Qwen3.8-27B | `generate_bulk.py`, bf16, A100 80 GB | passes gates but 39% no-op — budget ~2× the rows |
| ~~bulk via gemma-4-26B-A4B~~ | retired | — | MoE teacher failure is what v2/v3 paid for. Its old corpus: `vmp`/`dawo` salvage only |

## What to generate, and with which teacher

Division of labour, measured rather than assumed:

| slice | teacher | why |
|---|---|---|
| `refl`, `sep` | Sonnet **or** gemma-4-31B | need judgment about *which* subtle thing is wrong |
| `vmp`, `dawo`, `artikel`, `adjend`, `ndekl` | any of the three | mechanically simple: swap a preposition, collapse a compound |
| `verdict` (correct sentences) | Sonnet preferred | must be genuinely correct; a wrong row here teaches the model to accept errors |
| rare phenomena (`relpron`, `k2`, `imperativ`, `negation`) | Sonnet | low volume, high judgment |

Keep the verdict balance near **69% fix / 31% ok** (v1's shipped ratio). Too few `ok` rows and the
model invents corrections; too many and it stops correcting. Both failures have happened here.

⚠️ **The delivered ratio is not the requested ratio.** The 2026-08 bulk jobs asked gemma-31B for
65/35 and got **51/49** — the teacher over-produces `ok` rows. Measure the delivered split on every
batch (`check_hard_case_share.py` prints it) and correct at pack time with
`pack_dataset.py --fix-frac`; never assume the manifest's mix survived generation.
