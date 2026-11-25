# Phase 1 — teacher generation runbook

Generate ~40k tutor training examples with `gemma-4-26B-A4B-it` on a rented GPU, then gate them
locally. Plan and rationale: [`../../DATA_V2_DISTILL_PLAN.md`](../../DATA_V2_DISTILL_PLAN.md).
Worklog: [`../../training-v2.md`](../../training-v2.md).

## Before you rent anything

```bash
cd training
.venv/bin/python scripts/check_prompt_sync.py        # MUST pass — see below
.venv/bin/python scripts/test_prompt_sync_guard.py   # the guard's own tests
.venv/bin/python scripts/build_gen_jobs.py --target 40000 --size-by-measured-yield
```

**Always pass `--size-by-measured-yield`.** The teacher under-delivers on item count — worse the
longer the output — and some of what it returns is rejected. Sizing from `PER_JOB` produces about
**28k valid items when you asked for 40k**, and you find out after paying for the run. The scaling
table (`MEASURED_VALID_PER_JOB`) is measured, not assumed; re-measure it whenever the prompts,
`PER_JOB`, or validator change. See [`../../training-v2.md`](../../training-v2.md) §1.5.

**`check_prompt_sync.py` is not optional.** Phase 1 exists partly because the training data had
been generated for months against the 2026-07-09 prompt shape while the app moved on — missing the
`HINT:` line, the 12 GrammarFocus steering variants and the 23 typed scenario roles. Generating
40k examples against a stale prompt is the expensive version of that mistake.

## GPU choice

| | pick | why |
|---|---|---|
| model | **`google/gemma-4-26B-A4B-it`** (bf16, **51.6 GB**) | MoE, 128 experts, ~4B active per token → far higher throughput than the dense 31B at comparable quality |
| GPU | **A100 80 GB PCIe**, community, ~$1.19/hr | 51.6 GB of weights plus KV cache needs an 80 GB card |
| fallback | RTX PRO 6000 Blackwell 96 GB (~$1.69/hr) | more headroom, newer silicon, still under H100 PCIe pricing |

⚠️ **Checked 2026-07-28: there is no `w4a16` QAT build for 26B-A4B.** Google ships that format for
31B / 12B / E2B / E4B only; for 26B-A4B the QAT release is `-qat-q4_0-gguf` (llama.cpp, not vLLM)
and `-qat-q4_0-unquantized`, which is a bf16 container and still 51.6 GB. So the cheap
48 GB-card plan does not work as written — verify the file sizes before assuming otherwise:

```bash
curl -s "https://huggingface.co/api/models/google/gemma-4-26B-A4B-it/tree/main?recursive=1" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); \
print(sum((f.get('lfs') or {}).get('size') or 0 for f in d if f['type']=='file')/1e9, 'GB')"
```

If you want a 48 GB card instead, the only drop-in is **`google/gemma-4-31B-it-qat-w4a16-ct`**
(23.3 GB, compressed-tensors) on an L40S — but it is *dense*, so 60 layers run per token instead of
30 MoE layers with 4B active. Expect it to be several times slower. Cheaper per hour, more hours.

Do **not** use unquantized dense `gemma-4-31B-it` for bulk generation: slowest option, no quality
gain measured on this task.

### Cost

11,067 jobs, ~750 output tokens each ≈ **8M output tokens**. On an A100 80 GB with vLLM batching
that is roughly 1.5–3 h of generation, plus ~10 min to pull 51.6 GB and ~10 min to load, so
**≈ $2.50–4**. Budget **$8** to absorb a restart.

⚠️ The remaining unknown is vLLM's support for this MoE architecture. **The smoke test below finds
that out for ~$0.30 instead of ~$4.**

## Pod setup

Four things cost ~$0.50 and 25 minutes to rediscover on 2026-07-28. Do them right the first time.

### 1. Set `PUBLIC_KEY` or you get no SSH

The bare `runpod/pytorch` image only starts `sshd` when `PUBLIC_KEY` is in the pod env. Without it
the pod reports `RUNNING`, maps port 22, and the port is simply **closed** — which looks exactly
like a slow boot. With it, SSH is up in ~10 s.

