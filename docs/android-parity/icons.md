# Icons: SF Symbols on iOS → Android equivalents (Die Kartei)

Scope: iOS `german-ai-flashcards/` + `KeyboardExtension/` at main `42b1cc7`; Android worktree
`DieKarteiAndroid` at `8b99cfd`; SkipUI checkout in its `.build/checkouts`. Read-only audit, nothing
built or run on the emulator. Full table: `icon-map.csv` (463 rows). Scripts and downloaded metadata:
`icon-work/` (`scan.py` inventory, `mapping.py` SF→Material/alt map, `build.py` CSV + stats).

## 1. Method

- **Inventory**: every string literal in 749 Swift files was checked against the SF Symbols name list
  shipped with macOS (`CoreGlyphs.bundle/name_availability.plist` + aliases, 9,777 names). Literals in
  `systemName:`/`systemImage:`/`icon:`/`symbol:` contexts were kept as-is. Bare literals (enum
  `var systemImage: String { case .x: "cpu" }`, helper calls like `ActivityRow(…, "archivebox")`) were
  kept by pattern, and English vocab strings ("house", "table", "dog", "key") were dropped by hand.
  Also scanned: `Resources/whats_new.json` (icons rendered by the What's New sheet) and `link.badge.minus`,
  which is newer than this Mac's glyph list.
- **No interpolated symbol names**: there are no `"\(name).fill"` strings and no `.symbolVariant`
  calls. Every fill variant is spelled out as a literal, so each `.fill` name is its own CSV row.
- **Matching**: every proposed Material Symbols name was checked against Google's Rounded codepoints
  list (4,304 names). Phosphor (3,060), Lucide (2,124) and Tabler (5,509) names were checked against
  their published indexes. The ~35 hard cases were compared visually: SF rendered locally with AppKit
  (dev-only reference, `icon-work/sf_sheet.png`) next to the candidate SVGs (`icon-work/cand/`).
- **Quality scale**: `exact` = same concept, near-same shape · `close` = same concept, different
  drawing · `concept` = meaning only · `none` = draw it. `match_quality` rates the Material match. When
  an alternate library does better, the `notes` column says so (`alt match=exact`).

## 2. Licence finding: SF Symbols may not ship on Android

- **Xcode and Apple SDKs Agreement §2.10 "System-Provided Images"**, quoted from the local Xcode
  `License.rtf`: Apple's system-provided images and symbols "are licensed to You **solely for the purpose
  of developing Applications for Apple-branded products** that run on the system for which the image
  was provided." The same section bars them, and anything "substantially or confusingly similar", from
  app icons, logos and trademark use.
- **The SF Symbols app licence** says: "THE APPLE SOFTWARE IS TO BE USED SOLELY FOR CREATING USER
  INTERFACES TO BE USED IN SOFTWARE PRODUCTS RUNNING ON APPLE'S iOS, iPadOS, macOS, tvOS OR watchOS".
  It also says you agree not to use the Symbols or templates "for … software products running on any
  non-Apple operating system". Apple staff gave the same answer on the developer forums (thread 757407,
  "Is SF Symbols only allowed on Apple platforms?": "Yes").
- **Conclusion: exporting SF Symbol SVGs (or tracing them) for the Android build is not allowed.**
  Skip's docs suggest "You can also export symbols from the SF Symbols app". That is fine for Darwin
  targets only, so don't follow it for Android. Also, HIG: "Don't design replicas of Apple products" (the
  `applepencil.*`, `iphone`, `ipad`, `macbook*`, `apple.intelligence` glyphs).
- **Allowed sets**: Material Symbols (Apache-2.0, ship the NOTICE/licence in the app's licences
  screen) · Phosphor (MIT) · Lucide (ISC) · Tabler (MIT). Each needs its copyright notice included. The
  app's own PNGs and logos are fine.

## 3. Summary

