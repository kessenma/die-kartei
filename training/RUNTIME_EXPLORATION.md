# On-device runtime exploration — status & handoff

**Question:** can a runtime other than MLX run the custom Gemma-4 German tutors **leaner /
on more devices** *without* losing quality? Two candidates evaluated: **Cactus**
(rejected) and **LiteRT-LM** (rejected).

## ⛔ TRACK CLOSED (2026-07-28) — answer is NO on both. Ship MLX.

Two independent runtimes, two independent INT4 quantizers, same verdict: **nothing tested
preserves the tune, and nothing beats MLX 4-bit (83% core / 85% ext / 2.71 GB peak).** MLX +
the custom Gemma-4 tutor is the best available option with today's technology. Do not reopen
without a *specific new capability* (see "What would reopen this" at the end).

**The lesson that now gates everything:** Gemma-4's **per-layer embeddings (PLE)** are
quantization-sensitive. Post-training INT4 that doesn't protect them wrecks the tutor. The MLX
4-bit build protects them (~5.2 bpw effective, via `--quant-predicate`). Any new runtime is judged
first on *does its INT4 path preserve PLE quality?* — speed/memory are secondary.

Companions: [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md) (eval source of truth),
[`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md) (the PLE / 3-bit / Cactus write-ups),
[`german-tutor-cactus-retrain-plan.md`](german-tutor-cactus-retrain-plan.md) (Cactus plan).

**Current status (2026-07-28): CLOSED. Nothing running, nothing billing — all RunPod pods
deleted, `runpodctl pod list` → `[]`.** Total spend for the whole LiteRT-LM spike: **$1.20**.

---

## Baselines to beat (app-guarded scale, verified with the shared scorer)

| Model (MLX 4-bit, shipped) | Core | Ext | False-corr | Miss | Disk | Peak RAM |
| -------------------------- | ---- | --- | ---------- | ---- | ---- | -------- |
| **E2B** German tutor       | 83%  | 85% | 3%         | 19%  | 3.3 GB | 2.71 GB |
| **E4B** German tutor (hero)| 90%  | 93% | 6%         | 9%   | 4.9 GB | 4.32 GB |

Focus is **E2B** (smaller tier; matches the Cactus comparison one-to-one). Escalate to E4B once a
pipeline is proven.

---

## Track 1 — Cactus: DONE, rejected ❌

Installed `cactus-compute==2.0.1` via `uv` at `training/.venv-cactus` (symlinked
`~/.local/bin/cactus`). Converted the fp16 E2B tune to a CQ4 bundle (`training/convert/e2b-cur-cq4`)
offline, ran it on Metal, and quality-gated it with the shared harness.

**Result: worse than MLX on both axes.**

| E2B, app-guarded | MLX 4-bit | Cactus CQ4 | Δ |
| ---------------- | --------- | ---------- | --- |
| Core (n=60)      | 83%       | **65%**    | −18 |
| Ext (n=61)       | 85%       | 72%        | −13 |
| Miss (n=69)      | 19%       | **43%**    | +24 |
| Disk             | 3.3 GB    | 3.9 GB     | bigger (bundles vision+audio towers) |

CQ4 reverts to bare `OK` on textbook reflexive/preposition/separable errors the tune was built to
catch (18 such regressions), and sometimes emits corrupted fixes (verb doubling) — the
over-quantization signature. It lands at the rejected MLX **3-bit** tier (63%/30%) despite being
nominally 4-bit, because Cactus exposes **no PLE-sparing quant** (`--bits` is integer-only).
Full write-up: [`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md) §"Cactus CQ4 runtime".
Responses saved at `results/cactus_e2b_cq4_{core,ext}.responses.json`.

**Verdict:** parked. Cactus only becomes interesting if it ships PLE-aware quantization.

---

## Track 2 — LiteRT-LM: IN PROGRESS 🔄

Google's own on-device runtime. Research verdict: **PARTIAL** — promising, with real risks.

**Good:**
- **iOS runtime ships** — LiteRT-LM v0.13, macOS+iOS **Swift Package (SPM)**, runs `.litertlm`,
  GPU backend. Cleaner than Cactus's manual xcframework.
