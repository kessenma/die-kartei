# Verstehen items written by Claude Sonnet (2026-10-07)

546 one-sentence items for Rollen, Wer macht was? and Die Probe: 42 per unit and exercise. Seven
Claude Sonnet agents wrote them around the app's own plans, so Sonnet never chose a case. Every
item passes the app's gate (`kasus-cli concept-check`). The export passes the same audit as the
bundled items (`kasus-cli audit-concepts candidates.json`: 546/546).

**Nothing is in the app yet.** The items go into `Resources/kasus_concepts.json` only after a
read.

## Files

| file | what |
|---|---|
| `review.csv` | every item: unit, exercise, German, English, the planned roles, what the writer added, the gate verdict; fill in `reads_right` (✓/✗) and `note` |
| `review.md` | the same, grouped by unit and exercise |
| `candidates.json` | the items in `kasus_concepts.json` format (ids `kc-s-…`) |
| `BRIEF.md` | the instructions the writers got |
| `prompts.jsonl`, `chunk_*.jsonl` | the plans (seeds 101–142) and how they were split across the seven writers |
| `out_*.jsonl`, `check_*.jsonl` | the writers' raw output and the gate's verdicts |
| `summary.json` | counts per unit and exercise |
| `genitiv/` | the Genitiv round: 30 Rollen, 30 Wer, 28 Probe, each with a Genitiv attribute („den Opa des Schülers“); its own review files |
| `round1/` | the first run, on plans with random wegen/trotz reasons. Grammatical but often nonsense („Der Lehrer sieht eine Gabel trotz des Sturms“), so the planner got curated reason frames and the batch was redone |

Rebuild the review files after any edit to `out_*.jsonl`:

```bash
.venv/bin/python scripts/kasus_concept_review.py data/kasus-concepts-sonnet --prefix s
```

## Claude's read (a first pass, not the verdict)

All 546 were read once. The German is correct throughout, and no case or role is wrong. 26 English
questions were normalized („Who is finding?“ → „Who finds?“, „Who is seeing?“ → „Who sees?“), and
one missing question was filled in.

Worth a close look, all grammatical but thin:

- **Akkusativ Rollen, „für“ + an animal**: „Der Opa findet den Vogel für den Chef“ (akk-roles 104,
  105, 109, 113, 117, 120, 142).
- **Dativ Rollen, „helfen … mit“ + a random thing**: „Die Chefin hilft dem Pferd mit der Gabel“
  (dat-roles 114, 116, 129).
- **Alle Fälle Rollen, „für“ chains**: „Der Sohn schickt dem Chef eine Jacke für den Mann“ (all the
  `für` items in that slot read as errands passed along).
- **Alle Fälle Rollen, „schenkt … wegen der Prüfung“ to someone who isn't a student**
  (alle-roles 111, 119, 121, 122, 130, 143).
- **Odd gifts in Dativ Rollen**: a pot, a spoon, a letter as a present (dat-roles 107–110).
- **Genitiv Wer macht was? holds no Genitiv** (gen-wer, all 42). The bundled Genitiv Wer items
  each carry a Genitiv attribute („Der Hund des Lehrers jagt die Katze“); the planner only gives
  Wer an Akkusativ or Dativ partner, and the gate refuses a planned phrase right behind a noun.
  These 42 are fine Wer items but not Genitiv practice. **Replaced** by the Genitiv round in
  `genitiv/`, where every item carries an attribute: leave the 42 out when merging.

- **The Genitiv here is only „wegen“ / „trotz“.** The bundle's most common Genitiv, the attribute
  („das Auto des Mannes“), appears nowhere in this batch, for the same reason as above. The
  Genitiv Probe mix is like the bundle's (15 of 42 Genitiv, the rest Dativ and Akkusativ to tell
  apart).

The fixes for the next batch, if there is one: plan „für“ only with things, „helfen mit“ only with
tasks, and the exam reason only for a student or a teacher.
