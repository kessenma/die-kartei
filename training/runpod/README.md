# RunPod training runbook

Everything needed to take a packed dataset from this repo to a scored MLX model, plus the traps
that have actually cost money or hours here. Written against the E4B German-tutor runs; the trainer
is env-driven (`MODEL_NAME` / `CHAT_TEMPLATE` / `OUT_PREFIX` / `LORA_R` / …) so it generalises.

**Read [§6 Gotchas](#6-gotchas-that-have-actually-bitten-us) before your first run.** Every entry
there is something that already went wrong, not a hypothetical.

---

## 1. Pick and create the pod

Any ≥24 GB card trains E4B at `MAX_SEQ_LEN=1024`, batch 8. Measured picks:

| GPU | VRAM | $/hr | notes |
|---|---|---|---|
| RTX A6000 | 48 | 0.33 community | cheapest; stock is thin and evaporates |
| **A40** | 48 | 0.44 secure | same Ampere pool, usually actually available |
| A100 SXM | 80 | 1.39 community | ~2× faster; total cost lands ~1.5×, not 4× |
| RTX PRO 6000 / B200 | 96/180 | 1.69+ | ⚠️ Blackwell (sm_120) needs CUDA 12.8+/newer torch — avoid unless you want to debug the stack |

**Set `PUBLIC_KEY` at creation.** Without it the container's sshd never starts and you get
`Connection refused` on the mapped port, with the web-proxy fallback as the only way in
(see [§6.1](#61-ssh-is-dead-unless-you-set-public_key-at-creation)).

```bash
# via MCP: create-pod, or the console. Key fields:
#   imageName        runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404
#   containerDisk    40 GB   (LOCAL — put model outputs here)
#   volume           100 GB @ /workspace   (NETWORK fs — put the HF cache here)
#   ports            22/tcp, 8888/http
#   env.PUBLIC_KEY   <contents of ~/.runpod/ssh/runpodctl-ssh-key.pub>
```

Availability is a **snapshot, not a reservation** — a GPU reporting MEDIUM can fail to create
seconds later. Have a fallback picked before you start.

## 2. Connect

Use **direct** SSH (`ssh.direct.command` from `get-pod`), never the proxy, for anything scripted.
The runpodctl key is at `~/.runpod/ssh/runpodctl-ssh-key`. Always carry the keepalives — they are
the fix for the wedged-SSH incident in `training-v2.md` §3.5:

```bash
SSH="ssh -i $HOME/.runpod/ssh/runpodctl-ssh-key -p <port> \
  -o BatchMode=yes -o ConnectTimeout=10 \
  -o ServerAliveInterval=10 -o ServerAliveCountMax=3"
$SSH root@<ip> 'nvidia-smi --query-gpu=name,memory.total --format=csv,noheader'
```

⚠️ In **zsh** an unquoted `$SSH` does *not* word-split — the whole string becomes one argument to
`-i` and you get a baffling `Identity file ... not accessible`. Use an array, or inline the flags.

## 3. Get the data across, and verify it

```bash
scp -i ~/.runpod/ssh/runpodctl-ssh-key -P <port> \
    runpod/<bundle>.tar.gz root@<ip>:/workspace/
$SSH root@<ip> 'cd /workspace && tar --no-same-owner -xzf <bundle>.tar.gz'
```

`--no-same-owner` matters: `/workspace` is a network filesystem that rejects `chown`, so a plain
`tar -xzf` prints a wall of errors and exits non-zero even though the files extracted fine.

**Always checksum.** A truncated `train.jsonl` trains happily and silently:

```bash
$SSH root@<ip> 'md5sum /workspace/runpod_bundle/train.jsonl'
md5 -q data/packed-.../train.jsonl        # must match
```

## 4. Install

The image's Python is **externally managed** (PEP 668), so `pip install unsloth` fails. Do **not**
reach for `--break-system-packages`: unsloth upgrades torch (2.8.0+cu128 → 2.11.0+cu130 as of
2026-08) and you do not want that landing on the image's CUDA-matched install. Use a venv that
inherits the preinstalled torch:

```bash
$SSH root@<ip> '
  python -m venv --system-site-packages /workspace/venv
  setsid nohup /workspace/venv/bin/pip install unsloth > /workspace/install.log 2>&1 < /dev/null &'
```

Verify before training — the import also confirms the CUDA build actually matches the driver:

```bash
$SSH root@<ip> '/workspace/venv/bin/python -c "
import torch, unsloth
print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"'
```

## 5. Train

**Smoke first.** `EPOCHS=0.003` gives ~17 steps and exercises everything that actually breaks:
model load, chat-template detection, `train_on_responses_only` turn-marker detection, a real
optimizer step. This is worth the ~$0.10 — the July script was written against transformers 4.x and
the current image installs **5.x**.

```bash
$SSH root@<ip> 'cd /root/train && setsid nohup env \
  HF_HOME=/workspace/hf_cache PYTHONUNBUFFERED=1 \
  EPOCHS=0.003 OUT_PREFIX=smoke EVAL_STEPS=5 \
  /workspace/venv/bin/python train_gemma4_e4b.py > /workspace/smoke.log 2>&1 < /dev/null &'
```

Check the smoke log for these four lines; if all are present the stack is good:

```
turn markers: '<|turn>user\n' / '<|turn>model\n'
Removed N out of 44,211 samples ...        ← N must be tiny. Large N = response masking is broken
Trainable parameters = 18,350,080 ...      ← LoRA actually attached
Num examples = 44,210 | Total steps = 17
```

Then the real run. **Work out of the local container disk (`/root/train`), not `/workspace`** —
see [§6.5](#65-push_to_hub_merged-hangs-on-e4b).

```bash
$SSH root@<ip> 'cd /root/train && setsid nohup env \
  HF_HOME=/workspace/hf_cache PYTHONUNBUFFERED=1 \
  EPOCHS=1 BATCH_SIZE=8 GRAD_ACCUM=1 MAX_SEQ_LEN=1024 LORA_R=8 LR=2e-4 \
  EVAL_STEPS=1500 OUT_PREFIX=<name> \
  /workspace/venv/bin/python train_gemma4_e4b.py > /workspace/train.log 2>&1 < /dev/null &'
```

**Size `EVAL_STEPS` against the val set, not out of habit.** v1's val set was 29 rows; the v2
packing made it 2,326, so one eval is 291 batches (~4.5 min). At the old default of 250 that is 22
evals ≈ 100 min of pure evaluation on a 4 h run. Three checkpoints of the loss curve is plenty.

Poll without wedging:

```bash
$SSH root@<ip> 'tail -c 400 /workspace/train.log | tr "\r" "\n" | grep -E "[0-9]+/[0-9]+" | tail -1'
```

## 6. Gotchas that have actually bitten us

### 6.1 SSH is dead unless you set `PUBLIC_KEY` at creation
No `PUBLIC_KEY` → the container never starts sshd → `Connection refused` on the mapped TCP port.
The `ssh.runpod.io` proxy still authenticates, which makes it look like a key problem when it
isn't. Fix: `update-pod` with `env.PUBLIC_KEY`, then **restart** (the port number changes).

### 6.2 The RunPod SSH proxy needs a PTY and hangs on scripted commands
`ssh <id>@ssh.runpod.io '<cmd>'` returns `Your SSH client doesn't support PTY`; adding `-tt` makes
it hang indefinitely instead. It is for interactive use. Use direct SSH for automation.

### 6.3 `/workspace` is a network filesystem
It shows up as `mfs#<region>.runpod.net:9421`. Fine for the HF cache (read-mostly), bad for writing
a 15 GB merged model, and it rejects `chown`. The container disk (`/`, `/root`) is local.

### 6.4 Disk bills while the pod is STOPPED — terminate instead
Real billing rows from July: pod `nrqb8618jv1kz1` charged **$0.61 disk on a day with $0 GPU**, and
`3z6qwqrqdk0wpy` charged **$0.53** the same way. A 120 GB volume runs ≈ $0.40/day doing nothing.
Pull what you need off the pod, then **terminate**.

### 6.5 `push_to_hub_merged` hangs on E4B
Unsloth stalls at `Copying 1 files from cache` — a local copy of the single 15 GB safetensors shard,
measured at **0 bytes moved in 90 s**. Both 10.3 GB E2B pushes worked, so it is shard-size specific,
and the network filesystem makes it worse. **This is what produced `kessenma/gemma4-e4b-german-v2`,
a repo with a tokenizer and no weights.** Leave `HF_REPO`/`HF_TOKEN` unset, write the merge to local
disk, and `scp` it off (~11 MB/s, ~23 min for 15 GB).

### 6.6 Always verify an upload by shard size
The failure above is invisible unless you look — the repo exists, has a model card and a tokenizer,
and 404s nothing. Check the big file explicitly:

```bash
.venv/bin/python -c "
from huggingface_hub import HfApi
for f in HfApi().list_repo_tree('<repo>', recursive=True): print(f.path, getattr(f,'size',None))"
```
`model.safetensors` must be the expected byte count and `model.safetensors.index.json` must exist.
Then re-list **unauthenticated** — a repo that 404s logged-out 404s for the app.

### 6.7 `pgrep -f` matches your own command
`pgrep -f train_gemma4_e4b` run over SSH matches the SSH command string itself and reports the job
as running when it isn't. Use the bracket trick: `pgrep -f "[t]rain_gemma4_e4b"`. Same family as the
`grep -c … || echo 0` bug in `training-v2.md` §3.5 that stopped a healthy pod.

### 6.8 Python buffers stdout when it isn't a TTY
A backgrounded run writes a **0-byte log** for minutes and looks hung. Set `PYTHONUNBUFFERED=1`.
Cross-check with `nvidia-smi` — GPU utilisation is the ground truth, not the log.

### 6.9 The auto-shutdown failsafe has failed three times, in every direction there is
Once it stopped a healthy pod 90 s after arming; once it never fired and idled ~6 h ≈ $3.20; and on
2026-08-16 a stop-at-row-count script **killed the generator but not the pod**, which idled ~5 h ≈
$5.50 — more than the run's actual GPU work cost. The lessons, in order of importance:

1. **Kill the pod, not the process.** The GPU bills until the *pod* dies. Any shutdown path whose
   last line is `kill <pid>` saves nothing.
2. **Gate termination on the data being off the box**, then let the pod terminate itself.
   ⚠️ Measured 2026-08-17: contrary to RunPod folklore, `RUNPOD_POD_ID`/`RUNPOD_API_KEY` are **not**
   injected (community pod, standard pytorch image) — only `runpodctl` itself is preinstalled. Pass
   `env.SELF_POD_ID` and a **Restricted** `env.RUNPOD_API_KEY` (pod-scope only; never the full
   account key on a community host) at creation. The full pattern (generate → md5 → `hf upload` →
   verify remote byte count → self-remove, plus a separate absolute-deadline backstop armed first)
   is scripted in `bakeoff/run_and_die.sh` and documented in `bakeoff/README.md` §4. Upload to HF
   rather than scp — it works while the laptop sleeps, which is exactly when this bites.
3. **Verify from outside that it fired**: `runpodctl pod list` must print an empty table. Every one
   of the three failures would have been caught by this check; none of them was prevented by trust.

If you still hand-roll one: `-o ServerAliveInterval=10 -o ServerAliveCountMax=3`, wrap every poll in
`timeout 60`, and make the deadline a backstop a wedged child cannot block.

### 6.10 Unsloth drops `rope_theta` on Granite merges
Every time. Restore `rope_theta` (`10000000.0`) and `rope_scaling` from
`ibm-granite/granite-3.3-2b-instruct` before converting, or `mlx_lm` refuses.

---

## 7. Get the model out and convert

```bash
scp -r -i ~/.runpod/ssh/runpodctl-ssh-key -P <port> \
    root@<ip>:/root/train/<OUT_PREFIX>-merged ./models/

.venv/bin/python -m mlx_lm convert --hf-path models/<OUT_PREFIX>-merged \
    -q --q-bits 4 --q-group-size 64 --mlx-path models/<name>-4bit
```

If 4-bit quality drops vs fp16: `--q-group-size 32`, then `--quant-predicate mixed_4_6`, then DWQ.

**The `-4bit` repo must contain exactly ONE `.safetensors`.** MLX Swift merges every `*.safetensors`
in the snapshot recursively, so a stray `lora/adapter_model.safetensors` (PEFT `base_model.*` keys)
breaks loading with `Unhandled keys ["base_model"] in Gemma4Model`:

```bash
.venv/bin/python -c "from huggingface_hub import HfApi; HfApi().delete_folder(
    repo_id='<you>/<repo>', path_in_repo='lora',
    commit_message='remove LoRA adapters from inference repo')"
```

## 8. Score it — on the CORE suite, not just the holdout

**This is the step that matters most, and getting it wrong shipped a worse model.** E4B v2 scored
91% on the v2 holdout and was called a ship; on the core suite it had dropped 90% → 70%, *below the
untuned base*. Score all three, always guarded:

```bash
for EV in grammar_eval_v0:guarded-v0 \
          grammar_eval_v1_extra:guarded-v1ext \
          grammar_eval_v2_holdout:guarded-v2; do
  f=${EV%%:*}; t=${EV##*:}
  .venv/bin/python scripts/run_baseline_eval.py --model models/<name>-4bit \
      --eval-file data/eval/${f}.json --tag $t --app-guard
done
.venv/bin/python scripts/behavior_metrics.py --app-guard \
    results/guarded-v0_<name>-4bit.json results/guarded-v1ext_<name>-4bit.json
```

Bars to clear (all guarded, from `MODEL_SCOREBOARD.md`):

| | core v0 | holdout v2 | miss | false-corr |
|---|---|---|---|---|
| stock E4B — below this the tune is harmful | 48/60 (80%) | 64/82 (78%) | 16% | 6% |
| **E4B v1, the incumbent — the bar** | **54/60 (90%)** | 70/82 (85%) | **9%** | 6% |
| E4B v2 — shipped-then-retracted | 42/60 (70%) | 75/82 (91%) | 28% | 3% |

**Never quote a raw number.** `--app-guard` mirrors `ConversationPrompts.parseCorrection`; without
it a model that answers `OK\nFIX:…` scores as correct while the app shows the learner nothing. That
artifact put a fictional 58% for Gemma 3 1B (really 33%) in shipped copy for weeks.

Regenerate every in-app model's numbers from saved responses (free, no GPU):

```bash
.venv/bin/python scripts/rescore_app_models.py
```

## 9. Terminate

```bash
# MCP: delete-pod, or: runpodctl remove pod <id>. NOT "stop" — see §6.4.
runpodctl pod list        # then ALWAYS this — must print an empty table (§6.9)
```

For unattended generation runs, prefer the self-terminating launch in `bakeoff/README.md` §4 so
this step happens without you; the `pod list` check afterwards is still mandatory.

### 6.11 pip's torch build must match the HOST driver, which varies pod-to-pod
`pip install unsloth` upgrades torch and picks the newest CUDA build (cu130 as of 2026-08). Whether
that build *runs* depends on the **host driver** the scheduler hands you, which differs between pods
on the **same image**: an A100 host reporting CUDA 13.2 ran cu130 fine; the next day's L40S host
reported 12.8 and torch said `The NVIDIA driver on your system is too old (found version 12080)` —
surfacing as unsloth's misleading "cannot find any torch accelerator? You need a GPU." Fix, in order:

```bash
/root/venv/bin/pip install --force-reinstall "torch==<same version>" \
    --index-url https://download.pytorch.org/whl/cu128
/root/venv/bin/pip install --force-reinstall --no-deps --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cu128 "torchvision==<its version>"
```

torchvision fails SEPARATELY after torch is fixed (`operator torchvision::nms does not exist`) —
its compiled ops are also CUDA-build-specific. **Always run the import check (§4) before launching
anything**; both failures are import-time and cost a minute, not a training run.

### 6.12 pgrep's bracket trick does not protect WRAPPER scripts that mention the process name
`pgrep -f "[t]rain_x"` stops the *pgrep* from matching itself — but a `bash -c` wrapper whose text
contains the plain string `train_x` (a launch line, a grep in a checklist) matches forever. Two such
wrappers each saw the other and deadlocked a launch for several minutes while the GPU sat idle
(2026-08-17). Fixes, best first: gate stages on **sentinel files** (`PIPELINE_DONE`/`_FAILED`)
inside one sequential script, no process matching at all; or anchor the pattern to the process's
full cmdline end: `pgrep -f "python train_x\.py$"`.
