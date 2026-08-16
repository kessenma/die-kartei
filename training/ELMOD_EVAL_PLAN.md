# ELMOD-2.7B for the 4 GB tier — a test plan

**Question:** [`fraunhofer-iis/elmod-2.7b-it`](https://huggingface.co/fraunhofer-iis/elmod-2.7b-it) is a
2.85B German+English model, instruction-tuned by the group that pretrained it, ~1.7 GB at 4-bit.
Does it beat the 4 GB tier's current best answer?

**Why it isn't already settled:** three German models have been rejected on this bench
(BübleLM, Salamandra, LLäMmlein-class), all for the same reason — German substrate with no
task discipline. ELMOD is the first one that is *instruction-tuned by its own authors* rather than
carrying a community SFT bolted onto a base. That is exactly the variable that sank the others, so
the prior does not transfer cleanly. It needs a measurement.

**What it would cost to find out:** one 5.7 GB download and about an hour of Mac time. No Swift work
and no GPU.

Companion to [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md), [`BUEBLE_LM_EVAL.md`](BUEBLE_LM_EVAL.md),
[`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md), [`DATA_V2_DISTILL_PLAN.md`](DATA_V2_DISTILL_PLAN.md).

---

## 1. What is already settled — do not re-derive these

Verified 2026-08-15 from the model card, `config.json`, the HF API, the Fraunhofer blog post, and
the local `mlx_lm` install.

| fact | value | consequence |
|---|---|---|
| license | `cc-by-nc-4.0` (metadata tag; no LICENSE file in repo) | see §5 — a separate track, not a blocker on measuring |
| architecture | `GPTNeoXForCausalLM`, 32 layers × 2560, vocab 65,024 | Python `mlx_lm` 0.31.3 ships `gpt_neox.py` ✅ |
| MLX **Swift** support | **absent** — `gpt_neox` not in the 57-type registry | ~a day of Swift work, only if it clears §3 |
| context | **2,048**, `rope_theta` 10000, no scaling | hard cap. Grammar-correction only; see §4 |
| attention | MHA, no GQA → ~320 KB/token KV | ~640 MB KV at full context, on top of weights |
| download | 5.70 GB (4.95 + 0.75 GB shards, 7 MB tokenizer) | the only slow step |
| 4-bit estimate | ~1.6–1.8 GB (untied `lm_head`, 65k vocab both stay costly) | confirm at convert time |

The Fraunhofer LinkedIn post and blog say "freely available on the open-source platform Hugging
Face." That phrase describes *Hugging Face*. Neither document states license terms. The `cc-by-nc-4.0`
tag is the only licensing statement that exists.

## 2. The bar is 72%, not 55%

Two different plans with two different bars. Decide which one the number supports *after* seeing it,
but know in advance what each would require.

| plan | what it has to beat | why |
|---|---|---|
| **ship as-is** | **tuned Granite 3.3 2B, 72% guarded core** | the 4 GB tier's current best answer ([`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md) §banner) |
| **use as a fine-tune base** | the **~55% substrate floor** | the scoreboard's standing rule: "base core ≥ ~55% is necessary but not sufficient" |

Anchors to score against, all `--app-guard`:

```
Gemma 4 E4B tuned (hero)      85% raw / 90% guarded   8 GB tier, shipped
Gemma 4 E2B tuned             68% / 83% guarded       6 GB tier, shipped
Gemma 4 E2B stock             65% / 73% guarded
Granite 3.3 2B tuned          72% guarded             ← 4 GB tier incumbent, the real bar
Granite 3.3 2B stock          50% / 57% guarded
Gemma 3 1B stock              34% core, 100% miss     the thing Granite replaced
BübleLM-2B-SFT                7% strict / 25% lenient the German-substrate failure mode
```

**Do not pre-commit to a threshold.** Run it, put the number next to these, judge then. The purpose
of the anchors is to know what "good" would even mean, not to auto-decide.

## 3. Execution

Ordered so the cheap signals come back first and the 5.7 GB download is the *third* step, not the
first.

### Phase 0 — ✅ DONE (2026-08-16), all clear

