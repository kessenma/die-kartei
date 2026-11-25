# Data v2 + the 1B distillation track — plan

> ⚠️ **HISTORICAL — superseded.** This is the *plan*; what actually happened is in
> [`training-v2.md`](training-v2.md) (v2 build + mix-in ablation) and [`training-v3.md`](training-v3.md)
> (v3 rebalance, v4 teacher replacement). The 1B distillation track ended in a **negative result** —
> the same dataset gave E4B +13 pts and Gemma-3-1B **−26**; see the capacity-cliff entry in
> [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md). Start at [`CLAUDE.md`](CLAUDE.md). Kept for
> provenance — do not plan against it.

Three goals, in dependency order:

1. **Rebuild the training set** — clean the existing 1,447, scale it with a Gemma-4 teacher.
2. **Retrain E2B/E4B** on it, confirm no regression against [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md), republish.
3. **Distill a 1B** that beats the 4 GB entry tier — the one thing [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md)
   concluded was unimprovable.

> **Tier correction (2026-07-28).** The scoreboard's "4–6 GB → Gemma 3 1B stock" row reads as though
> 6 GB devices ship the 58% model. They don't. `MLXModel+Descriptors.swift:150-152` sets the real
> floors: **E2B requires 6 GB, E4B requires 8 GB, Gemma 3 1B is 4 GB only.** So a 6 GB phone already
> runs the 83% E2B tune. The 1B track's addressable population is **4 GB devices alone**
> (iPhone XR / 11 / SE 2–3 / 12 mini class) — see "What the 1B is actually for" below.

Companion to [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md), [`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md),
[`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md), [`RUNTIME_EXPLORATION.md`](RUNTIME_EXPLORATION.md).

---

## Audit findings (2026-07-28) — what's actually wrong with the data

Measured against `data/packed/train.jsonl` (1,447) and `data/eval/*.json` (121), not assumed.

### 1. The eval suites are clean. Don't rebuild them.

| check | result |
|---|---|
| exact eval sentences appearing in train | **0 / 121** |
| near-duplicates (Jaccard ≥ 0.7 on tokens) | **2 / 121** |

Both near-dups are trivial `expect_ok` variants (`"Ich denke oft daran."` vs
`"Ja, ich denke oft daran."`). `validate_data.py` already hard-rejects eval overlap at generation
time and it demonstrably worked. **Every number on the scoreboard is trustworthy.** No leakage
cleanup needed.

### 2. …but v0/v1 have quietly become *dev* sets, not test sets.

20+ models have been scored against `grammar_eval_v0` / `v1_extra`, and ship/no-ship decisions
(E2B tune, 3-bit, Cactus, LiteRT-LM, five budget bases) were made from those numbers. Every one of
those decisions fed information back into the pipeline. That is textbook test-set contamination by
iteration — not leakage, *selection*.

This does not invalidate past comparisons (all models saw the same suites, so the *ranking* holds),
but the absolute numbers are now optimistic, and the next claim published to HF should not rest on
them alone.

**Action: mint `grammar_eval_v2_holdout.json` (~80 items), score it once per candidate, never
iterate against it.** Keep v0/v1 as the dev suites they've become — they're well-built and the
whole scoreboard is denominated in them.

### 3. The real defect: 35% of training is machine-translated Alpaca.

507 of 1,447 rows (`mixin`) come from `alpaca-gpt4-deutsch` + `sharegpt-deutsch`. It is 504/507
German-dominant, so it isn't *wrong* — but it is **translationese**, and it is off-task:

```
U: Funktionieren Sie als Softwareingenieur. Erstellen Sie ein Beispiel für ein Mermaid-JS-Diagramm.
U: Implementieren Sie graphql-Mutation, um die CSV-Datei zu lesen … mit `pothos-graphql` und `fastify`
U: Wie hoch wird der geschätzte Wert der Aktien des Unternehmens am Ende des Jahres sein?
U: Analysieren Sie diese politische Karikatur und erklären Sie, was sie aussagt.
```

`Funktionieren Sie als Softwareingenieur` is a botched machine rendering of "Act as a software
engineer" — it means roughly *"Do you function as a software engineer."* This is the register the
model is being taught 35% of the time.

**For E4B this is harmless** anti-forgetting regularization — it has the capacity to absorb it.
**For a 1B student it is actively harmful**: it spends a third of a tiny gradient budget on GraphQL
and stock valuations, in unnatural German. It also works directly against goal 3 (human voice).

