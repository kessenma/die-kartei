# Schreibblatt · Writing sheet

Kyle's German teacher recommends a paper drill: fill a page with "five tables of five" — English
on the left, German on the right — and write the words out again and again. This is that drill.
Pick the words, say how many times to write each one, then write them with the Apple Pencil on
iPad, or export the sheet as a printable PDF anywhere.

**It is copying practice, not a test.** The German is always given. Nothing is graded and no OCR
reads the handwriting: a wrong verdict on real handwriting would make a working feature feel
broken. A recall mode (German blank in the Vorlage too, so you spell from the English) is a knob
over the same layout and is not built yet.

## The sheet

One **Vorlage** — the model table, both columns printed — then one blank writing table per
repetition, same words, same order.

```
VORLAGE                          1
┌───────────┬──────────────┐     ┌───────────┬──────────────┐
│ the house │ das Haus     │     │ the house │              │
│ the dog   │ der Hund     │     │ the dog   │              │
└───────────┴──────────────┘     └───────────┴──────────────┘
```

| Knob | Default | Means |
|---|---|---|
| `Wiederholungen` | 5 | writing tables — how many times each word gets written |
| `Englisch vorgedruckt` | on | off = the English column is blank too, so you write both |
| `Format` | Hochformat | Querformat = A4 on its side, the tables two by two (`Paper.columns = 2`), filled row by row. Endlos = one endless sheet, tables in a list, 2/3/4 across, or one long row (`SchreibblattArrangement`) |
| `Heftlinien` | on | exercise-book ruling on the paper around the tables; looks only, so it can change any time. Each line beside a table is one of its row lines carried out to the paper's edge (and across between tables side by side); none in the strip between rows of tables; the free paper below continues the last rows' spacing |

**Endless sheets** (`Paper.endless`): one "page" as big as its tables, the Vorlage once, no
header, a table's height of free paper below, tables as wide as an upright A4 page's. Capped at
`SchreibblattFormat.endlessMaxRepetitions` (20) tables; one row of them is ~12,000 points wide.
Written on the iPad only: never exported or printed (`SchreibblattSheet.canExport`). "Fit the
width" fits two tables when three or more sit across (`Paper.fitWidth`). The format picker
(`SchreibblattFormatPicker`) draws its pictures from a real layout of the same word count, so
the picture is what gets built.

Rows per table **is the number of words selected**, up to a page (11 upright on A4); a bigger
selection is split into parts (below), never cut.

At the A4 defaults, the teacher's five-of-five is **two pages** — asserted in
`SchreibblattLayoutTests.a4DefaultsPaginateTheTeachersFiveOfFiveToTwoPages`, so changing a paper
metric fails a test and makes someone look rather than quietly producing a three-page worksheet.

**The English column is measured, the German gets the rest.** When a sheet is made,
`SchreibblattRenderer.englishColumnWidth` measures the longest English as printed (half as wide
again when it is handwritten, i.e. `Englisch vorgedruckt` off) and the sheet freezes it
(`SchreibblattSheet.englishColumnWidth`). The layout keeps it within 22–50% of the table, so a
long German phrase ("jemandem (Dat.) beistehen") gets about 72% of an upright row instead of a
fixed 58%. Sheets from before it was measured store 0 and keep `Paper.englishColumnFraction`, so
their ink stays on its rules. On its side a table is half as wide, so upright gives long phrases
the most room; zooming in to write smaller works too.

## Parts · Teile (a deck in chunks)

For writing a whole deck a chunk at a time. The setup screen's **Aufteilen** stepper
(`schreibblatt.partSize`, default 10, 3 up to a page) splits a selection into parts: one sheet per
part, the words shared out evenly (`SchreibblattParts.sizes`: 52 at 10 → 9,9,9,9,8,8, never a stub
of 2). A selection that fits the stepper's size stays one sheet; one bigger than a page is always
split.

- **All parts are made at once**, sharing `SchreibblattSheet.seriesID` (+ `partIndex`,
  `partCount`, `seriesTitle`: the deck's name when the words come from one deck, else the first
  word). Each part is an ordinary sheet (frozen words, its own ink, its own format) titled
  "… · Teil 3 von 5", and names only its own words' decks.