Ran and passed. **Do not repeat this** — start at Phase 1.

| check | result |
|---|---|
| longest eval item (v0 + v1_extra, 121 items) | **86 tokens** (`refl-e5`) |
| full prompt (system + user) + 400 max_tokens | **~650 tokens against a 2,048 window** — ample headroom |
| tokenizer `eos_token` | `</s>` = **2** ⚠️ disagrees with the ChatML template |
| `<\|im_end\|>` / `<\|im_start\|>` | **6** / 5 |
| `model_max_length` | unset sentinel — no guard from the tokenizer |

**The EOS disagreement is real but `mlx_lm` handles it.** `tokenizer_config.json` says EOS is `</s>`
(id 2) while the chat template terminates turns with `<|im_end|>` (id 6).
[`mlx_lm/utils.py:276-277`](.venv/lib/python3.12/site-packages/mlx_lm/utils.py) overrides
`config["eos_token_id"]` from `generation_config.json` (which says 6) and passes it to the tokenizer
wrapper at line 496. So generation stops on 6 without intervention.

**Still worth watching in Phase 2:** the model may also emit the pretraining `</s>` (id 2), which is
*not* in the stop set. If answers are correct but followed by trailing garbage to max-tokens, add 2
to `eos_token_ids` — that is the BübleLM symptom exactly.

The original Phase 0 commands, for reference:

```bash
cd training
# tokenizer only — 7 MB, no model download
.venv/bin/python -c "
from transformers import AutoTokenizer
t = AutoTokenizer.from_pretrained('fraunhofer-iis/elmod-2.7b-it')
print('eos', t.eos_token, t.eos_token_id)          # expect <|im_end|> 6
print('im_end id', t.convert_tokens_to_ids('<|im_end|>'))
"
# then measure the app's real prompt against the window
.venv/bin/python scripts/run_baseline_eval.py --dry-run --eval-file data/eval/grammar_eval_v0.json
```

Take the longest printed prompt, tokenize it with the ELMOD tokenizer, add the generation budget.
**If prompt + output exceeds 2,048, stop here** — everything downstream would fail for the wrong
reason and you would have measured the window, not the model.

### Phase 1 — download + convert (~15 min on fast wifi, ~10 min convert)

```bash
cd training
.venv/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('fraunhofer-iis/elmod-2.7b-it')"
.venv/bin/python -m mlx_lm convert --hf-path fraunhofer-iis/elmod-2.7b-it -q --q-bits 4 \
    --mlx-path models/elmod-2.7b-it-4bit
```

Record the on-disk size of `models/elmod-2.7b-it-4bit`. That number decides which tier it could even
occupy, before quality enters into it.

### Phase 2 — the five-minute kill switch

Before spending an hour on 121 items, hand it three prompts in the app's exact format: one correct
sentence, one `refl` case error, one `sep` error.

**Look for exactly one thing: does it ever emit a bare `OK`?** BübleLM's 100% false-correction rate
was visible in three prompts and cost a full eval run to confirm. A model that structurally cannot
accept a correct sentence is done, whatever its German is like.

### Phase 3 — the real eval (~40 min)

```bash
cd training
.venv/bin/python scripts/run_baseline_eval.py --model models/elmod-2.7b-it-4bit --tag baseline --app-guard
.venv/bin/python scripts/run_baseline_eval.py --model models/elmod-2.7b-it-4bit --tag baseline-extra \
    --app-guard --eval-file data/eval/grammar_eval_v1_extra.json
```

Score core first. Only run the **v2 holdout** if core is interesting — it is scored once per
candidate and never iterated against ([`DATA_V2_DISTILL_PLAN.md`](DATA_V2_DISTILL_PLAN.md) §2).

Report raw **and** guarded, false-correction rate, miss rate, and format errors. The guarded/raw gap
and the miss rate are what separated "safe" from "silent" when the Gemma-3-1B anchor turned out to
be wrong — a high score with a 100% miss rate is not a good model.

## 4. Predicted traps

Every model on this bench has had two or three. These are the ones visible from the config files
before anything is downloaded.

