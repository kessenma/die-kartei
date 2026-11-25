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
[`bueble.md`](data/german-first-models-writeups/bueble.md).

> ## ⚠️ Verdict revised 2026-07-30 — read this first
>
> **The anchor this whole survey measured against was wrong.** Stock Gemma 3 1B was recorded at
> 58% core / 0% false corrections. The scorer credited replies that open `OK` and then append a
> `FIX:` line, which is what that model emits on nearly every input and which the app renders as
> *nothing*. Scored as the app behaves, stock Gemma 3 1B is **34% core with a 100% miss rate**.
>
> Two conclusions below invert:
>
> - **"No candidate clears the bar" is false.** Granite 3.3 2B was never tying the incumbent at
>   57% vs 58% — on the v2 holdout it beats it by 21 points, 55% vs 34%.
> - **"Not obviously worth a training run" is false.** That run happened (2026-07-30, ~40k v2
>   examples) and landed **72% guarded**, more than double the incumbent. See §3 of
>   [`training-v2.md`](training-v2.md).
>
> What survives, and is worth keeping: this doc's projection that a Granite fine-tune would land
> "around ~70% guarded" was **accurate**. So was the substrate rule — Granite still finishes
> below tuned E2B (84%), and no non-Gemma model reached the 6 GB tier. The error was in the
> comparison point, not the method.

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
[`bueble.md`](data/german-first-models-writeups/bueble.md): 7% strict / 25% lenient, never once emits a bare `OK`.
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

So the honest state of the budget tier (**updated 2026-07-30 — see the banner at the top**):

1. ~~**The 4 GB tier stays on stock Gemma 3 1B (58%, safe: never falsely corrects).**~~ The
   incumbent is **34% with a 100% miss rate**, and it is not safe, it is silent. **Tuned Granite
   3.3 2B beats it at 72%** and is the tier's best available answer, pending a device memory
   measurement.
2. **The 6–8 GB tier gets the shipped tuned E2B (83%, 84% on the v2 corpus).** Unchanged, and
   still the real budget win of this work.
3. **Granite 3.3 2B was the card worth playing, not parking.** Corrected: it was the only
   candidate above the true floor, and the fine-tune this doc declined to recommend is the one
   that produced the tier's best result.
4. **The lever that's now exhausted is more SFT.** A LoRA rank test (r=8 → r=32, 4× trainable
   params) cut validation loss 0.89 → 0.71 and moved the benchmark by 4 items in 82,
   McNemar p = 0.42. Granite's ceiling on this corpus is ~70%, and the gap to E2B is substrate
   and tokenizer, not training. Track paused there.

The full sweep cost ~2 hours of Mac time (five converts + eleven eval runs + two quant experiments)
and settled five "maybe this one?" model questions plus the 3-bit path the model cards couldn't.
Cheap, and exactly what the eval bench is for.

## Addendum 2026-08-26 — Granite 4.2-3b: a newer base that is a *worse* base

IBM released the Granite 4.2 family on 2026-08-25 (dense 3B/8B/30B "reasoning" models, Apache 2.0,
German among 12 tested languages). Since granite-4.1-3b v4 is the standing 4 GB-tier favorite
(164/203 tuned), the 3B was probed the same day. **Verdict: stock 4.2-3b scores below stock 4.1-3b
on every suite; the fine-tune was declined.** Total cost: ~$0.25 (a pod was provisioned and
terminated before training) plus ~1 h of Mac eval time.

### Compatibility notes (all clean — the pipeline takes it unchanged)

- `GraniteForCausalLM`, `model_type: granite`, dense, 40 layers, vocab **100,352** — same
  architecture class and German-friendly vocab as 4.1; `mlx_lm`'s granite arch handles every 4.2
  scaling field (`attention_multiplier` 0.015625, the rest 1.0).
- **New ChatML-style template** (`<|im_start|>`, replacing 4.1's format) with `enable_thinking`
  **defaulting to True**. The switch only changes the generation prompt: True primes
  `<|im_start|>assistant\n<think>\n`, False primes `<think></think>`. `run_baseline_eval.py`
  already passes `enable_thinking=False`; training rows would render with an empty
  `<think></think>` prefix, consistent with that. **If this family is ever tuned: bake a template
  with default False into the shipped checkpoint** — MLX Swift in the app can't pass the kwarg.
- Harness traps checked per the standing rule: `<|im_start|>` encodes to a single id (100256),
  EOS `<|im_end|>` (100257), 0 format errors across all 121 v0+v1 items.

### Results (guarded, local MLX 4-bit convert at 4.5 bpw)

| suite | 4.2-3b stock | 4.1-3b stock |
|---|---|---|
| core v0 (60) | **27** | 31 |
| ext v1 (61) | **34** | 39 |
| holdout v2 (82) | **39** | 41 |
| **total /203** | **100** | **111** |
| false corrections /32 | **9%** | 34% |
| miss rate /69 | **67%** | 45% |

Per-phenomenon the decline is scattered, not a collapse: core lost `dawo` 8→5 and `vmp` 12→10;
ext lost `adjend` 6→3, `aux` 5→3, `wechsel` 4→2 while *gaining* `ndekl` 0→3 and `imperativ` 1→2.
No cell moved the way a substrate change would.

**The real finding is the behavior flip.** The reasoning retrain shifted the verdict prior hard
toward "OK": false corrections 34% → 9%, misses 45% → 67%. With thinking disabled, 4.2 is a much
more cautious model that waves half again as many real errors through — the Qwen/Phi failure mode,
arriving via RL-for-reasoning rather than weak German. Same knowledge, worse judgment for a tutor.

### Why the tune was declined

The granite path's value was "base knows German but not correction behavior" — the v4 corpus adds
the behavior. 4.2 starts 11 items lower with *less* verdict courage to build on, and by the
substrate-sets-the-ceiling rule the tuned outcome projects at-or-below granite-4.1 v4's 164.
$2.50 would most likely buy a "confirmed, slightly worse" row. Declined; 4.1 v4 keeps the bench spot.

**Reopen criteria:** a granite-4.2-**1b** (would be a genuinely new size point for the 4 GB tier),
or independent evidence that reasoning-SFT'd bases respond differently to grammar SFT (in which
case the stock probe under-predicts). The 8B is moot — E4B owns that tier at 90% core.

Artifacts: `models/granite42-3b-4bit` (local), `results/guarded-{v0,v1ext,v2}_granite42-3b-4bit.json`.
Scoreboard row in the 2026-08-19 v4 block of [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md).

```bash
# reproduce
.venv/bin/python -m mlx_lm convert --hf-path ibm-granite/granite-4.2-3b -q --q-bits 4 \
    --q-group-size 64 --mlx-path models/granite42-3b-4bit
for EV in grammar_eval_v0:guarded-v0 grammar_eval_v1_extra:guarded-v1ext grammar_eval_v2_holdout:guarded-v2; do
  f=${EV%%:*}; t=${EV##*:}
  .venv/bin/python scripts/run_baseline_eval.py --model models/granite42-3b-4bit \
      --eval-file data/eval/${f}.json --tag $t --app-guard
done
.venv/bin/python scripts/behavior_metrics.py --app-guard \
    results/guarded-v0_granite42-3b-4bit.json results/guarded-v1ext_granite42-3b-4bit.json
```

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
