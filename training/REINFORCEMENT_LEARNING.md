# Reinforcement learning — GRPO on the German tutor

The round doc: plan, worklog, results, and the article draft in **one file**, so the whole round can
be lifted into [`ARTICLE.md`](ARTICLE.md) (and the website) when it lands. Same role
[`training-v3.md`](training-v3.md) played for v3/v4.

> **Status 2026-09-06 04:27: round parked. E4B rl1 = v4 on every suite, quantised or not (C.3, C.5); $7.05 spent.**
> The update never reached the greedy mode or the eval items' sampling distribution. Next lever if resumed:
> DPO on the 873 verdict-error pairs (Part A §9 row 6a, ~$1.50), then rl2 only if that moves misses without FC.
> Steps 0–3 done: v3 frozen (C.1), bias control a seesaw (C.2), reward tested, pool mined (1,723 prompts),
> seven smoke runs (Part B — three Unsloth-on-Gemma-4 traps found and fixed). Next: retrieve, convert, score → C.3.

Companions: [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md) (every number ends up there),
[`training-v3.md`](training-v3.md) §9 (the v4 generation this starts from),
[`DATA_GAP_PLAN.md`](DATA_GAP_PLAN.md) (the SFT data lever, still valid and independent),
[`runpod/README.md`](runpod/README.md) (pod hygiene — all of §6 applies unchanged).

## How this doc is kept

| part | what goes in it | when |
|---|---|---|
| **A — Plan** | the current plan. Edited **in place** when a step changes a decision; never a diary | when a decision changes |
| **B — Worklog** | dated entries, one per step of A §9. What was run, the exact command, the numbers with the `results/` file they came from, the cost, what was decided | at the end of every step, before the pod is terminated |
| **C — Results** | the tables. Pending cells say *pending*; a filled cell names its source file | as each table fills |
| **D — Article notes** | the story, in the article's first-person voice, written as it happens — not reconstructed at the end | after every step that changed the picture |

Rules, learned from the earlier rounds: quote **guarded** numbers only; **score core first**; a
number without a `results/` filename next to it does not go in Part C; and `runpodctl pod list`
must print an empty table at the end of every Part B entry that touched a GPU.

---

# Part A — The plan

## 0. Verdict in one paragraph

Yes, RL is the right next lever — but for a narrower reason than "the next step after fine-tuning".
The hero model has stopped moving under SFT: E4B v1 181/203 → v4 182/203 with 30× more data and a
better teacher (McNemar p = 1.00). What is left is not knowledge, it is **verdict calibration**: of
v4's 16 correction failures across all three suites, **12 are a bare `OK` on a real error** (miss
16%), and its false-correction rate is already 1/32. SFT cannot target that directly — it can only
teach the teacher's fix/ok prior, and `--fix-frac` 0.70 vs 0.80 is the bluntest possible knob. RL
with a programmatic reward can, because this task is *verifiable*: every training row carries a gold
verdict and a gold fix, and the eval scorer (`expect_ok` / `require_any` / `forbid_any`) is already
code. That is the RLVR setting (math/code-style rewards), not the vague-preference setting, and it
is where GRPO reliably works. Completions are tiny (`OK` is one token; `FIX`+`WHY` ≈ 40), so the
usual GRPO cost — generation — is cheap even without vLLM. **Expected spend for the first full run:
~$5. Budget $15 including smoke tests.** The real risk is not the training run; it is that the
203-item eval cannot certify a win of the size RL will plausibly produce (§5). Fix that first.

## 1. The evidence that SFT has plateaued (E4B)

All guarded, `results/guarded-*_gemma4-e4b-german-{tutor,v4}-4bit.json`.

| model | core | ext | holdout | /203 | FC | miss |
|---|---|---|---|---|---|---|
| v1 (1,403 rows, Sonnet) | 54 | 57 | 70 | 181 | 6% | 9% |
| v4 (42,841 rows, 31B teacher) | 51 | 56 | 75 | 182 | 3% | 16% |

Decomposition of v4's 21 failures by *kind*:

| kind | count | RL can touch it? |
|---|---:|---|
| bare `OK` on an error item (miss) | **12** | ✅ this is the target |
| `FIX` with the wrong correction | 4 | ✅ partially (fix-quality reward) |
| cloze items (`*-z*`) | 5 | ❌ different task, not in the app's correction path |

Eight of the 12 misses are phenomena the model demonstrably knows (v1 fixed `sep-e3`, `refl-e7`,
`im-e2`… on the same base): `sep-e3 sep-e8 refl-e7 dawo-e7 aux-e3 k2-e1 k2-e3 im-e2 im-e3
v2-sep-e5 v2-refl-e4 v2-wechsel-e1`. The knowledge is there; the threshold moved. That is exactly
what the v2/v3 rounds showed from the other direction (an OK-heavy corpus tripled the miss rate).

**Same story, smaller models.** E2B v5 "strict" was rejected because it could not hold strict
error-catching and calibrated permissiveness at once (miss 23% / FC 3%, bar was miss ≤ 15%).
Granite-4.1 v4 sits at miss 25% / FC 9%. All three are calibration failures on top of a base that
already knows the grammar — the profile RL is built for. Substrate rule still holds: RL re-weights
behaviour the model can already produce; it does not buy German (so Granite-3.3's 43% miss is
only partly reachable).

## 2. Method: GRPO with a verifiable reward, not DPO

| | DPO (offline pairs) | **GRPO (online, reward function)** |
|---|---|---|
| needs | chosen/rejected pairs | prompts + a reward function |
| what it optimises | "gold beats my old mistake" once | correct verdict **and** correct fix **and** format, jointly, on-policy |
| Gemma 4 support | ✅ Unsloth | ✅ Unsloth, with `fast_inference=False` (vLLM cannot load Gemma 4 for RL; Unsloth docs say this explicitly) |
| cost driver | none (no generation) | generation — but completions are ≤ ~60 tokens here |
| verdict | fallback | **primary** |

