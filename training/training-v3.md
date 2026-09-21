# Training v3 — the verdict-balance fix

Worklog for the E4B retrain that exists because **v2 shipped a worse model and nearly reached
users**. Companion to [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md) (scores),
[`training-v2.md`](training-v2.md) (§2.6 has the discovery), and
[`runpod/README.md`](runpod/README.md) (how to run the GPU half).

Status as of 2026-08-13: **training in progress.** v1 remains the shipped model.

---

## 0. What happened, in one paragraph

The v2 retrain was judged on one eval suite — the frozen 82-item v2 holdout — where it scored 91%
against v1's 85% and was written up as "✅ SHIP — better on both headline metrics". Wiring it into
the app meant re-scoring every model on a common basis, and that surfaced the rest of the picture:
on the **core suite**, the 60 items covering the app's four target phenomena, v2 had gone
**90% → 70%**, landing *below the untuned base model*. The holdout gain was not statistically
significant; the core loss was. Root cause was a data-composition bug that no gate caught. v3 is the
same recipe on a corpus with that bug fixed.

## 1. The measurement that caught it

All guarded (`--app-guard`), all reproducible from `results/guarded-*.json`.

| suite | stock E4B | **E4B v1 (shipped)** | **E4B v2** |
|---|---|---|---|
| **core v0** (60) — vmp/sep/refl/dawo | 48 (80%) | **54 (90%)** | **42 (70%)** |
| ext v1 (61) | 57 (93%) | 57 (93%) | 55 (90%) |
| holdout v2 (82) | 64 (78%) | 70 (85%) | **75 (91%)** |
| miss rate (/69) | 11 (16%) | **6 (9%)** | 19 (**28%**) |
| false corrections (/32) | 2 (6%) | 2 (6%) | **1 (3%)** |

Significance, exact McNemar on the discordant pairs:

```
core v0     v2 vs v1   +2 / -14   p = 0.0042   ← real regression
ext v1      v2 vs v1   +1 /  -3   p = 0.6250   ← nothing
holdout v2  v2 vs v1   +10 / -5   p = 0.3018   ← the "win" is noise
```

