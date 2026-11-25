# Spiele · Games

Three word games over the learner's own vocabulary, in a room of their own on Home
(`ActivityCategory.spiele`, the seventh tile). Card Matching and Der · Die · Das are **linked**
from the room, not moved — they keep their homes under Vocabulary and in the Grammatik hub.

| Game | German | What it is | Phase |
|---|---|---|---|
| Hangman | Galgenmännchen | Guess a word letter by letter, six misses | shipped |
| Word search | Wortsuche | Trace deck words out of a letter grid | generator done, UI pending |
| Fill-in crossword | Einsetz-Kreuzworträtsel | Fit words into an interlocking grid, no clues | generator done, UI pending |

## Why these are standalone activities, not grammar drills

The `KasusDrillModule` framework looks like a fit — Die Tabelle proves a board game can live on
it — but it demands a `GrammarCase` on every `KasusItemResult` and files every round as a
`KasusRoundStep` raw value forever. Vocabulary games have neither. They use the standalone rail
instead (`Activity.hangman`, like `.matching` / `.articleGame`): one `Activity` case per game,
one session payload, one arm in `ContentView.activityCover`.

**Three `Activity` cases, not one.** A single `.spiel(…)` would push a sum type into
`activityCover` and lose payload typing.

## The invariants

**Ä is not A, and ß is not SS.** `GameLetters` is the only place that decides what a letter is.
Guessing A on „Mädchen“ is a miss, and ß has its own key (the keyboard is 30 keys, not 26).
`"Straße".uppercased()` is `"STRASSE"` — it silently adds a letter — so `GameLetters.letters`
uppercases per character and preserves ß. Hangman keeps ß words; both grid games **exclude**
them rather than respell them, because a tray tile reading „Straße“ laid over seven cells is a
lie about German orthography. `EszettPolicy.expandToSS` is built and tested but unused.

**The round is composed at setup, never in the player.** `GameSetupView` resolves the source,
fits it, and (for the grid games) builds the puzzle *before* launching. So the full-screen cover
has no error state, and "not enough words" is answered on the one screen that can offer a top-up.

**A picture clue needs its deck.** `CardImageStore` keys its directories by `SavedDeck.id`, so
`imageFileName` alone can never be loaded. `GameWord` carries `imageDeckID` and **drops a file
name that arrives without one**, which keeps `HangmanClue` from offering a picture it could not
show. `SavedDeck.vocabCards` has no picture field at all, so a deck must be read through its
`SavedCard`s (`SavedDeck.gameWords`).

**The win check never consults the generator's answer.** In a clueless crossword, two
same-length slots that no crossing distinguishes are *both* legitimately fillable either way.
`FillInJudge.isSolved` compares crossings, not `puzzle.solution`. Comparing against the solution
is the bug that ships: it tells a learner who solved the puzzle that they are wrong.

**A grid may not contain a word twice, and an umlaut is never unique.** Filler letters can spell
an answer by accident, which would refuse a legitimate trace — so the filler is verified with
`WordSearchGenerator.scan` and re-rolled. And a single Ä on the board *is* the answer, so
camouflage promotes a few rare filler cells to match.

**Spiele have their own XP bucket.** `StudyActivity.games` / `StudyTimeBucket.games`, and
`StudyDay.gameWordsSolved` / `gameSeconds`. Not folded into `.cards`, because the Today screen
reports `cardsReviewed` as flashcards reviewed and a word game is not a flashcard review. Both
new fields are per-device counters in `StudyDayCodec` **and** are summed in
`SyncCanonicalizer` — miss the second and a canonicalization drops a day's games.

**`.partial` is the crossword's normal outcome.** Over 200 seeds on a ten-word kitchen deck:
164 built, 36 partial, 0 failed. The setup screen is designed around partial, not around
`.built`.

## Scoring, and what a game is allowed to claim

XP only, by default. Words the learner failed on go to
`LearnerMemoryService.noteVocabEncounters` — the rail for weak evidence, which claims no
production.

`SpieleWordOutcome.clean` means solved with no miss and no hint. It is the only evidence in the
room strong enough to move a card's review schedule, and only Galgenmännchen can set it — a word
you *found* in a grid was on screen the whole time. The opt-in credit toggle (Phase 5) is scoped
accordingly: pyramid credit for all three, SM-2 only from a clean Hangman win, and Wortsuche
never touches SM-2.

## File map

- `Models/Spiele/` — `GameWord` (+`GameWord+Sources`), `GameWordSource`/`GameWordPool`,
  `GameWordRequirements` + `GameRoundShape`, `SpielKind`, `GridPoint`, `HangmanMotif`,
  `HangmanSession`, `SpieleRoundResult`
- `Services/Spiele/` — `GameLetters`, `GameWordFitter`, `GameWordResolver`,
  `GermanLetterFrequency`, `HangmanState`, `HangmanClue`, `WordSearchGenerator`,
  `FillInGenerator`, `FillInJudge`, `SpieleScoringService`
- `Features/Spiele/Setup/` — `GameSetupView` (shared), `SourcePickerRow` (the extraction of a
  row that was already copy-pasted three times), `GameShortfallSheet`
- `Features/Spiele/Hangman/` — setup, play, keyboard, `HangmanFlatView`, summary
- `Features/Spiele/SpieleDebug.swift`
- Tests: `german-ai-flashcardsTests/Spiele/`

Everything under `Services/Spiele` and `Models/Spiele` is `nonisolated` and pure — the project
sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so that marking is load-bearing, not
decoration. (`SeededGenerator` and `String.withArticle` were made `nonisolated` for the same
reason; the duplicate `KasusSeededRandom` exists because they weren't.)

## Debug launch arguments

- `-spiele.debugOpen hangman|hangmanPlay|hangmanWin|hangmanLose` — the setup screen, or straight
  into a round parked in that state. The simulator can neither drag nor run a tutor, so every
  screen needs a way in that isn't a gesture.
- `-spiele.debugMotif turm|ballon|geruest` — which motif the debug round shows.

## The three motifs

Nobody hangs. Each motif is six parts that come or go as the misses mount, with die Figur beside
or atop them; the learner picks which in Hangman's setup.

- **Der Turm** — die Figur stands on a block tower; each miss takes the block under its feet.
  No ghost outlines for the lost blocks: the figure descends into exactly that space, and drawing
  both put it inside a cage.
- **Der Ballon** — the envelope deflates and sinks. It is placed above the **figure's head**, not
  merely above the basket; sized off the basket it deflates onto its own passenger.
- **Das Gerüst** — a symmetric frame of two posts and crossbeams. The first attempt (one post,
  one crossbeam, a short drop at the end) rebuilt a gallows exactly, which is the thing this
  motif exists to avoid. **Nothing may hang off the end.**

`HangmanFlatView` is the 2D twin required for Stills Only and Reduce Motion, and it ships first:
the 3D canvas (Phase 6, `tools/blender/galgen.py` → `galgen3d-<motif>.usdz` with `teil_1…teil_6`
and the clips `warten` / `jubel` / `kummer`, all of which already exist in `figur.py`) is an
upgrade over it, never a prerequisite.
