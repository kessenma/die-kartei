# Training v2 — worklog

Running log for the data-v2 + 1B-distillation track. **Plan, rationale and phase gates live in
[`DATA_V2_DISTILL_PLAN.md`](DATA_V2_DISTILL_PLAN.md)** — this file records what was actually run,
what it produced, and what changed as a result.

Companion to [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md) (single source of truth for scores),
[`PLAN.md`](PLAN.md) (the original v1 fine-tune), and the experiment writeups
[`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md) / [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md) /
[`RUNTIME_EXPLORATION.md`](RUNTIME_EXPLORATION.md).

---

## Phase 0 — local groundwork (2026-07-28)

No GPU, no API spend beyond a DeepL lexicon re-check. Goal: fix the data-plumbing defects and build
the two measurements the v2 retrain will be judged against, **before** generating anything.

### 0.1 Metadata passthrough — `scripts/pack_dataset.py` ✅

`data/generated/*.valid.jsonl` already carried `task`, `phenomenon`, `level`, `formality` and
`meta.{verb,prep,aux,subtype}`. `pack_dataset.py` rendered those into prompt strings and then wrote
bare `{"messages": [...]}`, discarding every label. Rebalancing, per-slice eval and leakage-safe
splitting all needed a regeneration to get them back.

Packed rows now carry a `meta` block:

```json
{"messages": [...],
 "meta": {"task": "correction", "phenomenon": "vmp", "level": "B1", "formality": "du",
          "source": "synthetic", "template_family": "vmp:verb:warten"}}
```

`template_family` is derived (`verb` → `prep` → `aux` → `subtype` → per-phenomenon fallback; scenario
for conversations, topic for flashcards). Coverage of the fine-grained keys: `verb` 368,
`prep` 138, `subtype` 116, `aux` 88 of 960 synthetic rows — the 245 `verdict` items carry empty
`meta` and fall back to a per-phenomenon bucket, which is coarse but safe (a coarser group can only
keep *more* related examples together).

`runpod/train_gemma4_e4b.py` updated in the same pass: `remove_columns=["messages"]` →
`remove_columns=ds["train"].column_names`, so the new column can't leak into the trainer as a stray
feature.

### 0.2 Grouped train/val split ✅

The old split was a random 2% row slice (29 rows). Two problems: too small to compare checkpoints,
and near-duplicate-contaminated with train **by construction** — the same verb family lands on both
sides, so val measures memorisation, not generalisation.

Now: whole `template_family` groups are assigned to one side, `--val-frac` default 0.02 → 0.05, with
an assert that no family straddles the split.

Measured, on the same 1,476-row pool:

| split | val corr. items | items with a ≥0.7 near-dup in train | max train↔val Jaccard |
|---|---|---|---|
| random rows (8 seeds) | 35–43 | **mean 2.0** | **1.0 in 5 of 8 seeds** |
| grouped (shipped) | 31 | **0** | **0.50** |

Five of eight random seeds put a *token-identical* sentence on both sides. That is now impossible.

New `data/packed/`: **1,403 train / 73 val**, 872 train families / 64 val families.

Also added `--no-mixin` + `--out-dir`. `data/packed-nomixin/` (912 train / 48 val) is the Phase 3
1B-student build — see 0.5.

### 0.3 `grammar_eval_v2_holdout.json` — frozen test suite ✅

v0/v1 never leaked (verified below), but 20+ models have been scored against them and ship decisions
made from the results, so they have become **dev** sets: rankings still hold, absolute numbers are
optimistic. v2 is the suite to quote in any new published claim.

**82 items** — 65 correction (24 `expect_ok`, 41 error) + 17 cloze, across all 12 phenomena from
v0 *and* v1, built from deliberately new lexical material (`zweifeln an`, `sich sehnen nach`,
`verzichten auf`, `sich erkundigen`, `wegwerfen`, `N-Deklination` on *Praktikant/Zeuge/Architekt*, …).

Verified clean:

| check | vs training data | vs v0/v1 |
|---|---|---|
| exact input overlap | **0 / 82** | **0 / 82** |
| near-dup (Jaccard ≥ 0.6) | **0 / 82** | **0 / 82** |

Also self-consistency-checked: every error item's `forbid_any` actually matches its own input, and no
item's `require_any` is already present in the input (this caught one malformed dawo item and five
mislabelled relpron/wechsel IDs, all fixed).

Bonus property: `validate_data.py:load_eval_texts()` globs `data/eval/*.json`, so v2 **auto-protects
itself** — the generator now hard-rejects any synthetic candidate that collides with it.

> **Rule: score each candidate on v2 once. Never iterate against it. Never generate from it.**

### 0.4 Naturalness bench ✅

The "slightly worse grammar but more human-sounding" trade was previously unanswerable because
nothing measured the second half. Two new artifacts, both free to run:

**`data/eval/conversation_v0.json`** — 50 frozen items in the app's *conversation* mode: 8 openers,
26 single-turn replies, 10 multi-turn, 6 edge cases (English word mixed in, transcription glitch,
one-word learner turn, very long learner turn). Spread over A2/B1/B2 × du/Sie × Lena and 11 role-play
scenarios, plus two deck-word items.

**`scripts/run_conversation_eval.py`** — builds the prompts by importing
`pack_dataset.conversation_system()`, so the bench can never silently drift from what the model was
trained on. Verified: the generated system prompt is byte-identical to the app's, and the hidden
`openerSeed` turn is in the right place. Greedy (`--temp 0`) by default — these proxies are sampling-
sensitive, so temperature must be held constant across anything being compared.

**`scripts/naturalness_metrics.py`** — reports, next to `behavior_metrics.py`:
`opening_variety`, `modal_particle_rate` (doch/mal/eigentlich/ja/eben/halt/schon/denn/wohl per 100
tokens), `followup_rate`, `question_variety`, `repeat_4gram_share`, `sentences_per_reply` (+stdev),
`mean_tokens_per_reply`, `type_token_ratio` (MSTTR-50, so a chattier model isn't penalised for
length), `english_leakage`. `--compare` prints a side-by-side delta table.

Smoke-tested against two synthetic fixtures with identical mean length (10.1 tokens/reply), one
deliberately robotic and one deliberately natural — every metric moved in the right direction:

| metric | robotic fixture | natural fixture | better |
|---|---|---|---|
| opening_variety | 0.05 | 0.50 | up |
| modal_particle_rate | 0.00 | 7.92 | up |
| question_variety | 0.053 | 0.227 | up |
| repeat_4gram_share | 1.00 | 0.10 | down |
| type_token_ratio | 0.24 | 0.86 | up |
| english_leakage | 0.05 | 0.00 | down |

⚠️ **These are proxies for variety and spoken register, not a naturalness certificate.** A model can
score well and still read like a textbook. They are reliable for A/B on a fixed bench, which is the
job; native review (Phase 5) is what turns them into a verdict. **Never tune against them directly.**

`behavior_metrics.py` also gained `--eval-file` so false-correction / miss rates can be computed on
v2 instead of the hardcoded v0+v1 pair.

### 0.5 The mix-in, quantified

507 of the 1,447 v1 training rows (35%) came from `alpaca-gpt4-deutsch` + `sharegpt-deutsch`.
504/507 are German-dominant, so it isn't wrong — it's **translationese and off-task**:

```
Funktionieren Sie als Softwareingenieur. Erstellen Sie ein Beispiel für ein Mermaid-JS-Diagramm.
Implementieren Sie graphql-Mutation, um die CSV-Datei zu lesen … mit `pothos-graphql` und `fastify`
Wie hoch wird der geschätzte Wert der Aktien des Unternehmens am Ende des Jahres sein?
```

`Funktionieren Sie als Softwareingenieur` is machine-rendered "Act as a software engineer" — it means
roughly *"Do you function as a software engineer."* That is the register the model sees 35% of the
time, which works directly against the human-voice goal.

Kept for the E2B/E4B retrain (a 4B-class model absorbs it as anti-forgetting regularisation);
**dropped for the 1B student**, where a third of a tiny gradient budget cannot go to GraphQL and
stock valuations. Hence `--no-mixin` and `data/packed-nomixin/`.

### 0.6 DeepL lexicon re-check ✅ — and a correction about what it's for

Re-ran `scripts/deepl_gloss_check.py` on the 268-entry `data/verb_praep_table.json`.
**54/268 flagged**, DeepL usage 5,628 / 1,000,000 chars lifetime.

Spot-reading all 54: they are **almost entirely paraphrase, not error**. The check flags when the
curated gloss and DeepL's round-trip share no content word, and two correct translations routinely
share none:

| entry | our gloss | DeepL | verdict |
|---|---|---|---|
| `sich beteiligen an` | to participate in | to take part in something | ✅ same |
| `sich konzentrieren auf` | to concentrate on | to focus on something | ✅ same |
| `beharren auf` | to persist in | to insist on something | ✅ same |
| `gewinnen an` | to gain in (importance) | to win someone over | ⚠️ weak *probe* (`an jemandem gewinnen`), gloss fine |

**The lexicon is clean; the check has near-zero precision as built.** Do not gate anything on it.

More importantly this confirms the scope correction from the plan: `deepl_gloss_check.py` validates
the **verb+preposition lexicon**, not training examples. "Re-validate the dataset with DeepL" was
never a thing this script did. The dataset gate is `validate_data.py` (LanguageTool zero-match on the
gold side + spaCy structural presence + eval-overlap rejection), and at 30–50k scale it gets a
teacher-as-judge pass on top (Phase 1).

### 0.7 Baselines of the shipped models ✅ — and the headline finding

Both shipped models, both new benches, all guarded. **This is the "before" column Phase 2 is judged
against.**

| | E4B tuned (shipped) | E2B tuned (shipped) |
|---|---|---|
| **v2-holdout core, guarded** | **70/82 = 85%** | **69/82 = 84%** |
| v2-holdout false-corr | 2/24 = **8%** | 3/24 = **12%** |
| v2-holdout miss | 5/41 = **12%** | 4/41 = **10%** |
| format errors | 0 | 0 |

Gate passed: E4B lands 85% on fresh material against 90% on v0, i.e. **5 points of dev-set drift**,
right at the tolerance the plan set.

#### The E4B/E2B gap mostly disappears on unseen material

Comparing each model against its own v0+v1 blended guarded score (the suites it was tuned and
selected on) versus the frozen v2 holdout:

| model | v0 guarded | v1-ext guarded | **blended v0+v1** | **v2 holdout** | drift |
|---|---|---|---|---|---|
| E4B tuned | 90% | 93% | **91.5%** | **85%** | **−6.5 pts** |
| E2B tuned | 83% | 85% | **84.0%** | **84%** | **0 pts** |

**E4B's advantage over E2B collapses from +7.5 points to +1 point.** E2B reproduces its number
exactly on material it has never been selected against; E4B does not.

The most likely reading is that some of E4B's measured lead was dev-set drift — it is the model whose
results drove the most iteration (it was the first tune, the hero, and the reference for every
later comparison), so it had the most opportunity to be selected on those suites. On genuinely fresh
material the two tunes are close to equivalent on grammar, and E2B is the *steadier* of the two.

**Caveat, stated plainly:** v2 is not a drop-in replacement for v0. It blends v0's four core
phenomena with v1's eight and uses deliberately unfamiliar verbs, so it is a somewhat harder and
differently-shaped suite. The v0+v1 blend above is the fairest available comparison, but a −6.5 vs
0 split across two models on the *same* new suite is not explainable by suite difficulty alone —
difficulty would move both.

**What this changes:**
- Phase 2's E4B target should be set against **85% on v2**, not 90% on v0.
- The 1B track's bar goes *up*, not down: the model it has to justify itself against is a 6 GB E2B
  that genuinely holds 84% on unseen material.
- Worth re-checking after the v2 retrain: if E4B's v2 number rises materially while E2B's holds,
  the drift reading is confirmed and the extra 4 GB is buying less than the scoreboard implies.

#### Naturalness baseline (50 items, greedy, `--temp 0`)

| metric | E4B tuned | E2B tuned | better |
|---|---|---|---|
| opening_variety | 0.70 | 0.70 | up |
| modal_particle_rate (/100 tok) | 2.82 | 2.94 | up |
| followup_rate | 0.78 | 0.80 | — |
| question_variety | 0.462 | 0.400 | up |
| top_opener_share | 0.231 | 0.325 | down |
| wh_question_share | 0.308 | 0.600 | — |
| repeat_4gram_share | 0.30 | 0.26 | down |
| sentences_per_reply | 2.00 | 2.06 | — |
| mean_tokens_per_reply | 11.3 | 11.6 | — |
| type_token_ratio (MSTTR-50) | 0.780 | 0.747 | up |
| **english_leakage** | **0.00** | **0.00** | down |

Both models obey the hard rules — zero English leakage, ~2 sentences per reply, ~80% of replies end
in a question, all as instructed. The weaknesses are the *soft* ones this bench exists to surface:

- **30% of replies reuse one of the top-5 4-grams**, and 30% of openings repeat.
- **Modal particles are thin** at ~2.8 per 100 tokens. This is the clearest spoken-register marker
  and the most obvious target for Phase 1's conversation slice.
- E4B leans on one question opener — `Woran…` accounts for 9 of its 39 questions.
- E4B asks mostly yes/no questions (wh-share 0.31) where E2B varies more (0.60). Yes/no questions
  are conversational dead ends; this is a concrete, fixable naturalness defect.

Two bugs in `naturalness_metrics.py` were found and fixed by looking at the raw questions rather than
trusting the first numbers — both would have made the baseline wrong:

1. `question_variety` bucketed everything not in a hand-written wh-list as `_other`. German yes/no
   questions are verb-initial, so they all collapsed into one bucket: reported 0.051, actual 0.462.
2. The wh-list omitted wo-compounds (`woran`, `wofür`, …), so `wh_question_share` read 0.051 when it
   is 0.308. Now matched structurally with the same pattern shape as `validate_data.py`'s `DAWO_RE`,
   unit-checked against `wir`/`wird`/`will`/`war` to confirm no false positives.

Both fixes re-verified against the synthetic robotic/natural fixtures, which still separate cleanly
(question_variety 0.053 vs 0.455; top_opener_share 1.00 vs 0.18).

#### One revision to the v2 suite, before it was frozen

The first E4B run surfaced three items where a *correct* answer could fail. Fixed before any number
above was recorded, and noted in the suite's `meta.revisions`:

| item | problem | fix |
|---|---|---|
| `v2-dawo-z1` | referent *die Prüfung* made `an sie` as valid as `daran` | neuter referent (*das Gewitter*), where only the da-compound is grammatical |
| `v2-artikel-e2` | *der Fenster* admitted both `das Fenster` and plural `die Fenster` | swapped to *Buch* — no plural reading |
| `v2-relpron-o1` | `feiert Jubiläum` vs `feiert sein Jubiläum` is a usage split, not an error | replaced with an unambiguous relative clause |

The other 11 E4B failures are genuine, and two are worth carrying into Phase 1 as training targets:
on `Mit was hast du das Paket geöffnet?` the model echoed the input and confabulated the rule
backwards (*"'Mit was' is correct; 'womit' is for things"*), and it flatly missed
`Ich hänge das Bild an der Wand` (Wechselpräposition, accusative required for the motion sense).

---

### 1.7 Packing at scale — two changes the v2 corpus forced

**Slice subsampling (`--slice-mix`).** Slices generate at wildly different yields, so the raw corpus
does not have the intended shape: the correction slice over-produced to 29,269 rows against a
16,002 target (yield tripled once fix rows stopped being destroyed) while flashcards came in at
6,852. Packing that as-is skews the corpus toward whatever generated most easily. `--slice-mix`
takes the target proportions, finds the binding slice, and scales everything to it — keeping as much
data as possible without inventing any.

**Invented focus areas are dropped (`clean_focus`).** The teacher produced **152 distinct**
`focus_areas` values that are not app `GrammarFocus` keys — `Wochenendpläne`, `Präteritum/Perfekt`,
`Wortschatz Freizeit`. They're topic labels, they have no steering hint, and rendering them raised
`KeyError` mid-pack. Filtered silently: the row is still good training data, it just carries no
focus steering.

**Verified end to end on a partial batch:** 2,251 packed rows, correct slice proportions, and the
nudgeMe path renders properly —

```
[user]      The student said: "Wir haben im Park spazieren gegangen."
[assistant] FIX: Wir sind im Park spazieren gegangen.
            WHY: 'Spazieren gehen' indicates movement, so use 'sein'.
            HINT: Benutzt man 'haben' oder 'sein' bei Bewegung?
```

### 1.8 Validation throughput

`validate_data.py` runs at **~0.5 rows/sec** — LanguageTool is an HTTP round-trip per row and spaCy
parses every gold sentence. That is 34 hours for a 61k corpus, which is not a thing you discover
politely. `scripts/validate_parallel.sh` splits the input across N workers (each with its own
LanguageTool JVM, ~1.5 GB) and merges the output; 6 workers on a 10-core/32 GB Mac gives ~3.5
rows/sec → **~5 hours**. Cross-chunk duplicates survive, which is harmless because
`pack_dataset.py` dedups globally anyway.

### 1.9 Phase 1 RESULT (2026-07-29)

**Validation: 45,097 valid / 16,057 rejected = 73% pass** on 61,154 generated rows.

**Composition gate: PASSED.**

| slice | validated rows |
|---|---|
| correction | 22,342 — **43.9% fix**, 4,008 HINTs (40.8% of fix rows) |
| conversation | 15,934 — **23/23 scenarios, 12/12 focus areas** |
| flashcards | 4,138 |
| native_instruction | 2,683 |

**Packed** (subsampled to the 40/30/15/10/5 target mix, grouped split, global dedup):

| build | train | val | HINT rows |
|---|---|---|---|
| `data/packed-v2` | **31,546** | 1,660 | 1,729 |
| `data/packed-v2-nomixin` | 20,505 | 1,080 | 1,675 |
| *(v1, shipped)* | *1,403* | *29* | *0* |

**v2 is 22.5× v1**, and the nudgeMe `HINT:` format now has 1,729 training examples where it
previously had none.

Two things to know when reading those numbers:

- **Dedup removed 6,002 rows.** Flashcards took the brunt: 4,138 available → 1,522 packed, because
  the dedup key is `topic + first card's germanWord` and the teacher reuses openers heavily across
  sets on the same topic. Not a bug — genuinely duplicated content — but it means the flashcard
  slice under-delivers against its 15% target and should be generated with more topic diversity
  next time.
- **`packed-v2` still contains 10,615 rows (33%) of the machine-translated Alpaca mix-in**, because
  `--mixin-frac` defaults to 0.35. See the open question below.

### 1.10 Open question: does the Alpaca mix-in still belong?

The plan called for the `native_instruction` slice to **replace** the translated mix-in, on the
grounds that `Funktionieren Sie als Softwareingenieur` is the register the model was learning 35%
of the time. But `pack_dataset.py` still blends it by default, so `packed-v2` is a third
translationese by row count — against only 1,325 native-German instruction rows.

The tension is real: the mix-in's *purpose* was anti-catastrophic-forgetting regularisation, and
1,325 rows is much thinner cover than 10,615. Resolving it by argument is guesswork; **Phase 2 can
just measure it** — train E2B on `packed-v2` and `packed-v2-nomixin` and compare on the v2 holdout
*and* the naturalness bench. That is one extra ~$1 training run and it settles a question this
project has been assuming an answer to since v1.

---

## Phase 2 — retrain and measure (2026-07-29)

Recipe changes from v1, both forced by the data and both justified:

| | v1 | v2 | why |
|---|---|---|---|
| epochs | 2 | **1** | 31,546 rows at 1 epoch = **10.9× v1's total step count**. Two would be 21.8× and invite overfitting at double the cost. |
| `MAX_SEQ_LEN` | 2048 | **1024** | measured p50 284 / p99 840 / **max 1000** — nothing truncates, attention cost halves |
| batch / accum | 2 / 4 | **8 / 1** | identical effective batch of 8, one forward/backward instead of four |

Training was clean: E2B ended train 0.981 / **eval 1.004**, with eval loss still declining and
tracking train loss almost exactly. No overfitting gap at 1 epoch — if anything there was headroom,
which validates cutting epochs rather than raising them.

⚠️ **Do not compare eval_loss across the two builds.** `packed-v2/val.jsonl` contains 33% translated
Alpaca rows; `packed-v2-nomixin/val.jsonl` contains none. The no-mixin run reported eval_loss 0.398
against the mixin run's 1.004 purely because its validation set is easier. Only the shared frozen
holdout is comparable.

### 2.1 E2B results — v2 holdout, all guarded

| model | core | false-corr | miss |
|---|---|---|---|
| **v1 shipped** | 69/82 = **84%** | 12% | **10%** |
| **v2 (with mix-in)** | 69/82 = **84%** | **4%** | 20% |
| v2 (no mix-in) | 63/82 = 77% | 4% | 39% |

**22× more data did not raise core accuracy.** 84% both times. What changed is disposition: the model
became markedly more cautious — false corrections 12% → **4%** (3× better on the metric the
scoreboard calls the trust-killer), missed errors 10% → **20%**.

Passes the Phase 2 gate (FC ≤ 12% ✅ at 4%; core ≥ 80% ✅ at 84%), but the core/miss trade is a
judgement call, not a free win.

A plausible mechanism: v1 was 56% correction data by task row; v2 is 47%. The corpus got *broader*
(conversation, recovery, native instruction) rather than deeper on grammar — so grammar held flat
while naturalness moved a lot. That is exactly what the slice mix predicts.

### 2.2 Naturalness — the axis that actually moved

| metric | v1 | v2 mix-in | better |
|---|---|---|---|
| **modal particles /100 tok** | 2.94 | **12.44** | up |
| repeat-4gram share | 0.26 | **0.12** | down |
| top-opener share | 0.325 | **0.158** | down |
| question variety | 0.400 | **0.474** | up |
| type-token ratio | 0.747 | **0.778** | up |
| sentences per reply | 2.06 | 1.44 | — |
| English leakage | 0.00 | 0.00 | — |

Modal particles **4.2×** — the single biggest defect Phase 0 identified, and the clearest
spoken-vs-textbook marker. Canned-phrase repetition halved; the one-opener tic broken.

Watch item: replies shortened 2.06 → 1.44 sentences. Still within the prompt's "one to three," but
worth a human read for terseness.

### 2.3 §1.10 ANSWERED — the mix-in earns its place, and my prediction was wrong

Phase 1 asserted the machine-translated Alpaca data was harmful, on the strength of
`Funktionieren Sie als Softwareingenieur` being the register the model saw 35% of the time.
**Measurement says the opposite:** removing it cost **7 points of core** (84% → 77%) and **doubled
the miss rate** (20% → 39%), while naturalness was statistically unchanged (12.12 vs 12.44
particles).

So it is not contributing register — it is contributing general language-modelling signal that keeps
grammar capability from narrowing under a task-heavy fine-tune. The comparison is clean: both builds
carry nearly identical task-row counts (20,931 vs 20,505), so the mix-in is the only real variable.

**Decision: keep the mix-in.** And note the shape of the error — an argument from a vivid example
(`Funktionieren Sie…`) lost to a measurement. Worth remembering next time a bad-looking sample
suggests a data slice should go.

### 2.4 E4B results — the headline

| model | core | false-corr | miss |
|---|---|---|---|
| E4B v1 (shipped) | 70/82 (85%) | 8% | **12%** |
| **E4B v2** | **75/82 (91%)** | **0%** | 15% |

**+6 points core, false corrections eliminated.** Unlike E2B, E4B converted the extra data into
actual capability rather than caution. Both Phase 2 gates clear with room (FC ≤ 8% → 0%;
core ≥ 85% → 91%).

Per-phenomenon, the gains land exactly where v1 was weak:

| phenomenon | v1 | v2 | |
|---|---|---|---|
| **dawo** | 6/10 | **9/10** | +3 — the app's hardest target area |
| adjend | 4/6 | 6/6 | +2 |
| k2 | 3/4 | 4/4 | +1 |
| refl | 8/10 | 9/10 | +1 |
| wechsel | 3/5 | 4/5 | +1 |
| wo | 4/5 | 5/5 | +1 |
| **relpron** | 6/6 | **4/6** | −2 ⚠️ |
| aux | 6/6 | 5/6 | −1 |
| sep | 10/10 | 9/10 | −1 |

Watch item: **relpron regressed 6/6 → 4/6.** Relative pronouns were never a v2 generation target —
the manifest has no relpron slice — so this is plausibly drift from a corpus weighted elsewhere
rather than damage. Worth a slice in a future generation round.

Naturalness moved even more than on E2B: modal particles **2.82 → 14.49 (5.1×)**, repeat-4gram
0.30 → 0.12, top-opener share 0.231 → 0.130, opening variety 0.70 → 0.78, TTR 0.780 → 0.806,
follow-up rate 0.78 → 0.90, replies longer (11.3 → 13.9 tokens). English leakage stayed at zero.

**So the trade this whole phase was designed to let you judge never had to be made for E4B** — it is
better on grammar *and* better on every naturalness proxy.

### 2.5 Operational note: the E4B HF push stalls

The training script's `push_to_hub_merged` **hangs** for E4B-sized models. Unsloth stops at
`Copying 1 files from cache` — a local 15 GB copy on the pod's network filesystem, before uploading.
Measured: **0 bytes moved in 90 s**, on disk and on the wire. Both E2B pushes (10.3 GB) worked, so
this is specific to E4B's single 15 GB safetensors shard.

**Workaround, now the recommended default above ~10 GB:** `scp` the merged directory off the pod
(~11 MB/s, ~23 min for 15 GB) and run `mlx_vlm convert --hf-path <local dir>`. It also removes HF as
a dependency for getting the result at all.

---

## 2.6 ⛔ §2.4 RETRACTED — E4B v2 is worse where the app actually works (2026-08-12)

Found while wiring v2 into the app. **The ship decision in §2.4 was made on the v2 holdout alone.
Scored on the other two suites, v2 is significantly worse than the model it would replace, and on
the core suite it is worse than the untuned base.** All guarded, all reproducible from
`results/guarded-*.json`:

| suite | stock E4B | E4B v1 (shipped) | E4B v2 |
|---|---|---|---|
| **core v0** (60) — the app's four target areas | 48 (80%) | **54 (90%)** | **42 (70%)** |
| ext v1 (61) | 57 (93%) | 57 (93%) | 55 (90%) |
| holdout v2 (82) | 64 (78%) | 70 (85%) | **75 (91%)** |
| miss rate (v0+v1, /69) | 11 (16%) | **6 (9%)** | 19 (**28%**) |
| false corrections (/32) | 2 (6%) | 2 (6%) | **1 (3%)** |

Methodology check: this harness reproduces the recorded numbers exactly — stock E4B at 48/60 = 80%
matches the guarded table at the top of `MODEL_SCOREBOARD.md`, and v1's 90%/93% match too.

**Two corrections to §2.4:**

1. **The regression is significant; the "win" is not.** Core suite: +2/−14 discordant, exact
   McNemar **p = 0.0042**. Holdout: +10/−5, **p = 0.30**. The 85% → 91% headline that drove
   "✅ SHIP — better on both headline metrics" does not survive a significance test on an 82-item
   bench, while the core-suite loss does.
2. **Per phenomenon, the loss lands exactly on the app's targets**: `refl` 11/15 → 7/15,
   `sep` 14/15 → 11/15, `vmp` 15/15 → 12/15, `dawo` 14/15 → 12/15.

### The cause: verdict imbalance, per phenomenon

`pack_dataset.py` took whatever verdict mix the generator produced. It is not uniform, and nothing
checked it:

| phenomenon | v1 packed (fix share) | **v2 packed (fix share)** | v2 core-suite change |
|---|---|---|---|
| sep | 110 rows, **100%** | 779 rows, **20%** | 14/15 → 11/15 |
| refl | 101 rows, **100%** | 1,911 rows, **39%** | 11/15 → **7/15** |
| dawo | 116 rows, **100%** | 1,454 rows, 56% | 14/15 → 12/15 |
| vmp | 130 rows, **100%** | 3,021 rows, 59% | 15/15 → 12/15 |
| **whole correction slice** | 789 rows, **69% fix** | 9,791 rows, **44% fix** | — |

v1 taught "a sentence tagged with a phenomenon has an error in it" (its `OK` examples came from a
separate 245-row `verdict` bucket). v2 taught the opposite for `sep`: **four out of five separable-verb
examples said nothing was wrong.** The model learned the prior, and it shows in the failure mode —
**8 of the 14 items v1 got right and v2 got wrong are answered with a bare `OK`**, and 50% of all v2
core-suite failures are a bare `OK` against 33% for v1:

```
sep-e1   v2: OK                              ← "Ich stehe auf jeden Tag um sieben Uhr" is wrong
sep-e5   v2: FIX: Er hat das Licht gemacht.
             WHY: 'ausmachen' is used for making noise, not for turning off a light.   ← invented
         v1: FIX: Er hat das Licht ausgemacht.
```

The remaining 6 of 14 are wrong `FIX`es, so the imbalance is the dominant cause but not the only one.

**This also explains §3.4**, which flagged as an unexplained mystery that `relpron` regressed 6/6 → 4/6
on *both* E4B v2 and Granite r=32. There are **zero** `relpron` rows in the v2 corpus, so it was never
about relpron data — both models were trained on the same OK-heavy corpus, both shifted their prior
toward "no error", and `relpron` holdout items are mostly error items. One cause, two architectures.

**§1.9's composition gate passed this.** It recorded "correction 22,342 — **43.9% fix**" as healthy
because it was checking that fix rows *existed at all* (after the `repair_json` bug of §1.5b
destroyed them). Nobody compared 43.9% against v1's 69%, and nothing looked per-phenomenon. That is
the same lesson as §1.5b one level up: a gate that proves data is *present* does not prove it is
*shaped right*.

### The fix, and what it costs

`pack_dataset.py` gained **`--fix-frac`**, which balances verdict per phenomenon (never dropping
`fix` rows — they're the scarce half — only surplus `ok`). Balancing per phenomenon rather than
globally matters: a global ratio would let `vmp` supply all the fixes while `sep` stayed at 19%.

```bash
.venv/bin/python scripts/pack_dataset.py --source data/gen_v2/corpus_v2.valid.jsonl \
    --fix-frac 0.70 --val-frac 0.05 --out-dir data/packed-v2-balanced
```

`data/packed-v2-balanced/` — **44,211 train rows, 14,045 correction rows at 62% fix**
(vmp/refl/dawo at 70%, sep 67%), against v2's 9,791 at 44%. That is **43% more correction data and
the right balance, from data that already exists** — no regeneration, no teacher GPU.

**Open: `sep` is thin at the source.** Only 379 `fix` rows were ever generated for it against 1,605
`ok`, so a balanced `sep` slice is 471 rows (v2 packed 779, v1 packed 110). The correction-slice
generation prompt under-produces separable-verb errors and should be fixed before any future run.

**Not yet done: the retrain.** ~$2–3, same recipe as §2. Until then **v1 stays shipped**, and the
app-side migration machinery is built but inert (`ModelSupersession.valid` drops any row whose
retired repo ID still equals the live one).

---

## PICK UP HERE (state as of 2026-07-29)

### Done

| | |
|---|---|
| Phase 0 | ✅ metadata passthrough, grouped split, v2 holdout, naturalness bench, shipped-model baselines |
| Phase 1 | ✅ 45,097 validated rows → `data/packed-v2` (31,546 train) + `data/packed-v2-nomixin` (20,505) |
| GPU | stopped (`nrqb8618jv1kz1`, EXITED). Spend to date ≈ **$5.50** |

### Baselines to beat (Phase 0, guarded, on the frozen v2 holdout)

| model | core | false-corr | miss |
|---|---|---|---|
| E4B tuned (shipped) | 85% | 8% | 12% |
| E2B tuned (shipped) | 84% | 12% | 10% |

Naturalness baseline: modal particles 2.82 / 2.94 per 100 tokens, repeat-4gram 0.30 / 0.26,
question_variety 0.462 / 0.400, English leakage 0.00 both.

### Next: Phase 2 — retrain and measure (~$2–3, RTX A6000 @ $0.33/hr)

1. Train E2B on `data/packed-v2` (QLoRA r=8, lr 2e-4, 2 epochs — same recipe as v1).
2. Train E2B on `data/packed-v2-nomixin` — **settles §1.10**, whether the translated Alpaca
   mix-in still earns its 33% of the corpus now that a native-German instruction slice exists.
3. Train E4B on whichever build wins.
4. Score all of them on `grammar_eval_v2_holdout.json` **with `--app-guard`**, plus
   `conversation_v0.json` through `naturalness_metrics.py`.
5. Report both axes together (DATA_V2_DISTILL_PLAN.md Phase 2 gate: FC must not rise —
   E4B ≤ 8%, E2B ≤ 12%; no collapse below 80% core). Everything between those floors is a
   judgement call made with the naturalness table in hand.

**Do not skip `--app-guard`**, and quote guarded numbers only — raw and guarded differ by up to
25 points and by different amounts per model.

### Open items carried forward

- **§1.10 mix-in question** — resolve by measurement in step 2, not argument.
- **Flashcard dedup** — 4,138 validated → 1,522 packed. Dedup key is `topic + first card's
  germanWord` and the teacher reuses openers per topic. Needs more topic diversity if that slice
  is regenerated.
- **`fix identical to student`** — 2,168 rejections, the single largest bucket and ~15% of all fix
  rows. Cheapest generation-prompt improvement available for a future run.
- **Pod volume** — 120 GB is still billing while stopped (~$0.40/day). It holds the 49 GB teacher
  cache, which Phase 2 does *not* need (different, smaller models). Terminate unless another
  generation run is imminent.
- **RunPod API key** was printed to a session transcript on 2026-07-28 — rotate it.

## Reproduce

```bash
cd training

# repack with metadata + grouped split
.venv/bin/python scripts/pack_dataset.py --val-frac 0.05
.venv/bin/python scripts/pack_dataset.py --no-mixin --out-dir data/packed-nomixin

# v2 holdout, scored the way the app behaves
.venv/bin/python scripts/run_baseline_eval.py --model models/gemma4-e4b-german-tutor-4bit \
    --eval-file data/eval/grammar_eval_v2_holdout.json --tag v2holdout-guarded --app-guard
.venv/bin/python scripts/behavior_metrics.py --app-guard \
    --eval-file data/eval/grammar_eval_v2_holdout.json \
    results/v2holdout-guarded_gemma4-e4b-german-tutor-4bit.json

# naturalness bench
.venv/bin/python scripts/run_conversation_eval.py --dry-run
.venv/bin/python scripts/run_conversation_eval.py \
    --model models/gemma4-e4b-german-tutor-4bit --tag v1shipped
.venv/bin/python scripts/naturalness_metrics.py --by-kind \
    results/conv_v1shipped_gemma4-e4b-german-tutor-4bit.responses.json
.venv/bin/python scripts/naturalness_metrics.py --compare <old.json> <new.json>

# lexicon check (needs deepL= in training/.env)
.venv/bin/python scripts/deepl_gloss_check.py
```

---

## Phase 0 scorecard

| item | status |
|---|---|
| metadata passthrough (`pack_dataset.py` + trainer) | ✅ |
| grouped train/val split, leakage measured | ✅ |
| `grammar_eval_v2_holdout.json` (82 items, frozen) | ✅ |
| naturalness bench (`conversation_v0.json` + 2 scripts) | ✅ |
| `--no-mixin` 1B-student build | ✅ |
| DeepL lexicon re-check | ✅ — clean; check has near-zero precision |
| shipped-model baselines, both benches | ✅ |

**Cost: $0.** No GPU, 5,628 lifetime DeepL characters.

## Next — Phase 1 targets, informed by the baselines

The naturalness baseline points the Phase 1 data mix at specific defects rather than "more
conversation data":

1. **Modal particles** (~2.8/100 tokens today). Generation prompts should require natural particle
   use, and the validator should reject conversation turns that read as written German.
2. **Question variety** — E4B's `Woran…` accounts for 23% of its questions, and 69% of its questions
   are yes/no. Conversation examples need varied wh-openers and follow-ups that can't be answered
   with *ja*.
3. **Opening variety / canned phrases** — 30% repeat rate on both.
4. **The two confirmed grammar gaps**: `wo`-compounds under questioning (`Mit was` → `Womit`) and
   Wechselpräpositionen in the motion sense.

Phase 1 itself (30–50k examples, `gemma-4-26B-A4B-it` teacher) is ready to start.
Everything above is done, reproducible, and cost nothing.

---

## Phase 1 — teacher generation (2026-07-28, harness built, not yet run)

### 1.0 The prompt drift — found before spending anything

`pack_dataset.py` hand-copied the app's prompt strings, and they had silently drifted to the
**2026-07-09** shape. The v1 training data — and, uncaught, all 40k of v2 — was being built against
a prompt the app no longer sends:

| element | v1 training data | current app |
|---|---|---|
| conversation modes | Lena + one generic role-play sentence | 5 modes (freestyle/decks/scenario/interview/paper) |
| scenarios | generic `"You are role-playing: {name}"` | **23 typed scenarios**, each with its own `roleInstruction` |
| grammar focus | ✗ | **12 `GrammarFocus` areas**, injected into *both* the conversation and correction prompts |
| `FeedbackStyle.nudgeMe` | ✗ | **a third `HINT:` line** |
| learned phrases / due-review words / learner briefing | ✗ | all three inject steering text |

The sharpest gap: **"Nudge me" is a shipped feature whose output format had zero training examples.**
`ConversationPrompts.parseCorrection` parses `HINT:`, the system prompt asks for it, and both tuned
models were trained on `FIX:`/`WHY:` only.

**Fix — stop copying, start extracting.** `scripts/app_prompts.py` parses the literals straight out
of `ConversationConfig.swift` / `GrammarFocus.swift` / `ConversationPrompts.swift` at import time,
so the variable strings cannot drift. `scripts/check_prompt_sync.py` guards the half that is still a
hand-port (the assembly order and connective sentences) by asserting every fixed sentence exists
verbatim in the Swift, that each config emits the right paragraph count, and that every extracted
string is byte-identical to its source.

A guard that cannot fail is worse than none, so `scripts/test_prompt_sync_guard.py` verifies it
catches five real drift modes — all five pass, including the exact one that happened:

```
PASS — guard caught: nudgeMe HINT line silently dropped
PASS — guard caught: focus-area steering paragraph dropped
PASS — guard caught: typed scenario role replaced with the old generic string
PASS — guard caught: a level instruction reworded away from the app's
PASS — guard caught: a focus steering hint reworded away from the app's
```

`pack_dataset.py` now imports from `app_prompts`, and **v1 renders byte-for-byte identically** —
verified by diffing the packed message sets before and after the swap. That check caught a real
regression on the way: v1 overloads `scenario` as either a *role* (21 specific strings) or a plain
*topic* ("morning routine", "fixing a bike" — 73 of 94 values), and routing topics through the
role-play sentence would have silently rewritten 73 existing examples. `LEGACY_ROLE_SCENARIOS`
preserves the split; v2 data uses an explicit `role_scenario` key instead.

### 1.1 nudgeMe / HINT support, end to end

- **Schema**: correction candidates may carry `hint`.
- **Validator**: `hint` must be a question, ≤ 14 words, and must not reveal the correction.
  `leaks_answer()` compares the words the fix *supplies* (in `fix`, absent from `student`) against
  the hint. It deliberately does **not** exempt short words — an earlier version skipped anything
  ≤ 3 characters and was therefore blind to the single most common leak, since verb+preposition is
  the largest phenomenon and the supplied word is always short:
  `"Heißt es nicht 'interessiere mich für Musik'?"` hands over the answer via `für`. Now tested
  against 9 cases covering preposition, pronoun and article leaks — all pass.
- **Packer**: rows with a validated `hint` render `FIX:/WHY:/HINT:` under the nudgeMe system
  prompt. `--nudge-ok-frac` (default 0.25) also renders a quarter of `verdict:"ok"` rows under that
  prompt, so the model doesn't learn "nudgeMe means always correct something". 68 such rows exist
  already from v1 data.

### 1.2 The generation harness

| file | role |
|---|---|
| `scripts/build_gen_jobs.py` | builds the manifest locally, no GPU |
| `runpod/gen_v2/generate.py` | runs on the pod, offline-batched vLLM, **resumable** |
| `runpod/gen_v2/README.md` | runbook, GPU choice, smoke-test gate, how to read rejections |

Manifest at `--target 40000`: **11,067 jobs → ~40,002 expected items**.

| slice | share | jobs | items |
|---|---|---|---|
| correction | 40% | 2,000 | 16,000 |
| conversation | 30% | 6,000 | 12,000 |
| flashcards | 15% | 2,000 | 6,000 |
| recovery | 10% | 667 | 4,002 |
| native_instruction | 5% | 400 | 2,000 |

Coverage verified: **all 23 scenarios**, **all 12 focus areas** (265–315 jobs each).

Design choices worth keeping:

- **Correction jobs are seeded, not free-form** — each is pinned to a specific verb+preposition from
  the 268-entry curated table and a specific phenomenon, because `validate_data.py` can only
  structurally check what it was told to expect.
- **The conversation prompt targets Phase 0's measured defects directly**: it demands modal
  particles, a different opening every time, varied question words, and explicitly forbids
  yes/no-question monotony and canned encouragement.
- **`native_instruction` replaces the Alpaca mix-in** and the prompt says so in as many words: text
  must be *originally* German, no translationese, no `"Funktionieren Sie als …"`.
- **`recovery` gets its own phenomenon** rather than reusing `verdict`, so the stats stay readable.
- The response parser handles all seven shapes teachers actually emit — bare JSONL, ```json fences,
  German preamble, pretty-printed, trailing commas, braces inside strings, and refusals — verified
  by unit test. At 40k items a 10% parse loss is 4,000 items.

### 1.3 Teacher/GPU correction

The plan said L40S 48 GB with a `w4a16` 26B-A4B build at ~$0.79/hr. **That build does not exist** —
Google ships `w4a16-ct` for 31B / 12B / E2B / E4B only; for 26B-A4B the QAT releases are
`-qat-q4_0-gguf` (llama.cpp, not vLLM) and `-qat-q4_0-unquantized`, which is bf16 and still 51.6 GB.

Revised: **`gemma-4-26B-A4B-it` bf16 (51.6 GB) on an A100 80 GB PCIe, community, ~$1.19/hr**.
≈ 1.5–3 h → **$2.50–4**, budget $8. Cheaper than the original estimate despite the bigger card,
because a 4B-active MoE generates far faster than the dense model the $10–16 figure assumed.

The 48 GB alternative is `gemma-4-31B-it-qat-w4a16-ct` (23.3 GB) on an L40S — but it is dense, so
60 layers run per token instead of 30 MoE layers: cheaper per hour, more hours.

### 1.4 Smoke testing — four rounds, five bugs

40 stratified jobs per round (every slice, every correction phenomenon), each round validated with
the real `validate_data.py`. Stratifying mattered: a random sample would have shown "69%, seems
low" without localising anything. Every failure turned out to be **mechanical, not data quality**.

| round | pass rate | empty jobs | conversation yield | what it exposed |
|---|---|---|---|---|
| 1 | 69.2% | 17.5% | 38% | truncation, manifest override, missing validator route, even turn counts |
| 2 | 82.9% | 12.5% | 33% | duplicate-key JSON glitch, 5-message conversation floor |
| 3 | **84.8%** | **5.0%** | **96%** | recovery under-delivery |
| 4 | 80.0% | 10.0% | — | confirmed the turn-trim: `roles must alternate` 11 → **0** |

**The five bugs, and why each is worth remembering:**

1. **Flat `max_tokens=1600` truncated long slices mid-JSON.** Yield tracked output length almost
   perfectly — flashcards 100%, correction 88%, recovery 62%, conversation 38%, native 33%. Fixed
   with per-slice budgets (`SLICE_MAX_TOKENS`) plus a `finish_reason == "length"` counter, because
   truncation is invisible in a yield number alone.
2. **The teacher overrode the manifest.** It rewrote `"phenomenon":"verdict"` as `"none"` on every
   verdict job — understandable, since that job's prompt describes the type as *"KEIN Fehler"* —
   and the validator's whitelist then rejected all 16. `attach()` now *forces* the manifest's
   values instead of `setdefault`-ing them. The manifest is authoritative; the teacher's opinion
   about its own metadata is not.
3. **A duplicate-key JSON glitch, in 2 of 4 conversation jobs.** The teacher emits
   `{"role":"assistant","content","content":"…"}` — a bare string where a value belongs. One
   occurrence invalidates the entire dialogue. `repair_json()` fixes it with a regex that provably
   cannot touch valid JSON (there is no legal JSON in which `"x","x":` is correct), unit-tested to
   leave well-formed objects byte-identical. **This single fix took conversation from 33% → 96%.**
4. **Even turn counts can't start *and* end on the assistant.** `validate_conversation` requires
   both. Asking for odd counts didn't work — the teacher emits 12 regardless. Trimming the trailing
   learner turn in `attach()` is deterministic where prompting wasn't: 11 rejects → 0.
5. **`native_instruction` had no validator route**, and `pack_dataset.py` would have crashed on it
   (its `else` branch assumes flashcards). Both fixed.

Plus one bug of my own: `leaks_answer()` false-positived on `das`. Student *"Kannst du mir die
Wasser geben?"* → fix *"das Wasser"*, hint *"Ist das Wort neutral oder feminin?"* — a textbook-correct
hint, rejected because `das` was the supplied word and also the most common word in German.
Closed-class words now only count as leaks when the hint **quotes** them; content words still leak
on any occurrence. 11 test cases, covering all four leak types and both false positives.

### 1.5 Size the manifest from measured yield, not from what you asked for

The most useful thing the smoke rounds produced. **The teacher reliably under-delivers on count**,
worse the longer the output, and some of what it delivers is rejected. Nominal asks versus what
actually survives the validator:

| slice | asked/job | **valid/job** | ratio |
|---|---|---|---|
| correction | 8 | 4.07 | 51% |
| conversation | 2 | 1.25 | 63% |
| flashcards | 3 | 2.56 | 85% |
| recovery | 3 | ~1.50 *(est.)* | 50% |
| native_instruction | 5 | 3.00 | 60% |

Sizing the manifest off `PER_JOB` would have produced **~28k valid items where 40k was asked for**,
discovered only after paying for the full run. `--size-by-measured-yield` scales each slice's job
count by `MEASURED_VALID_PER_JOB` so the *post-validator* corpus hits the target mix.

`recovery` is the least certain number — it is an estimate at `PER_JOB=3`, not a measurement. It was
measured at 0.80 with `PER_JOB=6`, which is why that dropped: making recovery dialogues 5 messages
(the validator's floor) meant asking for 30 turns of output per job, and the teacher returned ~1.2
dialogues. **Asking for less reliably returns more.**

Re-measure and update `MEASURED_VALID_PER_JOB` whenever the prompts, `PER_JOB`, or validator change.

### 1.5b The expensive bug: a repair function that destroyed what it was repairing

The full run produced 48,013 items of which **0 correction rows had `verdict:"fix"`** — a 16,128-row
correction slice containing no corrections. The validator passed all of them, because an `ok` row
with correct German is well-formed data. Pass rate went *up*.

**Cause: the `repair_json()` regex added just before smoke 3.** It was written to fix the teacher's
duplicate-key glitch (`"content","content":`) and was unanchored:

```python
_DUP_KEY_RE = re.compile(r'"(\w+)"\s*,\s*"\1"\s*:')     # WRONG
```

The correction schema contains a value immediately followed by a key of the same name:

```
..."verdict":"fix","fix":"Er hat lange mit seinem Bruder telefoniert."...
             └──┬──┘└─┬─┘
             value    key of the same name
```

The regex rewrote that to `"verdict":"fix":"Er hat …"` — invalid JSON — so **every** `verdict:"fix"`
row failed to parse and was silently dropped, while `"verdict":"ok","fix":null` was untouched.
One collision, and it happened on exactly the rows that carry the training signal.

Anchoring the first occurrence to key position fixes it:

```python
_DUP_KEY_RE = re.compile(r'([,{])\s*"(\w+)"\s*,\s*"\2"\s*:')   # RIGHT
```

Same 32 jobs, before and after: **130 rows / 0% fix → 239 rows / 45.6% fix, 37.6% of fix rows
carrying a HINT.**

**Three process lessons, all now enforced in code:**

1. **Pass rate cannot detect "valid data, wrong shape."** Added
   `scripts/check_batch_composition.py`, which gates on verdict mix, HINT share, per-phenomenon
   presence and scenario diversity. Verified: passes smoke 1–2, fails smoke 3, smoke 4 and the full
   run. It would have stopped this before the 81-minute spend.
2. **A repair function needs negative tests against the real schema, not generic JSON.**
   `repair_json` *was* tested — against a generic valid object, which has no value/key collision.
   The correction schema guaranteed one on every error row.
3. **Diagnose by comparing what the teacher said against what you stored.** My first diagnosis
   blamed a prompt paragraph added at the same time as the regex; it was plausible and wrong, and I
   stopped looking because it fit. Dumping raw model output next to the parsed result found the real
   cause in one step — fix rows were plainly present in the generation and absent from the file.

Cost of the bug: ~100 minutes and ~$2 of GPU. The conversation, flashcards and native_instruction
slices were unaffected — their schemas contain no value/key name collision — so only the correction
slice needed regenerating.

### 1.6 Full run — launched 2026-07-28

```
19,210 jobs -> ~69,024 nominal items -> ~40,005 projected VALID
correction    3,931 jobs -> 16,002 valid  (40%)
conversation  9,600 jobs -> 12,000 valid  (30%)
flashcards    2,344 jobs ->  6,000 valid  (15%)
recovery      2,667 jobs ->  4,001 valid  (10%)
native          667 jobs ->  2,001 valid   (5%)
~4.0 h on an A100 SXM 80GB @ $1.49/h -> ~$5.96
```

Resumable: completed `job_id`s append to `candidates.jsonl.done` and a rerun skips them.

**Actual throughput measured:** 40 jobs in ~0.5 min of generation (~724 output tok/s at batch),
model load ~2–3 min from the warm volume cache. vLLM 0.26.0 loads `gemma-4-26B-A4B-it` cleanly on
the **TRITON Unquantized MoE** backend — the one architectural unknown, resolved in smoke round 1.

## Phase 3 — the 4 GB tier (2026-07-29 → 2026-07-30)

Goal: beat what the app actually ships to 4 GB devices (iPhone XR / 11 / SE 2–3 / 12 mini class).

### 3.1 Base sweep, guarded, on the frozen v2 holdout

Nine candidates converted to MLX 4-bit and scored identically (`--app-guard`, 82 items):

| base | core |
|---|---|
| Granite 3.3 2B instruct | 45/82 = 55% |
| Granite 4.1 3B | 41/82 = 50% |
| Granite 4.0-H 1B | 33/82 = 40% |
| Granite 4.0-H 350M | 24/82 = 29% |
| Gemma 3 1B stock | 28/82 = 34% |

**Structural finding.** German capability lives in large multilingual vocabularies, which consume
the parameter budget; body capacity requires small vocabularies, which mean weaker multilingual
pretraining. Gemma 3 1B is ~60% vocabulary table (396M body); Granite 3.3 2B is ~4% (2,399M body).
At 4 GB you normally cannot have both — Granite 3.3 2B is the one model tested that threads it.

### 3.2 The incumbent was never 58%

`apply_app_guard` implemented only the echo rule, not the full `parseCorrection` contract — it was
missing `upper.hasPrefix("OK\n")`. Stock Gemma 3 1B answers **every** item with:

```
OK
FIX: <a real correction>
WHY: <...>
```

The old scorer credited both branches (`expect_ok` items passed on the leading `OK`, error items
passed on the `FIX`), scoring it 49/82 = 59%. The app shows the learner *nothing* for those replies.
True score **28/82 = 34%**, true miss rate **100%**, not 49%. That inflated number sat on
`MODEL_SCOREBOARD.md` as the 4 GB incumbent for weeks and made the whole budget-base search look
like a failure. Every Gemma 4 tune is unaffected — they emit a clean `OK` or a clean `FIX`.

**Second-order damage: the saved result files were poisoned too.** `results/*.json` stores
`app_guard: true` alongside a `pass` field computed at *run time*, so every file scored before the
fix carried the old verdict while advertising itself as guarded. Re-scoring all 16
`v2holdout-guarded_*.json` from their (unchanged) raw responses found **3 stale**:

| file | stored | corrected |
|---|---|---|
| `gemma-3-1b-it-4bit` | 49/82 | **28/82** |
| `granite-3.3-2b-instruct-4bit` | 47/82 | **45/82** |
| `Falcon-H1-1.5B-Instruct-4bit` | 11/82 | **10/82** |

The other 13 — every Gemma 4 model, both tuned Granites — were already correct, which is the
predicted signature. All three have been rewritten in place with a `rescored_note`. **Lesson: a
scorer fix must be replayed over saved results, not just applied going forward.** Raw generations
are the durable artifact; scores are derived and must be treated as cache.

### 3.3 LoRA rank test — is 67% a capacity ceiling or an absorption limit?

Single variable changed from the run that produced 67%: `r=8 → r=32` (`alpha=2r`), same corpus,
same 1 epoch, same chat template, same quantization (4 bit / group 64 / 4.501 bpw).

```
r=8    14.1M trainable (0.50%)   final eval_loss ~0.89   55/82 = 67%
r=32   56.4M trainable (2.18%)   final eval_loss  0.708  59/82 = 72%
```

**The loss moved a lot; the holdout core did not move measurably.**

```
gained 9   lost 5   net +4
exact McNemar, 14 discordant: two-sided p = 0.424
```

**But the behavioral metrics did move, in the direction that matters most:**

| | core | false-corr | miss |
|---|---|---|---|
| stock | 45/82 (55%) | 4/24 (17%) | 27/41 (66%) |
| r=8 | 55/82 (67%) | 2/24 (8%) | 19/41 (46%) |
| **r=32** | 59/82 (72%) | **0/24 (0%)** | 18/41 (44%) |

False corrections went 8% → **0%**. This scoreboard has treated FC as the trust-killer since the
E2B work, and on that metric r=32 is a clean win even though core is a coin flip. Read the rank
test as: *more adapter capacity bought verdict discipline, not knowledge* — consistent with the
capacity-cliff model, where judgment is what small students lose first.

An 82-item bench cannot distinguish 67% from 72%. Read this as *rank was not the binding
constraint* — r=64 or a second epoch is unlikely to pay. The remaining lever is on-policy KD.

Per phenomenon it is a reshuffle, not a lift:

```
UP    wechsel 2/5→4/5   dawo 6/10→8/10   sep 4/10→5/10   k2 2/4→3/4   adjend 3/6→4/6
DOWN  relpron 6/6→4/6   aux 6/6→5/6
```

Naturalness is a wash (r=8 → r=32): repeat-4gram 0.18→0.14, top-opener 0.182→0.143,
modal particles 12.34→12.02, TTR 0.806→0.797, English leakage 0.0, stutters 0.0.
`followup_rate` rose 0.86→0.98 — nearly every reply now ends in a question, which is worth a
listen; that can read as interrogative rather than conversational.

### 3.4 ⚠️ Carry forward: `relpron` regressed identically on two architectures

E4B v2 went `relpron` 6/6 → 4/6. Granite r=32 went `relpron` 6/6 → 4/6. Same phenomenon, same
magnitude, two unrelated model families, two separate training runs. That is not model noise —
it points at the relative-pronoun data in the v2 corpus. **Investigate before training anything
else on this corpus.**

### 3.5 Operational: the failsafe failed a second time, in the opposite direction

Round 1 (fixed 2026-07-30 morning): `grep -c … || echo 0` emits *two* lines on no-match, so the
process count read as `0` → "training died" → it stopped a **healthy** pod 90 s after arming.

Round 2 (this run): the failsafe never fired at all. `ConnectTimeout=20` bounds only *connection
setup*, not command execution — an `ssh` that connects and then hangs blocks forever, so the poll
loop froze inside a child and sailed past its own 16:55 deadline. Two copies were wedged this way.
The pod idled ~6 h at $0.53/hr ≈ **$3.20**. The model was never at risk: the HF push completed
before the hang.

**Fix for the next one:** `-o ServerAliveInterval=10 -o ServerAliveCountMax=3`, wrap every poll in
`timeout 60`, and make the deadline a backstop that a wedged child cannot block.

### 3.6 Unsloth drops `rope_theta` on Granite merges — every time

Both the r=8 and r=32 merges came back missing `rope_theta` (`10000000.0`) and `rope_scaling`, and
`mlx_lm` refuses to convert without them. Restore from `ibm-granite/granite-3.3-2b-instruct`
before converting. This is now scripted, not remembered.

### 3.7 Where the 4 GB tier stands

```
Gemma 3 1B stock  (ships today)   34%
Granite 3.3-2b tuned r=8          67%
Granite 3.3-2b tuned r=32         72%   (noise-equivalent to r=8)
──────────────────────────────────────
E2B v2 (6 GB)                     84%
E4B v2 (8 GB)                     91%
```

Roughly **double** the incumbent, short of E2B. Artifacts: `kessenma/granite33-2b-german-v2-r32`
(private), local `models/granite33-2b-r32-4bit` (1.3 GB).

**Open before shipping:** measure peak RAM on a real 4 GB device, and resolve §3.4.

### 3.8 Granite's tokenizer reads German in fragments

Found while scoping Phase 4. The teacher and the student do not share a vocabulary, and the
student's is poorly matched to the language:

```
"Ich habe gestern das Buch gelesen."

Gemma 4  (7)  ['Ich', '▁habe', '▁gestern', '▁das', '▁Buch', '▁gelesen', '.']
Granite (13)  ['I','ch','Ġh','abe','Ġgest','ern','Ġdas','ĠB','uch','Ġge','les','en','.']
```

| | vocab | tokenizer | German cost |
|---|---|---|---|
| Gemma 4 E4B | 262,144 | SentencePiece | 1 token/word |
| Granite 3.3 2B | 49,159 | byte-level BPE | ~1.9× |

Three consequences, in descending order of how well established they are:

1. **~2× slower generation per German word**, on the weakest hardware in the lineup. Measured.
2. **Effectively halved context** for German text. Follows directly.
3. **Plausibly part of the 72% ceiling** — body capacity spent reassembling subwords rather than
   on grammar. This is a hypothesis, consistent with a model whose body is 6× Gemma 3 1B's yet
   plateaus, but it is *not measured* and should not be quoted as a finding.

It also blocks Phase 4 as designed (no shared vocabulary → no token-level KL). See the block
notice in [`DATA_V2_DISTILL_PLAN.md`](DATA_V2_DISTILL_PLAN.md).

### 3.9 Status: 4 GB track PAUSED (2026-07-30)

The tier doubles and stops.

```
Gemma 3 1B stock (ships today)    34%
Granite 3.3-2b tuned r=32         72%
E2B v2 (6 GB)                     84%
```

Paused rather than pursued further, because every remaining lever is weak: SFT is exhausted
(§3.3), on-policy KD needs a redesign for this pairing (§3.8), the tokenizer penalty is
structural, and the 4 GB device population is shrinking. The structural read is that under 4 GB
you choose between a model that knows German (large vocabulary, no body left — Gemma 3 1B) and
one that can learn (large body, fragmenting tokenizer — Granite); neither wins. Reopen when a
small base offers both.

**Not blocked by this pause, and still open:**

- Ship E4B v2 (91% core / 0% FC) — public HF push + one-line `ModelConfiguration` change.
- The `relpron` regression, 6/6 → 4/6 on **both** E4B v2 and Granite r=32 (§3.4). Data-side,
  free to investigate, currently taxing every model trained on this corpus.
- Peak RAM for Granite on a real 4 GB device, if the tier is ever revived.
