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
| Right/wrong signal: verdict header, answer buttons, progress strip, capped tray scroll | `Features/Grammar/Kasus/KasusFeedback.swift` |
| The `{m:den}` / `{dat:Dativ}` / `**bold**` markup and `Text(kasusRich:)` | `Features/Grammar/Kasus/KasusRichText.swift` |
| Endings table + Schnellrunde (`CaseEndingsDrillView`) | `Features/Grammar/CaseEndingsView.swift` |
| Day detail in the calendar | `Features/Home/StreakCalendarView.swift` |
| Verlauf (every round by day) and a round's answers | `Features/Grammar/Kasus/KasusHistoryView.swift`, `KasusRoundDetailView.swift` |
| Sample rounds for the simulator (DEBUG) | `Services/KasusDebugSeeder.swift` |
| Where a grammar focus goes from Today, Coach's Notes, the pyramid and a class entry | `Services/GrammarRoute.swift` |
| Swift Testing target (engine, validator, explanations, service, recording) | `german-ai-flashcardsTests/` |

## The path

| Unit | Cases in play | Finden brushes | Label |
|---|---|---|---|
| Nominativ | nom | nom | A1 |
| Akkusativ | nom, akk | akk | A1 |
| Dativ | nom, akk, dat | nom, akk, dat | A1–A2 |
| Genitiv | all | all | B1 |
| Alle Fälle | all | all | B1 |

**Entry.** Home ▸ Grammar pushes the hub directly, and so does the pyramid's Grammatik-Kern
layer. The hub has four sections: **Weiter** (one hero row), **Die vier Fälle** (a row per unit,
with a dot per story, filled once its Finden and Einsetzen are both played, one for the
Schnellrunde, and a flame on a case the coach has as shaky), **Verlauf** (one row with the last
round's score) and **Werkzeuge** (Präpositionen, Der · Die · Das, Die Endungen). A unit screen
has **Die Regel** (open until the unit's first round), **Geschichten** (one row per story:
level, Finden ✓/○, Einsetzen ✓/○), the **Schnellrunde**, the endings drill limited to the
unit's cases, **Deine Runden** (the unit's last three rounds and "Alle anzeigen") and **Mehr
dazu**: the preposition cards opened on the case's group, with a 3D still (Akkusativ →
`.akkusativ`; Dativ → `.dativ` and "Wo oder Wohin?" → `.wechsel`; Genitiv → `.genitiv`; Alle
Fälle → every group), and Der · Die · Das for Nominativ and Alle Fälle.

**Verlauf · Your rounds** lists every scored grammar round, newest first, grouped by day: the case
path's `KasusRound`s and the article game's and the preposition drill's rounds (`ArticleRound`,
`PrepositionRound`, score and count only). Pills filter Alle · Fälle · Der·Die·Das · Präpositionen;
an all-time strip shows the first-try share per case. A Kasus round opens its detail: score, what
it did for the coach, a bar per case with its code word, then every answer in its sentence, misses
first (~~pick~~ **answer**, the answer in its gender color and the phrase underlined in its case
color, the outcome and the explanation); right answers keep their why folded until tapped. Rounds
from before `items` existed show their counts only.

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
an article), `demonstrative`, `relative` (a relative „der“), `idiom` („am besten“, „zum Glück“)
or `contraction`. Since Phase 2 dieser/jeder/welcher, contractions and the pronouns mich, mir,
dich, dir, ihn, ihm are targets themselves: contractions and pronouns are spot-only (marked in
Finden, never blanked), and a pronoun target may leave out `genus` and `lemma`. A story that
targets one of those pronouns targets all of them.

**Target kinds** (`KasusTargetKind`, derived at load):

- **article:** determiner + noun, the only kind Einsetzen blanks. dieser/jeder/welcher are a
  family of their own (`KasusFamily.derWord`: the definite article's endings on a stem; „jede“ +
  plural is impossible, like „eine Kinder“) and blank like any article.
- **contraction** („im Garten“, „zum Arzt“, „ins Kino“): read as preposition + article
  (`contractedArticle`, `caseForm` = the article inside). Proven by form or preposition, never
  by label. The trigger may be written as the contraction or its preposition („am“ or „an“).
- **pronoun** (mich/mir/dich/dir/ihn/ihm only, the six whose form shows the case): always
  form-proven. `hasNounGender` is false, so gender displays (the sort grid, the round detail's
  gender color) leave them out.

