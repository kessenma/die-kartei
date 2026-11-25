# Teacher generation — the fix

Why two retrains failed to beat a model trained on 758 rows, and what has to change before
generating another corpus.

Companion to [`training-v3.md`](training-v3.md) (the v3 run),
[`training-v2.md`](training-v2.md) §2.6 (the verdict-balance discovery), and
[`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md).

---

## 1. The finding

**v1 beats v2 and v3 on the metric that matters, using 10× less correction data.**

| | correction rows | teacher | core suite (guarded) |
|---|---|---|---|
| **v1** | **758** | **Claude Sonnet** (via Claude Code subagents) | **54/60 (90%)** |
| v2 | 9,791 | `gemma-4-26B-A4B-it` | 42/60 (70%) |
| v3 | 14,045 | `gemma-4-26B-A4B-it`, verdict-rebalanced | 46/60 (77%) |
| stock (untuned) | — | — | 48/60 (80%) |

v3 is statistically indistinguishable from the **untuned** model on the core suite
(+4/−6, exact McNemar p = 0.75). Two rounds of data work bought nothing there.

## 2. It is the data's *shape*, not its volume or its verdict balance

v3 fixed verdict balance (44% → 62% fix, per-phenomenon) and gained only 4 points. Measuring what
each teacher actually produced explains why:

| measure | v1 / Sonnet | v2+v3 / gemma-26B | what the eval needs |
|---|---|---|---|
| `sep` — fix is a **pure word reorder** (same words, moved) rather than prefix mechanics | **0%** | **26%** | 0% |
| `refl` — fix **changes reflexive case** (`mich`→`mir`), the hard case | **65%** | **12%** | **50%** of eval error items |
| `refl` — fix merely **inserts** a reflexive (`add sich`), the trivial case | 35% | **62%** | — |

A quarter of the `sep` slice is word-order drill mislabelled as separable verbs. Seven of eight
reflexive examples teach the trivial case when half the eval tests the hard one. **More of that data
cannot teach the skill being measured**, which is why `dawo` gained exactly 0 points from a 14-point
fix-share increase — that lever was already exhausted.

Where v3's missing 8 points sit:

```
refl  11/15 → 8/15   -3    12% hard-case training vs 50% hard-case eval
vmp   15/15 → 13/15  -2
dawo  14/15 → 12/15  -2    unmoved by verdict rebalancing
sep   14/15 → 13/15  -1    26% of training rows mislabelled
```

## 3. It is a capability limit, not a prompting gap

This was the hopeful hypothesis and it is wrong. The generation prompt
(`scripts/build_gen_jobs.py:151`) already asks for exactly the right thing:

```python
"sep":  "trennbares Verb falsch getrennt (Präfix nicht abgetrennt im Hauptsatz,
         oder fälschlich getrennt im Nebensatz)"       # prefix mechanics, explicitly
"refl": "fehlendes oder falsches Reflexivpronomen (auch Akkusativ statt Dativ)"
                                                       # the hard case, by name