| | count |
|---|---|
| Distinct SF Symbol names | **463** (124 of them `.fill` names) |
| References | **2,236** in 334 files + `whats_new.json` (64) |
| Rendered by SkipUI today (its fallback table) | 47 names / 513 uses (23%). Every other name shows the ⚠ "missing icon" triangle |
| Material Symbols Rounded match: exact / close / concept / none | 269 / 134 / 52 / 8 names (by uses: 1,516 / 586 / 118 / 16) |
| Best of Material + Phosphor/Lucide/Tabler | 303 / 129 / 29 / 2 (by uses: 1,661 / 538 / 35 / 2) |
| Names where an alternate beats Material | 34 (Phosphor 55 rows, Lucide 23, Tabler 11 offer alternates) |
| Distinct Material Symbols needed | 319 |
| Used only on Apple-only surfaces (macOS shell, PencilKit, keyboard extension, iCloud/Mac helper) | 27 names. Low priority |
| `.symbolEffect` / `.contentTransition(.symbolEffect)` / `.symbolRenderingMode` / `.imageScale` | 7 / 7 / 5 / 9 call sites. All are `@available(*, unavailable)` or missing in Skip Fuse UI |

**Uses by feature** (refs/distinct): Grammar 286/120 · Settings 259/130 · Conversation 222/120 ·
ClassNotes 213/98 · Cards 163/83 · Progress 110/59 · Home 107/62 · Stories 97/60 · Schreibblatt 84/45 ·
Zeichnen 80/47 · Schreiben 65/45 · WhatsNew 65/54 · JobPrep 62/29 · Hören 53/34 · Queue 39/27 ·
Library 38/30 · Onboarding 30/20 · Paper 29/21 · Wortschatz 21/20 · DocumentDeck 20/16 · Spiele 16/14 ·
Matching 15/11 · TabBar 9/9. **Apple-only surfaces:** Pencil (PencilKit) 40/24, Mac shell 34/23,
keyboard extension 8/7. Those surfaces plus iCloud sync settings are flagged `apple-only use` in the CSV
notes.

Most used: `checkmark.circle.fill` 111, `chevron.right` 41, `checkmark` 39, `exclamationmark.triangle` 34,
`book.pages` 32, `xmark.circle.fill` 32, `circle` 31, `questionmark.circle` 30, `info.circle` 29,
`trash` 29, `xmark` 29, `arrow.up.right.square` 27, `checkmark.seal(.fill)` 49, `checklist` 25,
`rectangle.stack(.fill)` 44, `rectangle.stack.badge.plus` 22, `sparkles` 22, `character.book.closed` 18.

### Custom image assets (app-owned, ship to Android as-is)

`Assets.xcassets` contains no vector PDFs or SVGs; everything is PNG or JPG:
- **Lernpyramide art**: 37 `pyramid-icon-*` imagesets (2 PNG each, ~250 KB each). These are layer icons
  and badges (`pyramid-icon-abzeichen-*`), referenced by name and through `pyramid-icon-\(layer.id.rawValue)`.
- **Logos**: `logo-gemma`, `logo-qwen`, `logo-meta`, `logo-mistral`, `logo-microsoft`, `logo-ibm`,
  `logo-sd21`, `logo-bksdm`, `logo-goethe`, `logo-goethe-square-icon`, `logo-wiktionary`, `github-mark`.
  These are third-party marks used as attribution, as on iOS. `logo-apple` is referenced in
  `ModelConfiguration.swift` but has no asset; it sits on the Apple Intelligence path, which is iOS-only.
- `figur-still` (PNG).
- `voice-guide-*`: 7 JPG screenshots of **iOS Settings**. These are meaningless on Android, so Android
  needs its own TTS-settings screenshots.
- `Resources/`: 173 `*3d-*-dim.png` scene stills (18 MB) and the `*.usdz` models. These are covered in
  `3d-and-learning.md`.
- How to ship them: copy the imagesets into `Sources/DieKartei/Resources/Module.xcassets` and load them
  with `Image("pyramid-icon-x", bundle: .module)`. SkipUI's Coil loader handles PNG, JPG, SVG and PDF.

## 4. Problem icons (SF-specific, tab bar, and weak matches)

