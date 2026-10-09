# Verstehen-item probe: can the tutors write case exercises?

Status: **measured 2026-10-06/07 on the Mac. Decided 2026-10-07: no on-device generation for now;
the bundle grows with items Claude Sonnet wrote through the same planner and gate (§7), after
Kyle's read.**

Question: the Grammatik case path's Verstehen exercises (Rollen, Wer macht was?, Die Probe) run on
124 hand-authored items (`german-ai-flashcards/Resources/kasus_concepts.json`). Could the
on-device tutors write more of them without teaching a wrong case?

The tutors are known to be weak at cases. The 2026-09-25 story probe (`docs/KASUS.md`, „Mac probe“)
kept only about a third of planned phrases verbatim and self-labelled cases 0–33% right. So the
tutor gets **one narrow job**: write one sentence around phrases the app already picked. The app
decides every case and role; the tutor never labels anything. The gate then proves each asked
phrase from its form, or from the frame the app planned.

Inputs, outputs and the report: `results/kasus-concept-probe/` (prompts, raw outputs per model,
`verdicts.jsonl`, `summary.json`, `hand_read_<model>.md`), with the summary copied to
`results/kasus-concept-probe_2026-10-07.json`.

---

## 1. Setup

| | |
|---|---|
| plans | 130 from `kasus-cli concept-prompts all:all:1-10`: Rollen 5 units × 10, Wer 4 × 10, Probe 4 × 10; distinct per exercise and unit |
| samples | 2 per plan per model (`--repeats 2`), seeded `plan seed + 1000 × repeat`: 260 per model, 1,040 in all |
| models | the four shipped tutors: E4B v4 (hero), E2B v1, Granite 4.1 3B v4, Granite 3.3 2B v4, all MLX 4-bit from HF |
| sampling | the app's: system + user chat, `enable_thinking=False`, temperature 0.75, top_p 1, 96 max tokens; `mlx_lm.generate` in process (never `mlx_lm.server`) |
| hardware | M1 Max 32 GB; median 0.4–0.8 s per sentence on the Mac |
| baseline | each plan's template sentence („Den Hund jagt die Katze.“), no model, through the same gate |

Reproduce, from `training/`:

```bash
kasus_cli/build.sh
kasus_cli/build/kasus-cli concept-prompts all:all:1-10 > results/kasus-concept-probe/prompts.jsonl
.venv/bin/python scripts/kasus_concept_probe.py --model all --repeats 2
.venv/bin/python scripts/kasus_concept_report.py
```

## 2. The pipeline (the app's own Swift, compiled into `kasus_cli`)

| piece | file | does |
|---|---|---|
| plan | `Models/KasusConceptPlan.swift`, `Services/KasusConceptPlanner.swift` | seeded: the phrases (article, noun, case, role), one shared verb with its allowed forms (er/sie/es present and past only), which phrase opens a Wer sentence, which phrase a Probe asks |
| prompt | `Services/KasusConceptPrompt.swift` | „Schreibe genau einen deutschen Satz …“, the phrases with plain role words (wer handelt / wen oder was / wem), the verb forms, „Beginne den Satz mit …“, may add a place, time or prepositional phrase but no person, no subordinate clause, no „und“; answer `SATZ: …` |
| gate | `Services/KasusConceptCheck.swift` | below |
| CLI | `kasus_cli/concepts.swift` | `concept-prompts`, `concept-check [--template]`, `audit-concepts` |
| tests | `german-ai-flashcardsTests/KasusConceptGenerationTests.swift` | planner determinism and coverage, every template passes, the prompt is clean, one fixture per reject code |

**The gate**, in order. Anything but `formatMissing` rejects.

