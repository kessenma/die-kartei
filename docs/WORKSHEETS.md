# Übungen · Homework from a lesson PDF

A tutor's lesson arrives as a PDF exported from PowerPoint: explanation slides and exercise slides
("Übungen"). Class gets through some exercises; the rest are homework. This feature turns the PDF
into that homework and back again:

1. **Import** the PDF as a class handout (Deutschkurs, usually under a *Private tutor* course). It
   can come in from Files or straight from another app ("Open in Die Kartei").
2. **Pick the homework.** The parser finds the exercise pages; the learner unticks what was done
   in class. Each page is worked **in the app** (blanks, chips, choices) or **on the slide** with
   the Pencil.
3. **Work it.** Answers save as you go and sync per blank across devices.
4. **Optional check** ("Prüfen"): the teacher's key, then the app's article rules, then the
   downloaded tutor. Handwriting is read and confirmed first. It is only for the learner.
5. **Share** her slides back: only the worked pages, answers written into her blanks in blue,
   unchosen options struck through, ink on top. "Mark as sent" ticks the homework off.
6. **Words to the deck.** The lesson's noun lists and vocabulary slides go into the course deck.

Nothing is tied to one teacher. The rules are the shapes German worksheets share.

## Invariants

1. **Her material stays private.** A lesson PDF is licensed for the learner's own use. It lives on
   the device and the learner's own iCloud, is never sent to a cloud model, and **never enters the
   repo**: the probe and the real-PDF test read it from outside (`~/Downloads`, a fixture folder).
   Tests, previews and the debug screens use `WorksheetSamplePDF`, drawn with the app's own words.
2. **Nothing parsed is stored.** A page is re-parsed whenever it is shown, checked or exported. iOS
   and macOS PDFKit order and group a page's text differently, so a stored text range would point
   at the wrong characters on the other device. Answers are keyed by what the sheet *prints*
   (section letter, item number, the "(3)" before a blank), and each picked page stores its items'
   anchor text so a later parser version can re-key (`WorksheetRekey`).
3. **One renderer.** `WorksheetRenderer` draws the live preview, the slide under the Pencil and the
   exported PDF. What the learner sees is what she gets.
4. **Outside the graded framework.** Worksheets do not go through `KasusRoundStep` or the drill
   shell: those hold validator-owned content with known answers. A worksheet's answers are the
   learner's, ungraded unless they ask.
5. **The check never guesses.** The rules judge only when every input is known; the tutor's
   "unsicher", a missing line or a garbled one is "prüfen", never wrong; handwriting is confirmed
   by the learner before it is judged. None of it is drawn into the PDF.
6. **Ink is one file per page, beside the PDF.** `ClassNotes/Worksheets/<material>/p<N>.drawing`
   syncs through `FileSyncDocument` with no model field. Every write is an upload, so writes are
   debounced (3 s), skipped when unchanged, and an erased page deletes its file.

## Files

| File | What |
|---|---|
| `Services/Worksheet/WorksheetParser.swift` | Pure parser: lines → `WorksheetExercise` (sections, items, segments, options, flags). `WorksheetText` holds the small rules. |
| `Services/Worksheet/WorksheetPDFReader.swift` | PDFKit side: a page's lines with UTF-16 ranges and boxes (splitting lines iOS glues together), and `geometry(of:on:)` — where each blank, option and word sits. |
| `Services/Worksheet/WorksheetDocumentActor.swift` | The open PDF: parses and preview renders off the main thread. |
| `Services/Worksheet/WorksheetRenderer.swift` | Her page + answers + ink, in page space. |
| `Services/Worksheet/WorksheetExport.swift` | The PDF of the worked pages; `WorksheetDocument` for `ShareLink`, rendered lazily and cached. |
| `Services/Worksheet/WorksheetInkStore.swift` | Ink files per page. |
| `Services/Worksheet/WorksheetGrader.swift` | Key check, article rules, tutor prompt and reply parser. |
| `Services/Worksheet/WorksheetInkReader.swift` | Vision on the ink near each blank. |
| `Services/Worksheet/InkLetterReading.swift` | A matching exercise's single letter, read as a tiled "word" (standalone, measurable on the Mac). |
| `Services/Worksheet/LessonWordExtractor.swift` | Nouns from "Nomen:" lines and vocabulary slides. |
| `Services/Worksheet/WorksheetSamplePDF.swift` | The app's own sample sheet. |
| `Models/Worksheet.swift` | `WorksheetSetup`, `WorksheetPagePlan`, `WorksheetAnswer`, `WorksheetCheck`. |
| `Features/ClassNotes/Worksheet/` | `WorksheetSetupView`, `WorksheetView`, `WorksheetItemsView`, `WorksheetCanvas`, `WorksheetCheckView`, `WorksheetWordsSheet`, `WorksheetSession`. |
| `Features/ClassNotes/IncomingHandoutSheet.swift` | "Open in Die Kartei" for a PDF. |
| `scripts/worksheet_probe.sh` | The parser against a real PDF, on the Mac. |