The harness reproduces the previously recorded numbers exactly (stock E4B 48/60 = 80% matches the
guarded table in `MODEL_SCOREBOARD.md`; v1's 90%/93% match), so the method is sound and only the
conclusion was wrong.

**Why one suite disagreed with the other:** the v2 holdout spreads 82 items over 12 phenomena, so
only about half of it touches the four the app actually teaches. The core suite is 60 items of
nothing else. v2 got broader and worse where it counts, and the holdout averaged that away.

## 2. Root cause — verdict imbalance, per phenomenon

`pack_dataset.py` took whatever mix of `verdict:"fix"` / `verdict:"ok"` rows the generator produced.
That mix is not uniform across phenomena, and nothing checked it:

| phenomenon | v1 packed | **v2 packed** | v2 core-suite change |
|---|---|---|---|
| sep | 110 rows, **100% fix** | 779 rows, **20% fix** | 14/15 → 11/15 |
| refl | 101 rows, **100% fix** | 1,911 rows, **39% fix** | 11/15 → **7/15** |
| dawo | 116 rows, **100% fix** | 1,454 rows, 56% fix | 14/15 → 12/15 |
| vmp | 130 rows, **100% fix** | 3,021 rows, 59% fix | 15/15 → 12/15 |
| **whole correction slice** | 789 rows, **69% fix** | 9,791 rows, **44% fix** | — |

v1 taught "a sentence tagged with a phenomenon contains an error" — its `OK` examples came from a
separate 245-row `verdict` bucket. v2 taught the opposite for `sep`: **four of five separable-verb
examples said nothing was wrong.** The model learned the prior.

The failure mode matches: **8 of the 14 items v1 got right and v2 got wrong are answered with a bare
`OK`**, and 50% of all v2 core failures are a bare `OK` against 33% for v1.

```
sep-e1   v2: OK                                    ← "Ich stehe auf jeden Tag um sieben Uhr"
sep-e5   v2: FIX: Er hat das Licht gemacht.
             WHY: 'ausmachen' is used for making noise, not for turning off a light.   ← invented
         v1: FIX: Er hat das Licht ausgemacht.
```

The other 6 of 14 are wrong `FIX`es, so imbalance is the dominant cause but not the whole story.

**It also explains `training-v2.md` §3.4**, filed as an unexplained mystery: `relpron` regressed
6/6 → 4/6 on *both* E4B v2 and Granite r=32, two unrelated architectures. There are **zero**
`relpron` rows in the corpus — it was never about relpron data. Both models were trained on the same
OK-heavy corpus, both shifted their prior toward "no error", and `relpron` holdout items are mostly
error items. One cause, two architectures.

### Why the existing gates missed it

`training-v2.md` §1.9 recorded "correction 22,342 — **43.9% fix**" as a *passing* composition gate.
That gate was added after the §1.5b disaster where a bad regex destroyed every fix row, so it was
built to answer "are there any fix rows at all?" — and 43.9% clears that easily. Nobody compared it
against v1's 69%, and nothing looked per-phenomenon, where `sep` sat at 19%.

Same lesson as §1.5b, one level up: **a gate proving data is present does not prove it is shaped
right.** Pass rates and presence checks are both blind to distribution.

## 3. The fix

`pack_dataset.py` gained `--fix-frac`, which balances verdict **per phenomenon**. Global balancing
would not have worked: a well-covered phenomenon like `vmp` would supply all the fixes while `sep`
stayed at 19%. `fix` rows are never dropped (they are the scarce half); only surplus `ok` rows are.

```bash
.venv/bin/python scripts/pack_dataset.py --source data/gen_v2/corpus_v2.valid.jsonl \
    --fix-frac 0.70 --val-frac 0.05 --out-dir data/packed-v2-balanced
```

| | v2 as shipped | **v3 (balanced)** |
|---|---|---|
| train rows | 31,546 | **44,211** |
| correction rows | 9,791 @ **44% fix** | **14,045 @ 62% fix** |
| vmp / refl / dawo | 59% / 39% / 56% | **70% each** |
| sep | 779 @ **20%** | 471 @ **67%** |

**43% more correction data and the right balance, from rows that already existed** — no
regeneration, no teacher GPU.

⚠️ **`sep` is thin at the source.** Only 379 `fix` rows were ever generated for separable verbs
against 1,605 `ok`, so a correctly-balanced `sep` slice is 471 rows — smaller than v2's 779, just no
longer 80% "nothing's wrong". The generation prompt under-produces separable-verb errors and should
be fixed before any future generation round. Volume here is a known remaining weakness.

## 4. The run

Same recipe as v2 so the verdict balance is the only variable:

```
EPOCHS=1  BATCH_SIZE=8  GRAD_ACCUM=1  MAX_SEQ_LEN=1024  LORA_R=8  LR=2e-4
44,210 examples → 5,527 steps
pod: A40 48 GB, EU-SE-1, $0.44/hr, ~4 h ≈ $2.20
```

`EVAL_STEPS` raised 250 → 1500. The v2 packing grew the val set from 29 rows to 2,326, making each
eval a 291-batch pass (~4.5 min); at 250 that is 22 evals ≈ 100 min of pure evaluation on a 4 h run,
for a loss number that is not comparable across builds anyway (different val sets — see
`training-v2.md` §2, the eval_loss warning).

Stack note: the current RunPod PyTorch image installs **transformers 5.5.0 / trl 0.24.0**, a major
version ahead of what this script was written against, and unsloth upgrades torch 2.8.0+cu128 →
2.11.0+cu130. A 17-step smoke run confirmed compatibility before committing to the full run — turn
markers auto-detected, only 1 of 44,211 rows failed response masking, LoRA attached at 18,350,080
trainable params. See [`runpod/README.md`](runpod/README.md) §5.

## 5. How to validate the result

**Score the core suite. Not just the holdout.** That is the whole lesson of this round.

```bash
for EV in grammar_eval_v0:guarded-v0 \
          grammar_eval_v1_extra:guarded-v1ext \
          grammar_eval_v2_holdout:guarded-v2; do
  f=${EV%%:*}; t=${EV##*:}
  .venv/bin/python scripts/run_baseline_eval.py --model models/gemma4-e4b-german-v3-4bit \
      --eval-file data/eval/${f}.json --tag $t --app-guard
done
.venv/bin/python scripts/behavior_metrics.py --app-guard \
    results/guarded-v0_gemma4-e4b-german-v3-4bit.json \
    results/guarded-v1ext_gemma4-e4b-german-v3-4bit.json
```

### Ship criteria

| metric | bar | why |
|---|---|---|
| **core v0** | **> 54/60** (beat v1) | the app's four target phenomena; the metric v2 failed |
| core v0 floor | **≥ 48/60** | below stock, the fine-tune is actively harmful |
| holdout v2 | ≥ 70/82 (beat v1) | fresh material, never iterated against |
| miss rate | ≤ 9% | v2 tripled this to 28%; it is the symptom of the OK-prior |
| false corrections | ≤ 6% | the trust-killer |
| format errors | 0 | |

**Judge core and miss together.** A model can buy a low false-correction rate by never correcting
anything — that is exactly what v2 did, and what Gemma 3 1B does at a 100% miss rate.

Also check per-phenomenon that `sep` and `refl` recovered specifically, since those are where the
imbalance was worst:

```bash
.venv/bin/python -c "
import json; print(json.load(open('results/guarded-v0_gemma4-e4b-german-v3-4bit.json'))['summary'])"
```

### If it doesn't clear the bar

The next levers, in order:
1. **`sep` volume** — regenerate that slice with a prompt that actually produces separable-verb
   errors (379 fix rows is thin). Needs a teacher GPU run.
2. **`--fix-frac 0.80`** — closer to v1's within-phenomenon shape. Free, one repack.
3. **2 epochs** — v2 used 1 because the corpus was 22× v1; the eval loss was still descending, so
   there was headroom.
4. Accept v1 and treat the v2 corpus as a naturalness-only asset.

## 6. What this round changed in the repo

| | |
|---|---|
| `scripts/pack_dataset.py` | `--fix-frac`, per-phenomenon verdict balance, recorded in `meta.json` |
| `scripts/rescore_app_models.py` | **new** — re-scores every in-app model guarded from saved responses, free. Identifies each responses file's suite **by item ID**, because filenames lie (`baseline_gemma-4-e4b-it-4bit.json` holds *extension* items) and scoring against the wrong suite silently turns unmatched IDs into empty strings that the guard reads as `OK` |
| `data/packed-v2-balanced/` | **new** — the v3 corpus |
| `MODEL_SCOREBOARD.md` | v2 SHIP verdict retracted; every in-app model restated on one guarded basis |
| `training-v2.md` §2.6 | the discovery, in place |
| `runpod/README.md` | rewritten as a full runbook with 10 measured gotchas |
| the app | migration machinery for retiring a model; all shipped copy re-derived from guarded scores |

## 7. Open

- **The run itself** — training as of 2026-08-13, unscored.
- **`sep` generation volume** (§3).
- **`relpron` has zero training rows** and regressed on every model trained on this corpus. Now
  explained (§2) but still not *fixed* — the corpus has no relpron slice at all.
- **The v2 4-bit artifact** is uploaded at `kessenma/gemma4-e4b-german-tutor-v2-4bit` (private).
  Given §1 it should stay private, or be published clearly labelled as superseded.

## 8. Corpus v4 — the teacher fixed, the corpus rebuilt (2026-08-16)

The v3 run was scored: **core 46/60 (77%), holdout 73/82 (89%)** — below v1's 54/60 bar and below
even stock's 48/60 floor on core. Verdict balance alone did not rescue a corpus whose hard-phenomenon
rows were generated by a ~4B-active MoE. So v4 replaces the *teacher*, not just the mix
(full teacher analysis: `TEACHER_GENERATION_FIX.md`; serving runbook: `runpod/bakeoff/README.md`).

### Sources

| source | rows fed | note |
|---|---|---|
| **gemma-4-31B bf16 batched** (new bulk run) | 4,668 | 5,223 raw → 5,024 after no-op filter (3.8%) → 4,668 validated (92%). Gates: refl case-change **98%**, sep pure-reorder **2%** — vs the 26B's 12%/26% |
| Sonnet 2026-08-14 batch | 586 | all 15 phenomena incl. first-ever `relpron`/`k2`/`imperativ`/`negation`/`wo`/`ndekl`/`wechsel` |
| v1-era Sonnet batches (`data/generated/`) | 1,401 unique | the corpus that produced the 54/60 model |
| 26B salvage: `vmp`/`dawo` only | 10,139 | `data/salvage_gemma26b/vmp_dawo.valid.jsonl` — the two phenomena the 26B shaped correctly (98%/90%). Its `refl`/`sep`/`verdict`/`aux`/`artikel`/`adjend` correction rows are **dropped** |
| 26B non-correction tasks | 22,755 | `data/salvage_gemma26b/tasks_noncorrection.valid.jsonl` — conversation/flashcards/native_instruction, the naturalness asset (v3 proved it survives independent of grammar scores) |

The 31B rejects were benign in profile: 168 near-duplicates, 101 hint-must-be-a-question, ~40
LanguageTool, 16 eval-overlap (correctly quarantined). Nothing systemic.

### Pack

```bash
.venv/bin/python scripts/pack_dataset.py \
  $(for f in data/generated/*.valid.jsonl; do echo --source $f; done) \
  --source data/generated_gemma31b/bulk_live.valid.jsonl \
  --source data/salvage_gemma26b/vmp_dawo.valid.jsonl \
  --source data/salvage_gemma26b/tasks_noncorrection.valid.jsonl \
  --fix-frac 0.70 --val-frac 0.05 --out-dir data/packed-v4
```

`data/packed-v4/`: **train 42,841 / val 2,254** (md5 `258ba84e67b935e486d7d8d23f87d1a7` /
`c10e49500a506b683ed4d3ce38356636`). Correction slice 13,758 rows at **70% fix in every phenomenon**
(`meta.json` has the full table). Global dedup collapsed 7,863 duplicate feeds (hardcase-subset
files + cross-source repeats).

This resolves two of §7's open items:

- **`sep` is no longer thin**: 984 rows @ 70% fix (v3: 471), with the reorder-mislabel poison at 2%.
- **`relpron` exists now**: 390 rows @ 70% fix (v3: zero — the phenomenon that regressed on every
  model trained on this corpus).

One watch item: the 31B *under*-delivers fix rows (51/49 delivered against 65/35 requested), the
opposite skew of the 26B. `--fix-frac` corrected it at pack time; §5 of the bakeoff README now says
to measure the delivered split on every batch.

### The run

> **Status 2026-08-17:** corpus packed 2026-08-16 (`data/packed-v4/`, md5 in the Pack section
> above); training run launched. **Scores not yet recorded — fill in the table below when it
> lands**, then update the lineage table in [`CLAUDE.md`](CLAUDE.md) and §1 of
> [`DATA_GAP_PLAN.md`](DATA_GAP_PLAN.md), which is blocked on this result.
>
> | suite | v3 | **v4** |
> |---|---|---|
> | core `guarded-v0` (60) | — | *pending* |
> | ext `guarded-v1ext` (61) | 86.9% | *pending* |
> | holdout `guarded-v2` (82) | 89.0% | *pending* |
>
> Watch `imperativ`, `relpron`, `k2` first — v3 had **zero** rows for all three, v4 has 133/390/287.
> This is the first run that gives a real dose-response point on the thin tail.

Same recipe as v2/v3 so the corpus is the only variable:

```
EPOCHS=1  BATCH_SIZE=8  GRAD_ACCUM=1  MAX_SEQ_LEN=1024  LORA_R=8  LR=2e-4  EVAL_STEPS=1500
42,841 examples → ~5,355 steps.  A40 48 GB @ $0.44/hr, ~4 h ≈ $2.20
```

Score **core first**, always guarded. Bars unchanged: beat v1's **54/60**; below stock's 48/60 the
tune is harmful. Holdout and naturalness proxies second — v3 already proved naturalness survives.

## 9. v4 generation results — four bases, one corpus, two days (2026-08-17/19)

Corpus v4 (§8) went through E4B, E2B, granite-3.3-2b, and granite-4.1-3b with the recipe held
constant (`EPOCHS=1 BATCH 8 LR 2e-4 SEQ 1024`; LoRA r=8 gemma / r=32 granite), so every delta below
is attributable to base capacity. Scoreboard-format summary: `MODEL_SCOREBOARD.md` 2026-08-19 block.
Total GPU spend for all four trainings: ~$10 (A100 SXM $1.39/hr for E4B, L40S $0.99/hr for the rest).

### 9.1 E4B v4 — 182/203, ship candidate

Grammar is a statistical tie with v1 (170/203 agreement, 11 v1-only vs 12 v4-only, exact McNemar
p = 1.00) with opposite strengths: v1 +3 on its old 4-phenomenon core, v4 +5 on the 15-phenomenon
holdout (75/82, ties the best ever). What actually changed is behavior: false corrections halved
(6% → 3%, one invented correction in 32 correct sentences), `relpron` restored to 6/6 on both
suites, and every naturalness proxy flipped — modal particles 2.82 → 12.37 /100 tokens,
repeat-4gram 0.30 → 0.10, follow-ups 0.78 → 0.82. The cost: miss 9% → 16%. Final eval_loss 0.806.

**Published:** `kessenma/gemma4-e4b-german-tutor-v4-4bit` (public, byte-verified, logged-out 200)
+ `…-v4-fp16` (public archive with LoRA). App swap staged but not yet made.

### 9.2 E2B v4 and v5 — the capacity-dilution discovery

- **v4 (full corpus): 163/203, miss 33%, FC 0%.** The corpus that helped E4B hurt E2B. The tell:
  ext 52 → 45 *including* phenomena E2B v1 was never trained on — the 15-phenomenon breadth
  interfered with existing competence instead of extending it. Dose-response on verdict ratio
  alone does NOT explain it (E2B v2, trained at 44% fix, missed *less*: 20%).
- **v5 (core-8 phenomena only, `--fix-frac 0.80`): 168/203, miss 23%, FC 3%.** Both levers worked
  directionally — ext +4, miss −10 points, voice retained — and the paired test vs v1 is a tie
  (18 vs 15, p = 0.73). But the pre-registered bar was *beat 171 with miss ≤ 15%*: *not met*.
  Final eval_loss 0.822 (own val set, not comparable across packs).

**Verdict: E2B stays on v1.** A ~2B model cannot hold strict error-catching and calibrated
permissiveness at once. Next levers if reopened: fix-frac 0.85–0.90, hard-negative OK rows
(correct sentences that look like classic errors). Archives: `…-e2b-german-v4-fp16`,
`…-e2b-german-v4s-fp16` (both private, byte-verified).

### 9.3 granite-3.3-2b v4 — 153/203, the project's first significant paired win

vs the r32 tune on the old corpus: +22 items (35 gained / 13 lost, **exact McNemar p = 0.002** —
every other pairwise comparison this project has run was noise). Miss 59% → 43%, FC stays 0%,
naturalness transformed (11.9 particles, follow-up 0.92). Both granite tunes share the same
failure mode — default to OK when unsure — the corpus just made it less unsure. eval_loss 0.7256.

**Published:** `kessenma/granite33-2b-german-tutor-v4-4bit` (public).

### 9.4 granite-4.1-3b v4 — 164/203, best small-model result

Stock probe first: 111/203 (core 31, ext 39 — *equal to tuned granite-3.3 v4* — holdout 41), i.e.
the base knows German but not correction behavior. Tuned on the full corpus: core 47 / ext 46 /
holdout 71, **miss 43% → 25%**, FC 9%, particles 12.0. vs granite-3.3 v4: 26/15 discordant,
p = 0.12 — directional, not conclusive on grammar, but the miss-rate halving is the story.
Its ~100k vocab roughly halves German token counts vs 3.3's 49k BPE, offsetting the larger
parameter count in per-sentence latency.

**Published:** `kessenma/granite41-3b-german-tutor-v4-4bit` (public). **Open: peak RAM on a real
4 GB device decides which granite ships in-app** (only one will — their sole differentiator is the
RAM floor; the loser stays an HF artifact).

### 9.5 The capacity law (the generalizable finding)

One corpus, four bases, recipe constant:

| base | effective capacity | outcome |
|---|---|---|
| gemma-4 E2B | ~2B sparse | ext regressed, miss 33% — **breadth dilutes**; even core-8-strict only reaches parity |
| granite-3.3 | 2.5B dense | +22 significant, but verdict courage still lacking (miss 43%) |
| granite-4.1 | 3.4B dense | +53 over its stock, miss 25% — digests breadth AND judgment |
| gemma-4 E4B | ~4B active (8B total) | absorbs everything; personality change only |

**Rules:** below ~2.5B dense, cap phenomenon breadth before adding data; below ~2B, the corpus
can only re-style, not improve; the verdict-strictness/permissiveness trade only resolves cleanly
at ≥3B dense. And on any pod: the delivered fix/ok ratio must be measured per batch (31B returned
51/49 against a 65/35 manifest) and corrected at pack time with `--fix-frac`.