- **The hub lists a set as one row** with its progress ("4 Teile · 24 von 32 Wörtern · weiter mit
  Teil 4"), in Fertig once every part is. It opens `SchreibblattSeriesView`: progress, the next
  part to write, practice offers from the finished parts, every part. Swiping a set away deletes
  every part and its ink, after a confirmation when any part has writing on it.
- **"Weiter" swaps the page in place.** `SchreibblattSheetView` is a host holding the current
  sheet; `SchreibblattSheetPage` is the page, rebuilt per sheet (`.id`). Going on to part 4 never
  stacks part 3's canvas underneath, and Back leads to wherever the set was opened from.
- A blank copy of a part ("Nochmal schreiben") is a sheet on its own, outside the set.

## Karten üben · Practice as flashcards

Fertig opens a checkpoint (`SchreibblattCheckpointSheet`): the words just written as flashcards,
only those, nothing else from their decks. For a part it also offers **the last two parts** and
**everything written so far** (the whole set at the end), and **Weiter: the next part** at the top.
Offers covering the same words collapse into one (`SchreibblattParts.practiceOptions`). Only
finished parts count as written, apart from the one just finished, so a skipped part never joins.

- A sheet's words are `SavedCard` ids (`SchreibblattWord.id`); `DeckStore.practiceSession` fetches
  them in the sheet's order, skips any deleted since (nothing is offered when none is left), runs
  the dictionary check on those cards only, and starts the regular player as a deck mix
  (`isDeckMix`: no pause, each deck credited its share) in **Default** style whatever the app
  default, since an SRS style deals only what is due. The setup screen can still switch.
- A practice set can hold a Goethe-box or other SRS-holder word; `creditDeckMix` skips decks that
  are not `isBrowsableContent`, so their own session clocks don't move.
- The finished banner, the details (iPhone/Mac) and "…" offer it again ("Karten üben…" opens the
  checkpoint's offers for a part). The player is the shell's cover, so the checkpoint acts in its
  `onDismiss`, once it is down.
- "Practice" means `writtenWords`: the words actually on the page (a page-limit prefix).

## Written words · Geschrieben

- **Wörter wählen** shows a pencil and a count on the right of every word already written: how many
  finished sheets it was on (`SchreibblattWortwahlView.writtenCounts`, read once with the cards;
  unfinished sheets and blank parts don't count).
- **The day's log.** A sheet's first Fertig adds its word count to `StudyDay.sheetWordsWritten`
  (synced, a per-device counter like the rest) and stamps `SchreibblattSheet.loggedAt`, so reopening
  and finishing again never counts it twice. It keeps the streak, earns 1 XP a word, counts toward
  the calendar's Items shading, and the day sheet lists each sheet ("8 words by hand, each 5×");
  another device's sheets (sheets don't sync) show as one row from the day's total. No time is
  logged, so the minutes-based Tagesziel doesn't move.

## Invariants

1. **One renderer, two contexts.** `SchreibblattRenderer.draw(_:page:in:)` is the only code that
   draws a sheet. The canvas's ruled view hands it `UIGraphicsGetCurrentContext()`; the PDF writer
   hands it a `CGPDFContext` page. Screen and paper cannot drift, because they are not two
   renderers. Do not add a second drawing path.
2. **One coordinate flip, in `SchreibblattPDF` only.** A PDF page is origin-bottom-left; the
   layout is top-left. Both contexts are y-down by the time the renderer sees them.
3. **Sheet space.** Every rect is measured from the top-left of one continuous space holding all
   pages stacked with `pageGap` between them. That is the canvas's content space directly; the PDF
   subtracts `pageOrigin(page)`. `pageGap` is nonzero for *both* — zeroing it for the PDF would
   mean two sets of numbers.
4. **The Vorlage is not a repetition**, and it is reprinted at the top of every page, so the word
   being copied is never scrolled away.
5. **A table never splits across a page break.** The knobs are clamped to
   `maxWordCount` / `maxRepetitions` instead; the layout has no failure mode.
6. **A lens is a permutation, not a filter.** All four lenses return the same set in a different
   order, so a ticked word cannot vanish by switching lens. Search narrows the visible rows, never
   the selection.
7. **The ranking is a sort, not a cutoff.** Every card is in the Braucht-Übung list, carrying its
   reasons and their counts. There is no threshold, so there is nothing to calibrate.
8. **Ink lives on disk and is local-only.** Sheets do not sync; they stay on the device that made
   them. `SchreibblattSheet` is in `AppSchema.models` but not in `SyncRegistry`.
9. **A sheet's words and knobs are frozen** (the orientation and the measured English column
   included). A blank sheet may still turn (`SchreibblattSheetView.turn`); a written one is offered
   a blank copy the other way up instead. The layout must rebuild byte for byte or the ink
   sits on the wrong rules.

## Files

| File | Role |
|---|---|
| `Services/SchreibblattLayout.swift` | the pure geometry + `SchreibblattWord` |
| `Services/SchreibblattRenderer.swift` | the one draw function, shrink-to-fit, ink |
| `Services/SchreibblattPDF.swift` | the PDF context + `SchreibblattDocument` |
| `Services/SchreibblattInkStore.swift` | ink bytes in `Application Support/Schreibblatt` |
| `Services/SchreibblattPractice.swift` | the card snapshot, the four lenses, the ranking |
| `Models/SchreibblattSheet.swift` | the local-only SwiftData model |
| `Features/Home/SchreibblattTile.swift` | the third wide Home tile |
| `Features/Schreibblatt/SchreibblattHubView.swift` | saved sheets + Neues Blatt |
| `Features/Schreibblatt/SchreibblattWortwahlView.swift` | the selection screen |
| `Features/Schreibblatt/SchreibblattSetupView.swift` | the knobs, Aufteilen (parts), making the sheet or the set |
| `Features/Schreibblatt/SchreibblattSheetView.swift` | the host (swaps parts in place) + the page: canvas on iPad, details + Share elsewhere; the "…" menu; full screen; Fertig → checkpoint |
| `Features/Schreibblatt/SchreibblattCheckpointSheet.swift` | what Fertig opens: practice offers, progress, the next part |
| `Features/Schreibblatt/SchreibblattSeriesView.swift` | a set of parts: progress, next part, practice, every part |
| `Services/SchreibblattParts.swift` | the pure splitting, the practice offers, the next part |
| `Features/Schreibblatt/SchreibblattCribSheet.swift` | the Spickzettel: the floating word table that follows the pen |
| `Features/Schreibblatt/SchreibblattCanvas.swift` | `SchreibblattPaper` (the ruled pages as a `PencilPaper`), the thin wrapper over `PencilSurface`, + Mac stub |
| `Features/Shared/Pencil/` | the Pencil controls every drawing screen shares (below) |
| `Features/Shared/Pencil/Surface/` | the Pencil surface: `PencilPaper`, `PencilSurface`, `PencilPad`, `PencilFullScreen`, `PencilFit` (below) |
| `App/NavBarVisibility.swift` | drawing mode: a Pencil page takes the tab bar away (`hidesNavBar()`) |
| `Features/Schreibblatt/SchreibblattDebug.swift` | launch arguments, seeder, self-verifiers |

## Platforms

PencilKit is split, which decides the whole shape:

| | iOS | macOS |
|---|---|---|
| `PKCanvasView`, `PKToolPicker` | yes | **no** (`TARGET_OS_IPHONE` only) |
| `PKDrawing`, `PKStroke` | yes | yes |
| `PKDrawing.image(from:scale:)` | `UIImage` | `NSImage` |

So the Mac cannot author a sheet but *can* render one's ink into a PDF — which is why the PDF
writer is Core Graphics + Core Text rather than `UIGraphicsPDFRenderer` (UIKit-only, and
`MacCompat` has no PDF-context stand-in). The tile and screens exist on every device; only the
canvas is gated, on `ThisDevice.kind == .iPad` — this is about a physical page and a pencil, not
window width.

## Choosing the words

One list of every `SavedCard` on the device, four lenses over the same selection:

| Lens | Order |
|---|---|
| `Neu` | newest first — **a proxy**: `SavedCard` has no `createdAt`, so this sorts by `(deck.createdAt, sortOrder)`. A real `addedAt` would cost a `SavedCardCodec` change, since cards sync. |
| `Deck` | grouped by deck, newest deck first; the section header toggles a whole deck |
| `A–Z` | alphabetical on the noun, ignoring the article |
| `Braucht Übung` | the ranking: `lapses`, `lastReviewWasCorrect == false`, overdue, `MatchingPairStat.timesMissed`, `ArticleWordStat.timesMissed` |

The three sources key on different things; the only shared key is
`SchreibblattPractice.joinKey` = `ArticleGameService.key(for: bareNoun(german))`.
**`bareNoun` on the matching side is mandatory, not defensive**: `MatchingStats.swift` claims its
`german` is bare, but `MatchingGameView` stores `card.germanWord` verbatim, article and all.
`WortschatzBrowseView.Lookup` gets away without it only because a `GoetheWord` is bare by
construction.

The screen **snapshots the cards once on appear** into value structs. A filtered `@Query` whose
cards are read in `body` re-renders forever once the screen is pushed, and the freeze looks like a
crash; with thousands of cards this is the likeliest screen in the app to hit it.

- **Decks on the rows.** Outside the `Deck` lens every row names its deck in the free space on
  the right (the `Deck` lens heads each group with it instead).
- **The Decks pill** (beside the lenses, when there are two or more decks) narrows the rows to
  the decks ticked in its menu. Like the search, **it narrows the rows, never the selection**: a
  word ticked under another deck stays ticked, and the bar says "N of them not in this view".
- **Alle abwählen** in the bar clears every tick. A new sheet starts from the last sheet's words
  (`schreibblatt.lastSelection`), so this is the quick way to start over.

The hub lists each sheet's decks (`SchreibblattSheet.sourceDeckIDs`, titles read once on appear):
beside the sheet on a wide screen, under it on a narrow one, two at a time with a "+N" that opens
the rest in place. A deck chip, or a pill in the strip above the list, shows only that deck's
sheets. A deck deleted since is left off.

## On screen (iPad)

- **The page fits the screen**, the page's width (default) or the whole page, centred, chosen
  under "…" ▸ Ansicht (`@AppStorage("schreibblatt.fit")`). It refits when the space changes
  (rotation, full screen, the rail changing sides) until the learner pinches; choosing a fit
  refits at once and keeps what was at the top of the screen there.
- **The rules zoom with the ink.** PencilKit zooms only its own ink, so the paper
  (`SchreibblattRulesView`) is scaled by hand as one transform, and `contentSize` is always
  sheet × zoom. It is a `CATiledLayer` (8 levels of detail, bias 3): only the tiles on screen are
  drawn, at the detail the zoom needs, so an endless row is never one bitmap. **Its `draw(_:)` is
  `nonisolated` and runs off the main thread**: the view is immutable (layout, ruling, palette are
  `let`s) and replaced, never mutated, when any of them changes; the renderer is values and Core
  Text only and skips tables outside the tile. `SchreibblattCanvasTests` holds the fit and the zoom.
- **Paper** ("…" ▸ Papier, `@AppStorage("schreibblatt.paper")`, a screen preference, not part of
  a sheet): Weiß, Sepia or Dunkel (`SchreibblattPaperStyle` → `SchreibblattRenderer.Palette`).
  **The canvas's appearance follows the paper, not the app**: light on white and sepia (in Dark
  Mode PencilKit would turn a black pen white, on white), dark on dark paper, where that same pen
  shows white. Strokes keep their light-appearance colour, so a sheet written on dark paper prints
  as dark ink on white. The PDF is always white paper (`drawInk` renders the ink in the light
  appearance too).
