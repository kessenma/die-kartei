# Grammatik — the case path and the Kasus stories

One path through the four cases, Nominativ → Akkusativ → Dativ → Genitiv → Alle Fälle, where
every unit runs the same loop: **Regel → Geschichte (Lesen → Finden → Einsetzen → Ergebnis) →
Schnellrunde**. The stories are the two exercises from a German class on one text: mark the cases,
then fill in the articles. A deterministic validator is the answer key; it gates the bundled
stories now and will gate the tutor's stories later (Phase 3).

Status legend: ✅ done · ⬜ open

## Where things live

| Piece | File |
|---|---|
| Units (cases in play, brushes, level labels, rule lines, start unit) | `Models/KasusUnit.swift` |
| Story format (stored fields, reasons, located targets) | `Models/KasusStory.swift` |
| Forms engine (determiner families, table lookups, options, slips, noun endings, word lists) | `Models/KasusForms.swift` |
| Validator (locate, prove, issue codes, policy) | `Services/KasusValidator.swift` |
| Explanations, built from the proof only | `Services/KasusExplanation.swift` |
| Loader, `AppKasusLexicon`, the DEBUG assert | `Services/KasusStoryBank.swift` |
| Planted-error fixtures, golden numbers, table round trip (DEBUG) | `Services/KasusFixtures.swift` |
| Sessions, blanks, grading, `recordRound`, progress, `KasusPath` (the hero) | `Services/KasusService.swift` |
| The round record | `Models/KasusRound.swift` |
| Bundled stories | `Resources/kasus_stories.json` |
| Hub | `Features/Grammar/GrammarHubView.swift` |
| Unit screen, story player, story text, Kasus-Check card | `Features/Grammar/Kasus/` |
| Endings table + Schnellrunde (`CaseEndingsDrillView`) | `Features/Grammar/CaseEndingsView.swift` |
| Day detail in the calendar | `Features/Home/StreakCalendarView.swift` |

## The path

| Unit | Cases in play | Finden brushes | Label |
|---|---|---|---|
| Nominativ | nom | nom | A1 |
| Akkusativ | nom, akk | akk | A1 |
| Dativ | nom, akk, dat | nom, akk, dat | A1–A2 |
| Genitiv | all | all | B1 |
| Alle Fälle | all | all | B1 |

**Entry.** Home ▸ Grammar pushes the hub directly, and so does the pyramid's Grammatik-Kern
layer. The hub has three sections: **Weiter** (one hero row), **Die vier Fälle** (a row per unit,
with a dot per story, filled once its Finden and Einsetzen are both played, one for the
Schnellrunde, and a flame on a case the coach has as shaky) and **Werkzeuge** (Präpositionen,
Der · Die · Das, Die Endungen). A unit screen has **Die Regel** (open until the unit's first
round), **Geschichten** (one row per story: level, Finden ✓/○, Einsetzen ✓/○) and the
**Schnellrunde**, the endings drill limited to the unit's cases.

Levels are soft labels, never gates. The hub's **Weiter** row (`KasusPath.next`) is derived on
every render and never stored. First rule that fits:

1. a shaky akk/dat/gen case whose unit has a story → its least-recently-played story (Lesen if
   never played, else Einsetzen);
2. an unplayed story, from the start unit on;
3. the first unfinished step from the start unit (Finden, Einsetzen, then the Schnellrunde);
4. the story played longest ago ("Wiederholen").

The start unit comes from `germanLevel` (A1 → Nominativ, A2 → Akkusativ, B1+ → Dativ) and is never
written back.

**Der Kasus-Check** (the "?" in the hub and the player) is the decision order every explanation
follows: preposition in front → hangs on another noun (Genitiv) → grammatical subject → what a
main-verb sein/werden/bleiben/heißen equates with the subject → receiver or Dativ verb →
otherwise Akkusativ. The traps get their own line: gefallen/gehören/schmecken turn the roles
around, and fragen/anrufen/besuchen take the Akkusativ although they feel like they have a
receiver.

## The story format

Plain prose in paragraphs `{de, en}`. Targets are stand-off annotations **in reading order**: the
validator finds each phrase verbatim, on word boundaries, walking forward from the previous one.
No offsets, no markup.

