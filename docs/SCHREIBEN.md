# Schreiben · Writing

A room for the learner's own writing, with two modes that share one editor, one store, one sync
codec and one tutor check:

- **Tagebuch · Journal.** Dated pages, kept over time, in German, English or both. The learner may
  vent about the language itself; that is the point. The check is optional and leaves English
  sentences alone. On an explicit button, structured notes reach the coach (below).
- **Aufsatz · Essay.** A prompt (from the bundled bank, picked for a shaky structure, written by
  the tutor on a topic, or the learner's own), a target length, a check sentence by sentence, and an
  app-computed score with one short tutor comment.

Input is the keyboard on every platform, and on the iPad the Apple Pencil on a ruled page whose ink
is kept as the entry's handwritten form; "Read my handwriting" turns it into text the learner
confirms before anything is checked.

Decisions made with Kyle on 2026-11-08: one room, two modes; journal in any language with an
opt-in per-entry hand-off; corrections plus an app-computed score, never a model-assigned grade;
ink page plus Vision reading with confirmation.

## Invariants

1. **The check never guesses.** Labelled lines, one per sentence; a reply that fails a gate (an
   echo, a rewrite, a stray noun, a missing line) is "prüfen", never "falsch". The tutor judges
   sentences; it never grades. Apple Intelligence is not used here (100 % false corrections on
   German, docs/WORKSHEETS.md); `GermanWriting.correct` stays the Schreibhilfe's.
2. **The coach learns only what the learner hands over.** `JournalCoachExport` runs on the entry's
   button and writes through `noteWrittenCorrections` (one-word fixes → cloze-ready slips),
   `noteVocabEncounters` (lookups, source `journal`) and `noteSelfReports` (the learner's own words
   about what is hard). It never writes `LearnerProfile.grammar` (the pyramid reads that as earned
   fill) and never bumps `sessionCount`. `sharedWithCoachAt` is the high-water mark: a second tap
   finds nothing new.
3. **Self-reports are stated, not inferred.** The tutor's extraction prompt may list only what the
   learner says about themselves; a line that copies a whole sentence of the entry is dropped; the
   learner edits or unticks every note before it goes; with no tutor they type it.
4. **Text is the entry; ink is a file beside it.** `JournalInkStore` keeps one `PKDrawing` per page
   under `Application Support/Journal/<entry id>/p0.drawing`, a synced root of its own; the row holds
   the page height and stroke count so lists never open a file. Unchanged bytes are not rewritten,
   an erased page deletes its file.
5. **One heavy resident.** Handwriting is read in 1024-point bands at 2× before the tutor is
   loaded; the check asks in batches of six sentences, at most 40 a run, with `maxTokens` capped per
   call and every call under a 90 s timeout (`generateText` has no watchdog of its own).
6. **The prompt is frozen on the entry.** Bank edits never move under a written essay. The level is
   copied from the declared level at creation and never written back.
7. **Autocorrect is off by default** in the editor: an English-locale autocorrect rewriting the
   learner's German first would hide exactly what the check should see. A toggle in the keyboard
   strip turns it on.

## Files

| File | What |
|---|---|
| `Models/JournalEntry.swift` | `JournalEntry` (@Model), `JournalKind`, `JournalPromptSource`; `WritingCheck`, `WritingSentenceCheck`, `WritingScore`, `JournalLookup` as Codable blobs. |
| `Services/Schreiben/JournalEntryStore.swift` | Today's page, new entry / essay, delete with its ink, `saveInk`, the day credit. |
| `Services/Schreiben/JournalInkStore.swift` | The ink files; root `Journal`. |
| `Services/Schreiben/JournalInkReader.swift` | Vision over the page in bands → `JournalInkLine`s; `transcript(from:)`. |
| `Services/Schreiben/WritingSentences.swift` | Sentence splitter, word count, language guess. |
| `Services/Schreiben/WritingTutorCheck.swift` | Prompts, parsers and gates: the check, the comment, the self-report extraction, the prompt generation. |
| `Services/Schreiben/WritingDiff.swift` | Word diff (`same`/`removed`/`inserted`), the rewrite ratio, `singleSwap`. |
| `Services/Schreiben/WritingCheckRunner.swift` | Runs one check; `WritingTutor` seam (`WritingMLXTutor`, DEBUG `WritingCannedTutor`); `WritingTutorPick` (the downloaded German tutor the room asks, Apple Intelligence never offered). |
| `Services/Schreiben/WritingPromptBank.swift` | `writing_prompts.json`, its gate and golden counts, `WritingPromptGate`, `CEFRLevel.essayWordRange`. |
| `Services/Schreiben/JournalCoachExport.swift` | The hand-off plan and send. |
| `Services/Schreiben/JournalDeckStore.swift` | The room's one deck of looked-up words (fixed id). |
| `Services/Sync/Codecs/JournalCodecs.swift` | `JournalEntryCodec`. |
| `Features/Schreiben/` | `SchreibenTile`, `SchreibenHubView`, `JournalTimelineView`, `JournalEntryView` (+ `JournalInkFullScreen`, `JournalPadSettings`), `JournalTextEditor`, `JournalCheckView`, `JournalHandwritingSheet`, `JournalInkPreview`, `JournalPromptPickerView`, `JournalCoachShareSheet`, `JournalLookupSheet`, `JournalTodayWriteView`, `SchreibenDebug`. |
| `Resources/writing_prompts.json` | The bank: 64 prompts, A1–B2, Tagebuch and Aufsatz. |
| `german-ai-flashcardsTests/SchreibenTests.swift` | Codec, splitter, score, parser gates, bank, self-reports, hand-off plan. |

Entry points: the fifth wide tile on Home ▸ All Activities; `MacDestination.schreiben` in the Mac
sidebar; the Today plan's "Schreib ein paar Zeilen" row.

## The entry

`JournalEntry`: `day` (local midnight, travels as `yyyy-MM-dd`), `kindRaw`, `title`, `text`,
`levelRaw`; the frozen prompt (`promptID/DE/EN`, `promptSourceRaw`, `promptFocusRaw`, `targetMin/Max`);
the ink's `inkHeight` (0 = never inked; else page height in points on a 768-wide page, +512 per
"Mehr Platz"), `inkStrokeCount`, `inkPaperRaw`, `transcriptConfirmedAt`; the check (`checkData`,
`checkedAt`, `checkedModelID`, `checkedTextHash`); `sharedWithCoachAt`, `lookupsData`, `creditedWords`.
Every property is defaulted (additive migration).

