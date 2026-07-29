# Hunting a cheaper base than Gemma 4 E2B — a survey of small German-capable models

Question: the shipped German tutors are Gemma 4 E2B (3.3 GB) and E4B (5 GB). Is there a **smaller**
2–3 B model with enough German to fine-tune into a budget tutor for the 4–6 GB tier — one that
beats stock Gemma 3 1B (the entry-tier fallback) without needing E2B's memory?

Answer, after measuring four untested candidates: **no non-Gemma model clears the bar.** The one
that comes closest (Granite 3.3 2B) only *ties* the Gemma-3-1B it would have to beat. This is the
scoreboard's oldest lesson, re-confirmed from four new directions: **base German substrate sets the
ceiling, and Gemma is the only family that clears it.**

Companion to [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md), [`ARTICLE.md`](ARTICLE.md),
[`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md), and the detailed BübleLM writeup in
[`BUEBLE_LM_EVAL.md`](BUEBLE_LM_EVAL.md).

## The four candidates and why each was picked

Filtered from the mid-2026 sub-3B field (Phi-4-mini, Qwen3-3B, SmolLM3, Granite, Llama 3.2 3B,
Salamandra, BübleLM) through four hard constraints: fits 4–6 GB, instruction-following, real German
substrate, commercial license.

| candidate | why it was worth testing |
|---|---|
| **Granite 3.3 2B** (IBM) | Apache 2.0, native support for 12 languages incl. German, instruction-tuned, ~1.5 GB |
| **Llama 3.2 3B** | Officially supports German, strong instruction-following, the 1B's much-stronger sibling |
| **Salamandra 2B** (BSC) | Apache 2.0, 35 EU languages incl. German, instruction-tuned |
| **BübleLM 2B-SFT** | Reader suggestion; Gemma 2-2B *re-adapted for German* — the strongest "German substrate" story |

Ruled out without testing: **Gemma 3n E2B** (predecessor generation to the proven Gemma 4 E2B —
older, not newer), Qwen3-3B (Qwen family = knowledge-deficit rubber-stamp), Phi-4-mini (already
measured, Mistral-tier German), SmolLM3 (English-first).

Two kinds of candidate were tested: **base models** to fine-tune ourselves (Granite, Llama,
Salamandra) and **already-fine-tuned** German models to use closer to as-is (BübleLM-SFT,
SauerkrautLM). Both were asked the same question the eval answers.

## Results (all scored app-equivalent, `--app-guard`)

| model | kind | size | core raw→guarded | ext guarded | false-corr guarded | miss | format errs |
|---|---|---|---|---|---|---|---|
| **Granite 3.3 2B** | base | 1.5 GB | 50% → **57%** | 62% | **19%** | 43% | 0 |
| SauerkrautLM gemma-2-2b | German tune | 1.4 GB | 33% → 53% | 64% | 25% | 46% | 5 |
| Llama 3.2 3B | base | 2.0 GB | 27% → 35% | 70% | 53% | 43% | 0 |
| BübleLM 2B-SFT | German tune | 1.1 GB | 7% (25% lenient) | 5% | ~100% | ~100% | — |
| Salamandra 2B | EU tune | 1.2 GB | 7% → 7% | 13% | 100% | 100% | **99/121** |
| *anchors* | | | | | | | |
| Gemma 3 1B stock (entry) | | 0.8 GB | 58% | 59% | 0% | 55% | 0 |
| Gemma 4 E2B stock | | 3.3 GB | 65% → 73% | 85% | 0% | 28% | 0 |
| **Gemma 4 E2B tuned (shipped)** | | 3.3 GB | 68% → **83%** | 85% | 3% | 19% | 0 |

**None of the five beats stock Gemma 3 1B (58%) — the entry-tier model they'd have to displace.**
Granite comes closest (57%) and SauerkrautLM second (53%), both just under it.

## What each one taught

**Granite 3.3 2B — the only genuine near-miss.** Guarded core 57%, right at the ~55% floor, and the
*best-behaved* non-Gemma model measured: guarded false-corrections 19% (better than every stock
Gemma) and it catches more real errors than Gemma-3-1B (miss 43% vs 55%). Apache 2.0, 1.5 GB. But it
only *ties* the Gemma-3-1B it would need to beat, at nearly twice the size, and the substrate ceiling
says a fine-tune lands it around ~70% guarded — real, but still well short of the tuned E2B (83%) and
not obviously worth a training run + dataset re-pack. It's the one candidate that could serve as a
fine-tune base *if* the goal is a non-Gemma 4–6 GB tutor; it is not a reason to prefer that over
3-bit-quantizing the E2B that already scores 83%.

**Llama 3.2 3B — the substrate ceiling, cleanly.** A strong generalist (extension 70% guarded, zero
format errors, real instruction-following) that simply doesn't know German grammar well enough:
guarded core 35%, and it over-corrects *half* the correct sentences even after the echo guard. German
MMLU 53.3 ≪ Gemma, and it shows exactly where the app needs it most. The 1B waved through every error
(capacity); the 3B has the capacity and still fails on substrate. Below floor.

**Salamandra 2B — EuroLLM, a second time.** 7% core, **99 of 121 format failures**: it translates the
sentence to English instead of correcting it, rambles, and confabulates (*"the correct form is 'er'
instead of 'er'"*). 35-EU-language pretraining tuned for Catalan/Spanish/Basque has neither German
depth nor task discipline. The exact failure the scoreboard first recorded for EuroLLM-1.7B (13%).

**BübleLM 2B-SFT — German knowledge without verdict discipline.** Full writeup in
[`BUEBLE_LM_EVAL.md`](BUEBLE_LM_EVAL.md): 7% strict / 25% lenient, never once emits a bare `OK`.
Genuine German (its fixes are often correct) but no instruction-format discipline — the EuroLLM
pattern with more German and even worse format.

**SauerkrautLM gemma-2-2b — the best off-the-shelf German fine-tune, and still short.** This was the
answer to "is there an *already-fine-tuned* German model we can just test?" It's the strongest such
candidate at budget size (VAGO's German Spectrum-tune of Gemma 2 2B, 1.4 GB) and the best-*behaved*
of everything here — only 5/121 format errors, because the light Spectrum tune preserved Gemma 2's
instruction-following where BübleLM's heavier SFT destroyed it. But guarded core 53% still lands
*below* stock Gemma 3 1B (58%): a German *chat* tune lifts general German without lifting the
specific hard grammar (verb-prep, separable, reflexive, da-/wo), and it's built on an older Gemma 2
substrate than the Gemma 4 E2B already shipped. Confirms the rule from a fifth angle — a general
German fine-tune is not a German-*grammar-correction* model.

Also considered and rejected without a full eval: **German GEC seq2seq models**
(`mbart-german-grammar-corrector` 610M, `t5-small-grammar-correction-german`). These are the only
models *purpose-built* for German error correction, but they're encoder-decoder translators that map
wrong→corrected sentence — no verdict discipline (`OK` vs `FIX`), no explanations, no tutor
conversation, and no MLX-Swift runtime. Wrong architecture for the app entirely.

## Conclusion

Salamandra and BübleLM fail on task discipline (the EuroLLM mode); Llama 3.2 3B has the discipline
but fails on German substrate; SauerkrautLM has both partly but its Gemma-2 substrate still lands
below the floor. Only Granite clears the floor at all, barely, and still doesn't beat what's shipped.
**The Gemma-4-family substrate advantage is real and this survey couldn't route around it — from
five directions, base *and* already-tuned.**

And the obvious escape hatch — shrink the model you already have — is closed too: **3-bit-quantizing
the tuned E2B doesn't work.** Gemma 4's PLE embeddings must stay high-bit or the model breaks, so
mixed 3-bit reaches only ~5.3 bpw (3.2 GB, barely under the 4-bit's 3.4 GB) *and* craters quality to
63% guarded — below stock E2B. Full detail in [`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md).
There is no quantization path to a smaller tier for this architecture.

