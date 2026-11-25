# past_tense_verbs.json — Perfekt examples from Tatoeba

Produced by `training/scripts/past_tense_review.py` (seed 7). Regenerate rather than hand-edit: a bad sentence means a bad *rule*, and the
rule lives in that script.

## Why

The examples in this file were built by DeepL round-trips and about 70% were defective:
173 did not contain their own participle (`"Gestern habe ich Buche."` for *buchen*) and a
further 234 were nothing but an auxiliary and a participle (`"Ich habe benutzt."`). Sixteen
`pastParticiple` values were not German at all — `gewiederholt`, `geregnt` — and six
`auxiliary` values were contradicted by the corpus.

Generating replacements would need per-verb valency data this repo does not have. Retrieving
them needs none: a real sentence already satisfies its verb's frame.

## What ran

- corpus: `training/data/raw/deu_sentences.tsv` — Tatoeba, CC-BY 2.0 FR, 773,911 sentences
- 348/374 verbs got a spaCy-verified, LanguageTool-clean Perfekt clause
- 277 have five or more candidates, so a rejected pick has somewhere to fall
- field corrections applied as code: {'participle': 15, 'auxiliary': 6, 'infinitive': 1}

## Files

| file | what |
|---|---|
| `review.csv` | the sheet to read — see `review.md` for the strata |
| `review.md` | what to read and how |
| `picks.json` | `infinitive -> {tatoeba_id, score, rank}`, the provenance of record |
| `summary.json` | the numbers above |

## Merging

```bash
training/.venv/bin/python training/scripts/past_tense_review.py --merge --dry-run
training/.venv/bin/python training/scripts/past_tense_review.py --merge
python3 scripts/check_content.py --write-baseline   # past_tense should fall to ~0
```

Attribution for Tatoeba is in `Features/Settings/SourcesView.swift`; the regression net is
`german-ai-flashcardsTests/PastTenseVerbAuditTests.swift`.
