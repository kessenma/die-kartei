# Reflexive items from the planner (reflexiv-2026-10)

Planned by `kasus-cli gap-plans` from the tables in `ReflexivForms.swift` (seed 7), gated by `gap-check`, exported by `gap-export`, audited by `audit-gaps`. No model wrote any of the German.

**Nothing is in the app until it has been read.** Fill in `reads_right` and `note` in `review.csv`; a ✗ names a table row to fix, then rerun:

```bash
python3 scripts/gap_review.py data/gap-choice/reflexiv-2026-10 --focus case:120 person:100 --seed 7
```

When the read is clean, `--merge` appends `candidates.json` to `Resources/gap_choice_items.json` and prints the golden rows for `GapChoiceFixtures.golden`.

## Read (2026-10-10)

Kyle skimmed `review.csv` and approved the batch without marking rows; Claude read every one of
the 219 sentences with their English twins. Two table rows were wrong, nothing in case or
agreement:

- **sich treffen** is reciprocal: „Ich treffe mich im Park“ needs a „mit …“. The verb is now
  plural-only (`numbers: [.pl]`), so it appears with wir, ihr and sie.
- **sich die Nase putzen** is right, but the verb's English pattern („brush“) made „I brush my
  nose“. Nase left putzen's pool; Zähne stays.

Regenerated with the same seed (213 items: 113 case + 100 person), merged into
`Resources/gap_choice_items.json` (229 with the 16 hand items), golden rows pinned in
`GapChoiceFixtures`. Read as acceptable although not perfect: a distributive singular with a
plural subject („Wir ziehen uns den Mantel aus“ → „We take off our coat“), and „sich duschen“,
which Duden allows beside plain „duschen“.
