# Kolibri-1 bake-off — Kasus stories and the correction tail

Status: **done, 2026-10-04. Kolibri-1 is not adopted as a teacher for either task; gemma-31B stays.**
Pod time ~54 min, ≈ $4.15 (billing hadn't posted when this was written). The pod removed itself; `runpodctl pod list`
and the API both confirmed it gone.

Question: is `Aleph-Alpha/Kolibri-1` (78B MoE, 3.46B active, German-first, Apache 2.0) usable as a
teacher, against dense `google/gemma-4-31B-it`, for:

- **Kasus stories**: write a story around the app's planned case phrases (the tutor-written stories of the
  Grammatik case path), and
- **the correction tail**: rows for `imperativ`, `k2`, `negation`, `aux`.

Plan, inputs and scripts: [`KASUS_STORY_DATA.md`](KASUS_STORY_DATA.md) §4 (the 2026-10-04 run table).
Raw outputs: the private HF dataset `kessenma/kasus-bakeoff-2026-10`; local copy in
`data/bakeoff/kasus-2026-10/drop/`. Report: `scripts/kasus_bakeoff_report.py <drop>`.

---

## Setup

| | |
|---|---|
| pod | 1× H200 SXM 141 GB, Secure Cloud EUR-IS-4, **$4.59/hr** |
| Kolibri | vLLM 0.29.0 + `aleph-alpha-inference` 1.0.0, FP8 weights, `--kv-cache-dtype fp8 --reasoning-parser kolibri1 --max-model-len 16384`; sampling temperature 1.0, top_p 0.97, top_k 128 (the model card's) |
| gemma-31B | transformers 5.18 bf16, batched; temperature 0.9, top_p 0.95 (the v4 corpus's) |
| story prompts | 306: the Mac probe's six specs + `all:{A1,A2,B1}:2001-2020`, from `kasus-cli prompts` |
| tail jobs | 48: 12 each of imperativ, k2, negation, aux, 8 rows asked per job (`build_tail_jobs.py`) |
| budget | 2× the app's `maxTokens` for stories (+8,192 for reasoning); 1,400 for tail jobs |

## Worklog (UTC)

| time | event |
|---|---|
| 21:52 | pod created. Community had no H200/H100/A100 on a CUDA ≥ 13.0 host, which vLLM 0.29's torch 2.13 (CUDA 13.0 runtime) needs, so Secure Cloud |
| 21:53 | run started; 4 h deadline backstop armed (fires 01:53) |
| 21:58 | install done in 5 min: vllm 0.29.0, torch 2.13.0+cu130, transformers 5.18.0 |
| 22:00 | Kolibri downloaded, 78 GB in ~80 s |
| 22:02 | **vLLM crashed at warm-up.** FlashInfer JIT-compiles its top-k sampling kernel and couldn't find `ninja` (the venv wasn't on PATH). Weights (74.8 GiB) and CUDA graphs had loaded fine |
| 22:04 | relaunched with the venv on PATH and `VLLM_USE_FLASHINFER_SAMPLER=0` (vLLM's PyTorch sampler, no JIT) |
| 22:06 | vLLM healthy, ~2.5 min after start |
| 22:07 | Kolibri stories, thinking off: 306 in 30 s, 1,916 tok/s aggregate, 0 errors, 1 hit the budget |
| 22:18 | Kolibri stories, `reasoning_effort: medium`: 11.5 min, **246 of 306 ran out of budget mid-reasoning** |
| 22:19 | Kolibri tail: 48 jobs in 18 s. gemma-31B weights mostly cached from the interrupted first run |
| 22:24 | `/workspace/HOLD` set so the main run keeps the pod for a fair reasoning retry (below) |
| 22:25 | gemma-31B stories: 306 in 5.4 min (transformers, batch 16), 0 errors |
| 22:29 | gemma-31B tail: 48 jobs in ~5 min. Main run uploaded, `VERIFY OK`, HOLD kept the pod |
| 22:32 | reasoning retry: vLLM healthy with `--max-model-len 40960` |
| 22:38 | Kolibri `reasoning_effort: low`, 32k budget: 66 stories in ~6 min |
| 22:45 | Kolibri `reasoning_effort: medium`, 32k budget: 66 stories in ~7 min |
| ~22:47 | upload verified, HOLD removed, pod terminated itself (GraphQL `podTerminate` with the restricted key) |

### Serving notes for next time

- Kolibri serves **only** through vLLM with Aleph Alpha's plugin; there is no transformers code.
- vLLM 0.29.0 pins torch 2.13 → **CUDA ≥ 13.0 host driver**. Filter pods with `minCudaVersion: 13.0`.
- Set `VLLM_USE_FLASHINFER_SAMPLER=0` (or have `ninja` and a matching `nvcc`) whenever requests use top-k.
- 74.8 GiB of weights on an H200 leaves ~50 GiB at `--gpu-memory-utilization 0.9`. With 4 KV heads, FP8
  KV and 40 of 50 layers sliding-window, that's far more KV than this workload uses.
- Thinking off, it's fast: a 306-story bake-off takes 30 seconds once served. Startup (~2.5 min) costs more
  than generation.

---

## Results

### Stories · Kolibri, thinking off

| stories | pass | verbatim | altered | missing | gradable per story (Nom · Akk · Dat · Gen) | median tokens | top rejects |
|---|---|---|---|---|---|---|---|
| 306 | **217 (71%)** | **76%** | 16% | 8% | 4.2 · 4.3 · 4.8 · 0.9 | 157 | unitCaseCount 52, wechselVerb 19, wordCount 8, impossibleForm 7 |

All 217 passing stories fit inside the app's own `maxTokens` with the shipped tutor's tokenizer.

For scale, the Mac probe's outputs through **today's** check (different plans: six specs × 2 runs,
contract A, so indicative only):

| model | contract-A attempts passing | verbatim |
|---|---|---|
| shipped E4B v4 | 10 / 23 (43%) | 65 / 150 (43%) |
| E2B v4 | 9 / 22 (41%) | 59 / 126 (47%) |
| E4B v3 | 12 / 24 (50%) | 49 / 156 (31%) |
| **Kolibri, thinking off** | **217 / 306 (71%)** | **1,599 / 2,091 (76%)** |

**On the check's numbers, Kolibri is far ahead.** The hand read below is why that isn't the verdict.

### Hand read · Kolibri, thinking off (20 passing stories, seed 7)

`hand_read_kolibri1-nothink.md`. Each story read for German the check can't see.

| verdict | stories |
|---|---|
| a grammar error the check missed | **9 / 20** |
| grammatical, but nonsense or phrase-stuffing | ~8 / 20 |
| reads clean | 3 / 20 |

The errors, by kind:

| kind | examples (all in passing stories) |
|---|---|
| Wo verb + accusative after a two-way preposition | „Der Bruder wartet neben *einen* Tisch.“ · „Am Abend liegt das Spielzeug unter *das* Bett.“ · „Sie suchte auch auf *den* Boden.“ · „Am Ende ist der Topf neben *den* Ball.“ |
| wrong auxiliary | „Wir *haben* durch den Zoo gegangen.“ · „Ich *habe mich* nicht erschrocken.“ |
| a nominative in object position | „Der Opa kocht *ein Gast*.“ |
| other | „Morgen wird schön.“ (no *es*) · „Der Mann kommt gestern.“ |
| meta-text in the story | „Ich stehe auf dem Tisch. (Unrealistisch, aber Satz lang.)“ · „Die Mutter kocht Suppe von der Mutter. (Doppelt.)“ · „…unter den Tisch gelegt… nein, ich habe mich unter den Tisch gesetzt? Nein…“ |
| phrase-stuffing nonsense | „Ein großer Schrank steht neben dem Schrank.“ · „Sie kauft eine Karte für die Karte.“ · „Die Kinder essen den Kuchen mit dem Handy.“ · „Ich schreibe der Oma einen Brief für die Oma.“ · „Alle sind happy.“ |

Some of the nonsense starts in the plan, not the teacher: the planner pairs prepositions and nouns at
random („um den Tisch“, „unter einen Kühlschrank“, „für die Karte“), and a teacher told to use every
phrase verbatim has to put them somewhere. Every teacher gets the same plans, so the comparison stays
fair. But this is a planner issue to fix before bulk.

### Why the check passed them

Each of these is a gap in the app's own check (`KasusStoryCheck`), so it matters beyond training data:
a tutor-written story with these sentences is shown to a learner as reading text.

1. **A planned Wohin phrase used with a Wo verb is neither graded nor rejected.** „unter das Bett“,
   „neben einen Tisch“, „auf den Boden“ were planned as `wechselWohin` with *legen*. Without *legen* in the
   sentence they're placed as `triggerMissing`, and the two-way mismatch rule never sees them, even next
   to *liegt*, *wartet*, *suchte*. 3 of the 4 two-way errors.
2. **sein + a two-way accusative** („ist … neben den Ball“) isn't a position verb for the mismatch rule, so
   the unplanned phrase stays ungraded.
3. **Auxiliaries aren't checked** (haben/sein with a motion participle, reflexive *erschrecken*).
4. **Roles aren't checked.** A nominative form in object position passes as a proven nominative.
5. **Meta-text passes**: parenthetical remarks and self-corrections inside the story body.

Gaps 1 and 5 look cheap to close. 2–4 are new rules.

### Stories · Kolibri, `reasoning_effort: medium` (starved)

| stories | pass | verbatim | missing | ended early | median reasoning tokens |
|---|---|---|---|---|---|
| 306 | 51 (17%) | 19% | 81% | **246** | **9,291** |

Budget was 2× `maxTokens` + 8,192 (about 9,000–9,500). Kolibri at `medium` thinks for ~9,000 tokens
about a 100-word story and then has nothing left to write it. That's lesson 4 again, so this run says
nothing about whether reasoning helps. A retry with a 32k reasoning budget (`low` and `medium`, 66
prompts) runs after gemma: `runpod/bakeoff/kasus_bakeoff_reasoning.sh`.

For the app this rules out any reasoning mode on a phone-sized budget. For a teacher it's cost:
~60× the tokens of thinking off.

### Stories · Kolibri, reasoning with room (32k budget, 66 prompts)

The six probe specs + seeds 2001–2004 of every unit and level, `max-model-len 40960`.

| effort | stories | pass | verbatim | altered | missing | ended early | median reasoning tokens |
|---|---|---|---|---|---|---|---|
| `low` | 66 | **59 (89%)** | **93%** | 2% | 5% | 3 | **8,802** |
| `medium` | 66 | 57 (86%) | 91% | 1% | 8% | 5 | **13,493** |

`medium` is no better than `low` at ~1.5× the tokens, so only `low` was hand-read. 20 of its 59 passing:

| verdict | Kolibri `low` | Kolibri thinking off | gemma-31B |
|---|---|---|---|
| a grammar or tense error the check missed | 7 / 20 | 9 / 20 | **5 / 20** |
| nonsense, phrase-stuffing or awkward | ~9 / 20 | ~8 / 20 | ~8 / 20 |
| reads clean | 4 / 20 | 3 / 20 | **7 / 20** |

Examples: „*Trotzdem* eines Termins geht sie pünktlich“ · „Das Baby schmeckt seine Finger“ · „Ich kaufe
Brot *im* kleinen Bäcker“ · „*Es* ist immer noch verschwunden“ (for *der Schlüssel*) · „Im Fernsehen sehe
ich ein Lied“ · „Trotz des Windes ist es sehr kalt“ (trotz for wegen) · and the self-correction is still
there: „Sie suchte in der Schule? Nein, sie war schon zu Hause.“

**Reasoning lifts Kolibri's check numbers almost to gemma's, but not its German.** Even at `low` it
spends a median 8,802 reasoning tokens on a ~150-token story, ~55× the cost of thinking off (`medium`:
13,493, ~85×), and the hand read still trails gemma-31B.

### Stories · gemma-31B

| stories | pass | verbatim | altered | missing | gradable per story (Nom · Akk · Dat · Gen) | median tokens | top rejects |
|---|---|---|---|---|---|---|---|
| 306 | **285 (93%)** | **99%** | 1% | 0% | 3.0 · 4.1 · 5.6 · 1.1 | 174 | unknownWord 12, impossibleForm 4, verbAgreement 4, wechselVerb 2 |

All 285 passing stories fit the app's `maxTokens`. On the check's numbers, gemma-31B is ahead of
Kolibri by 22 points of pass rate and 23 of verbatim phrases.

### Hand read · gemma-31B (20 passing stories, seed 7)

| verdict | gemma-31B | Kolibri, thinking off |
|---|---|---|
| a grammar or tense error the check missed | **5 / 20** | 9 / 20 |
| grammatical, but nonsense, phrase-stuffing or awkward | ~8 / 20 | ~8 / 20 |
| reads clean | **7 / 20** | 3 / 20 |

gemma's errors, all in passing stories:

| kind | examples |
|---|---|
| wrong case on an altered planned phrase | „Dann hat er *den Bruder* die Milch gebracht.“ (planned *dem Bruder*) |
| a planned phrase jammed into a broken sentence | „In dieser Geschichte ist *ein Chef kocht* meistens perfekt.“ |
| unplanned two-way phrase | „Lukas ruft *in die* Praxis an.“ |
| present tense inside a past-tense story | „Plötzlich passierte etwas Seltsames: Der Verkäufer *weint* …“ · „Die Fahrt war anstrengend, denn der Fahrer *kommt* oft zu spät.“ |
| nonsense | „Er hat ein Geschenk. Es ist für eine Uhr.“ · „Sie kauft den Brief.“ · „…einen Kollegen, bei dem der Verkäufer kocht, wenn die Gäste hungrig sind.“ |

**The tense switch comes from the plan, not the teacher.** The prompt shows each subject phrase with
its verb conjugated in the present („der Verkäufer (Subjekt: der Verkäufer weint)“). At B1 the teacher
writes in the past and pastes the present-tense hint in verbatim. The check accepts *weinte* and *hat
geweint*; the prompt doesn't say so.

gemma's B1 stories are also longer, more coherent and more natural than Kolibri's („Er ist sehr nervös,
deshalb wacht er schon um fünf Uhr auf.“). Kolibri's A1 stories are telegraphic.

### Correction tail · Kolibri vs gemma-31B

Same 48 jobs (12 each of aux, imperativ, k2, negation; 8 rows asked per job, 65/35 fix/ok).

| | Kolibri, thinking off | gemma-31B |
|---|---|---|
| rows (per job) | 386 (8.0) | 387 (8.1) |
| fix / ok | 62 / 38 | 62 / 38 |
| no-op fix rows (`fix == student`) | **37 / 239 (15%)** | 9 / 239 (3.8%) |
| `validate_data.py` valid | **190 / 386 (49%)** | **338 / 387 (87%)** |
| top rejects | not a full sentence 80, identical 56, LanguageTool 26 | duplicate 35, identical 7, eval overlap 3 |
| time | 18 s | ~5 min |

Right shape, of the non-no-op fix rows (`kasus_bakeoff_report.py`'s token test: aux a haben↔sein switch,
k2 a changed Konjunktiv II form, negation a changed or moved nicht/kein, imperativ a change in the first
two words):

| phenomenon | Kolibri | gemma-31B |
|---|---|---|
| aux | 39 / 53 (74%) | **55 / 57 (96%)** |
| imperativ | 15 / 46 (33%) | **52 / 57 (91%)** |
| k2 | 19 / 42 (45%) | **57 / 58 (98%)** |
| negation | **59 / 61 (97%)** | 46 / 58 (79%) |

- **gemma-31B is the better tail teacher by a wide margin**: 87% valid vs 49%, a quarter of the no-ops,
  and right-shaped on aux, imperativ and k2 where Kolibri mostly isn't.
- Kolibri's wrong-shape rows pass the validator: aux „Ich haben … gelesen → Ich habe …“ (agreement, not
  the auxiliary); imperativ „Geh mal an die Tür → Geh mal in die Tür“ (makes it worse); „Hör mal, ich bin
  müde → Hör mal her …“ (nothing was wrong). This is the 26B-A4B failure mode again: valid data, wrong
  shape.
- Kolibri wins only on negation, and almost all of it is `nicht ein` → `kein`, the easy reading.
  gemma's remaining negation misses are word-order fixes around *nicht* that the token test can't see
  („nicht einverstanden mit dem Plan → nicht mit dem Plan einverstanden“), plus a few that aren't
  negation at all („mit keinem Grund → aus keinem Grund“).
- gemma's 62/38 matches the request here, unlike its 51/49 on the v4 jobs. Its 35 duplicates are
  repeats across jobs and are dropped.
- `check_batch_composition.py` fails on missing core phenomena, which is expected for a tail-only batch.

## Verdict

**Kolibri-1 is not a teacher for this project, for stories or the correction tail.** gemma-31B wins
every comparison:

| | Kolibri, thinking off | Kolibri, reasoning `low` (32k) | **gemma-31B** |
|---|---|---|---|
| stories passing the check | 71% | 89% | **93%** |
| planned phrases verbatim | 76% | 93% | **99%** |
| hand read: error / clean (of 20) | 9 / 3 | 7 / 4 | **5 / 7** |
| tail rows valid | 49% | — | **87%** |
| tail no-op fix rows | 15% | — | **3.8%** |
| tail right shape (aux · imperativ · k2) | 74 · 33 · 45% | — | **96 · 91 · 98%** |
| tokens per story | ~157 | ~8,900 | ~174 |

- **The dense-only rule holds.** A 3.46B-active MoE gives fluent but wrong-shaped correction rows (wrong
  phenomenon, fixes that make things worse) that pass the validator, the 26B-A4B failure again. Its
  stories carry more errors the check can't see.
- **Reasoning doesn't rescue it.** It closes most of the gap on the check's numbers at 55–85× the tokens,
  and very little of the gap a reader sees.
- What Kolibri does well: it's fast (306 stories in 30 s once served), it follows count and mix
  instructions exactly (8 rows per job, 62/38), and it handles `nicht ein → kein`. Not enough to
  matter here.
- 4c (pruning by expert routing) is moot: nothing to keep.

## What this means for the Kasus story slice

Even gemma-31B's passing stories aren't trainable as they are (5 of 20 with an error). Most of the
rest traces to the plan or to check gaps, so the next work is in the app, before any bulk GPU time:

1. **Planner** (`KasusStoryPlanner`, `kasus_triggers.json`): plausible preposition–noun pairs instead
   of random ones („für die Karte“, „unter einen Kühlschrank“); show the subject verb as a choice of
   tenses, or tell the prompt any tense is fine, so B1 past-tense stories don't paste in present-tense
   hints.
2. **Check** (`KasusStoryCheck` / `KasusHarvest`): reject a `triggerMissing` Wohin phrase in a clause
   with a Wo verb; treat sein as a Wo verb for the two-way rule; flag a double accusative; flag
   parenthetical meta-text and self-corrections. Auxiliaries and roles are bigger rules, for later.
   These protect learners too: a tutor-written story with these sentences reaches the reading screen
   today.
3. **A second gate** on passing stories before training: LanguageTool at least; an LLM judge if LT
   misses the auxiliary and two-way cases (test it on this drop's hand-read errors first).
4. Then bulk stories with **gemma-31B** (306 stories in 5.4 min on an H200 with transformers, so
   ~3,000 stories ≈ 1 h), through the tightened check and the second gate, then select and pack
   (`KASUS_STORY_DATA.md` §5).

For the correction tail, `DATA_GAP_PLAN.md` §3 stands with gemma-31B, and these 338 valid gemma rows are
a head start. That plan gives imperativ, k2 and negation to Sonnet for judgment. gemma-31B's 91–98%
right shape on imperativ and k2 here suggests it could take them too. Hand-read a sample before
deciding.

---

## Checklist

- [x] Kolibri stories, `reasoning_effort: medium` (starved; retry queued)
- [x] Kolibri correction tail
- [x] Kolibri reasoning retry, 32k budget, `low` + `medium`
- [x] gemma-31B stories (+ hand read)
- [x] gemma-31B correction tail
- [x] tail gates: `validate_data.py`, `check_batch_composition.py`, no-op rate
- [x] cost and the pod confirmed gone (`runpodctl pod list` empty)
