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
the lesson). `KasusRoundStep.meta` is one `KasusDrillMeta` row per step: titles, blurb, symbol,
minutes, round size, the count noun („Sätze“ / „Wörter“), how it files (`story`, `topicDrill`,
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
frames with English twins). `UnbuiltModule` stays for a registered kind without a module.

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

## Adding an exercise type

1. A case on `KasusRoundStep` with a new raw value (never reuse one) and a `KasusDrillMeta` row.
2. A case on `KasusDrillKind` with its `step`, and (if it needs content) the pack it reads.
3. A module file in `Features/Grammar/Drill/`, and its line in `KasusDrillKind+Shell.swift`
   (`makeView` and `debugRound`).
4. If the module needs configuration, a case on `DrillVariant` and its `standard(for:in:)` row.
5. `KasusDrillMetaTests` pins the raw value and the meta; `KasusDrillShellTests.modulesCompose`
   plays it through; a `-kasus.debugVerifyRecord` row says what it moves.
6. A What's New bullet.

Recording, Verlauf, the calendar, the round detail, the unit and topic screens, the hub dots, the
seeder and `-kasus.debugOpen <kind>:<topic>` need nothing.

## Adding a topic

1. A case on `GrammarTopic` with its key, titles, symbol, level, cases, focus, rule lines, lesson
   cards (Swift literals, `KasusLesson`'s shape), memory aid, practice drill, exercises, reference.
2. A `GrammarFocus` case if the coach should hear it, with its five switch rows; the pyramid files
   anything that isn't a case under Strukturen.
3. A `GrammarRoute` row (`.topic(topic)` for a focus the route should launch).
4. The topic screen (generalise `ReflexivTopicView` when the second one arrives) and its hub row
   (the hub lists every non-unit topic that `isAvailable`).
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
| `-kasus.debugVerifyRecord 1` | the twenty-five synthetic rounds through `recordRound` |
| `-kasus.debugRoute 1` | where every `GrammarFocus` goes, incl. `reflexivverben → Akkusativ oder Dativ? · Reflexive Verben` |

## Still open

- The batch pipeline for the gap-choice packs (part 3 of the plan), `reflexverb` (the double
  gap) on the same planner.
- A Dativ-Verben pack of bundled sentences (the frames are runtime for now), a Fehler pack beyond
  the Rollen items.
- Splitting `KasusService.swift`, `KasusStoryView.swift` (`KasusDebugOpen`) and
  `CaseEndingsView.swift` (the table) into their own files.
