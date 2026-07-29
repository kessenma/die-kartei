# German Tutor — Cactus Runtime & Retraining Plan

**Base model:** `unsloth/gemma-4-E4B-it` (Gemma **4**, E-series; chat template `gemma-4`)
— confirmed in [training/runpod/train_gemma4_e4b.py](runpod/train_gemma4_e4b.py#L31).
**In-app models (MLX 4-bit today):**
`kessenma/gemma4-e4b-german-tutor-4bit` (`MLXModel.gemma4_E4B_german`, hero) and
`kessenma/gemma4-e2b-german-tutor-4bit` (`MLXModel.gemma4_E2B_german`).
**Training data:** `kessenma/gemma4-german-tutor-data`
**Goal:** keep the shipping MLX runtime + both custom Gemma-4 tutors, and **add a
Cactus runtime alongside it** to test whether Cactus builds run leaner and widen the
range of devices the app supports. Retraining for quality is a *separate, optional track.*
**Compute:** RunPod on-demand GPU (retrain sweep only — the Cactus spike is local).

---

## 0. Two tracks — and which one is actually your goal

This started as a *retraining* plan. Your goal is a *runtime* plan. Keep them separate,
because sequencing them wrong wastes GPU time and, worse, wastes it before you know whether
Cactus is even worth integrating.

- **Track 1 — Cactus runtime (your stated goal).** Does Cactus run your *existing*
  Gemma-4 tutor leaner than the MLX 4-bit build, and does that widen device reach? This
  rides entirely on the adapter you already trained. **No retraining required. No GPU
  required** — `cactus convert` runs locally. Start here.
- **Track 2 — Quality retrain (optional, separable).** Fix the echo failure / beat the eval
  baseline. Worth doing on its own merits, but it is *not a prerequisite* for Track 1, and
  it reuses Track 1's conversion pipeline unchanged once that pipeline is proven.

**The order that matters:** prove Cactus locally on the current model (Phase 0), decide
whether to wire it into the app (Phase 1), *then* — and only if it earns it — spend effort
on retraining (Phases A–E). The tempting order (retrain first, port later) spends real
effort on a runtime you haven't validated.

Rule #2 below is what makes this possible: the LoRA adapter is the master asset, so every
runtime is a one-command job from it. You do not need a new training run to answer "is
Cactus worth it."

---

## 1. Baselines to beat

### Quality (from the current E2B card, echo filter applied to both sides)

| Metric                            | Stock E2B | Current fine-tune | Target |
| --------------------------------- | --------- | ----------------- | ------ |
| Core suite (4 target areas, n=60) | 73%       | 83%               | ≥ 85%  |
| Extension (untargeted, n=61)      | 85%       | 85%               | ≥ 85% (no regression) |
| False corrections (n=32)          | 0%        | 3%                | ≤ 3%   |
| Missed / mis-fixed (n=69)         | 28%       | 19%               | ≤ 15%  |
| Separable verbs                   | 11/15     | 8/15 ⚠️            | ≥ 12/15 |
| Reflexives                        | 8/15      | 12/15             | ≥ 12/15 |

**Raw (unfiltered) false-correction rate: 59%.** Track this separately from the filtered
number every run. The filter is a safety net, not a fix, and if requantization makes the
raw rate worse you want to see it.

### Footprint (measured today, MLX 4-bit)

These come straight from the app's descriptors
([Models/MLXModel+Descriptors.swift](../german-ai-flashcards/Models/MLXModel+Descriptors.swift)):

| Artifact                       | On disk (dl) | Peak RAM (`measuredPeakMB`) | Min RAM tier |
| ------------------------------ | ------------ | --------------------------- | ------------ |
| E4B, MLX 4-bit (hero, current) | ~5.0 GB      | 4330 MB                     | 8 GB         |
| E2B, MLX 4-bit (current)       | ~3.3 GB      | 2710 MB                     | 6 GB         |

**The Cactus footprint is a hypothesis to measure, not a target to assume.** A realistic
prior: a stock Gemma-E2B **Q4 GGUF is ~2.8–3.0 GB on disk** — the per-layer-embedding
table inflates a "2B-effective" model toward ~5B real parameters, so ordinary 4-bit does
*not* land near 1 GB. Cactus's CQ4 plus 2-bit *embedding* quantization (TurboQuant-H) may
cut this substantially, but **no published Cactus number confirms a sub-1.2 GB E2B**, and
aggressive embedding quant carries quality risk. So the Phase-0 question is literally
"what are the real disk/RAM numbers?", not "did we hit 1.2 GB?" Fill the table in Phase 0
before committing to any footprint claim.

---

## 2. Artifact policy (non-negotiable rules)

1. **Never quantize a quantized checkpoint.** Every deployment artifact is built from the
   BF16 merged model or from base + adapter. The 4-bit MLX repos are terminal outputs.
2. **The LoRA adapter is the master asset.** Publish it separately. It's a few MB and it
   makes every future runtime a one-command job — this is the rule that lets Track 1
   proceed on the current model with no retraining. If only the merged 4-bit build
   survives, you've lost the ability to target anything new.
3. **Keep the BF16 merged model.** It's the eval reference — the ceiling that tells you
   how much each quantization actually cost.
4. **One `model.safetensors` per MLX inference repo.** MLX Swift recursively merges every
   `*.safetensors` it finds; a stray adapter folder breaks loading with
   `Unhandled keys ["base_model"]`. Keep it true.
5. **Version every artifact with the training run ID.** `e2b-r3-cq4`, not `e2b-cq4`.
   You will run this loop enough times that ambiguity becomes expensive.

---

## 3. Phase 0 — Cactus spike (local, current adapter — DO THIS FIRST)

The whole point: find out cheaply whether Cactus is worth integrating **before** you touch
the app or the GPU. Everything here runs on your Mac against the adapter you already have.

### 3.0. Cactus reality check (read before you budget anything)

Verified against the Cactus repo/docs — correct these assumptions up front:

- **License is source-available, NOT open source.** The grant covers individuals /
  non-commercial and orgs under **$2M funding AND under $2M revenue**; crossing either
  ends the grant (30-day window to buy a commercial license). Fine for a solo dev today —
  but it's a real dependency decision, so make it consciously before wiring Cactus into a
  shipping app. `LICENSE` in `cactus-compute/cactus`.
- **Swift integration is manual, not SPM (officially).** Build with `cactus build --apple`,
  then drag `cactus-ios.xcframework` into Xcode (Embed & Sign), or link the static lib +
  `module.modulemap`. There's a *third-party* SPM wrapper (`mhayes853/swift-cactus`,
  tracks ~engine v1.14) if you'd rather. **Pin a Cactus version** — the API churns
  (v2.0.1 removed the CoreML backend).
