# Grammar exercises — the framework

How a grammar exercise type is defined, played, recorded and fed with content, and what it
takes to add one. `docs/KASUS.md` describes the case path itself (stories, validator, Verstehen,
ending blocks); this file is the layer the case path and the other topics share.

## The four words

| Word | What it is | Where |
|---|---|---|
| **Topic** | A teachable area with a lesson, exercises, a coach focus and a hub row: the five `KasusUnit`s of the case path, and the topics that aren't a case (Reflexive Verben). A topic's `key` is what `KasusRound.unitRaw` stores. | `Models/Grammar/GrammarTopic.swift` |
| **Mechanic** | How one question is answered: an option grid, chips in the sentence, a Ja/Nein walk, a word tapped in the sentence, a find-then-fix. The shell plays any of them. | `Features/Grammar/Drill/` |
| **Exercise type** (`KasusDrillKind`) | A mechanic over an item shape with its grading, explanation and meta. Stored as its `KasusRoundStep` raw value, which never changes. | `Models/Grammar/Kasus/KasusRoundStep.swift` |
| **Content pack** | Bundled JSON items for a (topic, kind), written offline, gated by Foundation-only code that `training/kasus_cli` compiles, asserted at load in DEBUG, pinned by golden numbers. | `Resources/*.json`, `Services/Grammar/Content/`, `Services/Grammar/Check/` |

## The registry

`KasusRoundStep` is every step a round can record as (the stories' `find` and `fill`, the drills,
the lesson). `KasusRoundStep.meta` is one `KasusDrillMeta` row per step: titles, blurb, symbol, the
task drawing (`art`), minutes, round size, the count noun („Sätze“ / „Wörter“), how it files (`story`, `topicDrill`,
`concept`, `lesson`), its coach policy (`never`, `production`, `productionUnlessGenderShown`,
`hintLadder`), where a unit screen offers it, the outcome labels that differ per step, the
pooled-answer floor for a topic (`minItemsPerFocus`), and the round id it files under in a topic
(`roundID(topicKey:)`: `quick-dativ`, `concept-dativ-roles`, `reflexcase-reflexiv`).

`KasusDrillKind` is the subset the shell plays (not `find`, `fill` or `lesson`). Its raw value is
its step's, so `-kasus.debugOpen <kind>:<topic>` parses through the step and nothing can drift.

Everything downstream reads the meta and never switches on a kind: recording
(`KasusService.countsTowardSkill`, `skillMoves`), progress (`KasusProgress.drillDone`), Verlauf,
the round detail, the calendar, the unit screens, the hub dots, the seeder. The only switch over
modules in the app is `KasusDrillKind+Shell.swift`.

### How an exercise is announced

**Art marks a task you can play. A tinted chip marks a place you can enter or read.**

A launcher row shows the step's `art` — a `GrammarTaskArt`, drawn by `GrammarTaskArtView` as the
*shape of the task*: a sentence with one word slot empty, a word whose tail is missing, a stem with
an ending snapping on, lines against a clock. `meta.symbol` stays for the dense, retrospective
surfaces (Verlauf, the calendar, a round's detail, the drill shell's empty state). Rooms, cases,
topics, the endings table and the rule sheets keep their chips, because they are places.

Three rules the drawings hold (`GrammarTaskArtTests`):

- **One case per task shape, not per kind.** Two kinds sharing a drawing is a claim that they ask
  the same thing — `pair` and `reflexCase` are both „a gap, and exactly two candidates“. The test
  pins which shares are intended, and that no two exercises offered in *one section of one topic*
  look alike.
- **Nothing lettered.** docs/PREPOSITION_3D.md's delivery table gives matching tiles nothing rather
  than leak the meaning being tested; the same holds here, so a drawing is bars, blocks, dashes and
  blank tags — never a form that is somebody's answer.