- **Drawing mode**: while the sheet is on screen the tab bar steps aside (every Pencil page does,
  see Pencil surface), so nothing under the page can be tapped. The top bar stays.
- **Full screen** (`SchreibblattFullScreen`, on `PencilFullScreenPage`): the sheet without the
  navigation bar either, through the shared hand-off (`PencilHandOff`, below).
- **Spickzettel · Crib sheet** (`SchreibblattCribSheet`): the sheet's words in a small table that
  floats over the page, so the German is never a scroll back to the Vorlage away. On by default
  (`schreibblatt.crib`); the top bar's list button, the full-screen bar's "Spickzettel" and the
  gear show or hide it, and its × closes it. It **follows the pen**: the surface reports each new
  pen stroke's bounds in sheet space (`PencilBoard.lastStroke`), `SchreibblattLayout.cell(at:)`
  finds the table row under the stroke's middle, and that row is marked and scrolled into view.
  Strokes under 7 pt both ways (an umlaut's dots, an i's) never move the mark; highlighter strokes
  and erasing don't either. **Only its title strip drags it**, in global space, so a Pencil near
  it never moves it and dragging never inks the page; where it is let go is kept as a place in
  the free space (`cribX`/`cribY`, 0 to 1), so it stays on screen through rotation and full
  screen. Folded, it shows the row being written and the next one. A finished sheet hides it.
  **Its rows use plain colours, not `.secondary` or `Divider`**: hierarchical styles over the
  material are drawn vibrant, and inside its scroll view they rendered invisible.
