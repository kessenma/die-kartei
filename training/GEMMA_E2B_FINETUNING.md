# Gemma 4 E2B Fine-Tuning — rescuing the low/mid tier

Working log for the attempt to make **older/smaller iPhones (6–8 GB tier)** a first-class
target instead of a downgrade. Companion to:

- [`PLAN.md`](PLAN.md) — the overall fine-tune plan and phase tracker (E2B work is Phase 7 there)
- [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md) — the single source of truth for eval numbers
- [`ARTICLE.md`](ARTICLE.md) — the write-up; §"Round two" and §"The floor" are the sections this doc revises

**Status (2026-07-22): the low/mid tier problem is solved — by a scoring bug, not by training.**
The tuned E2B is shippable after all. Details below.

---

## The question

E2B was benched as a failure: core 65% → 68%, but **false corrections 34% → 59%** — a runaway
over-corrector. `MODEL_SCOREBOARD.md` recorded "DO NOT SHIP tuned — partial capacity cliff" and
the tier table fell back to **stock E2B**. The question this doc opened with: can more/different
training data, or a gentler recipe, push E2B over the bar?

Answer: **that was the wrong question.** E2B never needed more training.

---

## The finding: 18 of the 19 "false corrections" were echoes

Running the saved E2B responses through a decomposition of *how* each false correction fails:

| Model | false corrections | byte-identical echo | genuine bad rewrite |
|---|---|---|---|
| E2B stock | 11/32 | **11** | 0 |
| **E2B tuned** | **19/32** | **18** | **1** |
| E4B stock | 11/32 | 9 | 2 |
| E4B tuned | 7/32 | 5 | 2 |
| Apple Intelligence | 32/32 | 27 | 5 |

An "echo" is the failure mode `ARTICLE.md` already described anecdotally — the model emits
`FIX: <the student's sentence, verbatim>` plus a confabulated reason. The tuned E2B's *only*
genuinely wrong rewrite in the entire 121-item suite is:

```
sep-c3   in : Kannst du bitte das Fenster zumachen?
         fix: Kannst du bitte das Fenster zuschlagen?      ← "close" → "slam"
```

That single item is the whole of its real over-correction problem. The other 18 are a
verbatim restatement of the input.

### …and the app already discards echoes

`ConversationPrompts.parseCorrection` has compared the FIX line against the student's original
since before any of this training work, and returns "clean" when they match. **The app has never
shown the user an echoed correction.** The eval harness simply didn't model that step, so every
false-correction rate on the scoreboard measured the raw model rather than the shipped behaviour.

The 59% was real as a statement about the checkpoint, and misleading as a statement about the app.

---

## Re-scored the way the app actually behaves

Same saved generations, no re-inference; the guard is a pure post-process that can only turn a
spurious `FIX` into `OK`, never the reverse. Verified across **10 models × 121 items: zero items
regressed.**

| Model | core | ext | false-corr | miss |
|---|---|---|---|---|
| E2B stock | 65% → **73%** | 75% → **85%** | 34% → **0%** | 28% (unchanged) |
| **E2B tuned** | 68% → **83%** | 70% → **85%** | 59% → **3%** | **19%** (unchanged) |
| E4B stock | 72% → **80%** | 87% → **93%** | 34% → **6%** | 16% |
| **E4B tuned (shipped)** | 85% → **90%** | 90% → **93%** | 22% → **6%** | 9% |
| Gemma 3 1B stock | 58% (unchanged) | 59% | 0% | 55% |
| Qwen3-4B tuned | 62% → 65% | 64% → 66% | 16% → 6% | 45% |
| Apple Intelligence | 42% → 60% | 52% → 79% | 100% → 16% | 35% |
| Ministral 8B | 52% → 68% | 69% → 87% | 84% → 19% | 23% |
| Aya Expanse 8B | 57% → 72% | 64% → 89% | 100% → 25% | 12% |

