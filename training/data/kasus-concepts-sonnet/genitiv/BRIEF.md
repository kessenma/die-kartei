# Brief: Genitiv round (2026-10-07)

Read `../BRIEF.md` first. Everything there applies: the input and output format, the rules for the
German sentence, the English line, the gate and the rewrites. Only the paths differ: your files are
in `training/data/kasus-concepts-sonnet/genitiv/` (`chunk_<N>.jsonl` → `out_<N>.jsonl`, checked
into `check_<N>.jsonl`), and the gate command is

```bash
kasus_cli/build/kasus-cli concept-check data/kasus-concepts-sonnet/genitiv/out_<N>.jsonl > data/kasus-concepts-sonnet/genitiv/check_<N>.jsonl
```

## What's new: the Genitiv attribute

Every plan here has one phrase with `"reasonRaw": "attribute"` and a `head`: the index of the
phrase it belongs to. The `user` instructions show the two together, e.g. „den Opa des Schülers
(wen oder was; „des Schülers“ sagt, wessen Opa)“.

- Keep the attribute **directly behind its noun**, as one block: „den Opa des Schülers“. Never
  split them, never move the attribute elsewhere, never swap it for „von“ + Dativ („vom Schüler“)
  or a name with -s („Peters“).
- If you must start with a phrase, start with the whole block: „Den Hund des Lehrers jagt die
  Katze.“
- Where the attribute is „der“ + a feminine noun („der Lehrerin“), it is Genitiv only because it
  stands behind a noun. Don't put anything between the two.
- Make the relation make sense: the dog belongs to the teacher, the doctor treats the grandpa.

## English for an attribute

Use the English possessive with 's (or s'): „Den Opa des Schülers kennt die Verkäuferin.“ → „The
saleswoman knows the student's grandpa.“ In `phrasesEnglish`, give the head and the attribute
separately, in `plan.phrases` order, each copied exactly from your `english` line: the head
without the possessive („grandpa“) and the attribute with it („the student's“). Both must be
substrings of `english`. Mind capitals at the start of the English sentence („The teacher's dog
is sleeping.“ → „The teacher's“, „dog“).