Entry points: the handout page's **Hausaufgabe** section, the review step of *Add a handout* (when
the PDF has exercises), the hub's Homework row (its trailing button), and a PDF opened from another
app.

## The parser

Input is a page's lines in `page.string` order, each with its UTF-16 range and box. The document
pass drops **chrome**: lines that repeat (digits folded) on at least half the pages of a document of
four or more. The page pass:

- **Arranges** lines by position: rows top to bottom, left to right, a lone "1." merged into the
  text beside it, and a line PDFKit ran across two columns split at the second number.
- **Title** is the first line; **subtitle** the next line before the instruction.
- **Instruction**: any sentence starting with an imperative (`WorksheetText.instructionVerbs`:
  Ergänze, Wähle, Bilde, Setze, Schreibe, Verbinde, Ordne, Markiere, Unterstreiche, Notiere, …), or
  "Richtig oder falsch?". "A: Setze …" opens a **section**; numbering restarts in it.
- **Items**: a numbered line ("1.", "1)", "1 "), or any line with a blank (dialog lines keep their
  speaker, "A" or "Alex:", as the label). A plain line directly under a numbered item in the same
  column continues it ("Das ist …"); a line of only underscores up to two line heights under it is
  its answer line.
- **Segments**: `___` runs are blanks (≥ 10 underscores is a writing line, typed); "(3) ___" gives the
  blank its printed number; "…" is a blank only on a sheet with an instruction and no underscores
  at all. "der / den", "der / die / das", "R / F" are inline choices, unless the line has three or
  more slashes (then they are word separators: "Ich / kaufe / Brot / für / ___") or the item has a
  real blank ("9 faulty / broken" + "____" is a gloss). "A speichern B löschen" under an item is a
  choice line, and then that item's "…" is just text.