Miss rate is untouched by construction — the guard only ever fires on a sentence the model
declined to change.

### What this does to the E2B decision

| | core | false-corr | miss |
|---|---|---|---|
| stock E2B (what ships today) | 73% | 0% | 28% |
| **tuned E2B** | **83%** | 3% | **19%** |

The tuned model wins by **+10 points of core accuracy and 9 points of miss rate**, for a cost of
one bad correction in 32. It clears the project's ship bar (core ≥ 80%, false-corr ≤ 25%) — which
stock E2B does not. **The fine-tune should ship for the 6–8 GB tier.**

The "capacity cliff at ~2B" story in `ARTICLE.md` does not survive this. What the 2B actually
learned was the FIX *format* — including the habit of using it to say "no change needed" — while
the knowledge gains (miss 28% → 19%, reflexives 8 → 12) were real. That is a formatting failure
with a two-line fix, not a capacity ceiling.

Gemma 3 1B is unaffected (0 echoes, 0% FC both ways), so the 1B collapse remains a genuine
capacity result. The cliff is real; E2B was just never on it.

---

## Track status

Options as originally scoped, with outcomes.

| | Idea | Status | Result |
|---|---|---|---|
| **A2** | Kill echo-fixes in the decoder | ✅ **done** | **The answer.** +15 pts core, FC 59% → 3% on tuned E2B; every model improved; 0 regressions |
| **B1** | Gemma 3 4B as a better small base | ❌ **refuted** | Best variant (QAT) 50% core raw / 73% guarded — ties *stock* E2B, loses to tuned E2B by 10 pts. Real knowledge failures (dawo 3/15, evasive rewrites), not a scoring artifact |
| **A1** | LoRA α-scaling sweep | ⏸ deprioritised | Was the hedge against "the tune was too hot". With the tune now winning at α=1, this is optimisation, not rescue. Needs a ~10 GB fp16 base download |
| **A3** | Verdict logit bias | 🔄 **inverted, now interesting** | Was meant to *suppress* FIX. With FC at 3% the binding constraint is the 19% miss rate — the guard is a safety net that makes biasing *toward* FIX cheap |
| **A4** | Cascade verdict/correction | ⏸ unnecessary | Motivated by the over-correction that turned out to be cosmetic |
| **C1–C3** | Gentler SFT / data remix / DPO | ⏸ not needed for shipping | C3 (DPO) is now a precision instrument for a 2-item target: `sep-c3` and the sep regression |

### B1 detail — why Gemma 3 4B lost

Predicted ≥70% on the reasoning that 4B dense > 2B effective and Gemma 3 1B already scored 58%.
Both 4-bit builds were measured, because the 1B on the scoreboard is QAT and comparing it to a
naive quant would have been unfair:

| Gemma 3 4B build | disk | core raw | core guarded | false-corr (core, raw → guarded) |
|---|---|---|---|---|
| `gemma-3-4b-it-4bit` (naive) | 2.5 GB | 26/60 (43%) | 37/60 (62%) | 16/16 → 5/16 |
| `gemma-3-4b-it-qat-4bit` | 2.9 GB | 30/60 (50%) | 44/60 (73%) | 16/16 → 2/16 |
| *stock E2B (reference)* | 3.3 GB | 39/60 (65%) | 44/60 (73%) | — |
| ***tuned E2B (reference)*** | 3.3 GB | 41/60 (68%) | **50/60 (83%)** | — |

Two things worth keeping: **QAT is worth ~7 raw points** over a naive 4-bit quant of the same
model (a sizeable effect for a free swap), and Gemma 3 4B is *another* 100%-false-correction
model on the core suite before the guard — the echo failure is close to universal outside the
E4B tune.

But the ceiling is knowledge, and it is genuinely lower. Post-guard failures are substantive:

- `dawo` 3/15 — the da-/wo-compound area E2B handles better
- evasive rewrites, the exact failure the dataset was built to remove:
  `Ich wasche mich die Hände` → *"Ich wasche meine Hände"* (dodges the dative reflexive);
  `Ich kann das teure Auto nicht leisten` → *"…nicht bezahlen"* (swaps the verb rather than adding `mir`)
- over-correction of correct German on *meaning* grounds: `gern` → `gerne`, `wohnen` → `leben`

Consistent with the scoreboard's existing rule — **the E-series' German substrate beats raw
parameter count within the Gemma family.**

---

## Memory: what it actually costs, and the trap in fixing it

Measured with `mlx_lm` on Apple silicon (`mx.get_peak_memory()`), 2026-07-22:

| | disk | resident weights | peak, normal turn | peak, very long context |
|---|---|---|---|---|
| **E2B tutor** | 3.4 GB | 2.60 GB | **2.71 GB** | 3.42 GB |
| E4B tutor (hero) | 4.9 GB | 4.20 GB | 4.32 GB | 4.99 GB |

Sanity check: E4B peaks at ~5.0 GB and runs fine on an 11 GB iPhone 17 Pro (8 GB app budget).

**E2B fits a 6 GB iPhone.** Against the ~3.4 GB budget such a device gets: 2.71 + 0.25 reserve
≈ 2.96 GB, ~450 MB spare. The app's old estimate said otherwise only because
`requiredMB = approximateSizeMB × 1.15` scales the *download* size — 3.4 GB on disk, of which only
2.6 GB is resident weights — and so predicted 3.79 GB against a measured 2.71 GB. That 40%
over-estimate was the sole thing excluding 6 GB devices.

**The trap:** `MemorySaver.isActive` in automatic mode was `MemoryBudget.isOverBudget(model)`. Make
the budget more accurate and E2B stops being over budget on a 6 GB phone — which switches *off* the
KV-cache cap, freeing the 3.42 GB long-context peak to happen on the device with the least room to
absorb it. A more accurate budget would have produced a less safe app.

Fixed by separating the two questions: `fits()` still asks whether a model belongs here,
`hasSlimHeadroom()` asks whether it has room to spare (>75% of budget), and the governors engage on
either. A 6 GB phone runs E2B with the KV cache capped; an 8 GB phone runs it ungoverned; the hero
stays ungoverned on 11 GB, matching observed behaviour.

⚠️ **These are Mac readings used as an iOS proxy** — same MLX and unified memory, different
runtime. Nobody has yet run this on a 6 GB device. Confirm `MemoryBudget.footprintMB` on real
hardware before treating the 6 GB tier as supported.

## Changes made

**App** — `german-ai-flashcards/Services/ConversationPrompts.swift`
The existing guard had two defects, both now fixed:

1. It compared with `.diacriticInsensitive`, which silently swallowed **real umlaut corrections**
   (`Madchen` → `Mädchen`, `schon` → `schön`) as if they were echoes. For a German tutor those
   are exactly the corrections a learner needs. Now diacritic-*sensitive*.
2. It required an exact match otherwise, so an echo that merely added a period leaked through as
   a spurious correction. Now normalises wrapping quotes, whitespace and trailing `.!?…`.

Extracted as `echoNormalized(_:)`. Builds clean (`build_sim`, 2026-07-22).

**Eval harness** — `scripts/run_baseline_eval.py`, `scripts/behavior_metrics.py`
Added `apply_app_guard()` plus an `--app-guard` flag to both, mirroring the Swift normaliser, so
the eval can report app-equivalent numbers. Raw generations are still saved unmodified, so any
run can be re-scored either way and the historical raw numbers stay reproducible.

```bash
# app-equivalent behavioural metrics for any saved run
.venv/bin/python scripts/behavior_metrics.py --app-guard \
    results/finetuned_gemma4-e2b-german-tutor-4bit.json \
    results/finetuned-extra_gemma4-e2b-german-tutor-4bit.json
```

---

## Caveats

