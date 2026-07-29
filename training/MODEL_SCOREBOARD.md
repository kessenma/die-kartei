# Model Scoreboard — German grammar eval results

Single source of truth for every model measured against the two held-out eval suites.
Full per-item results live in `results/*.json`. Fine-tunes use the shared 1,447-example
dataset (`data/packed/`), QLoRA r=8, lr 2e-4, 2 epochs unless noted.

> ⚠️ **2026-07-22 — the false-correction column below measures the raw checkpoint, not the app.**
> Most "false corrections" across every model are the model echoing the student's sentence back
> under a `FIX:` header, and `ConversationPrompts.parseCorrection` has always discarded those, so
> the user never sees them. Re-scored the way the app behaves, **tuned E2B goes 68% → 83% core and
> 59% → 3% false corrections, and becomes shippable** for the 6–8 GB tier. See
> **[`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md)** for the decomposition, the app-side fix,
> and the revised tier plan. Reproduce app-equivalent numbers with the new `--app-guard` flag on
> `run_baseline_eval.py` / `behavior_metrics.py`.
>
> **The guarded (app-equivalent) numbers for the two shipped models — quote these, not the raw
> table below:**
>
> | model | core raw → guarded | ext raw → guarded | FC raw → guarded | miss |
> |---|---|---|---|---|
> | E4B stock | 72% → 80% | 87% → 93% | 34% → 6% | 16% |
> | **E4B tuned (shipped)** | 85% → **90%** | 90% → 93% | 22% → **6%** | 9% |
> | **E2B tuned (shipped)** | 68% → **83%** | 70% → **85%** | 59% → **3%** | 19% |
>
> The guard is `ConversationPrompts.parseCorrection` (`ConversationPrompts.swift:144`): a `FIX:`
> line identical to the student's own sentence is discarded rather than shown. It is
> diacritic-sensitive, so `Madchen → Mädchen` still counts as a real correction. Tier table
> revised 2026-07-28; the per-model rows below remain raw.

## Eval suites

- **Core** (`data/eval/grammar_eval_v0.json`, 60 items): the app's four target areas —
  verbs+prepositions (vmp), separable verbs (sep), reflexives (refl), da-/wo-compounds (dawo).
  Correction task in the app's exact FIX/WHY format + cloze.
- **Extension** (`data/eval/grammar_eval_v1_extra.json`, 61 items): word order, haben/sein,
  N-Deklination, relative pronouns, adjective endings, Wechselpräpositionen, Konjunktiv II,
  noun gender, imperatives, negation.
- **Behavior** (combined suites): *false-correction rate* = correct sentences wrongly "fixed"
  (n=32); *miss rate* = real errors missed or wrongly fixed (n=69). For a tutor, false
  corrections are the trust-killer.
- **v2 holdout** (`data/eval/grammar_eval_v2_holdout.json`, 82 items, added 2026-07-28): all 12
  phenomena from v0+v1, new lexical material, verified 0 overlap with training data *and* with
  v0/v1. **Frozen — score once per candidate, never iterate against it.** It exists because v0/v1
  have been scored by 20+ models and used for ship decisions, which makes them dev sets.

> **v0/v1 vs v2 — the shipped models, all guarded (2026-07-28).** The gap between the two tunes
> is much smaller on material neither was selected against:
>
> | model | v0 | v1-ext | blended v0+v1 | **v2 holdout** | drift | FC (v2) | miss (v2) |
> |---|---|---|---|---|---|---|---|
> | E4B tuned | 90% | 93% | 91.5% | **85%** | **−6.5** | 8% | 12% |
> | E2B tuned | 83% | 85% | 84.0% | **84%** | **0** | 12% | 10% |
>
> E4B's lead falls from +7.5 pts to +1 pt. E2B reproduces its number exactly on fresh material.
> Caveat: v2 is a differently-shaped suite (blends both phenomenon sets, harder lexis), so it isn't
> a drop-in v0 replacement — but suite difficulty would move *both* models, and it didn't. Working
> in [`training-v2.md`](training-v2.md) §0.7.

## Results

| Model | Size (4-bit) | Core base | Core tuned | Ext base | Ext tuned | False-corr (base→tuned) | Miss (base→tuned) | License | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| **Gemma 4 E4B** | 4.9 GB | 43/60 (72%) | **51/60 (85%)** | 53/61 (87%) | **55/61 (90%)** | 34% → **22%** | 17% → **9%** | Apache 2.0 | ✅ **SHIPPED** — app case "Gemma 4 E4B German Tutor", repo `kessenma/gemma4-e4b-german-tutor-4bit` |
| Gemma 3 1B (QAT) | 0.8 GB | 35/60 (58%) | ❌ 19/60 (32%) | 36/61 (59%) | ❌ 22/61 (36%) | 0% → 56% | 55% → 72% | Gemma | **Ship STOCK as entry tier.** Fine-tune = capacity cliff (behavior without knowledge); tuned model kept for reference only |
| Qwen3-4B | 2.3 GB | 29/60 (48%) | 37/60 (62%) | 35/61 (57%) | 39/61 (64%) | 19% → — | 61% → — | Apache 2.0 | Tuned still below *stock* E4B — not shipped. `kessenma/qwen3-4b-german-tutor` |
| Mistral 7B v0.3 | 4.1 GB | 26/60 (43%) | — | 30/61 (49%) | — | — | — | Apache 2.0 | ❌ dropped: dawo 1/15, artikel 2/8, slowest in app |
| Llama 3.2 1B | 0.7 GB | 17/60 (28%) | — | 20/61 (33%) | — | 0% (trivial) | **100%** | Llama license | ❌ unsalvageable — answered OK to all 69 errors |
| Qwen3-8B | 4.9 GB | 35/60 (58%) | — | 47/61 (77%) | — | 6% | 48% | Apache 2.0 | ❌ skip fine-tune: same Qwen knowledge-deficit profile as 4B (misses half of real errors), core below *stock* E4B at identical size. Tuning (~+13 → ~71%) still loses to tuned E4B (85%) |
| Phi-4 Mini 3.8B | 2.3 GB | 26/60 (43%) | — | 29/61 (48%) | — | 12% | **77%** | MIT | ❌ below fine-tune floor; Mistral-tier German despite strong English benchmarks (dawo 4/15, ndekl 1/6). Consider demoting for German use in-app |
| Gemma 4 E2B | 3.3 GB disk / ~2B-class RAM | 39/60 (65%) | 41/60 (68%) | 46/61 (75%) | ❌ 43/61 (70%) | 34% → ❌ **59%** | 28% → 19% | Apache 2.0 | ❌ **DO NOT SHIP tuned — partial capacity cliff.** Core +2 and miss rate improved (28→19%, learned real error-catching), but false corrections nearly **doubled (34→59%)**: over-corrects correct sentences with confabulated rules ("*aufstehen* is inseparable" — it's separable; "fixes" `zumachen`→`zuschlagen`). Learned the FIX *behavior* without the capacity to aim it — same failure as 1B, one tier up. Per-phen core: vmp 12→13, refl 8→12, **sep 11→8**, dawo 8→8. **Ship STOCK E2B** for low/mid tier (FC 34% ≪ 59%). Tuned kept **private/local** for reference (`kessenma/gemma4-e2b-german-tutor` fp16 private; 4-bit at `models/gemma4-e2b-german-tutor-4bit`). Caveat: base=community quant, tuned=local mlx_vlm quant (25-pt FC jump ≫ any quant artifact) |
| Ministral 8B (2410) | 4.2 GB | 31/60 (52%) | — | 42/61 (69%) | — | **84%** (!) | 23% | ⚠️ Mistral Research License | ❌ research footnote: most extreme over-corrector measured — "fixes" 84% of correct sentences (anti-Qwen profile). Below floor anyway; license moot |
| Aya Expanse 8B | 4.2 GB | 34/60 (57%) | — | 39/61 (64%) | — | **100%** (!!) | 12% | ⚠️ CC-BY-NC | ❌ research footnote: corrected ALL 32 correct sentences — zero verdict discipline, the exact mirror of Llama 1B (which OK'd all 69 errors). Decent knowledge, no judgment |
| EuroLLM-1.7B Instruct | ~1 GB | 8/60 (**13%**) | — | 4/61 (**7%**) | — | 100% | 97% | Apache 2.0 | ❌ **DEAD LAST** — can't follow the correction format (26–29 format failures per suite; rambles in English prose). EU-24-languages pretraining without instruction-following is useless for a structured tutor task. Local convert at `models/eurollm-1.7b-4bit` |
| BübleLM-2B-SFT (Gemma 2-2B, German) | 1.1 GB | 4/60 (**7%**) / 25% lenient | — | 3/61 (5%) | — | **100%** (0 bare OK) | 100% | Apache 2.0 | ❌ **below the fine-tune floor.** German-specialised Gemma 2-2B (HellaSwag-DE 47.9%) but never renders a verdict — 77% open `: "<sentence>"`, 0% emit `OK`, 7% emit `FIX:`. Even forgiving format entirely: 25% core ≪ 55% floor. The EuroLLM pattern again — strong-ish German, no task discipline. Full workup: [`BUEBLE_LM_EVAL.md`](BUEBLE_LM_EVAL.md). Local convert at `models/bueble-lm-2b-sft-4bit` |
| **Granite 3.3 2B Instruct** (IBM) | 1.5 GB | 30/60 (50%) → **34/60 (57%) guarded** | — | 27/61 (44%) → 62% guarded | — | 66% → **19% guarded** | 43% | Apache 2.0 | ◽ **at the floor, best non-Gemma tested.** Clean license, good verdict discipline (guarded FC 19% < Gemma's 34%), catches more errors than Gemma-3-1B (miss 43% vs 55%) — but only *ties* stock Gemma-3-1B (58%) on core while being ~2× the size, and a fine-tune would land ~70% (< tuned E2B 83%). Only worth it as a fine-tune base if avoiding the 3-bit-E2B path. See [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md) |
| Llama 3.2 3B Instruct | 2.0 GB | 16/60 (27%) → 35% guarded | — | 33/61 (54%) → 70% guarded | — | 100% → 53% guarded | 43% | Llama 3.2 (700M MAU) | ❌ **below floor.** Strong generalist (ext 70% guarded, 0 format errors) but weak German *grammar* — over-corrects half the correct sentences even guarded. Substrate ceiling: German MMLU 53.3 ≪ Gemma. The 1B's bigger sibling still can't do the hard areas. [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md) |
| Salamandra 2B Instruct (BSC) | 1.2 GB | 4/60 (**7%**) | — | 8/61 (13%) | — | 100% | 100% | Apache 2.0 | ❌ **EuroLLM redux — dead last tier.** 99/121 format failures; rambles in English, translates instead of correcting, confabulates (*'the correct form is "er" instead of "er"'*). 35-EU-language pretraining tuned for Catalan/Spanish → no German task discipline. Local convert at `models/salamandra-2b-instruct-4bit` |
| SauerkrautLM-gemma-2-2b-it (VAGO) | 1.4 GB | 20/60 (33%) → **32/60 (53%) guarded** | — | 28/61 (46%) → 64% guarded | — | 97% → **25% guarded** | 46% | Gemma | ❌ **best-behaved existing German fine-tune, still below floor.** German Spectrum-tune of Gemma 2 2B — kept instruction-following (only 5/121 format errors, unlike BübleLM's collapse) but Gemma-2 substrate on the hard grammar lands *below* stock Gemma-3-1B (58%) and under the 55% floor. Confirms: an off-the-shelf German chat tune ≠ this task. [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md) |
| Gemma 4 12B | 6.7 GB | ▫️ research only | — | ▫️ | — | | | Apache 2.0 | ❌ **not app-viable**: iOS caps per-app memory (~8 GB even on Pro devices) and 12B-class models fail to load in practice (user-tested). Baseline only worth running for the article's capacity curve |
| EuroLLM-9B Instruct | ~5 GB | ▫️ deprioritized | — | ▫️ | — | | | Apache 2.0 | the 1.7B's format-following collapse makes this a long shot; no MLX build either — only worth converting if curiosity outweighs the download |
| Gemma 3n E4B | 3.9 GB | ▫️ untested (in app) | — | ▫️ | — | | | Gemma | measure if curious; superseded by Gemma 4 E4B |
| Qwen3 0.6B | 0.5 GB | ▫️ untested (in app) | — | ▫️ | — | | | Apache 2.0 | expected far below floor |
| Apple Intelligence (on-device) | ~3B built-in | 25/60 (42%) | — | 32/61 (52%) | — | **100%** (!!) | 35% | Apple (system API) | ❌ research footnote — **worst verdict discipline measured, ties Aya Expanse 8B**: "fixes" all 32 correct sentences, echoing the input verbatim with a confabulated rule (*"'würde ich' is incorrect"* on a flawless Konjunktiv-II sentence; *"Incorrect subject-verb agreement needed"* on `Sie wartet auf ihren Freund`). Never emits a bare `OK`. Knowledge is Mistral-tier (**dawo 0/15**, k2 1/6, aux 2/6, imperativ 1/4) — below even stock Gemma 3 1B (58%). 0 format errors (nails the FIX/WHY shape, lacks the judgment to aim it). Not shippable as a bundled model (system-only, no weights); measured via `FoundationModels` in Swift — see Reproduce. |

## Runtime comparison — Cactus CQ4 vs MLX 4-bit (same E2B tune, 2026-07-26)

Not a new model — the *same* fp16 E2B tune (`kessenma/gemma4-e2b-german-tutor`) quantized two ways
and run through two runtimes, to test the [Cactus runtime spike](german-tutor-cactus-retrain-plan.md).
Both built straight from fp16 (no MLX→Cactus requantization); byte-identical prompts
(`scripts/gen_cactus_responses.py` imports the MLX harness's `build_messages`); same scorer.

| Runtime / quant | Disk | Core (guarded) | Ext (guarded) | False-corr | Miss | On-device |
|---|---|---|---|---|---|---|
| **MLX 4-bit** (shipped) | 3.3 GB | **83%** | **85%** | 3% | **19%** | 2.71 GB peak |
| Cactus CQ4 | 3.9 GB | ❌ 65% | 72% | 0% | ❌ **43%** | 851 MB reported (mmap) / 75.9 tok/s Metal |

**Cactus CQ4 loses ~18 pts core and doubles the miss rate** — it reverts to bare `OK` on textbook
reflexive/preposition/separable errors the tune was built to catch, and lands at the rejected MLX
**3-bit** tier (63% / 30%) despite being nominally 4-bit. Same PLE sensitivity as the 3-bit dead-end:
Gemma 4's per-layer embeddings need the high-bit protection MLX's 4-bit gives and CQ4 apparently
doesn't (and Cactus exposes no PLE-sparing quant — `--bits` is integer-only). Bigger *and* weaker as
built; the disk size is from bundled vision/audio towers. Full workup + reproduce:
[`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md) §"Cactus CQ4 runtime". Responses at
`results/cactus_e2b_cq4_{core,ext}.responses.json`.