| code | catches |
|---|---|
| `concept.empty`, `concept.notOneSentence` | nothing usable; two sentences |
| `concept.phraseAltered` | a planned phrase not there word for word: a changed article (a moved case), a possessive swap, a dropped phrase |
| `concept.verbMissing` | the verb not in a planned form („Der Bruder lachen“, „rufte“) |
| `concept.orderIgnored` | a Wer sentence not opening with the phrase asked for |
| `concept.roleUnsure` | a planned der/des/einer/eines phrase right behind a noun, where it reads as a Genitiv attribute |
| `concept.roleChanged` | a planned bare phrase right behind a preposition („sah in den Spiegel“ for the object „den Spiegel“) |
| `concept.notSimple` | a comma, colon, semicolon or conjunction: a second clause, or a label left on („Erklärung: …“) |
| `concept.extraPerson` | an added personal pronoun („ruft dich an“) |
| `concept.extraPhrase` | an added article phrase with no preposition: another subject or object |
| `concept.extraUnproven` | an added prepositional phrase whose case the form and preposition can't prove („am Wochenende“, „zum neuen Job“ with a noun the lexicon lacks) |
| `concept.ambiguousRoles` | two planned phrases whose article fits several cases (only word order would tell them apart) |
| validator + facts | wrong forms, a preposition wanting another case, the `sentence.*` checks; the Wer clue proven by form, the Probe phrase really ambiguous |

Proven prepositional additions („für ihre Hilfe“, „im Garten“) are allowed. They become validated
targets that are never asked (Rollen's `ask` lists only the planned phrases).

**Why an ambiguous phrase may be graded here** when a tutor-written story never grades one: its
label is the app's plan, not the tutor's, and the frame fixes who is who. One simple clause, one
verb, a subject the form proves and one more phrase: that phrase *is* the verb's partner („Der
Vater fragt die Schwester“). The planner never plans two ambiguous bare phrases, and the gate
refuses a sentence that has them.

## 3. Results

Pass = the gate's verdict on one sample. "bare" = passes with nothing added (the strict variant).
The families split the first reject: **german** = a moved article, possessive, dropped phrase,
wrong verb form, validator error; **instr.** = order, extra clause, extra phrase or person;
**unprov.** = an added phrase the gate couldn't vouch for.

| model | exercise | n | pass | bare | verbatim | Wer order | german | instr. | unprov. |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| template | all | 130 | **130 (100%)** | 130 | 100% | 40/40 | 0 | 0 | 0 |
| E4B v4 | Rollen | 100 | 80 (80%) | 57 | 93% | – | 10 | 3 | 5 |
| | Wer | 80 | 47 (59%) | 7 | 79% | 70/80 | 18 | 8 | 7 |
| | Probe | 80 | 55 (69%) | 9 | 86% | – | 12 | 4 | 9 |
| | **all** | 260 | **182 (70%)** | 73 | 87% | 70/80 | 40 | 15 | 21 |
| E2B v1 | Rollen | 100 | 78 (78%) | 65 | 81% | – | 19 | 2 | 1 |
| | Wer | 80 | 38 (48%) | 15 | 66% | 77/80 | 27 | 6 | 9 |
| | Probe | 80 | 47 (59%) | 27 | 75% | – | 22 | 2 | 9 |
| | **all** | 260 | **163 (63%)** | 107 | 75% | 77/80 | 68 | 10 | 19 |
| Granite 4.1 3B v4 | all | 260 | **102 (39%)** | 66 | 57% | 58/80 | 118 | 19 | 21 |
| Granite 3.3 2B v4 | all | 260 | **43 (17%)** | 31 | 28% | 58/80 | 199 | 13 | 5 |

Granite per exercise (pass): 4.1 Rollen 47%, Wer 28%, Probe 41%; 3.3 Rollen 17%, Wer 16%, Probe 16%.

**Plans that yield an item** (the app would retry once; a plan counts when either of its first two
samples passes):

| model | Rollen | Wer | Probe | all |
|---|---|---|---|---|
| E4B v4 | 78% → **90%** | 60% → **72%** | 70% → **88%** | 70% → **84%** |
| E2B v1 | 82% → 88% | 40% → 62% | 60% → 82% | 62% → 78% |
| Granite 4.1 3B | 46% → 60% | 25% → 42% | 38% → 60% | 37% → 55% |
| Granite 3.3 2B | 20% → 32% | 22% → 25% | 20% → 22% | 21% → 27% |

**What the tutors did to the planned phrases** (rejects only; one sentence can have several):