Per target, authored facts only: `phrase` (determiner + noun, no adjectives yet), `case`,
`genus` (m/f/n/pl), `lemma` (the singular, always), `reason`, `trigger`. Per story: `id`, `unit`,
`level`, `source` (authored/generated), `reviewed {by, date}`, `title`/`titleEnglish`,
`question {de, en, options, answer}` (the player shuffles the options), `notTargets [{phrase,
why}]`, `paragraphs [{de, en}]`, `targets`.

`notTargets` lists every article word the coverage rule should let through, verbatim and in no
particular order. `why` is one of `pronoun` („Ich kaufe ihr neue Schuhe“: „ihr“ is „to her“, not
an article), `demonstrative`
(dieser, jeder, welcher until Phase 2), `relative` (a relative „der“), `idiom` („am besten“) or
`contraction` (am, im, ins, zum… until contractions can be targets).

Everything else is derived at load: the ranges, the determiner and its family, the candidate
cases, the proof, the explanation, and whether a target can be graded or blanked. There is no
authored explanation; every one is built from the proof (`KasusExplanation`).

| `reason` | Case |
|---|---|
| `subject`, `predicate` | nom |
| `object`, `wechselWohin` | akk |
| `time` | akk, or dat after an/in/vor/zwischen |
| `recipient`, `dativeVerb`, `wechselWo`, `dativeOther` | dat |
| `attribute` | gen |
| `preposition` | whatever the preposition governs |
| `prepObject` | fixed by the verb (warten auf + Akk) |

## The validator

**Proof:** candidates = the cases the determiner fits with this gender. One left → `form`. Else
narrowed by the preposition in front → `preposition`; else by a main-verb copula for a
`predicate` → `copula`; still several → `label` (only the annotation decides).

**Issue codes** are stable histogram keys; never rename one. `locate.notFound`,
`np.unknownDeterminer`, `morph.impossibleForm`, `morph.caseMismatch`, `morph.pluralForm` (a plural
must be the Goethe marker's plural, with the Dativ -n), `morph.nDeklination` (Jungen, Herrn,
Studenten; -ns only for Name-type nouns), `morph.genitiveS` (-s/-es, -es/-ses after a sibilant),
`lex.gender`, `lex.conflict`, `lex.unverified`, `trigger.missing`, `trigger.prepositionCase`,
`trigger.wechselVerb`, `reason.caseMismatch`, `coverage.untargetedDeterminer` (every determiner
or contraction that opens a noun phrase, adjectives included, starts a target or a notTarget),
`story.unitCaseCount`, `story.wordCount`.

**Severity.** Every code is an error except these (`KasusValidator.Policy.severity`):

| Code | Authored | Generated |
|---|---|---|
| `lex.conflict`, `lex.unverified` | warning | warning |
| `story.wordCount` | warning | error |
| `coverage.untargetedDeterminer` | error | warning |
| `trigger.wechselVerb` on a motion verb that isn't liegen/stehen/sitzen/hängen or legen/stellen/setzen | warning | warning |

**Policy:** an authored story needs zero errors (`label` is fine: a human checked the role). A
generated story is rejected whole by any `morph.*`, `trigger.prepositionCase`,
`trigger.wechselVerb`, `lex.gender` or `story.*` error, because each means the German itself is
wrong; any other error, a `label` proof or an unverified gender only turns that target into plain
text (not marked, not blanked, not scored). The counts live in `KasusValidator.Policy`: 3 targets
of the unit's case, 2 of each case for Alle Fälle.

An issue line reads `error   trigger.prepositionCase  #11 „mit“ takes the Dativ, but …`:
severity, code, the target's number in reading order (from 1), message. The debug report prints
them under the story's summary line, which then reads `FAIL`.

**Lexicon order** (`AppKasusLexicon`): plural-only list → dual-gender whitelist → Wiktionary when
unanimous → the Goethe rows compared per level → a reliable suffix → unverified.

## The exercises

**Finden.** Tap a phrase to paint it with the selected brush; nothing is underlined before
Prüfen, since an authored story has full coverage. The first Prüfen is scored: right = solid
wash, wrong brush = struck-through grey, missed = dotted underline in the true case's color, and
painting a phrase whose case has no brush is a wrong pick. "Noch mal die Fehler" is not scored.
Finden counts for the streak and XP (the painted phrases only), never the coach.

