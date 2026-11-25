# Zeichnen · Draw

The Zeichnen room is the wide Home tile under Schreibblatt. Drawing a word fixes it in memory
better than writing it out (the "drawing effect"), so the room offers three ways to draw a word.
It also gives every word a folder of pictures.

| Part | What it is |
|---|---|
| **Bildermappe · Picture folder** | Every picture of one word: AI pictures in chosen styles, kept sketches, Atelier pieces, paint-by-number pictures. |
| **Schnellskizze · Quick Draw** | A timed run of n words. Each run is *recall* (draw from the German word, then reveal and mark) or *copy* (sketch the reference), chosen per run. |
| **Atelier · Studio** | Unhurried drawing from a reference, with a richer brush, a tracing layer and halftone finishes. |
| **Malen nach Zahlen · Paint by number** | A calm mode: a picture becomes numbered regions, and the key teaches German colour names. |

## Files

| What | Where |
|---|---|
| Models | `Models/WordArt/`: `WordArtwork`, `WordDrawingStat`, `QuickDrawSet`, `WordArtKey`, `WordArtStyle` |
| Files on disk, adopt-as-card-picture | `Services/WordArt/WordArtStore.swift` (`WordArtStore`, `WordArtLibrary`) |
| Cloud generation | `Services/WordArt/WordArtGenerator.swift`; prompts in `CardIllustrationPrompts.artPrompt` |
| Drawing stats | `Services/WordArt/WordDrawingLog.swift` |
| Word sources, coach pick | `Services/WordArt/ZeichnenCatalog.swift` |
| Quick Draw state machine | `Services/WordArt/QuickDrawSession.swift` |
| Paint-by-number generator, renderer, colour names | `Services/WordArt/PaintByNumber/` |
| Sync codecs | `Services/Sync/Codecs/WordArtCodecs.swift` |
| Screens | `Features/Zeichnen/` (hub, tile, gallery, canvas, `QuickDraw/`, `Atelier/`, `PaintByNumber/`, debug) |
| Studio brush | `Features/Shared/Pencil/PencilStudioBrush.swift`, wired through `PencilBoard.studioBrush` |
| Tests | `german-ai-flashcardsTests/ZeichnenTests.swift` |

## Storage: pictures belong to the word

- **Key.** `WordArtKey.make` drops a leading der/die/das, lowercases, trims and folds spaces.
  *der Tisch* in two decks and in Wortschatz shares one folder. Umlauts and ß are kept.
- **Records.** Each picture is its own `WordArtwork` record, so two devices adding pictures never
  conflict.
- **Files.** Each picture is a file under
  `Application Support/WordArt/<UUIDv5 of key>/`:
  - `<id>-<token>.png`: the picture. The token changes on every rewrite, so views reload.
  - `<id>.drawing`: the ink, for Atelier pieces only.
  - `<id>.pbn.json`: the paint-by-number template.
  - `<id>.progress.json`: paint-by-number progress.
- **Sync.** `WordArt` is a `FileSyncDocument` root. Older builds:
  - ignore files under roots they don't know (`destination` returns nil);
  - hold back record kinds they don't know (`SyncApplier`).
- **The card's picture is untouched.** `SavedCard.imageFileName` is still the card's own picture.
  "Use as card picture" copies a gallery file into `CardImages/<deck>/` at 512 px, so old builds
  see an ordinary card picture. It is refused for `goethe-srs` cards: sync never carries their
  content, so the copy would never reach the learner's other devices.
- **Sizes.**
  - AI references: 1024 px (`WordArtStore.artMaxPixel`). This is the documented exception to
    "pictures land at display size" in CLOUD_PICTURES.md.
  - Kept quick sketches: a 768 px PNG only.
  - Atelier pieces: a 1024 px PNG plus the ink.
- **The iCloud-space note.** Quick Draw's "Keep my sketches" toggle (off by default) and the review
  both say a kept sketch is about 80 KB, and show the size of `WordArt/` today.

## Invariants

1. **Every word drawn counts, kept or not.** `WordDrawingLog` updates `WordDrawingStat`
   (`quickCount`, `studioCount`, `paintedCount`, `recallRight`, `recallMissed`), and
   `StudyLogService.record(.drawing(n))` adds to `StudyDay.wordsDrawn` and `drawingSeconds`
   (1 XP a word).
2. **Drawing never moves SRS/Leitner**, the same as the Spiele games. A recall miss reaches the
   coach only as an encounter (`noteVocabEncounters`, source `zeichnen.quick`).
3. **No filtered `@Query`.** Every Zeichnen screen fetches on appear, and refreshes after a run or
   on `.syncedFileLanded`. Reading `@Model` rows in `body` from a filtered query re-renders forever.
4. **Gallery pictures are cloud-only** (`StoryImageService.beginCloudSession`), whatever the
   picture-source setting says. The styles are written for Muse Image and Nano Banana, and a cloud
   session loads nothing, so a deck run on the device's own model can carry on alongside.
5. **The coach pick never pads.** `ZeichnenCatalog.weakest`:
   - ranks every card with `SchreibblattPractice`'s "Braucht Übung" lens;
   - keeps only words that have a reason (lapse, wrong last answer, overdue, game misses);
   - never pads with other words, so a learner with no history gets fewer words.
6. **Atelier ink is never lost on Back.** The canvas's save callback writes into an `AtelierDraft`
   box. `onDisappear` waits one run-loop turn, because the canvas flushes as it is torn down, and
   then saves the draft as a studio piece.
7. **One canvas per Quick Draw word** (`.id(turnID)`). The ink is read from `ZeichnenCanvasHandle`
   when the turn ends, not from the surface's debounced save.

## Styles (`WordArtStyle`)

