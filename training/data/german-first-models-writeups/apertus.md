# Apertus (EPFL / ETH Zürich / CSCS) — three sizes, one format trap, one real candidate

Measured 2026-08-17. Switzerland's fully-open multilingual family: open weights **and** open training
data, Apache 2.0. 15T tokens, ~40% non-English, explicit German and Swiss-German coverage. The first
German-first family here whose licence is not a blocker.

Three sizes tested locally on MLX, all 4-bit, all `--app-guard`, all on the 60-item core v0 suite.

## Results

| model | 4-bit size | zero-shot | format errors | **3-shot** | false-corr (/16) | miss (/32) |
|---|---:|---|---:|---|---|---|
| Apertus v1.1-1.5B-Instruct | **828 MB** | 2/60 (3%) | 43 | 22/60 (37%) | 8 (50%) | 20 (63%) |
| **Apertus v1.1-4B-Instruct** | **2.0 GB** | **33/60 (55%)** | **0** | **42/60 (70%)** | **3 (19%)** | 9 (28%) |
| Apertus-8B-Instruct-2509 | 4.55 GB | 7/60 (12%) | 48 | **43/60 (72%)** | **0 (0%)** | 11 (34%) |

Anchors on the same suite and scorer:

```
Gemma 4 E4B tuned (hero)      90%   4.9 GB, shipped
Gemma 4 E2B tuned             83%   3.3 GB, shipped
Gemma 4 E4B stock             80%   4.9 GB
Gemma 4 E2B stock             73%   3.3 GB      <- measured 2026-08-17, 44/60
Apertus-8B 3-shot             72%   4.55 GB
Apertus v1.1-4B 3-shot        70%   2.0 GB
Qwen3-8B stock                58%   4.9 GB
Apertus v1.1-4B zero-shot     55%   2.0 GB
Apertus v1.1-1.5B 3-shot      37%   828 MB
Gemma 3 1B stock (4 GB tier)  33%   0.8 GB, shipped
```

## The 8B's zero-shot score is an artifact — and it is ELMOD's artifact, exactly

Apertus-8B scored **7/60 with 48 format errors** zero-shot, then **43/60 (72%)** at 3-shot with
**48/48 format adherence**. Those are, to the item, the same two numbers ELMOD produced (7/60 → 43/60,
46 format errors → 100% adherence). Two unrelated German-first models, same failure, same recovery.

The mechanism is visible in the raw responses — it answers in English prose instead of the app's
contract:

```
vmp-e1  "The student's sentence "Ich warte für den Bus." is grammatically correct
         and natural German."                                    <- also a real miss
vmp-e3  "The student's sentence is grammatically correct, but it can be improved...
         "Er denkt oft an seine Kindheit.""                       <- correct fix, scored FAIL
```

`vmp-e3` gets the grammar exactly right (`auf` → `an`) and still scores zero, because the harness
cannot parse prose. **Any German-first model measured zero-shot on the app's prompt should be assumed
format-blocked until `format_errors` is checked.** The number to quote is the 3-shot one.

## The 4B is the exception, and that is the finding

`Apertus-v1.1-4B-Instruct` produced **0 format errors zero-shot** — it follows the FIX/WHY/OK
contract cold, where its own 8B sibling failed 48 of 48. Same family, same tokenizer, opposite
behaviour. The v1.1 line ships a different chat template (`<SPECIAL_61>`-style control tokens plus a
`Deliberation: disabled` header) than the v1.0 `2509` line (`<|system_start|>`), which is the likely
cause.

Practical consequence: the 4B is the only Apertus that could be dropped into the app without burning
context on three worked examples every call.

## Composition — `dawo` is the wall, for a fourth family

Best condition for each model, all 15 items per phenomenon:

| | vmp | sep | refl | **dawo** |
|---|---|---|---|---|
| Apertus-8B, EN 3-shot | 14/15 | 12/15 | 12/15 | **5/15 (33%)** |
| Apertus v1.1-4B, EN 3-shot | 14/15 | 11/15 | 12/15 | **5/15 (33%)** |
| Apertus v1.1-1.5B, EN 3-shot | 9/15 | 3/15 | 8/15 | **2/15 (13%)** |
| *ELMOD 2.7B, EN 3-shot* | *15/15* | *13/15* | *11/15* | ***4/15 (27%)*** |
| *LLäMmlein 7B chat, EN 3-shot* | *14/15* | *14/15* | *11/15* | ***5/15 (33%)*** |
| **Gemma 4 E2B stock, zero-shot** | **14/15** | **12/15** | **9/15** | **9/15 (60%)** |