**The text** (`KasusText`) is one `Text` per paragraph of link runs. Inside it the only styling is
a wash, an underline, a strikethrough and a color, so painting or answering never moves a line;
a phrase or a blank never breaks across a line (its spaces are no-break spaces). Case labels,
chips and explanations live in the bottom tray.

**Einsetzen.** Blanks are the unit's case ("gemischt": every case in play); every other article
stays visible as a model. Hint ladder, stored in `kasus.hintLevel`, default Genus-Hilfe at A1–A2
and Ohne Hilfe from B1. The Nominativ unit only runs at Ohne Hilfe, since its blanks would give
themselves away with a gender tag. The level locks after the first pick.

| Level | Shows | Options | Moves the case skill? |
|---|---|---|---|
| Viel Hilfe | gender tag, trigger underlined | the noun's own gender through the cases, plus one other form when fewer than 3 | no |
| Genus-Hilfe | raised m/f/n/pl tag | the whole family (des/eines once Genitiv is in play) | masculine only |
| Ohne Hilfe | a Tipp button: trigger → gender → case → answer; sg/pl tag on nouns like Schlüssel (not in the Dativ, where the plural adds -n) | the whole family | yes, unless the Tipp showed the case or answer (or the gender of an f/n/pl Akkusativ) |

Grading is the first pick only, ignoring case. Three kinds of wrong:

- **Gender slip:** the right case for another singular gender („in dem Tasche“).
- **Number slip:** the right case in the plural on a noun that reads the same in the plural
  („nimmt die Schlüssel“ for one key).
- **Case miss:** everything else, including any form the noun's own gender takes in another case.
  „auf der Boden“ is the Nominativ left unchanged, a case miss, even though „der“ is also the
  feminine Dativ.

Right: the article fills in its gender color and the next gap comes up after 600 ms. Wrong:
~~pick~~ **answer**, the explanation in the tray, and Weiter. Never green or red. Einsetzen is
recorded the moment its last gap gets a first pick, right or wrong.

**Ergebnis.** Per-case counts, time, the hint level, the misses in their sentences with their
explanations, "Noch mal · eine Stufe schwerer" at 80% or more, and "Noch mal · gemischt".

**Explanations** follow the Kasus-Check order and end with the code word, for example
`„nach“ always takes the Dativ. Masculine Dativ in „mrmn“ is m: dem.` A slip gets its own line
(`Right case, wrong gender: „dem“ is masculine Dativ. This noun is feminine, so der.`).

## Recording (`KasusService.recordRound`)

Both activities (`.kasusStory`, `.caseEndings`) come back through `ContentView.activityCover` and
call `recordRound` once per scored step.

- Streak, time and XP: `StudyLogService.record(.grammar(answered), seconds:)`, XP at 2 per item.
  Time is per step: hopping between Finden and Einsetzen pauses the other's clock.
- One `KasusRound` per scored step (below).
- The coach (`applyDrillResult`) only from Einsetzen and the Schnellrunde, only unscaffolded first
  picks, only a case with at least 3 of them, once per case per round. Left out: Viel Hilfe;
  f/n/pl at Genus-Hilfe; at Ohne Hilfe a Tipp that showed the case or answer, or the gender of an
  f/n/pl Akkusativ; f/n/pl Akkusativ in the Schnellrunde (its header names the article); every
  slip. Nominativ writes nothing, and no `GrammarFocus` was added. Finden never reaches the coach.

### `KasusRound`

A SwiftData model, additive, every field defaulted (registered in `german_ai_flashcardsApp`).

| Field | Holds |
|---|---|
| `date` | when the step was scored |
| `storyID` | the story's id, or `quick-<unit>` for a Schnellrunde |
| `unitRaw` | a `KasusUnit` raw value |
| `stepRaw` | `find` · `fill` · `quick` (`KasusRoundStep`) |
| `hintLevelRaw` | `viel` · `genus` · `ohne` for Einsetzen; empty otherwise |
| `askedCount`, `firstTryCount` | items asked, right on the first pick |
| `durationSeconds` | that step's own clock |
| `perCaseData` | encoded `[case: {asked, firstTry}]` |

The calendar's day detail, the story rows' ✓/○, the hub's dots and `KasusPath.next` all key on
(storyID, unitRaw, stepRaw), never on a display string, so a retitled story keeps its history.

## Adding a story