```

The teacher was asked for accusative-instead-of-dative reflexives **by name** and produced them 12%
of the time. No prompt rewrite recovers that.

**The control that isolates it:** in the same run, with the same teacher, the *conversation* prompt
demanded modal particles, a different opening every time, and varied question words — and that slice
**worked**, lifting modal particles 4–5× (v1 2.82 → v3 11.74 per 100 tokens). One teacher, one run,
one slice succeeded and one failed. The failure is specific to *constructing subtle grammatical
errors on demand*, which is a reasoning task, not a fluency task.

Plausible mechanism: `gemma-4-26B-A4B-it` is a **Mixture-of-Experts with ~4B active parameters per
token**. §1.3 of `training-v2.md` chose it over the dense 31B for throughput, on the stated
assumption of "comparable quality." That assumption holds for generating fluent dialogue. The
measurements above say it does not hold for hard-grammar construction.

## 4. What does not need to change

Two things are working and should be carried forward untouched:

- **The conversation slice.** It produced the naturalness gains, and v3 shows those are
  independent of grammar: between v2 and v3 only the correction slice changed, grammar moved +4,
  and naturalness barely moved. **Grammar and naturalness live in different slices and do not trade
  against each other** — the "more natural but worse at grammar" framing was two independent
  changes made at once.
- **The mix-in.** §2.3 measured it: removing it cost 7 points of core and doubled the miss rate.

## 5. Candidate teachers

| teacher | how | cost | notes |
|---|---|---|---|
| **Claude Sonnet** | Claude Code subagents; `scripts/extract_batch.py` already parses the transcript into JSONL | tokens, no GPU, no API key | the only teacher with a measured 54/60 attached |
| **`google/gemma-4-31B-it`** | RunPod, QAT `w4a16-ct` build ≈ 23.3 GB, fits L40S (~$0.79/hr) or A40 ($0.44/hr) | ~$1–3 | **dense**, ~8× the active params/token of the 26B-A4B. Same family — your own rule is "base multilingual substrate sets the ceiling," and Gemma beat Qwen/Llama/Mistral on German at every size tested |
| **`Qwen/Qwen3.8-27B`** | RunPod; bf16 ≈ 54 GB (A100 80GB) or the FP8 build ≈ 27 GB (A40/L40S) | ~$0.50–1.50 | released 2026-08-14. **Dense**, 64 layers × 5120 hidden, **vocab 248,320**. See the split verdict below. |
| **`swiss-ai/Apertus-70B-Instruct-2509`** | RunPod; bf16 ≈ 140 GB (2×80 GB) — see §5a for the quantized traps | ~$3–6 | **dense**, 80 layers × 64 heads, Apache 2.0, German-speaking consortium (EPFL/ETH/CSCS). The only untested candidate that clears every filter this project applies. **⚠️ use the `2509` v1.0 build, NOT v1.5** — see §5a |
| another family (Llama / Mistral large) | RunPod | — | ⚠️ likely a downgrade for German on this project's own evidence |

### 5a. Apertus-70B — the pick-the-right-repo problem (surveyed 2026-08-17, not yet run)

Apertus is the first candidate since gemma-4-31B to clear every filter this project applies, and the
first one where the *repo selection* is the hard part. Three things to get right before spending.

**1. Use v1.0 (`2509`), not v1.5.** They are different architectures:

| | `Apertus-70B-Instruct-2509` (v1.0) | `Apertus-v1.5-70B` |
|---|---|---|
| `model_type` | `apertus` | **`apertus1p5`** |
| modality | text | **multimodal** (`image-text-to-text`) |
| transformers | standard release | **custom branch, upstreaming in progress** |
| HF gating | open | **`gated: auto`** (needs token + accepted terms) |
| mlx-lm 0.31.3 | ✅ `apertus.py` implements it | ❌ no `apertus1p5` support |

The standing rule — *check `transformers` can load it on a small download before renting* — would
have caught this, but only after paying for the pod. Checking `config.json` via the HF API costs
nothing and catches it first.

**2. The quantized builds each carry a known trap.** bf16 70B is ~140 GB, so the temptation is a
pre-quant:

| build | size | verdict |
|---|---|---|
| `RedHatAI/Apertus-70B-Instruct-2509-quantized.w4a16` | ~40 GB | ⚠️ **`compressed-tensors` dequantizes on load** — this is exactly what OOM'd a 48 GB A40 with gemma-4-31B's QAT build (§ bakeoff README). Do not assume it fits a 48 GB card |
| FP8 dynamic | ~70 GB | ⚠️ needs **Ada sm_89+**. A40 is Ampere — no FP8. L40S (48 GB) is Ada but too small for 70B; realistically H100 |
| `unsloth/...-GGUF` Q4 | ~40 GB | ⚠️ llama.cpp path, not the batched `transformers` path `generate_bulk.py` uses. Would need a separate harness |
| **bf16, 2×A100 80 GB** | 140 GB | ✅ the only path that reuses the existing batched generator unchanged |

**3. Volume budget.** 70B bf16 (140 GB) does not share a 150 GB volume with gemma-4-31B (62.5 GB).
Free the other cache first: `rm -rf /workspace/hf/hub/models--google--gemma-4-31B-it`.

**Why it is still worth ~$1 to bake off.** Every prior "add a second teacher" argument died on
measurement, and the Qwen post-mortem (§6d) explains why corpus statistics cannot settle it. Apertus
differs from Qwen on the one axis that plausibly matters: it was *pretrained for* German by a
German-speaking consortium rather than being incidentally multilingual, on 15T tokens with 40%
non-English. A supporting signal from the on-device work: Apertus tokenizes German at **1.70
tokens/word, identical to gemma-4-E4B** (131k vocab), so the Granite tokenizer-inefficiency failure
mode (49k vocab, ~1.9 tok/word) does not apply to this family.

**Protocol — unchanged from the 2026-08-14 bake-off so results are comparable.** Same 50 stratified
`refl`+`sep` jobs, same prompt, `scripts/check_hard_case_share.py`. Bar: match gemma-31B's 100% /
0% / 3.8%. **Kill if** either shape gate fails, or no-ops exceed ~20% (Qwen's 39% was the
disqualifier).

**Order of operations.** This is step 5 of [`DATA_GAP_PLAN.md`](DATA_GAP_PLAN.md) §5, deliberately
*after* the v4 eval and the gemma-31B tail generation. A second teacher is only justified by a
phenomenon that stays stuck **after** being well-fed; right now nothing is well-fed enough to make
that claim, and the thin tail is the cheaper explanation.

### On Qwen3.8-27B specifically

> ✅ **RESOLVED — see §6d.** Measured 2026-08-15: passes both shape gates (refl 84%, sep 0%) but
> 39% no-ops, and a 2026-08-17 control showed its lexical contribution is indistinguishable from
> resampling gemma. **Fallback teacher only.** The pre-registered reasoning below is kept because
> it predicted the outcome correctly on the "against" side.

Two facts argue for testing it, and one argues against. Worth stating both rather than deciding
from reputation.

**For:**
- It is **dense**, so the diagnosed failure mode (≈4B active params in the 26B-A4B MoE) does not
  apply — all 27B participate per token.
- Its **vocabulary is 248,320**, essentially Gemma-class. This matters: the Granite finding
  (`training-v2.md` §3.8) was that a 49k BPE vocab needs ~1.9× the tokens per German word and
  plausibly caps capability. The Qwen3 generation tested here did not have a vocab this large.

**Against — this project's own measurements of the Qwen family on German:**

```
Qwen3 8B         58% core guarded, misses ~48% of real errors  (below stock 4B-class Gemma)
Qwen3 4B         52% core, misses 61%
tuned Qwen3-4B (62%)  <  STOCK Gemma E4B (72%)
```

Qwen showed a specific **knowledge-deficit profile** on German: it misses real errors rather than
inventing them. The standing decision rule is *"base multilingual substrate sets the ceiling —
generic 'supports 100+ languages' marketing ≠ measured grammar-correction quality."*

**But that prior is two generations old and predates the vocabulary change.** A prior is not a
measurement, and the bake-off in §6 costs well under $1. Measure it.

## 6. The gate: bake off before generating at scale

**Do not generate a full corpus before measuring the teacher on the metric that failed.** Run the
same ~50 stratified `refl`+`sep` jobs through each candidate and score the *shape*, not the pass
rate — every one of the bad v2 rows passed LanguageTool, spaCy, and the composition gate.

### Acceptance criteria

| measure | target | gemma-26B (failed) | v1/Sonnet (reference) |
|---|---|---|---|
| `refl` case-change share | **≥ 60%** | 12% ❌ | 65% ✅ |
| `sep` pure-reorder share | **≤ 5%** | 26% ❌ | 0% ✅ |
| verdict fix share (per phenomenon) | 65–75% | 20–59% ❌ | 100%* |
| LanguageTool + spaCy validation | unchanged | ✅ | ✅ |

\* v1 kept OK examples in a separate `verdict` bucket rather than mixing them into phenomenon rows.

### The detectors

Both are cheap and belong in `scripts/check_batch_composition.py` as hard gates:

```python
# sep: a fix that is a pure reorder teaches word order, not prefix mechanics
pure_reorder = sorted(toks(row["student"])) == sorted(toks(row["fix"]))