The table on `KasusLocatedTarget` (`Models/KasusStory.swift`) lists what a view can rely on per
kind: every field stays non-optional; for a contraction or pronoun `determinerRange` covers the
whole token and `parsed` is nil; for a pronoun `nounRange` equals `range`.

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

### The bundled stories

Seven, all `authored`, none `reviewed` yet. Numbers are the golden ones `-kasus.debugVerify`
checks (targets · per case · per proof); "spot-only" counts contractions + pronouns, which Finden
marks and Einsetzen never blanks.

| id · title | Unit · level | Words | Cases | Proofs (form · prep · copula · label) | Spot-only |
|---|---|---|---|---|---|
| `ks-nom-a1-foto` · Das alte Foto | Nominativ · A1 | 89 | Nom 15 · Akk 1 | 11 · 0 · 2 · 3 | 0 + 0 |
| `ks-akk-a1-picknick` · Das Picknick | Akkusativ · A1 | 91 | Nom 2 · Akk 15 | 15 · 2 · 0 · 0 | 0 + 1 |
| `ks-akk-a1-berlin` · Besuch in Berlin | Akkusativ · A1 | 87 | Nom 5 · Akk 13 | 16 · 2 · 0 · 0 | 0 + 2 |
| `ks-dat-a2-schluessel` · Der verlorene Schlüssel | Dativ · A2 | 122 | Nom 6 · Akk 11 · Dat 9 | 20 · 2 · 0 · 4 | 0 + 0 |
| `ks-dat-a2-umzug` · Der Umzug | Dativ · A2 | 135 | Nom 5 · Akk 8 · Dat 15 | 24 · 2 · 0 · 2 | 5 + 4 |
| `ks-gen-b1-grossmutter` · Das Haus meiner Großmutter | Genitiv · B1 | 218 | Nom 10 · Akk 13 · Dat 17 · Gen 11 | 41 · 6 · 2 · 2 | 6 + 4 |
| `ks-alle-b1-gespraech` · Das Vorstellungsgespräch | Alle Fälle · B1 | 219 | Nom 7 · Akk 9 · Dat 17 · Gen 4 | 26 · 10 · 1 · 0 | 4 + 1 |

What they cover beyond the Phase 1 story: für/durch/ohne and „es gibt“ (the Akkusativ stories);
mit/von/aus/nach/beim/zum and helfen/danken/schmecken (Umzug); wegen/trotz/während/statt, n-nouns
(„des Nachbarn“, „den Namen“) and jedes/diesen/jeden (Großmutter). A1 sentences stay at 8 words or
fewer, A2 at 12. Every noun has one gender across Wiktionary and the Goethe lists (Morgen and See
were dropped for that), and idioms („Zum Glück“, „Kein Problem“, „Am liebsten“) are notTargets.

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

**Finden.** Tap a phrase to paint it with the selected brush; nothing is underlined before Prüfen,
since an authored story has full coverage. When the story marks pronouns or contractions, the
instruction names them (the pronouns of the cases being marked, and generic examples such as
„im, zum …“), so "article + noun" doesn't have the learner skip „ihn“ or „am Ende“. The sort grid leaves
pronouns out and lists a contraction under the article inside it. The first Prüfen is scored:
right = solid wash, wrong brush = struck-through grey, missed = dotted underline in the true case's
color, and painting a phrase whose case has no brush is a wrong pick. After Prüfen the tray shows
the verdict, one dot per phrase and what went wrong; tapping a phrase shows its own verdict, what
was marked and why. "Noch mal die Fehler" is not scored.
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
| Ohne Hilfe | a Tipp button: trigger → gender → case → answer; sg/pl tag on nouns like Schlüssel (not in the Dativ, where the plural adds -n) and on n-nouns outside the Nominativ (den Nachbarn) | the whole family | yes, unless the Tipp showed the case or answer (or the gender of an f/n/pl Akkusativ) |

A time phrase with no preposition („jeden Tag“) has no deciding word: neither Viel Hilfe nor the
Tipp underlines the verb next to it, and the Tipp's first clue reads "A time phrase: wann? wie
oft?".

Grading is the first pick only, ignoring case. Three kinds of wrong:

- **Gender slip:** the right case for another singular gender („in dem Tasche“).
- **Number slip:** the right case in the other number on a noun that reads the same in both
  („nimmt die Schlüssel“ for one key; „der Nachbarn“ for „des Nachbarn“, since an n-noun's -n
  outside the Nominativ is also its plural, except Herr and a Name-type Genitiv). A plural answer
  picked in the singular counts too.
