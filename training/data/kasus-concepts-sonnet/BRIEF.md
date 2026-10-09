# Brief: one-sentence case exercises for Die Kartei

(Round 2, 2026-10-07: new plans with curated wegen/trotz reasons. Round 1, on the old plans, is
kept in `round1/`.)

You are writing example sentences for a German-learning app's case exercises (Rollen, Wer macht
was?, Die Probe). English-speaking learners use them to understand Nominativ, Akkusativ, Dativ and
Genitiv, so a wrong sentence teaches something wrong. Correctness beats creativity.

The app has already decided every case and role. **You never choose a case.** You write one
sentence around the phrases you are given, keeping each phrase exactly as written.

## Input

Your chunk file, `training/data/kasus-concepts-sonnet/chunk_<N>.jsonl`, one JSON object per line:
`id`, `kind` (roles | wer | probe), `unit`, `level`, `user` (the German instructions for this
sentence: follow them exactly) and `plan` (the phrases, cases and allowed verb forms).

## What to write for each line

1. **The German sentence**, following the `user` instructions:
   - every listed phrase exactly as written, articles and endings unchanged (only the first
     letter may become a capital at the start of the sentence);
   - the verb in one of the listed forms only (no Perfekt, no other person, no added particle
     that makes a different verb: not „ruft … vorbei“, not „ruft … ein“);
   - if it says „Beginne den Satz mit …“, start with exactly that phrase. Those are object-first
     sentences („Den Hund jagt die Katze.“). Keep the order even when it feels unusual: that is
     the point of the exercise;
   - one main clause ending in a full stop: no comma, colon, semicolon, „und“, „aber“, „weil“ or
     any other joining word;
   - no other people or animals, no personal pronouns (ich, du, mich, dir, ihm …), no possessive
     in place of an article. You may add at most one short place or time phrase with a
     preposition („im Garten“, „nach der Arbeit“, „für ihre Hilfe“) or an adverb („heute“,
     „gern“). Only add what sounds natural with the verb, with the right preposition. Adding
     nothing is fine;
   - plain, natural German at the given level, with a situation that makes sense. With a
     „wegen“/„trotz“ reason, a short adverb often completes it („bleibt wegen des Regens zu
     Hause“, „kommt wegen des Staus spät“, „spielt trotz des Regens draußen“);
   - vary what you add across your lines: don't lean on „heute“ or „gut“, and adding nothing is
     often best.
2. **`english`**: a natural English translation of the whole sentence. For an object-first
   sentence, translate the meaning in normal English order („Den Hund jagt die Katze.“ → „The cat
   is chasing the dog.“). When two nouns would come out the same in English („die Freundin folgt
   dem Freund“), tell them apart („The girl follows her friend“ is wrong: no added possessives;
   use „the female friend“ / „the male friend“ or „the girlfriend“ where natural).
3. **`phrasesEnglish`**: the English for each planned phrase, in the same order as
   `plan.phrases`, each copied **exactly as it appears in your `english` line**, including
   capitals and any preposition („The father“, „the grandma“, „for the baby“, „because of the
   rain“). Every one must be a substring of `english`.
4. **`questionEnglish`**, only for `kind` = `wer`: the question „Who …?“ asking for the doer of
   the verb, always in the form „Who is …ing?“: „Who is chasing?“, „Who is helping?“, „Who is
   thanking?“ (the app shows the German „Wer <verb>?“ beside it).

## Output

Write `training/data/kasus-concepts-sonnet/out_<N>.jsonl`, one JSON object per input line, same
order:

```json
{"id": "...", "plan": <the plan object copied unchanged>, "raw": "SATZ: <German sentence>",
 "english": "...", "phrasesEnglish": ["...", "..."], "questionEnglish": "...", "model": "sonnet"}
```

Write the file with a short Python script using `json.dumps(..., ensure_ascii=False)` so every
line is valid JSON. Don't edit any other file.

## Check your work with the app's own gate

From the `training/` folder:

```bash
kasus_cli/build/kasus-cli concept-check data/kasus-concepts-sonnet/out_<N>.jsonl > data/kasus-concepts-sonnet/check_<N>.jsonl
```

The table goes to stderr; each line of `check_<N>.jsonl` has `passes`, `firstReject`, `codes`,
`errors` and `facts`. For every line that fails, read why, rewrite that sentence (and its English),
and run the check again. At most two rewrites per line; if it still fails, leave your last attempt
in the file. Never change a plan to make it pass.

What the codes mean:

| code | meaning |
|---|---|
| concept.phraseAltered | a planned phrase isn't there word for word |
| concept.verbMissing | the verb isn't in one of the listed forms |
| concept.orderIgnored | the sentence doesn't start with the phrase it had to start with |
| concept.notSimple | a comma, colon, semicolon or joining word |
| concept.extraPhrase / extraPerson | an added noun phrase without a preposition, or a pronoun |
| concept.extraUnproven | an added prepositional phrase the gate can't verify: drop it or pick a simpler one |
| concept.roleChanged / roleUnsure | a planned phrase sits right after a preposition or a noun |
| sentence.* or other codes | the app's grammar checks found a problem |

## When you're done

Reply with: lines written, lines passing the gate, and any plan you think is odd German in itself
(id and why). Keep the reply short.