1. Add an entry to `Resources/kasus_stories.json` with a new `id` (`ks-<case>-<level>-<slug>`),
   `source: "authored"` and an empty `reviewed`. Write the text at the level's length
   (`CEFRLevel.storyWordRange`), with at least 3 targets of the unit's case (Alle Fälle: 2 of
   each). Determiner + noun only, no adjectives in a target yet.
2. List every article + noun phrase as a target, in reading order, with its `case`, `genus`,
   singular `lemma`, `reason` and `trigger` (the word that decides: the verb, or the preposition).
   Every other article word goes in `notTargets` with its `why`.
3. Run `-kasus.debugVerify 1` until the story reads `OK · … · 0 errors`. A DEBUG build also
   asserts on first load if a bundled story has an error, so a broken story can't slip through
   unnoticed. Then add its numbers to `KasusFixtures.golden` (targets, per case, per proof), so a
   later change to the text or the rules that moves them shows up.
4. Ask a teacher the three questions below, then fill in `reviewed {by, date}`.

### Teacher checklist (about 10 minutes)

The validator proves that article, gender and case agree. It can't prove the German reads well,
or that the role behind a die/das/seine answer is the right one. Those are the teacher's:

1. **Is the German natural?** Every sentence reads like something a German speaker would say, at
   this level.
2. **Is every label-proof case right?** A `label` target's form fits more than one case and
   nothing next to it narrows it, so only the annotation decides. The debug report counts them;
   in „Der verlorene Schlüssel“ they are „seine Mutter“ (fragt), „Die Mutter“ (lacht), „Das Tier“
   (ist traurig) and „seiner Mutter“ (hilft). For each one, is the labelled case the right one?
3. **Is every article phrase targeted or listed in notTargets?** The validator already flags an
   article word in neither list; the check is that nothing in `notTargets` is really a noun
   phrase a learner should mark (a relative „der“ is fine there, „die Katze“ is not).

## Debug launch arguments (DEBUG)

```
xcrun simctl launch <udid> kyle-essenmacher.german-ai-flashcards -kasus.debugVerify 1
```

The lines print to the console with a `[kasus.debugVerify]` (or `[kasus.debugVerifyRecord]`,
`[kasus.debugOpen]`) prefix.

**`-kasus.debugVerify 1`** validates every bundled story against the real lexicon, then runs the
fixtures, the table round trip and the service checks. Nothing is written. Expected:

```
ks-dat-a2-schluessel OK · 26 targets · form 20 · preposition 2 · copula 0 · label 4 · 0 errors
  cases Nom 6 · Akk 11 · Dat 9 · gradable Nom 6 · Akk 11 · Dat 9 · 122 words
  golden ✓
Fixtures (plan) 11/11
  PASS  „mit den Hund“ → trigger.prepositionCase
  …
Fixtures (extra) 12/12
Round trip: 140 table cells OK
ALL OK
Service · ks-dat-a2-schluessel
  PASS  blanks Viel Hilfe: Dat 9
  …
Service ALL OK
```

The plan's eleven fixtures, each of which must raise exactly its code and nothing else:

| Fixture | Code |
|---|---|
| „mit den Hund“ | `trigger.prepositionCase` |
| „auf die Rand“ | `morph.impossibleForm` |
| „Ich helfe den Mann“ | `morph.caseMismatch` |
| „das Tasche“ | `lex.gender` |
| „eine Kinder“ | `morph.impossibleForm` |
| „mit den Termin“ labelled pl | `morph.pluralForm` |
| „den Junge“ | `morph.nDeklination` |
| an untargeted determiner | `coverage.untargetedDeterminer` |
| a missing phrase | `locate.notFound` |
| „liegt unter den Tisch“ as wechselWohin | `trigger.wechselVerb` |
| „um dem Hund zu helfen“ | no error |

The twelve extra ones cover a copula, „und“ reach-back, a postposition, a correct Genitiv, the
Genitiv -s rules (des Mann, des Haus, des Busses), n-nouns (des Studentens, des Namens, den Herren
for one man), a wrong plural (die Hunds) and an untargeted article + adjective + noun. The round
trip checks that `compatibleCases` gives back every real cell of the endings table. The service
block checks blanks per hint level, the options, grading (right, case miss, gender slip, number
slip), the sg/pl tags, the default hint per level, and `KasusPath.next` over seven synthetic
histories.