The styles:
- Skizze (the copy-mode reference)
- Kontur (black ground, one acid-yellow or crimson figure, contour hatching)
- Anime
- Volkskunst
- Bauhaus
- Märchenstich (fairy-tale engraving)
- Kaiserlich
- Illusion
- Theater
- Malvorlage (flat colours, made for numbering)

The fragments describe a look and never name an artist. `artPrompt` leaves the background to the
style. Card pictures keep their own `CardImageStyle`; the two never mix.

## Quick Draw

- **Setup.** The sources are:
  - Coach (weak words)
  - Decks (multi-select)
  - Sets (`QuickDrawSet`, which points at card ids; Wortschatz and singleton card ids are
    canonical)

  The other choices:
  - 5/10/20 words
  - 20/40/60 s a word
  - recall or copy
  - keep sketches
  - in copy mode, "Draw N Skizze references" for words that have none
- **Run.** The word sits in the top bar. The clock is a ring and is red in the last 5 s. Next is
  "Aufdecken" (reveal) in recall runs. In copy runs the reference sits beside the page (above it on
  compact width).
- **Review.** Tap a sketch to keep or let go it, or use All / None. "Save words as a set" saves
  only the misses when there are any. Fertig records the run.

## Atelier, phase 1 (PencilKit)

- **Brush.** `PencilStudioBrush` offers:
  - PencilKit's inks: pen, pencil, fineliner, fountain pen, marker, **watercolour** and **crayon**
  - any colour (a palette plus the system colour picker)
  - **opacity** (the `PKInkingTool` colour's alpha, 5–100 %)
  - a free **width** across the ink's own range

  While set on `PencilBoard`, it replaces the plain pen. Schreibblatt and worksheets never set it.
- **Paper.** White or black. On black paper the stored colour is the light-appearance colour, as
  with the plain pens.
- **Reference.** A layer under the ink with an opacity slider, shown or hidden from the rail's gear.
  "Andere Vorlage" picks another picture of the word.
- **Finishes** (`ZeichnenHalftone`, Core Image): dots, colour dots (CMYK), lines, hatching. A
  finish applies to the saved PNG, and the ink stays as drawn, so a reopened piece can take
  another.

### Phase 2 (not built): the brush engine

PencilKit cannot load brushes. Smudge, airbrush and a true halftone *brush* need a stamp-brush
engine of our own:
- **Renderer.** Port MaLiang's Metal stamp renderer (MIT).
- **Smudge.** Follow libmypaint's approach (ISC).
- **Halftone brush.** Draw a coverage mask, then apply a dot grid fixed to the page.
- **Brush tips.** CC0 only: mypaint-brushes, David Revoy's CC0 Krita set, OpenGameArt's "60 free
  GIMP/Krita brushes". **Never** Procreate packs or Krita's GPL assets.
- **Format.** A `.strokes` file next to the PNG. Every other reader uses the flattened PNG.
- **First step.** Spike it: measure Pencil latency on an iPad before building more.

## Malen nach Zahlen

**Pipeline.** `PaintByNumberGenerator` follows drakarah/paintbynumbersgenerator (MIT):
1. A 480² RGBA buffer.
2. Seeded k-means++ in Lab: Leicht 8 colours, Mittel 14, Schwer 20.
3. Two 3×3 majority passes.
4. 4-connected regions.
5. Regions under the difficulty's minimum area merge into the neighbour with the longest shared
   border.
6. The colours are numbered by area.
7. Each label goes at the pixel furthest from its region's edge: a chamfer distance transform, the
   raster form of polylabel's pole of inaccessibility.

**Why a raster, not vector outlines.**
- A tap is a lookup.
- Filling is a recolour of a 480² buffer.
- Outlines render once at 960².
- Labels come straight from the distance transform.

The cost is a slightly stepped outline, which reads as a printed sheet.

**Colour names.** `GermanColorName.uniqueNames` picks the nearest of about 30 colour words in Lab.
Two colours on the same word become hell-/dunkel-, and any still alike are numbered.

**The AI's part.** A model can't draw a numbered template (the no-text clause, and the digits come
out garbled). So "Malvorlage" asks for flat colour areas, and the numbering happens on the device.
Any picture in the folder can be numbered.

**Play.**
- Tap mode only so far, which works with a finger, the Pencil or a Mac pointer.
- A wrong region shakes, with no penalty.
- "Zeig mir" washes the regions the chosen colour still needs.
- Pinch to zoom; numbers too small to read wait for a zoom.
- A long press on a swatch speaks the colour name.
- Progress and a preview are saved every 10 fills and on leaving.
- Finishing fades the outlines and clears `inProgress`.

**Not built: brush mode.** The Pencil would paint inside the lines: a `PencilCanvasView` masked to
the chosen colour's regions, with each region counted done above about 85 % coverage.

## Debug launch arguments (DEBUG)

- `-zeichnen.debugSeedArt 1`: two flat-shape pictures (Kontur and Malvorlage) for the first four
  words, and a paint-by-number begun on the first. No OpenRouter spend.
- `-zeichnen.debugOpen hub|quick|run|review|studio|gallery|pbn|paint` opens:
  - `run`: a copy run of five words
  - `review`: a finished recall run with scribbles
  - `paint`: the begun piece
- With an empty simulator, add `-screenshots.debugFill 1` for decks to draw.

## Open

- Device check (Kyle): Pencil feel in the Atelier, Quick Draw timing, paint-by-number on an iPad
  (and Kyle's mom's verdict on Leicht/Mittel).
- Two-device sync of a gallery, a set and the stats; an old TestFlight build beside a new one.
- One real Muse picture per style before trusting the prompts (`scripts/openrouter_image_probe.py`).
- Paint-by-number brush mode; Atelier phase 2; "Restyle my sketch" (send a sketch as a reference).