- **Case miss:** everything else, including any form the noun's own gender takes in another case.
  „auf der Boden“ is the Nominativ left unchanged, a case miss, even though „der“ is also the
  feminine Dativ.

The tray reads top to bottom: the progress strip and score (and the Tipp button), the verdict
with its explanation, the answer buttons (they keep showing the pick), then Weiter. Right: the
article fills in its gender color, „Richtig!“ shows, and the next gap comes up after 800 ms.
Wrong: ~~pick~~ **answer** in the text, the verdict and explanation (a slip gets its slip note),
and Weiter. An answered gap keeps a light wash of its gender color, and coming back to a round in
progress scrolls to its gap. Never green or red for right and wrong (see below). Einsetzen is
recorded the moment its last gap gets a first pick, right or wrong.

**Ergebnis.** Per-case counts, time, the hint level, the misses in their sentences with their
explanations, "Noch mal · eine Stufe schwerer" at 80% or more, and "Noch mal · gemischt".

**Explanations** follow the Kasus-Check order and end with the code word, for example
`„nach“ always takes the Dativ. Masculine Dativ in „mrmn“ is m: dem.`: each code letter wears
its column's gender color, and the letter and the form the answer's (the same line the
Schnellrunde prints; `KasusExplanation.codeWord`). A slip gets its own line
(`Right case, wrong gender: „dem“ is masculine or neuter Dativ. This noun is feminine, so der.`).
Three lines have their own wording: a Dativ verb is named with its infinitive too („hilft
(helfen)“); the Genitiv prepositions add that speech often uses the Dativ, as the rule card says;
and the object of „es gibt“ says that *es* is the subject and the thing that is there the object,
instead of "what *gibt* acts on".

**Schnellrunde** (`CaseEndingsDrillView`). The sentence is the hero, in large type centred in the
free space (larger on iPad); the answer buttons are a 3-column grid at the bottom and the
feedback card appears between the two. The slot under the buttons shows a hint until Weiter takes
its place, so the buttons never move. It always draws on the themed ground (grey on Klar, like
the article game) so the white buttons stand out. Its summary has the dot strip and „Die Fehler ·
Your misses“, each with its explanation. The endings reference screen (`CaseEndingsView`) teaches
„Welcher Fall? · Which case?“: the six Kasus-Check steps (`KasusCheckSheet.steps`, shared with
the card), „Der Mann gibt dem Kind einen Ball“ run through them, and a link to the card.

## Right and wrong (`KasusFeedback`)

One signal for Einsetzen, Finden after Prüfen and the Schnellrunde:

| | Header | Answer buttons | Strip dot | Haptic |
|---|---|---|---|---|
| Right | „Richtig!“, the check bouncing in the case color, then the case | the pick fills in the case color with a ✓ and a small pop | filled, case color | success |
| Slip (gender or number) | „Fast · Almost“, grey half circle | as a miss | grey ring with a center dot | light tap |
| Miss | „Nicht ganz · Not quite“, grey | the pick shakes, greys out, is struck through with an ✗; the answer is outlined in the case color with a ✓; the rest fade | hollow grey ring | error |

- The strip (`KasusProgressStrip`) has one dot per question and a running ✓ count; past 20 marks
  the dots keep their size and wrap onto more rows (a B1 Finden has 51).
- `KasusCappedScroll` holds the verdict and its explanation at their own height up to about 30%
  of the screen and scrolls past that, so at accessibility text sizes a long why never pushes the
  buttons or Weiter off screen. At large sizes the header's case label moves to a second line and
  a button's ✓/✗ gives way to the word.
- Haptics follow `hapticMode`. Right and wrong are never green or red. The answer buttons take the
  question's case color (the same color as its progress dot), never the gender color, because a
  right „die“ filled die-red read as wrong. Forms keep their gender color in the sentence and the
  explanations.

## Rich text (`KasusRich`)

Every rule line (`KasusUnit.ruleLines`), Kasus-Check step, explanation and slip note is a plain
Swift string in one small markup, rendered with `Text(kasusRich:)`:

| Markup | Renders |
|---|---|
| `{m:den}` `{f:die}` `{n:das}` `{pl:die}` | the form, bold, in its gender color (`Gender.color`) |
| `{nom:Nominativ}` `{akk:…}` `{dat:…}` `{gen:…}` `{wechsel:…}` | the word, bold, in its case color (`GrammarCase.color`, `CasePalette.wechsel`) |
| `**bold**`, `*italic*` | inline Markdown: key terms bold, German words and triggers italic |