### 4. This reframes the "capacity cliff" — the 1B experiment was confounded.

The scoreboard's rule reads as a law of nature:

> Below ~4B-effective params the model learns the FIX *behavior* without the knowledge to aim it.

The Gemma-3-1B run that established it (58% → 32% core, FC 0% → 56%) varied **two** things at once:

- capacity (1B), **and**
- data (799 correction examples + 507 rows of translated GraphQL).

E4B only needed the tune to teach *aiming*, because it already knew German. The 1B needed the tune
to teach *knowledge and aiming*, from 799 examples, while 35% of the signal pulled elsewhere.

**The capacity-cliff conclusion is probably still right, but it has never actually been tested** —
no one has run a 1B on 30k+ on-task examples. That is precisely what distillation is. The prior is
against a full recovery to 83%; the experiment is cheap enough to be worth settling.

### 5. The labels ChatGPT recommends already exist — `pack_dataset.py` throws them away.

`data/generated/*.valid.jsonl` already carries `task`, `phenomenon`, `level`, `formality`, and
`meta.{verb,prep,aux,subtype}`. `pack_dataset.py:main()` renders those into prompts and then emits
bare `{"messages": [...]}`.

**Action: one-line change — keep a `meta` key on every packed row.** That gets ~80% of the
"metadata schema" for free and makes rebalancing, grouped splitting, and per-slice eval possible
without regenerating anything.

### 6. `val.jsonl` (29 rows, random 2%) is not a validation set.

It's a random slice of the same pool, so it is near-duplicate-contaminated with train by
construction, and 29 rows is too few to compare checkpoints. It works for loss monitoring, nothing
more.

**Action: grouped validation split (~5%), grouped by `template_family` / `meta.verb` so the same
verb-preposition family never straddles train and val.**

### 7. DeepL is the wrong tool for the revalidation.

`deepl_gloss_check.py` checks the **verb+preposition lexicon glosses** (`data/verb_praep_table.json`),
not training examples — it round-trips DE→EN and flags glosses with no content-word overlap. That's
a good lexicon check and worth re-running when the lexicon grows, but it cannot judge naturalness or
correctness of a tutor response.

The actual quality gate is and remains `validate_data.py` (LanguageTool zero-match on the gold side
+ spaCy structural presence + eval-overlap rejection). At 30–50k scale, add a **teacher-as-judge**
pass on top. See Phase 1.

---

## The distillation decision

Four things get called "distillation." Ranked for *this* failure mode:

| method | what transfers | cost | verdict here |
|---|---|---|---|
| **A. Sequence-level** (SFT on teacher text) | phrasing, format, tone, correction behavior | lowest | ✅ **do first** — tokenizer-agnostic, and it is the clean test of "capacity or data?" |
| **B. On-policy / GKD** (student generates, teacher scores *the student's own* tokens) | error recovery, calibration, verdict discipline | medium | ✅ **do second** — precisely targets over-correction |
| **C. Offline top-k logit KD** (dump teacher top-k, train student on it) | dark knowledge | medium | ◽ skip unless B is too slow — B subsumes it |
| **D. DPO / preference** | naturalness | medium | ◽ **goal 3 only**, not grammar. Phase 5 |

**Recommendation: A → B.** Not C, not "start with logits."

Why **B** specifically, and not just more SFT: the 1B's measured failure is *confabulated
over-correction* — it invents rules (`"aufstehen is inseparable"`) to justify a FIX it shouldn't have
made. Sequence-level SFT only ever shows the student the teacher's good answers; it never shows the
student **its own** bad ones. On-policy KD makes the student generate, then penalises the KL between
its distribution and the teacher's *on the tokens the student actually produced*. That is the direct
mechanism for killing a confabulation habit, and it's why it's worth the extra complexity — but only
after A tells you the ceiling.

### Logit distillation is viable — tokenizer verified

The usual blocker for B/C is vocabulary mismatch. Checked it directly:

| pair | tokenizer.json | verdict |
|---|---|---|
| Gemma 4 31B ↔ 26B-A4B ↔ E4B ↔ E2B | identical file (`oid cc8d3a0ce…`, 32,169,626 B) | byte-identical, zero work |
| Gemma 4 ↔ **Gemma 3 1B** | different files, both `vocab_size=262144` | **compatible in practice** |

Measured on the actual vocabularies:

```
tokens with identical id in both : 255,938 / 262,144  (97.63%)
mismatched                       : 6,206
  ├─ special/unused token shaped : 6,206   (<unusedNNN>, <start_of_turn>, …)
  └─ REAL text tokens            : 0
alphabetic / German-shaped tokens: 137,246 misaligned: 0
```

**Every mismatch is a control token. Not one real text token moves.** Gemma 3 1B additionally has
19 tokens Gemma 4 lacks (`<start_of_turn>`, `<end_of_turn>`, image sentinels, unused). So teacher
logits can be consumed by the student directly, given a ~24-entry remap of the chat control tokens
and masking of the 19 orphans. This is a config detail, not a research project.

### Student base: Gemma 3 1B. Not a new family.

The instinct to switch base families should be resisted, on this project's own evidence:

- [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md) tested five non-Gemma sub-3B candidates.
  **None beat stock Gemma 3 1B (58%).** Granite 3.3 2B tied it at 2× the size; Llama 3.2 3B, Salamandra,
  BübleLM, SauerkrautLM all landed below the floor. The German-substrate ceiling is real.
- There is **no 1B-class Gemma 4** — the family is E2B / E4B / 12B / 26B-A4B / 31B. E2B is the floor.
- 3-bit E2B is closed (PLE blocks it, 83% → 63%).
- Switching families **forfeits the tokenizer alignment above**, which is the only reason logit
  distillation is cheap here.

> **⚠️ This argument was wrong, and switching families is what worked (2026-07-30).**
>
> The first bullet rests on the 58% anchor, which was a scoring artifact — stock Gemma 3 1B is
> **34%**. Granite was never "tying at 2× the size"; it was **beating the incumbent by 21 points**
> before any training. Staying in-family produced the 25% collapse; switching produced **72%**.
>
> The fourth bullet, however, came true exactly as written, just as a *cost paid later* rather
> than a reason not to switch: Granite's 49k BPE vocabulary shares nothing with Gemma's 262k
> SentencePiece, which is precisely what blocks Phase 4 (see the block notice below) and makes
> German cost ~1.9× the tokens. **The tokenizer objection was the right objection for the wrong
> conclusion** — it should have been priced as a known downstream cost, not used to rule the
> option out up front.

Gemma 3 1B is the only student that is simultaneously 1B-class, above the substrate floor, and
logit-compatible with the teacher. Keep Granite 3.3 2B parked as the non-Gemma fallback.

*Worth 10 minutes before Phase 3: check whether Gemma 4 E-series is still MatFormer-nested like
Gemma 3n. If it is, a sub-E2B slice may be extractable directly and would beat any distillation.*

### Teacher: `gemma-4-26B-A4B-it`, unmodified

MoE, 128 experts, ~4B active per token → far higher generation throughput than dense 31B at
comparable quality. That matters when the deliverable is 30–50k long-form examples.

**Do not fine-tune the teacher first.** ChatGPT recommended it; it's the most expensive step in the
plan and the least justified here:

- The 1,447 examples mostly teach **format**, which few-shot prompting plus `validate_data.py`
  already enforces — that exact pipeline (strong general model → hard validator) produced the
  current dataset.
- Fine-tuning a 31B on 1.4k rows risks degrading its German for a marginal format gain.
- It burns the biggest GPU bill before you've learned anything.

Instead: few-shot the stock 26B-A4B with validated exemplars drawn from the existing `.valid.jsonl`
files, and use the **shipped E4B tune as the style anchor**. Revisit teacher tuning only if the
validator rejection rate on teacher output exceeds ~25%.

Use dense **31B** for the judge/preference pass (Phase 5), where quality beats throughput.

---

## Phases

Each phase has a gate. Stop and reassess if a gate fails.

### Phase 0 — local, free (~half a day)

- `pack_dataset.py`: carry `meta` through to packed rows (finding 5).
- Grouped train/val split by `template_family` / `meta.verb` (finding 6).
- Build `grammar_eval_v2_holdout.json`, ~80 items, from phenomena in v0/v1 but new lexical material.
  Freeze it (finding 2).
- Re-run `deepl_gloss_check.py` on `verb_praep_table.json` — cheap, and the lexicon feeds generation.
- Score the **currently shipped** E2B and E4B on v2-holdout. This is the honest baseline the retrain
  must not regress against.
- **Build the naturalness bench and baseline the shipped models on it** (below).

**Gate:** shipped E4B on v2-holdout lands within ~5 pts of its v0 core (85% raw / 90% guarded). A much
lower number means v0/v1 overfitting is worse than assumed — valuable either way, but it changes the
targets.

#### Naturalness bench — build it *before* retraining, not after

"Slightly worse but more human-sounding" can't be judged today because nothing measures the second
half. Two small artifacts fix that, both scriptable, no native speaker and no GPU required:

**1. `data/eval/conversation_v0.json`** — ~50 frozen conversation prompts, not correction items:
A2/B1/B2 × du/Sie × Lena-mode and role-play × mundane / emotional / practical topics, plus a few
learner turns containing an English word or a transcription glitch. Small enough to hand-check.

**2. `scripts/naturalness_metrics.py`** — sits next to `behavior_metrics.py`, consumes the same
`*.responses.json` files, reports per model:

| metric | why it tracks "human" |
|---|---|
| opening variety | distinct first-3-token prefixes / n responses — catches `"Das ist interessant!"` on repeat |
| modal particle rate | `doch`, `mal`, `eigentlich`, `ja`, `eben`, `halt`, `schon` per 100 tokens — the clearest spoken-vs-textbook marker |
| follow-up question rate | share of replies ending in a question (the app's prompt asks for this — is it obeyed?) |
| encouragement repetition | top-5 most repeated 4-grams and their share |
| length distribution | mean + spread of sentences per reply; CEFR instructions ask for 1–3 |
| type-token ratio | lexical variety over the whole run |
| English leakage | share of replies containing English words (should be ~0 in conversation mode) |

**These are proxies.** They measure variety and register markers, which correlate with naturalness
but don't certify it — a model can game opening variety and still sound like a textbook. They are
reliable for **A/B and regression detection**, which is exactly the job here: same bench, same
prompts, old model vs new. Native-speaker review (Phase 5) is what turns proxies into a verdict, and
it gets spent on the anchor set, not on this.

Baseline the currently shipped E2B and E4B on it in Phase 0. That way the v2 retrain produces a
two-axis before/after, and the "is slightly worse grammar worth it?" question gets decided against
numbers you already trust.

### Phase 1 — synthetic data at scale (~$10–20)

Target **30–50k** examples, not millions. Distribution, weighted toward what the app does and away
from the current 35% translationese:

| slice | share | notes |
|---|---|---|
| grammar correction | 40% | keep the v0/v1 phenomenon taxonomy; add the *hard negatives* the FC metric punishes |
| conversation / role-play | 30% | currently only 93 rows — the most under-served slice |
| flashcards / structured JSON | 15% | currently 48 rows |
| malformed / mixed-language recovery | 10% | maps directly to the app's speech-transcription reality |
| native German instruction | 5% | **replaces the Alpaca mixin** — teacher-generated, not translated |

Every row keeps `{task, cefr, register, region, persona, topic, target_features, template_family,
source, generator}`. Two-stage gate: `validate_data.py` first (hard), then teacher-as-judge on a
sample for naturalness.

**Gate:** validator pass rate ≥ 75% and ≥ 25k rows survive. Below that, fix prompts before spending
GPU on training.

> **Status 2026-07-28: gate cleared, full run launched.** Four stratified smoke rounds took the pass
> rate 69% → **85%** and the empty-job rate 17.5% → **5%**, fixing five mechanical bugs (truncation,
> teacher-overrides-manifest, a duplicate-key JSON glitch, even turn counts, a missing validator
> route) plus a false positive in the HINT leak detector. Full run: **19,210 jobs → ~40,005
> projected valid, ~4 h, ~$5.96** on an A100 SXM 80 GB. Detail in
> [`training-v2.md`](training-v2.md) §1.4–1.6; runbook in
> [`runpod/gen_v2/README.md`](runpod/gen_v2/README.md).
>
> Two things learned here that generalise to Phases 3–5:
> - **Stratify smoke samples across every slice.** All five bugs were slice-specific; a random
>   sample reports one aggregate number and localises nothing.
> - **Size any generation manifest from measured *validated* yield, never from what the teacher is
>   asked for.** The gap is large and one-directional: `PER_JOB` sizing would have produced ~28k
>   valid items against a 40k target, discovered only after paying for the run.

### Phase 2 — retrain E2B + E4B (~$3)

Same QLoRA recipe (r=8, lr 2e-4, 2 epochs) on the v2 data. Score on v0, v1, **and** v2-holdout,
always with `--app-guard` (see below).

**Report both axes, then decide.** Deliberately *not* a single hard threshold — the interesting
outcome ("a bit weaker on grammar, clearly more human") is one a fixed gate would reject before
anyone looked at it. What Phase 2 produces is a table, not a verdict:

Phase 0 measured the "v1 shipped" column — those are real numbers now, not placeholders:

| | E4B v1 (shipped) | E4B v2 | E2B v1 (shipped) | E2B v2 |
|---|---|---|---|---|
| v0 core guarded | 90% | ? | 83% | ? |
| v0 false-corr guarded | 6% | ? | 3% | ? |
| **v2-holdout core guarded** | **85%** | ? | **84%** | ? |
| **v2-holdout false-corr** | **8%** | ? | **12%** | ? |
| v2-holdout miss | 12% | ? | 10% | ? |
| naturalness: modal particles | 2.82 | ? | 2.94 | ? |
| naturalness: repeat_4gram_share | 0.30 | ? | 0.26 | ? |
| naturalness: question_variety | 0.462 | ? | 0.400 | ? |

⚠️ **Judge Phase 2 on the v2 column.** E4B drops 91.5% (v0+v1 blended) → 85% on fresh material while
E2B holds 84% → 84%, so the two tunes are within a point of each other on anything they weren't
selected against. Setting the E4B target from its v0 number would be setting it against drift. Full
working in [`training-v2.md`](training-v2.md) §0.7.

Only two things are hard rules, because both are trust failures rather than quality trade-offs:

- **False corrections must not rise**, on v2: E4B ≤ 8%, E2B ≤ 12%, guarded. A tutor that "fixes"
  correct German is the one failure users don't forgive, and it's the metric that cratered on every
  small model measured. No naturalness gain buys an increase here.
- **No collapse:** v2 core guarded ≥ 80% for both. Below that the data got worse, full stop, and
  Phase 3 isn't worth starting.

Between those floors and the current numbers, it's a judgement call made *with the naturalness
table in hand* — which is the whole reason Phase 0 builds it first. Republish when you're happy with
the trade, not when a threshold clears.

#### Always quote the guarded number

The scoreboard's headline table measures **raw checkpoints**; the app applies an echo guard on top,
so the two disagree by a lot — and by *different* amounts per model, which is what makes mixing them
misleading:

| model | core raw → guarded | FC raw → guarded |
|---|---|---|
| E4B stock | 72% → 80% | 34% → 6% |
| **E4B tuned (shipped)** | 85% → **90%** | 22% → **6%** |
| **E2B tuned (shipped)** | 68% → **83%** | 59% → **3%** |

The guard is `ConversationPrompts.parseCorrection` (`ConversationPrompts.swift:144`): if the model's
`FIX:` line is identical to what the student said, it's discarded as clean rather than shown as a
correction. Small models echo the input under a `FIX:` header and confabulate a reason — **18 of
tuned E2B's 19 false corrections were exactly this**. `echoNormalized` folds quotes, whitespace,
case and trailing punctuation but is deliberately **diacritic-sensitive**, so `Madchen → Mädchen`
still counts as a real correction.

This is why E2B is shippable at all: raw, its 59% FC is disqualifying; guarded, it's 3%. E4B needs
the guard far less (22% → 6%) because it confabulates less to begin with. Both ship with it.
Reproduce either column with `--app-guard` on `run_baseline_eval.py` / `behavior_metrics.py`.

**For the 1B this matters more, not less** — the guard is precisely a patch for the failure mode a
1B has worst, so Phase 3/4 must report guarded numbers or the comparison is meaningless.

### Phase 3 — 1B sequence-level distillation (~$2)

Gemma 3 1B + the full v2 set (**no Alpaca mixin**), QLoRA. This is the cheap, decisive test of
finding 4.

**Gate / realistic targets:**

| outcome | core (guarded) | FC | read |
|---|---|---|---|
| 🎯 win | ≥ 70% | ≤ 15% | **beats stock 58% — 4 GB tier upgraded.** Ship it there |
| ◽ partial | 60–70% | ≤ 20% | real but marginal; Phase 4 decides |
| ❌ cliff confirmed | < 58% or FC > 30% | | capacity is genuinely the wall. Publish the negative result and stop |

> **⚠️ These thresholds are anchored to a number that was wrong.** Stock Gemma 3 1B is **34%
> guarded, not 58%** — the scorer credited `OK\nFIX:…` replies the app discards. Read the gate
> as: win ≥ 70%, cliff < 34%.

#### Phase 3 OUTCOME (2026-07-30)

Ran as specified on Gemma 3 1B, then extended to a base sweep when it failed.

| student | stock | tuned on v2 | read |
|---|---|---|---|
| Gemma 3 1B | 34% | **26%** | ❌ cliff confirmed — the same collapse as v1, 28× the data |
| **Granite 3.3 2B** | 55% | **72%** | 🎯 win on the corrected gate |

**Finding 4 is settled: data volume does not rescue a 1B.** 1,400 → 40,000 on-task examples
changed nothing about the direction of travel for Gemma 3 1B; it still gets worse. The capacity
cliff is real and is not a data-starvation artifact.

The tier is nonetheless upgraded, by switching bases rather than by scaling data. Granite 3.3 2B
absorbed the same corpus for +17 points. A LoRA rank test (r=8 → r=32) then confirmed the result
is not tuning-limited: 4× trainable params, val loss 0.89 → 0.71, benchmark +4/82, **McNemar
p = 0.42**. Full detail in §3 of [`training-v2.md`](training-v2.md).

**Track paused after Phase 3.** Open before shipping: peak RAM on a real 4 GB device, and the
`relpron` regression that hit E4B and Granite identically (6/6 → 4/6).

#### What the 1B is actually for — and what it is not

App-equivalent (guarded, i.e. how the app really behaves) numbers for reference:

| model | min device RAM | core guarded | FC guarded | measured peak |
|---|---|---|---|---|
| E4B tuned (hero) | 8 GB | **90%** | 6% | 4.33 GB |
| E2B tuned | 6 GB | **83%** | 3% | 2.71 GB |
| Gemma 3 1B stock | 4 GB | 58% | 0% | ~0.9 GB |

**A 70–75% 1B does not displace anything on a 6 GB+ device** — E2B's 83% dominates it outright.
The honest scope is narrower than "upgrade the budget tier":

1. **4 GB devices go 58% → 70–75%.** Real, but an old and shrinking population.
2. **Headroom on 6 GB devices.** E2B needs 2,710 + 250 MB against a ~3.4 GB budget, which is above
   `slimHeadroomFraction` (0.75) — so `MemorySaver` engages its KV-cache cap and E2B runs
   *governed* on exactly the devices that just barely fit it. A ~1 GB tutor runs ungoverned and
   leaves room for the CoreML image models to stay resident. (There is currently **no unload path
   in Swift** — `grep unload` over `*.swift` returns nothing — so this benefit is hypothetical until
   that's built.)
3. **The research result.** Settling capacity-vs-data on a 1B is publishable in its own right and
   directly extends [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md)'s negative finding.

If none of those three is worth ~$25 to you, **Phase 3 is the right place to stop** and the data-v2
work (Phases 0–2) still stands on its own — it improves the two models that serve almost every user.

### Phase 4 — on-policy KD (GKD), only if Phase 3 lands ≥ 60% (~$20–40)

Teacher (26B-A4B, w4a16) and student co-resident. Student samples on the correction prompts; loss =
SFT + reverse-KL against teacher logits on student-generated tokens, with the 24-token control
remap. Anneal the on-policy fraction 0 → 0.5.

**Gate:** +5 pts core *or* FC halved vs Phase 3. Otherwise stop — the remaining gap is capacity.

> **🚫 BLOCKED as written (2026-07-30) — this design assumes a Gemma student.**
>
> Token-level reverse-KL requires teacher and student to share a vocabulary. That held for the
> planned Gemma 3 1B student: Gemma 3 ↔ Gemma 4 match on 255,938 of 262,144 IDs, all mismatches
> being special tokens, which is what "the 24-token control remap" refers to. The student that
> actually won Phase 3 does not share it:
>
> | | vocab | tokenizer |
> |---|---|---|
> | Gemma 4 E4B (teacher) | 262,144 | SentencePiece |
> | Granite 3.3 2B (student) | 49,159 | byte-level BPE |
>
> There is no token-level distribution to take a KL against. Reviving this needs either a
> cross-tokenizer method (ULD-style optimal transport) or a sequence-level variant where the
> teacher scores whole student responses — a redesign, so **the ~$20–40 estimate no longer
> applies**.
>
> Phase 3 also weakened the motive: the rank test says Granite isn't training-limited, and its
> tokenizer needs ~1.9× the tokens for the same German sentence (`gelesen` → `ge|les|en`), which
> costs speed and context on the weakest hardware in the lineup regardless of how it's trained.
> **Not recommended.** Revisit if a small base with Gemma's vocabulary and Granite's body ratio
> appears.

### Phase 5 — human voice (goal 3), cheapest version first

Do this **last** and keep the native-speaker spend on evaluation, not generation:

1. 200–300 anchor prompts (A2/B1/B2 × du/Sie × DE/AT × mundane/emotional/technical), frozen.
2. Teacher generates 2–3 candidates each; **31B judges** the bulk.
3. Native speakers review only: the anchor set, judge disagreements, and a random QC sample.
4. DPO the student on the resulting pairs.

The scriptable half of this now lives in Phase 0 (`scripts/naturalness_metrics.py` +
`data/eval/conversation_v0.json`), so by the time you get here you already have proxy trend lines
across v1 → v2 → distilled models. Phase 5 is where native speakers convert those proxies into a
verdict — and where DPO acts on the result. Expand the anchor set beyond the ~50 Phase 0 prompts
before paying for review.

---

## GPUs — live RunPod inventory (2026-07-28, this account)

**No H100 is needed for any phase.** Prices below are community/secure per hour as listed.

| stage | pick | $/hr | est. hours | est. cost |
|---|---|---|---|---|
| Phase 1 generation (26B-A4B w4a16 + vLLM) | **L40S 48 GB** | 0.79 / 0.99 | 12–20 | **$10–16** |
| ↳ alternative, newer silicon | RTX 6000 Ada 48 GB | 0.74 / 0.84 | | |
| ↳ if running 31B dense bf16 | **RTX PRO 6000 Blackwell 96 GB** | **1.69** / 1.99 | | 96 GB for *less* than an H100 PCIe |
| Phase 2 E2B/E4B QLoRA | **RTX A6000 48 GB** | **0.33** / 0.53 | 3–5 | **~$2** |
| ↳ alternative | A40 48 GB | 0.35 / 0.44 | | |
| Phase 3 1B SFT | RTX A6000 48 GB | 0.33 | 2–4 | **~$1.50** |
| Phase 4 on-policy KD (teacher + student) | **A100 80 GB PCIe** | **1.19** / 1.39 | 10–20 | **$15–25** |
| ↳ more headroom | RTX PRO 6000 96 GB | 1.69 | | |
| Phase 5 judging (31B dense) | A100 80 GB | 1.19 | 4–8 | **$5–10** |

**Total for the whole program: ~$35–55**, plus rerun margin → budget **$100**.

Reference points if something forces a bigger box: H100 PCIe $1.99, H100 NVL 94 GB $2.59,
H100 SXM $2.69, H200 141 GB $3.59, B200 $5.98. MI300X 192 GB at $2.39 is the cheapest way to a
very large VRAM pool but costs ROCm debugging time.

Standouts worth remembering: **RTX A6000 at $0.33/hr** for anything ≤ 48 GB, and **RTX PRO 6000
Blackwell 96 GB at $1.69/hr** — more VRAM than an H100 for 15% less.

---

## Answering the two direct questions

**"Can training data be used for both training and testing?"** No — and you already do this
correctly. Your real structure is: `train.jsonl` = train, `grammar_eval_v0/v1` = held-out test
(0/121 leakage, verified). The gaps are (a) `val.jsonl` is a 29-row random slice rather than a
grouped validation set, and (b) v0/v1 have been iterated against enough to have become dev sets.
Phase 0 fixes both. You do **not** need separate HF repos — splits inside one `DatasetDict` are
fine, and the private holdout should simply live outside the training pipeline.

**"Which distillation process?"** Sequence-level first (Phase 3) because it's cheap and it settles
whether the 1B failure was capacity or data. Then on-policy KD (Phase 4) because it's the only
method that attacks over-correction directly. Skip offline top-k logit KD; keep DPO for the
naturalness goal. The tokenizer check above means you can move between them without changing base
models.