Apertus makes it **four of four** German-first families that cap at ~33% on da-/wo-compounds while
clearing 73–93% on the other three areas. The contrast with the last row is the point: stock E2B —
*not* German-first, merely well-trained multilingually — nearly doubles every German-first model on
`dawo` while matching them elsewhere. Whatever produces da-/wo- competence is not "more German
pretraining data."

## Verdict by tier

| tier | incumbent | Apertus candidate | verdict |
|---|---|---|---|
| 4 GB entry | Gemma 3 1B stock, **33%** | v1.1-1.5B, 37% 3-shot | ❌ **negative result.** +4 points is inside noise on 60 items, and it falsely "corrects" **50%** of already-correct sentences — the failure mode this project calls fatal for a tutor. Fourth failed attempt at this tier |
| 6 GB low/mid | E2B tuned, **83%** | v1.1-4B, 70% 3-shot / 55% zero-shot | ⚠️ **the only one worth more work.** Loses to *stock* E2B (73%) head-to-head, but does it at **2.0 GB vs 3.3 GB**. A fine-tune is the open question, not a foregone win |
| 8 GB high | E4B tuned, **90%** | 8B, 72% 3-shot | ❌ below stock E4B (80%) at roughly the same size, and needs 3-shot to get there |

**Nothing here beats what ships.** The honest summary is that Apertus v1.1-4B reaches *stock-E2B-class*
quality at 60% of the size, with better verdict discipline (19% false-correction vs Gemma's ~36%) and
worse raw knowledge. Given this project's standing rule — *base multilingual substrate sets the
ceiling; tuned Qwen3-4B (62%) still lost to stock Gemma E4B (72%)* — a tuned Apertus-4B would have to
beat tuned E2B's 83% from a 70% stock base. The measured fine-tune lift on capable bases here is
~+13 points, which lands at ~83%: a tie, for a smaller model.

That is a real but narrow prize, and it is the only Apertus experiment with a defensible rationale.

## The 70B is a separate question

`Apertus-70B-Instruct-2509` is a **teacher** candidate, not an on-device one, and none of the above
bears on it directly — teacher quality is about constructing *wrong* German, which is a different
task from correcting it. Selection criteria, the repo traps, and the bake-off protocol live in
[`../../TEACHER_GENERATION_FIX.md`](../../TEACHER_GENERATION_FIX.md) §5a.

One transferable signal: Apertus tokenizes German at **1.70 tokens/word, identical to gemma-4-E4B**
(131k vocab). The Granite tokenizer-inefficiency failure (49k vocab, ~1.9 tok/word) does not apply to
this family at any size.

## Traps hit, for the next candidate

1. **⚠️ v1.5 is a different architecture from v1.0.** `Apertus-v1.5-8B`/`-70B` are `model_type:
   apertus1p5`, `Apertus1p5ForConditionalGeneration`, multimodal, HF-gated, and need a custom
   `transformers` branch. mlx-lm 0.31.3's `apertus.py` implements `model_type: apertus` only — the
   **`2509` v1.0 and `v1.1` lines**. Reading `config.json` off the HF API catches this for free;
   renting a pod first does not.
2. **`mlx_lm convert` fails after quantizing** if the source repo was cached weights-only. `save()`
   re-resolves the repo with `local_files_only=True` and raises `IncompleteSnapshotError` over
   missing `.gitattributes`/`README.md`. Run `snapshot_download(repo)` in full first.
3. **Check `format_errors` before believing any score.** See above; it inverted the 8B's result
   entirely.

## Reproduce

```bash
# zero-shot, scoreboard-comparable
.venv/bin/python scripts/run_baseline_eval.py \
    --model models/apertus-v1.1-4b-instruct-4bit --tag baseline --app-guard

# 3-shot — the number to quote for a format-blocked model
.venv/bin/python scripts/prompt_variants_elmod.py --mode fewshot \
    --model models/apertus-v1.1-4b-instruct-4bit --tag apertus4b-fewshot

# conversion (snapshot first, or save() throws after quantizing)
.venv/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('swiss-ai/Apertus-v1.1-4B-Instruct')"
.venv/bin/python -m mlx_lm convert --hf-path swiss-ai/Apertus-v1.1-4B-Instruct \
    -q --q-bits 4 --q-group-size 64 --mlx-path models/apertus-v1.1-4b-instruct-4bit
```