- **Options**, most specific first: a set named in the section heading or instruction ("Ergänze
  dem, der oder den"); a " · " word bank after the instruction (two lines allowed; "Jedes Wort passt
  einmal" means used once); lettered option lines (A, B, C … with nothing to fill); "Ergänze den
  (bestimmten/unbestimmten) Artikel".
- **Flags**: Markiere → highlight words, Unterstreiche → underline; "Fall"/"Kasus" → a case per
  blank; Bilde/Schreibe … Sätze, Verbinde, Forme … um → a sentence under each numbered item that has
  no writing line of its own (the ruled line is a drawing, with no text).
- **Footer**: "Nomen: …" (also Wörter/Wortschatz) is the noun list; "Lösungen: Folie N" the answer
  key reference; other lines below the last item are notes.
- **Verdict**: `interactive` when something is answerable and there is an instruction (or at least
  two underscore blanks); `writeOnly` for an instruction plus numbered items with nothing to model
  (offered for the Pencil); else `notExercise`. `hasTypedAnswers` marks a page whose items run on
  past their blank with whole sentences — answers typed in during class — so setup starts it
  unticked.

### Keys

`p{page}.{section}.i{number}` for a numbered item, `.r{n}` for an unnumbered one (n in reading
order). A blank is `{item}.g{n}`, or `p{page}.{section}.n{printed}` when it carries "(3)". A choice
is `{item}.c{n}`, the sentence line `{item}.w`, marked words `{item}.m`. Sections are `s0`, or
`sA`/`sB` from their letter.

### What iOS does differently

iOS PDFKit can return one "line" that is really several: the whole column of item numbers glued to
the first item ("1. 2. 3. 4. 5. 6. für der / den Salat", 232 points tall), or a subtitle run
together with "STUDENT EDITION" beside it or the instruction under it. `WorksheetPDFReader.lines`
cuts any line taller than 1.5 typical lines, or wider than half the page, back into rows by its
characters' positions. Use one-character `selection(for:)`, not `characterBounds(at:)`: the latter
counts characters differently from `page.string` (image placeholders shift it) and lands letters
away. The Mac probe and the iOS test now agree on both of the tutor's real PDFs.

## Storage and sync

`ClassMaterial.worksheetData` (`WorksheetSetup`: parser version, pages with mode and anchors,
status, `sentAt`, the teacher's `key` and `samples` read from her Lösungen) is last-writer-wins.
`ClassMaterial.worksheetAnswersData` (`[key: WorksheetAnswer]`) merges **per key**,
`.keyed(item: .lwwBy("at"))`: answers from two devices all survive, the later edit of one blank
wins. Both are in `ClassMaterialCodec`. Deleting a handout, entry or course deletes the ink folder.

## Rendering and export

Page space throughout: points, origin bottom-left, the space PDFKit reports a gap's rect in. Her
page is drawn as vectors (`drawPDFPage`). An answer is centred in a short blank, left-aligned on a
writing line, sitting just above the underline; it shrinks to 60% to fit, and beyond that sits
above the blank at that size rather than running over the next word ("___" is about 27 pt wide).
Case tags go small above the blank in the case's colour; sentence answers one line under the item;
marked words get a highlight or underline; ink is rasterised at 2× and laid on top, in light
appearance (PencilKit renders with the current traits, so Dark Mode would turn black ink white).

The export writes only the worked pages, in page order, each at its own size, via
`CGContext(consumer:mediaBox:)` (Mac-safe). A Pencil page still gets any typed answers drawn.

## The Pencil

`WorksheetCanvas` follows `SchreibblattCanvas` and inherits its traps (docs/SCHREIBBLATT.md):
transparent canvas or the slide is hidden; ink read in the struct's `init`; one canvas per page
(`.id(page)`). The tools, undo and the Pencil gestures are the shared Pencil controls
(docs/SCHREIBBLATT.md ▸ Pencil controls): no system tool picker, a rail at the side, pens and
colours, the highlighter, eraser sizes, the wrist guard, circle to erase.

**Notes paper** (the rail's gear ▸ Notizrand, per page: `WorksheetPagePlan.notes`, optional so
older plans decode): extra ruled paper on any side of the slide, 60% of its width (left, right)
or height (top, bottom), for the learner's own notes and questions. The slide then sits at an
offset in a bigger sheet (`WorksheetNotesPaperView` under it, a `CATiledLayer`). **The file always
holds ink in the slide's own points**: `Coordinator.onSheet` moves it out by the offset when the
canvas is made, `onSlide` moves it back on every save, so the export, the preview and the check
read the slide exactly as before, and ink in the margins (outside the slide) never leaves the
app. Changing the sides re-places the ink in place and clears undo (its steps remember the old
positions). **The check ignores highlighting**: `WorksheetInkReader.read` drops marker strokes. The embedded page and full screen each have their own `PencilBoard`. The
canvas is pinned to the light appearance, because the slide is always white and Dark Mode would
draw the black pen white.

**PencilKit zooms its own ink and nothing else.** Measured in the simulator: at zoom 2 the content
is 1920×1080 while a subview at index 0 stays 960×540. So the slide (a plain view drawing from its
own `CGPDFDocument`) is scaled by hand: anchored at its top-left, transformed by the zoom in
`scrollViewDidZoom`, re-rendered crisp when the zoom ends (capped at 4× the page's points; a slide
at 6× is about 75 MB). And `contentSize` is the *zoomed* size, so it is re-asserted as page × zoom,
never the bare page size. The page fits and centres in whatever space it gets, and fits again when
that space changes, until the learner pinches. `WorksheetCanvasTests` holds all of this.
`SchreibblattCanvas` scales its pages the same way (docs/SCHREIBBLATT.md ▸ On screen).

The canvas runs on the shared Pencil surface (docs/SCHREIBBLATT.md ▸ Pencil surface):
`WorksheetPaper` is the slide (and its notes paper) as a `PencilPaper`, and the coordinator's
`save` is the sink (skip unchanged, write, delete when empty). The page is a drawing page, so the
tab bar steps aside while it is up.

**Full screen** (`WorksheetPencilFullScreen`, on `PencilFullScreenPage`): the slide over the whole
screen, with previous/next page and the page's check, through the shared hand-off
(`PencilHandOff`), so the two canvases never hold one page's ink at once. On the Mac the canvas is
a placeholder; ink written on the iPad syncs and exports from the Mac.

## The check

`WorksheetCheckView`, for one page ("Check this page" under an answered page, the Check button
floating on a Pencil page and in full screen) or every page (the menu). For one page it starts by
itself: it reads the page's handwriting and, once confirmed, checks; a page answered in the app is
checked at once. Results show as ✓ / ? / ✗ beside each answer in the app and on the slide under
the ink (`WorksheetRenderer.Input.showsChecks`, never in the export or the "what she'll get"
preview, unless shared "With the check marks"). A handwriting reading that was confirmed is stored with `source: .ink` and is never typed
onto the page: the ink is already there. Order: the teacher's key
(`WorksheetSetup.key`, read from her Lösungen pages; see *The teacher's key* below), the
**article rules**, the **tutor**.

The rules handle a blank or choice that holds one article: the word right before it sets the case
(a preposition from `PrepositionService`; for a two-way one the item's "(Ort)"/"(Ziel)" hint;
nothing before it in its sentence → Nominativ), the first capitalised word after it is the noun,
its gender comes from the sheet's "Nomen:" list ("die Salate" is plural when "Salat" is a
masculine noun; "Regens" matches "der Regen"), else from the bundled dictionary. A case noted with
the blank is checked too. If any of that is unknown — a verb before the blank, a two-way
preposition without a hint, a noun nobody knows — the rules say nothing.

**A group into a case** (`WorksheetGroupRules`): "ein Brot: ________" under "Setze die Gruppen in
den Dativ mit „mit“" expects "mit einem Brot". The article decides right or wrong ("mit einen Brot"
is wrong, → "mit einem Brot"); a word that doesn't line up — a misread "mit eipen Brst" — is
"prüfen" with a nudge to fix the reading, never wrong. Plural tasks and the Genitiv (whose nouns
change ending) go to the tutor.

The tutor gets one prompt per page: the instruction, the noun list, and each open answer in its
sentence with the answer in [brackets], prefixed by its section's own task on a page with sections
("Schreibe im Plural" changes the answer); it replies `n: richtig|falsch|unsicher ; correct form ;
reason`. A "falsch" whose correction is the answer itself, or brings in a noun the item never
mentions (the E2B tutor answered "mit Eiern" to a misread "ein Brot" item), is read as unsure.
Apple Intelligence is not used: it measured a 100% false-correction rate on German.

Correcting: unsure handwriting readings must be looked at (fixed, an alternative picked, or "Looks
right") before "These are right" is enabled. Confirmed readings fold into one row with **Change**;
every checked answer has **Fix**, which edits it (with the crop of the handwriting) and re-checks
only that answer.

**Share ▸ With the check marks** exports the same pages with ✓ / ? / ✗ beside each answer and the
right form after a wrong one (`Snapshot.showsChecks`, file `…-geprueft.pdf`). "My answers" never
carries them.

Handwriting: for each blank with no typed answer, the ink near it (and only the ink) is drawn on
white at 3× and read by Vision (`de-DE`, accurate, language correction off so "dem" isn't
"corrected"). The confirm list shows each crop beside its reading, unsure ones first, with
alternatives as chips. Strikes on a printed choice are not read: the learner taps the choice.
Scribble already turns Pencil writing in the app's text fields into text.

- **Each stroke belongs to one blank** (`WorksheetInkReader.assign`): the one whose region it
  overlaps most. Handwriting rides high and runs into the rows around it; read for every region it
  touched, a tall "E" turned up at the blank above as "A" and "B" (measured on the IT workbook's
  Übung 01). A blank's crop is its region plus all of its own strokes, so a letter written high
  isn't cut off.
- **A matching exercise's letter** (a `.letters` section): Vision returns nothing for most lone
  letters (4 of 30 in handwriting fonts). Readings are folded from Cyrillic look-alikes (С, В, Е)
  and voted into one of the sheet's letters; when nothing comes back, the letter's own strokes are
  read again tiled three times as a "word" (`InkLetterReading`: 27 of 30 read, none wrong with
  confidence). Only a clean run of one capital ("CCC") is pre-accepted; anything else is asked
  about. Rerun `InkLetterReading` against fonts with a scratch `main.swift` if you change it.
- **A word bank or named set**: a reading that matches takes the sheet's spelling; one that
  doesn't is asked about.
- **Ink is never dropped.** A blank with ink that nothing could be read from comes back unread:
  "Couldn't read this", the sheet's letters or words as chips, a field to type, or **Skip**
  (left out, not checked). It used to vanish, so a page of six letters checked two.

## The teacher's key

`WorksheetKeyReader` (pure, PDFKit-free like the parser) reads her "Lösungen" pages into
`WorksheetSetup.key` (answer key → her answer) and `samples` (answer key → an example). The parser
outputs nothing for such a page, so the reader works on the raw lines:

- A key page has a title starting "Lösung" without a colon ("Lösungen · Übungen 01 und 02"; an
  exercise's "Lösungen: Folie 36" is a pointer, not a key). Blocks start at a line that is only
  "Übung 01" (or "Aufgabe 1"); a title naming one exercise ("Lösungen · Übung 09") makes the whole
  page that block. Answers are "1 …" lines.
- Her slides put two blocks **side by side**, so a line belongs to the header above it in its own
  column (by box: above it, starting left of it, rightmost column, nearest). With no boxes it is
  reading order.
- A block is matched to the exercise page whose title starts with the same number. Answer *n*
  fills the gap printed "(n)" if there is one, else the item numbered *n* plus the unnumbered
  lines after it (an item can wrap its blank onto the next line). Several blanks on one line take
  "a / b".
- "C · error analysis" is the letter C (the chip tray writes the letter); "falsch: …" is falsch,
  matched to an R/F choice by its initial.
- **Samples, never key:** a block whose note says its answers are examples ("Mögliche
  Übersetzungen", "Beispiele. Eigene Antworten sind richtig…", "Sinngleiche…"), and **any block
  that only partly fits** the parsed page. A partial fit means the parser misread the layout (a
  two-column table), so even the answers that landed may sit in the wrong blank.

How the check uses it (`WorksheetCheckView.runCheck`): a match is ✓. A mismatch is ✗ **only for a
closed set** (word bank, letters, the sheet's articles or options, a choice:
`WorksheetKeyCheck.isClosedSet`); an open blank in other words ("40 Stunden" for "40 Stunden pro
Woche") is "prüfen" with her answer (`mismatch`), and the rules and the tutor may still say more.
A sample matched word for word is ✓; anything else is "prüfen" with her example (`example`). The
tutor gets her answer or example beside the learner's (`WorksheetTutorCheck.Question.reference`).

**Lösungen on the slide** (`WorksheetKeyToggle`, on the Pencil page and in full screen, only on a
page her key answers): her answers in green tags beside each blank (`WorksheetRenderer.drawKey`;
"z. B. …" for an example), a choice's right option ringed, for marking your own work when the check
can't read it or you'd rather. A tag sits past the check mark, after the item's printed words on
a one-blank, one-line item, or under the blank when the page has no room; with a ✗ shown, the tag
is the correction (the ✗ doesn't repeat it in orange). Off each time the worksheet opens
(`WorksheetSession.showsKey`). Like the marks, it is never in the export or the "what she'll get"
preview: `WorksheetExport.Snapshot` has no field for it.

When it is read: on setup (`WorksheetSetupView.load`, saved in `save`, with a footer line "Her
answer key was found for N Übungen"), and once for a worksheet set up before the reader existed
(`WorksheetSession.load`, when `key` is nil). `key` is empty, not nil, after a read that found
none, so it isn't read again.

Measured on the IT workbook (Nov 2026, 62 pages, Lösungen on 43–51): 14 of 16 Übungen fully
placed (70 answers in the key, Übung 09 and 13 as examples). Übung 11 (R/F checkboxes the parser
doesn't model yet) and Übung 16 (a two-column table it misreads) only partly fit and are kept as
samples. `scripts/worksheet_probe.sh <pdf> --key` shows this per exercise; `--key-signature` is the
diffable form, which `WorksheetKeyReaderTests.realWorkbookKeyMatchesTheMacProbe` compares with the
iOS reading when `<name>.key.txt` sits beside the PDF in the fixture folder (on a mismatch both
real-PDF tests write `<name>.ios.*.txt` beside it to diff). Measured: the key itself is identical
on iOS and the Mac; only Übung 16's four-column table parses differently (its items and so its
samples), which is why that real-PDF signature test fails for this workbook until the parser reads
that layout.

The key also gives phrase cards: the Wörter sheet's "Wortgruppen" (`KeyPhraseExtractor`,
docs/PHRASES.md).

## Words to the deck

`LessonWordExtractor`: every "Nomen:" entry, and every line of a non-exercise page that is at least
80% article + noun pairs (her vocabulary slide; her "Zusätzlich für die Sätze: der Tisch …" sentence
is 73% and stays out), with "(bread)" after a noun taken as its English. A plural beside its
singular is dropped. `WorksheetWordsSheet` adds the dictionary's English, flags an article the
dictionary disagrees with (unticked, not changed), can fill missing English with the tutor
(`DocumentDeckService.translate`), and saves with `ClassDeckStore.saveWord`.

## Course setup

Adding a handout with no course yet opens the course editor first (kind, and for a course the
start plus a length in weeks with Quarter · 10 / Semester · 14 presets; the end date follows),
with "Skip for now" for a plain default. `ClassCourse.endDate(start:weeks:calendar:)` is the exact
inverse of the "Woche N" count: the end is the last day of the N-th calendar week, so a course
starting mid-week isn't a week too long (`ClassCourseWeeksTests`).

## Debug launch arguments (DEBUG)

| Argument | Does |
|---|---|
| `-classNotes.debugOpen worksheet-setup` | The setup screen over the sample sheet, on the seeded tutor course. |
| `-classNotes.debugOpen worksheet` | The work screen, pages 2–6 of the sample in the app. |
| `-classNotes.debugOpen worksheet-pencil` | The work screen with page 5 on the Pencil. |
| `-classNotes.debugWorksheetRects 1` | Outlines every placed blank in the preview and the export, to report an answer that lands in the wrong place. |

## Verification

- `scripts/worksheet_probe.sh <pdf>` prints how each page reads; `--page N` adds its raw lines and
  boxes, `--rects` where each blank sits, `--signature` a diffable summary, `--key` her Lösungen
  read as the key, `--key-signature` that as a diffable list.
- `WorksheetParserTests`, `WorksheetExportTests` (worked pages only, each answer found inside its
  blank, the sync merge), `WorksheetGraderTests`, `ClassCourseWeeksTests`.
- The iOS reading of a real PDF against the Mac's: put the PDF and its
  `<name>.signature.txt` (from `--signature`) and `<name>.key.txt` (from `--key-signature`) in a
  folder outside the repo and run
  `TEST_RUNNER_WORKSHEET_FIXTURE_DIR=<folder> xcodebuild test … -only-testing:german-ai-flashcardsTests/WorksheetParserTests -only-testing:german-ai-flashcardsTests/WorksheetKeyReaderTests`.

Measured on the tutor's two lessons (Oct 2026): the Präpositionen & Fälle deck reads 10 exercise
pages (AK1, AK2 flagged as filled in, D1, D2 with two sections, N1, W1, G1, G2, M1 with case tags,
the M2 dialog with blanks (1)–(8)) and no explanation slide as an exercise; the Vokabeltraining
deck reads all 16 Übungen (word banks, A–E matching, R/F, the letter and the dialog with numbered
blanks, the two-column writing pages).

**Device-only** (not covered above): real Pencil (palm rejection, sharpness when zoomed), drag and
drop of chips, Scribble into blanks, the tutor's actual replies, handwriting recognition quality,
sharing into the tutoring platform, and the memory log afterwards.

## Later

- The parser layouts her IT workbook showed it can't read yet: R/F checkboxes in table cells
  (Übung 11), a lettered meanings column (Übung 06 glues it onto items 1 and 5), a word bank in the
  note line (Übung 14), a four-column English/Deutsch table (Übung 16), the last word of a bank
  dropped (Übungen 04, 10). Their keys stay samples until then.
- Mistakes into the matching drill (Dativ unit, preposition hub).
- Her review plan ("M1 again in 24 hours, M2 in 7 days") as a redo with answers hidden, on Today.
- Read finished sentences aloud; role-play a dialog exercise with a tutor.
- An opt-in export of the app's check, for learners without a teacher.
