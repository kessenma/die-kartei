# Grammatik — the case path and the Kasus stories

One path through the four cases, Nominativ → Akkusativ → Dativ → Genitiv → Alle Fälle, where every
unit runs the same loop: **Regel → Geschichte (Lesen → Markieren → Endungen → Ergebnis) →
Schnellrunde**. The stories are the two worksheets from a German class on one text: mark every word
in a case, then fill in the article endings. A deterministic validator is the answer key; it gates
the bundled stories and the tutor-written ones (Phase 3, behind a developer toggle).

Status legend: ✅ done · ⬜ open

## Where things live

| Piece | File |
|---|---|
| Units (cases in play, Markieren's case order, level labels, rule lines, start unit) | `Models/Grammar/Kasus/KasusUnit.swift` |
| Story format (stored fields, reasons, located targets) | `Models/Grammar/Kasus/KasusStory.swift` |
| Forms engine (determiner families, table lookups, options, slips, noun endings, word lists) | `Models/Grammar/Kasus/KasusForms.swift` |
| Validator (locate, prove, issue codes, policy) | `Services/Grammar/Check/KasusValidator.swift` |
| Explanations, built from the proof only | `Services/Grammar/Kasus/KasusExplanation.swift` |
| Loader, `AppKasusLexicon`, the DEBUG assert | `Services/Grammar/Content/KasusStoryBank.swift` |
| Planted-error fixtures, golden numbers, table round trip (DEBUG) | `Services/Grammar/Content/KasusFixtures.swift` |
| Sessions, blanks, grading, `recordRound`, progress, `KasusPath` (the hero) | `Services/Grammar/Kasus/KasusService.swift` |
| Numbered sentences, word roles, the Markieren round and score, feedback modes (Foundation only) | `Services/Grammar/Kasus/KasusMarking.swift` |
| Endungen: gaps, ending buttons, grading an ending, the Endungen round | `Services/Grammar/Kasus/KasusEndings.swift` |
| The round record | `Models/Grammar/Kasus/KasusRound.swift` |
| Bundled stories | `Resources/kasus_stories.json` |
| Hub | `Features/Grammar/Hub/GrammarHubView.swift` |
| Unit screen, story player, story text, Kasus-Check card | `Features/Grammar/Topics/` (unit screen), `Features/Grammar/Story/` (player, story text, Kasus-Check card) |
| The story player: step bar, Lesen, Ergebnis, the exercises' state, DEBUG screens | `Features/Grammar/Story/KasusStoryView.swift` |
| Markieren's screen and state (`KasusMarkPlay`) | `Features/Grammar/Story/KasusMarkView.swift` |
| Endungen's screen and state (`KasusEndingsPlay`, `KasusGapState`) | `Features/Grammar/Story/KasusEndingsView.swift` |
| Numbered sentences as word chips (`KasusSentenceList`, `KasusWordFlow`, `KasusChip`) | `Features/Grammar/Shared/KasusSentences.swift` |
| Tray with a pinned footer, step clock, header, options pill | `Features/Grammar/Story/KasusPlayerParts.swift` |
| Right/wrong signal: verdict header, answer buttons, progress strip, capped tray scroll | `Features/Grammar/Shared/KasusFeedback.swift` |
| The `{m:den}` / `{dat:Dativ}` / `**bold**` markup and `Text(kasusRich:)` | `Features/Grammar/Shared/KasusRichText.swift` |
| Endings table (and its compact tray version with a highlighted cell) + Schnellrunde (`CaseEndingsDrillView`) | `Features/Grammar/Reference/CaseEndingsView.swift` |
| Verstehen: kinds, exercises, roles, the Probe noun, items, facts (Foundation only) | `Models/Grammar/Kasus/KasusConcept.swift` |
| Verstehen: the lessons' cards and the Merkhilfen, as literals | `Models/Grammar/Kasus/KasusLesson.swift` |
| Verstehen: the item bank, its audit, the DEBUG assert | `Services/Grammar/Content/KasusConceptBank.swift` |
| Verstehen: playable items, the round, picks, the walk, explanations, `KasusService` entry points, progress marks | `Services/Grammar/Kasus/KasusConcepts.swift` |
| Verstehen: golden numbers per unit and kind, the verify block (DEBUG) | `Services/Grammar/Content/KasusConceptFixtures.swift` |
| The bundled Verstehen items | `Resources/kasus_concepts.json` |
| Verstehen screens: the lesson sheet, the Merkhilfen list, the activity and its panels, the unit section | `Features/Grammar/Topics/KasusLessonView.swift`, `KasusMnemonicsView.swift`, `KasusConceptView.swift`, `KasusConceptPanels.swift`, `KasusVerstehenSection.swift` |
| Day detail in the calendar | `Features/Home/StreakCalendarView.swift` |
| Verlauf (every round by day) and a round's answers | `Features/Grammar/History/KasusHistoryView.swift`, `KasusRoundDetailView.swift` |
| Sample rounds for the simulator (DEBUG) | `Services/Grammar/Content/KasusDebugSeeder.swift` |
| Where a grammar focus goes from Today, Coach's Notes, the pyramid and a class entry | `Services/Grammar/GrammarRoute.swift` |
| Tutor-written stories: plan model, planner, verb frames and noun pools | `Models/Grammar/Kasus/KasusStoryPlan.swift`, `Services/Grammar/Tutor/KasusStoryPlanner.swift`, `Resources/kasus_triggers.json` |
| Tutor-written stories: prompt, generator, check, harvest, sentence checks, store | `Services/Grammar/Tutor/KasusStoryPrompt.swift` (prompt, request/result; no MLX, so `training/kasus_cli` compiles it), `KasusStoryGenerator.swift`, `KasusStoryCheck.swift`, `KasusHarvest.swift`, `KasusSentenceCheck.swift`, `KasusStoryStore.swift`, `Models/Grammar/Kasus/GeneratedKasusStory.swift` |
| Kasus Lab numbers and canned fixtures (DEBUG) | `Services/Grammar/Tutor/KasusLab.swift`, `Services/Grammar/Content/KasusGenerationFixtures.swift` |
| Unit row, generation sheet, Lab screen | `Features/Grammar/Story/Tutor/KasusAIStorySection.swift`, `KasusGenerationSheet.swift`, `KasusLabView.swift` |
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
with a dot for Verstehen (the lesson read and every offered drill played), a dot per story,
filled once its Markieren and Endungen are both played, one for the Schnellrunde, and a flame on
a case the coach has as shaky), **Verlauf** (one row with the last round's score) and
**Werkzeuge** (Präpositionen, Der · Die · Das, Die Endungen, Merkhilfen). A unit screen
has **Die Regel** (open until the unit's first round; with a link to the Lektion and the
Kasus-Check), **Verstehen** ([below](#verstehen--understand)), **Geschichten** (one row per
story: level, Markieren ✓/○, Endungen ✓/○), the **Schnellrunde**, the endings drill limited to
the unit's cases, **Deine Runden** (the unit's last three rounds and "Alle anzeigen") and **Mehr
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
1b. with the Verstehen items in hand (the hub passes `concepts: .bundled`; the default `nil`
   keeps every older expectation): before a unit's first story, its Lektion while unread, then
   Rollen while unplayed;
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

## Verstehen · Understand

The concept layer the path lacked: for an English speaker the hard part isn't the ending, it's
knowing what a *direct object* or a *receiver* is before the endings mean anything. Two findings
shaped it. Explicit information plus **structured input** (VanPatten's Processing Instruction;
Henry, Culman & VanPatten 2009 on German `den`) beats either alone: a short rule, then sentences
where the ending is the only clue to who does what, because English speakers read the first noun
as the doer. And the German classroom's **Satzproben**: the Ersatzprobe (swap in *der Mann*, the
one gender whose article shows every case) and the Umstellprobe (a block moves, the meaning
stays). The Kasus-Check stays the way to decide; wer/wen/wem/wessen appear only as the English
speaker's handles on the roles. Sources are in Settings ▸ About ▸ Sources.

