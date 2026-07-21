# Generated training data

Raw teacher-generated candidates land here as `<batch>.jsonl`; `validate_data.py`
splits each into `<batch>.valid.jsonl` (training pool) and `<batch>.rejected.jsonl`
(with reasons). Never edit `.valid.jsonl` by hand — fix the generator or validator
and re-run.

## Correction-task schema (one JSON object per line)

```json
{"task": "correction",
 "phenomenon": "vmp | sep | refl | dawo | aux | verdict | adjend | artikel",
 "level": "A1 | A2 | B1 | B2 | C1",
 "formality": "du | Sie",
 "partner": null,
 "student": "Ich interessiere mich auf Musik.",
 "verdict": "fix",
 "fix": "Ich interessiere mich für Musik.",
 "why": "'sich interessieren' takes the preposition 'für'.",
 "meta": {"verb": "interessieren", "prep": "für"}}
```

- `verdict: "ok"` items have `fix: null, why: null` — these train verdict discipline.
- `partner` is an optional preceding line of dialogue (needed for person-vs-thing
  da-compound items).
- `meta` carries whatever the validator can structurally check (`verb`, `prep`,
  `aux`, `subtype`).
- At packing time (Phase 4) these render into the app's exact correction prompt
  (`ConversationPrompts.correctionSystemPrompt` format: system + user → `OK` or
  `FIX:`/`WHY:`), with `level`/`formality` substituted into the system prompt.

## Provenance & license notes

Seed sentences may derive from Tatoeba (CC-BY 2.0 FR — attribution: tatoeba.org).
Teacher-generated content is original. Keep eval items (data/eval/) strictly out —
the validator enforces this.