| SF Symbol | uses | Material Symbols Rounded | Material match | Better alternate | Recommendation |
|---|---|---|---|---|---|
| `rectangle.stack` / `.fill` | 23 / 21 | `cards_stack` | concept | Phosphor `cards-three` (exact, has fill) | Phosphor. It's the app's core "deck" mark, so it's a good Bauhaus custom candidate |
| `rectangle.stack.badge.plus` | 22 | `library_add` | close | – | Material |
| `brain.head.profile` (Library tab) | 7 | `psychology` (head with gear) | close | Phosphor `head-circuit` (close) | Material. Custom candidate because it's a tab identity |
| `gearshape.2` (Settings tab) | 1 | `manufacturing` (two gears) | exact | – | Material |
| `checklist` / `.checked` (Grammar tab) | 25 / 1 | `checklist` | exact | – | Material |
| `figure.stairs` (Settings › Level) | 3 | `stairs` | concept | Tabler `stairs-up` (close) | No set has a person on stairs. Custom Bauhaus |
| `square.stack.3d.up` / `.fill` | 6 / 3 | `layers` (2 layers) | close | Phosphor `stack` (3 layers, exact) | Phosphor |
| `memorychip` | 9 | `memory_alt` (RAM stick) | close | Phosphor `memory` | Material |
| `cpu` | 6 | `memory` (chip) | exact | Phosphor `cpu` | Material |
| `character.book.closed` / `.fill` | 18 / 5 | `dictionary` (open book with A) | close | Lucide `book-a` (closed book with A, exact; stroke) | Lucide (outline the strokes) or Material |
| `character.bubble` / `.fill` | 1 / 2 | `translate` | concept | Tabler `message-language` (bubble with A, exact) | Tabler |
| `book.pages` | 32 | `auto_stories` | close | Phosphor `book-open-text` | Material |
| `books.vertical` / `.fill` | 2 / 1 | `library_books` | concept | Phosphor `books` (close) | Phosphor |
| `cube.transparent` | 2 | `deployed_code` | concept | Phosphor `cube-transparent` (exact) | Phosphor |
| `pyramid.fill` | 2 | `change_history` | concept | Lucide/Tabler `pyramid` (outline only) | Reuse the app's pyramid art or a custom filled pyramid |
| `metronome` | 1 | – (`timer`) | concept | Phosphor `metronome` (close) | Phosphor |
| `sparkle` | 2 | `auto_awesome` (3 stars) | concept | Lucide `sparkle` (exact) | Lucide |
| `tortoise` / `.fill` | 2 / 7 | none | none | Lucide `turtle` (exact, stroke) | Lucide |
| `hare.fill` (Fabel genre) | 1 | `cruelty_free` (rabbit face) | concept | – | Custom |
| `figure.stand` / `figure.stand.dress` / `figure.stand.dress.line.vertical.figure` (der/die/das, hangman) | 6/3/3 | `man` / `woman` / `wc` | exact | – | Material. These match well |
| `circle.square`, `square.on.circle`, `circle.lefthalf.striped.horizontal` (WordArt Bauhaus styles) | 1 each | none / `category` / `contrast` | none–concept | Tabler `circle-square` for square.on.circle | Custom. Trivial geometry, on-brand |
| `square.grid.3x3.topleft.filled` / `.bottomleft.filled` (game kinds) | 1 / 1 | `grid_on` | concept | – | Custom (3×3 grid with one filled cell) |
| `circle.dashed`, `circle.dotted` | 5 / 2 | `radio_button_unchecked` | concept | Lucide `circle-dashed`, Tabler `circle-dotted` (exact) | Lucide/Tabler |
| `a.circle`, `a.square`, `d.circle`, `e.circle`, `number.circle` | 1–2 | none | none | Tabler/Lucide `circle-letter-*` | Better: `Text("D")` in a `Circle()` |
| `ear.badge.waveform` (Listening category) | 6 | `hearing` (no badge) | close | – | Material |
| `waveform` | 10 | `graphic_eq` | close | Phosphor `waveform` | Material |
| `location` | 1 | `near_me` | exact | – | SkipUI's fallback draws a map pin (`LocationOn`), which is wrong. Ship a symbolset |
| `square.and.arrow.up` | 13 | `share` (Android idiom) / `ios_share` (same as SF) | close | – | Use `share` on Android |
| `apple.intelligence`, `applepencil.*`, `iphone`/`ipad`/`macbook*` | 1–6 | `auto_awesome`, `stylus`, `smartphone`/`tablet`/`laptop` | – | – | Apple-product glyphs. Use generic devices; the paths are iOS-only anyway |
| `*.circle.fill` with no Material circle variant (`arrow.clockwise.circle.fill`, `arrow.uturn.*.circle*`, `pencil.circle*`, `photo.circle.fill`, `pin.circle.fill`) | 1–3 | base icon | concept | Phosphor has several circled versions | Draw the base icon on a `Circle()` background |
| Badge composites (`*.badge.exclamationmark`, `tablecells.badge.ellipsis`, `keyboard.badge.ellipsis`, `checkmark.circle.trianglebadge.exclamationmark`) | 1–2 | base icon | concept | – | Base icon plus a small overlay |