Every unit screen has a **Verstehen** section between Die Regel and Geschichten, with ✓ per row:

| Row | What the learner does | Records as | Coach |
|---|---|---|---|
| **Lektion** (`KasusLessonView`, a sheet) | 4–6 paged cards (`KasusLesson.cards`): the role, „Englisch zuerst“ (I/me, he/him, who/whom/whose; the „to“ test for the Dativ; 's / of for the Genitiv), the case's trick, a worked example in Kasus-Check order, the trap, a Merkhilfe. Every German example has an English twin with the phrases in the same case colors. „Üben“ launches Rollen once the sheet has gone. | one `lesson` round per unit (asked 0, time only) when the last card is first shown; hidden from every list | never |
| **Rollen** (`.roles`) | 8 sentences as word chips; each asked phrase is ringed and gets a role chip (the Kasus-Check step: Präposition · Gehört zu · Subjekt · = Subjekt · Empfänger · Direktes Objekt, only the steps in play). The case is revealed after the pick. **Schritt für Schritt** (the default, `kasus.rolesMode`) asks the Check's questions one at a time with Ja/Nein instead: the first Ja decides, a Nein to every question is the direct object; a wrong Ja is explained and the walk goes on, a wrong Nein at the deciding question ends it with the answer. The mode is in the toolbar and locks once an answer is in. | `concept-<unit>-roles`, one item per phrase | never |
| **Wer macht was?** (`.wer`) | 10 items: 7 „Wer …?“ sentences (3–4 object-first: „Den Hund jagt die Katze“), two phrases to pick from, and 3 „Gleich oder anders?“ pairs (the Umstellprobe). After the pick the phrases take their case colors and the English appears. | `concept-<unit>-wer`, filed under the **clue's** case | never |
| **Die Probe** (`.probe`) | 8 sentences with an ambiguous phrase underlined („Ich helfe *der Frau*“): pick the form of the test noun that fits (der · den · dem Mann, des Mannes once the Genitiv is in play). The swapped sentence appears under the original. | `concept-<unit>-probe`, the swapped sentence as the item | like the Schnellrunde: first picks, ≥3 per case; an f/n/pl Akkusativ counts too, since nothing names the article |

The Nominativ unit offers Lektion and Rollen only; which rows a unit offers comes from the data
(`KasusConceptBank.offered`: an exercise needs `minimumItems`, 4 / 6 / 4). **Merkhilfen** (the
hub's Werkzeuge, `KasusMnemonicsView`; `KasusMnemonics.all`) lists the memory aids one line
each: the role hooks (Name · Accused · Donation · Genes), the model sentence, the Check, the
masculine chain, the code words, „nur der wird den“, DOGFU, the Blue Danube, the two-way tune,
the Genitiv four beats, the noun endings, the „to“ test. Never a chart.

**Items are mini-stories** (`Resources/kasus_concepts.json`, `KasusConceptItem`): one flat object
per item with the story fields the validator needs (`id`, `unit`, `level`, `paragraphs`,
`targets`, `notTargets`) plus `kind` (`roles` · `whoDoesWhat` · `sameMeaning` · `probe`) and the
kind's keys: `ask` (Rollen, optional), `question {de, en}` + `options` + `answer` (target
indices; the answer is the subject), two paragraphs + `same`, `probe {target, noun}` (Mann · Hund
· Lehrer · Vater). A target may carry `en`, its phrase in the English line, so the twin can wear
the case color. Ids are `kc-<case>-<kind>-<slug>` for the 124 hand-written items, and
`kc-s-<case>-<kind>-<seed>` / `kc-sg-gen-<kind>-<seed>` for the 592 Claude Sonnet wrote around
the app's own plans (2026-10-07; every one through the concept gate, `audit-concepts` and a read;
`training/data/kasus-concepts-sonnet/`, `training/KASUS_CONCEPT_PROBE.md` §7). 716 in all, about
40–50 per unit and exercise. Their added place and time phrases are validated targets that
Rollen never asks (`ask` lists the planned phrases). Everything else is derived at load into
`KasusConceptFacts`: a target's **role** is read off the Kasus-Check (`preposition != nil` →
Präposition, else `subject` → Subjekt, `predicate` → = Subjekt, `object` → Direktes Objekt,
`recipient` / `dativeVerb` / `dativeOther` → Empfänger, `attribute` → Gehört zu; a bare time
phrase or an inferred target has none and is never asked), the asked targets, the Wer item's
**clue** (the option whose proof is `form` or `preposition`), whether it is object-first, and the
Probe phrase's ambiguity. `KasusConceptBank.audit` is the answer key: the validator under the
`.authored` policy with the story-level codes left out (a one-sentence item is always "too
short"), zero warnings, plus the facts' `problems`. The DEBUG loader asserts every bundled item
passes; `-kasus.debugVerify 1` prints one line per unit and kind with golden numbers
(`KasusConceptFixtures.golden`) and „Concepts ALL OK“.

Invariants:

- **Never single-case past Nominativ.** `KasusConceptRound.compose` reshuffles until a Rollen
  round covers two cases and a Probe round asks two different forms.
- **A Wer item is decided by a form.** Its clue is form- or preposition-proven; the partner of a
  feminine/neuter/plural doer may be label-proven, which is exactly the processing problem the
  exercise trains. Nothing but word order deciding is refused. Per unit, 4 of 8 are object-first.
- **A Probe phrase could be two cases** (`candidates.count > 1`), is an article phrase, never
  masculine. Dativ probes are feminine (`dem` + n and `den` + pl already show their case).
- **Rollen, Wer and a lesson never move the coach;** the Probe may (`countsTowardSkill`).
- **No new `KasusRound` field:** the four new `KasusRoundStep` raw values (`roles`, `wer`,
  `probe`, `lesson`) and the `concept-` story ids carry everything, so the sync codec is untouched.
  A build that doesn't know a step reads the round with `step == nil` and a plain row.

Explanations are the target's own (`KasusExplanation`) with a role line in front („**Empfänger**
(the receiver) → {dat:Dativ}. …“), the walk's Ja/Nein lines (`KasusConceptExplanation.whyNot`),
the Wer reading („{m:Den} + a masculine noun can only be {akk:Akkusativ}: „Den Hund“ is what
*jagt* acts on, so „die Katze“ is the doer, even though it comes second. Word order doesn't decide
here; the ending does.“), „Gleich/Anders“ from the two sentences' roles, and the Probe's swap line.
The screen is `KasusConceptView` (the Schnellrunde's layout: strip, hero, pinned answer panel,
Weiter slot that never moves), with `KasusRolesHero` / `KasusRoleGrid` / `KasusWalkPanel`,
`KasusWerHero` and `KasusProbeHero` in `KasusConceptPanels.swift`. Right is the case color, wrong
grey; the Ja/Nein buttons take the tint until the deciding question, so they never name the case
ahead of the Check.