**`-kasus.debugVerifyRecord 1`** runs `recordRound` on twelve synthetic rounds in the live store and
checks what each one moved, then puts everything back (`keep` leaves the rounds and the skill
changes; they are filed under `debug-verify-record`, so they never mark a real step done).
Expected: rounds #1–#10 (Viel Hilfe, under 3 per case, f/n/pl Akkusativ at Genus-Hilfe, a Tipp
that showed the answer, gender slips, a gender Tipp on f/n/pl Akkusativ, Nominativ, f/n/pl
Akkusativ in the Schnellrunde, Finden) move no skill; #11 moves Dativ and #12 moves Akkusativ.

```
#1 Viel Hilfe · 5 Akk m, all wrong (scaffolded)
   grammarExercises +5 · KasusRound +1 · akk –→– · dat –→– · gen –→– · PASS
…
#11 Ohne Hilfe · 4 Dat wrong + 2 Nom → moves Dativ
   grammarExercises +6 · KasusRound +1 · akk –→– · dat –→0.20 · gen –→– · PASS
#12 Genus-Hilfe · 3 Akk m wrong + 3 Akk f → moves Akkusativ (m only, exactly 3)
   grammarExercises +6 · KasusRound +1 · akk –→0.20 · dat 0.20→0.20 · gen –→– · PASS
ALL OK · 12 rounds
restored: coach skills, 12 rounds removed, grammarExercises −55
```

**`-kasus.debugOpen <screen>`** opens a Grammatik screen at launch, since the simulator can't tap
its way there, and prints `[kasus.debugOpen] open <screen>`:

| Screen | Opens |
|---|---|
| `hub` | the hub, in a sheet |
| `unit:<unit>` | a unit screen in a sheet: `nominativ`, `akkusativ`, `dativ`, `genitiv`, `alleFaelle` |
| `read` | the bundled story at Lesen |
| `find` | Finden, painted if `-kasus.debugAnswers` is given |
| `check` | Finden after Prüfen, the first miss in the tray |
| `summary` | Finden's sort grid |
| `fill` | Einsetzen, all but the last three gaps answered if `-kasus.debugAnswers` is given |
| `result` | Ergebnis |

- `-kasus.debugAnswers right|mixed` prefills the answers. `mixed` gets about one gap in three
  wrong in Einsetzen, and in Finden leaves one phrase in four unpainted and paints one in five
  with the wrong brush. `check`, `summary` and `result` use `mixed` when it isn't given.
  Prefilled answers are never recorded.
- `-kasus.debugHint viel|genus|ohne` picks the hint level for that launch without overwriting the
  stored one.
- Combine with `-level.debugDeclare A1|B1` to check the hero's start unit and the default hint
  level.

## Removed

`Features/Grammar/GrammarCategoryDetailView.swift`, `GrammarStudyMode`,
`GrammarExerciseService.toVocabCards(category:)`, `DeckStore.grammarFlipSession` and the hub's
Coach's Picks, Akk/Dat category and Perfekt rows (the Perfekt decks live in Wortschatz ▸ More).
`AIGrammarCreateView` is unlinked, not deleted: its answers were never checked; Phase 3 replaces
it. The five akk/dat categories in `grammar_exercises.json` stay until `GrammarRoute` (Phase 2),
because Today and Coach Notes still launch them.

## Open

- ⬜ Phase 2: about six more stories (Nominativ A1, Akkusativ A1 ×2, Dativ, Genitiv B1, Alle
  Fälle), "Mehr dazu" rows, contraction/pronoun/dieser targets, `GrammarRoute`, a Swift Testing
  target running the fixtures.
- ⬜ Phase 3: tutor-written stories in the same format, gated by the validator, with a Lab.
- ⬜ The bundled story has no teacher review yet (`reviewed` is empty).
- ⬜ Homonyms with two plurals (Bank: Bänke/Banken) fail `morph.pluralForm` on the reading the
  Goethe list doesn't give.
- ⬜ Die Endungen's "Ask the question" section still teaches the Wer/Wen/Wem test, not the
  Kasus-Check order.
- ⬜ In the endings table the three-line cells (Dativ plural, Genitiv m/n) draw their article at
  about 80% size, a little higher than the rest of the row.
- ⬜ Before Prüfen, the Nominativ brush's graphite wash is close to the grey of a wrong pick after
  it (the strikethrough tells them apart).
- ⬜ Device verdict in all four themes; only Klar has been seen, in the simulator.