- **Gemma 4 E2B/E4B are officially in the catalog** (prebuilt `.litertlm` under the
  `litert-community` HF org). No version-mismatch risk.
- **It has the PLE knob Cactus lacked:** `--externalize_embedder` memory-maps the per-layer
  embeddings separately at higher precision, outside the aggressive weight quant. This is the
  litert-torch equivalent of MLX's `--quant-predicate`. **So PTQ INT4 here might hold quality where
  Cactus's did not — that's the thing to test.**

**Risks / catches:**
- **Conversion is Linux-only** (`litert-torch` needs Linux + TF-nightly) → **RunPod**. The Mac stays
  the iOS-build machine.
- **Custom-fine-tune INT4 is PTQ, not QAT.** The public converter only does post-training quant
  (`dynamic_wi4_afp32_hadamard` for INT4). The proprietary mixed int2/4/8 **QAT** scheme that makes
  Google's official bundle good is **not exposed for custom models**.
- **Custom Gemma-4 E-series export has open correctness bugs** (litert-torch #994: `<pad>`-only
  output; #1001: custom checkpoint exports as "generic"). The converter is a v0.1 "unstable" preview.

Key sources: `github.com/google-ai-edge/LiteRT-LM`, `github.com/google-ai-edge/litert-torch`,
`developers.google.com/edge/litert-lm`, HF `litert-community/gemma-4-E2B-it-litert-lm`.

### The two-tier plan

**Tier 1 (cheap, test first):** convert the *existing* fp16 E2B tune with
`export_hf --externalize_embedder` + INT4 PTQ, then quality-gate. If it lands near MLX 83/85 → done,
no retraining.

**Tier 2 (only if Tier 1 *converts but degrades*):** re-fine-tune as **QAT** on Google's Gemma-4 E2B
**QAT checkpoint** (Unsloth + TorchAO), then convert. QAT-conditioned weights survive 4-bit rounding.

**Decision fork — which failure are we looking at?**
- Converts but quality worse → try **Tier 1.5 first** (below), then **Tier 2**. ✅
- Converter itself breaks (`<pad>` / generic export) → **Tier 2 is blocked too** — the final step is
  the same `export_hf`; QAT changes weights, not the converter. Report as an upstream bug. ❌

### Tier 1.5 — better PTQ before paying for QAT (NEW, 2026-07-27)

The original fork jumped straight from "plain INT4 PTQ" to "re-fine-tune as QAT". `ai-edge-quantizer
0.7.0` exposes a **cheaper middle rung**: the recipe helpers take an `algorithm_key`, and
`AlgorithmName` includes `HADAMARD_ROTATION`, `DECOMPOSED_HADAMARD_ROTATION`, `GPTQ`, `OCTAV`, and
`MSE` — not just the default `MIN_MAX_UNIFORM_QUANT`. Hadamard rotation is exactly the
outlier-smoothing trick that makes INT4 PTQ survive, and it has a **specialized
`materialize_embedding_lookup_custom_op`** — i.e. it can protect the embedding path specifically.

The CLI can't pass `algorithm_key` (it calls `recipe_lib.__dict__[name]()` with no args), **but
`quantize_model` accepts a `.json` recipe path** (`if quantization_recipe.endswith('.json')`). So a
custom JSON recipe can mix algorithms per-tensor — e.g. Hadamard/8-bit on the embedder and
per-layer-embedding tensors, INT4 elsewhere. That is the real analogue of MLX's `--quant-predicate`,
and it costs one more conversion run (~10 min, ~$0.08) instead of a QAT retrain.

**Revised escalation:** plain `dynamic_wi4_afp32` → Hadamard/GPTQ JSON recipe → QAT retrain.

### Tier-1 command (ACTUAL, verified 2026-07-27 on litert-torch 0.9.1)

The command sketched from research above is stale in three ways — corrected here:

```bash
# on the pod (Linux), py3.11 venv, litert-torch 0.9.1:
litert-torch export_hf /root/e2b-fp16 /root/out-e2b-int4 \
  --task=text_generation \
  --externalize_embedder=True \
  --cache_length=2048 \
  --experimental_lightweight_conversion=True \
  --quantization_recipe=dynamic_wi4_afp32
```

1. **Positional, not flags** — `export_hf MODEL OUTPUT_DIR`; `--model=`/`--output_dir=` don't exist.
2. **The recipe name `dynamic_wi4_afp32_hadamard` does not exist.** Valid names are the function
   names in `ai_edge_quantizer/recipe.py`: `dynamic_wi4_afp32`, `dynamic_wi8_afp32`,
   `weight_only_wi4_afp32`, `weight_only_wi8_afp32`, `static_wi8_ai8`, `static_wi8_ai16`.
   Hadamard is not a recipe — it's an **algorithm** (see the new middle rung below).
3. **`--experimental_lightweight_conversion=True` is required at this box size** — see blockers.

### Toolchain reality vs. the research assumptions

**The version risk is gone.** Installed today: `litert-torch 0.9.1`, `litert-lm-builder 0.14.0`,
`ai-edge-quantizer 0.7.0`, `litert-converter 0.2.0`, `torchao 0.17.0`. The open correctness bugs
this doc worried about (#994 `<pad>`-only output, #1001 "generic" export) were filed against the
v0.1.x preview. 0.9.1 also adds `--auto_model_override`, a direct escape hatch for #1001.
`bundle_litert_lm: True` is the default, so `export_hf` emits the `.litertlm` directly — no
separate `litert-lm-builder` assembly step needed.

**Three blockers hit and cleared (none were Gemma-4 export defects):**

1. **`TypeError: Can't instantiate abstract class LiteRTLMCacheLayerForGemma4 with abstract
   method get_max_length`.** litert-torch declares `transformers` with **no version pin**, so uv
   pulls 5.14.1, where `CacheLayerMixin.get_max_length` is `@abstractmethod`. litert-torch 0.9.1
   only implements `get_max_cache_shape`. Identical semantics ("max sequence length the layer can
   hold"). Fix — 2-line shim in
   `litert_torch/generative/export_hf/core/cache.py` next to `get_max_cache_shape`:
   ```python
   def get_max_length(self) -> int:
     return self.max_cache_len
   ```
   Reapply after any reinstall. (Upstream-reportable: missing transformers pin.)
2. **OOM, exit 137, at ~5.5 min.** The container cap is **50 GB** — `free -g` reports the *host*
   (503 GB), not the cgroup; read `/sys/fs/cgroup/memory.max`. `prefill_lengths` was already
   minimal (`[128]`). Fix: `--experimental_lightweight_conversion=True`, which sets
   `enable_resource_constants` so weight tensors are not inlined into the MLIR. Peak RSS dropped to
   a flat **~21 GB**. A 50 GB box is enough *with* this flag.
3. **Every released `litert_lm_main` binary fails to load** — v0.14.0 `macos_arm64` and v0.11.0
   `linux_x86_64` both miss their Bazel runfiles shared libs (`libGemmaModelConstraintProvider`,
   `libLiteRt`), which ship in no release asset. This is a packaging bug, not a platform issue, and
   it kills the "serve an OpenAI endpoint + reuse `gen_cactus_responses.py`" plan.
   **Workaround:** `CLiteRTLM_mac.xcframework`'s `libCLiteRTLM_mac.dylib` (138 MB) *is*
   self-contained (system frameworks only). New `scripts/litertlm_runner.c` drives that C API
   directly, one fresh conversation per item; `scripts/gen_litertlm_responses.py` prepares prompts
   and folds driver output back into the harness's responses JSON. **Bonus: this is the same C API
   the iOS app would use, so it de-risks integration too.**
4. **C-API traps (v0.14.0) — all found by running the official bundle first, before trusting ours:**
   - The **low-level session path is a dead end**: `generate_content` and
     `run_prefill`+`run_decode` both return 1 candidate whose text is **always empty**, with no
     error. Only the **Conversation API** (`litert_lm_conversation_send_message`) returns text.
   - `litert_lm_conversation_config_set_system_message` takes a **PLAIN string**. Passing
     `{"role":"system",...}` JSON is **silently ignored** — no error, the prompt just has no effect.
     Verified with a forcing prompt ("answer only BANANE"): plain works, JSON doesn't. Since the
     whole eval lives in the system message, this would have silently invalidated every number.
   - **Samplers are unreliable:** `TopK`(1) → `UNIMPLEMENTED: Sampler type: 1 not implemented yet`;
     `Greedy`(3) errored in the session path; attaching sampler params to a conversation's session
     config can make `send_message` return NULL. The **default** (no sampler params) was verified
     deterministic across repeated identical runs, so the driver uses it.
   - Consequence: prompts are templated **by the runtime**, not pre-rendered by us — so the system
     and user turns match the MLX run, but the template application is LiteRT-LM's own.
5. **Custom `.json` quantization recipes are broken out of the box.**
   `resolve_recipe` → `_get_named_recipe` unconditionally does `_RECIPE_REPO_PATH.iterdir()` on
   `ai_edge_quantizer/recipes/`, **a directory the wheel does not ship** → `FileNotFoundError`,
   surfaced only as a generic `ValueError: Invalid quantization recipe: <path>. Please check the
   recipe name.` Fix: `mkdir -p .../site-packages/ai_edge_quantizer/recipes`. Worse, the recipe is
   validated **only at the quantize step, ~10 min into the export** — so **always pre-validate**
   (this cost one wasted run):
   ```python
   from ai_edge_quantizer.utils import recipe_utils
   from ai_edge_quantizer import recipe_manager
   r = recipe_utils.resolve_recipe("/path/recipe.json")       # gate 1: resolves
   recipe_manager.RecipeManager().load_quantization_recipe(r)  # gate 2: accepted
   ```

**Maturity read:** five distinct packaging/versioning defects (no transformers pin; >50 GB RAM to
convert a 2 GB phone model; every CLI binary missing its dylibs; unimplemented samplers + a
silently-empty session API; broken custom-recipe loading). Nominally 0.9.1, in practice still
preview-grade. Weigh this before betting a shipping tier on it.

---

### TIER-1 RESULT (2026-07-27): converts cleanly, but quality COLLAPSES ❌

**The conversion question is answered YES.** `export_hf` produces a runnable custom Gemma-4 E2B
`.litertlm` — 2.60 GB, loads in ~3 s, generates real tokens, **not `<pad>`**, **not** a "generic"
export, **0 format errors** across all 121 eval items. Upstream bugs #994/#1001 are not reproducible
on 0.9.1. Peak RSS **50.6 GB** (so the 46.6 GB first box missed by ~4 GB; ~51 GB is the real bar).

**The quality question is answered NO — emphatically.**

| Our E2B tune, app-guarded | MLX 4-bit (shipped) | LiteRT-LM INT4 PTQ | Δ |
| ------------------------- | ------------------- | ------------------ | --- |
| Core (n=60)  | 83% | **40%** (24/60) | **−43** |
| Ext (n=61)   | 85% | **41%** (25/61) | **−44** |
| False-corr   | 3%  | 0%              | — |
| **Miss rate**| 19% | **90%** (62/69) | **+71** |
| Disk         | 3.3 GB | 2.60 GB | smaller |

**Failure mode: the tune goes silent.** 46/60 core responses are a bare `OK`; only **2** items
produce a `FIX` line at all. 0% false-corrections is not discipline here — it is a model that has
stopped correcting anything. For scale, the *stock* official QAT bundle emits 16 `FIX` lines on the
same 60 items and misses 61%; our **fine-tuned** weights under INT4 PTQ miss **90%**, i.e. worse
than stock. The fine-tune's entire learned error-detection behaviour is destroyed by the quantizer.

This lands well below the rejected tiers: Cactus CQ4 65% / 43% miss, MLX 3-bit 63%. It is the
**worst** quantization result recorded for this model, and it is the same PLE-damage signature —
consistent with `--externalize_embedder` separating the per-layer embeddings but **not** protecting
them: the 9.4 GB fp32 PLE is quantized to 1.10 GiB by the same INT4 recipe as everything else.
`--externalize_embedder` controls *layout*, not *precision* — the doc's assumption that it implied
higher precision was wrong.

Artifacts: `results/litertlm_e2b_tune_int4_{core,ext}.responses.json`,
bundle at `convert/litertlm/e2b-tune-int4.litertlm`.

#### …but the MEMORY result is the reason to keep going (2026-07-27)

Measured with `/usr/bin/time -l` around the C driver, macOS CPU backend:

| E2B tune                | Peak RSS | Disk |
| ----------------------- | -------- | ---- |
| MLX 4-bit (shipped)     | 2.71 GB  | 3.3 GB |
| **LiteRT-LM INT4**      | **1.97 GB** | 2.60 GB |
| official stock QAT      | 2.51 GB  | 2.59 GB |

**−0.74 GB peak RAM vs MLX, a 27% cut** (LiteRT-LM mmaps weights instead of resident-loading).

This re-frames the entire track. The point of LiteRT-LM is **not** marginal leanness on iOS — MLX
already ships and wins on quality. The point is that **1.97 GB is the only measured path toward an
E2B-class model on a 4 GB iPhone**, a tier that currently tops out at Gemma 3 1B stock (58% core)
because 3-bit E2B can't get there (PLE blocks sub-~5 bpw; see `GEMMA_E2B_FINETUNING.md`).

⚠️ Caveats: macOS CPU backend, not iOS — jetsam limits and app overhead differ, and a 4 GB device's
per-app budget (~2 GB) makes 1.97 GB *marginal, not comfortable*. Needs on-device measurement before
anyone plans around it. And a 1.97 GB model at 40% core is worthless — memory only matters if
Tier 1.5 / Tier 2 recovers quality.

**Consequence for the Tier-2 decision:** pre-measurement, a QAT retrain was hard to justify (spend
GPU hours to *match* quality MLX already delivers). Post-measurement it has a real prize: a device
tier not currently servable at all.

### TIER-1.5 / 1.6 RESULT (2026-07-28): both escalations fail. Track closed ❌

Two attempts to recover quality; both dead ends.

**(a) Hadamard rotation — cannot be used at all.** `HADAMARD_ROTATION` is registered for
`FULLY_CONNECTED` + `EMBEDDING_LOOKUP` and looked like the PLE-sparing lever. It isn't:
`get_tensor_quant_params` raises **"Hadamard rotation is only supported for weight tensors"** when
`tensor_content is None`, i.e. it is incompatible with *dynamic* quantization (activations have no
static content). Hadamard is therefore only available in the weight-only mode — which (b) rules out.

**(b) `weight_only_wi4_afp32` — the model is destroyed.** Its docstring promises float compute
"thus retain model quality". Actual first response on `vmp-e1`:

```
"Correction:"Ich habegeboten den dasselbeftenechemelecebfreiechenslechdenknebengebenichtsweichen…
```

Token salad — not degraded German, *destroyed* German, plus the wrong response format. Disqualified
three times over, any one fatal:

| weight-only INT4 | Measured | Needed |
| ---------------- | -------- | ------ |
| Peak RAM | **~10–11 GB** (explicit dequantize materialises float weights) | <2 GB for a 4 GB phone |
| Speed | **~4 min/item** on Mac CPU (121-item suite ≈ 8 h) | interactive |
| Output | corrupted, wrong format | valid `FIX:` lines |

Full suite abandoned deliberately — 8 h of wall-clock to characterise a build already dead on
memory *and* latency was not a sensible spend. The 3-item smoke was conclusive.

### The verdict, and why the 4 GB tier does not fall out of this

**INT4 wrecks this model at the *weight* level, not just the activation level.** The two public
paths fail in opposite directions, which is what closes the door:

| Config | Peak RAM | Quality |
| ------ | -------- | ------- |
| INT4 weights + INT4 activations (`dynamic_wi4_afp32`) | **1.97 GB** ✅ | **40%** ❌ silent rubber-stamp |
| INT4 weights + float compute (`weight_only_wi4_afp32`) | ~10 GB ❌ | ❌ gibberish |
| INT8 weights (the obvious fix) | ~3.5–4 GB ❌ | probably fine |

⚠️ **Correction to the earlier optimism in this file:** the attractive 1.97 GB / −27% RAM number
belongs *only* to the config that scores 40%. It is not a standing win. Every fix that restores
quality raises precision somewhere, and the PLE is the largest tensor group in the bundle
(1.10 GiB of 2.43 GB at INT4) — so protecting it lands ~3.5 GB, i.e. **worse than the MLX 4-bit
build's 2.71 GB**. MLX already does exactly this mixed-precision PLE protection at ~5.2 bpw.
**LiteRT-LM cannot beat MLX on memory while remaining coherent**, so it does not unlock a 4 GB tier.

**Tier 2 (QAT) not attempted, deliberately.** Even on success it would have to clear MLX's 2.71 GB
to be worth anything for the 4 GB goal, and the analysis above says it can't: the good mixed
int2/4/8 QAT scheme is Google-internal and **not exposed for custom models**, so our QAT weights
would still exit through the same public PTQ converter that just destroyed them twice. Spending
GPU hours for that was not justified.

**Confirms the Cactus finding on a second, independent runtime:** Gemma-4's PLE needs
high-bit protection that neither Cactus CQ4 nor ai-edge-quantizer INT4 provides.

### What would reopen this

Only a *specific new capability* — not a version bump:
1. `ai-edge-quantizer` exposing **per-tensor mixed precision under INTEGER compute** (a real
   `--quant-predicate` analogue: INT4 linear layers + higher-bit PLE, activations ≥ INT8).
2. Google exposing the **mixed int2/4/8 QAT** path for custom checkpoints.
3. A LiteRT-LM release whose CLI binaries actually load (see defect #3) — a cheap proxy for the
   project's packaging health.

For the **4 GB tier**, the more promising direction is a genuinely smaller *base* model, not
harder quantization of E2B. [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md) found a 58% floor,
but that sweep predates several small multilingual releases and is worth re-running first.

**Salvage — what this spike leaves behind, all still useful:**
- `scripts/litertlm_runner.c` + `scripts/gen_litertlm_responses.py` — a working LiteRT-LM eval
  seam, and a **proven C-API integration path** if the runtime ever matures.
- The control-run methodology (validate the rig on a known-good official bundle *before* trusting
  your own artifact) — it caught the empty-text and system-message traps for free.
- Five documented upstream defects with exact fixes, so a future attempt starts from working ground.

---

### Control run — official bundle through the same harness (2026-07-27)

Before trusting any number from our own conversion, the whole path was validated against
Google's **prebuilt** `litert-community/gemma-4-E2B-it.litertlm` (2.59 GB, ungated, INT4 **QAT**)
— stock Gemma-4 E2B, not our tune. Run on the Mac, CPU backend, ~3 s/item.

| Official stock E2B, LiteRT-LM INT4-QAT, app-guarded | Result |
| --------------------------------------------------- | ------ |
| Core (n=60)   | 34/60 = **57%** |
| Ext (n=61)    | 40/61 = **66%** |
| False-corrections | **0%** (0/32) |
| Miss rate     | **61%** (42/69) |
| Format errors | **0** on both suites |

Responses at `results/litertlm_official_e2b_stock_{core,ext}.responses.json`.

**Why this matters:** zero format errors and clean `OK` / `FIX:` / `WHY:` output prove the C-API
driver, the system-message plumbing, and the scoring seam are all faithful. And the 0% false-
correction / 61% miss shape is exactly the known *stock* E2B behaviour profile (rubber-stamps
everything, catches little) — the harness reproduces a model's character, not just its score.
So any degradation seen in our own converted tune is attributable to the conversion, not the rig.

⚠️ Do **not** read the 57% as a runtime-vs-runtime verdict: this is a *stock* model and the MLX
stock E2B numbers on the scoreboard come in several guard/scoring variants. The only clean
comparison is our own tune, same weights, same guard, MLX vs LiteRT-LM.

---

## Environment & assets (all confirmed present)

**RunPod** (paid, cost-guarded):
- `runpodctl` authed (`~/.runpod/config.toml`), balance ~$17.9; RunPod MCP also authed.
- SSH key **`runpod-gemma-training`** registered; private key `~/.ssh/runpod_gemma_ed25519`.
- Community **RTX 3090 @ $0.22/hr** is the target box (24 GB VRAM; 4090 community stock was tight).
- Image: `runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404`.
- **Always** create with `--terminate-after <now+Nh>` as the cost backstop; tear down with
  `runpodctl pod delete <id>`; confirm with `runpodctl pod list` → `[]`.
- ⚠️ **Gotcha:** community machines can stall on a cold image pull (one sat at `uptimeSeconds: 0`
  for 13 min). Poll readiness on **`uptimeSeconds > 0`** (the `ssh info` "not ready" check gave a
  false positive); kill a stalled machine fast and try another, or fall back to a lighter image
  (conversion is CPU-bound, so heavy CUDA/torch isn't strictly required for Tier 1).

**Local conversion inputs:**
- fp16 merged **E2B** — HF `kessenma/gemma4-e2b-german-tutor` (**private**, ~9.6 GB), also cached at
  `~/.cache/huggingface/hub/models--kessenma--gemma4-e2b-german-tutor`.
- fp16 merged **E4B** — `kessenma/gemma4-e4b-german-tutor` (~15 GB).
- **E2B LoRA adapter** (79 MB) — `training/runpod/e2b_artifacts/gemma4-e2b-german-lora`.
- **HF token** at `~/.cache/huggingface/token` — pull the private repo on the pod by piping this file
  over the SSH channel via stdin (value never appears in a command/log):
  `ssh <pod> 'mkdir -p ~/.cache/huggingface && cat > ~/.cache/huggingface/token' < ~/.cache/huggingface/token`

**Eval harness (the runtime-agnostic seam):**
- `scripts/gen_cactus_responses.py` — generates responses from any OpenAI-compatible endpoint using
  the harness's exact prompts (`--port`); **reuse it pointed at the LiteRT-LM server**.
- Score: `scripts/run_baseline_eval.py --responses <file> --app-guard --eval-file <core|ext>` and
  `scripts/behavior_metrics.py --app-guard <core> <ext>`.
- Eval data: `data/eval/grammar_eval_v0.json` (core 60), `data/eval/grammar_eval_v1_extra.json`
  (ext 61). Run scorers with `training/.venv/bin/python`.

---

## Open questions / risks
- [ ] Does `export_hf` produce a **runnable** custom Gemma-4 E2B `.litertlm` (not `<pad>`, not
      "generic")? — Tier-1 conversion answers this.
- [ ] Does INT4 PTQ **+ `--externalize_embedder`** preserve quality (near MLX 83/85), or degrade like
      Cactus? — Tier-1 eval answers this. **This is the whole bet.**
- [ ] If Tier 2: is Google's Gemma-4 E2B QAT checkpoint gated? (token already handled.) Does QAT
      survive the PTQ-INT4 convert?
- [ ] iOS integration cost: SPM `LiteRTLM`, `Engine`/`Conversation` API, `.gpu` backend, min iOS
      version, real device peak RAM. (Deferred until a quality-passing bundle exists.)

---

## Resume checklist

1. Reprovision a fresh community pod (loop GPUs; poll on `uptimeSeconds > 0`; kill slow machines):
   ```bash
   TERM=$(date -u -v+3H +%Y-%m-%dT%H:%M:%SZ)
   runpodctl pod create --name gemma4-e2b-litert \
     --image runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404 \
     --gpu-id "NVIDIA GeForce RTX 3090" --cloud-type COMMUNITY \
     --ports "22/tcp,8080/http" --container-disk-in-gb 40 --terminate-after "$TERM" -o json
   ```
2. SSH in (`~/.ssh/runpod_gemma_ed25519`); install `uv`, make a **py3.11** venv, `pip install
   litert-torch ai-edge-litert ai-edge-quantizer` (+ tf-nightly / torch as its deps require).
3. Pipe HF token to pod (above); `hf download kessenma/gemma4-e2b-german-tutor --local-dir /root/e2b-fp16`.
4. Run the **Tier-1 `export_hf`** command above; **validate real-token generation**.
5. Serve the `.litertlm` (LiteRT-LM OpenAI-compatible CLI, bind `0.0.0.0:8080`), run
   `gen_cactus_responses.py --port <mapped>` for core+ext, score with the harness.
6. Read the fork: near MLX → success/document; converts-but-worse → **chain Tier 2 (QAT)** on the
   same pod (extend `--terminate-after` first); won't convert → report the upstream bug.
7. `runpodctl pod delete <id>`; confirm `runpodctl pod list` → `[]`. Update this file with results.