| model | case moved („der Vogel“ → „den Vogel“) | possessive („die Tochter“ → „seine Tochter“) | phrase dropped |
|---|---:|---:|---:|
| E4B v4 | 18 | 15 | 3 |
| E2B v1 | 17 | 31 | 24 |
| Granite 4.1 3B | 43 | 21 | 76 |
| Granite 3.3 2B | 39 | 52 | 172 |

## 4. The hand read: what passed but reads wrong

The checks alone aren't enough. The Kolibri bake-off found 5 wrong in 20 of gemma-31B's
*passing* stories. So every distinct passing sentence was read once by Claude (a first pass, not
the verdict). The sheets `results/kasus-concept-probe/hand_read_<model>.md` hold 20 random
passes per model for Kyle's own read, which is the number that counts.

| model | passes read | **case or role wrong** | wrong German elsewhere | examples |
|---|---:|---:|---:|---|
| E4B v4 | 182 | **0** | 3 | „fragte die Tochter vom Projekt“, „ruft … in die Besprechung ein“, „antwortete der Mutter auf den Tisch“ |
| E2B v1 | ~150 distinct | **0** | ~5 | „ruft die Schwester vorbei“ (×2), „heute abends“ (×2), „holt die Jacke nicht in der Tasche“ |
| Granite 4.1 3B | ~90 distinct | **1** | ~2 | „Die Tochter sieht den Rucksack … tragen“ (den Rucksack becomes the subject of tragen); „weint tröstlich“ |
| Granite 3.3 2B | ~40 distinct | 0 | ~2 | „fragt die Tochter über ihren Urlaub“, „folgt dem Freund zu seinem Zuhause“ |

Plus one Granite 3.3 item that passed with its label on („Erklärung: Der Chef nimmt …“). The gate
now rejects colons; that item and the table above reflect the fix.

Many passing sentences are grammatical but odd, mostly because of the plan's own pairings
(„Die Oma sieht den Fisch wegen des Fiebers“): the Genitiv reasons are random nouns, and the
templates share the oddness.

## 5. What it showed

1. **The gate holds where it matters.** No E4B or E2B pass mislabels a case or a role. Every case
   the tutors moved (35 between them) was caught, as were the possessive swaps, wrong verb forms
   („rufte“, „Der Schüler antwortet die Frau“, „antwortet auf die Tochter“) and order swaps.
2. **Wrong German that gets through lives in what the tutor adds.** All E4B and E2B slips sit in an
   added place, time or particle, never in a planned phrase. A strict variant (nothing added)
   would remove them, at a cost: E4B's bare passes fall from 182 to 73, and Wer from 47 to 7,
   because the tutor almost always adds something.
3. **Wer macht was? is the weak exercise.** It asks for object-first order with an ambiguous
   subject („Den Chef sucht die Tochter“). E4B keeps the order in 70 of 80, but it often "fixes"
   the clue so the sentence reads subject-first („der Vogel“ → „den Vogel“). That is the
   English-speaker's error too, and exactly what the exercise exists to drill.
4. **rufen is a trap verb.** The tutors add particles („an“, „ab“, „vorbei“, „ein“): an and ab
   are fine German, vorbei and ein aren't. A verb list without separable cousins would avoid it.
5. **The Granites aren't fit for this job.** They drop or rewrite most planned phrases (172 drops
   for Granite 3.3), answer in the first person („Ich besuche meine Tochter“), and Granite 4.1
   produced the only role error. With one retry they yield 55% and 27% of plans.
6. **Templates already pass 100%**, and every sentence is plain, correct German. What a tutor
   adds is variety and a more natural sentence, not correctness.

Gate blind spots still open:
- A second verb that changes a phrase's role („sieht den Rucksack … tragen“): an infinitive at the
  end isn't checked.
- Wrong prepositions in additions („fragte … vom Projekt“, „über ihren Urlaub“), and nonsense
  that's grammatical („auf den Tisch“). The validator proves a preposition's case, not that the
  preposition fits the verb.
- Semantics: a baby looking for a driver, a cat chasing a dog. For Wer macht was? that's partly
  the point.

Caveats: these are Mac numbers through Python mlx_lm, a stand-in for the phone. The plans are
seeds 1–10, now a development set the gate was tuned on: a fresh run on other seeds should
confirm. 2 samples per plan is small, so read ±3 points as noise. The tokenizer loaded with
transformers' "incorrect regex pattern" warning; the app tokenizes in Swift, so this doesn't
match the device exactly.