The **AI seam**: an item is a `KasusStory`, so a tutor-written set can go through the same
planner / prompt / check and `KasusConceptBank.audit`, and merge in by id
(`KasusConceptBank.merging`, `KasusConceptSource.generated`). Not built; nothing reads it yet.

### Tutor-written Verstehen items (probe 2026-10-06)

Measured, not shipped. The tutor only writes one sentence around phrases the app planned; it never
decides a case. Full numbers, the hand read and the options: `training/KASUS_CONCEPT_PROBE.md`.

- **Code** (Foundation only, compiled into `training/kasus_cli` too): `KasusConceptPlan`,
  `KasusConceptPlanner` (seeded; one shared verb with er/sie/es present and past forms; at most
  one bare phrase whose article fits several cases), `KasusConceptPrompt` (`SATZ: …`, additions
  with a preposition allowed, no person, no clause), `KasusConceptCheck` (verbatim phrases, verb
  form, Wer order, no planned phrase behind a preposition or a noun, one simple clause, extras only
  behind a preposition and proven, then `KasusConceptBank.audit` with the plan as the label plus
  the generated-story rejects). Proven additions become targets that Rollen never asks.
- **Why an ambiguous phrase is gradable here:** the label is the app's plan, and one clause with
  a form-proven subject and one more phrase fixes who is who. Two ambiguous bare phrases are
  refused (`concept.ambiguousRoles`).
- **Results** (2 samples × 130 plans per tutor): templates 100%; E4B 70% (84% of plans with one
  retry), E2B 63% (78%), Granite 4.1 39% (55%), Granite 3.3 17% (27%). No E4B or E2B pass had
  a wrong case or role; their few slips sit in added phrases. Wer macht was? is the weak
  exercise: the tutors "fix" object-first sentences into subject-first ones, and the gate turns
  those away.
- **Tests:** `KasusConceptGenerationTests` (planner determinism and coverage, every template
  passes, prompt hygiene, one fixture per reject code). `kasus-cli audit-concepts` keeps every
  bundled item passing the same audit (716/716; `--golden` prints the table for
  `KasusConceptFixtures`).
- **Shipped instead:** no on-device generation. The bundle grew to 716 items, written offline by
  Claude Sonnet through the same planner and gate, read, then merged (`concept-export`). The
  planner also learned the Genitiv attribute (a phrase's `head`; possessors from a table of
  plausible relations), which the gate only accepts right behind its noun.

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

