# Parity audit: Apple Pencil / PencilKit → Android stylus & ink ("Kartei Ink")

Scope: every Pencil/PencilKit feature in the iOS app (`german-ai-flashcards`,
docs in `docs/`), and the Android design (Skip Fuse + a Kotlin-bridged ink module).
Builds on `ai-platform-infra.md` ▸ Schreiben / Schreibblatt / Zeichnen / §2.6 "Ink module".
Android facts checked on developer.android.com / developers.google.com in Nov 2026 (links in §7).

## 1. iOS inventory

### 1.1 Shared engine (`Features/Shared/Pencil/`, ~3.1k lines)
Every Pencil screen runs on one engine. **No system `PKToolPicker` anywhere.**

| Piece | What it does |
|---|---|
| `PencilCanvasView` (PKCanvasView subclass) | tools, its own `UndoManager` per canvas, `UIPencilInteraction` (squeeze), finger undo/redo taps, wrist guard, circle-to-erase |
| `PencilBoard` / `PencilPrefs` | shared state: tool (always starts on pen), pen ink/shade/weight, highlighter, eraser size, wrist guard, lock, can-undo/redo; gear prefs (squeeze action, 1- vs 2-finger scroll, guard pause 0–1 s, finger taps) |
| `PencilRail` | slim SwiftUI dock on any edge (draggable, turns to the edge): pen, highlighter, eraser, undo, redo, wrist guard, gear, "?"; bilingual labels |
| `PencilEraseLoop` | circle-to-erase: an eraser loop (≥270° turning, closes, real area) removes strokes ≥70% inside (nonzero winding) |
| `PencilStudioBrush` | Atelier brush: any PencilKit ink, any colour, opacity 5–100%, free width |
| `Surface/PencilSurface`, `PencilPaper`, `PencilPad`, `PencilFullScreen`, `PencilFit` | transparent canvas over "paper" layers; fit width/page; zoom (paper scaled by hand, `contentSize` = sheet × zoom); `CATiledLayer` paper; debounced save (~1.5 s, flushed on dismantle); hand-off to full screen |
| `PencilHelpSheet` | gesture help |

Capabilities used:
- **Tools:** pen = PencilKit inks `.pen/.fountainPen/.pencil/.monoline` (Kugelschreiber/Füller/Bleistift/
  Fineliner), black/blue/red (+yellow on dark paper), 3 widths; **highlighter** = `.marker` in
  yellow/green/pink/blue; **eraser** = `PKEraserTool(.fixedWidthBitmap)` (partial, rubs only what it
  passes, 16.4–80.4 pt, 4 sizes) + circle-to-erase; Atelier adds `.watercolor`, `.crayon`, `.marker`,
  any colour/opacity. No lasso, no ruler.
