# Grammatik — the case path and the Kasus stories

One path through the four cases, Nominativ → Akkusativ → Dativ → Genitiv → Alle Fälle, where every
unit runs the same loop: **Regel → Geschichte (Lesen → Markieren → Endungen → Ergebnis) →
Schnellrunde**. The stories are the two worksheets from a German class on one text: mark every word
in a case, then fill in the article endings. A deterministic validator is the answer key; it gates
the bundled stories now and will gate the tutor's stories later (Phase 3).

Status legend: ✅ done · ⬜ open

## Where things live

| Piece | File |
|---|---|
| Units (cases in play, Markieren's case order, level labels, rule lines, start unit) | `Models/KasusUnit.swift` |
| Story format (stored fields, reasons, located targets) | `Models/KasusStory.swift` |
| Forms engine (determiner families, table lookups, options, slips, noun endings, word lists) | `Models/KasusForms.swift` |
| Validator (locate, prove, issue codes, policy) | `Services/KasusValidator.swift` |
| Explanations, built from the proof only | `Services/KasusExplanation.swift` |
| Loader, `AppKasusLexicon`, the DEBUG assert | `Services/KasusStoryBank.swift` |
| Planted-error fixtures, golden numbers, table round trip (DEBUG) | `Services/KasusFixtures.swift` |
| Sessions, blanks, grading, `recordRound`, progress, `KasusPath` (the hero) | `Services/KasusService.swift` |
| Numbered sentences, word roles, the Markieren round and score, feedback modes (Foundation only) | `Services/KasusMarking.swift` |
| Endungen: gaps, ending buttons, grading an ending, the Endungen round | `Services/KasusEndings.swift` |
| The round record | `Models/KasusRound.swift` |
| Bundled stories | `Resources/kasus_stories.json` |
| Hub | `Features/Grammar/GrammarHubView.swift` |
| Unit screen, story player, story text, Kasus-Check card | `Features/Grammar/Kasus/` |
| The story player: step bar, Lesen, Ergebnis, the exercises' state, DEBUG screens | `Features/Grammar/Kasus/KasusStoryView.swift` |
| Markieren's screen and state (`KasusMarkPlay`) | `Features/Grammar/Kasus/KasusMarkView.swift` |
| Endungen's screen and state (`KasusEndingsPlay`, `KasusGapState`) | `Features/Grammar/Kasus/KasusEndingsView.swift` |
| Numbered sentences as word chips (`KasusSentenceList`, `KasusWordFlow`, `KasusChip`) | `Features/Grammar/Kasus/KasusSentences.swift` |
| Tray with a pinned footer, step clock, header, options pill | `Features/Grammar/Kasus/KasusPlayerParts.swift` |
| Right/wrong signal: verdict header, answer buttons, progress strip, capped tray scroll | `Features/Grammar/Kasus/KasusFeedback.swift` |
| The `{m:den}` / `{dat:Dativ}` / `**bold**` markup and `Text(kasusRich:)` | `Features/Grammar/Kasus/KasusRichText.swift` |
| Endings table (and its compact tray version with a highlighted cell) + Schnellrunde (`CaseEndingsDrillView`) | `Features/Grammar/CaseEndingsView.swift` |
| Day detail in the calendar | `Features/Home/StreakCalendarView.swift` |
| Verlauf (every round by day) and a round's answers | `Features/Grammar/Kasus/KasusHistoryView.swift`, `KasusRoundDetailView.swift` |
| Sample rounds for the simulator (DEBUG) | `Services/KasusDebugSeeder.swift` |
| Where a grammar focus goes from Today, Coach's Notes, the pyramid and a class entry | `Services/GrammarRoute.swift` |
| Swift Testing target (engine, validator, explanations, service, recording) | `german-ai-flashcardsTests/` |

## The path

| Unit | Cases in play | Markieren asks, in order | Label |
|---|---|---|---|
| Nominativ | nom | nom | A1 |
| Akkusativ | nom, akk | akk, nom | A1 |
| Dativ | nom, akk, dat | dat, akk, nom | A1–A2 |
| Genitiv | all | gen, dat, akk, nom | B1 |
| Alle Fälle | all | nom, akk, dat, gen | B1 |

**Entry.** Home ▸ Grammar pushes the hub directly, and so does the pyramid's Grammatik-Kern
layer. The hub has four sections: **Weiter** (one hero row), **Die vier Fälle** (a row per unit,
with a dot per story, filled once its Markieren and Endungen are both played, one for the
Schnellrunde, and a flame on a case the coach has as shaky), **Verlauf** (one row with the last
round's score) and **Werkzeuge** (Präpositionen, Der · Die · Das, Die Endungen). A unit screen
has **Die Regel** (open until the unit's first round), **Geschichten** (one row per story:
level, Markieren ✓/○, Endungen ✓/○), the **Schnellrunde**, the endings drill limited to the
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
color, the outcome and the explanation); right answers keep their why folded until tapped. A
Markieren round shows its case („Markieren · Dativ“), the class-sheet score („6 / 10“ over „8
richtig · 2 falsch · 2 übersehen“, also the row's score in Verlauf), a word marked that has no case
there struck through, and a partly marked phrase with its word count. A round whose answers Lösung
zeigen showed carries „Lösung angezeigt · Answers shown“ (an eye in the Verlauf row, and on each
answer it showed). Rounds from before `items` existed show their counts only.

Levels are soft labels, never gates. The hub's **Weiter** row (`KasusPath.next`) is derived on
every render and never stored. First rule that fits:

1. a shaky akk/dat/gen case whose unit has a story → its least-recently-played story (Lesen if
   never played, else Endungen);
2. an unplayed story, from the start unit on;
3. the first unfinished step from the start unit (Markieren, Endungen, then the Schnellrunde);
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
dich, dir, ihn, ihm are targets themselves: contractions and pronouns are spot-only (never a
gap; in Markieren a pronoun counts and a contraction never does), and a pronoun target may leave
out `genus` and `lemma`. A story that targets one of those pronouns targets all of them.

**Target kinds** (`KasusTargetKind`, derived at load):

- **article:** determiner + noun, the only kind that becomes a gap. dieser/jeder/welcher are a
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
checks (targets · per case · per proof); "spot-only" counts contractions + pronouns, which never
become gaps.

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

The two class worksheets on one text. Markieren and Endungen replaced the brush-sorting Finden and
the whole-article Einsetzen in the player (Phase 3a). `KasusStep.finden` / `.einsetzen` and
`KasusRoundStep.find` / `.fill` keep their names and raw values, but read „Markieren“ and
„Endungen“; a round recorded before keeps „Finden“ / „Einsetzen“ (`KasusRound.stepLabel`).

**Numbered sentences** (`KasusSentences.swift`). Both exercises show the story one sentence per row,
numbered straight across paragraphs (`KasusPlayableStory.numbered`), the number hanging in a column
as wide as the widest one („9.“ and „10.“ end on the same line). Every word is a chip in a wrapping
flow (`KasusWordFlow`, 2 pt across and 5 pt between lines, each chip's tap area grown into half of
each gap and dimmed while pressed), padded so a short „den“ is an easy tap; punctuation rides along
in `leading` / `trailing`, and a class-style tag („(m)“) sits between a noun and its punctuation. A
chip's look (wash, outline, strikethrough, a small ✓ / ✗ badge in its corner, a ring when the tray
is talking about it) never changes its width, so marking or checking never moves a line; only a
wrong ending shown as ~~der~~ dem widens its chip. Lesen keeps the paragraphs (`KasusText`). The
validator's own splitter and words are used, so every target lands on whole words. Each word has a
role:

| Role | Words | Marked in a round of its case | Marked in another round |
|---|---|---|---|
| `target` (determiner · adjective · noun · pronoun) | every word of a gradable article or pronoun target | right | wrong |
| `plain` | verbs, prepositions, adverbs … | – | wrong |
| `ungraded(contraction)` | a contraction phrase and its noun („zum Geburtstag“, „Zum Glück“) | never counted | never counted |
| `ungraded(pronoun)` | pronouns other than the six (or the six in a story that doesn't mark them) | never counted | never counted |
| `ungraded(noArticle)` | a capitalised word inside a sentence with no article (names, bare nouns), with the quantifier or adjective leading into it („viele Leute“, „mit großer Freude“, „nächsten Montag“; -e/-en only where the word before couldn't be the verb's subject, so „Wir trinken Kaffee“ keeps *trinken* plain), and every number word („zwanzig Kisten“, „um sechs“) | never counted | never counted |
| `ungraded(sentenceStart)` | a capitalised word opening a sentence or quote with no article that isn't a known function word (probably a name) | never counted | never counted |
| `ungraded(superlative)` | *am* + a word in -sten („am liebsten“, „am besten“), unless a noun follows an ordinary -sten word („am nächsten Morgen“ is an + dem) | never counted | never counted |
| `ungraded(idiom / standalone / unchecked)` | an idiom notTarget; an article word with no noun („Das ist …“); a phrase the validator couldn't grade („ein paar Entwürfe“) | never counted | never counted |

After Prüfen a tap shows `KasusMarking.note`: a target word's explanation (led by its real case
when the round asked another), why an ungraded word doesn't count („*zum* = *zu* + dem:
contractions aren't counted here.“), or why a plain word isn't part of the phrase („*mit* decides
the case of „dem Schlüssel“ (Dativ), but it isn't part of it.“). The ungraded notes say "not
counted here", never that no case shows, since an ending often does: „No article in front: names
and phrases without one aren't counted in this exercise.“, „Numbers don't change with the case“,
„Only *mich, mir, dich, dir, ihn* and *ihm* are counted in this exercise.“, and a name with a
Genitiv -s before a noun gets „*Saras* = Sara's: a name with *-s* is in the Genitiv, but names
aren't counted here.“ The Nominativ's instruction adds "Pronouns like *er* and *sie* aren't
counted."

**Feedback mode**, per exercise (`KasusFeedbackMode`, `kasus.markFeedback` /
`kasus.endingsFeedback`), in the options pill next to the instruction: „Sofort · After each answer“
judges each tap or pick with the `KasusFeedback` signal; „Am Ende · Check at the end“ judges
everything at Prüfen, then Lösung zeigen, then Noch mal. Defaults: Markieren Am Ende, Endungen
Sofort. The mode (and Endungen's help level) can't change while a round is under way (a pick made or
a Tipp taken: `KasusEndingsRound.settingsLocked`, so a rebuilt round can't forget a Tipp); changed
after Prüfen it starts a fresh attempt of the same round, which isn't recorded again.

**Markieren** (`KasusMarkView`). One case per round, „Markiere alle Wörter im Dativ.“ with
"Tap every word in the Dativ: the article, any adjective and the noun." (and the case's pronouns
when the story marks them). Order per unit (`KasusUnit.markCases`, skipping a case with no words
in the story): Nominativ → nom; Akkusativ → akk, nom; Dativ → dat, akk, nom; Genitiv → gen, dat,
akk, nom; Alle Fälle → nom, akk, dat, gen, shown as „Dat › Akk › Nom“ under the instruction.

- Am Ende: a tap marks a word (a light wash in the asked case's color), a second tap unmarks it;
  the tray counts „5 marked · 18 words to find“ above Prüfen. Prüfen (Fertig in Sofort) with
  nothing marked asks first and then records a round that answered nothing (no streak or XP):
  it's how to give up and see the answers.
- Sofort: each tap is judged at once (✓ on the case-color wash, or a grey ✗ struck through) with
  the verdict header; a wrong tap says why without naming a phrase still to be found, a word that
  never counts says so and stays unmarked. Fertig shows what was missed.
- After Prüfen / Fertig: right = ✓ on a wash in the case color, wrong = grey ✗ struck through,
  missed = a dashed outline in the case color. The tray has the score („6 / 10“, „8 richtig · 2
  falsch · 2 übersehen“; max(0, right − wrong) / words to find, so marking everything scores low),
  „Alle Fälle“ (every phrase washed in its own case's color, the verdicts kept; only after Prüfen,
  and off again after Noch mal, a mode switch or the next case), „Lösung zeigen“ (the missed words
  wash in the case color and the first of them scrolls above the tray; recorded, flagging only the
  missed and partly marked phrases, never a wrong mark), „Noch mal“ (clears, unrecorded) and
  „Nächster Fall · Akkusativ“ (a new round, recorded on its own), or „Weiter: Endungen“ after the
  last case. A tap on any word shows its note.
- Recognition only: streak and XP count the words to find, the coach never hears of it. Its
  per-case tally (Verlauf's bars, a row's strip, the round detail's „Nach Fall“) is the class
  score's points, right minus wrong, so the bars agree with „6 / 10“ and marking everything fills
  nothing (`KasusRound.perCase` reads it from `markScore` on older rows too).

**Endungen** (`KasusEndingsView`). Only definite (der … des) and ein (ein … eines) articles become
gaps, with the stem as written („D__“, „d__“, „ein__“); possessives, kein and dieser stay written
out, and so do the adjective and noun endings. Buttons: -er -ie -as -en -em (-es) and – -e -en
-em -er (-es); -es only once Genitiv is in play. Gap selection is the old Einsetzen's
(`blankCases`: the unit's case, every case in play when gemischt, the Nominativ only at Ohne
Hilfe). A chosen ending goes back on its stem and is graded as before. Four help levels, one
control in the options pill (`kasus.hintLevel`, default Genus-Hilfe at A1–A2 and Ohne Hilfe from
B1; the Nominativ unit runs at Ohne Hilfe only):

| Level | Shows | Buttons | Moves the case skill? |
|---|---|---|---|
| Lernhilfe (first) | the endings table in the tray with the gap's cell (case row × gender column) ringed in the case color and its ending bold, the gender and case chips above the buttons, the „(m)“ tag, the trigger underlined | the noun's own gender, padded to 3 | no |
| Viel Hilfe | the table (nothing ringed), the gender chip and tag, the trigger underlined | the noun's own gender, padded to 3 | no |
| Genus-Hilfe | the gender chip („Bruder · m“) and tag | the whole row | masculine only |
| Ohne Hilfe | the Tipp button (trigger → gender → case → answer), the sg/pl tag | the whole row | unless the Tipp showed the case or answer (or the gender of an f/n/pl Akkusativ) |

The table is `CaseEndingsTable(compact:)` for the unit's cases in play („Endungstabelle“): small
type, each form split where Endungen splits it (d·**em**, ein·**em**, and ein·**–** where the
buttons say „–“), folding to one line („Tabelle zeigen“, remembered
in `kasus.endingsTableOpen`). At the largest text sizes a row label drops its icon, then shrinks,
rather than break „Nom“ into one letter per line. A time phrase with no preposition („jeden Tag“) has no deciding
word: nothing is underlined, and the Tipp's first clue reads "A time phrase: wann? wie oft?".

The tray reads top to bottom: the dots (Sofort) or „3 of 8 filled“ (Am Ende) with the Tipp and,
in Sofort, „Lösung“; the verdict and why once picked (Sofort); the table; then, pinned, the
gender and case chips, the ending buttons and the main button. Only the part above the chips
scrolls when the tray runs out of room, so a four-case table at Lernhilfe (Genitiv, Alle Fälle)
never pushes the buttons out of reach.

- Sofort: the first pick is graded and locked, with the `KasusFeedback` signal. Right: the gap fills
  with the answer, its letters in the gender color on a wash in the case color (✓ in the corner;
  never a gender-colored wash, so a right feminine „der“ never sits on red), and the next gap comes
  up after 800 ms. Wrong: ~~der~~ dem in the text, the verdict and why (a slip gets its slip note),
  and Weiter. The table folds away once a gap is judged. „Lösung“ fills every gap not picked yet
  (never counted) and finishes the round.
- Am Ende: tap any gap and pick freely (a pick shows only as chosen; the next empty gap comes up;
  tapping the chosen ending again empties the gap). Prüfen with gaps still empty asks first
  („3 gaps are still empty · An empty gap counts as not answered.“), even with none filled, which
  is how to give up and see the answers. After Prüfen: ✓ or a grey ✗
  on every gap, but a wrong gap keeps its answer back until „Lösung zeigen“ (a tap says only how
  it was wrong and in which case), so „Noch mal“ is still a real try; an empty gap has a dashed
  outline. Then Ergebnis.
- The footer (the chips, the ending buttons, then Weiter, Prüfen or Ergebnis) is pinned under
  the tray, and the main button holds its place with a hint before Weiter appears, so the ending
  buttons never move under a finger and a quick second tap can't land on Prüfen.
- A fresh round (or coming back to one) scrolls the focused gap's sentence to just above the
  tray when the tray covers it (at Lernhilfe it takes almost half the screen), and again if the
  tray settles at another height in the first second (its content animates in); a gap already in
  view doesn't move. The clock stops at any finish, a Noch mal's too, so Ergebnis's time holds.

Grading ignores capitalisation and takes the first pick in Sofort, the pick standing at Prüfen in
Am Ende. Three kinds of wrong:

- **Gender slip:** the right case for another singular gender („in dem Tasche“).
- **Number slip:** the right case in the other number on a noun that reads the same in both
  („nimmt die Schlüssel“ for one key; „der Nachbarn“ for „des Nachbarn“, since an n-noun's -n
  outside the Nominativ is also its plural, except Herr and a Name-type Genitiv). A plural answer
  picked in the singular counts too.
- **Case miss:** everything else, including any form the noun's own gender takes in another case.
  „auf der Boden“ is the Nominativ left unchanged, a case miss, even though „der“ is also the
  feminine Dativ.

**The tray** (`KasusTray`) is the same for every step: its content scrolls past 40% of the step (the
largest text sizes, or a four-case table on a small phone) while the footer stays in view; a verdict
and its why scroll past 30% (20% at the accessibility sizes). At the accessibility sizes a checked
round's Lösung zeigen, Noch mal (and Markieren's Alle Fälle) move into the pinned footer as one row
of bordered buttons, their German where it fits and the icon alone where it doesn't
(`KasusFooterLabel`), so a long note can't scroll them out of sight. The step bar stops growing at
the navigation bar's size so „Markieren“ never truncates.

**Ergebnis** (Endungen's). The round on screen: „5 / 8 richtig“ (as the tray and the round detail
write it), per-case counts, time, help level and mode, the
misses in their numbered sentences with their explanations (held back in Am Ende until Lösung
zeigen, which it offers too), „Noch mal · eine Stufe schwerer“ at 80% or more, „Noch mal ·
gemischt“ and „Noch mal · Retry“ (the same gaps, unrecorded).

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

One signal for Endungen, Markieren in Sofort and the Schnellrunde:

| | Header | Answer buttons | Strip dot | Haptic |
|---|---|---|---|---|
| Right | „Richtig!“, the check bouncing in the case color, then the case | the pick fills in the case color with a ✓ and a small pop | filled, case color | success |
| Slip (gender or number) | „Fast · Almost“, grey half circle | as a miss | grey ring with a center dot | light tap |
| Miss | „Nicht ganz · Not quite“, grey | the pick shakes, greys out, is struck through with an ✗; the answer is outlined in the case color with a ✓; the rest fade | hollow grey ring | error |

- The strip (`KasusProgressStrip`) has one dot per question and a running ✓ count; past 20 marks
  the dots keep their size and wrap onto more rows.
- `KasusCappedScroll` holds the verdict and its explanation at their own height up to about 30%
  of the screen and scrolls past that, so at accessibility text sizes a long why never pushes the
  buttons or Weiter off screen. At large sizes the header's case label moves to a second line and
  a button's ✓/✗ gives way to the word.
- Endungen's Am Ende buttons have a sixth look, chosen (outlined in the tint, still live), so a
  choice never reads as right or wrong before Prüfen.
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
| akkusativ, dativ, genitiv | `.kasus(unit)`, launch | Endungen in the unit's least-recently-played story (even one never played), or its Schnellrunde while the unit has no story |
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
  Time is per step: hopping between Markieren and Endungen pauses the other's clock.
- One `KasusRound` per scored step (below).
- The coach (`applyDrillResult`) only from Endungen (and Einsetzen) and the Schnellrunde, only
  unscaffolded first picks, only a case with at least 3 of them, once per case per round. Left
  out: Lernhilfe and Viel Hilfe; f/n/pl at Genus-Hilfe; at Ohne Hilfe a Tipp that showed the case
  or answer, or the gender of an f/n/pl Akkusativ; f/n/pl Akkusativ in the Schnellrunde (its
  header names the article); every slip; every answer Lösung zeigen filled and every gap left
  empty. Nominativ writes nothing, and no `GrammarFocus` was added. Markieren (and Finden) never
  reaches the coach; its streak count is the words to find.

### `KasusRound`

A SwiftData model, additive, every field defaulted (registered in `german_ai_flashcardsApp`).

| Field | Holds |
|---|---|
| `date` | when the step was scored |
| `storyID` | the story's id, or `quick-<unit>` for a Schnellrunde |
| `unitRaw` | a `KasusUnit` raw value |
| `stepRaw` | `find` · `fill` · `quick` (`KasusRoundStep`) |
| `hintLevelRaw` | `lern` · `viel` · `genus` · `ohne` for Endungen (and Einsetzen); empty otherwise |
| `askedCount`, `firstTryCount` | items asked, right on the first pick. Markieren: the words to find, the words marked right |
| `wrongCount` | Markieren: words marked that weren't in the asked case. Score = max(0, firstTry − wrong) / asked (`markScore`) |
| `markCaseRaw` | Markieren: the case the round asked; empty otherwise (and on the old Finden) |
| `feedbackModeRaw` | `sofort` · `amEnde` for Markieren and Endungen; empty on the Schnellrunde and on rounds from before them, which is how `stepLabel` knows to say „Finden“ / „Einsetzen“ |
| `revealedAnswers` | Lösung zeigen was tapped („Lösung angezeigt · Answers shown“) |
| `roundKey` | the result's id, so Lösung zeigen after recording finds the row |
| `durationSeconds` | that step's own clock |
| `perCaseData` | encoded `[case: {asked, firstTry}]`. A Markieren round reads its tally from `markScore` instead (points, not right words) |
| `itemsData` | encoded `[KasusRoundItem]`, one per answer: sentence, phrase (and where it starts), answer, pick (a Finden pick is the painted case), case, gender, outcome (`right`, `caseMiss`, `genderSlip`, `numberSlip`, `missed`, `wrongPick`, and since Phase 3a `partial` and `wrongMark` for Markieren, `unanswered` and `revealed` for Endungen; stable raw values), `revealed` (Lösung zeigen showed it), `markedWords` / `wordCount` (Markieren), whether it counted toward the coach, the explanation in `KasusRich` markup (a slip stores its slip note), the target's index, and `hasNounGender` (false for a pronoun; nil on items saved before it, where the round detail checks the answer's form instead). Built by `KasusService.round(for:date:)`, which also sets the counts-toward-coach flag; the Schnellrunde's come from `EndingsQuestion.roundItem(pick:)`. Nil on older rounds and the record check's synthetic ones |

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

A Swift Testing target in the `german-ai-flashcards` scheme; `test_sim` runs its 98 tests. Debug
only, since they use `KasusFixtures` and `KasusStoryBank.only`. They read the bundled JSON
directly instead of `KasusStoryBank.bundled`, whose DEBUG assert would stop the whole run on one
broken story instead of failing one test.

| File | Covers |
|---|---|
| `KasusFormsTests` | every cell of the endings table for 12 determiner families, both ways; the 184-cell round trip; option sets; gender and number slips; plurals, n-nouns, the Genitiv -s; contractions against `prepositions.json`; the six pronouns; decoding a target |
| `KasusValidatorTests` | each of the 46 fixtures raises exactly its code; every bundled story passes with its golden numbers and keeps the `KasusLocatedTarget` contract; generated-story and story-level rules; severities; issue codes stay stable |
| `KasusExplanationTests` | every target's explanation is clean markup, the Finden note only on label targets; pinned lines; every rule line, the Kasus-Check card and every Schnellrunde feedback are clean markup |
| `KasusServiceTests` | blanks per hint level, options, grading, the sg/pl tag, feedback, the Einsetzen and Finden results, the harder-round offer, the Weiter row, the debugVerify service block |
| `KasusMarkingTests` | sentence numbering and punctuation on every story, every target word classified with its case, the words that never count, each unit's case order, the class score, Am Ende and Sofort rounds, pinned notes, the instruction, the Markieren result, feedback-mode keys and defaults |
| `KasusEndingsTests` | both families' ending rows, gap selection, every gap's stem and buttons on every story, pinned buttons, ending grading with slips, what each hint level shows, Sofort and Am Ende rounds, empty and revealed gaps, Lernhilfe never counting |
| `KasusRecordingTests` | which answers count toward the coach, the fifteen record-check rounds, `recordRound` against an in-memory store, the Markieren round's stored fields, Lösung zeigen after recording, rounds from before Phase 3a |
| `KasusPlayStateTests` | the players' state (`KasusMarkPlay`, `KasusEndingsPlay`): a round recorded once at the first Prüfen or last pick, never after Noch mal or a mode switch; Lösung zeigen flagging the recorded attempt; Nächster Fall recorded on its own; „Alle Fälle“ off after Noch mal, a mode switch and the next case; a DEBUG prefill never handed on; a Tipp locking the help level and mode |

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
slip), the sg/pl tags, the numbered sentences and each word's role (printed for sentence 1), the
words to mark per case, the Markieren case order and class score (and that marking everything
scores 0), Sofort marking, the Endungen gaps, stems and buttons per help level, ending grading,
Lernhilfe's highlighted cell, the default hint per level, and `KasusPath.next` over seven
synthetic histories.

**`-kasus.debugVerifyRecord 1`** runs `recordRound` on fifteen synthetic rounds in the live store and
checks what each one moved, then puts everything back (`keep` leaves the rounds and the skill
changes; they are filed under `debug-verify-record`, so they never mark a real step done).
Expected: rounds #1–#13 (Viel Hilfe, under 3 per case, f/n/pl Akkusativ at Genus-Hilfe, a Tipp
that showed the answer, gender slips, a gender Tipp on f/n/pl Akkusativ, Nominativ, f/n/pl
Akkusativ in the Schnellrunde, Finden, Lernhilfe, answers Lösung zeigen filled, Markieren with
wrong marks) move no skill; #14 moves Dativ and #15 moves Akkusativ. The Markieren round is read
back too: `Markieren · Dativ · 6 / 10 · 2 wrong`.

```
#1 Viel Hilfe · 5 Akk m, all wrong (scaffolded)
   grammarExercises +5 · KasusRound +1 · akk –→– · dat –→– · gen –→– · PASS
…
#13 Markieren · Dativ, 10 words: 8 marked + 2 wrong marks (recognition only; 10 answered)
   grammarExercises +10 · KasusRound +1 · akk –→– · dat –→– · gen –→– · Markieren · Dativ · 6 / 10 · 2 wrong · PASS
#14 Ohne Hilfe · 4 Dat wrong + 2 Nom → moves Dativ
   grammarExercises +6 · KasusRound +1 · akk –→– · dat –→0.20 · gen –→– · PASS
#15 Genus-Hilfe · 3 Akk m wrong + 3 Akk f → moves Akkusativ (m only, exactly 3)
   grammarExercises +6 · KasusRound +1 · akk –→0.20 · dat 0.20→0.20 · gen –→– · PASS
ALL OK · 15 rounds
restored: coach skills, 15 rounds removed, grammarExercises −72
```

**`-kasus.debugOpen <screen>`** opens a Grammatik screen at launch, since the simulator can't tap
its way there, and prints `[kasus.debugOpen] open <screen>`:

| Screen | Opens |
|---|---|
| `hub` | the hub, in a sheet |
| `unit:<unit>` | a unit screen in a sheet: `nominativ`, `akkusativ`, `dativ`, `genitiv`, `alleFaelle` |
| `quick:<unit>` | the unit's Schnellrunde |
| `read` | the first bundled story („Der verlorene Schlüssel“) at Lesen; `-kasus.debugStory <id>` picks another for every player screen |
| `mark` | Markieren, its first case, marked if `-kasus.debugAnswers` is given (in Sofort the last tap's verdict in the tray) |
| `mark-checked` | Markieren after Prüfen, the first wrong mark's note in the tray |
| `mark-revealed` | Markieren after Prüfen and Lösung zeigen |
| `fill` | Endungen, all but the last three gaps answered if `-kasus.debugAnswers` is given (Sofort: the last wrong one's verdict in the tray) |
| `fill-checked` | Endungen in Am Ende (whatever is stored) after Prüfen, the last gap left empty |
| `result` | Ergebnis |
| `history` | Verlauf, in a sheet |
| `round` | the newest Kasus round that kept its answers, in a sheet |
| `round-mark` | the newest Markieren round that kept its answers (one with a miss or a wrong mark first), in a sheet |

- `-kasus.debugAnswers right|mixed` prefills the answers (`KasusService.debugMarks`,
  `debugEndingPicks`). `mixed` gets about one gap in three wrong in Endungen, and in Markieren
  leaves one phrase in four unmarked and marks the first plain word of every fifth sentence.
  `mark-checked`, `mark-revealed`, `fill-checked` and `result` use `mixed` when it isn't given.
  Prefilled answers are never recorded (a Nächster Fall or another help level after them is).
- `-kasus.debugHint lern|viel|genus|ohne` picks the help level for that launch without overwriting
  the stored one; `-kasus.debugFeedback sofort|amEnde` does the same for both feedback modes
  (`KasusPrefill.feedback`). Changing either in the options pill then changes only that launch.
- `-kasus.debugStory <id>` opens `read` … `result` on that story instead of the first, e.g.
  `-kasus.debugOpen mark-checked -kasus.debugStory ks-nom-a1-foto -kasus.debugAnswers mixed`.
- `-app.theme klar|sanft|kritzel|grundform` shows the player in another theme.
- `-kasus.debugQuickState right|wrong|slip|done`, with `quick:<unit>`, answers the Schnellrunde's
  next question that way (`done` finishes the round); with `-kasus.debugAnswers right|mixed` the
  first four are answered first. Never recorded.
- `-kasus.debugRoute 1` prints where every `GrammarFocus` goes from Today, Coach's Notes, the
  pyramid and a class entry, and ends `OK` when no case, article or preposition focus falls back
  to the lesson sheet.
- Combine with `-level.debugDeclare A1|B1` to check the hero's start unit and the default hint
  level.

**`-kasus.debugSeedRounds 1`** inserts most of a week of rounds so Verlauf has something to show:
today Markieren in the Dativ (Am Ende, misses and wrong marks), Markieren in the Akkusativ
(Sofort, all right) and Endungen at Genus-Hilfe (Am Ende, answers shown afterwards) on the bundled
Dativ story; the Nominativ and Akkusativ Schnellrunden; an Einsetzen from before Endungen (the old
label); one Dativ Schnellrunde stored without answers (how older rounds look); and two
der/die/das and two preposition rounds. The
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
- ✅ Phase 3a engine: numbered sentences, word roles, Markieren (one case per round, the class
  score), Endungen (stem + ending gaps, ending buttons, Lernhilfe), feedback modes, the new
  `KasusRound` fields, Lösung zeigen after recording. 28 new tests.
- ✅ Phase 3a views: Markieren and Endungen in the player on numbered sentences of word chips, the
  Lernhilfe table with its ringed cell, the options pill (help level, feedback mode), Lösung zeigen
  wired to `markAnswersShown` (`onAnswersShown`), a pinned tray footer, and Verlauf / the round
  detail / the calendar showing `stepLabel`, the class score and „Lösung angezeigt“.
- ⬜ The old Finden / Einsetzen APIs no screen calls any more (`gradeFind`, `findResult`,
  `findCounts`, `nonTargetNote`, `KasusFindMark`, `blanks`, `KasusBlank`, `options`, `fillResult`,
  `debugPaint`, `debugPicks`, `findenBrushes`) can go, with the tests, `debugServiceReport` lines
  and record-check round that still use them.
- ⬜ Markieren's wash, badges and shake/pop, and Endungen's pinned chips, buttons and footer, not
  yet felt on a device; the chip size (title3, 5 pt padding, 5 pt between lines, tap area into
  half of each gap) is a first guess worth checking with a thumb.
- ⬜ Teacher notes from the review: „Letzten Sommer“ and „Nächsten Montag“ open their sentences, so
  they're never counted; making them time targets (Akk, like „jeden Sommer“) needs a validator
  rule for a phrase without an article. The Nominativ unit's Endungen still runs at Ohne Hilfe
  with the whole row of buttons (the spec kept the old blank rules); a Lernhilfe there would be
  the teacher's call.
- ⬜ Phase 3: tutor-written stories in the same format, gated by the validator, with a Lab.
- ⬜ No bundled story has a teacher review yet (`reviewed` is empty), and the seven new label
  targets need the teacher's check too.
- ⬜ Homonyms with two plurals (Bank: Bänke/Banken) fail `morph.pluralForm` on the reading the
  Goethe list doesn't give.
- ⬜ In the endings table the three-line cells (Dativ plural, Genitiv m/n) draw their article at
  about 80% size, a little higher than the rest of the row.
- ⬜ In a Nominativ Markieren round, a marked word's graphite wash is close to the grey of a wrong
  mark after Prüfen (the ✗ and the strikethrough tell them apart).
- ⬜ Device verdict in all four themes; the new screens were seen in the simulator in Klar and
  Grundform (Bauhaus), and at the largest text size on a small phone.