# refl: does the fix change the reflexive's CASE, or merely insert one?
REFL = {"mich","mir","dich","dir","sich","uns","euch"}
s, f = set(toks(row["student"])) & REFL, set(toks(row["fix"])) & REFL
case_change = bool(s and f and s != f)
insert_only = bool(not s and f)
```

**This is the third time a gate that checks "is the data valid?" has missed "is the data the right
shape?"** — §1.5b (a repair regex destroyed every fix row while the pass rate went *up*), §2.6
(verdict balance), and now hard-case share. Validity and usefulness are different questions and
need different gates.

## 6b. BAKE-OFF RESULTS (2026-08-14) — measured, not predicted

Same 50 stratified `refl`+`sep` jobs, same prompt (the enhanced one with worked examples and the
self-check instruction), scored by `scripts/check_hard_case_share.py`.

| teacher | refl case-change | sep pure-reorder | no-op rows | verdict |
|---|---|---|---|---|
| **Claude Sonnet** (subagents) | **100%** | **0%** | 0% | ✅ PASS |
| **`google/gemma-4-31B-it`** (dense) | **100%** ¹ | **0%** ¹ | 18% ² | ✅ **PASS — viable bulk teacher** |
| `gemma-4-26B-A4B-it` (MoE, v2/v3) | 12% | 26% | 0% | ❌ FAIL |
| `Qwen/Qwen3.8-27B` (dense) | 84% | 0% | **39%** | ⚠️ PASSES both gates, poor yield — fallback only, see §6d |

¹ of *live* rows (excluding no-ops). ² `student == fix`, removable with a one-line filter.

**gemma-4-31B is the bulk answer.** Every non-degenerate row it produced was correctly shaped,
matching Sonnet. Filter `student.strip() == fix.strip()` and accept ~20% yield loss.

**The two failure modes are not equally dangerous, and this is the durable lesson:**

```
31B no-op      LOUD.   student == fix. Trivially detectable, costs yield, nothing bad ships.
26B reorder    SILENT. Fluent, plausible, correctly labelled, teaches the wrong skill.
                       Cost: two training runs before anyone noticed.
