# BübleLM-2B evaluated on the app's grammar task — a negative result

Someone flagged [`QuantFactory/bueble-lm-2b-GGUF`](https://huggingface.co/QuantFactory/bueble-lm-2b-GGUF)
as a possible model for the app. This is the measurement. Short version: **skip it.** It is
unusable as-is and sits far below the fine-tune floor. Full workings below, because the *way* it
fails is the same lesson the scoreboard keeps teaching, and worth having on record.

Companion to [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md), [`ARTICLE.md`](ARTICLE.md),
[`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md).

## What it is

**BübleLM** (Flair — Delobelle & Akbik) is **Gemma 2-2B re-adapted for German**: a custom 20k German
SentencePiece tokenizer trans-grafted onto Gemma 2, then continued-pretrained on 3.5B German tokens.
It has genuinely stronger German *substrate* than stock Gemma 2-2B on German benchmarks (+71%
HellaSwag-DE → 47.9%, +41% ARC-DE → 32.3%). The GGUF link is a llama.cpp requant; the app is MLX, so
that file can't load here anyway.

The base model is **not instruction-tuned** — the authors say so and recommend fine-tuning first — so
the fair candidate to test is the community SFT variant
[`johannhartmann/bueble-lm-2b-sft`](https://huggingface.co/johannhartmann/bueble-lm-2b-sft)
(LoRA SFT on German translations of alpaca-gpt4, dolphin, evol-instruct, hermes, etc.; Apache 2.0,
ChatML template with a system role).

## Getting it to run at all (two conversion snags)

1. **Untied output head.** Trans-tokenisation trains a fresh `lm_head.weight` separate from
   `embed_tokens`, which mlx_lm's Gemma 2 (tied-embedding) rejects: `Received 1 parameters not in
   model: lm_head.weight`. The two matrices turned out **near-identical** (max abs diff 0.006, mean
   0.0008 on norm-1.2 rows — the SFT barely moved the head), so dropping `lm_head` and using tied
   embeddings is a faithful approximation. Rebuilt a clean local checkpoint without that key, then
   `mlx_lm convert -q --q-bits 4` → 1.1 GB, 4.5 bpw.
2. **Broken stop token.** `generation_config` declares `eos_token_id: 2`, but the ChatML EOS is
   `<|im_end|>` = 24, and the model actually emits `<eos>` = id **0**, which *collides with `<unk>`*
   in the custom vocab. Result: it answers correctly, then spams `<unk>` to max-tokens forever.
   Fixed for the eval by stopping on `{0, 2, 24}`.

Neither is a defect that scoring should be blamed on — both were repaired before measuring.

## Results — scored two ways

Same held-out suites and scorer as every other model, with `--app-guard` (echo filter) applied.
**Strict** = the app's real format (`FIX:`/`OK`) — *can it be dropped in?* **Lenient** = extract
whatever German sentence it proposed, however phrased, and apply the same token checks — *is its
German good enough to be worth fine-tuning?* (the question EuroLLM failed).

| | core | extension | false-corr | miss |
|---|---|---|---|---|
| **strict** (app FIX/WHY format) | **4/60 (7%)** | 3/61 (5%) | **32/32 (100%)** | 69/69 (100%) |
| **lenient** (German substrate) | 15/60 (25%) | 15/61 (25%) | 26/32 (81%) | 52/69 (75%) |

For context, core accuracy of the models it would have to beat:

| model | core | note |
|---|---|---|
| Gemma 4 E4B tuned (hero) | 85% raw / 90% guarded | shipped |
| **Gemma 4 E2B tuned** | 68% / **83% guarded** | shipped, 6–8 GB tier |
| Gemma 4 E2B stock | 65% / 73% guarded | |
| Gemma 3 1B stock | 58% | **entry tier — what BübleLM would have to beat** |
| EuroLLM-1.7B | 13% | prior "German but no format" cautionary tale |
| **BübleLM-2B-SFT** | **7% strict / 25% lenient** | this experiment |

## Why it fails

It never renders a verdict. Across 121 items:

- **0 bare `OK`** — it structurally cannot accept a correct sentence, which *is* the 100% strict
  false-correction rate.
- **7%** emitted a `FIX:` prefix; **77%** opened with `: "<sentence>"` — the sentence, reframed, with
  no verdict marker the app can parse.
- **31%** appended freeform German commentary, often a confabulated *"…aber es gibt einige kleine
  Stilfehler"* on flawless input, and a few leaked the system prompt back into the answer
  (*"he student's sentence is correct and natural German…"*).

The German *content* is frequently right — it fixes *warten für→auf*, *freue→freue mich auf*,
*anruft→ruft…an* correctly. The knowledge is real. What's absent is the instruction-following
discipline to deliver a parseable verdict in a fixed format. This is the **EuroLLM pattern, confirmed
a second time**: strong-ish target-language pretraining without task-shaped instruction tuning is
worthless for a structured tutor task. BübleLM has more German than EuroLLM (lenient 25% vs its 13%)
and even *worse* format discipline (strict 7% vs 13%).

## Verdict

**Not usable as-is** (7%), and **below the fine-tune floor** the scoreboard set the hard way:
*"base core ≥ ~55% is necessary but not sufficient."* At 25% lenient — a generous upper bound on its
substrate — BübleLM is less than half of that floor. By the 1B-cliff lesson, fine-tuning a base this
far below the line adds confidence, not skill. It would not beat stock Gemma 3 1B (58%) at the entry
tier, let alone the shipped tuned E2B (83%). There is no tier in the app where it wins.

The meta-point is the familiar one: a model that posts 47.9% on a German benchmark (HellaSwag-DE)
turns in 7–25% on the actual app task. Model cards measure German knowledge; this eval measures the
job. They disagree, and the eval is the one that decides shipping — which is exactly why running it
cost ~30 minutes of Mac time and settled the question.

## Caveats (honest)

- **Lenient is an upper bound.** The extractor is generous and imperfect — appended commentary
  inflates its own false-correction count, and pulling "the proposed sentence" out of freeform prose
  is fuzzy. The true substrate score is at best 25%, plausibly lower.
- **The `lm_head` untie was approximated** with tied embeddings. The 0.006 max deviation makes this
  negligible and it cannot explain a 25% ceiling.
- **Zero-shot in the app's exact format.** A few-shot prompt or a German-language system prompt might
  lift format adherence — but the app pipeline is fixed zero-shot, and 25% lenient is a hard stop
  regardless, so this wouldn't change the verdict.
- **This was the best-case variant.** The SFT model follows instructions better than the base; the
  base would score lower on format, not higher.

## Reproduce

```bash
cd training
# convert (handles the untied-head snag + 4-bit quant): see scripts/eval_bueble.py header
.venv/bin/python scripts/eval_bueble.py models/bueble-lm-2b-sft-4bit
# raw responses saved to results/bueble_{core,ext}.responses.json — re-score strict via:
.venv/bin/python scripts/run_baseline_eval.py --responses results/bueble_core.responses.json \
    --model bueble-lm-2b-sft --tag baseline --app-guard
```