The table on `KasusLocatedTarget` (`Models/Grammar/Kasus/KasusStory.swift`) lists what a view can rely on per
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
`story.unitCaseCount`, `story.wordCount`. Generated stories only: `trigger.wechselUnconfirmed`,
`sentence.verbAgreement`, `sentence.unknownWord`, `sentence.lowercaseNoun`,
`sentence.copulaAkkusativ`, `sentence.objectNominativ`, `sentence.repeated` (see
[Tutor-written stories](#tutor-written-stories-phase-3)).

**Severity.** Every code is an error except these (`KasusValidator.Policy.severity`):

| Code | Authored | Generated |
|---|---|---|
| `lex.conflict`, `lex.unverified` | warning | warning |
| `story.wordCount` | warning | warning; error under half the level's range |
| `coverage.untargetedDeterminer` | error | warning |
| `trigger.wechselVerb` on a motion verb that isn't liegen/stehen/sitzen/hängen or legen/stellen/setzen | warning | warning |

**Policy:** an authored story needs zero errors (`label` is fine: a human checked the role). A
generated story is rejected whole by any `morph.*`, `trigger.prepositionCase`,
`trigger.wechselVerb`, `sentence.*` or `story.*` error (too few gradable answers of the unit's
case, or under half the level's length), because each means the German itself is wrong or there
is too little to play; any other error (`lex.gender` included: a harvested target's gender comes
from the lexicon, so it could only mean a mislabelled target), a `label` proof or an unverified
gender only turns that target into plain text (not marked, not blanked, not scored). The counts
live in `KasusValidator.Policy`: 3 targets of the unit's case, 2 of each case for Alle Fälle. A
length outside the range is a warning for both sources; the half rule is the one the Stories
feature retries on.

An issue line reads `error   trigger.prepositionCase  #11 „mit“ takes the Dativ, but …`:
severity, code, the target's number in reading order (from 1), message. The debug report prints
them under the story's summary line, which then reads `FAIL`.

**Lexicon order** (`AppKasusLexicon`): plural-only list → dual-gender whitelist → Wiktionary when
unanimous → the Goethe rows compared per level → a reliable suffix → unverified.

## Tutor-written stories (Phase 3)

The app is always the answer key: it plans the phrases, the tutor writes prose around them, and
the validator proves every graded answer before a story is shown. A case only the tutor labelled
is never graded. One run is **Planen → Schreiben → Prüfen**, one retry with a new seed, then either
a saved story or a bundled one with an honest note. Off in Release: Settings ▸ Developer ▸
„KI-Geschichten im Kasus-Pfad“ (`kasus.aiStories`, on by default in DEBUG).

### Planner

`KasusStoryPlanner` is pure and seeded (SplitMix64), so a seed always gives the same plan. It
picks 5–8 phrases, at least 3 of the unit's case (the Nominativ unit plans mostly subjects),
definite or ein articles only, since those are the two Endungen blanks. Nouns are Goethe nouns at
or below the level with a unanimous gender (no n-nouns, dual-gender or plural-only nouns), plus
any learner nouns whose gender verifies. Verbs are at or below the level too (folgen and vertrauen
are on no Goethe list, so they're gone). Every planned phrase is checked to leave exactly one case.
The verb frames, noun pools, two-way pairs, Genitiv nouns and topics live in
`Resources/kasus_triggers.json`. Frames:

- subject: der/ein + masculine, its verb counted only in the third person singular (`lacht`,
  `lachte`, `hat gelacht`, `kann lachen`, `zu lachen`; never the bare infinitive), and shown
  conjugated in the prompt („der Bruder (Subjekt: der Bruder lacht)“). People only for singen,
  lachen, weinen, kochen, rufen, arbeiten, tanzen; pets (no Fisch) for kommen, warten, spielen,
  schlafen.
- object, Dativ verb, receiver: den/einen, dem/einem with the verb's noun categories.
- preposition: never an article it would contract with (zum, zur, vom, beim, im, am, ins, ans);
  „bei der Oma“ and „von der Tante“ are fine. um takes only „den Tisch / das Haus / den See / die
  Ecke / den Park“, definite; nach is definite only; zu is ein only, to a person you visit or an
  outing.
- two-way: auf/unter/neben with a position/placement pair (Wo → Dat, Wohin → Akk). Each pair
  names its furniture (sitzen/„sich setzen“ on seats and the floor, stehen/stellen on surfaces,
  liegen/legen on any furniture).
- Genitiv: wegen/trotz + a curated noun.
- `definiteOnly` nouns never take ein: kinship („der Bruder“; „ein Bruder“ invited „Mein Bruder“)
  and mass nouns („wegen des Regens“, never „eines Regens“).
- Memory saver on for the tutor: level at most A2, at most 6 phrases. Otherwise at most B1.

### Generator

`KasusStoryGenerator`, with the model call behind `KasusStoryWriter` so canned text can stand in
(tests, the Lab's fixtures, `-kasus.debugGenerate`).

- **Model:** German tutors only (`StoryStudyService.resolve(modelManager.selectedStoryModel)`),
  gated by `ModelReadiness` `.germanTutor`; never Apple Intelligence or a general model.
- **Prompt** (`KasusStoryPrompt`): the Stories feature's `storyPrompt` (level constraints, the
  TITEL:/GESCHICHTE: format) plus „Verwende JEDEN dieser Ausdrücke genau einmal und GENAU so
  geschrieben:“ and the phrase list with each verb hint, then „Schreibe genau diesen Artikel (der,
  den, dem, ein, einen …), nicht mein, dein, sein oder ihr. Am Satzanfang darfst du ihn
  großschreiben.“ Contract B asks for the article as written, not the dictionary form.
- **Call:** `MLXGenerationService.generateStreamedText` with the level's `storyMaxTokens` (+250
  for contract B's label block) at temperature 0.75. The output is plain prose parsed with
  `StoryStudyService.parseStory`, never JSON (the quote sanitizer would break „…“).
- **Memory** ([MEMORY.md](MEMORY.md)): one heavy resident. The generator only calls `loadModel`,
  which refuses while pictures are drawn, another model generates or the budget is over, and the
  refusal comes back as the `.failed` result's note. The writer also refuses while the batch
  queue or a chat reply is using the tutor, so two writes never share one model, and it asks
  again before the retry (a tutor dropped between the tries is reloaded, or the refusal is shown).
  It never unloads anything.
- **Abbrechen** cancels the write's task, so a tap during the prompt read-in isn't lost, and the
  sheet says „Stoppt …“ until the run ends. A write that stopped early or doesn't end on a full
  sentence is trimmed to its last full sentence before the check.

### Check: locate, harvest, gate

**Check** (`KasusStoryCheck`): parse (markdown and list numbers come off; a numbered list is
regrouped into paragraphs of four); locate (verbatim, with its verb in the sentence, and a
verb-frame phrase never right after a preposition); harvest every other article + noun phrase
(`KasusHarvest`): proven by form and preposition → an `inferred` target, whose explanation uses
only the form and the preposition; wrong → a target that makes the validator reject (an adjective
in between no longer hides a wrong article: „das große Tasche“); else ungraded, including a bare
„ihr“ (pronoun or possessive), a d-word after a comma (maybe a relative pronoun), a verb used as a
noun („beim Spielen“), a Genitiv plural that hangs on nothing („Der Zimmer ist groß“) and a Dativ
next to sein („Das ist dem Kind egal“). Nouns are read only through Goethe, planned and learner
lemmas, never the surface form (Wiktionary gives plural forms the singular's gender, which would
pass „dem Kinder“). A wrong phrase the validator doesn't confirm is dropped, and the landing check
reruns until nothing more drops. An ungraded phrase is plain text: neutral in Markieren, never
blanked, so Markieren never marks a correct, unplanned phrase as wrong.

**Two-way prepositions:** an inferred phrase names Wo?/Wohin? in its explanation, and can be
blanked in Endungen, only when a position or placement verb in its clause agrees. Without one it
is marked by its form („*in* takes the Akkusativ or the Dativ; here {f:der} + a feminine noun can
only be Dativ“) and never blanked, since only the tutor chose Wo or Wohin. A mismatch rejects the
story when the phrase is alone in its clause („sitzt auf den Stuhl“); with another two-way phrase
there it most likely describes a noun („auf den Tisch neben der Tür“) and goes plain
(`trigger.wechselUnconfirmed`). The check looks only at its own half of an und/oder clause, so
„Er steht da und wartet auf den Bus“ is fine.

**Verb pairs** (`KasusVerbPairs`, 2026-10-04): a verb that fixes its preposition's case decides it,
not Wo/Wohin and not the preposition alone. „Er wartet auf den Bus“ is Akkusativ though nothing
moves; „Er hat Angst vor dem Hund“ is Dativ.
- **Source:** the 42 pairs of `verb_prepositions.json` (Verben mit Präpositionen). Each lists the
  verb's conjugated forms; a separable verb is listed as its two words („passt auf“, „denkt nach“),
  and „Angst haben“ as „angst“ plus a form of haben.
- **Scope:** a pair counts when all the words of one of its forms stand in the phrase's own part of
  its clause (`KasusValidator.verbPairScope`). The validator and the harvest share that function.
- **The rule:**
  - When the pair's case fits, the pair narrows the preposition. The phrase is then graded and
    explained by the pair („*warten auf* **always** takes the {akk:Akkusativ}: the verb decides
    here, not {wechsel:Wo?} or {wechsel:Wohin?}“).
  - An inferred two-way phrase decided by a pair may be blanked, since the verb rather than the
    tutor settled it.
  - A soft „um“ counts once its pair's verb is there („kümmert sich um den Hund“).
  - A clash narrows the preposition all the same, so `trigger.prepositionCase` fires and a
    generated story is rejected („Er denkt an dem Hund“, „Er hat Angst vor den Hund“).
- **Where a clash may just be a place,** the phrase is neither endorsed nor rejected
  (`KasusUnverifiable.verbPair`, `KasusLocatedTarget.verbPairUnsure`). That covers two cases:
  - the same preposition stands twice in that part („Wir warten auf dem Platz auf den Zug“: the
    pair takes „den Zug“);
  - the pair's preposition is also a plain place with that verb (`spatialToo`: warten auf,
    aufpassen auf, schreiben an). So „wartet auf dem Bus“ is no longer graded as a correct Dativ,
    but it doesn't reject either, because „wartet auf dem Bahnsteig“ reads the same.
- **Bundled stories:** they kept every golden number.

**Sentence checks** (`KasusSentenceCheck`, generated only, each rejects): ich + ist/sind/hat …, er
+ bin/sind/hast …, ich/er or a singular Nominativ phrase + an -en form that no modal, werden,
haben/sein, zu or bare-infinitive verb in its clause explains („Der Bruder lachen laut“); a word
no dictionary knows (`WiktionaryValidator.partsOfSpeech`), with fallbacks for compounds, prefixes,
weak-verb forms, present participles and noun suffixes, and names (a capitalised word that also
stands bare); an ein-article before a lowercase noun („einen stand“); an Akkusativ with no
preposition where sein/werden/bleiben/heißen is the verb (time and measure nouns and „wert“
exempt); a masculine object in the Nominativ after „es gibt“ or ich/du/er/wir +
haben/brauchen/kaufen; the same sentence three times. They are narrow on purpose; what they don't
see („wartet auf unserem Freund“, „die Sonne schien in den Himmel“, „dass der Raum vorbereitete“)
is what the Lab's „reads right / wrong“ tap is for.

**Gate:** the validator's generated policy ([Severity and policy](#the-validator)). A story is
rejected whole on any `morph.*`, `trigger.prepositionCase`, `trigger.wechselVerb` or `sentence.*`
error (the German itself is wrong), on `story.unitCaseCount` (under 3 gradable answers of the
unit's case, 2 of each for Alle Fälle) and on a length under half the level's range. Everything
else only turns a phrase plain. Two rejects go beyond the original spec on purpose: the sentence
checks (the Mac probe found broken German passing every form check) and the far-too-short story
(the same rule the Stories feature retries on). A length that's merely outside the range warns.

### Retry and fallback

A failed check retries once with a new seed (`KasusStoryPlan.retrySeed`), so the retry gets a new
plan. If both fail, the learner gets a bundled story of the same unit with the note „Die
KI-Geschichte hat die Prüfung nicht bestanden. Hier ist stattdessen eine fertige Geschichte.“
(„Die KI konnte gerade keine Geschichte schreiben …“ when every write threw), an English line and
one plain reason per try („a preposition with the wrong case („den Hund“)“, „no answers in the
Nominativ“). The unit screen offers its first story not yet played through (Markieren and
Endungen both done), else its first. A loadModel refusal ends as `.failed`: the sheet says „Der
Tutor ist nicht bereit“ and why, and offers the same bundled story.

### Storage (`GeneratedKasusStory`)

A SwiftData model, additive, every field defaulted, registered in `german_ai_flashcardsApp`'s
schema. Only a story that passed is saved (`KasusStoryStore.save`); the Lab never saves.

| Field | Holds |
|---|---|
| `id` | the story's id, `kg-<unit>-<level>-<8 hex>` („kg-dativ-a2-3f9a1c0b“): what its rounds key on |
| `date`, `unitRaw`, `level` | when, which unit, the `CEFRLevel` it was written at |
| `modelID` | the tutor that wrote it (an `MLXModel` raw value) |
| `title` | for lists that shouldn't decode the story |
| `planData` | the encoded `KasusStoryPlan` that produced it |
| `storyData` | the encoded `KasusStory`, source `generated`, in the bundled stories' format |
| `validatorSummary` | the check's line when it passed („PASS · 6/6 placed · …“) |
| `attempts`, `generationSeconds` | 1 or 2 (after the retry); the passing write's seconds |

A generated story plays through `KasusSession(generated:unit:)` exactly like a bundled one, is
validated again at play time under the generated policy, and its rounds file under its id.
`KasusStoryStore` lists a unit's stories (newest first), deletes one (its rounds stay, since they
hold their sentences and answers) and gives a merged bank, so Verlauf, the round detail and the
calendar name a generated story too. What differs: no comprehension question (`hasQuestion`), no
English (`hasEnglish`), no English title.

### On the unit screen

- **The row** (`KasusAIStorySection`, from `KasusStoryGenerator.availability`): „Neue Geschichte ·
  New story (KI)“ naming the tutor when one is ready; the usual download state (opening Settings ▸
  Model, never a tutor the device can't run) or a quiet too-small line otherwise; nothing while
  the toggle is off. While a tutor is loading, the row says so.
- **„Deine KI-Geschichten · Your AI stories“:** the unit's tutor-written stories under the row,
  newest first, with level, Markieren ✓/○, Endungen ✓/○, tutor and date; delete by swipe or context
  menu after a confirmation. Saved stories stay listed and deletable with the toggle off.
- **The sheet** (`KasusGenerationSheet`): the unit and level, the three steps with a live token
  count, „2. Versuch“ and why the first try failed. Abbrechen stops the tutor, and swipe-to-dismiss
  is off while it writes. Passed: title, level, words and the answers per case, „Lesen · Start
  reading“ or „Später · Later“ (it's already saved). Fallback and failed as above. The player
  opens only after the sheet has closed, since a full-screen cover can't come up over a sheet.
- **The player:** the header reads „KI-Geschichte · A2 · Dativ“; Lesen skips the question card
  and hides the English toggle on empty paragraphs; the Endungen Tipp uses `gap.triggerClue`
  („Find the verb. Ask wer?, wen?, wem? or wessen?“ for a form-only phrase), and a form-only phrase
  is never underlined.
- **Request:** the level is the unit's default (A1 Nominativ and Akkusativ, A2 Dativ, B1 Genitiv
  and Alle Fälle), not the learner's; no learner nouns are passed yet.

### The Kasus Lab (DEBUG) and its contracts

Settings ▸ Developer ▸ Kasus Lab (`KasusLabView`, numbers in `KasusLab`): the measurement behind
the decision to ship, or to fine-tune a tutor for this workload. No thresholds and no pass/fail
colors: the table is read, not judged.

- **Setup:** tutor (the tutors on disk, plus canned options since the simulator has none), unit,
  level, N runs, contract.
- **Contract A** („planned“): the product flow above, the app's planned phrases.
- **Contract B** („selfLabelled“): no planned phrases; the tutor writes the story and then labels
  every article + noun phrase itself in a block after it („FÄLLE:“, one „den Ball | Akk“ per
  line). `KasusSelfLabels` parses it tolerantly and scores each label against the case the form
  proves: right, wrong, unverifiable (the form leaves several cases), not in the story. A label
  in the dictionary form („der Schrank“ for „den Schrank“) falls back to matching by noun,
  counted apart. This measures directly whether a tutor can label cases.
- **Per model:** gate pass rate (first try / after the retry), planned phrases verbatim / altered /
  missing, gradable answers per case (mean), the top error and warning codes, contract B's label
  accuracy and % unverifiable, the „reads right / wrong“ taps, median seconds and tokens (MLX
  reports tokens in steps of 32), and how many runs had the memory saver on.
- **Per run:** the summary lines, the two taps, and a detail screen with the text, placements,
  harvest, issues, contract B's score, the raw output and the prompt.
- **Export:** a ShareLink per model, JSONL with one line per attempt (raw output, plan, report),
  named `kasus-lab_<model>.jsonl`, for `training/results/`. If a tutor is fine-tuned for this,
  the validator is the data filter.
- The Lab takes no ModelContext and never writes rounds, the profile or a `GeneratedKasusStory`.
  While it runs the back button is hidden and the run details are locked; leaving the screen any
  other way stops the batch. A loadModel refusal ends the batch with its reason.

`KasusLab`, `KasusLabView` and the fixtures are DEBUG only. Contract B's prompt branch and
`KasusSelfLabels` ship on purpose: they are a few pure functions inside the one check, a Release
plan is never contract B, and splitting a „FÄLLE:“ block off also keeps a stray one out of a
contract A story.

### Mac probe (2026-09-25)

Before any device run, the planner, prompt and check (the app's own Swift, compiled into a small
command-line tool, rebuilt and kept as `training/kasus_cli`, see `training/KASUS_STORY_DATA.md`, over the real `wiktionary_de.db`, `prepositions.json` and Goethe lists) were run
against the tutors with Python mlx_lm on an M1 Max (32 GB), sampling like the app (system + user
chat, temperature 0.75, the level's token budget). Mac numbers, a stand-in for the phone. Plans:
Nom A1, Akk A1, Dat A2 ×2, Gen B1, Alle B1, 2 runs each, each run being attempt 1 plus the retry;
contract B on 2 plans × 2 runs, one attempt each. Raw data, 81 attempts with plan, prompt, raw
output and full check plus the per-model summary: `training/results/kasus-lab-mac_2026-09-25.json`.

| As first probed (the check before the review fixes) | Hero E4B v4 | E2B v4 (memory saver) | E4B v3 (unshipped) |
|---|---|---|---|
| Gate pass, first try / after retry (12 runs) | 1 / 5 | 2 / 2 | 0 / 1 |
| Same, without the length rule | 8 / about 11 | 8 / about 10 | 4 / about 7 |
| Planned phrases verbatim with their trigger | 31% | 36% | 26% |
| Planned phrases verbatim anywhere | 43% | 47% | 31% |
| Gradable answers per attempt, Nom / Akk / Dat / Gen | 1.6 / 2.8 / 3.0 / 0.7 | 2.5 / 3.5 / 2.5 / 0.7 | 2.0 / 3.2 / 3.4 / 0.4 |
| Inferred (harvested) gradable answers per story | 6.0 | 7.2 | 7.4 |
| Median seconds / tokens per attempt (Mac) | 3.4 s / 158 | 1.9 s / 133 | 3.6 s / 167 |
| Contract B labels, matched by noun, right | 0 of 1 | 3 of 9 | 3 of 9 |

What it showed:

1. **Length, not bad German, rejected most stories.** At A1 and A2 the tutors stop short of the
   level's word range on their own (every hero A2 story ran 69–116 words against 120–180); at B1
   they land in range. Length caused 14 of the hero's 18 failed attempts, so it became a warning
   unless a story is under half the range.
2. **About a third of planned phrases survive verbatim.** The tutors swap the article for a
   possessive („der Bruder“ → „Mein Bruder“) or drop the preposition; Dativ-verb and receiver
   phrases almost never survive (about 1 in 12–16). Passing stories pass on 6–7 inferred answers,
   so the plan works mostly as a topic seed. The prompt now forbids possessives, and kinship nouns
   are definite only.
3. **Form checks don't prove sentences.** The infinitive hint leaked („Der Bruder lachen laut“),
   and valid forms were graded inside broken sentences („ihre Nachbarn waren ihren Gast“). Hence
   the conjugated hint, the third-person subject forms and the sentence checks.
4. **Some rejections were false** („beim Spielen“ read as a plural; a noun's own two-way phrase
   tied to a Wohin verb). Both are fixed.
5. **Contract B: the tutors can't label case in this format yet.** They write labels in the
   dictionary form, so the exact-match scorer found 64–85% „not in story“; matched by noun,
   accuracy was 0–33%, mostly Dativ labelled Nom. The hero once wrote a whole contract A story in
   French, which the check caught.

Caveats: 12 runs per model is small (treat ±2 runs as noise); the E2B was v4 from `training/`,
not the shipped E2B v1; Python mlx_lm can't quantize Gemma 4's rotating cache, so only the memory
saver's smaller prefill step was mirrored.

**Rescored with the review fixes.** The same 81 raw outputs through the new check (old plans with
the new subject forms): contract A attempts passing went from 8 of 69 to 32 of 69. Length stopped
rejecting (50 attempts before, 2 far-short ones now); the sentence checks rejected 11 attempts,
every one of them for real broken German (spot-checked: „Ich ist“, „einen stand“, „Der Bruder
lachen“, „Er kochen“, „waren ihren Gast“, „einen Schicklebesele“, a 16-times loop, the French
story), with no false alarms on those outputs; „beim Spielen“ and „auf den Tisch neben meiner Tür“
no longer reject. Stories that now pass can still hold German the checks don't see („wartet auf
unserem Freund“), and „die hohen Anteil“ still passes: Anteil is on no Goethe list, and the
harvest reads nouns only through lemmas it knows. The rescore isn't in `training/results/`; the
file there has the first-probe checks.

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

## Ending blocks in 3D: Endungs-Werkstatt and Bau das Wort

A determiner drawn as blocks on a plate: the **stem in ink** (d, ein, mein, dies), the **ending in
its case color** (`CasePalette`), and a thin **plate in the noun's gender color**
(`GenderPalette`). The case is what changes, so the case color sits where the change happens.
Forms with no ending (ein, kein, mein in m. Nom and n. Nom/Akk) show an empty slot, a translucent
block in the case color. The ink is die Figur's (`FigurScene.defaultTint`): charcoal on light,
cream on dark.

| Piece | Where |
|---|---|
| The split, d + em, eur + en, dies + e | `KasusForms.parts(family:stem:case:genus:)` → `KasusFormParts`; nil exactly where `form` is |
| Every ending a family uses, in table order | `KasusForms.endingOptions` |
| The stems a learner can pick | `KasusStemChoice.all` (der, ein, kein, the six possessives, dieser, jeder, welcher) |
| What is shown, and how it moves | `EndingBlocks/EndingBlocksState.swift`: `EndingBlocksState` (`.open` grey slot, `.built` with an optional `rejected` ending), `EndingBlocksTransition` (rise, snap, swap, bounceThenSnap, recolor, hold), `EndingBlocksPose.at(_:time:)`, `EndingBlocksFraming` |
| The canvas | `EndingBlocks/EndingBlocksScene.swift`: letters extruded at runtime (`MeshResource(extruding:)`, Futura Bold, cached per string), so nothing ships and any stem works |
| The 2D twin | `EndingBlocks/EndingBlocksFlat.swift`, shown for Stills Only (`LightweightGraphics`) and Reduce Motion; builds no RealityKit |
| The workshop | `Features/Grammar/Reference/EndungsWerkstattView.swift`, the hub's „Weitere Übungen“ |

Where it shows, one live canvas per screen each time:

- **Endungs-Werkstatt** (hub ▸ Weitere Übungen): pick a stem, a gender and a case; the old ending
  flies off and the new one drops onto the stem. Durchblättern steps Nom → Akk → Dat → Gen. The
  caption names the cells that share the word („Same word: Akk f“). The canvas is pinned above
  the list, framed for the stem's widest form so the camera holds still while flipping.
- **The endings table** (`CaseEndingsView`): tapping a cell builds it in a panel pinned above the
  list, with a der · ein · kein · mein · dieser picker. ein's plural cell shows kein's.
  `CaseEndingsTable(selectedCell:onSelectCell:)`; callers that pass neither are unchanged.
- **The Schnellrunde**: a strip above the sentence, dimmed, with the stem and a grey slot until the
  pick. Then the answer snaps in, after a wrong ending lands grey and bounces off.
- **Bau das Wort** (`CaseEndingsSession(unit:style: .bauDasWort)`, unit screen ▸ Schnellrunde
  section, and the Werkstatt): the Schnellrunde's sentences with the stem in the gap („Ich helfe
  mein___ Pferd“) and ending buttons (`-em`, `–` for none, `KasusEndingGap.label`). A tapped
  ending is turned back into the whole word (`EndingsQuestion.form(endingLabel:)`), so grading,
  slips, feedback, `roundItem` and the debug prefill are the Schnellrunde's unchanged.

Moves: every one settles within a second and ends on `EndingBlocksPose.settled`. A landing ending
starts grey and takes its case color on contact, and the stem squashes slightly. The same form in
another case („die“ Nom → Akk) hops in place and changes color; the same form in another gender
(„dem“ m. → n.) only changes the plate. The `TimelineView` runs only while something moves.

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
  unscaffolded first picks, only a case with at least 3 of them, once per case per round. Bau
  das Wort counts like the Schnellrunde (`countsTowardSkill`), but only the Schnellrunde marks a
  unit's dot done. Left
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
| `storyID` | the story's id, `quick-<unit>` for a Schnellrunde, `build-<unit>` for Bau das Wort, or `concept-<unit>-<exercise>` / `concept-<unit>-lesson` for Verstehen |
| `unitRaw` | a `KasusUnit` raw value |
| `stepRaw` | `find` · `fill` · `quick` · `build` (Bau das Wort), and Verstehen's `roles` · `wer` · `probe` · `lesson` (`KasusRoundStep`) |
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

A Swift Testing target in the `german-ai-flashcards` scheme; `test_sim` runs its 160 tests. Debug
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
| `KasusGenerationTests` | Phase 3: planner determinism, provable frames and counts, the prompt, locate / harvest / gate on the canned fixtures, contract B, the generator's retry, fallback and cancel, the store, the Lab export |
| `KasusGenerationScreenTests` | the generation sheet's lines, tutor names, the unit row's availability, the Lab runner |
| `KasusGenerationReviewTests` | the review fixes: third-person subject verbs, the sentence checks (what they catch and what they spare), two-way phrases, adjectives, copula, „ihr“, „beim Spielen“, the Genitiv plural, planner collocations and levels, the length rule, the retry's prepare, trimming, stopping, labels by noun |
| `KasusConceptTests` | Verstehen: every bundled item plays, the golden numbers, the Wer / Probe / Rollen invariants, negative fixtures, the role mapping and chips, seeded composing, grading per kind, clean explanations for every pick, the Kasus-Check walk, `countsTowardSkill`, recording a Probe and a Rollen round, a read lesson, an unknown step, the hub's row with Verstehen |
| `KasusLessonTests` | every unit's cards and Merkhilfen are clean markup, worked examples in Check order, the English bridge and the „to“ test |
| `KasusFormPartsTests` | the stem + ending split against every hand-written table, euer, the three empty ein-word cells, no plural for ein and jeder, ending options in table order; `EndingBlocksStateTests`: which move each change makes, every move settling, framing; `BauDasWortTests`: an ending pick grades like the whole word over 50 rounds, `build-<unit>` filing and skill counting |
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
fixtures, the table round trip, the Verstehen items (one line per unit and kind, ending
„Concepts ALL OK“) and the service checks (now with three Weiter-row checks for Verstehen).
Nothing is written. Expected (four lines
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
| `lesson:<topic>` | a Lektion in a sheet, by a unit's raw value or a topic's key (`lesson:dativ`, `lesson:reflexiv`); its Üben launches the topic's practice drill (Rollen, or Akkusativ oder Dativ?) |
| `topic:<key>` | a topic that isn't a case, in a sheet: `topic:reflexiv` (Reflexive Verben: rule, pronoun table, lesson row, drills, rounds) |
| `merkhilfen` | the Merkhilfen list, in a sheet |
| `werkstatt` | the Endungs-Werkstatt, in a sheet; `-kasus.debugWerkstatt dieser:dat:m` opens on that word, a fourth field `:flip` starts Durchblättern |
| `table` | the endings table, in a sheet; `-kasus.debugCell dat:m` builds that cell in 3D |
| `build:<unit>` | the unit's Bau das Wort, prefilled like `quick:<unit>` |
| (with `lesson:<unit>`) `-kasus.debugPlayScene 1` | every lesson scene starts live instead of as a still |
| (with `lesson:<unit>`) `-kasus.debugLessonPage <n>` | the lesson opens on card n (from 0) |
| (with `roles:` · `wer:` · `probe:`) `-kasus.debugItem <id>` | that item comes first in the round |
| `roles:<unit>` · `wer:<unit>` · `probe:<unit>` | a Verstehen round, prefilled from `-kasus.debugAnswers right\|mixed` (the first four steps) and `-kasus.debugQuickState right\|wrong\|done` (the next step, or the summary); Rollen plays in the stored mode (`-kasus.debugRolesMode schritt\|direkt` picks one for that launch), a walk included |
| `reflexcase:reflexiv` · `reflexperson:reflexiv` | a reflexive drill on the bundled gap-choice items (`docs/GRAMMAR_EXERCISES.md`), prefilled the same way; `-kasus.debugItem <id>` puts that item first |
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
- `-lightweightGraphicsMode on` shows the ending blocks' 2D twin (and every other 3D canvas's
  still) for that launch.
- `-kasus.debugQuickState right|wrong|slip|done`, with `quick:<unit>` or `build:<unit>`, answers the Schnellrunde's
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
Dativ story; the Dativ Lektion read, a Rollen round (Akkusativ) and a Probe round (Dativ) built by
the real engine; the Nominativ and Akkusativ Schnellrunden; an Einsetzen from before Endungen (the old
label); one Dativ Schnellrunde stored without answers (how older rounds look); and two
der/die/das and two preposition rounds. The
Kasus rounds are built by the service, so their sentences and explanations are real. Nothing
else moves (no streak, XP or coach), but the story rounds do mark its steps as played. It is
idempotent: the rows' dates are kept in UserDefaults and a second run prints `already seeded`;
`-kasus.debugSeedRounds remove` deletes exactly those rows. Launch with it and
`-kasus.debugOpen history`; the first launch of a fresh install can lose the sheet to the
launch presentations, so relaunch if it doesn't show.

**`-kasus.debugGenerate <unit>`** (Phase 3) runs the tutor-story pipeline on canned output, since
MLX doesn't run in the simulator: the generation sheet (Planen → Schreiben → Prüfen), the gate,
and either a saved story („Deine KI-Geschichten“) or the fallback note. It prints
`[kasus.debugGenerate]` lines: the outcome, then each attempt's summary, placements and errors.

- `-kasus.debugGenerateFixture good|altered|wrongArticle|tooFew` picks the canned text (default
  `good`; `wrongArticle` and `tooFew` end in the fallback note).
- `-kasus.debugGenerateDelay <seconds>` makes each canned step take that long (default 0.9), so
  a screenshot can catch the sheet mid-write with its token count.
- With `-kasus.debugOpen unit:<unit>` it opens that unit screen instead, its „Neue Geschichte“
  row ready on the canned writer (nothing is ever ready in the simulator otherwise).
- With `-kasus.debugOpen read|mark|mark-checked|fill|…` a story that passes goes on to the player
  at that screen, prefilled by `-kasus.debugAnswers` / `-kasus.debugHint` as usual:
  `-kasus.debugGenerate dativ -kasus.debugOpen mark-checked -kasus.debugAnswers mixed`.
- Every passing run saves a real `GeneratedKasusStory`; delete them from the unit screen.

**`-kasus.debugLab <runs>`** opens the Kasus Lab in a sheet and starts that many runs (`0` only
opens it). In the simulator they're canned, good · altered · wrongArticle · tooFew in turn.

## Removed

`Features/Grammar/GrammarCategoryDetailView.swift`, `GrammarStudyMode`,
`GrammarExerciseService.toVocabCards(category:)`, `DeckStore.grammarFlipSession` and the hub's
Coach's Picks, Akk/Dat category and Perfekt rows (the Perfekt decks live in Wortschatz ▸ More).
Phase 2 deleted the five akk/dat categories in `grammar_exercises.json` and
`GrammarExerciseService.category(for:rotation:)`: Today, Coach's Notes, the pyramid and class
entries all go through `GrammarRoute` now (the `praep-*` categories stay for the preposition hub).

Phase 3 deleted the old AI exercise path, whose answers were never checked (Phase 1 had already
unlinked its screen): `Features/Grammar/AIGrammarCreateView.swift`,
`MLXGenerationService.generateGrammarExercises` with its prompt builder, parse / salvage /
normalize helpers and `CodableGrammarExercise(Response)`, `GrammarExerciseSeed` /
`GrammarFocus.exerciseSeed`, `GrammarExerciseService.aiCategory` and `GrammarFocus.compactRule`
(only `aiCategory` read it). Perfekt, Modalverben, Konjunktiv II and the other non-case
structures keep the lesson sheet and conversation coaching but have no drill. `GrammarTopicService`
and `grammar_topics.json` stay as the source of story topics, though nothing reads them yet.

## Open

- ✅ Verstehen (2026-10-06): the lessons with English twins and Merkhilfen, Rollen (chips and
  Schritt für Schritt), Wer macht was? (structured input + Gleich oder anders?), Die Probe, the
  item bank with its audit and golden numbers, the unit section, the hub dot and hero rule 1b,
  Verlauf / round detail / calendar labels, the Sources section, debug arguments, tests.
- ⬜ Verstehen on a device: the role chips under a thumb, the Ja/Nein pace, the lesson's paging;
  seen in the simulator (Klar) only.
- ✅ Verstehen imagery, first two scenes (`tools/blender/kasus_szenen.py --ship`, on the verben.py
  rig): „Der Mann gibt dem Kind einen Ball“ (`kasus3d-geben`: the ball arcs from his hand to the
  child's, the subject tinted Akkusativ) and „Die Nachbarin hilft dem Kind mit der Hausaufgabe“
  (`kasus3d-helfen`: she bends over the desk and taps the sheet, tinted Dativ). Das Kind is a
  second, smaller Figur (`staemmig`, 1.1) with a teal (Dativ) torso; the doer stays the plain
  Figur. `kasus3d-manifest.json` merges into `PrepositionScene`'s lookup. They sit on the Dativ
  lesson's first and Dativ-verb cards, the Alle Fälle lesson's first two cards and the model
  sentence's Merkhilfe (`KasusLessonExample.scene`, `KasusLessonSceneView`): a still, and
  „Abspielen · Play“ swaps in the live scene (only on tap, so one RealityKit surface at most).
- ✅ Three more scenes (same tool and rig): the picture pair „Der Hund jagt die Katze“ /
  „Die Katze jagt den Hund“ (`kasus3d-jagen-hund`, `kasus3d-jagen-katze`: a dark dog and a pale
  cat, the chaser hopping after the other), on the Akkusativ lesson's „Warum überhaupt?“ card and
  as the two answers of three Wer macht was? items (`pictures` in `kasus_concepts.json`,
  `KasusPictureChoice`: tap the picture that fits; the still is zoomed 3.4× since the pair fills
  only the middle third of the 512-px render); and „Der Hund des Kindes spielt“ (`kasus3d-leine`:
  das Kind holds the dog on a lead, tinted Genitiv) on the Genitiv lesson's „Wessen?“ card.
- ✅ More Verstehen items (2026-10-07): 592 written offline by Claude Sonnet around the app's
  plans, gated, read and merged (124 → 716); a Genitiv round adds the attribute („Den Vater des
  Kindes fragt die Oma“). On-device generation measured and not built. See [Tutor-written
  Verstehen items](#tutor-written-verstehen-items-probe-2026-10-06) and
  `training/KASUS_CONCEPT_PROBE.md`.

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
- ✅ Phase 3: tutor-written stories in the bundled format ([Tutor-written
  stories](#tutor-written-stories-phase-3)): the seeded planner and `kasus_triggers.json`, the
  generator (tutors only, plain prose, one retry, the bundled fallback with its note), locate /
  harvest / gate with the sentence checks, `GeneratedKasusStory` and „Deine KI-Geschichten“, the
  unit row and generation sheet behind the developer toggle (off in Release), the Kasus Lab with
  contracts A and B and its JSONL export, `-kasus.debugGenerate` / `-kasus.debugLab` on canned
  output, the Mac probe and the review fixes it led to, and the old unchecked AI exercise path
  deleted. 62 new tests (160 in all).
- ⬜ Phase 3 on a device: no real tutor has run through the app yet (the simulator can't run MLX),
  so the Lab's numbers, the „reads right“ rate, the stop-during-read-in path, the unit screen's
  own sheet → player hand-off and the sheet's „Der Tutor ist nicht bereit“ state are unseen. Run
  the Lab on a phone per tutor, export to `training/results/kasus-lab_<model>.jsonl`, and keep the
  toggle off in Release until those runs have been read.
- ⬜ Phase 3 gaps: generated stories have no comprehension question or English; the level is the
  unit's default, not the learner's; no learner nouns are passed; prepositional objects are
  checked only for the 42 verb pairs (above), and only where no place reading is possible, so
  „wartet auf unserem Freund“ is now ungraded rather than caught; adjective endings aren't
  checked; nouns off the Goethe lists
  are never read, so „die hohen Anteil“ passes; Tag, Jahr, Abend and Samstag have no article in the
  Goethe lists, so „jeden Tag“ and „am Abend“ in a generated story stay ungraded.
- ⬜ Phase 3 debug side effects: every passing `-kasus.debugGenerate` run saves a real story (the
  simulator's Dativ unit lists several „Wo ist der Ball?“), and the download row inside the debug
  unit sheet switches tabs underneath the sheet.
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


## Guided explainers and exercise reference

`KasusExplainer` contains eight curated, unscored explainers, separate from lesson cards and
concept items. Grammar ▸ Warum dieser Fall? groups them into foundations, contrasts and deeper
explanations, with article tables and memory aids nested under Reference. Each unit's Verstehen
section links to the relevant subset. Each explainer has two translated, case-colored examples,
a reason for each, an optional self-explanation reveal, links back to unit practice, and an IDS
source link. Reading these does not write a round or change lesson completion.

`kasusReference()` adds the same question-mark menu to lessons, concept drills, quick rounds,
stories and explainers. Open table is a dismissible reference sheet; Keep table visible pins a
neutral compact table above the activity. Pinning lasts across questions and story steps, but
resets when the activity is left. It never selects the current answer or changes the story's
existing hint level. The table has a bounded scroll area so exercise controls retain space.

Grammar checks: IDS grammis [Kasus](https://grammis.ids-mannheim.de/sgt/2218),
[Objekt](https://grammis.ids-mannheim.de/sgt/2279),
[Wechselpräpositionen](https://grammis.ids-mannheim.de/progr@mm/6858), and
[Rollen und Situationen](https://grammis.ids-mannheim.de/progr@mm/6727).
The contrasts and self-explanation prompts are an editorial design choice, not a claim of
measured learning gains in this app. The generated concept bank and its review gate are unchanged.