The editor edits a local draft and writes it a second after the last keystroke, so autosave does
not rewrite SQLite (and the sync history) per character. `checkedTextHash` is a fingerprint of the
text a check was made on: a mismatch shows "edited since" instead of claiming the new text passed.
Applying a fix replaces the sentence and refreshes the hash, so the rest of the check stays valid.

### Sync

`JournalEntryCodec`: `updatedAt`, `sharedWithCoachAt`, `creditedWords` take the larger value;
`lookups` merge word by word (`.set(idField: "german", lowercasedID: true, item: .lwwBy("at"))`); the
check's four fields travel as one group, so a check is never credited to the other device's tutor;
the rest is last-writer-wins per field, so two devices editing one entry at once keep the later
save whole. Ink syncs as files under the `Journal` root with no model field naming it.

### Day credit

Leaving an entry (or the app going to the background) credits the words gained since
`creditedWords` to `StudyDay.wordsWritten` when the delta is ten or more; a minute of typing or
drawing every minute goes to `writingSeconds`. XP: 1 per ten words, plus the minute. Both fields are
counters in `StudyDayCodec`, folded by the canonicalizer, and a "Schreiben" slice in the calendar's
day detail.

## The check

`WritingCheckRunner.run`: `prepare` the tutor (refuse while the queue or a chat is using it, then
`loadModel`), split the text, in a Tagebuch entry skip sentences `WritingSentences.guessLanguage`
calls English, batch the rest in sixes, ask, parse, then one comment call, then the score.

System prompt: a meticulous German teacher, the learner's level, the prompt's focus when there is
one, `LearnerMemoryService.correctionHint` as context, strict but never inventing a mistake, keep the
learner's words, never correct punctuation alone. User prompt: one line per sentence,
`number: richtig | falsch | unsicher ; full corrected sentence (or -) ; reason ≤ 12 English words ; category`,
the category one of the fourteen `GrammarFocus` keys plus `wortstellung`, `konjugation`,
`rechtschreibung`, `wortwahl`, `-`. `normalizeCategory` folds umlauts and common English and German
synonyms onto those keys.

Gates, in order (`WritingTutorCheck.parse`, all unit-tested):

1. a missing or garbled line → unsure ("The tutor didn't answer this one");
2. falsch with no correction → unsure;
3. a correction that echoes the original (`ConversationPrompts.echoNormalized`: punctuation, case
   and quotes folded, umlauts kept) → ok;
