# Vocabulary example sentences — the screener

A plan, not a built thing. It answers one question: **how do you fill ~3,300 missing example
sentences when you are not a native speaker and cannot pay for a review pipeline?**

## Where the field stands

`Resources/a1_vocabulary.json`, `a2_vocabulary.json` and `b1_vocabulary.json` carry a `example`
field next to each Goethe headword. After the 2026-10 cleanup (`scripts/clean_vocab_examples.py`):

| list | entries | with an example | empty |
|---|---|---|---|
| A1 | 585 | 583 | 2 |
| A2 | 1209 | 256 | 953 |
| B1 | 2358 | 0 | 2358 |

B1 never had any. A2's were scraped out of the Goethe PDFs and most of what came back was
wreckage — a Perfekt form from the next column glued to the front (`"hat abgeholt Wir müssen noch
meinen Bruder abholen."`), bare fragments (`"ich Zeit."`), page furniture (`"9WORTLISTE"`). The
cleanup repaired 69, dropped 110 and kept 188. Nothing was invented.

**Empty is the honest state, not the finished one.** A learner seeing no example is better served
than one seeing `"9WORTLISTE"`, but a B1 deck with no example sentence anywhere is a real gap.

## The approach that works: retrieve, don't generate

Settled by `past_tense_verbs.json`, repaired in the same pass. Writing German needs per-verb
valency data that does not exist in this repo; **retrieving real German needs none, because a real
sentence already satisfies the word's frame.** `training/scripts/past_tense_review.py` got
348/374 verbs a spaCy-verified, LanguageTool-clean Perfekt clause out of
`training/data/raw/deu_sentences.tsv` (773,911 sentences, Tatoeba, CC-BY 2.0 FR). Copy that
script; do not start from scratch.

Two of its gate rules were learned the expensive way and are worth copying verbatim:

- **Check vocabulary against the Goethe lists, not `wiktionary_de.db`.** The dictionary knows
  every word, so `"Der Finanzminister hat seinen Rücktritt angeboten."` sailed through as an A2
  example. Restricting to the 2,791 Goethe headwords cost 3 verbs out of 354 and fixed the
  register problem outright — the same sentence became `"Man hat mir deine Stelle angeboten."`
- **Require the sentence to teach something.** A candidate made only of an auxiliary, a pronoun
  and the target word passes every grammatical check and is worthless: 23 of the old DeepL
  templates (`"Gestern habe ich geliefert."`) survived the first gate for exactly that reason and
  won on the incumbent tie-break.

### Coverage is already measured — it is good

Surface-form hits in learner-length (4–12 word) Tatoeba sentences, for the headwords that need an
example:

| list | needs one | ≥1 candidate | ≥5 | ≥20 |
|---|---|---|---|---|
| A2 | 953 | 933 | **923 (97%)** | 873 |
| B1 | 2358 | 2278 | **2153 (91%)** | 1842 |

That is an upper bound: it counts the exact surface form, so it misses inflected occurrences
(helping) and ignores the gate (hurting). The verb run lost about 6% of its verbs to the gate, so
budget for roughly **85–90% of B1 fillable**, with a tail of 200–350 words needing a hand-written
sentence or staying empty.

### The gate

Reuse `past_tense_review.py`'s, with the headword-specific parts swapped:

1. The headword occurs, as an inflected form of the right lemma — spaCy `token.lemma_`, not a
   substring match (`Rat` must not match `Berater`).
2. Its POS matches the entry's `wordType`. The lists mark `nomen` / `verb` / `adj` / `adv`, so a
   noun entry must be matched by a `NOUN` token.
3. For a noun, the article the sentence uses agrees with the entry's `article`. This is the only
   check here the verb run did not need, and it is free — `KasusForms` and `wiktionary_de.db` both
   already do it, and `scripts/check_content.py` has the lookup.
4. LanguageTool zero matches, same predicate as `training/scripts/validate_data.py:384`.
5. 4–9 content tokens, one clause, no proper nouns.
6. **Every content lemma inside Goethe A1∪A2∪B1 ∪ the entry's own level.** This was the highest
   value rule in the verb run and matters more here: a B1 example full of C1 vocabulary teaches
   the wrong word.
7. Not a near-duplicate of another entry's example.

Ranking, not rejection: headword late in the sentence, 5–8 tokens, concrete over abstract,
penalise questions and proper nouns.

### The sample a human reads

Not 3,300 sentences. Stratify and read **~80 per stratum**, which puts the 95% upper bound on a
stratum's error rate near 4% when nothing fails.

- **A — census.** Every word where the gate fell through to a lower rank, every word with ≤2
  candidates, every word whose article the dictionary could not confirm. A few hundred at most,
  and these are where errors actually live.
- **B — seeded random sample**, stratified by level (A2, B1) and word type (noun, verb, adj/adv).
  ~80 each, so ~480 reads total across six strata.
- **C — zero reads.** Nothing: unlike the verb run there is no incumbent to defend.

If more than ~3 fail in a stratum, **change a gate rule and regenerate** — never hand-patch the
output. That rule is what keeps this from turning into the pipeline you cannot afford.

### The review sheet

`review.csv`, the shape `training/scripts/gap_review.py` already writes, with four alternates per
row so a rejection costs one keystroke instead of a composition. **The reviewer never writes
German.** Columns:

`word · article · wordType · level · english · candidate · alt1..alt4 · stratum · reads_right ·
natural · picked_alt · note`

`reads_right` and `natural` must stay separate columns. "Is this correct German?" and "would
anyone say this?" are different questions — `"Stark! Hast du dich vor dem Laufen richtig
aufgewärmt?"` is flawless and nobody says *Stark* any more. Collapsing them into one column is
what makes a review sheet useless, because a reviewer who means "correct but odd" has nowhere to
put it.

Who can read it: the Preply tutor, the Deutschkurs teacher, the group chat. All of them will read
80 sentences. None of them will read 3,300. Scope the ask accordingly.

## If you do build it

- `training/scripts/vocab_example_review.py`, batch folder
  `training/data/vocab-examples/<level>-<yyyy-mm>/`.
- Per-row provenance in the shipped file: `exampleSource` only (`tatoeba` / `authored`), with
  `picks.json` in the batch folder as the source of truth. Do **not** add a per-row `reviewed`
  block — `kasus_stories.json` has one on all 7 stories and all 7 are empty strings.
- Tatoeba is CC-BY 2.0 FR. `Features/Settings/SourcesView.swift` must credit it.
- `scripts/check_content.py` already lints this field; re-baseline after a merge.
- A What's New bullet: a B1 deck gaining example sentences is learner-visible.

## Out of scope

Corpus-frequency naturalness scoring (DWDS, Leipzig). It is the obvious next idea and the wrong
one to start with: false alarms are high on A1–B1 material, and the sample read in stratum B tells
you whether naturalness is even the dominant defect. Measure first.