- **Gemma is in the "especially tested" set**; arbitrary-HF conversion is self-described
  **experimental**. Gemma 4 conversion landed around v1.12/v1.14. Expect to debug the
  converter at least once.
- **CQ is real: CQ4/CQ3/CQ2 uniform, CQ3.26/CQ2.54 mixed-precision.** But the `--bits`
  flag is **integers only** (`1|2|3|4`) — there is no documented `--bits 3.26`. How the
  mixed schemes get selected is not documented in the CLI; confirm before relying on them.

### 3.0.5. Local assets already on disk (verified 2026-07-26 — no HF download needed)

The merged BF16 tutors and the E2B adapter are **already on this machine**, so Phase 0
needs no model download — only the Cactus toolchain itself. Convert straight from these.

| Asset | Path (slug) | Size / precision |
| ----- | ----------- | ---------------- |
| Merged BF16 **E4B** (hero) | `~/.cache/huggingface/hub/models--kessenma--gemma4-e4b-german-tutor` — slug `kessenma/gemma4-e4b-german-tutor` | 15 GB, single `model.safetensors`, `bfloat16`, no `quantization_config` |
| Merged BF16 **E2B** | `~/.cache/huggingface/hub/models--kessenma--gemma4-e2b-german-tutor` — slug `kessenma/gemma4-e2b-german-tutor` | 9.5 GB, `bfloat16`, full precision |
| **E2B LoRA adapter** (master asset, rule #2) | [training/runpod/e2b_artifacts/gemma4-e2b-german-lora/](runpod/e2b_artifacts/gemma4-e2b-german-lora) | 50 MB, r=8 α=16, base `unsloth/gemma-4-e2b-it-unsloth-bnb-4bit` |
| Stock MLX 4-bit bases | `~/.cache/huggingface/hub/models--mlx-community--gemma-4-e{2,4}b-it-4bit` | 3.3 / 4.8 GB — **already 4-bit, do NOT convert (rule #1)** |

- The `kessenma/*` merged repos are **base+adapter already merged**, so convert them
  directly with **no `--lora`**. They satisfy rule #1 (full-precision source) and are the
  BF16 eval reference of rule #3.
- No E4B adapter is on disk, but none is needed — convert the merged E4B directly.
- The `unsloth/gemma-4-E{2,4}B-it` BF16 *base* referenced elsewhere in this plan is **not**
  cached; the base+adapter commands would pull it (~10 GB+). Prefer the merged-repo route
  on a slow link.

### 3.1. Publish the adapter (free, do it first — rule #2)

Push the current E4B/E2B LoRA adapters to HF (private is fine). This is the master asset
and it's the input to every convert command below.

### 3.2. Convert the existing adapter with Cactus

Real converter surface (**field-tested on installed cactus 2.0.1**). The short `cactus --help`
hides most flags; the full set (`cactus convert --help`) includes `--weights-only`,
`--weights-dir <path>`, `--artifact-dir <path>`, `--task`, `--skip-model-load`,
`--low-memory-load`, and fusion toggles — so those *do* exist. Core surface:
`cactus convert <model> [dir] --bits 1|2|3|4 --token <t> --reconvert --lora <path>`.
`--lora` takes a **local path**; `<model>` may be an HF slug *or* a local path; `[dir]` is the
output bundle dir.

**Convert is two-phase:** (1) quantize weights to CQ, then (2) build the runtime graph. A bundle
is only runnable once phase 2 finishes.

> **Gotcha (verified on 2.0.1): pass an ABSOLUTE output path.** A *relative* `[dir]` quantizes the
> weights fine (you'll even see "Model converted and ready…") but phase 2 re-resolves the weights
> dir against the wrong cwd and dies with
> `RuntimeError: weights_dir does not exist: <venv>/lib/python3.12/<your-relative-path>` (exit 1),
> leaving a weights-only bundle with no graph. An absolute path lets phase 2 complete.

**Running a bundle:** `cactus run <abs-bundle-path>` runs a *complete* bundle. If phase 2 never ran,
`run` won't recognize the dir as a bundle — it treats it as HF source and errors on a missing
`model.safetensors`. Convert also runs automatically inside `run`/`serve`/`download`, so
`HF_HUB_OFFLINE=1 cactus run kessenma/gemma4-e2b-german-tutor --bits 4` converts-then-runs in one
shot from cache (into cactus's own cache dir, which avoids the relative-path gotcha).

```bash
# Merges the adapter at convert time. Start at 4-bit; then try 3 and 2 for the size/quality curve.
cactus convert unsloth/gemma-4-E2B-it ./e2b-cur-cq4 --lora ./adapters/e2b-current --bits 4
cactus convert unsloth/gemma-4-E2B-it ./e2b-cur-cq3 --lora ./adapters/e2b-current --bits 3
cactus convert unsloth/gemma-4-E2B-it ./e2b-cur-cq2 --lora ./adapters/e2b-current --bits 2
```

**Preferred on a slow link (no model download).** You already have the merged BF16 tutors
cached (§3.0.5), so convert those directly — no `--lora`, and force offline so Cactus can
only touch the cache:

```bash
# E2B — cached slug + offline, zero network for the model.
# NOTE: use an ABSOLUTE output path — a relative dir trips the phase-2 gotcha above.
HF_HUB_OFFLINE=1 cactus convert kessenma/gemma4-e2b-german-tutor "$PWD/convert/e2b-cur-cq4" --bits 4   # ✅ verified 2026-07-26
HF_HUB_OFFLINE=1 cactus convert kessenma/gemma4-e2b-german-tutor "$PWD/convert/e2b-cur-cq3" --bits 3
HF_HUB_OFFLINE=1 cactus convert kessenma/gemma4-e2b-german-tutor "$PWD/convert/e2b-cur-cq2" --bits 2

# E4B — from the merged repo (no adapter needed)
HF_HUB_OFFLINE=1 cactus convert kessenma/gemma4-e4b-german-tutor "$PWD/convert/e4b-cur-cq4" --bits 4

# Sanity-run a finished bundle (offline, forced on-device):
HF_HUB_OFFLINE=1 cactus run "$PWD/convert/e2b-cur-cq4" --no-cloud-handoff \
  --system "Du bist ein geduldiger Deutschlehrer." --prompt "..." --max-new-tokens 200
```

Passing the cached slug with `HF_HUB_OFFLINE=1` resolves to the local snapshot (verified)
and sidesteps whether the CLI accepts a bare local path; if a needed file isn't cached it
errors instead of downloading. The base+adapter form above stays valid for the Track-2
retrain, where you convert a *fresh* adapter against the base.

This answers the plan's central open question in one afternoon: **does `cactus convert`
even handle a Gemma-4, LoRA-merged checkpoint** (per-layer embeddings + AltUp intact)? If
it errors, you've spent $0 and learned the integration is blocked upstream.

### 3.3. Sanity-run locally + record real footprint

Run a few tutor turns through the converted bundle on the Mac (Cactus CLI/host), then fill
in the numbers that don't exist yet:

| Artifact       | On disk | Loads? | Coherent German? | Echo behavior vs MLX | Notes |
| -------------- | ------- | ------ | ---------------- | -------------------- | ----- |
| `e2b-cur-cq4`  | **3.9 GB** | ✅ Metal GPU | ✅ correct | 1/1 correct FIX, no echo (echo-on-correct not yet tested) | 75.9 tok/s decode; cactus-reported RAM **851.8 MB** (weights mmap'd); bundle includes vision+audio towers |
| `e2b-cur-cq3`  | _tbd_   | _tbd_  | _tbd_            | _tbd_                | not yet run |
| `e2b-cur-cq2`  | _tbd_   | _tbd_  | _tbd_            | _tbd_                | not yet run |

**Measured 2026-07-26 (E2B CQ4, current merged tutor, offline from cache):**
- **Converts cleanly.** All 1951 tensors loaded; graphs captured for every component
  (`vision_encoder`, `audio_encoder`, `lm_encoder`, `decoder_*`) → `components/*/graph.cactus`.
  Gemma-4 per-layer embeddings + AltUp are **not** a blocker for `cactus convert`.
- **Runs + coherent, correct German.** Prompt "Korrigiere … 'Ich habe gestern ins Kino
  gegangen.'" → "Der richtige Satz ist 'Ich **bin** gestern ins Kino gegangen.' Das Verb
  gehen bildet das Perfekt mit dem Hilfsverb 'sein'." — correct fix **and** correct rule.
- **Footprint is the concern, not quality.** On disk **3.9 GB > MLX 3.3 GB** — CQ4 is
  *larger*, because the vision+audio towers are bundled (see below). cactus reported only
  851.8 MB RAM (mmap), but that's a working-set number, not a jetsam peak — Phase E must
  measure true peak RSS before trusting any device-reach win.
- **Hybrid handoff is on by default.** Confidence 63.7% < threshold 81% would have handed
  off to cloud; it stayed local only because there was no API key. **Use `--no-cloud-handoff`
  for honest on-device eval.**

**Gate 0 (below) decides whether Phase 1 happens at all.** If CQ4 is a coherent tutor and
meaningfully smaller than 3.3 GB, integrate. If it's broken or barely smaller, stop — you
learned that for the cost of one local afternoon. **Status: quality ✅, but disk size ❌
(3.9 GB > 3.3 GB) as built. The deciding question is now whether a decoder-only build gets
under the MLX size — see the towers note.**

> **The unused modality towers ARE bundled — confirmed, and they're the whole size story.**
> The CQ4 build carries full `vision_encoder` + `audio_encoder` components (you can watch
> `audio_conformer_*` weights being written during convert), which is why 3.9 GB > the 3.3 GB
> MLX E2B. `--weights-only` only skips the graph, not the towers — but convert **does** expose
> `--components <a,b,...>` and `--component-pipeline auto|on|off`, which look like the real
> lever: build a **decoder/text-only** subset and drop the media encoders. Untested here;
> this is the highest-value Phase-0 follow-up, because it's what decides Gate 0.

---

## 4. Phase 1 — App integration seam (only if Gate 0 passes)

The doc's downstream phases measure artifacts on a bench, but *your* goal is a second
runtime inside the app. The good news: the app is already shaped for this. It **already
runs a second, non-MLX runtime** — `AppleIntelligenceService` sits behind the same method
surface as MLX, dispatched by inline `== .appleIntelligence` checks. A Cactus backend is
the same move, done once and properly.

### What exists today

- No `GenerationService` protocol. Feature code injects the concrete
  `MLXGenerationService` (`@Observable @MainActor`) in ~40 places and calls **6 domain-typed
  methods** — feature code never imports MLX types. Coupling is **wide but shallow**, the
  favorable case. Methods:
  [MLXGenerationService.swift](../german-ai-flashcards/Services/MLXGenerationService.swift):
  `generateCards`, `generateText`, `generateStreamedText`, `generateGrammarExercises`,
  `streamChatReply`, `generateArticleNouns` — each already contains an
  `if model == .appleIntelligence { … } else { …MLX container… }` branch.
- Model identity is one enum, `MLXModel`
  ([Models/ModelConfiguration.swift](../german-ai-flashcards/Models/ModelConfiguration.swift)),
  which already holds a non-MLX case (`.appleIntelligence`). Descriptors are exhaustive
  `switch self` blocks in
  [Models/MLXModel+Descriptors.swift](../german-ai-flashcards/Models/MLXModel+Descriptors.swift).
- A **dormant seam already exists**: `enum ModelProvider { case mlx }` — persisted as
  `activeProvider`, never branched on. The runtime switch was anticipated and never built.
- Memory gating is **already runtime-agnostic**: `DeviceCapability`, `MemoryBudget`,
  `MemoryPressureMonitor`, and the new `MemoryPressureBanner` all key off descriptor fields
  (`minimumRAMGB`, `measuredPeakMB`, `approximateSizeMB`), not MLX types. This is exactly
  the machinery that delivers "broader device reach" — a Cactus model slots in by carrying
  those fields.
- Load path is single-slot MLX: `loadModel` → `LLMModelFactory.loadContainer` into one
  `modelContainer`, weights pulled from HF at runtime by `ResumableModelDownloader`
  (patterns `*.safetensors`/`*.json`/`*.jinja`).

### The refactor (highest-leverage, do it once)

1. Add `MLXModel.runtime: ModelRuntime` (`.mlx` / `.appleIntelligence` / `.cactus`) — one
   computed switch that *replaces* the scattered `== .appleIntelligence` checks. Retire or
   fold in the dead `ModelProvider` enum.
2. Extract a `TextGenerationBackend` protocol with the 6 methods. Keep
   `MLXGenerationService` as the injected **coordinator/facade** (all ~40 call sites,
   pickers, persistence, and memory gating stay untouched); have it dispatch on
   `model.runtime` to `MLXBackend` (current container code moved wholesale),
   `AppleIntelligenceService` (already conforms in spirit), or a new `CactusBackend`.
3. `CactusBackend` needs: its own load slot (a Cactus handle alongside `modelContainer`),
   a download branch (extend `ResumableModelDownloader` patterns to the Cactus bundle
   format, or add a Cactus fetch), and a **`MemorySaver` equivalent** — the current
   governor mutates MLX's `GenerateParameters`, so it's MLX-only.
4. Add Cactus model cases to `MLXModel` (e.g. `.gemma4_E2B_german_cactus`) carrying the
   measured Phase-0 footprint fields. Because several descriptor switches have no
   `default:`, the compiler will enumerate exactly what each new case must fill in.

**Seam quality: ~6.5/10 toward clean.** The AppleIntelligence precedent de-risks the
protocol shape; the work is mostly mechanical. This converts "paste a third `if` into 6
methods" into "add one backend," and everything downstream (descriptors, memory tiers,
pickers) extends by *data* rather than new branches.

---

## 5. Phase A — Dataset diagnosis (quality track; no GPU)

Cheap local scripts. Three questions. **Not a prerequisite for Track 1** — start these only
once you've decided the quality retrain is worth doing.

### A1. What is the OK:FIX ratio in the training data?

Top suspect for the echo failure. If the model almost never saw a turn whose correct answer
was bare `OK`, it learned that `FIX:` is the prior and emits it even with nothing to fix —
exactly the observed behavior (18 of 19 false corrections were the input verbatim).

```python
# scripts/diagnose_ok_ratio.py
from datasets import load_dataset
ds = load_dataset("kessenma/gemma4-german-tutor-data", split="train")
ok  = sum(1 for x in ds if x["output"].strip() == "OK")
fix = sum(1 for x in ds if x["output"].lstrip().startswith("FIX:"))
print(f"OK={ok} FIX={fix} other={len(ds)-ok-fix}  ratio={ok/max(fix,1):.2f}")
```

**Decision rule:** if OK examples are under ~35% of correction-task items, that's your fix.
Rebalance toward the deployment distribution — a real B1 learner's sentences are correct a
meaningful fraction of the time.

### A2. What's the per-area item count?

Separable verbs regressed (11/15 → 8/15) while reflexives improved (8/15 → 12/15). Check
whether that tracks item counts across the four target areas. Also check: does the
separable-verb slice contain examples where a separable verb is used *correctly* and the
answer is `OK`? If every separable-verb example is a correction, the model has no signal
for "this one is fine."

### A3. Is the eval overlap guard actually holding?

Train loss 0.57 → low 0.2s with **held-out eval loss flat at ~0.75** is a memorization
signature. Verify empirically by checking near-duplicate similarity (not just exact match)
between train and eval sets. Flat eval loss with falling train loss means extra epochs buy
nothing.

---

## 6. Phase B — Retraining sweep (RunPod; quality track)

Training entry point already in-repo: [training/runpod/train_gemma4_e4b.py](runpod/train_gemma4_e4b.py)
(`MODEL_NAME=unsloth/gemma-4-E4B-it`, `CHAT_TEMPLATE=gemma-4`).

### Hardware

| Model | Method | VRAM needed | Suggested pod        | ~$/hr  |
| ----- | ------ | ----------- | -------------------- | ------ |
| E2B   | QLoRA  | ~10 GB      | RTX 4090 (24 GB)     | ~$0.34 |
| E4B   | QLoRA  | ~14–16 GB   | RTX 4090 (24 GB)     | ~$0.34 |
| E4B   | LoRA (bf16 base) | ~28 GB | L40S / A6000 (48 GB) | ~$0.80 |

Prior E2B run: ~26 min on an RTX 4000 Ada. On a 4090 assume ~15–20 min per run.
**A 6-config sweep is roughly 2 GPU-hours ≈ $0.70.**

### Sweep grid

Change one thing at a time against the current config (r=8, α=16, lr=2e-4, 2 epochs):

| Run | Change                                              | Hypothesis being tested |
| --- | --------------------------------------------------- | ----------------------- |
| R0  | Reproduce current config exactly                    | Baseline / seed variance |
| R1  | Rebalanced OK:FIX ratio (from A1)                   | Kills the echo failure at the source |
| R2  | R1 + separable-verb slice augmented with `OK` cases | Recovers the 11/15 → 8/15 regression |
| R3  | R1 + rank 16, α 32                                  | Is 4 target areas too much for rank 8? |
| R4  | R1 + 1 epoch instead of 2                           | Flat eval loss says epoch 2 may be pure memorization |
| R5  | R1 + general-instruction mix raised 35% → 50%       | More anti-forgetting headroom for the extension suite |

Run R0 twice with different seeds. **On n=60, one item is 1.7 points — treat anything under
~5 points as noise unless you've measured otherwise.**

### Persistence

RunPod pods are ephemeral. Before terminating: push the adapter to HF (the artifact that
matters), push the merged BF16 model, save the training log + loss curves, save the exact
`requirements.txt` / image tag. Mount a network volume at `/workspace` so an interrupted
run doesn't cost you the checkpoint.

---

## 7. Phase C — Quantization matrix

Build every artifact **from base + adapter**, never from another quantization.

```bash
# Cactus — merges the adapter at convert time. --bits is INTEGER only (1|2|3|4).
cactus convert unsloth/gemma-4-E2B-it ./e2b-r2-cq4 --lora ./adapters/r2 --bits 4
cactus convert unsloth/gemma-4-E2B-it ./e2b-r2-cq3 --lora ./adapters/r2 --bits 3
cactus convert unsloth/gemma-4-E2B-it ./e2b-r2-cq2 --lora ./adapters/r2 --bits 2

# MLX (note: mlx_lm.convert cannot handle Gemma 4 — use mlx_vlm), from the merged BF16 repo
mlx_vlm convert --hf-path <merged-bf16-repo> --quantize --q-bits 4
```

Artifacts to build per winning training run:

| ID          | Runtime | Recipe                              | Expected disk |
| ----------- | ------- | ----------------------------------- | ------------- |
| `-mlx4`     | MLX     | mlx_vlm 4-bit                       | ~3.3 GB (E2B), ~5.0 GB (E4B) |
| `-cq4`      | Cactus  | uniform CQ4                         | measure (prior: ~2.8–3.0 GB) |
| `-cq3`      | Cactus  | uniform CQ3                         | measure |
| `-cq2`      | Cactus  | uniform CQ2                         | measure |
| `-gguf-q4`  | llama.cpp | Q4_K_M                            | ~2.9 GB |

**Mixed-precision (CQ3.26 / CQ2.54) and 2-bit embedding quant (TurboQuant-H):** these are
real Cactus schemes but there's no documented `--bits 3.26` selector, and "PLE 2-bit" is
not Cactus terminology (the real thing is TurboQuant-H 2-bit *embedding* quantization). If
you want them in the matrix, first confirm how the converter actually selects them — don't
script a flag that doesn't exist.

---

## 8. Phase D — Quality eval (per artifact, not per run)

The mistake to avoid: eval the BF16 checkpoint, pick a winner, quantize it, ship.
Quantization changes behavior, and degenerate echoing is exactly the kind that shifts under
aggressive quantization. Aggressive quant silently wrecking Gemma is a documented, real
phenomenon — e.g. the `llm-compressor` Gemma-3n W4A16 regression (#1765) that collapsed
`o_proj` and tanked benchmark accuracy. **Verify the exact bundle you actually ship**, not
a sibling build.

Harness already in-repo: [training/scripts/run_baseline_eval.py](scripts/run_baseline_eval.py),
[training/scripts/behavior_metrics.py](scripts/behavior_metrics.py).

### Suites

| Suite      | n  | What it catches |
| ---------- | -- | --------------- |
| Core       | 60 | The four target areas |
| Extension  | 61 | Catastrophic forgetting on untargeted grammar |
| Correct-set| 32 | False corrections / echo behavior |
| Error-set  | 69 | Missed and mis-fixed errors |

### Results table (fill one row per artifact)

| Artifact | Core | Ext | False (raw) | False (filt) | Missed | Sep. verbs | Reflex. | Notes |
| -------- | ---- | --- | ----------- | ------------ | ------ | ---------- | ------- | ----- |
| `bf16` (reference) | | | | | | | | ceiling |
| `mlx4`   | | | | | | | | current shipping build |
| `cq4`    | | | | | | | | |
| `cq3`    | | | | | | | | |
| `cq2`    | | | | | | | | |

### Additions to the harness

- **Log raw and filtered false-correction rates separately.** The gap is your echo-emission
  rate and the cleanest single signal of quantization damage.
- **Add a diacritic regression check.** The filter must stay diacritic-sensitive
  (`Madchen` → `Mädchen` is a real correction). Add explicit test cases.
- **Score the `WHY:` line separately.** It confabulates rules (calling *aufstehen*
  inseparable). Don't let a bad `WHY:` count against a good `FIX:`.
- **Keep the `zumachen` → `zuschlagen` case as a named regression test.** Meaning-changing
  rewrites are the worst failure class for a tutor.

---

## 9. Phase E — On-device measurement

Speed is not the gate. **Peak RSS against the jetsam budget is the gate.**

### What to measure — per artifact × device

1. **Peak RSS** during a normal turn, and at worst-case context length
2. **`os_proc_available_memory()`** at load time — the actual headroom, not a table number
3. **Cold-load time** (first launch, post-install)
4. **Decode tok/s**, burst
5. **Sustained decode over 10 minutes** — GPU-backed runtimes throttle on iPhone (one
   published measurement: MLX retained 38% of burst vs the ANE's 67%). A tutor is bursty,
   so this may not bind — measure before assuming.

### Devices

Test on your **floor device**, not your dev phone. Rough jetsam budgets: ~4 GB on an 8 GB
iPhone, considerably less on 6 GB. Add the **Increased Memory Limit** entitlement early — but
don't treat it as headroom (a ~6 GB per-process ceiling is reported even with it, and App
Store builds behave differently from dev builds).

The app already gates on this: `DeviceCapability.canRun`, `MLXModel.recommended(ramGB:)`,
`MemoryBudget.isOverBudget`, and the interrupted-load "probably OOM" detection. Cactus
models plug into all of it by carrying the Phase-0 footprint fields.

### Optional external bench

`john-rocky/apple-silicon-llm-bench` (CLI: `yardstick`) has adapters for MLX Swift,
llama.cpp, Core ML, LiteRT-LM, ExecuTorch behind an `LLMRuntime` protocol and measures peak
memory, TTFT, ITL percentiles, energy. Useful for an apples-to-apples MLX-vs-Cactus row,
separate from wiring Cactus into the app itself.

---

## 10. Decision gates

**Gate 0 — integrate Cactus at all? (Phase 0)**
The converted CQ4 build of the *current* adapter loads locally, produces coherent German
tutoring, and is meaningfully smaller than the 3.3 GB MLX E2B. If it's broken or barely
smaller, stop — Track 1 is dead for now and you've spent one local afternoon.

**Gate 1 — proceed to a quality retrain? (after Phase A)**
Only if you're pursuing Track 2. A run beats baseline on core suite AND does not regress
extension suite AND separable verbs ≥ 11/15. If nothing clears this, the answer is more
data work, not more hyperparameters.

**Gate 2 — which quantization ships?**
The most aggressive artifact within 3 points of the BF16 reference on the core suite, with
raw false-correction rate no worse than the MLX build. If CQ4 and CQ3 tie on quality, ship
CQ3 for the memory.

**Gate 3 — E4B or E2B on Cactus?**
E4B ships only if it clears E2B by enough to justify roughly double the footprint. On a
6 GB floor device, E4B is likely out regardless. **Decide the floor device before investing
more in E4B** — it determines whether that branch is even live. (Today E4B is gated to the
8 GB tier and E2B to 6 GB in the app.)

---

## 11. Budget

| Item                              | Estimate |
| --------------------------------- | -------- |
| Phase 0 (local Cactus spike)      | $0, one afternoon |
| Phase 1 (app integration seam)    | dev time, no compute |
| Phase A (local, no GPU)           | $0, half a day |
| Phase B sweep, E2B × 6 runs       | ~$0.70, ~2 h wall clock |
| Phase B sweep, E4B × 3 runs       | ~$0.60 |
| Re-runs / debugging headroom      | ~$5 |
| **Total compute**                 | **< $10** |

Compute is not the constraint. The **Phase-0 spike, the app-integration seam, and
on-device measurement** are where the real time goes — plan accordingly.

---

## 12. Open questions

- [ ] **Gate 0:** does `cactus convert` handle a Gemma-4, LoRA-merged checkpoint (per-layer
      embeddings + AltUp) at all, and what's the real CQ4 disk/RAM? *(Phase 0 answers both.)*
- [ ] Is the adapter published separately yet? (rule #2 — do this first, it's free)
- [ ] What's the floor device? 6 GB vs 8 GB changes which runtimes/models are live.
- [ ] Does the echo failure survive requantization, or is it quantization-sensitive? If CQ
      makes it worse, that's a strong argument for fixing it in the data (Track 2).
- [ ] How does Cactus actually select CQ3.26 / CQ2.54, if you want them? (`--bits` is
      integer-only.)
- [ ] Commercial-license decision on Cactus's source-available terms before shipping.
- [ ] What's the OK:FIX ratio in the training data? (blocks the Track 2 retrain, not Track 1)

---

## Appendix — repo layout

### Training / conversion side (this folder)

```
training/
├── runpod/train_gemma4_e4b.py    # base=unsloth/gemma-4-E4B-it, template=gemma-4
├── scripts/
│   ├── run_baseline_eval.py      # eval harness (mlx-community/gemma-4-e4b-it-4bit)
│   ├── behavior_metrics.py       # false-correction / echo metrics
│   └── diagnose_ok_ratio.py      # Phase A1 (to add)
├── convert/                      # cactus.sh / mlx.sh / gguf.sh (to add)
├── eval/                         # suites, echo_filter.py (single source of truth), results/
└── german-tutor-cactus-retrain-plan.md   # this file
```

Keep `echo_filter.py` as the one implementation, imported by both the eval harness and the
Swift app's test fixtures. Two drifting copies is a bug you will ship.

### App side (../german-ai-flashcards)

Where a Cactus runtime lands (Phase 1):

```
german-ai-flashcards/
├── Services/
│   ├── MLXGenerationService.swift    # facade + 6 gen methods; add runtime dispatch here
│   ├── AppleIntelligenceService.swift# the existing 2nd-runtime precedent
│   ├── MLXModelManager.swift         # activeProvider (dormant ModelProvider enum)
│   ├── MemorySaver.swift             # MLX-specific governor; Cactus needs an equivalent
│   ├── ResumableModelDownloader.swift# *.safetensors patterns; extend for Cactus bundles
│   └── HubCacheLocation.swift        # repo-id-keyed cache (mostly reusable)
├── Models/
│   ├── ModelConfiguration.swift      # enum MLXModel (+ .appleIntelligence); add .runtime
│   ├── MLXModel+Descriptors.swift    # footprint/tier fields; add Cactus cases
│   ├── DeviceCapability.swift        # runtime-agnostic tier gate
│   └── MemoryBudget.swift            # runtime-agnostic live jetsam budget
└── Features/Shared/MemoryPressureBanner.swift  # runtime-agnostic
```