- **Two scales now exist.** Raw scores measure the checkpoint; guarded scores measure the app.
  Both are legitimate; mixing them is not. The ship bar (core ≥ 80%) was set on the raw scale and
  should be restated on the guarded one before it's used to judge anything new.
- **Not re-generated, re-scored.** The guard is a deterministic post-process over saved responses,
  so no inference was repeated. This is sound, but it does mean nothing was re-verified against
  fresh sampling.
- **Quantisation asymmetry persists** (carried over from `MODEL_SCOREBOARD.md`): E2B base is a
  community quant, the tune is a local `mlx_vlm` quant.
- **Not yet confirmed on-device.** Numbers are Mac-side MLX.
- **The guard hides confabulated WHY notes rather than curing them.** The model still privately
  produces *"'aufstehen' is inseparable"*; the app just never renders it, because the note is
  dropped along with the echoed fix. Any future surface that shows a WHY without the fix would
  re-expose this.
- **`sep` still regressed** (11 → 8) in the tune. Untouched by any of this and still worth a
  targeted data wave.

---

## Shipped (2026-07-22)

- [x] **Published**: [`kessenma/gemma4-e2b-german-tutor-4bit`](https://huggingface.co/kessenma/gemma4-e2b-german-tutor-4bit)
      — public, Apache 2.0, one `model.safetensors`. The card leads with the echo-filter
      requirement, since the raw model reads as 59% false corrections without it, and ships the
      filter as copy-pasteable code.
- [x] **App case** `gemma4_E2B_german` wired through config, descriptors, theme, logo and promo
      link. Builds clean.
- [x] **Budget switched to measured peaks**, with `hasSlimHeadroom` keeping the governors on where
      the fit is tight.

### Retrained on the v2 corpus (2026-07-29) — a trade, not an upgrade

~40k teacher-generated examples vs v1's ~1,400, scored on the frozen v2 holdout, all guarded:

| | core | false-corr | miss |
|---|---|---|---|
| E2B v1 (shipped) | 69/82 (84%) | 12% | **10%** |
| E2B v2 | 69/82 (84%) | **4%** | 20% |

Core is flat; the model traded 3× fewer false corrections for 2× more missed errors. It became
more *cautious*, not more capable — which is a defensible ship for a tutor but is not the
improvement 28× the data was supposed to buy. **E4B v2, on the same corpus, went 85% → 91% with
false corrections eliminated (8% → 0%)**, so the corpus is fine; this is the capacity gradient
showing up again one tier down. E2B v1 stays shipped pending a call on the trade.
Full workup: [`training-v2.md`](training-v2.md) §2.

## Next

1. **Verify on device** — the one thing standing between this and a supported 6 GB tier. Load E2B,
   watch `MemoryBudget.footprintMB` through a long conversation, confirm the KV cap holds it under
   the budget. The Mac proxy says it fits; only hardware settles it.
2. **Restate the ship criteria on the guarded scale**, and re-report `MODEL_SCOREBOARD.md` with
   both columns.
3. **Revisit the recommendation ordering** — `recommendationRank` gates on `minimumRAMGB`, a fixed
   tier, while `MemoryBudget.fits()` knows the real answer for the device in hand. On a phone where
   the hero doesn't fit but E2B does, the picker still leads with the hero. Also
   `germanQualityScore` looks stale against the scoreboard (Qwen3-8B scores 5 on 58% core).
4. **A3 inverted** — with FC at 3%, bias the first token toward `FIX` and see how far the 19% miss
   rate falls before false corrections become real ones.
5. **A small DPO run (C3)** aimed at the two remaining defects: `sep-c3` and the sep regression.
6. ~~**Revise `ARTICLE.md`**~~ **Done 2026-07-30.** And the pattern repeated: a *second* scoring
   artifact turned up in the same guard, this time flattering stock Gemma 3 1B. `apply_app_guard`
   implemented the echo rule but not `parseCorrection`'s `hasPrefix("OK\n")` clause, so a reply
   that opens `OK` and then appends a real `FIX:` was credited on both branches. That model emits
   exactly that shape on nearly every input, and the app displays none of it. **Stock Gemma 3 1B
   is 34% guarded with a 100% miss rate, not 58%/55%** — it had been the recorded 4 GB incumbent
   for weeks. Same lesson as the E2B echo decomposition, opposite direction: *implement the app's
   parse contract in full, or the bench measures a model the user never meets.*
7. ~~**A 3-bit E2B** would drop peak to ~2 GB and open the 4–6 GB tier.~~ **Tested 2026-07-23 —
   dead end, see below.**

---

## 3-bit quantization — architecturally blocked by PLE (2026-07-23)

The hope: 3-bit-quantize the tuned E2B (or E4B) to reach the 4–6 GB tier. It doesn't work, and the
reason is specific to Gemma 4.

Converted the fp16 tuned E2B with `mlx_vlm convert --quant-predicate` (the PLE-safe mixed presets
the PLAN reference-linked). Two attempts, both revealing:

| recipe | bpw | disk | peak RAM | core guarded | miss |
|---|---|---|---|---|---|
| `mixed_3_6` | **6.47** | 3.9 GB | — | (bigger than 4-bit — abandoned) | |
| `mixed_3_4` | **5.29** | 3.2 GB | 2.5 GB | **63%** | 30% |
| *4-bit (shipped)* | ~5.2 | 3.4 GB | 2.7 GB | **83%** | 19% |

**The PLE architecture that makes Gemma 4 memory-efficient at 4-bit also blocks 3-bit.** The
per-layer embeddings are a large fraction of the weights and must stay high-bit or the model breaks
(the documented naive-4-bit garbage). Protecting them means the average bpw can't drop much:
`mixed_3_6` protected so much it came out *bigger* than 4-bit; `mixed_3_4` reached only 5.29 bpw /
3.2 GB — a **6% size cut** and a **~200 MB peak-RAM cut** (2.7 → 2.5 GB, still over a 4 GB phone's
~2.0 GB budget). The shipped "4-bit" is already ~5.2 bpw effective for exactly this reason; there is
no real 3-bit tier beneath it.

And it isn't free: core accuracy fell **83% → 63% guarded**, miss rate rose **19% → 30%** — the
tune's whole value gone, dropping it *below stock E2B* (73%). Sanity-gen showed the degradation
directly: it corrupted *"Ich"→"I"* and missed the reflexive error in *"Ich freue auf…"* that the
4-bit catches.

**E4B 3-bit is pointless for the same reason** and wasn't converted: identical PLE wall, and even a
generous 6% shrink (4.9 → ~4.6 GB) can't reach a 6 GB phone's ~3.4 GB budget. Naive `--q-bits 3`
would shrink further but reintroduces the PLE garbage.

**Conclusion: quantization can't take Gemma 4 below its 4-bit footprint.** Reaching devices smaller
than the 6 GB tier needs a genuinely smaller *model*, not a smaller quant — and the
[budget-base search](BUDGET_BASE_SEARCH.md) found nothing that beats stock Gemma 3 1B there. The
3-bit model was deleted (worse than 4-bit on every axis); eval results kept at
`results/threebit*_gemma4-e2b-german-tutor-3bit.json`.

---

## Cactus CQ4 runtime — quality regression vs MLX 4-bit (2026-07-26)

Cross-runtime check for the [Cactus runtime spike](german-tutor-cactus-retrain-plan.md): does
Cactus's **CQ4** quant of the *same* fp16 E2B tune preserve the German knowledge the MLX 4-bit build
ships? **No — it loses ~18 pts of core accuracy and more than doubles the miss rate.**

Method (apples-to-apples by construction). Both artifacts are 4-bit-class quants of the identical
fp16 merged tutor `kessenma/gemma4-e2b-german-tutor` — **not** an MLX→Cactus requantization; each is
built straight from the fp16 source. Responses generated through `cactus serve` (OpenAI endpoint,
`--no-cloud-handoff`, greedy, Metal) with **byte-identical prompts** — `scripts/gen_cactus_responses.py`
imports `build_messages` from the MLX harness, so only the runtime/quant differs. Scored with the same
rubric (`--responses --app-guard`); the MLX row was re-scored from saved responses with that same
scorer (reproduces the scoreboard's 83 / 85 / 3 / 19 exactly).

| Metric (app-guarded) | MLX 4-bit (shipped) | Cactus CQ4 | Δ |
|---|---|---|---|
| Core (n=60) | 50/60 (**83%**) | 39/60 (**65%**) | **−18 pts** |
| Extension (n=61) | 52/61 (**85%**) | 44/61 (**72%**) | −13 pts |
| False-correction (n=32) | 1/32 (3%) | 0/32 (0%) | ~tie |
| Miss / mis-fix (n=69) | 13/69 (**19%**) | 30/69 (**43%**) | **+24 pts** |
| Format errors | 0 | 0 | — |
| Raw core / ext (no guard) | 68% / 70% | 58% / 67% | — |

Guarded per-phenomenon core (MLX → Cactus): **vmp 15→11, refl 14→9**, sep 11→9, dawo 10→10. The two
areas the tune most improved — verb+preposition and reflexives — are exactly where CQ4 gives it back.

**It's a genuine knowledge regression, not a scoring artifact.** 18 error items the MLX build fixes,
CQ4 answers bare `OK`: textbook cases like `Ich freue auf das Wochenende` (missing reflexive `mich`),
`Ich warte für den Bus` (`für`→`auf`), `Er ärgert sich auf …` (`auf`→`über`), `Er anruft mich`
(separable `ruft…an`). It also emits corrupted fixes — `Ich ausgehe …` → *"Ich gehe … mit Freunden
**ausgehen**"* (verb doubled) — the degenerate-generation signature of over-aggressive quantization
that Phase D of the Cactus plan warned about.

**Same shape as the rejected MLX 3-bit above.** CQ4's 65% core / 43% miss sits at/below the
PLE-blocked MLX 3-bit build (63% core / 30% miss) despite being nominally 4-bit. The mechanism is the
same one this whole doc is about: Gemma 4's per-layer embeddings are quantization-sensitive; MLX's
shipped "4-bit" protects them (~5.2 bpw effective, via `--quant-predicate`), and Cactus's CQ4 evidently
does not to the same degree — so a nominally-4-bit build behaves like a 3-bit one. Cactus `--bits` is
integer-only and its convert surface exposes no per-layer/embedding precision control, so there is no
obvious CQ equivalent of the PLE-sparing MLX preset.

**Verdict for the runtime spike:** on the current tune, Cactus CQ4 is worse than MLX on *both* axes —
larger on disk (3.9 GB vs 3.3 GB, from bundled vision/audio towers) **and** materially weaker on German
grammar. A `--components` decoder-only build could address the size but not the quality (that's a
weight-quant question, not a graph question). Reproduce: start `cactus serve` per
[german-tutor-cactus-retrain-plan.md](german-tutor-cactus-retrain-plan.md) §3.2, then
`.venv/bin/python scripts/gen_cactus_responses.py`, then score the two `results/cactus_e2b_cq4_*.responses.json`
files with `run_baseline_eval.py --responses --app-guard` / `behavior_metrics.py --app-guard`.

---

> **2026-08-19 update:** two corpus-v4 retrains (full corpus, and core-8 @ 0.80 fix "v5") both
> failed to displace the shipped v1 — grammar ties (p = 0.73) but miss rate 23–33% vs v1's ~10%.
> E2B stays on v1; the capacity analysis and next levers are in
> [`training-v3.md`](training-v3.md) §9.2 and the `e2b-capacity-dilution` memory.