The one thing that normally makes GRPO expensive (long rollouts through vLLM) does not apply: the
output is one word or three short lines. Without vLLM, HF-generate on a 4-bit E4B at 64 completions
× ≤96 tokens is seconds per step. DPO stays as the fallback if the Unsloth GRPO + Gemma 4 stack
misbehaves in the smoke test — and the hard-prompt mining in §4 produces DPO pairs as a by-product
(gold = chosen, the model's own wrong sample = rejected), so the fallback costs nothing extra.

**Why not just a decode-time logit bias toward `FIX`?** `GEMMA_E2B_FINETUNING.md` A3 proposed it,
and it is a legitimate control: the app's echo guard makes over-FIXing cheap. §5 runs it as a
zero-GPU baseline. If a bias alone takes E4B from miss 16% → ≤ 9% with FC ≤ 6%, RL is unnecessary
for E4B and this plan moves to E2B. Expectation: it will trade FC for miss roughly 1:1, because a
bias cannot tell a confident `OK` from an uncertain one — that discrimination is what RL learns.

## 3. Reward design

One composite function (so the format gate can zero everything), components logged separately via
`log_metric`. Gold per prompt comes from dataset columns forwarded as kwargs: `student`, `verdict`,
`fix`. **Reuse `apply_app_guard`, `strip_channels`, `_guard_normalize` from
`scripts/run_baseline_eval.py`** so the reward sees exactly what the app shows.

```
strip channels; apply the app guard (echo-FIX → OK)
format gate:   exactly "OK", or "FIX: …\nWHY: …" and nothing else, WHY ≤ 18 words
               → fail: reward = -1.0, stop
gold = ok:     model OK  → +1.0            model FIX (real change) → -1.0     [false correction]
gold = fix:    model OK  → -1.0 [miss]     model FIX → +0.3 + 0.7 × fix_score
why:           +0.1 if WHY is 3–18 words and mostly ASCII (English), else 0
```

`fix_score ∈ [0, 1]`, derived from the gold automatically — no hand labels:

- normalised candidate == normalised gold → **1.0**
- else word-level diff. `gold_added` = words in gold not in student, `gold_removed` = the
  reverse; same for the candidate. `coverage` = mean of (|gold_added ∩ cand_added| / |gold_added|,
  |gold_removed ∩ cand_removed| / |gold_removed|). `excess` = candidate edits outside the gold
  edit. `fix_score = coverage × max(0, 1 − 0.25 × excess)`.
- This is `require_any` / `forbid_any` generated from the diff, plus a penalty for the **evasive
  rewrite** (`Ich wasche mich die Hände` → *"Ich wasche meine Hände"*, which dodges the dative
  reflexive) that the dataset was built to remove.

**Known gap, accepted for v1:** a *valid alternative* fix scores ~0. Audit: after the run, take
200 completions with `verdict correct, fix_score < 0.3`, run them through LanguageTool + a read.
If more than ~20% are legitimate alternatives, add LT as a secondary path (too slow for the inner
loop at ~80 ms/sentence × 64 completions/step; fine post-hoc).

**Reward weights are the calibration lever.** v1 runs symmetric (miss = FC = −1.0). Read FC and
miss off the eval; if FC rises past 6%, raise the FC penalty to −1.5 and rerun from the same
checkpoint — that is a $3 adjustment, not a new round.

**Reward-hacking watch, logged every 25 steps:** format-reward mean (must stay ≈ 1.0), mean
completion length (drift = padding), fraction of `FIX` on gold-ok prompts, and 8 raw samples. TRL
logs `frac_reward_zero_std` — the share of groups where all 8 completions scored the same. Above
~0.7 the pool is too easy and the run is learning nothing (§4 fixes that).

Unit-test the reward against the eval suites before renting anything: every gold fix must score
max; every echo must land in the miss branch; a known evasive rewrite must score < 0.5. The 203
items double as the test fixture — never as training prompts.

## 4. Prompt pool

Use the **raw validated rows** (structured `student` / `verdict` / `fix`), not the packed
messages: `data/generated_gemma31b/bulk_live.valid.jsonl` (4,668),
`data/generated/*.valid.jsonl` (1,865, the v1-era Sonnet rows), and the 26B salvage for
`vmp`/`dawo` only (10,139). Render the prompt with `scripts/app_prompts.py`
(`correction_system` / `correction_user`) so it is byte-identical to what the app sends.
Eval overlap is already quarantined by `validate_data.py`. ~~Exclude the packed-v4 val split too.~~
*(2026-09-05: not excluded — the family-wise split put all `k2`/`adjend` fix rows in val; see Part B.)*

| rule | value | why |
|---|---|---|
| verdict balance | **50/50** ok/fix | RL does not need the SFT prior; it needs both failure modes present so both penalties fire |
| per-phenomenon cap | ≤ 400 | `vmp`+`dawo` are 66% of the corpus; the misses are in the tail |
| hard-negative OKs | +200–300, Sonnet-written | correct sentences that *look* like classic errors (`Ich freue mich auf dich`, `Er hat sich das Bein gebrochen`). Without them a verdict reward drifts toward FIX |
| no `HINT:` rows in v1 | — | keep the completion short and the reward simple; nudgeMe is a follow-up (§9) |

**Hard-prompt mining (Mac, MLX, ~40 min, $0).** Run the v4 4-bit model over the candidate pool at
temperature 0.8, 4 samples each. Keep: everything scored 0/4 (wrong), everything 1–3/4 (uncertain —
these are the groups with reward variance, i.e. the ones GRPO learns from), and a 20% slice of 4/4
(anti-forgetting). Target **2,500–4,000 prompts**. This step is also the DPO-pair generator (§2).

## 5. Step 0 — fix the measurement before spending on training

**The 203-item eval cannot see the win.** v4 has 12 reachable misses. A good RL run that fixes
half of them is +6 items ≈ 3%. This repo's own noise floor is ±2 on 82; a +6 move with 8 gained /
2 lost is McNemar p ≈ 0.11 — "directional, not conclusive", the phrase already used for
granite-4.1 vs 3.3. Running RL against the current eval risks a $5 answer of "maybe".

Build **`data/eval/grammar_eval_v3.json`** before the run and freeze it:

- ~300 correction items, **50/50** ok/fix, all 14 phenomena, ≥ 100 hard-negative OKs
- same item shape as v0/v1/v2 (`expect_ok` / `require_any` / `forbid_any`) so every existing
  script works unchanged; Sonnet-written, hand-checked, tagged `guarded-v3`
- never in the pool, never in the reward, added to `validate_data.py`'s quarantine set
- score **v1, v4, stock E4B, E2B v1/v5, granite-4.1 v4** on it first, so the RL delta has a baseline
  measured the same day

With 500 items in hand a 5-point move is significant. Cost: ~2 h of Sonnet subagent time, $0 GPU.

**Zero-cost control, same afternoon:** the logit-bias baseline from §2 on the v4 4-bit model
(bias the first-token `FIX` vs `OK` logit in `mlx_lm` sampling, sweep 3 values, score all suites
guarded). Record it in the scoreboard as `v4+bias`. It is the number RL has to beat.

## 6. Starting checkpoint and stack

**Policy init: E4B v4** — the best current model and the one with FC already at 3%. Two ways to
load it; the choice is forced by the KL term:

| | load | reference model for KL | verdict |
|---|---|---|---|
| A | base 4-bit + continue `models/gemma4-e4b-german-v4-lora` (r=8, base `unsloth/gemma-4-e4b-it-unsloth-bnb-4bit`) | adapter-disabled = **stock E4B**, wrong | ❌ only if β = 0 |
| **B** | `kessenma/gemma4-e4b-german-v4-fp16` (public, byte-verified) loaded `load_in_4bit=True` + **fresh LoRA r=16** | adapter-disabled = **v4**, right | ✅ |

Use B with **β = 0.02**. TRL's default is β = 0 (no reference model), which is fine for math but
not here: the RL prompts are correction-only, so nothing in the reward protects the conversation
task (11,791 rows of naturalness v3 proved survives SFT). A small KL to v4 plus LoRA plus a short
run bounds that drift; the naturalness proxies (`naturalness_metrics.py`, `conversation_v0.json`)
confirm it after. Note B re-quantises the merged fp16, but that is already the path that produced
the measured `gemma4-e4b-german-v4-4bit` (182/203), so the control exists.

Stack, per the Unsloth Gemma 4 page and the TRL GRPO docs (checked 2026-09-05):

- `FastModel.from_pretrained(..., load_in_4bit=True, fast_inference=False)` — vLLM cannot load
  Gemma 4 for RL (v0.27.1's per-layer `head_dim` failure is the same one that blocked the 31B
  teacher in vLLM). Unsloth documents Gemma 4 RL as working with `fast_inference=False`; E2B RL
  fits in 9 GB.
- `finetune_vision_layers=False`, language/attention/MLP only — same as the SFT script.
- `GRPOTrainer(model, processing_class=tokenizer, reward_funcs=[tutor_reward], ...)`; dataset
  columns `prompt` (messages, system + user) plus `student`, `verdict`, `fix` forwarded to the
  reward as kwargs; completions arrive as `[{"role":"assistant","content":…}]`.
- Optional speedup if the image's transformers ≥ 5.8: `use_transformers_continuous_batching=True`
  with `max_memory_percent` ≈ 0.4. Try it in the smoke run, not the real one.
- Same image and venv recipe as `runpod/README.md` §4; the §6.11 torch/driver check first.

## 7. The run

```
per_device_train_batch_size=16  gradient_accumulation_steps=4  num_generations=8
  → 64 completions / 8 prompts per optimizer step
max_prompt_length=512   max_completion_length=80 (was 96; Part B)   mask_truncated_completions=True
temperature=1.0   loss_type="dapo" (TRL default)   scale_rewards="group"
learning_rate=5e-6 (LoRA-RL range; TRL's 1e-6 default is for full FT)   warmup_ratio=0.1
beta=0.02   LORA_R=16 alpha=16   optim="adamw_8bit"   seed=7
LOAD_4BIT=0 (bf16 LoRA — 4-bit measured 173 s/step, Part B)   GRAD_CKPT=none (unsloth ckpt breaks on Gemma 4 E under GRPO)
3,000 prompts × 2 epochs ≈ 750 steps.  Save every 150.
```

Time and cost, estimated (not measured — the smoke run measures it):

| pod | $/hr | s/step est. | 750 steps | total |
|---|---|---|---|---|
| **A100 SXM 80 GB** (community) | 1.39 | ~12–15 | ~2.5–3 h | **~$4–5** |
| A40 48 GB (secure) | 0.49 | ~25–30 | ~5.5–6 h | ~$3 |

A40 is cheaper in dollars and slower in wall-clock; either is fine. Availability today: A40 HIGH,
A100 SXM MEDIUM. No pods are currently running (checked).

**Smoke first (`max_steps=10`, ~$0.20), and read these lines before the real run:**

1. rendered prompt ends in `<|turn>model\n` with **no** `<|channel>` — thinking must be off, as
   in the eval (`enable_thinking=False`); the reward strips channels regardless
2. reward components on the 10 steps are non-degenerate: format mean ≈ 1.0, `frac_reward_zero_std`
   < 0.7, at least one group with both a miss and a catch
3. trainable params ≈ the r=16 LoRA, not 0 and not the whole model
4. s/step and peak VRAM — size the real run from these, not from the table above
5. `runpodctl pod list` empty afterwards (§6.9 of the runbook: the failsafe has failed three times)

Then the real run, `setsid nohup … PYTHONUNBUFFERED=1`, deadline backstop armed first, outputs on
the local container disk, LoRA + merged fp16 pulled by `scp` (never `push_to_hub_merged` on E4B —
§6.5). Convert with the standard `mlx_lm convert -q --q-bits 4 --q-group-size 64`.

## 7b. Pod runbook — copy-paste, written before the first GPU minute

Everything below the local line is the *only* GPU work in the round. Pre-flight done 2026-09-05:
`kessenma/gemma4-e4b-german-v4-fp16` serves `model.safetensors` = **14.89 GB logged-out** (the
policy init the pod downloads), `~/.runpod/ssh/runpodctl-ssh-key` present, `runpodctl 2.7.2`,
`runpodctl pod list` → `[]`.

```bash
# ---- local (Mac) ----------------------------------------------------------------------------
cd training
.venv/bin/python scripts/test_rl_rewards.py                 # 13/13 — the reward is what ships
bash runpod/make_grpo_bundle.sh                             # runpod/gemma4_grpo_runpod.tar.gz + md5
runpodctl pod list                                          # must print []

# ---- pod --------------------------------------------------------------------------------------
# create-pod (MCP) or console.  Smoke: A40 48 GB secure ($0.49).  Real run: A100 SXM 80 GB ($1.39)
#   imageName      runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404
#   containerDisk  60 GB (local; the 15 GB fp16 download + merged output live here)
#   volume         100 GB @ /workspace (HF cache only)
#   ports          22/tcp
#   env.PUBLIC_KEY   <~/.runpod/ssh/runpodctl-ssh-key.pub>     REQUIRED or sshd never starts (§6.1)
#   env.HF_HOME      /workspace/hf_cache
#   optional self-termination: env.SELF_POD_ID + a RESTRICTED env.RUNPOD_API_KEY (bakeoff README §4)
SSHK=~/.runpod/ssh/runpodctl-ssh-key; PORT=<port>; IP=<ip>
S=(ssh -i $SSHK -p $PORT -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 root@$IP)
"${S[@]}" 'nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader'

scp -i $SSHK -P $PORT runpod/gemma4_grpo_runpod.tar.gz root@$IP:/workspace/
"${S[@]}" 'cd /workspace && tar --no-same-owner -xzf gemma4_grpo_runpod.tar.gz && mkdir -p /root/train \
           && cp runpod_bundle/* /root/train/ && cd /root/train && md5sum train.jsonl && cat train.jsonl.md5'
#   the two md5 lines must match (§3 of the runbook: a truncated pool trains happily)

"${S[@]}" 'python -m venv --system-site-packages /workspace/venv && \
           /workspace/venv/bin/pip install -q unsloth > /workspace/install.log 2>&1; tail -2 /workspace/install.log'
"${S[@]}" '/workspace/venv/bin/python -c "import torch, unsloth, trl; print(torch.__version__, torch.cuda.is_available(), trl.__version__)"'
#   if torch complains about the driver: runbook §6.11 (force-reinstall the cu128 wheel)

# SMOKE — 10 steps, ~$0.20.  Read the five lines of Part A §7 before anything else.
"${S[@]}" 'cd /root/train && nohup env HF_HOME=/workspace/hf_cache PYTHONUNBUFFERED=1 SMOKE=1 \
           /workspace/venv/bin/python train_grpo.py > /workspace/smoke.log 2>&1 < /dev/null &'
"${S[@]}" 'grep -E "rendered prompt tail|trainable|reward on gold|frac_reward_zero_std|s/step|peak VRAM|Traceback|Error" /workspace/smoke.log'

# REAL RUN — deadline backstop FIRST (a wedged trainer cannot block it), then the run
"${S[@]}" 'nohup bash -c "sleep 21600; runpodctl remove pod \$SELF_POD_ID" > /workspace/deadline.log 2>&1 < /dev/null &'   # only with SELF_POD_ID
"${S[@]}" 'cd /root/train && nohup env HF_HOME=/workspace/hf_cache PYTHONUNBUFFERED=1 \
           EPOCHS=2 BATCH_SIZE=16 GRAD_ACCUM=4 NUM_GEN=8 LR=5e-6 BETA=0.02 LORA_R=16 LOAD_4BIT=0 GRAD_CKPT=none \
           HF_HUB_OFFLINE=1 OUT_PREFIX=gemma4-e4b-german-rl1 \
           /workspace/venv/bin/python train_grpo.py > /workspace/train.log 2>&1 < /dev/null &'
"${S[@]}" 'tail -c 600 /workspace/train.log | tr "\r" "\n" | grep -E "[0-9]+/[0-9]+|reward" | tail -2; nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader'
#   OOM on an A40 → BATCH_SIZE=8 GRAD_ACCUM=8 (same 64 completions/step).  A100 should not need it.

# OUT — LoRA (small) + merged fp16 (~15 GB, ~25 min at 11 MB/s).  Never push_to_hub_merged on E4B (§6.5)
scp -r -i $SSHK -P $PORT root@$IP:/root/train/gemma4-e4b-german-rl1-lora    models/
scp -r -i $SSHK -P $PORT root@$IP:/root/train/gemma4-e4b-german-rl1-merged  models/
# delete-pod (MCP) or: runpodctl remove pod <id>      then, every time:
runpodctl pod list                                          # must print []

# ---- local again ------------------------------------------------------------------------------
.venv/bin/python -m mlx_lm convert --hf-path models/gemma4-e4b-german-rl1-merged -q --q-bits 4 \
    --q-group-size 64 --mlx-path models/gemma4-e4b-german-rl1-4bit
for EV in grammar_eval_v0:guarded-v0 grammar_eval_v1_extra:guarded-v1ext \
          grammar_eval_v2_holdout:guarded-v2 grammar_eval_v3:guarded-v3; do
  f=${EV%%:*}; t=${EV##*:}
  .venv/bin/python scripts/run_baseline_eval.py --model models/gemma4-e4b-german-rl1-4bit \
      --eval-file data/eval/${f}.json --tag $t --app-guard
done
.venv/bin/python scripts/behavior_metrics.py --app-guard results/guarded-v0_gemma4-e4b-german-rl1-4bit.json results/guarded-v1ext_gemma4-e4b-german-rl1-4bit.json
.venv/bin/python scripts/behavior_metrics.py --app-guard --eval-file data/eval/grammar_eval_v3.json results/guarded-v3_gemma4-e4b-german-rl1-4bit.json
.venv/bin/python scripts/run_conversation_eval.py --model models/gemma4-e4b-german-rl1-4bit   # naturalness proxies
# then: C.3 (all columns), McNemar vs v4 on every suite, per-phenomenon diff, the §3 audit of low-fix_score catches
```

Budget guardrails: the smoke run ends by itself (`SMOKE=1` → 10 steps); the real run is bounded by
`EPOCHS=2` (~750 steps) *and* the 6 h deadline backstop. Delete the pod as soon as the two `scp`s
finish — the merged fp16 on the container disk is the only copy until then.

## 8. Ship bars — pre-registered, guarded, all suites

| metric | bar | why |
|---|---|---|
| core v0 | **≥ 54/60** | beat v4's 51, match v1 |
| holdout v2 | ≥ 75/82 | hold v4 |
| ext v1 | ≥ 56/61 | hold v4 |
| **new v3** | **beat v4 by ≥ 5 pts, McNemar p < 0.05** | the suite built to see this |
| miss | **≤ 9%** | v1's number — the whole point |
| false corrections | ≤ 6% | the trust-killer; RL that buys miss with FC has failed |
| format errors | 0 | |
| naturalness | particles ≥ 10 /100 tok, follow-ups ≥ 0.80, repeat-4gram ≤ 0.15 | within noise of v4 (12.4 / 0.82 / 0.10) — the KL term's job |
| beats `v4+bias` | on miss at equal FC | otherwise ship the bias, not the model |

Judge core and miss together, as always. A model that "wins" by never saying OK will show up as
FC — that is what the symmetric penalty and the hard-negative OKs are for.

## 9. Order of operations, budget, and where each step gets written down

Decision 2026-09-05: **E4B first.** E2B and Granite wait for the E4B result.

Every step ends with a dated entry in Part B of this doc. Numbers in an entry come from a file in
`results/` (name it) or from RunPod billing (`get-billing`), never from memory. If a step changes a
decision in Part A, edit Part A in place and note the change in the Part B entry — the plan should
always read as current, the worklog as history.

| # | step | gate | cost | record in |
|---|---|---|---|---|
| 0 | `grammar_eval_v3.json` (300 items), score every in-app model on it | frozen before any RL | $0, ~2 h | Part B entry; Part C table C.1; `MODEL_SCOREBOARD.md` v3 column |
| 0b | logit-bias control on v4, record `v4+bias` | — | $0, ~1 h | Part B; C.2; scoreboard row `v4+bias` |
| 1 | `scripts/rl_rewards.py` + unit tests against the 203 eval items | all fixtures pass | $0 | Part B (test counts, any reward-design change → Part A §3) |
| 2 | `scripts/build_rl_pool.py` + hard-prompt mining on the Mac | 2,500–4,000 prompts, 50/50, `frac_zero_std` est. < 0.7 | $0, ~1 h | Part B; `data/rl_pool_v1/meta.json` |
| 3 | `runpod/train_grpo.py`, smoke 10 steps on A40 | the 5 smoke lines (§7) | ~$0.20 | Part B (paste the 5 lines, s/step, peak VRAM); C.4 cost ledger |
| 4 | E4B GRPO, 750 steps | reward curve rising by ~300 steps | ~$5 | Part B; keep `train.log`; C.4 |
| 5 | convert, score all four suites + naturalness, compare to `v4+bias` | §8 bars | $0 | Part B; **C.3**; scoreboard row `E4B rl1`; Part D article notes |
| 6a | **DPO on verdict-error pairs first** (`data/rl_pool_v1/dpo_verdict_pairs.jsonl`, 873 pairs, gold vs the model's own wrong verdict): Unsloth `DPOTrainer`, bf16 LoRA r=16, LR 5e-6–1e-5, β 0.1, 2–3 epochs; score bf16 then 4-bit (`scripts/eval_unquantized_gemma4.py`) | tests the round's hypothesis (verdict update without the FC seesaw) offline, no generation, no stalls | ≈ $1.50 (A40) or $0 (mlx-tune QLoRA, untested stack) | Part B; C.3 row `E4B dpo1` |
| 6b | **rl2** only if 6a moves misses without FC: same GRPO stack, `LR=2e-5`, `EPOCHS=2`, `BETA=0.01`; stalls diagnosed on an A40 smoke first | C.5: rl1's update was never there, not erased — a bigger step is necessary, generalisation from pool to eval prompts unproven | ~$7 | Part B; C.3 row `E4B rl2` |
| 7 | **E2B** from v1 or v5, same pool/reward; bar = 171 + miss ≤ 15% (pre-registered in v3 §9.2) | only after 5 | ~$3 | new C table |
| 8 | **granite-4.1-3b** from v4, r=32; try `fast_inference=True` (dense, vLLM-supported); restore `rope_theta` on merge (§6.10) | only after 5 | ~$3 | new C table |

Steps 0–5 are the decision: **≈ $6 and two evenings.** Total for all three models ≈ **$12–15**, in
line with the v4 sweep.

**E2B may be the more informative run.** It has the larger reachable headroom (16 misses at v5),
a crisp pre-registered bar that SFT could not meet, and the failure is *exactly* "can't hold both
sides of the verdict at once" — the thing a joint reward optimises. If E4B lands at "directional",
run E2B before concluding anything about RL.

## 10. Follow-ups, deliberately out of v1 scope

- **nudgeMe `HINT:` prompts** — 2,791 corpus rows carry hints; `validate_data.leaks_answer()` is
  already a reward-shaped check (hint must not contain the supplied word). Add as a second reward
  term once the base run works.
- **Conversation turns** — no verifiable reward exists; a judge-model reward (dense 31B) is the
  `DATA_V2_DISTILL_PLAN.md` Phase 5 idea and a different project.
- **Variety** (`DIALECT_EVAL.md`) — an `OK` reward on Austrian/Swiss-standard sentences would
  directly counter the fine-tune's Bundesdeutsch drift. Cheap to add to the pool once the AT/CH
  items exist; note it here so it is not forgotten.

## 11. Files this round will create

| file | role |
|---|---|
| `data/eval/grammar_eval_v3.json` | the suite that can see the win (§5) |
| `scripts/rl_rewards.py` | composite reward + `pytest` fixtures from the eval suites (§3) |
| `scripts/build_rl_pool.py` | pool + hard-prompt mining, writes `data/rl_pool_v1/{train,meta}` (§4) |
| `runpod/train_grpo.py` | env-driven like `train_gemma4_e4b.py`; `MODEL_NAME`, `POOL`, `BETA`, `MAX_STEPS` |
| `runpod/gemma4_grpo_runpod.tar.gz` | bundle: script + pool + rewards + `run_baseline_eval.py` (imported by the reward) |
| `MODEL_SCOREBOARD.md` | rows for `v4+bias`, `E4B rl1`, and the v3 column for every in-app model |
| this doc, Parts B–D | the worklog, the result tables, and the article draft — one file, so the round can be lifted into `ARTICLE.md` whole |

---

# Part B — Worklog

### 2026-09-05 — plan agreed, E4B first

Read every round doc, the v4 scoreboard block, the per-item failure lists
(`results/guarded-{v0,v1ext,v2}_gemma4-e4b-german-v4-4bit.json`) and the HF account
(19 model repos, 4 datasets; `…-v4-fp16` public and byte-verified — the RL policy init).
Checked the stack: Unsloth's Gemma 4 page says RL works with `fast_inference=False`; vLLM 0.27.1
cannot load Gemma 4 (per-layer `head_dim`), fixed only in 0.27.2rc0 — irrelevant here since Unsloth
RL does not go through vLLM for this family. TRL defaults today: `beta=0.0`, `loss_type="dapo"`,
`num_generations=8`, `lr=1e-6`. RunPod: no pods running; A40 HIGH at $0.49 secure, A100 SXM
MEDIUM at $1.39 community.

Decisions: GRPO over DPO (§2); composite reward with symmetric penalties (§3); init from v4-fp16
with a fresh LoRA and β = 0.02 (§6); **build a 300-item eval before spending anything** (§5).
Cost so far: $0.

### 2026-09-05 — step 0: the v3 suite, the reward, the pool (no GPU)

**`data/eval/grammar_eval_v3.json` built and frozen** by `scripts/build_eval_v3.py`: 300 correction
items, 150 error / 150 ok, 14 phenomena (12+12 for the four core ones, 10–11 each for the rest),
93 of the 150 OK items are designed hard negatives. Every error item carries `gold_fix`. The
builder's self-checks are hard failures: an echo of the input must fail the item's own criteria and
be caught by `forbid_any`; the gold fix must pass through the real scorer; no exact or Jaccard ≥ 0.6
overlap with v0/v1/v2 or with any of the 37,579 `student`/`fix` sentences in the validated corpus.
First draft failed 113 of those checks (9 weak-noun forbids that were substrings of the gold, ~100
corpus collisions — textbook sentences are dense in a 17k-row corpus); every flagged item was
rewritten with more specific lexical material until the checker was clean. LanguageTool over all
150 OK inputs + 150 gold fixes: 1 flag (`Recht hat` vs the recommended `recht hat`; scoring is
case-insensitive, left as is). LT sees 37/150 of the error inputs — the other 113 are exactly the
class of error LT is blind to (CLAUDE.md lesson 2), which is the point of the suite.

**`scripts/rl_rewards.py`** — the composite reward of Part A §3, one function in the TRL signature,
reusing `apply_app_guard` / `strip_channels` from the eval script so it sees what the app shows.
One addition to §3: **contractions are expanded before diffing** (`am` = `an dem`, `ins` = `in das`,
…), so "am Kurs" and "an dem Kurs" are the same edit — this removes a whole class of false
"alternative fix" penalties. **`scripts/test_rl_rewards.py`: 13/13 pass** on the 300 v3 items:
gold fix = max (1.1) on all 150 error items, echo = miss on all 150, bare OK = ±1 as expected,
malformed variants (preamble, `OK`+`FIX`, missing WHY, unrequested HINT, trailing chatter) = −1,
the evasive rewrite (`wasche mich die Hände` → `wasche meine Hände`) scores 0.475 vs 1.1 gold,
a valid alternative (`unter` vs `an Kopfschmerzen`) lands between miss and gold — the documented gap.

**`scripts/build_rl_pool.py build`** — 4,170 candidates (1,896 ok / 2,274 fix) from 15,557 raw
validated rows, per-phenomenon cap 400, exact-overlap guard against every eval input (0 hits — the
corpus was already quarantined). One decision changed from the plan: the packed-v4 **val split is
not excluded**. `pack_dataset.py` splits by template family, so *all* 181 `k2` and *all* 130
`adjend` fix rows live in val; excluding them would have removed two phenomena from RL for no
benefit (RL never reads eval_loss). Part A §4 updated.

**First v3 baseline, E4B v4** (`results/guarded-v3_gemma4-e4b-german-v4-4bit.json`, 300 items in
4.5 min on the M1 Max): **260/300 (87%), FC 4/150 = 3% (1 of the 93 hard negatives), miss
36/150 = 24%** — 27 bare-`OK` misses and 9 wrong fixes, 0 format errors. The suite does what it
was built for: the miss problem is visible at full size (24% here vs 16% on the old suites) while
FC stays at the app's floor even under 93 traps. Weakest cell `imperativ` 12/20; `wechsel` 16/20.
The four false corrections are all *lexical* over-reach (`zurückgerufen` → `angerufen`,
`gewinselt` → `gewartet`, `übers Wochenende` → `am Wochenende`) — the fine-tune not knowing a
word, not a grammar miscalibration. Remaining five baselines running.

Cost so far: $0 (all Mac).

### 2026-09-05 — step 0 done: six baselines on v3 (C.1), the calibration picture

All six in-app models scored on v3 in one sequential Mac run (`score_v3_baselines.sh`, 23 min total,
~67 items/min for E4B). The table is C.1. What it says:

- **E4B v4 is the only model at the app's FC floor** — 4/150 (3%), and only **1 of the 93 traps**
  fooled it. Stock E4B falls for 19 traps, v1 for 12, both E2Bs for 10–13, granite for 11. The v4
  SFT solved false corrections; the traps confirm it is not a fluke of the old suites.
- **Every fine-tune paid for it in misses.** v4 misses 36/150 (24%), of which 27 are bare `OK` —
  against stock's 12 bare `OK`s. The SFT moved the verdict prior toward silence. That is the RL
  target, and on v3 it is 27 items wide instead of 12.
- **E2B v5 "strict" is the cautionary tale in one row**: fix-frac 0.80 bought FC 13% → 7% and
  *raised* the miss rate 20% → 27%. The composition knob cannot move one without the other.
- **v4 vs v1 on v3: +21/−11, p = 0.11.** Still directional after 300 items — but the *kind* of
  difference is now legible: v1 has 17 FC (12 traps) where v4 has 4; v4 has 3 more misses. The
  old suites' "v1 core 54 vs v4 51" was a 3-item wobble on 60 items; on the traps v1 is clearly
  the more trigger-happy model.
- Per phenomenon, `imperativ` is the tail everyone misses (v4 12/20, v1 10/20; the corpus has 133
  rows of it) and `aux` is where v4 gained most over v1 (17 vs 14).

**What RL has to do, in numbers:** take v4's 27 bare-`OK` misses down while holding FC ≤ 9/150 (6%)
and the traps ≤ ~5/93. The step-0b bias sweep (running) tells whether a decode-time bias can do
that for free; if it takes miss to ≤ 9% at FC ≤ 6%, the plan stops there for E4B.

Also written this session, no GPU: `runpod/train_grpo.py` (the Part A §7 recipe, env-driven like the
SFT script, smoke mode, TRL-version-tolerant config, thinking forced off, gold-reward sanity print),
`runpod/make_grpo_bundle.sh`, and `scripts/build_hard_negatives.py` (171 trap rows for the pool;
5 more were written and dropped by the checker as near-duplicates of v2/v3 items — the guard works).
The reward import chain was verified on a Python without MLX, as it will be on the pod.

### 2026-09-05 — step 0b, first attempt: the bias that did nothing (a harness trap, caught)

The first bias sweep (biases 1, 2, 4 × four suites) returned numbers **identical to bias 0 on all
466 correction items**. Not "no effect" — *zero* changed verdicts, which is impossible against a
measured first-token margin of 1.25 nats on a real miss (`v3-imperativ-e1`: `OK` −0.25 vs `FIX` −1.5
log-prob). Diagnosis in one generate call with a printing processor: **mlx_lm 0.31 hands a logits
processor only the tokens generated so far** — shape `(1,)` on the first call, holding the last
prompt token — not the full history the docstring implies. The "bias only when
`tokens.shape == prompt length`" guard therefore never fired. Fixed to fire on the first call
(`scripts/verdict_bias_eval.py`); the same item now flips from `OK` to `FIX: Lies das Buch!` at
bias +4. Stale result files deleted; sweep relaunched (second relaunch — the first used `setsid`, which does
not exist on macOS; the runbook's `setsid nohup` lines are for the Linux pod only). Lesson filed with
the other harness traps: a control that reproduces the baseline *exactly* is a broken control, not
a null result.

### 2026-09-05 — step 0b done: the bias curve (C.2) — go for the GPU run

Rerun with the fixed processor: 466 correction items × 3 bias values, 24 min on the Mac. The
result is the plan's §2 prediction measured: **the bias trades FC for miss one-for-one.** +1: miss
24% → 15%, FC 3% → 9%, traps fooled 1 → 7. +2: miss 9% (the target) at FC 19% (three times the bar).
+4 = +2 — the last 13 misses on v3 are not verdict-threshold decisions (9 of v4's 36 misses were
wrong *fixes* with the right verdict; those need the fix-quality half of the reward, not a bias).

So the control did its job in both directions: it proves the miss problem *is* mostly a first-token
threshold (a +2 bias removes 23 of 36 misses), and it proves a threshold shift cannot fix it without
the FC cost, because a bias cannot tell a confident `OK` from an uncertain one. That discrimination
is what the joint reward has to learn. **Decision: proceed to the pod.** Bars unchanged (Part A §8);
the curve in C.2 is what "beats `v4+bias`" now means concretely — nothing on it is inside the box
miss ≤ 9% ∧ FC ≤ 6%.

Mining started 20:53 (the rebuild picked up the 171 hard negatives: OK counts rose, e.g. `adjend`
83 → 93, `imperativ` 43 → 53). Cost so far: $0.

### 2026-09-05 — step 3: the pod, and smoke run #1

Pod `5cfbspfzata4a3`, **A100 SXM 80 GB community at $1.39/h**, created 21:06 local. Why this card:
the only 80 GB class with HIGH availability at the time; per-run cost lands within ~$1 of an A40
($3.5 vs $3.1 estimated) at roughly a third of the wall-clock, and no OOM risk at batch 16. No
network volume this time — 80 GB container disk holds the 15 GB fp16 download, the venv and the
merged output, and it avoids the network-fs `chown` noise. Host: driver 590.48 / CUDA 13.1; image
torch 2.8.0+cu128; `pip install unsloth` upgraded to **torch 2.11.0+cu130, transformers 5.5.0,
trl 0.24.0, unsloth 2026.9.2** — `torch.cuda.is_available()` True on this host, so §6.11 of the
runbook did not bite. TRL 0.24 accepts every `GRPOConfig` key the script uses except
`use_transformers_continuous_batching` (off by default; the config loop drops it).

Two small traps on the way in, both logged so they stay small:
- the model prefetch launched with the *system* python has no `huggingface_hub` — use the venv's;
- two unauthenticated HF clients from one community-pod IP hit **429** rate limits on the repo's
  metadata calls; the trainer's built-in retries rode it out, and the real run goes `HF_HUB_OFFLINE=1`
  from the warm cache anyway. (Passing `HF_TOKEN` would raise the limit if it ever recurs.)

**Smoke #1 (candidates.jsonl as a stand-in pool, 4,300 rows):** model loaded, LoRA attached, pool
columns correct, and the rendered prompt tail is exactly right — ends in `<|turn>model\n`, no
`<|channel>` (smoke line 1 ✅). Then *my own diagnostic* crashed: `tokenizer(probe)` — for Gemma 4,
`FastModel` returns a multimodal **processor**, whose `__call__` wants `text=`. Fixed to count with
the inner tokenizer; relaunched as smoke #2, offline from the cache.

**Smoke #2** (offline from the cache): loaded in seconds; **LoRA r=16 attached — 36,700,160 trainable of
6,018,935,328 (0.61%)** (smoke line 3 ✅); row-0 prompt 175 tokens (MAX_PROMPT 512 is generous);
**reward on the gold answers = 1.0 on all eight probe rows** (the reward ships intact); config
accepted; rollouts and the forward pass ran. The backward then raised
`torch.utils.checkpoint.CheckpointError: recomputed values … different metadata` — Unsloth's
`use_gradient_checkpointing="unsloth"` recompute path produces a different tensor sequence than the
saved forward on **Gemma 4 E-series under the GRPO trainer** (saved side: `[1, 3406, 256]` per-layer-
embedding tensors; recompute side: `[3406, 16]` LoRA and `[3406, 10240]` MLP tensors). The SFT runs
used the same flag on the same model without incident, so it is GRPO-path specific. Fix: gradient
checkpointing is now an env switch (`GRAD_CKPT=none|unsloth|hf`, **default none**) — with ~300-token
sequences and a 4-bit base, the activations fit an 80 GB card easily; a 48 GB card would try `hf`
first, then `BATCH_SIZE=8`. Smoke #3 launched 21:30 with `GRAD_CKPT=none`.

**Smoke #3** (`GRAD_CKPT=none`, 4-bit, 10 steps, `smoke3.log`): **ran to `DONE`.** The remaining
checklist lines, measured:

| line | result |
|---|---|
| 2 — reward non-degenerate | ✅ reward mean 0.29–0.35, std 0.78–0.93 per step; **`frac_reward_zero_std` = 0.125** — only 1 group in 8 is all-same, on the *unmined* candidate pool (the plan's bar was < 0.7) |
| 4 — s/step, VRAM | ❌ **173 s/step, peak 30.1 GB** — ~12× the estimate; 750 steps would be 36 h ≈ $50 |
| completions | mean 33–42 tokens, terminated ones 15–25; **22–23% hit the 96 cap** — the sample table shows why: at temperature 1.0 the SFT model sometimes *repeats its own FIX/WHY block* until the cap. The reward scores that −1 (malformed), which is the right lesson for RL to learn, but every batch pays 96 decode steps for it |
| kl | 0.000 at step ≤ 10, as expected |

Diagnosis for line 4: the 30 GB peak on an 80 GB card is the tell — the run is not memory-bound, it is
paying bnb-4bit dequantisation on every matmul, in generation (64 sequences × 96 steps) *and* in the
three training forwards (policy, reference, backward). Unsloth's own Gemma 4 page says "prefer
16-bit / bf16 LoRA if memory allows"; it does. Changes, all in `train_grpo.py` env: **`LOAD_4BIT=0`
(bf16 LoRA) is the new default**, `MAX_COMPLETION` 96 → 80 (valid replies terminate by ~60; clipped
ones are malformed regardless), `SMOKE_STEPS` for short timing runs. Smoke #4 (bf16, 4 steps)
launched 22:02 to measure the new s/step. Note for the record: TRL 0.24 does not forward a
`log_metric` callable to reward functions, so the reward's component metrics (`reward/format_ok`
etc.) are silent on this stack; TRL's own `reward`/`reward_std`/`frac_reward_zero_std` carry the
watch instead.

**Smoke #4** (bf16 LoRA, 4 steps): **135.9 s/step average, peak 34.0 GB** — only 22% faster than
4-bit, so dequantisation was not the main cost. But the progress bar tells a different story than
the average: steps 1–3 took ~168 s each and **step 4 took ~35 s**. No dynamo recompile messages in
the log. Reading: torch.compile warm-up of Unsloth's GRPO loss graphs on the first few distinct
(batch, length) shapes, then steady state. **Smoke #5** (`UNSLOTH_COMPILE_DISABLE=1`, to test that
theory) crashed instead: the *un-compiled* Unsloth generation path hands `torch.multinomial` a 3-D
probability tensor (`prob_dist must be 1 or 2 dim`) — so the compiled path is the only working one on
this stack, and compile-disable is not a knob here. **Smoke #6** (8 steps, per-step timer, generate
timer) launched 22:15 to measure the steady state directly; it sizes the real run.

**Smoke #6** (bf16, 8 steps, per-step + per-generate timers): the split is now measured.
**Generation: 11 s per call** (64 completions × ~80 tokens, output shape `(64, ~260)`) = **10% of
wall-clock**. Steps: 55 / 227 / 198 / **31** / 127 / 130 / 133 s; "steady state" 105 s/step, of which
~95 s is training-side. Peak 33.9 GB. So neither dequantisation nor generation was the story — the
training half of a step costs 10× what an 8B bf16 forward/backward on 64 × 265 tokens should
(~6–10 s on an A100), and it swings 30 ↔ 130 s on near-identical shapes. Unsloth's GRPO loss is
`torch.compile(dynamic=True, fullgraph=True)`, so shape recompiles are not expected; but dynamo's
guard cache defaults to 8 variants per frame, after which it **silently falls back to eager** — a
chunked, Python-driven loss in eager would look exactly like a 100 s step, and the one 31 s step
like the last cache hit. Smoke #7 (6 steps, `TORCH_LOGS=recompiles`, `TORCHDYNAMO_CACHE_SIZE_LIMIT=64`)
launched 22:36 to make dynamo name the failing guard. Budget note: at 105 s/step the planned 750 steps
would be ~22 h ≈ $30 — the run is not launched until this is understood or the step count is cut.

### 2026-09-05 — step 2 done: the mined pool (`data/rl_pool_v1/`)

Mining ran on the Mac in 107 min (40 prompts/min, K=4 at temperature 0.8, batched MLX, E4B v4 4-bit
as the probe): 4,300 candidates → **243 wrong (0/4), 707 uncertain (1–3/4), 3,350 easy (4/4)**;
candidate accuracy 87.6%. Pool = wrong + uncertain + 20% of easy = 1,652, then **all 123 hard
negatives forced in** (the sampler had kept 52 — a trap the model already passes is exactly the row
that must stay in the pool to hold FC while the reward pushes toward FIX) → **1723 prompts,
818 ok / 905 fix** (45/55), every phenomenon 45–185 rows. `meta.json` has the
per-phenomenon table; `mined_full.jsonl` keeps all four samples + rewards per candidate for audits;
`dpo_pairs.jsonl` (950 gold-vs-worst-sample pairs) is the DPO fallback, free.

Two numbers to reconcile: the K=4/temp-0.8 mining probe saw 84% of candidate groups with zero reward
variance, but the K=8/temp-1.0 GRPO smoke on the *unmined* candidates measured `frac_reward_zero_std`
= 0.125. Temperature 1.0 and eight samples surface the repetition failure (a −1 in an otherwise-
correct group) far more often than the mining probe did — so the pool is, if anything, harder than it
needs to be, which is fine. Below the 2,500–4,000 target of §4, and *deliberately left there*: with the
step-time problem (Part B, smoke #6) fewer steps is what the budget needs — 2 epochs over
1723 prompts = **430 optimizer steps**, same two-epoch coverage as the original plan.

Shipped to the pod (`/root/train/train.jsonl`, md5 verified), bundle rebuilt
(`runpod/gemma4_grpo_runpod.tar.gz`).

### 2026-09-05 22:43 — step 4 launched: E4B rl1

**Smoke #7** (6 steps, `TORCH_LOGS=recompiles`, dynamo cache 64): steps 52 / 48 / 169 / 34 / 82 s and
**zero dynamo recompile events**. So the stalls are below dynamo: the inductor cache on the pod is
1.3 GB and still gaining kernel files between runs — **Triton compiling kernels for new
sequence-length classes** (max-autotune is off by default in unsloth_zoo; checked). Those compiles
cache to disk, so they thin out over a long run; the true steady state is the 33–52 s steps. Budget
math at 45 s/step: 430 steps ≈ 5.4 h ≈ $7.5, plus stalls — inside the $15 envelope. Decision: launch,
watch the per-step timer, and **cut to one epoch (215 steps) if the running average is above 80 s/step
at step 40**. `SAVE_STEPS=50` so a kill leaves a usable adapter checkpoint.

```
pod 5cfbspfzata4a3 (A100 SXM 80 GB, $1.39/h)   launched 02:43:27Z = 22:43 local
EPOCHS=2 BATCH_SIZE=16 GRAD_ACCUM=4 NUM_GEN=8 LR=5e-6 BETA=0.02 LORA_R=16 LOAD_4BIT=0 GRAD_CKPT=none
MAX_PROMPT=512 MAX_COMPLETION=80 TEMP=1.0 loss_type=dapo SAVE_STEPS=50 LOG_STEPS=5
pool train.jsonl 1,723 rows (md5 d8c111fe…), 430 optimizer steps, OUT_PREFIX=gemma4-e4b-german-rl1
```

Monitoring: a session monitor reports every 25 steps, any traceback, and completion; the pod is
deleted from here as soon as the LoRA and merged model are copied off. Pod time before launch:
1 h 37 min of smoke runs ≈ $2.25.

### 2026-09-05 23:06 — attempt 1 stopped at step 11; the shape fix

Attempt 1's first eleven steps: 229 / 39 / 79 / 129 / 150 / 39 / 173 / 75 / **23** / 139 s — the fast
steps are getting *faster* (23 s at step 10) while two in three still stall, and generation is a flat
11 s per call. Projection at the 120 s mean: 14 h ≈ $20. Stopped at 03:06Z (25 min, ≈ $0.60 of the run)
rather than let the budget question ride to step 40.

The stall mechanism, now pinned down by reading the generated trainer: TRL pads prompts (left) and
completions (right) **to the batch maximum**, so every step presents a new `(prompt_len,
completion_len)`; dynamo sees no guard failure (`dynamic=True`), but inductor/Triton still compile
kernels for each new size class, and the on-disk cache grows step after step. Fix: TRL's `pad()`
already has `pad_to_multiple_of`; `train_grpo.py` now installs a wrapper that forces it to
`PAD_MULTIPLE=64` on `trl.trainer.utils`, `trl.trainer.grpo_trainer`, *and* Unsloth's generated
`UnslothGRPOTrainer` module (which imports `pad` by name and calls it at run time — verified in the
file). Completions ≤ 80 → always 128; prompts → 192/256/320: at most six shapes for the whole run,
each compiled once. Masks pad with 0, so the loss is untouched. Smoke #8 (8 steps) launched 23:07 to
verify the step times are uniform before relaunching.

Honest accounting for the user's question ("way more expensive than my previous runs?"): yes. Pod
time so far ≈ 2 h ≈ $2.75 against SFT runs that cost $2.20 *in total*; seven smoke runs were the
price of three Unsloth-on-Gemma-4 incompatibilities the plan did not foresee, and the eighth is the
price of a compile behaviour it did not foresee either. If the fix holds, the run itself is ~4 h ≈ $6.

### 2026-09-05 23:21 — attempt 2 launched: one epoch, the user's call

**Smoke #8** (pad-to-64): 49 / 43 / **220** / **168** / 38 / 38 / … — 98 s/step mean. The wrapper was
installed (log line confirms) and the fast steps are as fast as ever, but the stalls stayed. So fixed
pad shapes do not remove them; whatever inductor/Triton is compiling on those steps is keyed on
something other than the padded sequence length (candidates for a daytime look, not tonight: the
number of unmasked tokens driving Unsloth's chunked-loss split, or the `mask_truncated_completions`
row count). Two smokes spent on the hypothesis, ~$0.60. Left `PAD_MULTIPLE=64` on — harmless.

The choice was put to the user with the numbers (pod ≈ $3.00 so far; ~90 s/step mean): one epoch on
this A100 (≈ 5.5 h, ≈ $7.70 more), two epochs (≈ 11 h, ≈ $15.50), an A40 (cheaper, slower, cold
cache), or stop and rebuild on plain TRL tomorrow. **User chose one epoch on the A100.**

```
attempt 2: launched 03:21:44Z = 23:21 local, EPOCHS=1 → 215 steps, everything else as attempt 1
(+ PAD_MULTIPLE=64). SAVE_STEPS=50. First steps: 50 / 39 / 37 s.
```

Coverage note for the write-up: one epoch = every pool prompt seen once with 8 samples = ~13.8k
scored completions, in the range where Unsloth's own guidance expects the reward to have started
moving (they quote ~300 steps at smaller batches).

**Mid-run read at step 87/215 (01:20 local):** mean 61 s/step (the fast steps are now 13 s — see why
below), 26 stalls in 86 steps, ETA ~2 h. The logged curve (every 5 steps, 8 prompts × 8 samples each,
so noisy):

| step | reward mean | reward std | zero-std groups | KL | clipped completions |
|---|---|---|---|---|---|
| 5 | 0.43 | 0.69 | 0.20 | 0.0001 | 9% |
| 25 | 0.34 | 0.74 | 0.15 | 0.0002 | 11% |
| 50 | 0.46 | 0.38 | 0.50 | 0.004 | **0.6%** |
| 70 | 0.54 | 0.40 | 0.53 | 0.007 | 0.9% |
| 85 | 0.37 | 0.34 | 0.55 | 0.005 | 0.0% |

The first thing RL fixed was the one the smoke runs kept tripping over: the **repeat-the-FIX/WHY-block
loop is gone by step 50** (clipped 9–15% → ~0%), which is also why the unstalled steps shrank from
~38 s to 13 s — shorter completions. Reward mean drifting 0.3 → 0.45–0.6, reward std halving, the
zero-variance share rising to ~0.5 (the model agreeing with itself more, not yet saturated), KL
0.005–0.015 under a β = 0.02 leash, grad norm steady 0.1–0.27. Nothing to intervene on.

### 2026-09-06 02:32 — step 4 done: training finished

**215 steps in 190.2 min = 53.1 s/step, peak VRAM 34.1 GB, generation 16% of wall-clock** (215 calls,
1,831 s). The stalls never went away (51 of the first 167 steps > 100 s) but the unstalled steps
fell to 12–13 s once the repetition loop was gone, so the mean landed at 53 s against the 90 s
projected at the one-epoch decision. Final logged window (steps 130–165): reward mean 0.53 vs 0.33
in the first window; reward std 0.33–0.45; zero-variance groups ~0.5; KL ≤ 0.039; clipped
completions 0.0–0.6%. `outputs-grpo/` holds checkpoints 50/100/150; the final LoRA
(`gemma4-e4b-german-rl1-lora`, 147 MB adapter, r=16) saved and was **copied to the Mac immediately**
(`models/gemma4-e4b-german-rl1-lora`).

One more trap for the list: `save_pretrained_merged` **checks that the base repo exists on the Hub
before merging**, so with `HF_HUB_OFFLINE=1` (set to dodge the 429s) it raised
`OfflineModeIsEnabled` after training. The LoRA save had already succeeded, so nothing was lost;
the merge is re-run online from the cached weights (`merge.py`, Unsloth `from_pretrained` on the
adapter dir + `save_pretrained_merged`). Runbook §7b: unset `HF_HUB_OFFLINE` for the save, or merge
in a second step.

Pod time at training end: 5 h 26 min ≈ **$7.55**.

**Merge done** (online re-run, 19 s of actual merging): `gemma4-e4b-german-rl1-merged`,
`model.safetensors` = 15,992,595,884 bytes. **Archived to HF first**: `kessenma/gemma4-e4b-german-rl1-fp16`
(private), byte count verified against the pod — 56 s from the pod, vs the Mac's own downlink measured
at ~4 MB/s (a 55-min `scp`; the runbook's "upload to HF rather than scp" line is right for the wrong
reason on this connection: the pod's egress is fine, the laptop's downlink is the bottleneck). A pod-side
MLX convert to shrink the transfer was tried and abandoned — the Linux `mlx` wheel installs without
`libmlx.so`. The fp16 copy to `models/gemma4-e4b-german-rl1-merged` continues in the background; the
pod is deleted the moment its md5 matches.

**Pod deleted 03:00 local** on the user's ask, with the Mac copy at 73% — the LoRA was local and the
fp16 verified on HF, so nothing depended on the pod any more; the rest of the fp16 comes from HF at the
same ~4 MB/s. `runpodctl pod list` → `[]`, checked. **RunPod billing for the pod: $7.05** (GPU $6.99,
disk $0.06), C.4.

**fp16 on the Mac** (from HF at ~9.5 MB/s over six chunk-store connections — 2.4× the scp rate; byte
count matches the pod). **Convert trap:** `mlx_lm convert` now fails on it with `Received 54
parameters not in model` — the `k_proj`/`v_proj`/`k_norm` tensors of the 18 KV-sharing layers
(24–41) that the HF checkpoint carries and the MLX Gemma 4 model does not define. It is the tool,
not the merge: the **v4 merge that converted on Aug 17 fails identically today** with mlx_lm 0.31.3.
Fixed with a sanitize patch that drops exactly those 54 unused tensors
(`scripts/convert_gemma4_patched.py` — promoted, since v4 itself can no longer be reconverted without it). Scoring follows.

### 2026-09-06 03:45 — step 5: scored. rl1 = v4. Bars not met.

| | core | ext | holdout | v3 | FC (core+ext) | miss (core+ext) | v3 FC | v3 miss |
|---|---|---|---|---|---|---|---|---|
| E4B v4 | 51 | 56 | 75 | 260 | 3% | 16% | 3% | 24% |
| **E4B rl1** | 51 | 56 | 73 | 260 | 3% | 16% | 3% | 24% |

Exact McNemar: every suite a tie (holdout −2, p = 0.50). On the 300 v3 items **pass/fail is identical
item for item**; 20 responses differ and every difference is in the WHY sentence. Naturalness: particles
12.4 → 12.8, follow-ups 0.82 → 0.82, repeated 4-grams 0.10 → 0.12 — noise. **The shipped-path model
is v4 with a different explanation style. None of the §8 bars moved.**

Why, measured:
- **The update was tiny.** Merged rl1 vs merged v4 weights: max |Δ| ≈ 6e-5, relative Δ ≈ 5e-5 to
  1e-4 per matrix. The LoRA B matrices have norms 0.007–0.03. A delta that size does not survive
  4-bit quantisation at group size 64 — the app's path — and barely survives greedy decoding in bf16.
- **The reward moved anyway** (0.33 → 0.53 in-training) because GRPO scores *sampled* completions at
  temperature 1.0, and the cheapest reward gain was eliminating the repeat-the-block loop (clipped
  completions 9–15% → 0% by step 50). That failure never appears under greedy decoding, so the
  eval could not see the win, and the remaining verdict work was too small an update to register.
- Recipe arithmetic: LR 5e-6 × 215 steps × cosine × advantages that shrink as groups agree (zero-std
  share rose to 0.5) × a β = 0.02 leash to the very model being evaluated. Unsloth's own guidance
  quotes rewards starting to move at ~300 steps *and* runs with LR 5e-6 for a thousand-plus; the
  one-epoch cut (taken for cost) sat below both.

What this round bought, at $7.05: a working Unsloth-GRPO-on-Gemma-4 stack with its four traps
documented (processor diagnostic, checkpointing, bnb-4bit speed, offline merge) plus the mlx_lm
KV-shared-layer convert trap; a reward that ships; a frozen 300-item suite that can see a real move;
and one clean negative result: **at this learning rate and step count, GRPO re-styles the
explanations and the sampling distribution but does not move the verdict threshold on the
deployed 4-bit model.** The step-time stalls remain undiagnosed (not shapes, not dynamo).

The sampled-decoding comparison (temperature 1.0, v4 vs rl1 on v3) was started on the Mac and **stopped
at the user's request** (fan noise) after the v4 half: **v4 sampled at temperature 1.0 (2 samples × 300):
82.5% pass, 1.0% malformed, FC 9%, miss 26%** — i.e. under the RL regime v4 is a noticeably looser model
than under greedy (FC 3%), which is the distribution rl1 was rewarded on. rl1's half did not finish; the script is in the session scratchpad
(`sampled_compare.py`, ~10 min of Mac GPU) if the question — did the policy move where it was
trained — is worth answering before rl2. Round closed 2026-09-06 04:00.

### 2026-09-06 04:27 — overnight: not erased, never there (C.5)

The bf16 scoring settles the open question in the least flattering direction: **rl1 equals v4
unquantised too** — identical pass/fail on 503 items, 31 responses differing in WHY wording. And
sampled at temperature 1.0 on eval items, rl1 and v4 are the same model (FC 10% vs 10%, miss 27% vs
28%, malformed 1.2% vs 1.3%). So the reward that rose during training was earned on the pool's
prompts specifically — mostly the repetition loop, which is a pool-prompt phenomenon (22% there,
1.3% on eval) — and the verdict work never reached a measurable update. Quantisation is exonerated;
the recipe is not.

What this changes about rl2 (Part A §9 row 6, revised): a bigger step is *necessary* but the
overnight data lowers, not raises, the odds it is *sufficient* — the run also has to generalise from
pool prompts to eval prompts, which rl1 gave no evidence of. The cheaper test of the same hypothesis
is now ready: **DPO on the 873 verdict-error pairs** (offline, no generation, no stalls, ≈ $1.50 on an
A40 or possibly $0 with mlx-tune QLoRA on the Mac). If DPO moves misses without the FC seesaw, rl2 is
worth $7; if it seesaws like the bias, RL is unlikely to escape it and the round's answer is the bias
curve. Round parked here pending the user.

Two numbers for the article that came free: 4-bit costs E4B ~5/503 items (holdout 78 → 75), and under
sampling the shipped model is a much looser tutor (FC 10%, miss 28%) than under greedy (3%, 24%) —
the decoding mode is itself a calibration knob.

---

# Part C — Results

All guarded. A cell is filled only with the `results/` filename it came from.

### C.1 — Baselines on the new v3 suite (step 0) — filled 2026-09-05

300 items = 150 ok (93 hard negatives) + 150 error. FC over the 150 ok items, miss over the 150 error
items; `bare OK` = misses where the model said nothing, `wrong fix` = it corrected the wrong thing.

| model | v3 (/300) | FC | traps fooled (/93) | miss | bare OK | wrong fix | file |
|---|---|---|---|---|---|---|---|
| E4B stock | 244 (81%) | 19% (29/150) | 19 | 18% (27/150) | 12 | 15 | `results/guarded-v3_gemma-4-e4b-it-4bit.json` |
| E4B v1 | 250 (83%) | 11% (17/150) | 12 | 22% (33/150) | 16 | 17 | `results/guarded-v3_gemma4-e4b-german-tutor-4bit.json` |
| **E4B v4** | **260 (87%)** | 3% (4/150) | 1 | **24%** (36/150) | 27 | 9 | `results/guarded-v3_gemma4-e4b-german-v4-4bit.json` |
| E2B v1 | 251 (84%) | 13% (19/150) | 13 | 20% (30/150) | 10 | 20 | `results/guarded-v3_gemma4-e2b-german-tutor-4bit.json` |
| E2B v5 | 249 (83%) | 7% (11/150) | 10 | 27% (40/150) | 21 | 19 | `results/guarded-v3_gemma4-e2b-german-v4s-4bit.json` |
| granite-4.1 v4 | 228 (76%) | 13% (19/150) | 11 | 35% (53/150) | 22 | 31 | `results/guarded-v3_granite41-3b-german-v4-4bit.json` |

Per phenomenon (correct / items):

| model | adjend | artikel | aux | dawo | imperativ | k2 | ndekl | negation | refl | relpron | sep | vmp | wechsel | wo |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| E4B stock | 19/20 | 19/20 | 12/20 | 20/24 | 18/20 | 14/22 | 17/20 | 18/20 | 20/24 | 16/22 | 17/24 | 20/24 | 17/20 | 17/20 |
| E4B v1 | 19/20 | 18/20 | 14/20 | 19/24 | 10/20 | 16/22 | 19/20 | 17/20 | 22/24 | 22/22 | 21/24 | 19/24 | 16/20 | 18/20 |
| E4B v4 | 19/20 | 19/20 | 17/20 | 20/24 | 12/20 | 19/22 | 18/20 | 18/20 | 21/24 | 22/22 | 19/24 | 21/24 | 16/20 | 19/20 |
| E2B v1 | 20/20 | 16/20 | 16/20 | 16/24 | 16/20 | 15/22 | 17/20 | 19/20 | 22/24 | 18/22 | 20/24 | 21/24 | 15/20 | 20/20 |
| E2B v5 | 20/20 | 19/20 | 16/20 | 18/24 | 14/20 | 18/22 | 17/20 | 19/20 | 22/24 | 16/22 | 22/24 | 20/24 | 12/20 | 16/20 |
| granite-4.1 v4 | 17/20 | 15/20 | 13/20 | 20/24 | 13/20 | 14/22 | 14/20 | 16/20 | 19/24 | 16/22 | 16/24 | 22/24 | 15/20 | 18/20 |

Paired tests on v3 (exact McNemar): **v4 vs v1** +21 / −11, p = 0.11 — directional, not significant;
**v4 vs stock** +36 / −20, p = 0.044. The v3 suite's own noise floor: with 300 items a ±3% move on the
total is about the 1-σ band; the *decision* metrics (FC, miss) are read on 150 items each.

### C.2 — The zero-cost control: v4 + logit bias (step 0b) — filled 2026-09-05

First-token logit bias toward `FIX` (and away from `OK`), everything else untouched. Correction items
only (v0 48, v1ext 53, v2 65, v3 300 = 466; FC over 206 ok items, miss over 260 error items). 0 format
errors at every bias. Files: `results/guarded-<suite>_gemma4-e4b-german-v4-4bit+bias<b>.json`.

| bias | v0 | v1ext | v2 | **v3 /300** | v3 FC | traps fooled /93 | **v3 miss** | all-suite FC | all-suite miss |
|---|---|---|---|---|---|---|---|---|---|
| 0 (= v4) | 41/48 | 48/53 | 61/65 | 260 | 3% (4) | 1 | 24% (36) | 2% (5/206) | 20% (51/260) |
| +1 | 42/48 | 49/53 | 62/65 | 263 | 9% (14) | 7 | 15% (23) | 9% (19/206) | 12% (31/260) |
| +2 | 40/48 | 50/53 | 60/65 | 259 | 19% (28) | 15 | 9% (13) | 19% (40/206) | 7% (17/260) |
| +4 | 40/48 | 50/53 | 60/65 | 256 | 21% (31) | 16 | 9% (13) | 21% (43/206) | 7% (17/260) |

**Verdict: the bias is a seesaw, not a fix.** Every point of miss it buys costs about a point of FC: +1 takes
v3 miss 24% → 15% and FC 3% → 9% (7 traps fooled instead of 1); +2 reaches the miss target (9%) at
FC 19%, three times the bar; +4 adds nothing over +2 (the remaining 13 misses are not first-token
decisions at all — 9 of v4's misses were wrong *fixes*, not silence). The best total, 263 at +1, is +3
items — noise — bought with 10 extra false corrections. **No bias point satisfies miss ≤ 9% at FC ≤ 6%.**
The bar RL has to clear is therefore strictly above the whole curve: miss ≤ 9% *and* FC ≤ 6% *and*
traps ≤ 5, which no threshold shift reaches. Decision: **proceed to the GPU run.**

### C.3 — E4B rl1 vs v4 vs v1 (step 5) — the decision table

| model | core | ext | holdout | **v3** | /203 | FC | miss | particles | follow-ups | 4-gram | file |
|---|---|---|---|---|---|---|---|---|---|---|---|
| E4B v1 | 54 | 57 | 70 | 250 | 181 | 6% | 9% | 2.8 | 0.78 | 0.30 | scoreboard 2026-08-19 block; v3: `results/guarded-v3_gemma4-e4b-german-tutor-4bit.json` |
| E4B v4 | 51 | 56 | 75 | 260 | 182 | 3% | 16% | 12.4 | 0.82 | 0.10 | scoreboard 2026-08-19 block; v3: `results/guarded-v3_gemma4-e4b-german-v4-4bit.json` |
| v4 + bias 1 | 42 | 49 | 62 | 263 | 153/166 corr. | 9% | 15% | — | — | — | C.2 — the seesaw point; not a candidate |
| v4 + bias 2 | 40 | 50 | 60 | 259 | 150/166 corr. | 19% | 9% | — | — | — | C.2 — meets miss, fails FC 3× |
| **E4B rl1** | 51 | 56 | 73 | 260 | 180 | 3% | 16% | 12.8 | 0.82 | 0.12 | `results/guarded-*_gemma4-e4b-german-rl1-4bit.json`, `results/conv_rl1_*.responses.json` — **tie with v4, bars not met** |

McNemar, rl1 vs v4: core 0/0 (p = 1) · ext 0/0 (p = 1) · holdout 0 rl1-only / 2 v4-only (p = 0.50) · **v3 0/0 (p = 1)**.
Pass/fail identical on all 300 v3 items; 20 of 300 responses differ, all in the WHY wording only. v3 FC 4/150 (3%),
miss 36/150 (24%) — the same four false corrections and the same 36 misses as v4.
Per-phenomenon: watch `sep`, `refl`, `k2`, `imperativ` — the 12 misses in §1 live there.

### C.4 — Cost ledger (from `get-billing`, not from estimates)

| date | pod | GPU | hours | $ | purpose |
|---|---|---|---|---|---|
| 2026-09-05 21:06 → 2026-09-06 03:00 (local) | `5cfbspfzata4a3` e4b-grpo-rl1 | A100 SXM 80 GB, community, $1.39/h, CUDA 13.1 host, 80 GB container disk, no volume | 5.9 | **$7.05** (GPU $6.99 + disk $0.06, `get-billing`) | 8 smoke runs (~1.6 h), attempt 1 (25 min), attempt 2 = the run (3.2 h), merge + upload + copy (~0.6 h) |
| | | | | **total: $7.05** | the whole E4B round so far; the plan's estimate was ~$6 for the run + $0.20 smoke |

### C.5 — Was the rl1 update erased by quantisation, or never there? (overnight 2026-09-06, Mac, $0)

Greedy, guarded, all four suites, the same merges scored **unquantised (bf16)** and as the app's 4-bit.
Files: `results/guarded-*_gemma4-e4b-german-{v4,rl1}-{bf16,4bit}.json`.

| model | core /60 | ext /61 | holdout /82 | v3 /300 | total /503 |
|---|---|---|---|---|---|
| v4 bf16 | 51 | 55 | 78 | 263 | 447 |
| **rl1 bf16** | 51 | 55 | 78 | 263 | **447** |
| v4 4-bit | 51 | 56 | 75 | 260 | 442 |
| rl1 4-bit | 51 | 56 | 73 | 260 | 440 |

rl1-bf16 vs v4-bf16: +0/−0 on core, ext, holdout; +1/−1 on v3 (p = 1). Responses differ on 2 / 4 / 5 / 20
items — WHY wording only. **Never there.** Side finding worth keeping: 4-bit costs this model ~5 items
in 503 (447 → 442), concentrated on the holdout (78 → 75) and v3 (263 → 260).

Sampled decoding at temperature 1.0 (2 samples × 300 v3 items, `results/sampled-v3_v4_vs_rl1.json`):

| model | pass /600 | malformed | FC /300 | miss /300 |
|---|---|---|---|---|
| v4 4-bit | 486 (81.0%) | 1.3% | 31 (10%) | 83 (28%) |
| rl1 4-bit | 489 (81.5%) | 1.2% | 29 (10%) | 82 (27%) |

Even the sampling distribution rl1 was rewarded on is unchanged **on eval items**. The in-training
reward rise (0.33 → 0.53) was earned on the pool's own prompts — where the repetition loop was common
(22% clipped) — and did not transfer; on eval prompts v4 already only loops 1.3% of the time.

DPO fallback prepared: `data/rl_pool_v1/dpo_verdict_pairs.jsonl` — **873 pairs** where the rejected
sample is a *verdict* error (523 gold-fix rows the model answered `OK`, 350 gold-ok rows it "fixed"),
gold as chosen; repetition-loop rejects excluded.

---

# Part D — Article notes

Draft material for a "Round four: reinforcement learning" section of `ARTICLE.md`, in its voice.
Written as the round happens. `[TODO]` marks numbers that do not exist yet.

**The framing.** Fine-tuning had stopped paying. Thirty times more data and a better teacher moved
the hero model from 181 to 182 out of 203 — a tie by the project's own test. But the failures that
were left had a shape: twelve of the sixteen were the model looking at a broken sentence and saying
*OK*. Not wrong corrections — silence. The same model, one round earlier, had fixed eight of those
twelve. It hadn't forgotten the grammar. It had changed its mind about when to speak up.

That is a problem supervised fine-tuning is bad at, because all it can do is show the model more
examples and hope the ratio of "fix" to "OK" in the pile teaches the right threshold. I had already
tried that knob twice (`--fix-frac` 0.70, then 0.80) and watched it move the miss rate and the
false-correction rate in opposite directions, like a seesaw. What I wanted was to reward the
*decision* directly: right verdict, right fix, and nothing else — and this task, unusually, can be
scored by a program. Every training row has a gold verdict and a gold fix; the eval scorer is
twelve lines of Python. That's the setting where reinforcement learning with a verifiable reward
actually works, as opposed to the setting where it mostly produces blog posts.

**The measurement problem came first.** Before renting anything I had to admit that my eval couldn't
see the result I was hoping for. Twelve reachable misses on 203 items: fix half of them and you have
moved the score three percent, which on those suites is a coin flip. So the first artifact of the RL
round was not a training script but three hundred new test sentences — half broken, half correct,
and most of the correct half deliberately shaped like the errors a learner makes. *Ich wasche mir die
Hände.* *Er wiederholt den Satz.* *Sie besteht auf ihrem Recht.* Ninety-three traps, each one a
sentence that an over-eager tutor would "fix." Building it was humbling in a way I hadn't planned:
the first draft failed a hundred and thirteen of its own checks, mostly because my textbook-style
sentences already existed, nearly word for word, somewhere in a seventeen-thousand-row corpus that
I had generated myself.

The new suite rearranged the leaderboard slightly and the story a lot. The fine-tuned hero model
scored 260 of 300 and fell for exactly one of the ninety-three traps; the stock model fell for
nineteen, my earlier fine-tune for twelve. So the false-correction problem really was solved — but
the price was now visible at full size: twenty-seven sentences with a real error that the model
looked at and said *OK*, against twelve for the stock model. Forty thousand rows of training data
had made the model polite. Reinforcement learning had one job: make it speak up again without
making it rude.


**The free baseline.** There is a cheaper way to make a model speak up: nudge the very first token.
The reply is either *OK* or it starts with *FIX*, so a one-line change at decode time can tilt that
choice, and I owed myself the honesty of trying it before spending a cent on RL. (I also owed myself
a working control — the first sweep came back identical to the baseline on all 466 items, which
turned out to be my code talking to the wrong argument, not the model being stubborn. A control that
reproduces the baseline *exactly* is a broken control.) With the nudge working, the result was a
seesaw. A small bias cut misses from 24 to 15 percent and raised false corrections from 3 to 9. A
bigger one reached the miss target I wanted, 9 percent, at a false-correction rate of 19 — three
times what I'd accept — and fooled fifteen of the traps. Push harder and nothing more moved: the
misses that remained weren't threshold decisions at all, they were wrong fixes with the right verdict.
A bias can move the line; it cannot tell a confident *OK* from an uncertain one. That distinction is
the whole job, and it is the thing a reward function can teach and a threshold can't.


**The run.** Eight smoke runs before the real one, which is not the number I'd planned. Three of them
were Unsloth and Gemma 4 disagreeing about things the supervised trainer never touched: the
multimodal processor that isn't a tokenizer, a gradient-checkpointing path whose recomputed backward
pass didn't match its forward, and a merge step that refuses to run offline. Two more chased a step
time that stalled two steps in three on kernel compilation for reasons I still can't name. The run
itself, once it ran, was almost boring: 215 steps in three hours, generation a sixth of the time,
the reward climbing from 0.33 to 0.53 and the model's one visible bad habit — repeating its own
correction until it hit the length cap — gone by step fifty. Seven dollars and five cents on the pod,
against a plan that said five.


**What it did and didn't do.** On the phone's model — four-bit, greedy — it did nothing. Same
score on every suite, the same thirty-six misses and the same four false corrections on the new
three-hundred-item test, pass and fail identical item for item; twenty replies differed, every one
of them in the wording of the explanation. The weights had moved by about one part in ten thousand,
which is below what four-bit quantization keeps. The reward curve was telling the truth about the
model that trained — sampled at temperature one, it had stopped looping — and telling me nothing
about the model that ships, which decodes greedily and never looped in the first place. That is the
lesson I'd underline for anyone doing this on a small model for a phone: the thing you reward is a
sampling distribution; the thing you ship is its mode after quantization; check that the delta
survives both before you read the curve. The recipe was too gentle — a learning rate of 5e-6 for two
hundred steps behind a KL leash — and I checked the obvious excuse overnight: scored unquantized, it is still the same model, so
quantization erased nothing — there was nothing to erase. The cheaper next question is whether an
offline preference step on the model's own wrong verdicts can move the threshold without the seesaw;
if it can, the expensive run is worth repeating with a real step size. [TODO: DPO / rl2, if run.]

