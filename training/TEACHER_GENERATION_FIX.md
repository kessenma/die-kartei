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
| another family (Llama / Mistral large) | RunPod | — | ⚠️ likely a downgrade for German on this project's own evidence |

### On Qwen3.8-27B specifically

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
| `Qwen/Qwen3.8-27B` | — | — | — | ⏸️ not measured, see §6d |

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

### 6d. ⚠️ Qwen3.8-27B — unmeasured, and the trap that nearly produced a false negative

Released 2026-08-14. `model_type: qwen3_5`, **dense**, 64 layers × 5120, **vocab 248,320** (Gemma-class,
unlike the 49k that hobbled Granite on German). `transformers` 5.15.0 loads it without
`trust_remote_code` issues — the architecture-support risk did not materialise.

**It was not measured** because the session ended; it had loaded (30 GB at 8-bit) and was mid-run.

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

Prior worth weighing when it *is* measured: this project has consistently found Qwen weak on German
(Qwen3 8B 58% core and misses ~48% of real errors; tuned Qwen3-4B 62% < **stock** Gemma E4B 72%),
with a knowledge-deficit profile. But that prior is two generations old and predates the vocabulary
change.

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

- **`sep` volume at source** — only 379 `fix` rows were ever generated for separable verbs against
  1,605 `ok`, so even a correctly balanced slice is thin (471 rows).
- **`relpron` has zero training rows** in the v2 corpus and regressed on every model trained on it.
- **`dawo`** did not respond to verdict rebalancing; it needs the same shape analysis `refl` and
  `sep` got, and it has not been done.