Tokens are never nested inside `*` or `**`. A code word is one token per letter
(`„{m:m}{f:r}{n:m}{pl:n}“`), so it reads like the endings table everywhere: explanations, the
Schnellrunde, Ergebnis and the round detail's bars. `KasusRich.plain(_:)` strips the markup for
logs and accessibility strings. `KasusExplanation` stays Foundation-only and emits the markup, so
the host harness prints the same strings. A form that fits two genders (a slip's „dem“) is bold
instead of one gender color. Round items store the explanation already in markup, so rounds
recorded before the markup existed stay plain in the round detail. The tests check every rule line,
every explanation and every Schnellrunde feedback for leftover `*`, `{` or `}`.

## Where practice goes (`GrammarRoute`)

Today's weak spot, Coach's Notes' "Practice this", the pyramid's rows and a class entry all ask
`GrammarRoute(focus)`:

| Focus | Route | Opens |
|---|---|---|
| akkusativ, dativ, genitiv | `.kasus(unit)`, launch | Einsetzen in the unit's least-recently-played story (even one never played), or its Schnellrunde while the unit has no story |
| artikel | `.articleGame`, launch | a der/die/das round from the Goethe list at the learner's level, with tricky nouns mixed in, using the setup screen's round size and "Bring back tricky nouns" |
| praepositionen, wechselpraepositionen | `.prepositionHub`, push | `PrepositionHubView` |
| everything else (Perfekt, Präteritum, Futur, Konjunktiv II, Modalverben, Adjektivendungen) | `.lesson(focus)`, sheet | `GrammarLessonSheet` |

A row decides while it draws whether it is a launch, a push or a sheet; the story pick and the
article nouns are resolved only at the tap. Per surface: the pyramid's Fälle row (which now holds
Genitiv) opens the shakiest case and names it, the preposition hub with only tricky prepositions,
the Grammar hub with nothing shaky; a Strukturen weak spot opens its lesson; the Artikel row still
pushes the der/die/das setup. A class entry gets „Mit einer Geschichte üben“ (or „Schnellrunde“
while the unit has no story) per tagged case, „Der · Die · Das üben“ for Artikel and
„Präpositionen“ for a preposition tag.

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
| `itemsData` | encoded `[KasusRoundItem]`, one per answer: sentence, phrase (and where it starts), answer, pick (a Finden pick is the painted case), case, gender, outcome (`right`, `caseMiss`, `genderSlip`, `numberSlip`, `missed`, `wrongPick`; stable raw values), whether it counted toward the coach, the explanation in `KasusRich` markup (a slip stores its slip note), the target's index, and `hasNounGender` (false for a pronoun; nil on items saved before it, where the round detail checks the answer's form instead). Built by `KasusService.round(for:date:)`, which also sets the counts-toward-coach flag; the Schnellrunde's come from `EndingsQuestion.roundItem(pick:)`. Nil on older rounds and the record check's synthetic ones |

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
   nothing next to it narrows it, so only the annotation decides. The debug report lists them
   (`label:` under each story). For each one, is the labelled case the right one?

   | Story | Label targets (case, the word it hangs on) |
   |---|---|
   | Der verlorene Schlüssel | „seine Mutter“ (Akk, fragt) · „Die Mutter“ (Nom, lacht) · „Das Tier“ (Nom, ist traurig) · „seiner Mutter“ (Dat, hilft) |
   | Das alte Foto | „eine Frau“ (Nom, sitzt) · „ein Mädchen“ (Nom, steht) · „Das Foto“ (Nom, ist ein Schatz) |
   | Der Umzug | „das Sofa“ (Nom, ist) · „das Sofa“ (Akk, tragen) |
   | Das Haus meiner Großmutter | „Die Küche“ (Nom, war) · „meiner Großmutter“ (Gen, attribute of Haus) |

   The two Akkusativ stories and „Das Vorstellungsgespräch“ have none.
3. **Is every article phrase targeted or listed in notTargets?** The validator already flags an
   article word in neither list; the check is that nothing in `notTargets` is really a noun
   phrase a learner should mark (a relative „der“ is fine there, „die Katze“ is not).

## Tests (`german-ai-flashcardsTests`)

A Swift Testing target in the `german-ai-flashcards` scheme; `test_sim` runs its 58 tests. Debug
only, since they use `KasusFixtures` and `KasusStoryBank.only`. They read the bundled JSON
directly instead of `KasusStoryBank.bundled`, whose DEBUG assert would stop the whole run on one
broken story instead of failing one test.