**Custom Bauhaus set (8–10 drawings):** `rectangle.stack`, `brain.head.profile`, `figure.stairs`,
`pyramid.fill`, `hare.fill`, the three WordArt geometry marks, and the two 3×3 game grids. The
rest is covered by Material Symbols plus about 30 Phosphor/Lucide/Tabler glyphs.

## 5. Where the Android port uses different icons from iOS today

| Place | iOS | Android now (renders as) | Fix (Material Rounded) |
|---|---|---|---|
| Tab: Home | `house` / `house.fill` when selected (custom `NavBar`) | `house` → `Icons.Outlined.Home` | `home` (FILL 1 when selected) |
| Tab: Grammar | `checklist` / `checklist.checked` | `checkmark.circle` → `CheckCircle` | `checklist` |
| Tab: Library | `brain.head.profile` / `.fill` | `bookmark` → `BookmarkBorder` | `psychology` (or custom) |
| Tab: Settings | `gearshape.2` / `.fill` | `gearshape` → `Settings` | `manufacturing` |
| Home › Vocabulary | `rectangle.stack.fill` | `bookmark.fill` | Phosphor `cards-three` (fill) |
| Home › Grammar | `checklist` | `checkmark.circle.fill` | `checklist` |
| Home › Hören | `ear.badge.waveform` | `play.fill` | `hearing` |
| Home › Spiele | `gamecontroller.fill` | `star.fill` | `sports_esports` FILL 1 |
| Tutor › Gespräch | `bubble.left.and.bubble.right.fill` (Speaking) | `person.fill` | `forum` FILL 1 |
| Tutor › Satz prüfen | `checkmark.bubble` (GermanWriter `.correct`) | `checkmark.circle.fill` | `mark_chat_read` |
| Vocabulary › Karteikarten | `rectangle.stack` | `bookmark.fill` | Phosphor `cards-three` |
| Vocabulary › Wortschatz | `archivebox` ("Wortschatz · Goethe") | `list.bullet` | `inventory_2` |
| Karten: speak button | `speaker.wave.2(.fill)` | `play.fill` | `volume_up` |
| Hören "Anhören", model picker ✓ | `play.fill`, `checkmark` | same | matches already |

The Android swaps were picked from SkipUI's fallback table. With symbolsets shipped (below), the Android
views can use the iOS names directly.

## 6. Recommendation

1. **Default set: Material Symbols Rounded, weight 400, grade 0, FILL 0 or 1 by name.** SF's rounded
   terminals match Rounded best, Outlined and Sharp less so. It covers 403 of 463 names at
   exact or close. Don't use Compose's `material-icons-extended`. SkipUI already pulls it in as an
   `api` dependency for its 150-name fallback, but Google calls that artifact "no longer maintained or
   recommended" (old Material Icons look, slow builds). It is also only reachable from SwiftUI through
   SkipUI's hard-coded switch, so a `"Icons.Rounded.Psychology"` passthrough doesn't work.
2. **About 30 alternates**, mostly **Phosphor** (fill-path SVGs with regular, bold and fill weights,
   which line up with SF's `.fill` pairs). Use Lucide/Tabler only for the exact hits (`book-a`,
   `turtle`, `sparkle`, `circle-dashed`, `message-language`). Those are stroke icons, so convert strokes to
   paths first (`picosvg` or Inkscape `object-stroke-to-path`).
3. **8–10 custom Bauhaus SVGs** (list in §4), drawn as monochrome fill paths in the same template
   format.

### How to ship them: symbolsets in the Android app's asset catalog, with no iOS code change

Confirmed in SkipUI `Image.swift` (`RenderSystem`). `Image(systemName: n)` looks for an **`n.symbolset`
in any `*.xcassets` of the top-level app bundle first**, and only then falls back to the 150-entry Material
table, then to ⚠. It parses SF-template SVGs (`<g id="Symbols">` → `Regular-M`, `Bold-M` …), picks the
variant closest to the current `fontWeight`, and tints it with `foregroundStyle`. Grouped folders work:
`assetContentsURLs` matches `*.xcassets/**/NAME/Contents.json`.