1. ~~**`generation_config.json` sets `max_length: 256`.**~~ **Cleared in Phase 0.** `mlx_lm/utils.py`
   reads only `eos_token_id` out of `generation_config.json`, and
   [`run_baseline_eval.py:248`](scripts/run_baseline_eval.py#L248) passes an explicit
   `max_tokens=400`. No truncation risk.
2. **`config.json` declares `dtype: float32` but the weights are BF16** (5.7 GB ÷ 2.85B = 2
   bytes/param). A loader that trusts the field upcasts and wants ~11.4 GB transiently during
   convert. Watch memory on the convert step.
3. **EOS mismatch — measured in Phase 0, partly cleared.** `config.json` and
   `generation_config.json` agree on 6 (`<|im_end|>`); `tokenizer_config.json` says `</s>` = 2.
   `mlx_lm` prefers 6, so the common case works. The residual risk is the model emitting `</s>`,
   which is not in the stop set — see the Phase 0 note above.
4. **`attention_bias: true` and `use_parallel_residual: false`.** Both non-default for GPT-NeoX.
   If `mlx_lm`'s implementation ignores either, output is fluent-but-wrong rather than crashing —
   the dangerous failure mode. Sanity-check a German completion against `transformers` on CPU if the
   numbers look strange.
5. **Composition, not just pass rate.** Per the standing lesson: break the result down by phenomenon
   (`refl`, `sep`, `vmp`, `dawo`, `relpron`) before concluding anything. An aggregate that clears the
   bar while `refl` collapses is the class-collapse failure that pass-rate gates miss.

## 5. The license track — start it now, it runs in parallel

Zero cost, slow turnaround, and it gates *shipping* rather than *measuring*. Measuring is fine
regardless.

- **Email Fraunhofer IIS and ask for commercial terms.** A two-week-old research release with 89
  downloads is likely to welcome the ask, and Fraunhofer institutes routinely grant separate
  commercial licenses. This is the clean outcome.
- **Absent that, CC BY-NC's bar is use "primarily intended for or directed toward commercial
  advantage or private monetary compensation."** The app currently has no StoreKit, no IAP, and no
  subscription code. A good-faith non-commercial reading is available — that is a judgment call, not
  a technical one. If it is taken: attribution is required, a fine-tune is Adapted Material and
  inherits NC (so the tuned weights would be NC on HF too), and the model has to come out before any
  paid tier ships.

## 6. What each outcome means

| core guarded | read | next |
|---|---|---|
| **> 72%** | beats the tuned Granite incumbent *stock* | Swift `GPTNeoX.swift` port + device memory measurement + settle the license. The 4 GB tier's open problem is solved. |
| **55–72%** | clears the substrate floor, below the incumbent | Only interesting as a fine-tune base — and it would have to beat tuned Granite *after* training. Weigh against the fact that Granite is Apache 2.0 and already tuned. |
| **< 55%** | below the floor | Write it up like [`BUEBLE_LM_EVAL.md`](BUEBLE_LM_EVAL.md) and close it. A fourth confirmation that German-benchmark scores do not predict this task. |
| **no bare `OK`** | the BübleLM mode | Stop at Phase 2. Cost: ten minutes. |

Whatever the number, it gets a row in [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md) — the negative
results in this directory have been worth as much as the positive ones.

## 7. Honest caveats on this plan

- **The 2,048 window caps the upside even in the best case.** It is enough for single-sentence
  grammar correction and not enough for conversation, stories, or paper study. A win here buys a
  better 4 GB *correction* tier, not a general 4 GB tutor. Worth knowing before the Swift port is
  costed.
- **~640 MB of KV at full context on top of ~1.7 GB of weights** is tight against the ~3.4 GB an iOS
  app actually gets. The Mac reading is a proxy; confirm on a real 4 GB device via
  `MemoryBudget.footprintMB` before believing the tier assignment
  ([`MLXModel+Descriptors.swift:140-156`](../german-ai-flashcards/Models/MLXModel+Descriptors.swift#L140-L156)).
- **"Matching 7B models in German" is a model-card claim** measured on the EleutherAI harness. This
  bench exists because that class of claim has disagreed with the app task every previous time.