- **No colour of its own.** The row passes its tint (a unit's case colour, a topic's, a preposition
  group's), so neither the gender nor the case palette gains a meaning. A drawing works in one hue
  at three strengths; differentiation is by form.

The raw value is an asset slug, so a drawing can later be swapped for a baked Blender still without
touching a screen — the `BauhausIcon` hatch, resolved in `GrammarTaskArtView` alone. Both rows live
in `Features/Grammar/Shared/GrammarLauncherRow.swift` (`GrammarTaskRow`, `GrammarShelfRow`);
a screen never hand-rolls one.

## The shell and a module

`Activity.grammarDrill(GrammarDrillSession)` is the one activity for every drill. A session is a
kind in a topic with a typed `DrillVariant` (`endings(EndingsConfig)`, `concept(ConceptConfig)`,
`gap(GapConfig)`), an optional DEBUG prefill, and a personal best for timed rounds.

`GrammarDrillShell<Module>` owns every piece of state: the round (`KasusDrillRound`), the pick,
the feedback card, the summary, haptics, recording (once, never for a prefill), the reference pin
(the article table for a case, the pronoun table for the reflexive topic; a pinned table marks
that step's answers scaffolded, so they count for the streak and never for the coach), and the
DEBUG prefill (`-kasus.debugAnswers`, `-kasus.debugQuickState`, `-kasus.debugSeed`).

A module (`KasusDrillModule`) is a value with nine requirements:

| Requirement | Does |
|---|---|
| `kind` | which kind it plays |
| `compose(session, rng:)` | the round's items, seeded; nil when the topic can't offer the kind |
| `answer(pick, for:step:partial:)` | grades a tap: `.graded`, `.partial` (a multi-tap step keeps scratch state in `Partial`), `.ignored` |
| `debugPick(for:partial:want:)` | the pick the prefill and the seeder make for right / wrong / slip |
| `hero` · `panel` | the question above, the inputs below |
| `stage` · `toolbar` | optional: the 3D word or a timer above the hero; a trailing menu |
| `hint` | the line under the inputs until a pick |
| `missText` · `scoreLine` · `summaryNote` | optional summary wording |

Modules today: `EndingsModule` (Schnellrunde, Bau das Wort, and the variants on the same engine
by `EndingsConfig`: the Dativ-Verben frame family, a confusion pair's two forms on one gender,
the Blitzrunde's minute with deferred feedback and the clock as its stage), `RollenModule`
(direct roles, or the Kasus-Check walk as a multi-tap step), `WerModule`, `ProbeModule`,
`GapChoiceModule` (a bundled sentence with a gap: buttons, or two chips in the sentence),
`FehlerModule` (a mistake planted in a Rollen sentence by `FehlerQuestion`: tap the word, then
fix it; a fix after a missed find is practice), `BridgeModule` (`BridgeQuestion`: the English
pronoun, the German pronoun, then the article on one frame, derived from the Schnellrunde's
frames with English twins), `ArticleTableModule` (Die Tabelle: the article chart as a board,
below). `UnbuiltModule` stays for a registered kind without a module.

The unit screens read the registry: `GrammarTopic.exercises()` lists a unit's kinds (the concept
bank's, the Brücke once the Akkusativ is in play, the Schnellrunde and Bau das Wort, the
Dativ-Verben once the Dativ is in play, Finde den Fehler where two cases can be confused, the
Blitzrunde) and `KasusDrillMeta.placement` says which section shows each one. A kind the hub's
Verstehen dot never counted stays out of it when it arrives.

Verwechslungs-Paare (`KasusConfusion`) read every form pick in the round history: once one pair
of forms has six misses and twice the runner-up's, the hub and Coach's Notes show the pair with
its two-button drill on the gender the misses were on (`KasusDrillKind.pair`), which never moves
the coach.

## Topics

`GrammarTopic` answers for a topic what `KasusUnit` answers for a unit: titles, symbol, colour
(a topic that spans cases never wears a case colour), level label, cases in play, emphasis, the
coach focus, rule lines, lesson cards, memory aids, the lesson's practice drill, the exercises
its banks can fill, the reference it pins. A unit's topic forwards to the unit, so nothing stored
changed when topics arrived.

A topic that isn't a case files its rounds under its own key (`unitRaw: "reflexiv"`), which keeps
them out of every unit screen, the unit's dots and the all-time case bars in Verlauf (a *sich* /
*uns* pick can't demonstrate a case). It gets its own Verlauf filter, a hub row under Themen, a
screen (`ReflexivTopicView`), and one coach focus that pools every counting answer across its
cases (`KasusService.skillMoves`: `minItemsPerFocus` of them, six for a drill whose buttons are
few enough to guess). Weiter on the hub never suggests a topic; the case path stays the path.

## The hub's rooms

The hub shelves everything that isn't the case path by domain: one `GrammarArea`
(`Models/Grammar/GrammarArea.swift`) per room — Präpositionen (its own grown screen), Artikel &
Endungen, Verben and Englisch & Fälle (one generic `GrammarBereichView` rendering `area.rows`). The grouping is
display only: no stored key, no registry contact, and a room row's flame is any of its `foci`
shaky. Reference lives below the rooms under Nachschlagen (the endings table directly, then the
explainer library, which indexes the Merkhilfen, the Kasus-Check, the Endungs-Werkstatt and the
rule sheets — an index may list what lives elsewhere; that is order, not duplication).

Three contracts hold the shape as content grows (`GrammarAreaTests`):

- **In-place upgrade.** A structure is one `.struktur(focus)` row on its room's shelf. It renders
  as a quiet Lektion row (the 30-second `GrammarLessonSheet`) while `GrammarRoute(focus)`
  `.hasExercise` is false, and as a full topic row (dots, push) the day its `GrammarTopic` ships —
  same position, one predicate, never two maintained lists.
- **Every `GrammarTopic` ships with a `GrammarFocus`.** The flames, the shelf row and the upgrade
  all key on the focus.
- **A room of exercises has no focus at all.** Englisch & Fälle shelves `.drill` rows only, so its
  `foci` is empty and `levelLabel` names the span of the path it reads („A1–B1“). That is
  deliberate: every kind in it is `coachPolicy: .never`, so a flame there would be one nothing
  could put out, and a `GrammarFocus` nothing moves would show up in the conversation picker, the
  class-entry picker and the pyramid's „rest“ list as a skill that is never practised.
- **Overflow hatch.** When a room passes about eight rows, split along the focus mapping (Verben
  would shed a Zeiten & Formen area): one new `GrammarArea` case, never a new taxonomy. The hub
  and the room view iterate `allCases` / `rows` and are not edited for it.

Adding to a room is one `BereichRow` in `GrammarArea.rows` (a `.struktur`, a pushed screen, a rule
sheet, or a `.drill(kind)` that builds its row from `KasusDrillMeta` and pushes the exercise's own
setup screen); adding a room is one enum case. A room's raw value is one lowercase word, because
`-kasus.debugOpen <area>` reads it with `GrammarArea(rawValue:)`.

### Die Tabelle

The classroom article chart as a board: the grid is drawn with its cells open and the forms are
tiles underneath, dragged into place (`ArticleTableBoardView`). Two charts and three shapes
(`TableConfig`, remembered under `kasus.tabelle.*`, picked on `TabelleSetupView` off the Artikel
room's shelf). No content: every cell is `GrammarCase.article(_:)` / `einEnding(_:)`, the same
table `CaseEndingsTable` renders, so the game and the reference cannot disagree.

- **A round is always the whole table** — sixteen cells, whether that is one board (Ganze Tabelle),
  a case's row at a time (four boards) or four scattered gaps (a Latin square over the four boards,
  so no board is one case or one column). A score means the same thing across the shapes, and every
  round spans all four cases, which is why it files under `tabelle-alleFaelle` and needs nothing of
  Verlauf or the per-case strip.
- **The module grades the cell that was dropped on** (`pick.cell`), not the step the shell handed
  it: the learner picks the order. The items are the blanks in a fixed order so the prefill, the
  seeder and the progress strip have sixteen steps to walk, the board view offers only open cells,
  and `answer` ignores a drop on anything else. Anything reading a step back reads the pick
  (`missText`), never `item.blank`.
- **The tray is the blanks**: one stack per distinct form with a count, and an answered cell
  consumes one copy of *its own* form, right or wrong — so the counts can never drift from the
  cells left, and running out of „der“ is itself a signal.
- **A miss leaves the right form in its cell**, with the wrong pick struck through under it. The
  learner is building a reference table; a wrong form left sitting in it would teach the wrong
  thing. The misses are read back in the summary, because feedback is deferred like the
  Blitzrunde's — a card between two drops would break the board into sixteen screens.
- **Never evidence** (`coachPolicy: .never`): the tiles are a closed set, so elimination does part
  of the work. It counts for the streak. `allowsReference` is off for the obvious reason — the
  pinned table is the answer key.
- **A drag is not the only path.** The same gesture taps: tap a tile to arm it, tap a cell to place
  it. VoiceOver, a trackpad and a thumb on a four-column grid all need that, and both paths call
  one `place`.
- **The lifted tile is an overlay, never a child.** `position` takes every point its parent
  offers, so a positioned child made the tray greedy and pushed the chart off the screen the
  moment a drag started. An overlay is sized to the tray and still draws outside it.
  `-kasus.debugTabelleLift der` parks a tile in the air over the first open cell, because the
  simulator cannot drag and a screenshot of the resting state proves nothing about this.
- **One subtree, one coordinate space.** The grid and the tray are the module's `panel` together
  are the module's hero and panel, so the drag between them works in `.global` coordinates and
  shares one `ArticleTableDrag` held by the module (built once per round, unlike the views).

### Englisch & Fälle

The four anchor questions (**Wer oder was? · Wen oder was? · Wem? · Wessen?**) asked on the English
sentence of a Verstehen item, with „Keine Frage“ as the fifth answer where a preposition decided the
case. Two exercises today, one module (`FrageModule`), one pool
(`Services/Grammar/Kasus/EnglishAnchors.swift`) and no content of its own: both read
`kasus_concepts.json`, whose items already carry an English twin and, per target, that phrase's span
in the English line.

- **The question is read off the role,** never authored: `KasusConceptFacts.roles` →
  `KasusQuestion(role:)`. The pool is read off the target's **reason**, because
  `KasusRole.empfaenger` merges a true receiver with a Dativ verb's partner, and that merge is the
  trap („The father followed the woman“ → *der Frau*).
- **Welche Frage?** draws the clean spans and always includes one „Keine Frage“ span where the unit
  has one: an exercise that never shows a preposition-governed phrase teaches that every phrase
  answers one of the four, when Kasus-Check step one says the opposite.
- **Die englische Falle** draws the Dativ-verb spans and mixes in the clean spans an English ear
  confuses them with, so the answer can never be „always Wem?“. It has no pool before the Dativ.
- **Nominativ is never offered** (one case in play is a one-button grid), and a round files per
  unit (`frage-alleFaelle`), so Verlauf, the per-case strip and the done-marks need nothing.
- **The help preset is the ramp** (`KasusHelp`, `kasus.hilfe`): Leicht pins every item to „Beide“,
  Normal walks Englisch → Beide → Deutsch across the round, Frei pins „Deutsch“ and asks one phrase
  per sentence. The same five options at every setting, so a first-try share stays comparable; what
  changes is the crutches. Seeded from `germanLevel` and never written back — nothing is stored
  until the dial is touched (`EnglischSetupView`).

## Content packs

A pack is one JSON file per item format, every topic's items in it. The pattern, from the
Verstehen items (`kasus_concepts.json`, 716 items) and the gap-choice items
(`gap_choice_items.json`):

1. **Format** — a Foundation `Codable` item with the facts the gate needs, never a decision a
   model made (`Models/Grammar/Kasus/GapChoiceItem.swift`: the sentence with `{1}` placeholders,
   each gap's answer and options and case, the subject, the verb and what it takes, the second
   object, a verbatim tail).
2. **Tables** — hand-written, the gate's source of truth (`ReflexivForms.swift`: pronouns by
   person and case, subjects, verbs with present forms and valency, each verb's natural objects).
3. **Gate** — `Services/Grammar/Check/GapChoiceCheck.swift`: stable `gap.*` codes per item, and
   `gap.composition.*` over a whole pack (both cases present, every verb and person in a
   batch-sized pack, no duplicates). A rejecting code refuses the item; `unknownWord` and
   `objectUnverified` are recorded. Explanations are derived at play time
   (`ReflexivExplanation`), never stored.
4. **Bank + fixtures** — `GapChoiceBank` loads once and, in DEBUG, asserts every item and the
   composition; `GapChoiceFixtures` pins golden numbers per topic/focus and holds one planted
   error per rejecting code. `-kasus.debugVerify 1` ends „Gaps ALL OK“; `GapChoiceTests` runs the
   same block.
5. **CLI** — `training/kasus_cli/build.sh`, then `build/kasus-cli audit-gaps [file] [--golden]`
   gates a file in the pack's format and prints the golden rows to paste. `selftest` loads the
   bank.

A batch, from `training/`:

```bash
python3 scripts/gap_review.py data/gap-choice/reflexiv-2026-10 --focus case:120 person:100 --seed 7
python3 scripts/gap_review.py data/gap-choice/reflexiv-2026-10 --merge     # after the read
```

`GapChoicePlanner` (`Services/Grammar/Content/`) writes the German and the English from the
tables alone (verb × subject × object or tail, the pronoun from person and case, the English from
the verb's pattern with `{S} {V} {B} {R} {P} {O}` tokens), with the pack's composition built in
(every verb, every person, both cases, no sentence a drill already asks). `kasus-cli gap-plans`
emits it as JSON lines, `gap-check` gates it, `gap-export` keeps the passing items in bundle
format, `audit-gaps` audits the export; the script writes `review.csv` (fill in `reads_right` and
`note`), `review.md`, `summary.json` and a `README.md` run log. A ✗ in the read names a table row
to fix (`ReflexivForms.swift`), and the pack regenerates from the same seed. `--merge` appends the
export to `Resources/gap_choice_items.json` and prints the golden rows for
`GapChoiceFixtures.golden`. No model writes grammar content for the app; the tutors on the device
never do.

## Checking the content

Three axes decide whether shipped German is good, and none of them subsumes another. Running one
and calling it done is how `past_tense_verbs.json` reached 70% defective while LanguageTool
rated it 4%: `"Gestern habe ich gekündigt."` filed under *anbieten* is flawless German and
completely wrong.

| axis | what it answers | tool |
|---|---|---|
| self-consistency | does the item agree with its own metadata? | `scripts/check_content.py` |
| grammaticality | is the German well formed? | `--languagetool`, and `KasusValidator` in `kasus-cli` |
| naturalness | would a German actually say this? | a human, on a sample — no tool catches it |

```bash
python3 scripts/check_content.py              # fail on anything new since the baseline
python3 scripts/check_content.py --report     # the per-corpus table, exit 0
python3 scripts/check_content.py --show gender-conflict
training/.venv/bin/python scripts/check_content.py --languagetool
```

It lints every bundled corpus: answers inside their option rows, blanks matching gap counts,
annotated phrases occurring verbatim, and every gender claim in the app cross-checked against
`wiktionary_de.db`. `scripts/content_baseline.json` records what is accepted today, so the
script fails only on *new* findings — a linter that is red from day one gets ignored. Re-baseline
with `--write-baseline` after a deliberate change, and say so in the commit.

There is no CI, so this is a local command. Run it before merging a content batch.

### The Schnellrunde's own sentences

Five kinds (`quick`, `build`, `blitz`, `pair`, `dativVerbs`) read no JSON at all — they assemble
German at runtime from `EndingsFrame.all` × `EndingsNoun.all` × `EndingsDeterminer.form`. That
space is finite, so `kasus-cli audit-endings` proves it exhaustively rather than sampling: all
2,736 reachable cells, each one checked for the article carrying its case for that gender, the
stem + ending round trip Bau das Wort builds from, the dative-plural `-n`, and the noun's gender
against the dictionary. It also asserts on the data the two invariants that otherwise live only
inside `EndingsQuestion.round`: `ein` never reaches a plural cell, `kein` never a Genitiv one.

```bash
training/kasus_cli/build.sh
training/kasus_cli/build/kasus-cli audit-endings            # exit 1 on any failing cell
training/kasus_cli/build/kasus-cli audit-endings --dump     # every cell as JSON, for LanguageTool
training/kasus_cli/build/kasus-cli audit-endings --matrix   # the frame × noun grid a human reads
```

What the sweep cannot prove is whether a frame and a noun belong together — `Wir gratulieren dem
Pferd.` is impeccable and silly. The article and number dimensions being machine-proven is what
makes that affordable: `--matrix` collapses the question to 25 × 16 frame × noun pairs, one page
of checkboxes, instead of 2,736 sentences.

Running the dump through LanguageTool flags **16 of 2,736 (0.6%), and all sixteen are false
alarms**: the rule `DEN_DEM` reads `Ich antworte den Männern.` as an accusative singular and asks
for „dem“. It is a correct Dativ plural — `antworten` takes the Dativ and the plural article is
`den`. Do not "fix" those sentences, and keep `DEN_DEM` out of any ignore list you add for other
corpora: it catches real errors in the singular.

## Adding an exercise type

1. A case on `KasusRoundStep` with a new raw value (never reuse one) and a `KasusDrillMeta` row,
   including its `art`: an existing `GrammarTaskArt` if it asks the same thing as a kind that has
   one, a new case if it doesn't. The field has no default, so the compiler asks.
2. A case on `KasusDrillKind` with its `step`, and (if it needs content) the pack it reads.
3. A module file in `Features/Grammar/Drill/`, and its line in `KasusDrillKind+Shell.swift`
   (`makeView` and `debugRound`).
4. If the module needs configuration, a case on `DrillVariant` and its `standard(for:in:)` row.
5. `KasusDrillMetaTests` pins the raw value and the meta; `GrammarTaskArtTests` pins the drawing
   and re-checks that no section shows one twice; `KasusDrillShellTests.modulesCompose` plays it
   through; a `-kasus.debugVerifyRecord` row says what it moves.
6. A What's New bullet.

Recording, Verlauf, the calendar, the round detail, the unit and topic screens, the hub dots, the
seeder and `-kasus.debugOpen <kind>:<topic>` need nothing.

## Adding a topic

1. A case on `GrammarTopic` with its key, titles, symbol, level, cases, focus, rule lines, lesson
   cards (Swift literals, `KasusLesson`'s shape), memory aid, practice drill, exercises, reference.
2. A `GrammarFocus` case if the coach should hear it, with its five switch rows; the pyramid files
   anything that isn't a case under Strukturen.
3. A `GrammarRoute` row (`.topic(topic)` for a focus the route should launch).
4. The topic screen (generalise `ReflexivTopicView` when the second one arrives). No hub edit:
   the topic's `.struktur` row in its room (`GrammarArea.rows`) upgrades from Lektion to topic row
   by itself once the focus routes to `.topic` — add the row there if the structure was never
   shelved before.
5. `GrammarTopicTests` for clean markup and the lesson's shape; `KasusRecordingTests` for what
   its rounds move; the Verlauf filter.

## Debug launch arguments

| Argument | Opens / prints |
|---|---|
| `-kasus.debugOpen <kind>:<topic>` | any drill on the shell: `quick:dativ`, `build:dativ`, `roles:dativ`, `wer:akkusativ`, `probe:genitiv`, `dativverben:dativ`, `blitz:akkusativ`, `fehler:dativ`, `bridge:akkusativ`, `reflexcase:reflexiv`, `reflexperson:reflexiv` |
| `-kasus.debugSeedRounds 1 -kasus.debugConfusion 1` | seeded rounds with dem ↔ den missed, so the Verwechslungs-Paar card shows on `hub` |
| `-kasus.debugOpen lesson:<topic>` | the lesson sheet: `lesson:dativ`, `lesson:reflexiv` |
| `-kasus.debugAnswers right\|mixed` · `-kasus.debugQuickState right\|wrong\|slip\|done` · `-kasus.debugSeed <n>` · `-kasus.debugItem <id>` · `-kasus.debugRolesMode schritt\|direkt` | the prefill (never recorded) |
| `-kasus.debugVerify 1` | the stories, the Verstehen items and the gap-choice items with their golden numbers and planted errors |
| `-kasus.debugVerifyRecord 1` | the synthetic rounds through `recordRound`, one per policy |
| `-kasus.debugRoute 1` | where every `GrammarFocus` goes, incl. `reflexivverben → Akkusativ oder Dativ? · Reflexive Verben` |
| `-kasus.debugOpen verben` · `artikel` · `englisch` | a hub room (`GrammarBereichView`) in a sheet |
| `-kasus.debugOpen frage:<unit>` · `englischefalle:<unit>` | Englisch & Fälle, straight into a round (`alleFaelle`, `dativ`, `genitiv`, `akkusativ`) |
| `-kasus.debugOpen tabelle:alleFaelle` | Die Tabelle on the chart and shape last picked (`kasus.tabelle.chart`, `kasus.tabelle.shape`) |
| `-kasus.debugTabelleLift <form>` | with it, a tile („der“) parked in the air over the first open cell: the drag's look, on a simulator that cannot drag |

## Still open

- The batch pipeline for the gap-choice packs (part 3 of the plan), `reflexverb` (the double
  gap) on the same planner.
- A Dativ-Verben pack of bundled sentences (the frames are runtime for now), a Fehler pack beyond
  the Rollen items.
- Splitting `KasusService.swift`, `KasusStoryView.swift` (`KasusDebugOpen`) and
  `CaseEndingsView.swift` (the table) into their own files.