| File | Covers |
|---|---|
| `KasusFormsTests` | every cell of the endings table for 12 determiner families, both ways; the 184-cell round trip; option sets; gender and number slips; plurals, n-nouns, the Genitiv -s; contractions against `prepositions.json`; the six pronouns; decoding a target |
| `KasusValidatorTests` | each of the 46 fixtures raises exactly its code; every bundled story passes with its golden numbers and keeps the `KasusLocatedTarget` contract; generated-story and story-level rules; severities; issue codes stay stable |
| `KasusExplanationTests` | every target's explanation is clean markup, the Finden note only on label targets; pinned lines; every rule line, the Kasus-Check card and every Schnellrunde feedback are clean markup |
| `KasusServiceTests` | blanks per hint level, options, grading, the sg/pl tag, feedback, the Einsetzen and Finden results, the harder-round offer, the Weiter row |
| `KasusRecordingTests` | which answers count toward the coach, the twelve record-check rounds, `recordRound` against an in-memory store |

A wording change to an explanation moves the pinned lines in `KasusExplanationTests.swift`; a
change to a story's text moves its golden numbers in `KasusFixtures.golden`.

## Debug launch arguments (DEBUG)

```
xcrun simctl launch <udid> kyle-essenmacher.german-ai-flashcards -kasus.debugVerify 1
```

The lines print to the console with a `[kasus.debugVerify]` (or `[kasus.debugVerifyRecord]`,
`[kasus.debugOpen]`, `[kasus.debugRoute]`, `[kasus.debugSeedRounds]`) prefix.

**`-kasus.debugVerify 1`** validates every bundled story against the real lexicon, then runs the
fixtures, the table round trip and the service checks. Nothing is written. Expected (four lines
per story, all seven `OK` with `golden ✓`; the numbers are the table in "The bundled stories"):

```
ks-dat-a2-schluessel OK · 26 targets · form 20 · preposition 2 · copula 0 · label 4 · 0 errors
  cases Nom 6 · Akk 11 · Dat 9 · gradable Nom 6 · Akk 11 · Dat 9 · 122 words
  spot-only: contraction 0 · pronoun 0 · blankable Nom 6 · Akk 11 · Dat 9
  label: #6 seine Mutter (Akk, fragt) · #8 Die Mutter (Nom, lacht) · #15 Das Tier (Nom, ist) · #17 seiner Mutter (Dat, hilft)
  golden ✓
ks-nom-a1-foto OK · 16 targets · form 11 · preposition 0 · copula 2 · label 3 · 0 errors
…
ks-alle-b1-gespraech OK · 37 targets · form 26 · preposition 10 · copula 1 · label 0 · 0 errors
  cases Nom 7 · Akk 9 · Dat 17 · Gen 4 · gradable Nom 7 · Akk 9 · Dat 17 · Gen 4 · 219 words
  spot-only: contraction 4 · pronoun 1 · blankable Nom 7 · Akk 9 · Dat 12 · Gen 4
  golden ✓
Fixtures (plan) 11/11
  PASS  „mit den Hund“ → trigger.prepositionCase
  …
Fixtures (extra) 12/12
Fixtures (phase 2) 23/23
Round trip: 184 table cells OK
ALL OK
Service · ks-dat-a2-schluessel
  PASS  blanks Viel Hilfe: Dat 9
  …
Service ALL OK
```

The service block runs on `KasusStoryBank.only(["ks-dat-a2-schluessel"])` (a DEBUG helper), since
its `KasusPath` histories assume that one story; the Swift tests cover the other six.

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
for one man), a wrong plural (die Hunds) and an untargeted article + adjective + noun. The
twenty-three Phase 2 ones cover the new target kinds: contractions („im Garten“, „ins Kino“, „zur
Schule“, „Am Montag“; „zur Arzt“, „ins Garten“ and „liegt ins Bett“ must fail), idioms as
notTargets, the pronouns („mit mir“, reached back through „und“; „Ich helfe dich“, „für ihm“ and
„ihn“ for a feminine noun must fail), dieser/jeder/welcher („diesen Film“, „jeden Tag“, „mit diesem
Bus“; „jede Kinder“ and „Dieses Mann“ must fail), and an untargeted contraction, pronoun and
der-word each raising `coverage.untargetedDeterminer`. The round
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
| `quick:<unit>` | the unit's Schnellrunde |
| `read` | the first bundled story („Der verlorene Schlüssel“) at Lesen; `-kasus.debugStory <id>` picks another for every player screen |
| `find` | Finden, painted if `-kasus.debugAnswers` is given |
| `check` | Finden after Prüfen, the first miss in the tray |
| `summary` | Finden's sort grid |
| `fill` | Einsetzen, all but the last three gaps answered if `-kasus.debugAnswers` is given |
| `result` | Ergebnis |
| `history` | Verlauf, in a sheet |
| `round` | the newest Kasus round that kept its answers, in a sheet |