```

Prefer a teacher that fails loudly over one that fails quietly, even at worse yield.

**Dense vs MoE is confirmed as the cause.** Same family, same prompt, same task:
**12% → 100%** going from ~4B active params (26B-A4B) to dense 31B. `training-v2.md` §1.3 chose the
MoE for throughput on the stated assumption of "comparable quality" — that holds for fluent dialogue
and does not hold for constructing subtle grammatical errors, which is a reasoning task.

### 6c. The existing v2 corpus is partly salvageable — do NOT regenerate all of it

Shape-testing the other slices of the gemma-26B corpus:

| slice | measure | 26B | usable? |
|---|---|---|---|
| `vmp` (3,989 fix rows) | fix changes the preposition | **98%** | ✅ keep |
| `dawo` (1,918 fix rows) | fix introduces a da-/wo-compound | **90%** | ✅ keep |
| `refl` (1,714) | case-change | 12% | ❌ replace |
| `sep` (379) | morphological | 74%, and 26% true reorders | ❌ replace |

**5,907 existing rows need no regeneration.** The 26B is fine at *mechanically simple* error types
(swap a preposition, collapse `auf es` → `darauf`) and fails only where the error requires judgment
about which subtle thing is wrong. That is a coherent capability boundary, not general incompetence.

### 6d. Qwen3.8-27B — MEASURED (2026-08-15), and the trap that nearly produced a false negative

Released 2026-08-14. `model_type: qwen3_5`, **dense**, 64 layers × 5120, **vocab 248,320** (Gemma-class,
unlike the 49k that hobbled Granite on German). `transformers` 5.15.0 loads it without
`trust_remote_code` issues — the architecture-support risk did not materialise.

**Result: passes both shape gates, disqualified on yield.** Pilots at
`data/bakeoff/qwen38_pilot.jsonl` (55 rows) and `qwen38_refl.jsonl` (56 rows), scored with
`scripts/check_hard_case_share.py`:

```
refl case-change   84%   (gate >= 60%)  PASS      vs gemma-31B 100%
sep pure-reorder    0%   (gate <=  5%)  PASS      vs gemma-31B   0%
no-op rows         39%                            vs gemma-31B 3.8%
malformed          3/31 (~10%, "fix changes no reflexive")  vs gemma-31B 0
```

39% no-ops means ~1.6× the rows for the same usable yield. On a $5 bulk run that is ~$8 — not a real
constraint, which is why the yield argument alone was never decisive. **The decisive measurement was
the diversity control** (2026-08-17), which tested the only reason to want a second teacher:

```
vocab Jaccard, n=44 samples, refl only, 200 trials
  gemma vs gemma  (SAME teacher, different samples)   0.249   [0.187-0.314]   <- the control
  gemma vs qwen                                       0.203   [0.164-0.256]
  gemma-bulk vs gemma-pilot (different runs/dates)    0.258

novel-vocabulary rate of a 44-row sample vs ~800 gemma refl rows
  a fresh GEMMA sample   13.8%   (300 draws, range 6.9-21.1%)
  the QWEN sample        14.5%   <- inside gemma's own resampling range