- **Pressure / tilt:** implicit only, through PencilKit's inks (fountain pen, pencil shading). **No
  custom pressure curve, no custom brushes** (PencilKit can't load them; documented in SCHREIBBLATT.md).
- **Pencil-only vs finger:** "wrist guard" = `drawingPolicy = .pencilOnly` + `PalmGuardRecognizer`
  (swallows finger touches while the Pencil is down, for 0.25 s after, or `majorRadius` > 50 pt);
  scrolling/zoom take two fingers. Guard off → `.anyInput`, a finger draws. Default follows the system
  "Only Draw with Apple Pencil"; first Pencil touch turns it on if nobody chose.
- **Squeeze (Pencil Pro):** configurable: eraser toggle (default), undo, redo, next colour, next width,
  pen picker, off. **Double-tap deliberately not handled.** **Hover: not used** (no `UIHoverGestureRecognizer`).
- **Undo:** per-canvas stack; two-finger tap = undo, three-finger tap = redo; loop-erase/clear are one
  undoable `replaceDrawing`.
- **Backgrounds:** exercise-book ruling, Schreibblatt tables (tiled, endless up to ~12k pt wide),
  teacher's PDF slide + notes margins, plain/ruled pad, Atelier tracing reference (opacity live),
  paper styles Weiß/Sepia/Dunkel (ink stored in light-appearance colours, so it prints dark-on-white).
- **Zoom:** UIScrollView pinch; paper re-rendered crisp on zoom end (capped 4×).

### 1.2 Features

| Feature | User-visible behaviour | Files | Devices | Ink storage / sync | Recognition |
|---|---|---|---|---|---|
| **Schreibblatt** (five tables of five) | copy-writing drill on ruled tables; Vorlage + N blank tables; formats upright/landscape/endless; crib sheet that **follows the pen** (`PencilBoard.lastStroke` → table row); Fertig locks; PDF export with ink | `Features/Schreibblatt/*`, `Services/Schreibblatt{InkStore,PDF,Renderer,Layout}` | canvas **iPad only** (`ThisDevice.kind == .iPad`); iPhone/Mac print the PDF | `Application Support/Schreibblatt/<UUID>.drawing`, one `PKDrawing` for all pages; **not synced** ("Sheets don't sync") | **none by design** |
| **Schreiben** (journal Pencil page) | ruled page (28 pt, 768 pt wide, grows +512 "Mehr Platz"); "Lies ich das richtig?" reads it into lines, each with its crop, unsure first, confirm before the tutor sees it | `Features/Schreiben/{JournalEntryView,JournalHandwritingSheet,JournalInkPreview}`, `Services/Schreiben/{JournalInkReader,JournalInkStore}` | page **iPad only**; iPhone/Mac show synced ink read-only and can read it | `Journal/<entry>/p<N>.drawing`; **synced** (FileSyncDocument root `Journal`, CKAsset per file) | Vision `VNRecognizeTextRequest`, `.accurate`, **`de-DE` + `en-US`**, language correction **off** by default (gear toggle); page rendered in 1024-pt bands at 2×; highlighter strokes dropped |
| **Worksheets** (answer on the slide) | write on the teacher's slide (and notes margins), highlighter, full screen, Lösungen overlay; optional check reads ink per blank → confirm → grade; PDF export of filled slides | `Features/ClassNotes/Worksheet/{WorksheetCanvas,WorksheetCheckView,WorksheetView}`, `Services/Worksheet/{WorksheetInkReader,InkLetterReading,WorksheetInkStore,WorksheetRenderer,WorksheetExport}` | iOS canvas (iPad-centric; Mac placeholder "Mit dem iPad schreiben") | `ClassNotes/Worksheets/<material>/p<N>.drawing`, ink in slide points; **synced** (root `ClassNotes`); erased page deletes its file | Vision per blank: strokes assigned to the blank they overlap most, ink-only crop at 3×, **`de-DE`**, accurate, LC off; lone letters read tiled ×3 ("CCC") + Cyrillic look-alike folding; matched to the sheet's own options; text fields get **iPadOS Scribble** (system) |
| **Zeichnen · Schnellskizze** (Quick Draw) | timed recall/copy sketches of words, one canvas per word, review keeps some | `Features/Zeichnen/QuickDraw/*`, `ZeichnenCanvas` | **iPad and iPhone** (finger) | kept sketches = **PNG only, no `.drawing`** (iCloud budget), synced under `WordArt` | none |
| **Zeichnen · Atelier** | one word drawn slowly; tracing reference with opacity; studio brush (watercolour, crayon…); halftone finishes (Core Image) on save | `Features/Zeichnen/Atelier/*`, `PencilStudioBrush`, `Services/WordArt/WordArtStore` | iPad and iPhone | PNG + `WordArt/<word>/<id>.drawing` (reopenable); **synced** (root `WordArt`) | none |
| **Zeichnen · Malen nach Zahlen** | tap a region to fill a numbered colour; **tap mode only, no PencilKit**; brush mode = "not built" | `Features/Zeichnen/PaintByNumber/*` | all (finger/Pencil/pointer) | `.pbn.json` + `.progress.json` + PNG, synced | none |
| **Cards · Schreib es / Write it after a miss** | after a missed card, write the word once looking, once covered; small ruled `PencilPad` (400×336) | `Features/Cards/WriteItSheet.swift`, toggle in `CardSettingsView`, deck setup, player menu | **iPad only** (`CardStudyPrefs.writeAfterMissAvailable`) | **nothing kept** | none |

Debug: `SchreibblattDebug`, `SchreibenDebug`, `ZeichnenDebug` seed synthetic `PKStroke`s (force 1,
azimuth 0, altitude π/2), so the features run in the simulator without a Pencil.

## 2. Android platform capabilities

| Capability | Android API | Notes for Kartei |
|---|---|---|
| Stylus vs finger vs eraser | `MotionEvent.getToolType()` = `TOOL_TYPE_STYLUS`, `TOOL_TYPE_ERASER`, `TOOL_TYPE_FINGER` [A1] | eraser end of USI/other pens → eraser tool automatically (iOS has no equivalent) |
| Pressure | `AXIS_PRESSURE` [A1] | feed into ink brush; no curve needed for v1 (parity with iOS) |
| Tilt / orientation | `AXIS_TILT` (radians from perpendicular), `AXIS_ORIENTATION` [A1] | iOS `altitude` is from the surface: `tilt = π/2 − altitude` when converting |
| Hover | `ACTION_HOVER_*`, `AXIS_DISTANCE` (vendor-dependent range) [A1] | iOS doesn't use hover → optional (eraser-size/nib preview), not parity |
| Historical (coalesced) points | `getHistoricalX/Y/AxisValue` / Compose `PointerInputChange.historical` [A1] | ink-authoring consumes these itself |
| Palm rejection | OS sends `ACTION_CANCEL`; `FLAG_CANCELED` on `ACTION_POINTER_UP` (API 33+) [A1] | must undo the canceled pointer's stroke; app-level wrist guard still needed (finger ignored while stylus seen) |
| Stylus buttons | `BUTTON_STYLUS_PRIMARY/SECONDARY` on MotionEvent [A1] | S Pen side button / USI barrel button ≈ iOS squeeze → map to `PencilPrefs.squeeze` action |
| Low-latency rendering | `androidx.graphics:graphics-core` 1.0.4 stable / 1.1.0-beta01: `CanvasFrontBufferedRenderer` (`@RequiresApi(29)`), `GLFrontBufferedRenderer` [A2][A3] | only if we hand-roll; Ink authoring already does low-latency in-progress strokes (`CanvasInProgressStrokesRenderHelperV33`, 720 Hz request in 1.1.0-alpha12) [A4] |
| Motion prediction | `androidx.input:input-motionprediction` **1.0.1 stable** (Nov 2026), `MotionEventPredictor`, uses system prediction when available; 1.0.1 adds stylus `AXIS_RZ` [A5] | pulled in by ink-authoring [A4] |
| Jetpack Ink | `androidx.ink` **1.0.0 stable**, 1.1.0-alpha12 (18 Nov 2026); modules `ink-strokes`, `ink-brush(-compose)`, `ink-geometry(-compose)`, `ink-authoring(-compose)`, `ink-rendering`, `ink-storage`, `ink-nativeloader`; also runs on iOS 15+ and JVM (KMP "Cmn" APIs) [A4][A6] | the engine for Kartei Ink (§5) |
| Stylus in text fields | Compose `TextField` handwriting by default on **Android 14+** with foundation 1.7+, compatible stylus + IME (Gboard); `handwritingDetector`/delegation for placeholder fields [A7] | free Scribble-equivalent for worksheet text answers and journal typing |
| Samsung S Pen extras | **S Pen Remote SDK 1.0.2** (BLE button + Air Actions gestures: Note 10/20, S22 Ultra, Tab S6–S8, S Pen Pro) [A8]; Galaxy S25 Ultra's S Pen **dropped Bluetooth → no Air Actions** [A9] | skip; plain `BUTTON_STYLUS_PRIMARY` covers the useful part |
| USI 2.0 | Pixel Tablet: "Supports USI 2.0 stylus pens" (pen not included) [A10]; Chromebooks/ChromeOS | standard `MotionEvent` stylus; pressure + tilt per USI 2.0 |
| OEM pens | OnePlus Stylo, Lenovo Precision/Tab Pen, Xiaomi Focus Pen: proprietary, pen-per-tablet, usually not interchangeable [A11] | all surface as `TOOL_TYPE_STYLUS` to apps; no SDK needed |
| Detect a stylus | `InputManager.getInputDeviceIds()` → `InputDevice.supportsSource(SOURCE_STYLUS / SOURCE_BLUETOOTH_STYLUS)` [A12] | a built-in digitizer reports `SOURCE_STYLUS` even with no pen in hand → **use "stylus seen" (first `TOOL_TYPE_STYLUS` event, persisted)**, as iOS does with the first Pencil touch |

## 3. Handwriting recognition on Android

| | iOS today | Android proposal |
|---|---|---|
| Engine | Vision `VNRecognizeTextRequest` on a **rendered bitmap** (ink-only crop, 2–3×) | **ML Kit Digital Ink Recognition** on the **strokes** (x, y, t) [M1] |
| German | `de-DE` (+ `en-US` for journal) | model codes `de`, `de-DE`, `de-AT`, `de-CH`… (+ `-x-gesture`) [M2] |
| Where it runs | on device, bundled | on device, offline after a **~20 MB per-language model** download via `RemoteModelManager`; API 23+ [M3] |
| Hints | language correction off (so "dem" isn't "fixed") | `RecognitionContext`: `preContext` (text before) and `WritingArea` (box size) improve accuracy [M3]; no dictionary forcing needed |
| Output | text + confidence per line/candidate | ranked candidates (score may be absent) → keep the existing "confirm, never an answer" UX |

Per feature:
- **Schreiben "read my handwriting":** group strokes into lines (by y against the 28 pt rules, the
  same banding logic in drawing space), recognise each line with `de`; for lines with weak/odd output
  re-run with `en` and let the confirm sheet offer both (iOS passes both languages to one request; ML
  Kit is one model per recognizer). Crops for the confirm sheet: render the line's strokes to a bitmap.
- **Worksheets:** port `WorksheetInkReader.assign` (pure geometry) to the shared core; per blank pass
  only its strokes with a `WritingArea` = blank size and `preContext` = printed text before the gap.
  ML Kit is trained on Gboard single-character input, so the **tiled-letter trick and Cyrillic folding
  are probably unnecessary** (verify on device); keep matching to the sheet's option set.
- **ML Kit Text Recognition v2 on a bitmap** (Latin script, German "Supported") [M4] is built for
  printed text: use it only for ink that has no timing (e.g. a flattened PNG from iOS), not as the main path.
- Gestures (`de-x-gesture`: scribble, strike, circle) could later replace the hand-tuned circle-to-erase
  classifier; keep the iOS geometry (`PencilEraseLoop` is pure math → core) for parity first.
- Schreibblatt, Quick Draw, Atelier, Write it: **no recognition** (same as iOS).

## 4. Data format

`PKDrawing.dataRepresentation()` is an undocumented Apple binary; **Android cannot read it.**
androidx.ink's `ink-storage` (protobuf + delta compression, `StrokeInputBatch.encode/decode`, ByteArray
KMP API since 1.1.0-alpha04) [A6][A4] is Android-native; iOS could only read it via the KMP framework.

**Proposal: a neutral `KInk` v1 file, owned by the shared Swift core** (both apps compile it):

```
KInkDocument { version: 1, space: "pt, origin top-left, light-appearance sRGB",
               size: {w, h}, strokes: [KInkStroke] }
KInkStroke   { brush: { family: pen|fountainPen|pencil|fineliner|marker|highlighter|watercolor|crayon,
                        color: 0xRRGGBBAA, width: pt }, tool: stylus|finger|eraserTip,
               t0: ms epoch, points: [ {x, y, t: ms from t0, p: 0…1, tilt: rad from perpendicular,
                                        az: rad (iOS azimuth convention), size?: pt} ] }
```
Encoding: compact binary (int16 deltas ×100 for x/y, uint16 t, uint8 p/tilt/az; JSON header) or
JSON+gzip for v1 — the core decides once; both platforms only call `KInk.encode/decode`.

- **iOS → KInk:** `PKStroke.path` points give location, `timeOffset`, `force`, `altitude`, `azimuth`,
  `size`, `opacity`; apply `stroke.transform`; **bitmap-erased strokes**: emit one KInk stroke per
  `maskedPathRanges` range (else erased ink reappears). Ink type → family; colour already stored light.
- **KInk → iOS:** `PKStrokePoint(location:timeOffset:size:opacity:force:azimuth:altitude:)` + `PKInk`.
- **KInk ↔ Android:** `MutableStrokeInputBatch` (x, y, elapsed ms, pressure, tilt, orientation) +
  `Brush(family, color, size)`; family map: pen/fineliner → `pressurePen`/custom, marker → `marker`,
  highlighter → `highlighter` (translucent), crayon/watercolour/pencil → custom `BrushFamily` (texture).
- Renderers differ, so strokes look **similar, not identical** across platforms (acceptable: same
  points, same width, same colour).

**Sync decision:**
1. **Now:** Android ink is **per-device**, stored natively as `.kink` (never androidx.ink protobuf), with
   PNG renders where iOS keeps PNGs. Auto Backup covers new-phone restore. Matches the sync plan
   (Drive transport per device, iPhone↔Android later; ai-platform-infra.md ▸ Sync).
2. **When iPhone↔Android sync lands:** iOS writes a `.kink` sidecar next to each synced `.drawing`
   (Journal, Worksheets, WordArt) and converts existing files once; Android reads `.kink` only.
   `PKDrawing` stays iOS's working format, so no iOS feature changes. Android-made `.kink` opens on iOS
   via KInk → PKDrawing on first open.
3. Cheap intermediate: sync a flattened PNG of journal/worksheet pages so the other platform can show
   ink read-only (iOS already renders ink to images for PDF/preview).
4. Schreibblatt ink doesn't sync on iOS → stays per-device on Android too. Quick Draw: PNG only.

## 5. Proposed Android "Kartei Ink" module

**Shape:** a Skip Lite transpiled + bridged module `KarteiInk` (`skip.yml`: `mode: 'transpiled'`,
`bridging: true`, like `GermanVoice`), with Gradle deps on `androidx.ink:*` (pin 1.0.0 stable;
1.1 alphas only if multi-device input is needed), `com.google.mlkit:digital-ink-recognition`. The canvas
is Compose embedded via **`ComposeView { InkCanvasComposer(...) }`** with a `ContentComposer` in an
`#if SKIP` block [S1]. Pure logic (KInk codec, erase-loop geometry, stroke→blank assignment, line
grouping, Schreibblatt layout display list) lives in **DieKarteiCore** so iOS shares it.

Inside the composer: `InProgressStrokes(defaultBrush, pointerEventToWorldTransform = inverse(zoom/pan),
onStrokesFinished)` for live strokes; finished strokes drawn with `CanvasStrokeRenderer` over the paper
in a Compose `Canvas`; pan/zoom with `detectTransformGestures` (two-finger), stylus/finger split via
`PointerType` / `MotionEvent.getToolType` [A6]. Never nest it in a SwiftUI `ScrollView` (same trap as iOS).

**Swift API sketch** (bridged; mirrors `PencilBoard` + `PencilSurface`):
```swift
public enum InkTool { case pen, highlighter, eraser }
public enum InkFamily: String { case pen, fountainPen, pencil, fineliner, marker, highlighter, watercolor, crayon }
public struct InkBrush { var family: InkFamily; var argb: Int64; var width: Double }
public enum InkPaper {                       // drawn behind the ink, in sheet points
    case plain(argb: Int64), ruled(spacing: Double, argb: Int64)
    case displayList(InkDisplayList)          // Schreibblatt tables: lines/rects/text runs from core layout
    case image(path: String, frame: InkRect, opacity: Double)   // slide page, tracing reference
}
public final class InkController {           // one per screen, like PencilBoard
    public var tool: InkTool; public var pen: InkBrush; public var highlighter: InkBrush
    public var eraserWidth: Double; public var stylusOnly: Bool /* wrist guard */; public var isLocked: Bool
    public private(set) var canUndo: Bool; public private(set) var canRedo: Bool; public private(set) var strokeCount: Int
    public var onChange: ((Data?) -> Void)?   // debounced KInk bytes, nil when empty
    public var onStrokeFinished: ((InkRect) -> Void)?   // crib sheet follows the pen
    public var onStylusButton: (() -> Void)?  // ≈ squeeze → PencilPrefs.squeeze action
    public init(ink: Data?)
    public func undo(); public func redo(); public func clear(); public func replace(_ ink: Data?)
    public func snapshot() -> Data?           // Quick Draw "Next" reads now, not the debounce
}
public struct InkCanvas: View { public init(controller: InkController, paper: [InkPaper], sheetSize: InkSize, fit: InkFit) }
public enum InkRender {
    public static func png(_ ink: Data, size: InkSize, scale: Double, paper: [InkPaper]) -> Data?
    public static func pdf(pages: [(paper: [InkPaper], ink: Data?)], pageSize: InkSize) -> Data?   // android.graphics.pdf.PdfDocument
}
public enum InkReader {                       // ML Kit Digital Ink
    public static func ensureModel(_ tag: String = "de") async throws        // ~20 MB, Wi-Fi prompt
    public static func read(_ strokes: Data, tag: String, area: InkSize?, preContext: String?) async throws -> [String]
}
public enum InkDevice { public static var isTablet: Bool; public static var stylusSeen: Bool }
```

Tools per feature:

| Feature | pen | highl. | eraser (stroke / partial) | loop-erase | undo/redo | paper | other |
|---|---|---|---|---|---|---|---|
| Write it | ✓ | – | ✓ | ✓ | ✓ | ruled | ephemeral |
| Quick Draw | ✓ | – | ✓ | ✓ | ✓ | plain square | reference beside; `snapshot()`; PNG |
| Schreibblatt | ✓ | ✓ | ✓ | ✓ | ✓ | tables display list, tiled/endless, zoom | lock; crib follows pen; PDF |
| Schreiben | ✓ | ✓ (ignored by reader) | ✓ | ✓ | ✓ | ruled, grows | ML Kit read + confirm |
| Worksheets | ✓ | ✓ | ✓ | ✓ | ✓ | slide image (PdfRenderer) + notes margins | per-blank read; PDF over slide |
| Atelier | studio brush | ✓ | ✓ | ✓ | ✓ | white/black + tracing image w/ opacity | custom brush families, halftone finish |
| Paint by number | – | – | – | – | fill undo | numbered raster | tap mode needs **no ink module** (Compose Canvas taps); brush mode later |

Eraser: Ink 1.0 has **no built-in eraser**; whole-stroke erase = hit-test strokes' geometry; a
partial (iOS bitmap-like) eraser means splitting a stroke's input batch where the eraser path crosses
it — do whole-stroke first, partial as a follow-up (iOS users will notice the difference in
Schreibblatt). PDF: `android.graphics.pdf.PdfDocument`, draw the paper display list as vectors, ink
rasterised at 2× like iOS (`SchreibblattRenderer`/`WorksheetRenderer` already rasterise ink).

**Rollout (Android), with effort:**
0. **Spike (M):** `KarteiInk` module, `ComposeView` + `InProgressStrokes` on a Galaxy Tab S + Pixel
   Tablet (USI pen) + a phone with finger; check Skip bridging of callbacks/Data, latency, two-finger
   pan/zoom, palm cancel. Decide KInk binary vs JSON.
1. **Write it after a miss (S):** smallest consumer, no storage, ruled pad. Settings toggle shown on tablets / stylus seen.
2. **Quick Draw (S–M):** plain page, PNG out, finger-first; validates phone UX.
3. **Schreibblatt (M):** tables as a core display list (port the CoreGraphics renderer once, draw on
   Compose/PdfDocument), zoom + tiling for endless sheets, crib sheet, lock, PDF export. No OCR.
4. **Schreiben ink + read (M):** ruled growing page, `.kink` store, ML Kit `de` (+`en`), confirm sheet (core UI already designed).
5. **Worksheets on the slide (L):** PdfRenderer slide paper, notes margins + coordinate shift,
   per-blank ML Kit read, export; depends on ClassNotes port.
6. **Atelier (L):** custom `BrushFamily` textures for pencil/crayon/watercolour, tracing layer, halftone
   finishes (android.graphics / RenderEffect port of Core Image). Paint-by-number tap mode (S, independent).
7. Later: partial eraser, stylus hover preview, ML Kit gestures, cross-platform `.kink` sync.

**Phone (finger) vs tablet (stylus) UX:**
- Feature availability follows iOS's device class: **tablet** (`smallestScreenWidthDp ≥ 600`) = iPad
  (Schreibblatt canvas, journal page, Write it); **phone** = iPhone (Schreibblatt PDF/print, read-only
  journal ink; Quick Draw/Atelier with a finger). A phone where a stylus has been seen (Galaxy S Ultra)
  may opt into the tablet features from Settings.
- Wrist guard default: **off** until a stylus is seen, then on (iOS's "first Pencil touch" rule). On:
  only `TOOL_TYPE_STYLUS` draws, fingers pan/zoom (two-finger by default), large `touchMajor` ignored,
  pause after stylus lift. Off: one finger draws, two fingers pan/zoom.
- Two-finger tap undo / three-finger redo on both. Stylus barrel button = squeeze action; eraser tip = eraser.
- Rail: same dock component in SwiftUI (bridged to Compose by Skip), bottom edge default on phones.

## 6. Device support & gating

- **Real stylus support (active pen, pressure, palm rejection):** Samsung Galaxy Tab S series
  (S Pen in the box), Galaxy S Ultra phones (built-in S Pen; S25 Ultra's has no Bluetooth [A9]),
  older Galaxy Note; Google Pixel Tablet with any USI 2.0 pen (sold separately) [A10]; USI Chromebooks;
  OnePlus Pad + Stylo, Lenovo Tab + Precision/Tab Pen, Xiaomi Pad + Focus Pen (proprietary per model [A11]).
  Budget tablets (Galaxy Tab A, most Lenovo M/Xiaomi Redmi Pad) have none; passive capacitive pens act as fingers.
- **Share:** tablets are a minority of Android devices; IDC Q2 2025: Apple 33% of tablet shipments,
  Samsung #1 Android tablet vendor at 18.7% (7.2 M units) [D1]. No public figure for "Android users
  with an active stylus" was found; **estimate: low single-digit % of Android users** (Tab S owners +
  S Ultra owners). Treat stylus as an enhancement, not a requirement.
- **Recommendation for gating:**
  1. Gate **features** on device class (tablet vs phone), never on `SOURCE_STYLUS` presence.
  2. Gate **behaviour** (wrist guard, palm rules, barrel button) on `stylusSeen`.
  3. Gate **OS-version extras** at runtime: `FLAG_CANCELED` (33+), Compose handwriting in text fields
     (34+), front-buffer (29+, only if hand-rolled); ML Kit needs 23+.
  4. ML Kit model download behind an explicit "Handschrift lesen" opt-in (≈20 MB), like the iOS model downloads.
  5. Ship Write it + Quick Draw first: they work well with a finger on any device, so the ink module
     earns its keep before the stylus-heavy Schreibblatt/Worksheets.

## 7. Sources
- [A1] Advanced stylus features (MotionEvent tool types, axes, hover, ACTION_CANCEL/FLAG_CANCELED, low latency, prediction): https://developer.android.com/develop/ui/compose/touch-input/stylus-input/advanced-stylus-features
- [A2] androidx.graphics releases: https://developer.android.com/jetpack/androidx/releases/graphics
- [A3] CanvasFrontBufferedRenderer (`@RequiresApi(29)`): https://developer.android.com/reference/androidx/graphics/lowlatency/CanvasFrontBufferedRenderer
- [A4] androidx.ink releases (1.0.0 stable, 1.1.0-alpha12, Android/iOS 15+/JVM): https://developer.android.com/jetpack/androidx/releases/ink
- [A5] androidx.input releases (motionprediction 1.0.1): https://developer.android.com/jetpack/androidx/releases/input
- [A6] Ink API modules / state & storage / StockBrushes: https://developer.android.com/develop/ui/compose/touch-input/stylus-input/ink-api-modules , https://developer.android.com/develop/ui/compose/touch-input/stylus-input/ink-api-state-preservation , https://developer.android.com/reference/kotlin/androidx/ink/brush/StockBrushes
- [A7] Stylus input in text fields (Android 14+): https://developer.android.com/develop/ui/compose/touch-input/stylus-input/stylus-input-in-text-fields
- [A8] Samsung S Pen Remote SDK overview: https://developer.samsung.com/galaxy-spen-remote/overview.html
- [A9] S25 Ultra S Pen without Bluetooth: https://www.androidauthority.com/galaxy-s25-ultra-s-pen-no-bluetooth-3517872
- [A10] Pixel Tablet specs ("Supports USI 2.0 stylus pens"): https://support.google.com/googlepixeltablet/answer/13555146?hl=en
- [A11] OEM pens not interchangeable: https://ipadstylusblog.com/best-stylus-android-tablet/
- [A12] InputDevice (`SOURCE_STYLUS`, `SOURCE_BLUETOOTH_STYLUS`, `supportsSource`): https://developer.android.com/reference/android/view/InputDevice
- [M1] ML Kit Digital Ink overview: https://developers.google.com/ml-kit/vision/digital-ink-recognition
- [M2] Digital Ink base models (de, de-DE, de-AT, de-CH…): https://developers.google.com/ml-kit/vision/digital-ink-recognition/base-models
- [M3] Digital Ink on Android (API 23+, ~20 MB/language, RemoteModelManager, pre-context/writing area): https://developers.google.com/ml-kit/vision/digital-ink-recognition/android
- [M4] ML Kit Text Recognition v2 languages: https://developers.google.com/ml-kit/vision/text-recognition/v2/languages
- [S1] Skip `ComposeView` / `ContentComposer`: https://skip.dev/docs/modules/skip-ui/
- [D1] IDC Q2 2025 tablet shipments (via SamMobile): https://www.sammobile.com/news/samsung-biggest-android-tablet-brand-q2-2025/

Unverified / to check on device: exact `MutableStrokeInputBatch` signature and orientation axis
convention vs iOS azimuth; whether ML Kit reads lone handwritten letters reliably; PdfDocument canvas
with `CanvasStrokeRenderer` (fallback: rasterise); Skip bridging of `Data` callbacks from a ContentComposer.