4. a correction that changes more than half the words or changes the length by more than
   0.6…1.6× → unsure, "the tutor rewrote this sentence";
5. a correction that brings in a noun the sentence and the prompt never mention
   (`WorksheetTutorCheck.strayNouns`) → unsure;
6. richtig with a correction → ok, correction dropped.

Outcomes: `ok`, `fix`, `unsure` (shown as "prüfen", never wrong), `skipped` (not German).

The comment: one English sentence, ≤ 25 words, no grade or number; `parseComment` rejects a line
with a digit followed by `/`, `%`, `points`, `Punkte`, the words grade, Note, score, or a line
shorter than 12 or longer than 200 characters, and the app writes its own line from the counts
instead (`commentIsFallback`).

### The score (essays)

`WritingScore`: `checked = ok + fix`; `cleanRatio = ok / checked`; `lengthScore` = 1 inside
`[targetMin, targetMax]`, falling off linearly outside, 1 with no target;
`points = round(70 · cleanRatio + 30 · lengthScore)`. Fewer than three judged sentences → counts
only, no points. Categories are counted for display and routing (a chip opens the 30-second
lesson); none of it touches `LearnerProfile.grammar`. A Tagebuch entry shows counts only.

## Handwriting

The Pencil page is `PencilPad` on ruled paper (28 pt), 768 points wide, `inkHeight` tall, in the
entry's paper style; the gear adds half a page ("Mehr Platz", to 8192 points) and holds the
dictionary-smoothing toggle. Full screen goes through the shared hand-off
(`PencilHandOff`, docs/SCHREIBBLATT.md), so two canvases never hold one page's ink. The ink is read
in `init`; the `onSave` updates the `@State` ink so a rebuilt canvas reads the newest; "Clear the
handwriting" rebuilds the pad with no ink so the cleared page cannot save itself back.

`JournalInkReader.read`: marker strokes dropped; the page rendered in 1024-point bands (96 of
overlap) at 2× via `WorksheetInkReader.inkOnWhite`; one `VNRecognizeTextRequest` per band,
`.accurate`, `de-DE` + `en-US`, language correction **off by default** (on, Vision smooths a misspelt
word into a dictionary word, which hides exactly what the check should see; the toggle is for a hand
it keeps misreading). Observations → page points; the same line seen in two bands keeps the surer
reading; pieces on one rule (within half a pitch) become one line, left to right; each line gets
its crop, up to three alternatives when it was one piece, and a confidence (sure at 0.6).
`transcript(from:)` joins lines with spaces and starts a paragraph where a rule was skipped.

`JournalHandwritingSheet`: rows in order, unsure first and tinted, each with its crop, an editable
field, "Looks right" and alternative chips; "Text übernehmen" waits until every unsure line was
looked at; typed text already in the entry asks replace-or-append. The reading is never drawn onto
the page.

iPhone and Mac render the ink read-only (`JournalInkPreview`, `PKDrawing` exists on macOS) above
the keyboard editor and can still read it into text.

## Prompts

`writing_prompts.json`: `{id, de, en, level A1–B2, kind tagebuch|aufsatz, topics[], focus?,
targetWords{min,max}?, scaffold[≤4]?}`. The gate (`WritingPromptBank.validate`, asserted in DEBUG at
first load, run by `-schreiben.debugVerify 1`, mirrored by `scripts/check_content.py`
`check_writing_prompts`): unique ids; level A1–B2; `de` ends in punctuation and has at most two
sentences; `en` and topics present; a focus is a `GrammarFocus` key introduced at or below the
prompt's level; an essay's target lies inside `CEFRLevel.essayWordRange` (A1 30–60, A2 60–110,
B1 110–180, B2 180–280); a Tagebuch prompt has no target. Golden counts in `WritingPromptFixtures`:
Aufsatz 10/12/10/8, Tagebuch 6/8/6/4 by level.

The picker: **Vorschlag** (`coachPick`: a bank prompt whose focus is shaky in the profile, else
random at level), **Bank** (by topic), **Vom Tutor** (one prompt on a topic through
`WritingPromptGate`: German, 1–2 sentences, 3–30 words, a question or instruction, no English
tells, no label leakage; else a bank prompt with a note), **Eigenes Thema**. Adding a prompt: a row
in the JSON, the golden count, `python3 scripts/check_content.py`.

## The coach hand-off