So the honest state of the budget tier:

1. **The 4 GB tier stays on stock Gemma 3 1B (58%, safe: never falsely corrects).** Nothing measured
   beats it there, and Gemma 4 can't be shrunk into it.
2. **The 6–8 GB tier gets the shipped tuned E2B (83%).** That remains the real budget win of this work.
3. **Granite 3.3 2B is the only card worth keeping** — if a future need demands a non-Gemma,
   Apache-2.0, sub-2 GB base, it's the one that clears the floor. Park it, don't pursue it.
4. **The only lever left for the 4 GB tier is more training, not a smaller model or quant** — a
   Granite fine-tune (~70% projected) or a fresh Gemma-3-1B data wave — and both are uncertain bets
   against a 58% incumbent that at least never misleads.

The full sweep cost ~2 hours of Mac time (five converts + eleven eval runs + two quant experiments)
and settled five "maybe this one?" model questions plus the 3-bit path the model cards couldn't.
Cheap, and exactly what the eval bench is for.

## Reproduce

```bash
cd training
# ready MLX builds — no conversion needed:
.venv/bin/python scripts/run_baseline_eval.py --model mlx-community/granite-3.3-2b-instruct-4bit --tag baseline
.venv/bin/python scripts/run_baseline_eval.py --model mlx-community/Llama-3.2-3B-Instruct-4bit --tag baseline
# Salamandra + SauerkrautLM need a convert. NB: mlx_lm's save() trips an IncompleteSnapshotError on
# these repos (a couple of missing README/.gitattributes files) — pre-download to complete the snapshot:
.venv/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('BSC-LT/salamandra-2b-instruct')"
.venv/bin/python -m mlx_lm convert --hf-path BSC-LT/salamandra-2b-instruct -q --q-bits 4 --mlx-path models/salamandra-2b-instruct-4bit
.venv/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('VAGOsolutions/SauerkrautLM-gemma-2-2b-it')"
.venv/bin/python -m mlx_lm convert --hf-path VAGOsolutions/SauerkrautLM-gemma-2-2b-it -q --q-bits 4 --mlx-path models/sauerkraut-gemma2-2b-4bit
# add --eval-file data/eval/grammar_eval_v1_extra.json --tag baseline-extra for the extension suite;
# guarded/behavioral numbers via the same apply_app_guard rescoring used across the board.
```
