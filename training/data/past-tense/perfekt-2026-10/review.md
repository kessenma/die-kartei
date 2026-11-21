# Perfekt examples, 2026-10

Seed 7. 348/374 verbs have a spaCy-verified, LanguageTool-clean Perfekt sentence from Tatoeba (CC-BY 2.0 FR).

Read the rows with `to_read = yes` in `review.csv`. You never write German: tick
`reads_right = y`, or put `1`-`4` in `picked_alt` to promote an alternate, or `n` to
leave the verb without an example. A bad *rule* is fixed in the script and the sheet
regenerated -- never hand-edit the bundle.

| stratum | verbs | why |
|---|---|---|
| `A:auxiliary-fixed` | 4 | auxiliary contradicted by the corpus |
| `A:modal` | 6 | Ersatzinfinitiv, example forced to null |
| `A:no-evidence` | 20 | no Perfekt clause in 773,911 sentences |
| `A:participle-fixed` | 13 | participle was corrupt in the file |
| `A:thin` | 38 | only 1-2 candidates survived the gate |
| `B:bulk` | 231 | clean bulk; a seeded sample is read to bound the error rate |
| `C:incumbent` | 62 | the shipped sentence won; already in the app, no read needed |

**181 rows to read.**