`JournalCoachExport.pendingPlan(for:)`: one-word fixes (`LearnerMemoryService.singleTokenDiff`)
from a check newer than `sharedWithCoachAt`, lookups newer than it, and the notes the share sheet
adds. The sheet shows each as a toggle; "Ask the tutor what I said I find hard" runs the extraction
prompt (`STRUGGLE: <≤ 12 English words> ; <GrammarFocus key or ->`, at most three lines, NONE when
nothing); the learner edits, tags or unticks each note, or types one. The footer names what never
travels: the text, the level, the grammar confidence.

`SelfReportNote` on `LearnerProfile` (`selfReportsData`, cap 10, LRU to the archive as
`MemoryKind.selfReport`, pinnable): text ≤ 80 characters, optional focus, `notedAt`, `timesNoted`,
`entryID`. Its id is the text's letters, so the same thought written twice becomes one note seen
twice. Coach's Notes shows them under "Selbstbericht · In your own words" with a "you wrote this in
your journal" caption. The briefing carries at most one line (two notes, ≤ 40 characters each) and
its `sessionCount > 0` guard is relaxed to notes-or-sessions, so a journal-only learner's own words
steer the first chat; `correctionHint` adds only the focus labels named in notes. The codec rule is
`.set(idField: "id", item: .lwwBy("notedAt"))` with the id written in like a slip's; a payload from
a build without the field merges as an empty set and keeps the other side's notes (tested).

## Lookups and the Today plan

"Nachschlagen" (the selection's edit menu on iOS, the ⋯ menu everywhere) looks a word up in the
bundled dictionary (`WiktionaryValidator.translation(for:)`, offline, never the tutor), remembers it
on the entry (`lookups`) for the hand-off, and can save it to the room's one deck
(`JournalDeckStore`, fixed id, `generatorRaw = "journal"`). Saving to the deck tells the coach
nothing; only Share does.

`TodayIntent.write(prompt:)`: offered when there is no entry today and the last one is three or
more days old, else every third day; the prompt is `WritingPromptBank.daily` (stable through the
day); the page is made when the destination appears (`JournalTodayWriteView`), never in the planner.

## Platforms

| | iPhone | iPad | Mac |
|---|---|---|---|
| Keyboard editor, DE/EN switch, umlaut strip | ✓ | ✓ | `TextEditor` (input sources are system-wide) |
| Pencil page, full screen | – | ✓ | – |
| Ink shown read-only, read into text | ✓ (synced ink) | ✓ | ✓ |
| Check, prompts, hand-off, lookups | ✓ | ✓ | ✓ (tutors run on the Mac) |

## Debug launch arguments (DEBUG, one presenting argument per launch)

| Argument | Does |
|---|---|
| `-schreiben.debugSeed 1` | A mixed DE/EN journal entry with a scribble page and an essay with a bank prompt; idempotent by title; refuses while sync runs. |
| `-schreiben.debugOpen hub\|timeline\|entry\|essay\|prompts\|share\|check` | Opens the screen over the seeded rows. |
| `-schreiben.debugCanned 1` | `WritingCannedTutor` answers the check, the comment and the extraction, so the flow runs where MLX cannot. |
| `-schreiben.debugVerify 1` | The bank gate, the golden counts and the prompt-gate fixtures; prints "Schreiben ALL OK". |

## Verification

- Simulator: builds on iOS and macOS; `-schreiben.debugSeed 1 -schreiben.debugOpen entry`, type,
  leave, the day appears in Today and the calendar; `-schreiben.debugCanned 1 -schreiben.debugOpen check`
  runs a whole check; `… debugOpen share` the hand-off; `-sync.debugVerify 1` includes `JournalEntry`;
  `SchreibenTests` (seven suites); `python3 scripts/check_content.py`.
- Device only (Kyle, via DeviceHub): real tutor output on A2/B1 paragraphs on E4B and E2B (the
  false-correction rate decides whether the rewrite ratio needs tuning); memory on an 8 GB iPad
  through a 40-sentence check; Pencil reading of real handwriting (umlaut dots, ß, cursive line
  merging) and whether dictionary smoothing should default on; two devices editing one entry and
  its ink; the Mac's read-only ink and keyboard writing.

## Later

- Tutors reading the journal in conversation ("Letztes Mal hast du geschrieben, dass …"), through
  the same self-report notes.
- A weekly review of essays: score trend, categories that recur.
- Dictation: the tutor reads a Tagebuch prompt aloud, the learner answers by voice.
