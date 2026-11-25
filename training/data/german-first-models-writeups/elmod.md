# ELMOD-2.7B (Fraunhofer IIS) — the most promising 4 GB base measured

**Verdict: reopened, not closed.** 1.6 GB, and **72% guarded on core v0 with a 3-shot prompt** —
stock, no fine-tuning. That is level with *stock Gemma 4 E2B* (73%) at half the size, and well above
the ~55% substrate floor. It is not shippable as-is and it has a real weakness (`dawo`), but "below
the floor, close it" was wrong.

> 🛑 **This document originally reported "0 of 101 correction items passed — closed."** That number
> was real but it measured the wrong thing: the app's system prompt is in **English**, and ELMOD is
> German-first with weak English instruction-following. It was an English-instruction-following
> failure reported as a German-grammar failure. Corrected 2026-08-16, same day, before anything was
> built on it. Full history in §"What went wrong with the first measurement".

Ran 2026-08-16. This file merges the original `ELMOD_EVAL.md` with the pre-registered
`ELMOD_EVAL_PLAN.md` (§"The plan, and which traps it caught").
Family index: [README.md](README.md). Siblings: [BübleLM](bueble.md), [LLäMmlein](llammlein.md).
Companion to [`BUDGET_BASE_SEARCH.md`](../../BUDGET_BASE_SEARCH.md),
[`MODEL_SCOREBOARD.md`](../../MODEL_SCOREBOARD.md).

## What it is