## 6. Decision (open: Kyle's call after the hand read)

The options as they stand:

1. **Ship E4B-written items behind the gate, templates as the fallback.** One retry yields about
   84% of plans; the rest play the template. Allowing additions keeps the sentences natural,
   with about 1 in 60 passes holding a slip in an added phrase. E2B is close (78%) for the
   memory-saver tier. The Granite tiers would get templates only.
2. **The strict variant**: the same, but nothing added. No slips seen at all, far fewer tutor
   items (Wer almost never), so templates carry most of it.
3. **Templates only, no AI.** 100% correct and deterministic today; less variety.
4. **Train first.** This probe makes the data cheap: the planner and gate produce verified
   plan-to-sentence pairs for every case. A teacher (or E4B itself, rejection-sampled on the Mac
   with no GPU) writes sentences for thousands of plans; only gate passes become training rows,
   weighted toward Wer and object-first order. Re-probe on fresh seeds. Risks: the E2B
   capacity-dilution lesson (breadth breaks ≤2B tunes), and a fine-tune can't add German the base
   lacks (the Granite bases). A small slice mixed into the next E4B round is the low-risk form.

If anything ships, Step 4 of the plan applies: Kasus Lab numbers on a device first (DeviceHub),
a developer toggle off in Release, rounds marked „KI“, generated items never moving the coach.

## 7. The Sonnet batch (2026-10-07)

Kyle chose to grow the bundled set offline instead: grammar this basic needs a high share of
correct items, and every bundled item can be read before it ships. Seven Claude Sonnet agents
wrote one sentence each around 546 fresh plans (seeds 101–142, 42 per unit and exercise), with
the same prompt rules plus an English line, each phrase's English and, for Wer, the question in
English (`data/kasus-concepts-sonnet/BRIEF.md`). They ran the gate themselves and rewrote what
failed, at most twice.

| | |
|---|---|
| gate | 546 of 546 pass (most first try; rewrites were almost all `extraUnproven` time phrases like „am Abend“) |
| export | `kasus-cli concept-export` → `candidates.json`, 546 items in the bundle's format; `audit-concepts` on it: 546/546 |
| Claude's read | German correct throughout, no wrong case or role; thin pairings listed in the batch README |
| wall clock | about two minutes per round, seven agents in parallel |

**Round 1 was thrown away.** The planner's random wegen/trotz reasons and errands made
grammatical nonsense („Der Lehrer sieht eine Gabel trotz des Sturms“, „Das Kind trinkt den
Wein“, „Das Baby kocht“). The planner now draws reasons from curated frames
(`intransitiveReasons`, `objectReasons`, `givingReasons` in `KasusConceptPlanner`), never plans
wine, beer or the baby, and in Alle Fälle plans „für“ only after handing-on verbs (geben, bringen,
schicken). That also changed the plans
behind §3, whose outputs stay as recorded.

**The Genitiv round.** The main batch's Genitiv was only „wegen“/„trotz“, and its 42 Genitiv Wer
items held no Genitiv at all. The plan now carries the Genitiv attribute: a phrase with reason
`attribute` and a `head` (the phrase it follows, „den Opa des Schülers“). The prompt shows the
two as one block with „… sagt, wessen Opa“; the gate finds the attribute only directly behind its
head (moved elsewhere it is `phraseAltered`), skips the „behind a noun“ check for it, and leaves it
out of the two-ambiguous-phrases rule, since its place settles it. Possessors come from a table of
plausible relations. A Genitiv Wer plan always has one; Rollen and Probe plans in the Genitiv unit
have one half the time (the Probe's is der + feminine, asked with „des Mannes“). 88 items, all
passing (`data/kasus-concepts-sonnet/genitiv/`), replace the 42.

Open before anything ships: Kyle's read of both `review.csv` files; leaving out the main batch's
42 Genitiv Wer items; then merging into `Resources/kasus_concepts.json` with the
golden numbers in `KasusConceptFixtures` and its tests updated. New tools: `kasus-cli
concept-export`, `kasus-cli audit-concepts <file>`, `scripts/kasus_concept_review.py`.