## Runtime comparison — LiteRT-LM vs MLX 4-bit (same E2B tune, 2026-07-27)

Google's own on-device runtime, same fp16 E2B tune, same scorer, same system/user turns
(`scripts/gen_litertlm_responses.py` imports the MLX harness's `build_messages`). Prompts are
templated **by the runtime** (its Conversation API templates internally). Generated via
`scripts/litertlm_runner.c` against the C API — the released `litert_lm_main` CLI binaries all
ship without their runfiles dylibs and won't load. Full workup:
[`RUNTIME_EXPLORATION.md`](RUNTIME_EXPLORATION.md).

| Runtime / quant | Disk | Core (guarded) | Ext (guarded) | False-corr | Miss | Peak RAM |
|---|---|---|---|---|---|---|
| **MLX 4-bit** (shipped) | 3.3 GB | **83%** | **85%** | 3% | **19%** | 2.71 GB |
| LiteRT-LM INT4 **dynamic** (`dynamic_wi4_afp32`) | 2.60 GB | ❌ **40%** | ❌ **41%** | 0% | ❌ **90%** | 1.97 GB |
| LiteRT-LM INT4 **weight-only** (`weight_only_wi4_afp32`) | 2.60 GB | ❌ gibberish | — | — | — | ❌ ~10 GB |
| *(reference)* official stock E2B, INT4 **QAT** | 2.59 GB | 57% | 66% | 0% | 61% | 2.51 GB |

**Converting works; the default INT4 recipe destroys the tune.** The bundle is valid — loads in ~3 s,
real tokens (not `<pad>`), 0 format errors on all 121 items — so upstream bugs #994/#1001 don't
reproduce on litert-torch 0.9.1. But 46/60 core answers are a bare `OK` and only **2** items emit a
`FIX` at all: a 90% miss rate is not caution, it's a model that stopped correcting. Our *tuned*
weights score below *stock*.

**INT4 damages the WEIGHTS, not just the activations** (2026-07-28, track closed). The two public
recipes fail in opposite directions, which is what kills the runtime: dynamic also quantizes
activations to INT4 → silent rubber-stamping; weight-only keeps float compute → **token salad**
(`"Ich habegeboten den dasselbeftenechemelecebfreiechenslech…"`) at **~10 GB peak RAM** and
~4 min/item. Neither is tunable toward the other.

⚠️ `--externalize_embedder` controls **layout, not precision** — it splits the PLE into its own file
and then quantizes it with the same recipe. It is *not* an analogue of MLX's `--quant-predicate`.
The Tier-1 plan's central assumption was wrong. Hadamard rotation, the apparent PLE-sparing lever,
is unusable: it requires weight tensors and so cannot combine with dynamic quantization.

⚠️ **The 1.97 GB / −27% RAM figure belongs only to the 40% build** and is not a standing win.
Protecting the PLE (1.10 GiB of a 2.43 GB bundle at INT4) lands ~3.5 GB — **worse than MLX's
2.71 GB**, which already does mixed-precision PLE protection at ~5.2 bpw. So LiteRT-LM does **not**
unlock a 4 GB tier. Tier-2 QAT was not attempted: its weights would exit through the same public
PTQ converter, and the good mixed int2/4/8 scheme is not exposed for custom models.

**Verdict: ship MLX.** Second independent runtime to confirm Gemma-4's PLE needs high-bit
protection that public INT4 quantizers don't provide. Full workup + reopen criteria:
[`RUNTIME_EXPLORATION.md`](RUNTIME_EXPLORATION.md). Responses at
`results/litertlm_e2b_tune_int4_{core,ext}.responses.json` and
`results/litertlm_official_e2b_stock_{core,ext}.responses.json`.

## App tiers by device RAM (working plan)

> **Read the RAM column as the model's minimum, not a range.** The authoritative floors live in
> `MLXModel+Descriptors.swift:150-152` (`minimumRAMGB`): Gemma 3 1B = **4**, E2B = **6**, E4B = **8**.
> A 6 GB device therefore runs the **83% E2B tune**, not the 58% entry model. Only 4 GB devices
> (iPhone XR / 11 / SE 2–3 / 12 mini class) fall back to Gemma 3 1B.

| Device RAM | Tier | Current pick | Challenger on the bench |
|---|---|---|---|
| 4 GB only | entry | Gemma 3 1B stock (58% core — fine-tune proven harmful) | — no smaller model beats it; 3-bit E2B **can't reach this tier** (PLE blocks quantization below ~5 bpw, and quality craters 83→63% — see [`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md)). Budget-base search (Granite/Llama/Salamandra/SauerkrautLM/BübleLM) found nothing above the floor: [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md). **Open: distill a 1B on 30k+ on-task examples** — the capacity-cliff run never tested that ([`DATA_V2_DISTILL_PLAN.md`](DATA_V2_DISTILL_PLAN.md)) |
| 6 GB+ | low/mid | ✅ **Gemma 4 E2B German Tutor** — 83% core / 3% FC scored as the app behaves; measured 2.71 GB peak, fits a 6 GB device's ~3.4 GB budget. ⚠️ Runs *governed* there — 2,710+250 MB exceeds `slimHeadroomFraction` 0.75, so `MemorySaver` caps the KV cache on exactly the devices that just barely fit it. Public at `kessenma/gemma4-e2b-german-tutor-4bit` (2026-07-22). *Supersedes the earlier "ship stock, the tune is harmful" call — see [`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md).* **On-device confirmation still open.** | stock E2B (73% core) as the fallback |
| 8 GB+ | high | ✅ **Gemma 4 E4B German Tutor** — 85% raw / **90% guarded** | — nothing measured comes close |
| ≥11 GB (iPhone 17 Pro class) | max | **E4B German Tutor is the ceiling** — iOS's per-app memory cap (~8 GB) rules out 12B-class models regardless of device RAM (user-tested) | EuroLLM-9B ~5 GB might *just* fit (round 2, needs convert) |

## Decision rules (learned the hard way)

- **The capacity cliff is a gradient, not an edge — and false-correction rate slides off it first.**
  Same dataset, three sizes: it *helps* at ~4B-eff (E4B FC 34→**22**, core 72→85), *teeters*
  at ~2B-eff (E2B FC 34→**59**, core only 65→68 despite better miss rate), and *collapses* at
  1B (core 58→32, FC 0→56). Below ~4B-effective params the model learns the FIX *behavior*
  without the knowledge to aim it and over-corrects — worse the smaller it is.
- **Base core ≥ ~55% is necessary but NOT sufficient.** E2B cleared it at 65% and still
  regressed on the trust-critical metric. For small models, gate on the *post-tune
  false-correction rate*, not core accuracy — and treat a sub-~55% base as a hard stop.
- **Expect ~+13 pts from the shared dataset** on capable bases (E4B +13, Qwen3-4B +14).
- **Base multilingual substrate sets the ceiling** — tuned Qwen3-4B (62%) < stock E4B (72%).
  Generic "supports 100+ languages" marketing ≠ measured grammar-correction quality.
- **Size ≠ German quality** — Mistral 7B lost to Gemma 3 1B on the core suite.
- Ship criteria: core ≥ 80%, false-corrections ≤ 25%, license permits commercial use,
  fits the tier's RAM budget.

## Licensing quick reference

| License | Baseline for research/article | Fine-tune for research | Ship in app |
|---|---|---|---|
| Apache 2.0 / MIT (Gemma 4*, Qwen, Phi, EuroLLM) | ✅ | ✅ | ✅ |
| Gemma Terms (Gemma 3 family) | ✅ | ✅ | ✅ (with Gemma terms compliance) |
| Llama Community License | ✅ | ✅ | ✅ small-scale (has MAU threshold clauses) |
| Mistral Research License (Ministral 8B) | ✅ | ✅ | ❌ needs commercial license |
| CC-BY-NC (Aya Expanse) | ✅ | ✅ | ❌ non-commercial only |

*Gemma 4 released under Apache 2.0 (changed from the old Gemma license).

## Reproduce

```bash
cd training
.venv/bin/python scripts/run_baseline_eval.py --model <mlx-repo-or-local-path> --tag baseline
.venv/bin/python scripts/run_baseline_eval.py --model <...> --tag baseline-extra \
    --eval-file data/eval/grammar_eval_v1_extra.json
```
Training runbook: `runpod/README.md` (env-driven for any model: MODEL_NAME / CHAT_TEMPLATE / OUT_PREFIX / HF_REPO).

### Apple Intelligence (FoundationModels, not MLX)

The built-in model isn't an MLX checkpoint — it's reached through Apple's `FoundationModels`
Swift API, so it runs through a tiny Swift harness that emits raw responses, which the *same*
Python scorer then grades (identical rubric, so it's directly comparable). Requires macOS 26+ /
Xcode 26 with Apple Intelligence enabled. Prompts in the Swift harness are kept verbatim-in-sync
with `run_baseline_eval.py`'s `CORRECTION_SYSTEM` / `CLOZE_SYSTEM`; greedy (`temperature: 0`).

```bash
cd training
swiftc scripts/eval_apple_intelligence.swift -o /tmp/eval_ai
/tmp/eval_ai --eval-file data/eval/grammar_eval_v0.json          --out results/apple_ai_core.responses.json
/tmp/eval_ai --eval-file data/eval/grammar_eval_v1_extra.json    --out results/apple_ai_ext.responses.json
# score with the shared rubric:
.venv/bin/python scripts/run_baseline_eval.py --responses results/apple_ai_core.responses.json \
    --model apple-intelligence --tag baseline        --eval-file data/eval/grammar_eval_v0.json
.venv/bin/python scripts/run_baseline_eval.py --responses results/apple_ai_ext.responses.json \
    --model apple-intelligence --tag baseline-extra  --eval-file data/eval/grammar_eval_v1_extra.json
# combined behavioral metrics (false-corr /32, miss /69):
.venv/bin/python scripts/behavior_metrics.py results/apple_ai_core.responses.json results/apple_ai_ext.responses.json
```

`scripts/behavior_metrics.py` also reproduces any MLX model's behavioral rates from its saved
results files (verified: stock E4B → 34% / 17%).

---

# Image generation models — on-device (story illustrations)

Second track, same discipline: the CoreML model that draws Short-Story illustrations and AI
flashcard pictures (`ImageGenModel.swift` / `StoryImageService.swift`). The app ships **SD 2.1
base palettized** today (`apple/coreml-stable-diffusion-2-1-base-palettized`, ~1.2 GB). This
section records what's viable on a phone, what isn't, and why — measured fit, not model-card
hype, exactly like the LLM board above.

## Why most "best image model" advice doesn't apply

The Reddit/`r/StableDiffusion` "best model" threads describe **desktop** workflows — FLUX,
Wan, Chroma on 16–24 GB-VRAM GPUs via ComfyUI. Four constraints kill almost all of it on
iPhone, three of them specific to *this app*:

1. **Memory after the LLM.** Illustration runs *after* the ~5 GB Gemma tutor is unloaded — the
   two don't coexist on a 6 GB device (`StoryStudyService.swift` evicts the LLM before loading
   diffusion). The image model's peak RAM must fit what's left.
2. **GPU, not ANE.** The iOS 26 continued-processing background task grants **GPU**, so the
   pipeline runs `.cpuAndGPU` (`ImageGenConstants.computeUnits`). ANE-only (`split_einsum`)
   builds don't benefit from that grant and can be suspended when backgrounded.
3. **Abortable per-step.** Stop button + background-expiration both need the diffusion progress
   callback to return `false` mid-run. Any runtime we adopt must expose that.
4. **Bundled/downloadable CoreML**, not "it runs in Draw Things." Draw Things ships big models
   on iPhone via its own Metal stack (s4nnc/ccv, not CoreML) with aggressive SSD weight-
   streaming — a different game than a model that has to fit and behave inside our pipeline.

## Survey

Figures are vendor/community reports at time of writing; **⏳ = not yet measured by us**.
Latency is per-image at the model's native resolution.

| Model | Params | Disk (quant) | Steps | Peak RAM | iPhone latency | License | Verdict |
|---|---|---|---|---|---|---|---|
| **SD 2.1 base palettized** (current) | 0.9 B | 1.2 GB | 20–25 | fits 6 GB post-unload | 8–11 s @512 (14-class) | OpenRAIL-M | ✅ **SHIPPED** |
| **BK-SDM-Tiny** (distilled SD1.4) | 0.5 B (0.33 B U-Net) | 1.43 GB | ~10 | ⏳ | ⏳ | OpenRAIL-M | 🔧 **convert ORIGINAL** — HF repo is split_einsum (ANE) zips; need GPU variant |
| BK-SDM-Small / Base | 0.66 / 0.76 B | 1.44 / 1.48 GB | ~10 | ⏳ | ⏳ | OpenRAIL-M | 🔧 same job as Tiny, larger — quality comparison |
| **SDXS-512-DreamShaper** | ~0.9 B | 0.89 GB (fp16) | **1** | ⏳ | ⏳ | OpenRAIL++ | 🔧 **convert** — 1-step; guidance=1, no neg-prompt; use `vae_large` (tiny `vae/` is TAESD) |
| SD-Turbo | 0.9 B | ~1.2 GB | **1** | ⏳ | ⏳ | Stability Community ⚠️ | maybe — commercial OK <$1M rev, needs "Powered by Stability AI" |
| SDXL base (Apple iOS build) | 2.6 B | 1.46 GB (4.04-bit) | 20 | high | **31 s @768 (15 Pro Max)** | OpenRAIL++ | ❌ too slow for N images/story |
| PixArt-Σ | 0.6 B DiT | — | 20 | high | ⏳ | OpenRAIL++ | ❌ the real load is a 4.76 B T5-XXL encoder |
| SD3.5 Medium | ~2 B | 2.88 GB (8-bit) | 28 | ~2.2 GiB | ⏳ | Stability Community ⚠️ | ❌ marginal; Draw-Things-only tooling |
| FLUX.1 schnell / dev | 12 B | 12.7 GB (5-bit, +T5) | 1–4 | ~6.5 GiB | 35 s best (17 Pro) → **44 min** default | schnell Apache-2.0 / dev non-comm | ❌ too big; 8 GB+ only; no CoreML build exists |
| Chroma | 8.9 B | ~9 GB | — | — | — | Apache-2.0 | ❌ FLUX derivative; desktop only, no CoreML |
| Qwen Image | 20 B | 17.6 GB (6-bit) | 2–20 | ~11 GiB | 45 s (17 Pro, 2-step) | Apache-2.0 | ❌ too big; Draw-Things-only |
| SD3.5 Large | 8 B | 8.5 GB (8-bit) | 28 | high | ~6 min (17 Pro Max) | Stability Community ⚠️ | ❌ too big/slow |
| Wan 2.1 / 2.2 (video) | 14 B | ~15 GB | — | ~20 GiB | Mac-only | Apache-2.0 | ❌ video; needs ≥23 GiB (Draw Things gate) |
| FLUX.2 dev | DiT + 24 B Mistral enc. | 33 GB (8-bit) | — | huge | Mac-only | FLUX-2 license | ❌ 24 B text encoder alone exceeds any iPhone |
| **FLUX.2 Klein 4B** | 4 B | ~2.9 GB (6-bit) | 4 | ~6.5 GB (unverified) | ⏳ | **Apache-2.0** | 🔭 **iOS 27 / Core AI only** — the frontier path |
| SANA | 0.6–1.6 B | ~1 GB | — | — | — | ⛔ NVIDIA-only + NC | ❌ license bars Apple Silicon even for research |
| Stable Cascade | 3.6 B | — | — | — | — | ⛔ non-commercial | ❌ license (not relicensed in Stability's 2025 pass) |
| Kolors | — | 28.98 GB | — | — | — | ⛔ license conflict (PRC) | ❌ too big + license |

Legend: ✅ shipped · 🔧 convert & test (this track) · 🔭 frontier (toolchain not here yet) ·
❌ ruled out · ⚠️ conditional license · ⛔ blocking license.

## Conversion log — our runs (2026-07-20)

Converted on-Mac via `training/imagegen/` (see PLAN.md, Image track). **Validate through the Swift
runtime on the Neural Engine** — this Mac's Metal GPU corrupts fp16 SD (renders black/blur); it's a
macOS-26 regression, not a model defect, and the iPhone GPU is expected fine (memory:
`coreml-sd-fp16-mac-gpu-black`). Images checked visually; all rendered via Apple's `StableDiffusionSample`.

| Model | Converted | Disk (fp16) | Steps | In-app runtime (Apple Swift pipeline) | Result |
|---|---|---|---|---|---|
| **BK-SDM-Tiny** | ✅ | **948 MB** | ~10 | standard scheduler, guidance 7.5 | ✅ **coherent watercolor** — smaller + faster than current SD 2.1; ships as-is |
| **SDXS-512** | ✅ | 933 MB | **1** | dpmpp, 1 step, guidance 0 | ⚠️ **beautiful 1-step in PyTorch** (higher quality than Tiny); **off-prompt** in Apple's pipeline — no scheduler matches SDXS's single fixed-timestep denoise |
| BK-SDM-Base | ✅ | 1.4 GB | ~10 | — | ❌ noise (broken convert); dropped — marginal value anyway |

**Toolchain reality (the hard-won part):**
- **coremltools 9 bakes NaN into the weights** — every generation goes black. Pin **coremltools 7.2**.
  (torch stays 2.8; a "period-correct" torch-2.2 / diffusers-0.27 venv unexpectedly produced garbage — don't.)
- Apple's converter **reimplements the U-Net** and hard-rejects non-standard configs. BK-SDM-Tiny
  (no mid-block) and SDXS (no mid-block + `only_cross_attention` + no fp16 variant) each needed a
  converter patch — all captured in `patch_converter.py`, each faithful to diffusers' own behavior.
- **coremltools' Python `predict` is unreliable on this Mac** — its parity check even logged
  `nan dB … parity check passed`. Only the **Swift runtime + ANE** gives truthful validation.
- **BK-SDM-Tiny is the deliverable**: 948 MB (vs current 1.2 GB), ~10 steps (vs 25), coherent in the
  exact runtime the app uses.
- **SDXS is a near-miss**: conversion is perfect, but Apple's `StableDiffusionPipeline` ships no
  scheduler matching SDXS's one-step sampling, so in-app it drifts off-prompt. Would need a custom
  Swift scheduler — future work, not a today ship.

## Tooling dead-ends (don't re-investigate)

- **`apple/ml-stable-diffusion` is frozen at 1.1.1 (May 2024)** — still what we ship on.
  Successor **`apple/coreai-models`** (WWDC26, BSD-3) has an official iOS export for FLUX.2
  Klein 4B (512px, 4 steps) but needs **iOS 27 / Xcode 27**. Migration target, not today.
- **Image Playground / `ImageCreator`** (iOS 18.4): headless, free, on-device — but
  **deprecated in iOS 27**, rebuilt on Private Cloud Compute (network + user quota). Defeats
  offline illustration. Skip.
- **`argmaxinc/DiffusionKit`**: declares iOS 16 but sources are placeholder stubs; **archived
  Mar 2026**.
- **`stable-diffusion.cpp`**: no iOS CI, Metal "highly inefficient" per its own docs; the one
  iOS attempt (issue #1029) failed. A cross-platform app that had it on Android chose CoreML
  for iOS.
- **MLX Swift StableDiffusion** (`mlx-swift-examples`): a real iOS target but memory-fragile
  (one diffusion step at a time in a conserve mode that "may exit if memory exceeded"); SD2.1 /
  SDXL-Turbo only. Fallback if the CoreML path stalls.
- **SnapFusion, Google MobileDiffusion, UFOGen**: no public weights (first two never released;
  UFOGen "officially unofficial," legal issues). Vapor.

## App tiers by device RAM (working plan — fill measured numbers after Phase I3)

| Device RAM | Tier | Current pick | Challenger on the bench |
|---|---|---|---|
| 4–6 GB | entry | SD 2.1 base (heavy) | **BK-SDM-Tiny** (smaller, ~10 steps) / **SDXS** (1-step) |
| 6–8 GB | low/mid | **SD 2.1 base** (shipped) | **SDXS** (biggest speed win) |
| 8–12 GB | high | SD 2.1 base / SDXS | SDXL ruled out (too slow) |
| iOS 27+ (any tier) | frontier | — | FLUX.2 Klein 4B via Core AI |

## Decision rules

- **Ignore leaderboards; measure what fits.** Same lesson as the LLM board — a 12 B model that
  "wins" on desktop is unshippable at 12.7 GB / 6.5 GiB peak on a phone.
- **Steps are the phone's real currency.** A 1-step model (SDXS) or ~10-step distill (BK-SDM)
  beats a 25-step base far more than raw quality deltas suggest, because latency is N×steps.
- **The 6 GB-after-LLM-unload budget is the hard gate**, and GPU (not ANE) is mandatory for the
  background-generation path — both eliminate models before quality is even considered.
- **License first for anything re-hosted**: SANA (NVIDIA-only), Stable Cascade / Kolors (NC) are
  out regardless of size; Turbo models are OK but carry Stability Community conditions.
- Ship criteria: fits the tier's post-unload RAM, runs on GPU, abortable per-step, seconds-not-
  minutes per image, license permits commercial redistribution.

## Licensing quick reference (image models)

| License | Re-host & ship in app |
|---|---|
| OpenRAIL-M / OpenRAIL++ (SD 2.1, BK-SDM, SDXS, SDXL, PixArt-Σ) | ✅ must redistribute LICENSE + use-restrictions |
| Apache-2.0 (FLUX.1 schnell, Chroma, Qwen Image, FLUX.2 Klein) | ✅ (size/tooling permitting) |
| Stability Community (SD-Turbo/XL-Turbo, SD3.x) | ⚠️ commercial <$1M rev, registration + attribution |
| FLUX.1 dev / FLUX.2 dev | ❌ non-commercial / restricted |
| NVIDIA SANA, CC-BY-NC (Stable Cascade), Kolors | ⛔ not shippable |

## Reproduce (conversion + host)

Convert on a **Mac** (CoreML compile + validation are macOS-only; conversion is CPU/RAM-bound,
so a rented GPU is idle spend). Toolchain lives in `training/imagegen/` (py3.9 venv +
`apple/ml-stable-diffusion` pinned to the app's Swift-package revision).

```bash
# BK-SDM-Tiny → GPU (ORIGINAL) + 6-bit palettized, Swift-CLI resource layout
python -m python_coreml_stable_diffusion.torch2coreml \
  --model-version nota-ai/bk-sdm-tiny-2m \
  --convert-unet --convert-text-encoder --convert-vae-decoder \
  --attention-implementation ORIGINAL --quantize-nbits 6 \
  --bundle-resources-for-swift-cli -o out-bksdm-tiny
```
- **SDXS**: `--model-version IDKiro/sdxs-512-dreamshaper`; point the VAE at `vae_large` (the
  9.8 MB `vae/` is a TAESD tiny-autoencoder the converter won't take). App config: `stepCount=1`,
  `guidanceScale=1.0`, no negative prompt.
- Host the resulting `Resources/` as `<subfolder>/compiled/*` under `kessenma/coreml-<model>`
  (public) so `ResumableModelDownloader` + `HubCacheLocation` fetch it unchanged — the only app
  change is a new `ImageGenModel` case.