**Google publishes every Material Symbol in exactly that template format:**
`github.com/google/material-design-icons/symbols/ios/<name>/materialsymbolsrounded/<name>_symbol.svg`
plus `<name>_fill1_symbol.svg`. Verified for `memory`: the file holds all 27 groups,
`Ultralight-S` … `Black-L`, which match SkipUI's `SymbolSize` enum.

So the pipeline is:

```
DieKarteiAndroid/Sources/DieKartei/Resources/Module.xcassets/Symbols/
    cpu.symbolset/{Contents.json, cpu.svg}            ← Material "memory" template
    checkmark.circle.fill.symbolset/…                 ← "check_circle" fill1 template
    rectangle.stack.symbolset/…                       ← Phosphor cards-three wrapped in the template
```

- A generator script on the Android branch (e.g. `scripts/android_symbols.py`) reads `icon-map.csv`. For
  each row it fetches the Google template (fill1 for `.fill` names), or wraps the chosen
  Phosphor/Lucide/custom path into the template groups. It then writes `<sf>.symbolset/Contents.json` as
  `{"symbols":[{"filename":"<sf>.svg","idiom":"universal"}],"info":{"author":"xcode","version":1}}`.
- **Strip unused groups.** Each Google template is ~48 KB. Keep the `-M` scale and 3–4 weights (Light,
  Regular, Semibold, Bold), which gets each file to about 10 KB (measured on `memory`: 47.9 → 10.2 KB, keeping the Guides group SkipUI needs for cap height) and the whole set (~440) to about 4.5 MB
  raw, compressed well in the APK.
- **Ship all of them, including the 47 SkipUI already maps.** The symbolset wins over the fallback, so the
  set stays consistently Rounded and `location` stops drawing a pin.
- iOS is untouched. This catalog only exists in the Android package, and on Darwin `Image(systemName:)`
  never consults catalogs. `DieKarteiCore` enums that return `"cpu"` strings keep working on Android
  because the lookup always goes through the app bundle.
- Add a guard script (or a test) that collects every symbol literal from the core files and the Android
  UI module and fails if any name has no symbolset. Otherwise ⚠ only shows up at runtime as the log line
  "Unable to find system image named".

**Variants and weights.** `.fill` is just another name, so ship a `fill1` template under the `.fill`
name. If `.symbolVariant(.fill)` is ever used, SkipUI appends `.fill` to the name, which works the same way.
`.fontWeight(.semibold)` picks `Semibold-M`, the same idea as SF. Multicolour, hierarchical and palette
rendering are not supported: SkipUI fills every path with one tint.

**Effects** (only matters once iOS views are shared). `.symbolEffect(.pulse/.bounce)`,
`.contentTransition(.symbolEffect(.replace))`, `.symbolRenderingMode` and `.imageScale` don't compile under
Skip Fuse; they are `unavailable` or absent. Guard them or route them through no-op shims. Keep the iOS
behaviour identical, as a move rather than a rewrite:

```swift
extension View {
    @ViewBuilder func karteiPulse(isActive: Bool = true) -> some View {
        #if os(Android)
        self.opacity(isActive ? 0.85 : 1)          // or plain `self`
        #else
        self.symbolEffect(.pulse, isActive: isActive)
        #endif
    }
}
```

If code really must pick a different name on Android, keep a single lookup instead of scattering
`#if`s:

```swift
enum KarteiSymbol {
    static func name(_ sf: String) -> String {
        #if os(Android)
        androidOverrides[sf] ?? sf     // e.g. ["square.and.arrow.up": "share-android"]
        #else
        sf
        #endif
    }
}
```

Prefer the symbolset route, though. With it, the SF name works as the asset key on both platforms and
needs no lookup.

### Not verified / open

- No emulator check yet; the worktree is read-only for this audit. Test first: one Google template, one
  Phosphor-wrapped symbol and one `.fill` name in `Module.xcassets`. On the tab bar, check centring and
  size: SkipUI sizes symbolsets from the template's cap-height guides.
- SkipUI fills with the NonZero rule. Spot-check icons with holes (`check_circle` fill1, `settings`) for
  inverted cut-outs.
- Licence notices: add the Apache-2.0 (Material Symbols) and MIT/ISC (Phosphor, Lucide, Tabler) texts to
  the Android Settings › Sources/licences screen.