```bash
runpodctl ssh info <podId>            # ip + port + the key path it expects
cat ~/.runpod/ssh/runpodctl-ssh-key.pub   # <- pass this as PUBLIC_KEY at create time
```

### 2. Prefer SECURE cloud for this

The first attempt took a community A100 that sat at `uptime: 0` with `dataCenterId: null` for 11
minutes and never came up — a dead machine, billed the whole time. Secure cost $1.49/h vs $1.19/h
and worked immediately. For a 4-hour run the $1.20 difference is not worth the restart risk.

Also: **the GPU catalog reports stock it does not have.** `A100 80GB PCIe` listed 8 secure
instances and returned *"no longer any instances available"* on create. Have a fallback list ready
(`A100-SXM4-80GB`, `RTX PRO 6000 Blackwell`) — note the v2 API accepts only **one** GPU type per
pod and silently ignores the rest of the list, so retry rather than relying on the fallbacks.

### 3. `pip install vllm` fails — PEP 668

Ubuntu 24.04 marks the environment externally-managed:

```
error: externally-managed-environment
```

Use `uv` with an explicit override. It reuses the image's existing torch, so it takes **15 seconds**,
not 10 minutes:

```bash
pip install --break-system-packages -q uv
uv pip install --system --break-system-packages vllm
python -c "import vllm; print(vllm.__version__)"     # 0.26.0 verified working
```

### 4. Upload

```bash
mkdir -p /workspace/gen
# from the Mac — COPYFILE_DISABLE=1 keeps macOS ._AppleDouble junk out of the tarball,
# and --no-same-owner avoids uid-mismatch errors on extract
COPYFILE_DISABLE=1 tar czf bundle.tgz -C bundle .
scp -i ~/.runpod/ssh/runpodctl-ssh-key -P <port> bundle.tgz root@<ip>:/workspace/gen/
ssh ... "cd /workspace/gen && tar xzf bundle.tgz --no-same-owner"
```

⚠️ **zsh does not word-split unquoted variables.** `SSHOPT="-i key -p 22"; ssh $SSHOPT host` passes
the whole string as one argument and fails with a confusing *"Identity file … not accessible"*.
Inline the flags or use `${=SSHOPT}`.

## 1. Smoke test first — always

```bash
python generate.py --jobs jobs.jsonl --out smoke.jsonl --limit 40
```

**Stratify the smoke sample across every slice and every correction phenomenon.** A random 40-job
sample reports one aggregate number; a stratified one localises the failure to a slice, which is
what actually gets fixed. All five bugs found on 2026-07-28 were slice-specific.

Check, before spending real money:

- it loaded at all (this is where an unsupported architecture shows up)
- `empty-job rate` is **< 10%** — above that, something mechanical is wrong; check `trunc` first
- `trunc` is near zero — a non-zero count means a slice's `SLICE_MAX_TOKENS` budget is too small
  and its trailing objects are being cut off mid-JSON
- `wrong_shape` is near zero
- eyeball ~10 rows: is the German natural? Do `verdict:"ok"` rows actually contain correct German?
  Do the `hint` fields point at the error without giving it away?

**Yield per slice is the diagnostic, not the aggregate.** Print it:

```bash
python3 - <<'EOF'
import json, collections
rows=[json.loads(l) for l in open('smoke.jsonl')]
jobs=[json.loads(l) for l in open('data/gen_v2/jobs_smoke.jsonl')]
got=collections.Counter(r['_gen']['job_id'] for r in rows)
exp={j['job_id']:(j['slice'],j['expect']) for j in jobs}
per=collections.defaultdict(lambda:[0,0,0])
for jid,(sl,e) in exp.items():
    per[sl][0]+=e; per[sl][1]+=got.get(jid,0); per[sl][2]+= got.get(jid,0)==0
for sl,(e,g,z) in sorted(per.items()): print(f"{sl:<20}{g:>5}/{e:<5}{g/e:>6.0%}  empty={z}")
EOF
```

Yield falling monotonically with output length means truncation. Yield fine but validator rejects
high means a prompt or schema problem.

Pull `smoke.jsonl` down and run it through the real gate:

```bash
# locally
.venv/bin/python scripts/validate_data.py smoke.jsonl --out-dir data/generated
```

**Gate 1 — validator pass rate ≥ 75%.** Below that, fix the generation prompts in
`scripts/build_gen_jobs.py` and re-smoke. Do not start the full run to "see if it averages out" —
it won't, and a 50%-pass run costs the same as a 90% one.

**Gate 2 — composition. Do not skip this one.**

```bash
.venv/bin/python scripts/check_batch_composition.py smoke.jsonl
```

Pass rate asks *"is each row well-formed?"*. This asks *"is the SET the right shape?"* — and only
the second question catches the failure that actually happened on 2026-07-28: a regex bug silently
dropped every `verdict:"fix"` row, producing a 16,128-row correction slice with **zero corrections**.
Every surviving row was valid German, so the pass rate went **up** while the data became useless.
A model trained on pure `ok` rows learns to rubber-stamp everything — the exact profile the
scoreboard records for Llama-3.2-1B ("answered OK to all 69 errors").

The check gates on verdict mix (≥35% `fix`), HINT share of fix rows, per-phenomenon presence, and
scenario diversity. It fails the broken batches and passes the good ones — see
[`../../training-v2.md`](../../training-v2.md) §1.5b.

## 2. Full run

```bash
nohup python generate.py --jobs jobs.jsonl --out candidates.jsonl > gen.log 2>&1 &
tail -f gen.log
```

Resumable: completed `job_id`s land in `candidates.jsonl.done` and a rerun skips them. If the pod
dies (community cloud is interruptible), restart the same command — you lose the current chunk, not
the run.

## 3. Back on the Mac

```bash
# gate → data/generated/candidates.valid.jsonl (+ .rejected.jsonl with reasons)
.venv/bin/python scripts/validate_data.py candidates.jsonl --out-dir data/generated

# repack (metadata + grouped split + nudgeMe rendering)
.venv/bin/python scripts/pack_dataset.py --val-frac 0.05
.venv/bin/python scripts/pack_dataset.py --no-mixin --out-dir data/packed-nomixin

# sanity: did the HINT examples survive the gate?
python3 -c "import json; rows=[json.loads(l) for l in open('data/packed/train.jsonl')]; \
print(sum(1 for r in rows if any(m['role']=='assistant' and 'HINT:' in m['content'] for m in r['messages'])), 'HINT rows')"
```

Then **stop the pod.** Phase 2 is a different, much cheaper machine (RTX A6000 @ ~$0.33/hr).

## Reading the rejections

`data/generated/candidates.rejected.jsonl` carries a `reason` on every row. The common ones and
what they mean:

| reason | what to change |
|---|---|
| `languagetool: …` | the teacher's "correct" side isn't correct — a few are normal attrition; a spike means the prompt is inducing bad German |
| `conv: LT on assistant turn: …` | same, on a dialogue turn. The most common survivor: real German errors like a missing comma before `dass`, or `Check-in Schalter` for `Check-in-Schalter` |
| `content: fix identical to student` | the teacher echoed instead of correcting — the same echo failure the app's `parseCorrection` guards against |
| `content: hint reveals the correction` | tighten the HINT rule; over-rejection here is deliberate (a leaking hint defeats nudgeMe entirely) |
| `conv: too few messages` | the slice's schema asks for fewer than `validate_conversation`'s floor of 5 |
| `conv: roles must alternate…` | should be ~0 — `attach()` trims to start and end on the assistant. If it reappears, that trim broke |
| `schema: bad task/phenomenon` | the teacher invented its own metadata. `attach()` should be *forcing* the manifest's values, not `setdefault`-ing them |
| `native: needs a user turn and an assistant turn` | the teacher emitted only the answer. ~33% of this slice; over-provision rather than fight it |
| `vmp: prep '…' missing` / `structural: …` | teacher ignored the pinned target verb/preposition, or wrote an `ok` row that doesn't exercise the phenomenon |
| `eval-overlap` | the teacher reinvented a held-out item; working as intended — `data/eval/*.json` is auto-protected, including the naturalness bench |
| `duplicate` | raise generation temperature or widen the seed pool |