[`fraunhofer-iis/elmod-2.7b-it`](https://huggingface.co/fraunhofer-iis/elmod-2.7b-it) — a 2.85B
German+English GPT-NeoX, pretrained on 55k H100 hours by Fraunhofer IIS and instruction-tuned by
the same group. The first German model on this bench whose SFT came from its own pretraining
authors rather than a community tune bolted onto a base.

**1.605 GB on disk at 4.504 bits/weight.** Context **2048** — the binding limitation (§Caveats).
License **CC BY-NC-4.0**, which now actually matters (§License).

Settled before anything was downloaded, from the model card, `config.json`, and the HF API:

| fact | value | consequence |
|---|---|---|
| architecture | `GPTNeoXForCausalLM`, 32 layers × 2560, vocab 65,024 | Python `mlx_lm` ships `gpt_neox.py` ✅ |
| MLX **Swift** support | **absent** — not in the 57-type registry | ~a day of Swift work if it ships |
| context | **2,048**, `rope_theta` 10000, no scaling | hard cap; grammar-correction only |
| attention | MHA, no GQA → ~320 KB/token KV | ~640 MB KV at full context |

## Results — three prompt conditions, same 60 core items, same scorer, all `--app-guard`

| | core v0 | false-corr (/16) | miss (/32) | format adherence | clean FIX lines |
|---|---|---|---|---|---|
| English zero-shot *(the app's real prompt)* | **7/60 (12%)** | 100% | 100% | 2% | — |
| German zero-shot | 32/60 (53%) | 50% | 47% | 100% | 73% |
| **English 3-shot** | **43/60 (72%)** | **19%** | **28%** | **100%** | **100%** |

Where 72% sits among models scored on **this same core v0 suite**, guarded:

```
Gemma 4 E4B tuned (hero)   90%    4.9 GB, shipped
Gemma 4 E2B tuned          83%    3.3 GB, shipped
Gemma 4 E4B stock          80%
Gemma 4 E2B stock          73%    3.3 GB
LLäMmlein 7B chat 3-shot   73%    3.5 GB   (sibling, research-only licence)
ELMOD 3-shot, stock        72%    1.6 GB   <- here
LLäMmlein 7B base 3-shot   68%    3.9 GB
Granite 3.3 2B stock       57%    1.5 GB
SauerkrautLM gemma-2-2b    53%
ELMOD German zero-shot     53%
Gemma 3 1B stock           34%
```

> ⚠️ **Do not compare this to "tuned Granite 72%".** That number is **59/82 on the v2 holdout**, a
> different suite ([`MODEL_SCOREBOARD.md`](../../MODEL_SCOREBOARD.md) §4 GB tier). The two 72%s are
> not the same measurement, and treating them as equal would repeat exactly the cross-suite error
> the v2 retraction banner exists to warn about. ELMOD has **not** been scored on the v2 holdout,
> and the holdout is spent once per candidate.

### Few-shot is affordable here, not just diagnostic

Zero-shot prompt: 175 tokens. 3-shot prompt: **320 tokens**, +400 generation = 720 of a 2048
window, leaving **1328 tokens of headroom**. So the 72% is not a lab-only number that a fine-tune
would have to recover — it is a configuration the app could ship, at the cost of ~145 extra prompt
tokens per correction.

That also makes it the strongest fine-tunability signal available: a model that reaches 72% *shown
three examples* is a far better bet to tune than the zero-shot 12% suggested.

## What went wrong with the first measurement

The eval's correction prompt (`ConversationPrompts.correctionSystemPrompt`, mirrored in
`run_baseline_eval.py`) is entirely in English — reasonably, since that is what the app sends.
ELMOD answered it in fluent free-form English prose, never emitting `OK` or `FIX:`, scoring 2%
format adherence and 0/101 correction items.

Translating the *same contract* into German took format adherence from **2% to 100%**. The model
could always follow the contract; it could not follow it in English.

**Control — is this a general effect?** Reran SauerkrautLM-gemma-2-2b (a German model already on
the scoreboard at 53% guarded core) with the identical German prompt: **53% → 50%.** No lift. So
the German-prompt effect is specific to ELMOD's German-first pretraining, **not** a rising tide
that would relabel the whole scoreboard. Every other model's English-prompt number stands.

> 📌 **Superseded as a general rule, 2026-08-17.** This finding generalised into "add a
> native-language prompt variant for any German-first candidate." [LLäMmlein](llammlein.md)
> **inverts it**: German-only pretrained, and its 7B chat goes English 58% → German **23%** (format
> 94% → 23%). The real mechanism is not prompt language but **worked examples** — 3-shot gives 100%
> adherence for both models. Prompt language is a per-model variable to *test*, not a known
> correction. See [README.md](README.md#what-they-disagree-on--and-the-correction-it-forced).

## Getting it to run at all (two blockers, one of them the model's own bug)

Both had to be cleared before any of the above was measurable. **Neither was in the plan's trap
list** — see §"The plan, and which traps it caught".

### 1. `mlx_lm`'s GPT-NeoX uses the wrong activation

`mlx_lm/models/gpt_neox.py` hardcodes `nn.gelu_approx` (tanh/FastGELU). ELMOD's `config.json`
declares `hidden_act: "gelu"` (exact, erf-based). Greedy-decoding one eval prompt under both
**diverges at token 20 of 40** — fluent-but-different text, nothing crashes.
[`scripts/eval_elmod.py`](../../scripts/eval_elmod.py) patches `gpt_neox.MLP.__call__`, scoped to
that one architecture so other scoreboard rows stay comparable.

### 2. ELMOD's tokenizer does not register its own chat-control tokens

**A bug in the published model.** `tokenizer.json` registers 1515 added tokens — ids 0–4 and 7
onward. **Ids 5 and 6 are missing**, and those two, `<|im_start|>`/`<|im_end|>`, are the *only*
control tokens its own `chat_template.jinja` emits.

Both exist in the base vocab, so `decode([6])` and `convert_tokens_to_ids('<|im_end|>')` both look
right — which is why the plan's Phase 0 check passed. But the *encoder* never produces them:

```
encode('<|im_end|>')  ->  [1537, 1601, 2085, 15761, 1601, 1539]   # six literal pieces
```

`apply_chat_template` rendered correct ChatML and then tokenized it into literal characters. The
model was fed a format it was never trained on, never emitted id 6, and every completion ran to
max_tokens into unrelated pretraining documents — ELMOD's own default system prompt, then a
vape-pen listicle. [`scripts/fix_elmod_tokenizer.py`](../../scripts/fix_elmod_tokenizer.py)
registers the two tokens at their existing vocab ids; nothing shifts, `vocab_size` stays 65024.

After the fix, prompts drop 179 → 158 tokens and generation terminates on its own. **All numbers
above are post-fix.**

Conversion itself was clean: 4.6 s, peak RSS 3.29 GB. The plan's feared float32 upcast never
happens — `convert()` reads `config["torch_dtype"]`, and transformers 4.56 renamed that key to
`dtype`.

## Composition — the one robust weakness

Per-phenomenon, core v0 guarded, across all three conditions:

| phenomenon | English 0-shot | German 0-shot | **English 3-shot** |
|---|---|---|---|
| vmp (verb+preposition) | 3/15 (20%) | 11/15 (73%) | **15/15 (100%)** |
| sep (separable verbs) | 3/15 (20%) | 9/15 (60%) | **13/15 (87%)** |
| refl (reflexive) | 1/15 (7%) | 9/15 (60%) | **11/15 (73%)** |
| **dawo (da-/wo-compounds)** | 0/15 (0%) | 3/15 (20%) | **4/15 (27%)** |

`dawo` is weak in *every* condition and barely responds to few-shot. Three of the app's four core
areas go to 73–100% with three examples; the fourth stays at 27%. That is a real substrate gap, not
a prompting artifact, and it is the thing a fine-tune would have to fix.

**Confirmed family-wide.** [LLäMmlein](llammlein.md) lands at 5/15 on `dawo` at its best (0–1 of 8
counting error items only) despite scoring 73% overall. No German-first model measured here clears
33% on da-/wo-compounds. See [README.md](README.md#1-dawo-is-the-shared-wall).

## The plan, and which traps it caught

`ELMOD_EVAL_PLAN.md` was written before the download and pre-registered five predicted traps. Kept
because the hit rate is the useful part: **it caught none of the two that actually bit.**

| # | predicted | outcome |
|---|---|---|
| 1 | `generation_config` `max_length: 256` truncates | ❌ cleared in Phase 0 — `mlx_lm` reads only `eos_token_id` |
| 2 | `dtype: float32` declared over BF16 weights → 11.4 GB upcast | ❌ never happened (key renamed to `dtype`) |
| 3 | EOS mismatch (`</s>`=2 vs `<\|im_end\|>`=6) | ⚠️ partly — `mlx_lm` prefers 6; the *real* bug was ids 5/6 unregistered |
| 4 | `attention_bias`/`use_parallel_residual` ignored by `mlx_lm` | ❌ both honored correctly |
| 5 | Composition, not just pass rate — check per phenomenon | ✅ **the one that paid off** — found `dawo` |
| — | *(unpredicted)* | 🛑 hardcoded `gelu_approx`; unregistered chat tokens |

The plan's other durable contribution was the **five-minute kill switch**: before spending an hour
on 121 items, hand the model three prompts and check whether it ever emits a bare `OK`. BübleLM's
100% false-correction rate was visible in three prompts and cost a full run to confirm.

The plan also framed the bar as "72%, not 55%", which produced a cross-suite error — see the ⚠️
callout under Results. Pre-committing to a threshold is what
[`measure-before-gating`](../../MODEL_SCOREBOARD.md) warns against.

## Verdict

- **Ship as-is:** no. 72% core is not the shipping bar, and `dawo` at 27% would visibly fail
  learners on one of four target areas.
- **Fine-tune base:** **yes, genuinely arguable — this is the strongest 4 GB candidate measured.**
  72% stock few-shot at 1.6 GB, well clear of the ~55% floor, versus stock Granite's 57%. The open
  question is whether tuning fixes `dawo` or whether that is a pretraining gap.
- **Swift `GPTNeoX.swift` port:** now worth costing (~a day), where before it was moot.

**What has to happen before this is a real decision**, in order:

1. **Extension suite (v1_extra, 61 items) with the 3-shot prompt.** Core-only is half the picture,
   and it is cheap.
2. **Head-to-head against tuned Granite on the *same* suite.** The incumbent's 72% is on the v2
   holdout; ELMOD's is on core v0. One of them has to move onto the other's ground before "beats
   the incumbent" means anything. Cheapest honest option: score tuned Granite on core v0.
3. **The license call** (below) — this one is yours, and it gates everything downstream.
4. Only then: v2 holdout, which is spent once per candidate.

## License (CC BY-NC-4.0) — the real gate

Free of charge and ungated, but NonCommercial. This gated nothing while the model was failing; now
that it is the leading 4 GB candidate, it is the decision.

**NC is sticky through training.** A fine-tune is Adapted Material and inherits NC, so the cost is
not "swap the model out later" — it is discarding the tuned checkpoint and redoing the run on a
different base. And the incumbent it would displace, Granite 3.3 2B, is **Apache 2.0**. So ELMOD
has to be better by enough to be worth the strings.

Emailing Fraunhofer IIS for commercial terms is the clean resolution and now has a reason to
happen. Not done — outbound contact is the author's call.

For contrast, [LLäMmlein](llammlein.md) is **research-only RAIL-M**, which has no good-faith
non-commercial reading at all — CC BY-NC is the *permissive* end of this family.

## Criteria — what this says about the eval generally

- **Keep the English zero-shot number as the ship criterion.** It is what the app actually sends,
  and 12% is a truthful answer to "can this be dropped in today." Softening it would repeat the
  Gemma-3-1B fake-58% mistake.
- ~~**Add a native-language prompt variant for any German-first candidate.**~~ **Revised** — see the
  📌 note above. Prompt language is a per-model variable to test, with a control, not a standing
  correction.
- **Add few-shot compliance as the base-selection criterion.** Zero-shot compliance answers "can we
  ship it"; it is a poor proxy for "can we tune it." The ~55% lenient floor was standing in for
  that and got it badly wrong here — 45% lenient vs 72% few-shot on the same model. **This one has
  held up** across all three families.

## Caveats (honest)

- **Core suite only, 60 items.** Extension and holdout not run in the 3-shot condition.
- **The 3-shot demos were hand-written for this test** and cover OK/FIX/FIX. A different demo set
  would move the number; 72% is one draw, not a distribution. Demo choice matters — a fix-only demo
  set would teach it to always fix (the `packed-v2` lesson).
- **4-bit only,** no BF16 control.
- **The 2048-token window still caps the upside.** Enough for single-sentence correction with
  few-shot headroom to spare; not enough for conversation, stories, or paper study. A win here buys
  a better 4 GB *correction* tier, not a general 4 GB tutor.
- **~640 MB of KV at full context on top of ~1.6 GB of weights** is tight against the ~3.4 GB an
  iOS app gets. Confirm on a real 4 GB device via `MemoryBudget.footprintMB` before believing the
  tier assignment.

## Reproduce

```bash
cd training
.venv/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('fraunhofer-iis/elmod-2.7b-it')"
.venv/bin/python -m mlx_lm convert --hf-path fraunhofer-iis/elmod-2.7b-it -q --q-bits 4 \
    --mlx-path models/elmod-2.7b-it-4bit
.venv/bin/python scripts/fix_elmod_tokenizer.py models/elmod-2.7b-it-4bit   # REQUIRED

# English zero-shot (the app's real prompt) — eval_elmod.py = run_baseline_eval.py + exact-gelu patch
.venv/bin/python scripts/eval_elmod.py --model models/elmod-2.7b-it-4bit --tag baseline --app-guard
.venv/bin/python scripts/eval_elmod.py --model models/elmod-2.7b-it-4bit --tag baseline-extra \
    --app-guard --eval-file data/eval/grammar_eval_v1_extra.json

.venv/bin/python scripts/behavior_metrics.py --app-guard \
    results/baseline_elmod-2.7b-it-4bit.json results/baseline-extra_elmod-2.7b-it-4bit.json
.venv/bin/python scripts/score_elmod_lenient.py \
    results/baseline_elmod-2.7b-it-4bit.json results/baseline-extra_elmod-2.7b-it-4bit.json
```

The German-prompt and 3-shot runs are `scripts/prompt_variants_elmod.py`; saved responses are
`results/german-prompt_elmod-2.7b-it-4bit.json`, `results/fewshot_elmod-2.7b-it-4bit.json`, and the
control `results/german-prompt_sauerkraut-gemma2-2b-4bit.json`.

**The v2 holdout has NOT been run** — it is scored once per candidate and should be spent only
after the head-to-head in §Verdict.