- `-kasus.debugAnswers right|mixed` prefills the answers. `mixed` gets about one gap in three
  wrong in Einsetzen, and in Finden leaves one phrase in four unpainted and paints one in five
  with the wrong brush. `check`, `summary` and `result` use `mixed` when it isn't given.
  Prefilled answers are never recorded.
- `-kasus.debugHint viel|genus|ohne` picks the hint level for that launch without overwriting the
  stored one.
- `-kasus.debugStory <id>` opens `read` … `result` on that story instead of the first, e.g.
  `-kasus.debugOpen check -kasus.debugStory ks-nom-a1-foto -kasus.debugAnswers mixed`.
- `-kasus.debugQuickState right|wrong|slip|done`, with `quick:<unit>`, answers the Schnellrunde's
  next question that way (`done` finishes the round); with `-kasus.debugAnswers right|mixed` the
  first four are answered first. Never recorded.
- `-kasus.debugRoute 1` prints where every `GrammarFocus` goes from Today, Coach's Notes, the
  pyramid and a class entry, and ends `OK` when no case, article or preposition focus falls back
  to the lesson sheet.
- Combine with `-level.debugDeclare A1|B1` to check the hero's start unit and the default hint
  level.

**`-kasus.debugSeedRounds 1`** inserts most of a week of rounds so Verlauf has something to show:
Finden and Einsetzen (Genus-Hilfe, mixed answers) on the bundled Dativ story today, the Nominativ
and Akkusativ Schnellrunden, a gemischt Einsetzen at Ohne Hilfe, one Dativ Schnellrunde stored
without answers (how older rounds look), and two der/die/das and two preposition rounds. The
Kasus rounds are built by the service, so their sentences and explanations are real. Nothing
else moves (no streak, XP or coach), but the story rounds do mark its steps as played. It is
idempotent: the rows' dates are kept in UserDefaults and a second run prints `already seeded`;
`-kasus.debugSeedRounds remove` deletes exactly those rows. Launch with it and
`-kasus.debugOpen history`; the first launch of a fresh install can lose the sheet to the
launch presentations, so relaunch if it doesn't show.

## Removed

`Features/Grammar/GrammarCategoryDetailView.swift`, `GrammarStudyMode`,
`GrammarExerciseService.toVocabCards(category:)`, `DeckStore.grammarFlipSession` and the hub's
Coach's Picks, Akk/Dat category and Perfekt rows (the Perfekt decks live in Wortschatz ▸ More).
`AIGrammarCreateView` is unlinked, not deleted: its answers were never checked; Phase 3 replaces
it. Phase 2 deleted the five akk/dat categories in `grammar_exercises.json` and
`GrammarExerciseService.category(for:rotation:)`: Today, Coach's Notes, the pyramid and class
entries all go through `GrammarRoute` now (the `praep-*` categories stay for the preposition hub).

## Open

- ✅ Phase 2: six more stories (Nominativ A1, Akkusativ A1 ×2, Dativ A2, Genitiv B1, Alle Fälle
  B1), contraction/pronoun/dieser targets, `GrammarRoute`, the "Mehr dazu" rows, and the Swift
  Testing target `german-ai-flashcardsTests` (`test_sim` on the `german-ai-flashcards` scheme; Debug
  only, since it uses the DEBUG fixtures).
- ⬜ Phase 3: tutor-written stories in the same format, gated by the validator, with a Lab.
- ⬜ No bundled story has a teacher review yet (`reviewed` is empty), and the seven new label
  targets need the teacher's check too.
- ⬜ Homonyms with two plurals (Bank: Bänke/Banken) fail `morph.pluralForm` on the reading the
  Goethe list doesn't give.
- ⬜ In the endings table the three-line cells (Dativ plural, Genitiv m/n) draw their article at
  about 80% size, a little higher than the rest of the row.
- ⬜ Before Prüfen, the Nominativ brush's graphite wash is close to the grey of a wrong pick after
  it (the strikethrough tells them apart).
- ⬜ Device verdict in all four themes; only Klar has been seen, in the simulator.