- **"…"**: Seite (turn a blank sheet, or start a blank copy the other way up), Ansicht,
  Nochmal schreiben (a blank copy of the same sheet), Alles löschen (undoable until you leave).
- **Fertig** (every device, so a sheet written on paper can be marked too): stamps
  `SchreibblattSheet.finishedAt` and locks the page. Locked means `PencilBoard.isLocked`: the
  canvas scrolls and zooms, its drawing recognizer is off, undo, redo, clear and squeeze do nothing,
  and the rail steps aside. It then opens the checkpoint (Karten üben, above) and logs the day's
  words. A banner offers "Wieder öffnen" (clears `finishedAt`), "Nochmal schreiben" (a part: the
  next part instead) and "Karten üben". The hub lists finished sheets in their own Fertig section. The rail modifier keeps
  the same view structure when locked, so the canvas is never rebuilt (a rebuilt canvas would
  re-read the ink the screen opened with).
- **Share** writes the PDF when someone shares (`SchreibblattDocument` holds the layout and the
  ink file's name), so it carries the ink as it is on disk then, not as it was when the screen
  opened.

## Pencil surface

Every Pencil drawing screen (this sheet, the Deutschkurs slide, whatever drawing exercise comes
next) runs on one engine in `Features/Shared/Pencil/Surface/`. A screen gives it paper; the
engine does the rest.

| | |
|---|---|
| `PencilPaper` | the protocol a screen implements: `sheetSize` (the ink's space), `pageSize` (what "whole page" fits), `fitWidth`, the ink's `appearance`, `gutterColor`, `makeLayers()` (views behind the ink, each at an origin, made fresh), `toSheet`/`toStore` (stored ink ↔ sheet; a worksheet keeps ink in the slide's points), `zoomDidSettle` (sharpen a non-tiled layer) |
| `PencilTiledPaperView` | the `CATiledLayer` base for paper bigger than the screen; `drawPaper` runs **off the main thread**, so subclasses read only `let`s and are replaced, never mutated |
| `PencilSurface` | the engine: container + transparent `PencilCanvasView` + layers; fit (`PencilFit`: width or whole page, refit on a new size until a pinch, top line kept), zoom (layers scaled by hand, `contentSize` = sheet × zoom), centring, debounced save to a sink in stored space, `flush()`, board attach/detach and stroke count, `restyle` (same geometry) and `replace` (new geometry; the ink keeps its stored place, undo cleared if it moved) |
| `PencilPad` + `PencilBlankPaper` | the ready-made page for a new exercise: plain or ruled paper (Weiß/Sepia/Dunkel), the dock, drawing mode; the screen keeps the ink (`onSave` hands `Data?`, nil when wiped) and may add gear rows and tips. `WriteItSheet` (Schreib es, below) is the smallest user |
| `PencilFullScreen` | `PencilHandOff` + `.pencilFullScreen` + `PencilFullScreenPage`: take the inline canvas down a beat before the cover opens (it flushes), rebuild it (`token` as its `.id`) when the cover closes, after `onReturn` re-reads anything held in `@State`; the cover's frame is a Done bar over the canvas, no status bar |

**Schreib es · Write it** (`Features/Cards/WriteItSheet.swift`): after a missed flashcard, a
sheet with the word (article included) over a small `PencilPad` page (400 × 336, so fitted to the
sheet's width its lines come out about 40 pt apart) to write it once looking and once with it
covered (Verdecken). iPad only and optional: `CardStudyPrefs.writeAfterMissKey`, on by default,
switched in the deck's start screen, the player's text menu and Settings ▸ Flashcards, none of
which show it on an iPhone or a Mac (`writeAfterMissAvailable`). It opens once per miss as it is
marked (quiz ✗, Leitner Wrong, Anki Didn't know, a wrong gap choice after a beat, the full-screen
card's ✗), before any auto-advance, so it names the missed card. Copying practice like the sheet:
nothing reads the handwriting, nothing is kept, and the rating is already made. Swipe-to-dismiss
is off so a downward stroke can't close it; Done does.

**Drawing mode.** `.pencilRail` also applies `.hidesNavBar()` (iOS): while a Pencil page is up the
shell slides the NavBar off, stops it taking touches, and lets the tabs run to the bottom
(`navBarClearance` is 0 by the flag, since a slid-off bar keeps its last measured top). Holds are
per tab (`shellTab`, set by the shell on each tab's root) because hidden tabs stay mounted, so a
deep link to another tab still finds its bar. Covers and sheets have no `shellTab`, and the
modifier does nothing there.

Each screen's own rows in the "?" sheet come through `.pencilRail(…, tips:)` (`PencilTipRow`), so
the shared tips never describe paper a screen doesn't have.

## Pencil controls

There is no system `PKToolPicker` anywhere: it floats in its own window over the bottom of the app,
tab bar included. Both writing surfaces (this sheet and the Übungen slide, docs/WORKSHEETS.md) use
the shared layer in `Features/Shared/Pencil/` instead, with Procreate's gestures:

| | |
|---|---|
| `PencilCanvasView` | the `PKCanvasView` subclass both wrappers build. The highlighter (`PencilHighlighter`: PencilKit's marker in yellow/green/pink/blue, its own tool beside the pen, so each keeps its colour; the eraser toggle goes back to whichever was in hand; colour and width cycling act on the tool in hand). The pen (`PencilPen`: Kugelschreiber/Füller/Bleistift/Fineliner = PencilKit's pen/fountainPen/pencil/monoline, black/blue/red (+ yellow on dark paper), three widths), bitmap eraser (rubs out only what it passes over; `fixedWidthBitmap`, the kind that takes a size: 16.4–80.4 pt, the plain `bitmap` one ignores a width; sizes in `PencilEraserSize`), squeeze (Pencil Pro) = pen ↔ eraser, two-finger tap = undo, three-finger tap = redo, the wrist guard. **No Pencil double-tap**: tried, dropped after device testing, and left alone |
| `PencilEraseLoop` | circle to erase: an eraser loop around a word removes every stroke mostly inside it |
| `PencilBoard` | the screen's `@State`: tool, pen, prefs, wrist guard, dark paper, lock, can-undo/redo. The canvas attaches in `makeUIView`, detaches in `dismantleUIView`. `perform(_:)` runs a squeeze action (nothing on a locked page); `notice` is the word shown beside the rail for a moment (what a squeeze switched to, the wrist guard changing) |
| `PencilRail` | `.pencilRail(board, accent:) { canvas settings }`: the slim dock in its own strip on one edge (pen, highlighter, eraser, undo, redo, wrist guard, gear, ?). Upright on the left or right, lying flat along the top or bottom (`PencilRailEdge`); dragged by its handle it follows the finger, turns to match the nearest edge, and settles where it is let go (`pencil.railSide` + `pencil.railPosition`). Only the handle drags, so nothing in the dock or its popovers fights a drag. Tapping the pen, highlighter or eraser in hand opens its picker; the gear opens `PencilSettingsPanel`. Every German label keeps its English beside or under it |
| `PencilPrefs` | the gear's settings, kept for every surface: the squeeze action (`Action`: undo, redo, eraser, next colour, next width, pen picker, off; default eraser), the wrist guard's scrolling (one or two fingers) and pause (0–1 s, default 0.25), the finger taps. Plus the bar's side, and a screen's own canvas settings under "Blatt" (a Schreibblatt's paper, ruling and fit: `SchreibblattCanvasSettings`) |
| `PencilHelpSheet` | the ? sheet: every gesture, the two eraser ones as loops |

Invariants:

- **Each canvas has its own undo stack**: `undoManager` is overridden, so undo needs no first
  responder and never reaches the window's text-field undo. PencilKit registers strokes and erasures
  there; a loop's erase registers a snapshot of the whole drawing beside them (`replaceDrawing`).
  Assigning `drawing` fires `canvasViewDrawingDidChange`, so undo and loop-erase save like a stroke.
- **The tool always starts on the pen** and is never kept. The pen (`pencil.ink`, `pencil.shade`,
  `pencil.weight`) and the wrist guard (`pencil.wristGuard`) are kept for every surface.
- **No custom brushes, no pressure curve.** PencilKit draws only its own inks and has no API for a
  force curve; thickness is the knob it does have. A Procreate-style brush or curve means our own
  stroke engine.
- **The wrist guard** (the hand button on the rail; on: `.pencilOnly`) keeps a hand off the
  canvas. **One finger does nothing: scrolling and zooming take two** (`panGestureRecognizer
  .minimumNumberOfTouches = 2`, re-asserted in `layoutSubviews` because PencilKit configures its
  own pan; 1 on a locked page, or when the gear sets one-finger scrolling, which only applies with
  the guard on: a finger that writes cannot also scroll). That does not fight the two-finger undo tap: a tap is two fingers
  that lift without moving, a scroll two that move, the same split Procreate makes. On top,
  `PalmGuardRecognizer` swallows a finger touch while the Pencil is down, for the gear's pause
  (default 0.25 s) after it lifts, or when it is bigger than a fingertip (`majorRadius` > 30), and the scroll view's pan and
  pinch and the undo taps all `require(toFail:)` it. **A fingertip is not a hand**: iPads report a
  fingertip pressed flat at up to ~42 pt (`majorRadius` comes in ~10.4 pt steps), so the hand
  threshold is 50; at 30, two fingers scrolling or tapping to undo were swallowed with the guard on (the pinch only exists once zoom is allowed, hence
  `layoutSubviews`). A touch it lets through waits 0.08 s first, since a resting hand lands small
  and spreads. `PencilWatcher` sees Pencil touches without taking them. Default: the old
  `pencil.fingerDraws` turned around, else the system's "Only Draw with Apple Pencil"; the first
  Pencil touch turns it on if nobody has chosen. The rule is `PalmGuard.blocks`, tested. Turning
  it on or off (by hand or by itself) shows a note beside the rail for a moment.
- **The Pencil's double-tap is not handled.** A squeeze set to Off in Settings stays off.
- **Circle-to-erase rides on `drawingGestureRecognizer`**, so it sees exactly the eraser's input.
  Its points are `location(in: canvas) / zoomScale`: drawing space is the unzoomed content. Loop
  vs scrub: ≥ 270° total turning, back near the start, real enclosed area (a scrub's cancels out);
  inside is nonzero winding, and a stroke goes when ≥ 70% of its *visible* points are inside (a
  rubbed stroke's `mask` is the part that still shows). The thresholds are a first guess for tuning
  on a device; `PencilEraseLoopTests` pins the synthetic cases.
- **A board only detaches the canvas it holds**: a new page's canvas (`.id(page)`) can be made before
  the old one is torn down.

## Traps already paid for

- **A subview at index 0 of a `PKCanvasView` is invisible** unless the canvas is transparent: its
  internal ink view is opaque when the canvas is, and covers the rules. The canvas is therefore
  `isOpaque = false` inside a container that paints the gutters.
- **Ink must be read before the canvas is made.** `updateUIView` deliberately never reassigns
  `canvas.drawing` (that would round-trip the learner's ink through a copy and reset
  `contentSize`), so ink loaded in `onAppear` — which runs *after* `makeUIView` — never arrives
  and a written sheet reopens blank. `SchreibblattSheetView` reads it in `init`.
- **`contentSize` is set after `drawing`, never before**: assigning `drawing` resets it. It is also
  re-asserted in `canvasViewDrawingDidChange`, because the canvas grows it to keep stray ink
  reachable — otherwise a sheet silently gains a blank page the first time someone writes past the
  margin.
- **`PKDrawing.bounds` is `.null` when empty**, which poisons arithmetic.
- **`drawingPolicy` is `.anyInput` or `.pencilOnly`, never `.default`**, which is pencil-only when
  no tool picker is visible and makes the simulator a dead sheet. The board sets it from the wrist
  guard: on, only the Pencil draws and one finger scrolls; off, a finger draws and scrolling is
  two-finger.
- (Gone with the tool picker: it showed only for a first responder in a window, so it was shown one
  beat after `makeUIView` and torn down in `dismantleUIView`, or it floated over the next screen.)
- **Never nest `PKCanvasView` in a SwiftUI `ScrollView`** — it *is* a `UIScrollView`.
- `canvasViewDrawingDidChange` fires per stroke *and* again when delayed pressure data lands, so
  saves are debounced ~1.5s and flushed in `dismantleUIView`.

## Testing

`SchreibblattLayoutTests` runs on a round synthetic page so expectations are exact arithmetic;
A4 gets its own section. `SchreibblattPracticeTests` covers the join, the lenses and the ranking
over value structs. `SchreibblattPDFTests` reads real PDF bytes back with PDFKit.
`SchreibblattVerifierTests` runs the two self-verifiers. `SchreibblattPartsTests` covers the split,
the checkpoint offers, the next part and the day counter.

Two DEBUG self-verifiers exist because the things that matter most cannot be asserted from a
layout: a PDF that opens but is blank or upside down passes everything else. **Mirrored text
extracts perfectly well, so only the reading-order check catches a botched flip.**

| Launch argument | What it does |
|---|---|
| `-schreibblatt.debugOpen hub\|wahl\|blatt` | opens a screen (one presenting argument per launch) |
| `-schreibblatt.debugSeed 1` | a sheet with synthetic ink, so the canvas is reachable without a Pencil |
| `-schreibblatt.debugLandscape 1` | with `debugSeed`: the seeded sheet on its side, two by two |
| `-schreibblatt.debugVerifyPDF 1` | the PDF round trip — **run this on the Mac**, which the test target cannot reach |
| `-schreibblatt.debugVerifyInk 1` | save → read → overwrite in place → orphan sweep → delete |

Unusually for this app the whole feature runs in the simulator: PencilKit takes mouse input as
finger input with `.anyInput`, and nothing loads an MLX model. Still unverified on hardware: real
Pencil behaviour (palm rejection, pressure, squeeze, two- and three-finger taps,
how circle-to-erase feels) and actual printing. The simulator cannot draw a curve, so
circle-to-erase is checked on the iPad.

## Not built yet

- Recall mode (German blank in the Vorlage too).
- OCR grading. `PhotoOCRService` exists, but handwritten German with umlauts reads unreliably and
  a false "wrong" is worse than no verdict.
- Sync. Travelling means a codec, a `SyncRegistry` entry and the ink through `SyncDocuments`.
- A real `addedAt` on `SavedCard`, which would make `Neu` exact.
- The ~2,800 unreviewed Goethe headwords, which are not `SavedCard` rows and so are not "words on
  your device".
- Letter paper — `paperRaw` is on the model from day one so this needs no migration.
- Attaching a finished sheet to a course as a Deutschkurs handout.