```

**Qwen's lexical contribution is indistinguishable from running gemma longer**, and gemma's
vocabulary is nowhere near exhausted (44 rows → 162 types; 800 rows → 963, still adding ~272 new
types per 400 rows). At matched level, gemma also writes the *more* complex sentences — at C1, 9.7
words and 0.57 commas/sentence against Qwen's 6.5 and **0.00**. Qwen matches on lexical
sophistication and lags on syntax.

⚠️ **The methodological trap here, worth more than the result:** the first pass measured
gemma-vs-Qwen Jaccard at 0.264, controlled for the job-mix confound, and concluded "genuine teacher
personality." That was wrong — with no same-teacher control, it was measuring temperature-0.9
sampling noise. **Any claim that two teachers differ requires a same-teacher baseline at matched
sample size.** Corpus statistics cannot detect a teacher ceiling anyway: a phenomenon a teacher
never constructs leaves no lexical trace. Only a trained student's eval can.

**The trap, which cost ~$0.15 and nearly produced a wrong conclusion:** Qwen3.x chat templates
default to thinking mode. `apply_chat_template` emits

```
system: Reasoning effort is set to xhigh. Please think carefully through the task...
assistant: <think>\n
```

and the model spends the entire `max_new_tokens` budget reasoning, emitting **zero** parseable JSON.
It looks exactly like a capability failure. **Always pass `enable_thinking=False`** — which
`scripts/run_baseline_eval.py` has done all along; the bake-off script simply didn't carry it over.
Fixed in `runpod/bakeoff/generate_hardcase.py`, which now tries the kwarg and falls back on
`TypeError` for templates that don't accept it.

**How the prior held up.** This project had consistently found Qwen weak on German (Qwen3 8B 58%
core, misses ~48% of real errors; tuned Qwen3-4B 62% < **stock** Gemma E4B 72%), with a
knowledge-deficit profile — but that prior was two generations old and predated the vocabulary
change, so it was explicitly *not* treated as decisive. It turned out to be directionally right for
the wrong reason: the 248k vocab did close the gap on shape quality (84% is a clear pass), and Qwen
failed instead on **yield** and on contributing nothing gemma could not. Keep the rule that a stale
prior does not substitute for measurement — it cost ~$1 to check and produced a cleaner answer than
the prior would have.

---

## 7. Plan

Ordered so that money is only spent after the cheap signal comes back.

| phase | what | cost | gate to pass |
|---|---|---|---|
| **0** | Sonnet bake-off: ~50 hard-case `refl`+`sep` rows via subagents, score shape | tokens | §6 criteria |
| **0b** | *(optional, parallel)* gemma-4-31B bake-off: same 50 jobs on RunPod | ~$0.40 | §6 criteria |
| **1** | Whichever teacher(s) clear: generate ~2,000 hard-case correction rows | tokens and/or ~$2 | §6 criteria on the full batch |
| **2** | Repack: new hard-case rows + v1's 758 Sonnet rows + v2's conversation slice + mix-in, correction share ≈ 50% | $0 | composition gate |
| **3** | Train E4B, ~4 h A40 | ~$2.50 | — |
| **4** | Score **core first**, then ext + holdout, all `--app-guard` | $0 | **core > 54/60** |

### On combining two teachers' output

Combine on **measured shape, not provenance**. If both clear §6, mixing adds lexical diversity and
is a win. If one does not, including it reintroduces exactly the dilution that produced v2 — a
corpus where 88% of reflexive examples teach the easy case. Score each teacher's batch separately,
then decide the mix; never concatenate first and measure after.

### Why phase 0 exists at all

Sonnet generation costs no infrastructure and is the proven path. If it clears the gate, the GPU is
optional — the deficit is **qualitative** (hard cases), not quantitative. You already have 14,045
correction rows; what is missing is ~2,000 of the *right kind*. The gemma-4-31B run is worth doing
if you want a self-hosted pipeline that does not depend on Claude, which is a legitimate goal on its
own, but it is not on the critical path to beating 54/60.

## 8. Open

*Status as of 2026-08-17. Current generation targets live in [`DATA_GAP_PLAN.md`](DATA_GAP_PLAN.md).*

- ✅ **`sep` volume** — resolved in v4: **984 rows** @ 70% fix (was 471), reorder-mislabel at 2%.
  ⚠️ But the *generation prompt* still under-produces separable-verb errors (379 `fix` vs 1,605 `ok`
  at source). Fix the prompt before any new `sep` request or the skew returns.
- ✅ **`relpron`** — resolved in v4: **390 rows** @ 70% fix (was zero).
- ⏸️ **`dawo` shape analysis** — still not done. It did not respond to verdict rebalancing and has
  never had the shape audit `refl` and `sep` got. At 3,070 rows it is the second-largest slice, so a
  shape problem here would be expensive.
- 🆕 **Distribution, not coverage, is now the problem.** v4 covers all 14 phenomena but `vmp`+`dawo`
  are 66% of the correction slice while `imperativ` has 133 rows — 45:1. See
  [`DATA_GAP_PLAN.md`](DATA_GAP_PLAN.md) §1.
- 🆕 **`aux` is `ok`-starved.** `ok_available: 47, ok_kept: 47` — the packer consumed every available
  `ok` row and still landed at 77.2% fix, the only phenomenon that missed the 70% target. New `aux`
  requests must ask for `ok` rows specifically.
