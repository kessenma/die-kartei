# Theme Upgrade

Making the app feel like *its own little world* instead of a stock iOS `Form`/`List`, via a
**toggleable app-wide theme system** with **four themes shipped together** — the user switches freely
in Settings, and no direction is a one-way door.

- **Branch:** `theme-upgrade` (off `image-generation`)
- **Design brief (mockups of all four directions + nav redesign):**
  https://claude.ai/code/artifact/75f4feba-4efa-4096-9466-a9e1babb862b
- **Status:** ✅ **Phases 0–11 all done — the theme-upgrade branch is complete.** Every screen wears the
  active theme (System/Soft/Notebook/Bauhaus); der/die/das gender colors are unified via `GenderPalette`;
  Klar stays pixel-identical. Tester asks folded in: 6-tile hub, streak ranges, read-aloud voice nudge,
  model-by-goal. Still open, on the **functional track (§5)**: photo/URL "talk about this" mode, skippable-
  voice chat, and the earlier model/TTS/bug items — all need engine/prompt work + on-device MLX testing.
  Bespoke celebratory motif art (confetti / hand-drawn empty states) is optional future design polish.
- **Related memory:** `playful-ui-theme-initiative`

### How to work this doc

Each **phase** below is a self-contained unit: an objective, the exact files, per-file change notes,
a test step, and a definition of done. **One agent takes one phase at a time**, builds it, verifies
it, checks the boxes, appends to the changelog. Phases are ordered so each builds on the last, but
after Phase 1 any screen phase (6–11) can be done in any order.

**Testing note** (see memory `verification-environment`): the sim can't tap/navigate and can't run
MLX, so per-screen visual checks happen through **SwiftUI `#Preview`s** — every themed screen gets a
preview that loops the four themes. Compile verification is `build_sim`. Ignore SourceKit reindex
noise. Re-read a file before editing it — other agents touch this repo (memory
`concurrent-agents-workflow`).

---

## 1. Why

Almost every screen is a native grouped `Form`/`List` — the same chrome as the iOS Settings app — so
the app disappears into the platform. The only personality today (`ModelTheme`) is borrowed from the
AI vendor's brand, not ours.

**The reframe (from grug's design philosophy):** the lesson isn't "go hand-drawn," it's *commit to one
point of view*. Since we have on-device image generation, the resolution is:

> **Identity lives in the chrome. AI-generated art stays the content, inside themed frames.**

**Not this:** a mascot, a cartoon character, anything that reads as a Duolingo clone.

---

## 2. The four themes (all ship together)

Named in German, because that's free identity. **Every one uses only fonts already on iOS — nothing
to bundle.**

| Key | Picker label | Idea | Display font (iOS built-in) | Ground (light) | Corner | Motif |
|-----|--------------|------|------------------------------|----------------|--------|-------|
| `klar` | **System** | Current look — the baseline | SF (`.system`) | Grouped grey | 10 | none |
| `sanft` | **Soft** | Warm & cozy | SF **Rounded** (`design: .rounded`) | Warm sand `#F1E9DC` | 20 | soft shadow, air |
| `kritzel` | **Notebook** | Hand-drawn scribble | **Noteworthy-Bold** (titles only) | Ruled paper `#FBF9F0` | 4–8 irregular | tilt ±1°, sketch borders |
| `grundform` | **Bauhaus** ⭐ | Geometric, primary-colored | **Futura-CondensedExtraBold** | Warm white `#F3EFE6` | 0 | black rules, geometric icons, UPPERCASE |

⭐ Kyle's favorite; the six-tile hub (Phase 4) is where it shines. But all four are first-class.

**Font PostScript names** (verify on-sim with `UIFont.fontNames(forFamilyName:)` if a name misses):
`Noteworthy-Bold` / `Noteworthy-Light`; fallbacks `BradleyHandITCTT-Bold`, `MarkerFelt-Wide`.
`Futura-CondensedExtraBold` / `Futura-Bold` / `Futura-Medium`. Kritzel & Grundform keep **body text in
SF** — only titles, numbers, and section headers take the custom face, so long German passages stay
legible. (Optional future polish: bundle an OFL face — Caveat/Patrick Hand for Kritzel, Space
Grotesk/Archivo for Grundform. Not required for the toggle.)

### Signature move (theme-independent): der/die/das in color

Color-code grammatical gender **everywhere** it appears — articles, card corners, the article game,
the picker. Classic learner mnemonic = pedagogy wearing a costume. Lives in `GenderPalette`, applied
regardless of the active theme. In **Grundform** these *are* the Bauhaus primaries, so identity and
pedagogy share one palette.

| Gender | Hex | |
|--------|-----|--|
| der (masc.) | `#2F6BFF` | blue |
| die (fem.) | `#E23D4C` | red |
| das (neut.) | `#1FA971` | green |
| plural | `#D9930E` | gold |

---

## 3. Architecture

Sits **beside** `ModelTheme`, never replacing it. `AppTheme` is the app's identity; `ModelTheme` stays
the per-model accent. A theme decides whether to defer its accent to the loaded model (`usesModelAccent`)
or override it.

**Decided:** plain `@AppStorage("app.theme")` + a SwiftUI `Environment` key (mirrors how
`CardImageStyle` already persists). No `@Observable` manager unless a theme later needs runtime state.

### `Models/AppTheme.swift` — the token surface

```swift
enum AppTheme: String, CaseIterable, Identifiable {
    case klar, sanft, kritzel, grundform
    var id: String { rawValue }
    static let defaultsKey = "app.theme"

    var label: String        // "System" / "Soft" / "Notebook" / "Bauhaus"
    var subtitle: String     // one-liner for the picker tile

    // Colors — each resolves light/dark internally (asset-catalog or dynamic UIColor)
    var screenBackground: AnyShapeStyle
    var surface: Color                 // card / row fill
    var cardBorderColor: Color
    var cardBorderWidth: CGFloat
    var cornerRadius: CGFloat
    var cardShadow: (color: Color, radius: CGFloat, y: CGFloat)
    var cardRotation: Angle            // Kritzel tilt; .zero elsewhere

    // Type
    func titleFont(_ size: CGFloat) -> Font     // custom face per theme
    func numberFont(_ size: CGFloat) -> Font    // big streak numbers
    var bodyDesign: Font.Design?                // .rounded for Sanft, nil elsewhere
    var uppercaseSectionHeaders: Bool           // true for Grundform

    // Accent
    var usesModelAccent: Bool
    func accent(model: ModelTheme?) -> Color

    var previewColors: [Color]         // swatch strip for the picker tile
}
```

**Klar returns system-equivalent tokens** (`.clear`/system grouped background, system radius, SF fonts,
no border, no shadow, `.zero` rotation, `usesModelAccent = true`). So on Klar every `.themed*` modifier
is a **no-op** — the invariant that lets us migrate incrementally without regressions.

### `Models/GrammarPalette.swift`

`enum Gender { case der, die, das, plural }` + `static func color(_:) -> Color` with the four hexes
above. Independent of `AppTheme`.

### `Features/Shared/ThemeEnvironment.swift`

- `EnvironmentKey` + `EnvironmentValues.appTheme`.
- `ThemedBackground` view (handles Kritzel's ruled-paper pattern; simple fills otherwise).
- Modifiers, each reading `@Environment(\.appTheme)`:
  - `.themedScreen()` — background + `.tint(theme.accent(model:))`
  - `.themedListScreen()` — the `List`/`Form` form of the above (Phase 2): hides the scroll background so
    the themed ground shows through, except on Klar where that background *is* the ground
  - `.themedCard()` — surface fill, border, corner radius, shadow, rotation (free-standing cards only)
  - `.themedListRow()` — the `List`-row counterpart (Phase 3): swaps the grouped row's system background
    for the theme's surface, one card per row, separator hidden. **A no-op on Klar.**
  - `.themedSectionHeader()` — font + optional uppercase/tracking. **A no-op on Klar** — a grouped `List`
    uppercases headers by default, so overriding `textCase` there would silently regress every screen.
  - `.themedTitle(_ size:)`, `.themedNumber(_ size:)` — `Text` font helpers (unconditional display face)
  - `.themedLabel(_ base: Font, size:)` — **the migration workhorse** (Phase 3). Re-fonts a label that
    already has a font: `base` on Klar and Sanft, the theme's display face on Kritzel and Grundform.
    Sanft is excluded on purpose — it gets its character from `.fontDesign(.rounded)` screen-wide, so
    swapping fonts there would just make it bolder than the baseline, not warmer.

### Extra `AppTheme` tokens added while migrating (Phases 2–3)

- `func innerRadius(_ base: CGFloat) -> CGFloat` — radius for a *small inner shape* (icon chip, stat
  tile, day cell, tab bar, selection pill) whose radius today is `base`. `cornerRadius` is the **card**
  token and swallows small shapes (Sanft's 20 on a 34pt chip is a circle). Klar returns `base`
  untouched, which is the whole trick: an adopting screen is pixel-identical on the baseline theme.
- `var hasDisplayFace: Bool` — Kritzel/Grundform only; backs `.themedLabel`.
- `var pillShape: AnyShape` — `Capsule()`, or `Rectangle()` on Grundform, which has no round corners.

### Wiring (root)

`german_ai_flashcardsApp` (or `ContentView`) reads `@AppStorage(AppTheme.defaultsKey)` and injects
`.environment(\.appTheme, theme)` so every screen can read it.

### Standard migration recipe (referenced by every screen phase)

1. Add `@Environment(\.appTheme) private var theme`.
2. Screen container: `.themedScreen()` (replaces ad-hoc `.background(Color(.systemGroupedBackground))`).
   For a `List`/`Form`, use `.themedListScreen()` instead — it handles the scroll background.
3. `List` rows: `.themedListRow()` on the row or the whole `Section`. Free-standing cards (outside a
   `List`): `.themedCard()`. Don't put `.themedCard()` inside a grouped row — it double-draws.
4. Existing labels: `.themedLabel(<the font it already had>, size:)`. New display type and big numbers:
   `.themedTitle(_)` / `.themedNumber(_)`. Section headers: `.themedSectionHeader()`.
5. Inner shapes (icon chips, tiles, cells): swap the literal radius for `theme.innerRadius(<that same
   literal>)`. Capsules that should square off on Grundform: `theme.pillShape`.
6. Fixed `Color.accentColor` → `.tint` as a `ShapeStyle` (`AnyShapeStyle(.tint)` where the ternary needs
   it). `.themedScreen()` sets the tint, so the accent then tracks the theme *and* the loaded model.
7. Any `der/die/das` text or badge → `Gender.color` / `Gender.symbol`; any Nom/Akk/Dat/Gen label →
   `GrammarCase.color` / `.symbol` (Wechsel: `CasePalette.wechsel`). All in `Models/GrammarPalette.swift`;
   never reuse a gender hue for a case, and don't mark right/wrong in green/red where genders are colored.
8. Add/extend `#Preview` to render the screen across all four themes.
9. `build_sim`; confirm **Klar is pixel-identical to before**; check Grundform + Kritzel dark mode.

**Known limitation — grouped-section corner clip.** SwiftUI clips a grouped `List`/`Form` section
(background *and* content) to a rounded rect whose radius we don't control (~10pt in `List`, ~18pt in
`Form`). A Grundform row therefore gets its square corners cut, leaving an unstroked rounded "ear" at
each outer corner; middle rows of a multi-row section are unaffected, so it only shows on the first/last
row, worst on single-row `Form` sections (Create). Cosmetic only, and every workaround that keeps the
grouped style is worse (matching the clip radius costs Grundform its sharpness everywhere; insetting the
card horizontally narrows it out from under its own text). The real fix is leaving grouped chrome, which
**Phase 4** already does for the biggest list and Phase 10 can do for the settings/Create forms.

---

## 4. Phases

Overview — check off as each completes:

| # | Phase | Files | Visible change on Klar? | Tester ask folded in |
|---|-------|-------|--------------------------|----------------------|
| 0 | ✅ Foundation | 3 new + root wire | none | — |
| 1 | ✅ Settings → grouped list + theme picker | 1 new + shell rewrite | new grouped Settings | houses app-level settings |
| 2 | ✅ App shell | ContentView, NavBar | none | — |
| 3 | ✅ Home · For You | 8 | none | — |
| 4 | ✅ All Activities → 6-tile hub | HomeHubView + 1 new | **new hub grid** | ✅ "6 main cards" |
| 5 | ✅ Streak ranges | StreakCalendarView, WeekInReview | **new range picker** | ✅ week/month/year + range |
| 6 | ✅ Flashcards + gender colors | 12 | **gender colors visible** | ✅ (gender aid) |
| 7 | ✅ Grammar & games | 14 | **gender colors visible** | — |
| 8 | ✅ Stories & reading | 16 | none | ✅ voice discoverability |
| 9 | ✅ Conversation *(theming; 2 tester asks → §5)* | 12 | none | ⏭ photo/URL entry + skippable voice → §5 |
| 10 | ✅ Settings & Model UI | 22 | none | ✅ model-by-goal (live-verified) |
| 11 | ✅ Library, Queue, leaf & polish | 8 + motifs | none | — |

---

### Phase 0 — Foundation *(no visible change)*

**Objective:** the theme system exists and is injected, Klar selected by default, app looks identical.

**Create:**
- [x] `Models/AppTheme.swift` — enum + all tokens for all four themes (values in §2 / §3).
- [x] `Models/GrammarPalette.swift` — `Gender` + `color(_:)`.
- [x] `Features/Shared/ThemeEnvironment.swift` — `EnvironmentKey`, `ThemedBackground`, the `.themed*` modifiers.

**Edit:**
- [x] `App/german_ai_flashcardsApp.swift` — `@AppStorage(AppTheme.defaultsKey) var theme` + `.environment(\.appTheme, theme)` on `ContentView`.

**Test / DoD:** ✅ `build_sim` green (only the pre-existing `WebTextExtractor` warning remains). No screen
adopts the modifiers yet → zero visual diff. Throwaway `#Preview "Theme foundation"` in
`ThemeEnvironment.swift` renders `.themedTitle(28)` / `.themedNumber(40)` + the gender colors across all
four themes (SF · SF-Rounded · Noteworthy · Futura).

**Notes for later phases (decisions made in Phase 0):**
- The `Color(hex:)`, `Color(light:dark:)`, and `UIColor(hexValue:)` inits are marked `nonisolated` so the
  `nonisolated` `AppTheme`/`Gender` enums can build color tokens off the main actor (this module compiles
  with default main-actor isolation). Keep new color helpers `nonisolated` too.
- `GenderPalette` brightens each hex a notch in **dark** mode (legibility, not a theme token) via
  `Color(light:dark:)` — light values are the plan's exact hexes.
- Added a second env key **`\.modelTheme: ModelTheme?`** (default `nil`) that `.themedScreen()` reads to
  resolve Klar's model-deferred tint. **Not wired at the root yet** — Phase 2 (App shell) should inject
  `.environment(\.modelTheme, mlxService.loadedModel?.theme)` so Klar's accent tracks the loaded model.
- `.themedScreen()` also applies `.fontDesign(theme.bodyDesign)` (only Sanft rounds body; `nil` no-op elsewhere).
- `cardRotation` (Kritzel ±1°) and `cornerRadius` jitter (Kritzel 4–8) are single fixed values for now;
  per-card variation is left to the Phase 11 motif pass.

---

### Phase 1 — Settings → grouped list + theme picker *(the toggle + a home for app-level settings)*

**Objective:** replace the four-tab segmented Settings with a native **grouped list** (sections
App / Learning / Model / About, rows that push to detail screens). This gives the homeless app-level
settings a home and lands the theme picker at **App ▸ Appearance**, from which all four themes switch.

**New structure** — root `SettingsView` is one grouped `List`:

- **App** — Appearance (→ `ThemePickerView`), Reminders (→ `ReminderSettingsView`), Voice (→ voice settings)
- **Learning** — Flashcards (→ `CardSettingsView`), Conversation (→ `ConversationSettingsView`), Stories (→ `StorySettingsView`)
- **Model** — Model & Downloads (→ `ModelSettingsView`); keep the download badge on this row
- **About** — Sources & Credits (→ `SourcesView`), Send Feedback (→ `FeedbackSection`)

**Keep the morphing icon header** (Kyle likes it). Extract the current large-title-plus-symbol header
(`SettingsView.swift:38-54`, `.contentTransition(.symbolEffect(.replace))`) into a reusable
`SettingsHeader(icon:title:)`. Use it on the root (gear · "Settings") **and on each pushed section**, so
the icon still reflects the current screen and morphs on appearance — the same look, now driven by
navigation instead of segments.

**Create:**
- [x] `Features/Settings/ThemePickerView.swift` — 4 tappable tiles mirroring `CardStyleCard`
  (`Features/Cards/CardImageStyleSheet.swift:338`): each previews the theme (its `screenBackground`,
  `titleFont` on a sample "Hallo", `previewColors` swatches, accent selection ring), bound to
  `@AppStorage(AppTheme.defaultsKey)`.
- [x] `Features/Shared/SettingsHeader.swift` — the extracted morphing icon header (neutral
  `circle.dotted` → screen icon on appear; carries `listRow*` so it also sits atop the ScrollView picker).

**Edit:**
- [x] `Features/Settings/SettingsView.swift` — rewrote the shell: segmented `selectedTab` → grouped
  `List` (App/Learning/Model/About) + `NavigationLink`s. Preserved `resetToken` pop-to-root and the
  `lastLoadedModel` `onChange`; download badge moved onto the Model row; each Learning/Model destination
  is a thin `Form`-wrapper (`FlashcardsSettingsScreen`/…/`ModelSettingsScreen`, `FeedbackScreen`) with a
  `SettingsHeader`, since those setting bodies emit bare `Section`s.
- [x] Relocated the embedded app-level sections (verified placement first): **Reminders** (was in
  `CardSettingsView`) → App ▸ Reminders (`ReminderSettingsView`); **Pronunciation + Dialogue Voices**
  → new **`VoiceSettingsView`** at App ▸ Voice; **Sources** → About (`SourcesView`); **Feedback** (was in
  `ModelSettingsView`) → About ▸ Send Feedback. Trimmed `CardSettingsView` to Flashcard Style/Haptics/
  Card Matching/Der·Die·Das; added `import UIKit` there (was leaning on AVFoundation's transitive UIKit).

**Test / DoD:** ✅ `build_sim` green; **verified live on the iPhone 17 sim via `agent-device`** (screenshots
in scratchpad): grouped App/Learning/Model/About list with morphing gear header; App ▸ Appearance shows
all four tiles (SF · SF-Rounded · **Noteworthy** · **Futura** all resolving on-device); tapping **Bauhaus**
moves the accent ring + check, the root Appearance row updates to "Bauhaus", and it **persists across a full
relaunch**; Voice screen renders the extracted Pronunciation + Dialogue Voices; Flashcards no longer shows
the relocated rows. Reset to System after testing. Rows are unthemed on Klar (a clean native grouped
Settings) — theming is Phase 10.

---

### Phase 2 — App shell *(no visible change on Klar)* ✅

**Objective:** the root canvas and tab bar read the theme.

- [x] `App/ContentView.swift` — `.themedScreen()` behind the tab content ZStack (one ground behind all
  three tabs, so switching tabs never crossfades the background), plus the deferred Phase 0 wire:
  `.environment(\.modelTheme, coordinator.mlxService.loadedModel?.theme)` published for the whole app.
- [x] `App/NavBar.swift` — reads `\.appTheme`. Klar keeps the frosted `.ultraThinMaterial` pill,
  20pt radius, and SwiftUI's default `.shadow(radius: 10)` (spelled out literally as
  `Color(.sRGBLinear, white: 0, opacity: 0.33)` so it renders identically); the identity themes take
  `theme.surface` + their border and `cardShadow` (Grundform: flat, sharp, black-ruled). Geometry via
  `innerRadius(20)` for the bar and `innerRadius(12)` for the selection pill. Tint is now
  `theme.accent(model:)`; `selectedTabFill` keeps the model's brand gradient only when the theme defers
  to it (`usesModelAccent`). Grundform sets its labels in condensed Futura caps. `DownloadBadge` and
  `GeneratingBadge` logic untouched — the badge just draws in `.tint` instead of a fixed accent.
- [x] `#Preview "NavBar · four themes"` — the bar over each ground with both badges showing.

**Test / DoD:** ✅ `build_sim` green. Verified on the iPhone 17 sim (agent-device): the bar restyles per
theme — frosted pill on System, terracotta on Soft, ink-lined on Notebook, sharp black-ruled block with
Futura caps on Bauhaus — and Klar is unchanged (see the Phase 3 pixel diff, which covers the bar).

**Note (deliberate, from the Phase 0 design):** with `\.modelTheme` now injected at the root, Klar's
accent tracks the **loaded model** wherever a screen uses `.tint` — the ring on today's calendar cell,
icon chips, selection checkmarks. That's `usesModelAccent` working as specified, not a regression; with
no model loaded (the sim, which can't run MLX) it resolves to the system accent, i.e. today's look.

---

### Phase 3 — Home · "For You" *(the everyday screen)* ✅

**Objective:** the highest-traffic screen carries each theme's identity.

Applied the **standard recipe** to:
- [x] `Home/HomeHubView.swift` — `.themedListScreen()`; all six All-Activities sections take
  `.themedSectionHeader()` + `.themedListRow()` (the grid itself is still Phase 4); `hubRow`'s icon chip
  moves to `.tint` + `innerRadius(8)`, its title to `.themedLabel`. Five `#Preview`s (four themes + a
  Bauhaus dark).
- [x] `Home/TodayView.swift` — hero + plan sections `.themedListRow()`, header `.themedSectionHeader()`;
  `TodayHeroRow`'s Start affordance uses `theme.pillShape` (a block on Grundform) and uppercases there.
  `rec.accent` is left alone on purpose — it's **content** (which kind of exercise this is), so the theme
  reshapes the chip without recoloring it.
- [x] `Home/StreakCalendarView.swift` — section + day-detail sheet themed; week/month/heatmap cells and
  the today ring all take `innerRadius`, so **Grundform gets square cells**; the ring and the heatmap's
  today border draw in `.tint`. *(Kritzel's hand-circled days deferred to the Phase 11 motif pass.)*
- [x] `Home/WeekInReviewSection.swift` — themed section header + rows; `StatTile` keeps its per-figure
  tint wash but takes the theme's geometry and gains the border (invisible on Klar, `lineWidth: 0`).
- [x] `Home/CardSelectionView.swift` — themed list + rows, `.tint` checkmarks, `pillShape` word-type
  chip, themed thumbnail frame (**chrome-vs-content: the picture itself is untouched**). Four previews.
- [x] `Home/GeneratingFlashcardsView.swift` — overlay paints `ThemedBackground` off Klar; the
  `AnimatedCardStack`'s blank cards draw on `theme.surface` so the placeholder deck matches the real one.
  Four previews.
- [x] `Home/FlashcardTopicBrowseSheet.swift` — themed list/rows. **Dropped its `accent:` parameter** —
  the tint now comes from the environment, which resolves the same model accent on Klar.
- [x] `Home/HomeView.swift` — the Create `Form` themed; `.tint(activeTheme?.accent)` replaced by
  `.themedListScreen()`; suggestion chips take `pillShape`. **The `ModelTheme` generate-button gradient
  is kept** exactly as-is; only its no-model fallback moved from `secondarySystemGroupedBackground` to
  `theme.surface`.

**Test / DoD:** ✅ `build_sim` green (only the pre-existing `WebTextExtractor` warning). Verified live on
the iPhone 17 sim via agent-device across all four themes, light **and** dark:
- **Klar is pixel-identical** — a full-screen diff of For-You before/after the phase shows 312 of
  3,162,132 pixels differing (0.0099%), *all* of them in rows y 78–118, i.e. the status-bar battery
  indicator. Zero app pixels changed.
- **Bauhaus:** warm-white ground, Futura UPPERCASE tracked headers, black-ruled cards, square day cells,
  square blue icon chips, sharp nav bar with a solid blue selection block, blocky uppercase START.
- **Notebook:** ruled paper with the red margin, **continuous across the whole screen** — the app shell's
  ground and the screen's own no longer double up (see the `RuledPaperOverlay` fix below), Noteworthy
  numerals, ink borders, ballpoint-blue ring.
- **Soft:** warm sand ground, cream 20pt cards with the cozy lift, terracotta accent throughout.
- **Dark:** Bauhaus inverts to near-black with light rules; Notebook keeps legible paper + ink.

**Two fixes the on-sim pass forced (both in `ThemeEnvironment.swift`, both benefit every later phase):**
- `RuledPaperOverlay` now phases its rules to the **screen** (`geo.frame(in: .global)`) rather than its
  own frame. Two stacked grounds — the shell's and a screen's — were drawing offset rulings that
  compounded into a darker, denser paper wherever they overlapped.
- `.themedListRow()` hides the system separator and insets each row 2pt vertically. Without it a hairline
  drew straight across the gap between two rounded Soft cards, and Kritzel/Grundform rows fused their
  borders into doubled rules. Each row now reads as its own card.

---

### Phase 4 — All Activities → six-tile hub *(tester ask: "6 main cards")* ✅

**Objective:** replace the long scrolling `List` with a 6-tile category grid → sub-page → tool. The six
tiles map 1:1 to `HomeHubView`'s existing sections (Vocabulary, Grammar, Reading, Speaking, Listening,
Batch), so this promotes each section header to a tile and pushes its rows down one level (hub-and-spoke,
already named in the file's own comments).

- [x] `Home/HomeHubView.swift` — the `showAllActivities` branch is now a `ScrollView` + `LazyVGrid` of
  six `ActivityCategoryTile`s, each pushing to `ActivityCategoryView`. The two modes are separate
  subtrees (`activityHub` / `forYouList`) sharing one `modePicker`, which is inset 20pt to match the
  grouped-`List` section margin so it doesn't shift when you switch modes. All thirteen rows and the four
  `router` launch helpers moved out of this file.
- [x] **`Home/ActivityCategoryView.swift` (new)** — `ActivityCategory` (title, subtitle, SF Symbol,
  Grundform glyph, tint), the category page, `ActivityRow` (the old `hubRow`), and `ActivityCategoryTile`.
  The page owns the launch helpers now, so it reaches `ActivityRouter`/`DeckStore` from the environment
  and needs nothing threaded down but `onGenerationComplete`.
- **Category colors reuse the app's existing activity language** (blue = cards, purple = grammar,
  pink = reading, green = conversation, orange = listening, indigo = batch — the same assignments
  `DayDetailSheet` already uses), so a category reads the same wherever it's met. Like `rec.accent` on
  the Today hero, they're *content*: the theme reshapes a tile without recoloring it.

**Test / DoD:** ✅ `build_sim` green. Verified on the iPhone 17 sim: **all six tiles fit on one screen
above the tab bar with no scrolling** (thirteen rows → six tiles, which was the tester's complaint), each
opens its category, and Vocabulary still lists all five of its tools — nothing lost. Grundform draws the
geometric marks in solid color blocks with Futura caps. Five `#Preview`s of the grid (four themes + dark)
plus three of the category page.

**Follow-up (2026-08-14) — no category page for a category of one.** Speaking, Listening, and Batch hold
exactly one tool each, so their sub-page was a list with a single row in it. Tiles now push through
`ActivityCategoryDestination`, which sends the three multi-tool categories to `ActivityCategoryView` and
the other three straight to their tool (`ConversationListView` / `PhraseLibraryView` / `BatchQueueView`,
each of which already carries its own nav title). Vocabulary, Grammar, and Reading are unchanged.

**Bonus, and the reason to do this phase before the remaining form-heavy ones:** stepping outside grouped
chrome means the §3 corner-clip limitation doesn't apply here — **Grundform's tiles are genuinely square**,
which the Bauhaus screenshot confirms. That's the pattern to reach for wherever a screen can afford it.

**Note:** Speaking, Listening, and Batch hold one tool each today, so their category page is a single row.
Kept for predictability (every tile behaves the same) and because those categories are where new tools
will land; Conversation stays one tap away via the For-You plan regardless.

---

### Phase 5 — Streak ranges *(tester ask: week/month/year + custom range)* ✅

**Objective:** range control over the streak calendar and a from–until picker on the review section.

- [x] `Home/StreakCalendarView.swift` — **already shipped** (found in place during Phase 3): `StreakRange`
  (Week / Month / 3 Mo / Year) drives a paged week strip, month grid, and two heatmap widths, with an
  Items/Time shading switch and a per-range time summary.
- [x] `Services/WeekInReviewService.swift` — generalized. The rolling-7-day `summary(days:conversations:asOf:)`
  now delegates to a new `summary(days:conversations:from:to:periodLabel:)` over any half-open window,
  compared against the window of the **same length** immediately before it. `WeekInReview` gained
  `dayCount` and `periodLabel`, both defaulted, so nothing else had to change.
- [x] `Home/WeekInReviewSection.swift` — a collapsed "Date range" row expands to From/Until `DatePicker`s
  plus a "Back to this week" reset. Picking either date clamps the other and flips the section onto the
  custom window. **Everything that names the range follows it**: the header ("This Week" → "Jul 1 – Jul 27"),
  the footer ("Your last 7 days versus the 7 before" → "These 27 days versus the 27 before them"), the
  Active-days tile ("of 7" → "of 27"), and `headline`'s prose (which is why `periodLabel` lives on the
  struct — a summary can't claim "this week" about a window that isn't one).
- **Not persisted, deliberately:** a custom range is a "let me go look at something" action, and the
  honest default to return to is always this week. Also, the section now shows even when a custom range
  is empty — otherwise it would vanish the moment you looked at a quiet stretch, which reads as a bug.

**Test / DoD:** ✅ `build_sim` green. Verified live on the sim rather than by preview: the fresh simulator
had no study history, so the section was correctly hidden — **seeded real data by running the bundled
"Akkusativ: Negation" drill** (2 questions, no MLX needed), after which the section appeared with
Active days 1 of 7 (+1) and Grammar drills 2 (+2). Setting From to Jul 1 then retitled the header to
"JUL 1 – JUL 27", changed the tile to "of 27", re-queried the stats, adapted the footer to "These 27 days
versus the 27 before them", and revealed the reset button. Screenshots in the session scratchpad.

---

### Phase 6 — Flashcards + gender colors *(gender colors go live)*

**Objective:** the flashcard player wears the theme; **der/die/das gets colored** on cards.

Standard recipe, plus `GenderPalette` on any article/gender UI:
- [x] `Cards/CardDeck/CardDeckView.swift` (themed ground for non-Klar behind the whole player; Klar keeps its exact system bg) · [x] `Cards/FlashCardView.swift` (**gender color** on the article via `Text.gendered`, a slim gender corner tab, gender-badge glyph; surface/stroke/radius theme-aware; + 4-theme `#Preview`)
- [x] `Cards/FullscreenCardView.swift` (themed ground, non-Klar) · [x] `Cards/FullScreenImageView.swift` (photo lightbox — stays on black by design; chrome-vs-content) · [x] `Cards/CardImageStyleSheet.swift` (`.themedListScreen()`)
- [x] `Cards/CorrectionSheetView.swift` (`.themedListScreen()` **+ gender colors → GenderPalette**, was blue/pink/purple) · [x] `Cards/FlashcardPreviewOptionsView.swift` (`.themedListScreen()`) · [x] `Cards/IllustratingDeckView.swift` (themed ground, non-Klar; keeps model brand accent)
- [x] `Cards/ValidationBadgeView.swift` (status badge, not gender — no change needed) · [x] `Cards/ValidationInfoSheet.swift` (`.themedListScreen()`) · [x] `Cards/ValidationReviewView.swift` (`.themedListScreen()` **+ shared `ArticleStyle.color` → GenderPalette**, the canonical der/die/das helper)
- [x] `Cloze/ClozePracticeView.swift` (`.themedCard()`)

**Note (chrome-vs-content):** the AI card image renders unchanged inside a **themed frame** — themed
border/corner/shadow, never a filter on the picture itself.

**Test / DoD:** ✅ `build_sim` green (only the pre-existing `WebTextExtractor` warning). 4-theme `#Preview`
`"Gender colors · 4 themes"` in `FlashCardView.swift` renders a noun per theme with der=blue / die=red /
das=green. The gender palette is now consistent across the card, the correction sheet, and the validation
review (all route through `GenderPalette`). On-device flashcard walk deferred (no saved decks in-sim +
generation needs MLX) — Kyle will UI-test once the screen phases land; the themed NavBar/ground confirm
the theme applies app-wide.

---

### Phase 7 — Grammar & games *(gender colors continue)*

Standard recipe; `GenderPalette` throughout the article game.
- [x] `Grammar/GrammarHubView.swift` (List; `.themedListScreen/Row/SectionHeader`, `innerRadius` chips, `.tint` fills, 4-theme `#Preview`) · [x] `Grammar/GrammarCategoryDetailView.swift` · [x] `Grammar/GrammarMultipleChoiceView.swift` (non-Klar ground; `innerRadius` cards/buttons; gender badge → `pillShape`)
- [x] `Grammar/GrammarLessonSheet.swift` (non-Klar ground) · [x] `Grammar/AIGrammarCreateView.swift` (Form `.themedListScreen/Row/SectionHeader`; topic chip → `pillShape` + `.tint`; since deleted)
- [x] `Grammar/ArticleGame/ArticleGameSetupView.swift` (`.themedListScreen/Row`, `innerRadius` chip) · [x] `Grammar/ArticleGame/ArticleGameView.swift` (**gender colors already `GenderPalette` via `GermanArticle.color`**; themed ground + tint on progress/Weiter, hero noun via `.themedLabel`, 4-theme `#Preview`) · [x] `Grammar/ArticleGame/ArticleRulesSheet.swift` (`.themedListScreen/Row`)
- [x] `Matching/MatchingDeckPickerView.swift` (List recipe + `innerRadius` chip) · [x] `Matching/MatchingGameView.swift` (non-Klar ground; **German tiles → `Text.gendered`**; `innerRadius` tiles; 4-theme `#Preview`) · [x] `Matching/TrickyPairsView.swift` (`Text.gendered` on the pair line)
- [x] `PastTense/PastTenseLevelView.swift` (List recipe; sein/haben badges → `pillShape`, colors kept — auxiliary code, not gender) · [x] `PastTense/SeinHabenGuideView.swift` · [x] `A1/A1VocabView.swift` (**gender fix: `die`=.pink → `GenderPalette` red**; List recipe; badges → `pillShape`)

**Test / DoD:** ✅ `build_sim` green (only the pre-existing `WebTextExtractor` warning). 4-theme `#Preview`s on
**GrammarHub** and the **ArticleGame** (plus Matching + PastTense). Gender coloring is consistent with Phase 6
everywhere — the ArticleGame was already on `GenderPalette` (`GermanArticle.color = gender.color`), and the
one stray old palette (A1Vocab `die`=pink) is fixed; grammar word-type/auxiliary colors (verb=green,
sein/haben) are intentionally left, they aren't der/die/das. Done as 1 self + 2 parallel subagents; on-device
UI check deferred to Kyle per the Phase 6 note.

---

### Phase 8 — Stories & reading *(tester ask: voice discoverability)*

Standard recipe.
- [x] `Stories/StoryListView.swift` (List recipe; CEFR chip → `pillShape`; 4-theme `#Preview`) · [x] `Stories/StorySetupView.swift` (Form recipe; hero/generate brand-gradient rows kept; `.tint(appTheme.accent(model: theme))` innermost so Klar keeps hero brand) · [x] `Stories/StoryDetailView.swift` (List recipe; genre pill → `pillShape`; brand rows kept; 4-theme `#Preview`)
- [x] `Stories/StoryReadAloudView.swift` — themed ground + voice sheet, **and the tester ask: a one-time popover on first playback pointing at the (already-present) voice button** (`@AppStorage readAloud.seenVoiceTip`)
- [x] `Stories/StoryQuizView.swift` (non-Klar ground; `innerRadius` cards/buttons; 4-theme `#Preview`) · [x] `Stories/StoryStyleSheet.swift` (non-Klar ground; StyleCard `innerRadius` + `.themedLabel`) · [x] `Stories/StoryIllustrationView.swift` (image *tile* → `innerRadius` only, no ground by design)
- [x] `Stories/StoryStarterBrowseSheet.swift` (List recipe) · [x] `Stories/GeneratingStoryView.swift` (conditional ground) · [x] `Stories/GeneratingStoryAnimations.swift` (**unchanged — pure animation, no screen/card chrome**) · [x] `Stories/DialogueVoicesInfoSheet.swift` (`.themedListScreen/Row`)
- [x] `Paper/PaperListView.swift` (List + nested URLImport/Generating; 4-theme `#Preview`) · [x] `Paper/PaperDetailView.swift` (List recipe; brand accent wash kept; nested Source/Deck-gen grounds) · [x] `Paper/ExtractedTextReviewView.swift` (Form recipe; word chip → `pillShape`) · [x] `Paper/WebClipperView.swift` (non-Klar ground; WKWebView stays opaque)
- [x] `PhotoScan/PhotoScanListView.swift` (List recipe; nested Generating ground; 4-theme `#Preview`)

**Test / DoD:** ✅ `build_sim` green (only the pre-existing `WebTextExtractor` warning), first integrated try.
4-theme `#Preview`s on StoryList, StoryDetail, StoryQuiz, Papers, PhotoScans. Voice picker is reachable from
playback (it already was, in the transport bar) **and now surfaced once on first play**. Ran as 2 self-files +
**3 parallel subagents** on disjoint sets; brand-gradient/accent rows treated as content (chrome-vs-content);
`GeneratingStoryAnimations` correctly left as pure animation. On-device UI check deferred to Kyle per prior note.

---

### Phase 9 — Conversation *(tester asks: photo/URL entry, skippable voice)*

Standard recipe. **Theming done; the two tester asks moved to the functional track (§5) — see note.**
- [x] `Conversation/ConversationListView.swift` (List recipe; row chips → `innerRadius`; 4-theme `#Preview`)
- [x] `Conversation/ConversationSetupView.swift` — themed (Form recipe). ⚠️ **Tester asks NOT done here — deferred to §5:** a general photo/URL "talk about this" mode and a skippable/text-input voice path both need `ConversationMode`/`ConversationConfig`/engine/prompt changes + a chat text-input pipeline + on-device (MLX) testing — i.e. functional work a theming pass can't validate. (Note: a URL/paste entry already exists, but only inside **Interview** mode for job postings.)
- [x] `Conversation/ConversationView.swift` (non-Klar ground; 16 bubble/card `innerRadius`/`pillShape`; `modelBubble` extension → `ViewModifier` so it can read `\.appTheme`) · [x] `Conversation/ConversationComponents.swift` (**no change** — shared `Section` components, host themes them via `.themedListRow()`) · [x] `Conversation/ConversationSummaryView.swift` (List recipe; `FlowChips` → `pillShape`)
- [x] `Conversation/ConversationPhrasePreviewView.swift` · [x] `Conversation/PhraseLibraryView.swift` (List + `AddEditPhraseSheet` Form; status/scenario chips → `pillShape`; innermost tint) · [x] `Conversation/PhraseToDeckSheet.swift`
- [x] `Conversation/ReviewDeckView.swift` · [x] `Conversation/SayItView.swift` · [x] `Conversation/ScenarioPickerView.swift` · [x] `Conversation/TappableText.swift` (**no change** — pure text)

**Test / DoD:** ✅ `build_sim` green (only the pre-existing `WebTextExtractor` warning), first integrated try.
Conversation setup + chat themed across 4 themes; 4-theme `#Preview` on ConversationList. Ran as 1 self-file +
**3 parallel subagents**. **Photo/URL "talk about this" entry and skippable-voice remain open on the functional
track (§5)** — they're features, not chrome. On-device UI check deferred to Kyle per prior note.

---

### Phase 10 — Settings & Model UI *(tester ask: model-by-goal)*

Standard recipe.
- [x] `Settings/SettingsView.swift` (root list `.themedListScreen/Row`; the 5 wrapper Forms → `.themedListScreen()`) · [x] `Settings/CardSettingsView.swift` · [x] `Settings/ConversationSettingsView.swift` · [x] `Settings/StorySettingsView.swift` (section-emitters → `.themedListRow/SectionHeader`)
- [x] `Settings/ModelSettingsView.swift` — **"Pick by goal" section added** (Best German / Fastest / Fits my device / Longest stories) → `modelForGoal(_:)` resolves over `recommendedOrder(ramGB:)` (max `germanQualityScore` / min `parameterCountValue` / `recommended` / max params) → one tap calls the existing `requestLoad` (keeps the too-big check). Spec cards stay below. Themed + `tagLabel` pill → `pillShape`.
- [x] `Settings/ModelGuideSheet.swift` · [x] `Settings/ReminderSettingsView.swift` · [x] `Settings/CoachNotesView.swift` (+`MemoryArchiveView`) · [x] `Settings/DrillDeckView.swift`
- [x] `Settings/FeedbackSection.swift` · [x] `Settings/ImageGenerationSection.swift` · [x] `Settings/SourcesView.swift` · [x] `Settings/StoryProgressView.swift` · [x] `Settings/DialogueVoicePickerSection.swift`
- [x] `ModelPickerButton.swift` (+ sheet; hero "Recommended" row left unthemed so its brand highlight survives) · [x] `ModelGradientHero.swift` (**unchanged — pure brand mesh/logo**) · [x] `ModelInfoSheet.swift` (**unchanged — brand gradient sheet**) · [x] `ModelEmphasisUI.swift` (badge → `pillShape`) · [x] `ModelLoadingIndicator.swift` (**unchanged — brand loading mark**) · [x] `ModelLoadingPanel.swift` (**unchanged — no surface**) · [x] `ImageModelInfoSheet.swift` (**unchanged — brand gradient sheet**)
- [x] `Onboarding/HeroModelIntroSheet.swift` (info card → `innerRadius`; brand gradient ground kept)

**Test / DoD:** ✅ `build_sim` green (only the pre-existing `WebTextExtractor` warning), first integrated try.
**Verified live on the iPhone 17 sim via `agent-device`:** Settings ▸ Model wears the theme (screenshot on
Notebook — ruled-paper ground, bordered row cards, morphing cpu header) and the **"Pick by goal" section
resolves correctly** — Best German → *Gemma 4 E4B German Tutor*, Fastest → *Apple Intelligence*, Fits my
device → *Gemma 4 E4B German Tutor*. Ran as 2 self-files + **3 parallel subagents**; 5 pure-brand Model
components correctly needed no change (gradients/glows/logos = content).

---

### Phase 11 — Library, Queue, leaf & polish

Standard recipe + motif pass (Kritzel tilt/squiggle, Grundform geometric dividers, empty-state art).
- [x] `Library/UnifiedLibraryView.swift` (decks/reading Lists + `DeckStatsSheet` themed)
- [x] `Queue/BatchQueueView.swift` · [x] `Queue/BatchPlannerSheet.swift` · [x] `Queue/QueueJobSheets.swift` (List/Form recipe; job-card chips → `innerRadius`; status glyphs = content)
- [x] `Shared/WordInspector.swift` (non-Klar ground) · [x] `Shared/GestureHelpSheet.swift` (non-Klar ground; demo card → `innerRadius`) · [x] `Shared/MemoryPressureBanner.swift` (banner card → `innerRadius`) · [x] `Shared/SelectableGermanText.swift` (**unchanged — pure `UITextView` text, like TappableText**)
- [x] Motif pass — **the mechanical motifs ship via the token system** (Kritzel card tilt `cardRotation` + ruled-paper ground; Grundform square corners + 2pt black rules + UPPERCASE headers via `uppercaseSectionHeaders`; Sanft rounded warmth), applied everywhere the recipe touched. **Bespoke celebratory art** (confetti on completion screens, hand-drawn per-theme empty-state illustrations) is logged as **optional future design polish** — a creative-artist task, not mechanical; the baseline is clean and consistent without it.

**Test / DoD:** ✅ `build_sim` green (only the pre-existing `WebTextExtractor` warning), first integrated try.
Nothing left on stock chrome — every screen reads its theme. `SelectableGermanText` (pure text) correctly
needed no change. Ran as 1 self-file + **2 parallel subagents**. On-device 4-theme walk deferred to Kyle.

---

## 5. Functional / model / bug track *(NOT this branch)*

Logged from tester feedback so they don't get lost; handled separately from the theme work.
- [ ] Story TTS sounds "too AI" — warmer voices *(model/TTS)*
- [ ] Story text wants more expressive writing *(prompt)*
- [ ] A1 job-interview grammar too hard — level calibration *(prompt)*
- [ ] Paragraph gen + photo scan felt slow *(perf)*
- [ ] Crash switching to A1; crash on first job-interview start *(bug)*
- [ ] **Photo/URL "talk about this" conversation entry** *(feature; moved here from Phase 9)* — a general
  mode to chat about a scanned photo / pasted text / URL. Needs a new `ConversationMode`,
  `ConversationConfig.topicContext`, an engine/prompt path for discussing arbitrary content, and a source
  picker (reuse `WebTextExtractor` + `StudyPaper` extracted text). Today only **Interview** mode takes a
  URL/paste (job-posting-specific). Needs on-device MLX testing.
- [ ] **Skippable / text-input voice in the chat** *(feature; moved here from Phase 9)* — `ConversationView`
  is mic-driven with no typing fallback; add a keyboard path so a learner can respond without speaking
  (route typed text through the same reply pipeline as recognized speech). `SayItView` already does
  type-or-speak; the main chat does not.

**Working well — leave alone:** flashcards (images, German quality, UX), double-tap words, saved
phrases, response hints, Library, Settings tabs.

---

## 6. Decisions & open questions

- **Q1 — all four ship together?** ✅ Yes (this revision). Klar is the untouched baseline; the picker
  offers System / Soft / Notebook / Bauhaus from Phase 1.
- **Q2 — state approach?** ✅ `@AppStorage` + `Environment`, no manager object.
- **Q3 — theme-picker placement?** ✅ **Decided: grouped-list Settings.** Segmented tabs → sections
  App / Learning / Model / About with rows that push to detail. Theme picker lives at **App ▸ Appearance**.
  Restructure is **Phase 1**; the morphing icon header is preserved via a reusable `SettingsHeader` used
  on every settings screen.
- **Q4 — default theme?** Klar, so shipping the scaffold is a no-op until the user opts in. Consider
  first-run nudge to Bauhaus later. *Open.*
- **Q5 — per-theme dark mode:** each theme defines its own dark tokens; don't naively invert.
- **Q6 — bundle a signature font later?** Optional polish only; the four themes ship on iOS built-ins.

---

## 7. Changelog

- **2026-07-27** — Branch `theme-upgrade` created; design brief published; doc written, then revised to
  ship all four themes together (no bundled fonts; Klar = no-op baseline) with granular per-file phases
  0–11 for one-agent-per-phase execution. Foundation not yet started.
- **2026-07-27 (later)** — Settings IA decided: **grouped list** (App/Learning/Model/About), theme picker
  at App ▸ Appearance, morphing icon header kept via a reusable `SettingsHeader`. Folded into Phase 1
  (was "theme picker in Settings"); Phase 10 now just themes the already-restructured screens.
- **2026-07-27 (later still)** — **Phase 0 shipped.** Created `Models/AppTheme.swift` (all four themes'
  tokens), `Models/GrammarPalette.swift` (`Gender` + `color(_:)`, dark-brightened), and
  `Features/Shared/ThemeEnvironment.swift` (`\.appTheme` + `\.modelTheme` env keys, `ThemedBackground`
  with Kritzel ruled-paper, and the `.themedScreen/.themedCard/.themedSectionHeader/.themedTitle/.themedNumber`
  modifiers). Wired `@AppStorage(AppTheme.defaultsKey)` + `.environment(\.appTheme,)` at the app root
  (`german_ai_flashcardsApp`). Marked `Color(hex:)`/`Color(light:dark:)` `nonisolated`. `build_sim` green,
  zero visual diff on Klar. `\.modelTheme` root injection deferred to Phase 2 (see Phase 0 notes).
- **2026-07-27 (Phase 1)** — **Grouped Settings + theme picker shipped.** New `SettingsHeader` (morphing
  icon, reused on root + every pushed screen), new `ThemePickerView` (4 tiles at App ▸ Appearance), new
  `VoiceSettingsView`. Rewrote `SettingsView` from segmented tabs into a grouped App/Learning/Model/About
  `List`; relocated Reminders/Voice/Sources out of `CardSettingsView` and Feedback out of
  `ModelSettingsView`. **Verified on the iPhone 17 sim with `agent-device`** (install → open → snapshot →
  press → screenshot): all four theme tiles render with their real faces, selection persists across a full
  relaunch, relocated screens intact. Also establishes agent-device as a working on-sim tap/screenshot
  harness for the visual phases ahead (see memory `verification-environment`).
- **2026-07-27 (Phases 2 + 3)** — **App shell + Home · For You themed.** `ContentView` paints one themed
  ground behind all three tabs and publishes `\.modelTheme` app-wide (the wire Phase 0 deferred);
  `NavBar` restyles its surface, geometry, tint, and Grundform label face while keeping Klar's frosted
  pill byte-for-byte. All eight Home files migrated, with 4-theme previews on the hub, the card-selection
  sheet, and the generating overlay. Three reusable modifiers were added on the way —
  `.themedListScreen()`, `.themedListRow()`, `.themedLabel(_:size:)` — plus three `AppTheme` tokens
  (`innerRadius(_:)`, `hasDisplayFace`, `pillShape`); `.themedSectionHeader()` was corrected to be a true
  no-op on Klar (it was un-uppercasing grouped headers). **Verified on the iPhone 17 sim across four
  themes in light and dark; Klar confirmed pixel-identical by full-screen diff (0.0099% differing, all
  status-bar battery).** On-sim testing forced two fixes: screen-anchored ruled paper (Kritzel grounds
  were doubling) and per-row separators/insets (rows were fusing). Phase 5's calendar half was found
  already implemented. One cosmetic limitation logged: SwiftUI's grouped-section corner clip rounds
  Grundform's outer row corners — see "Known limitation" in §3.
- **2026-07-27 (Phases 4 + 5)** — **Six-tile hub + review date range.** All Activities is now a
  `ScrollView` + `LazyVGrid` of six category tiles (new `Features/Home/ActivityCategoryView.swift` holds
  `ActivityCategory`, the category page, `ActivityRow`, and the tile); thirteen rows moved down one
  level, all six tiles fit on one screen with no scrolling, and nothing was lost. Because the grid isn't
  grouped chrome, **Grundform's tiles are genuinely square** — the §3 clip limitation doesn't reach them.
  `WeekInReviewService` was generalized to any half-open window compared against the equally long one
  before it (`dayCount` + `periodLabel` on `WeekInReview`), and the section gained a From/Until picker
  that retitles the header, footer, tile detail, and headline together. **Verified on-sim by seeding real
  study data through the bundled Akkusativ drill** rather than by preview, since a fresh simulator has no
  history and the section correctly hides itself when there's nothing to review.
- **2026-07-27 (Phase 6)** — **Flashcards + gender colors go live.** Picked up a second agent's partial
  work (which had already done the hard part — `FlashCardView`: `Text.gendered` article coloring, the slim
  leading gender tab, gender-badge glyph, theme-aware surface/stroke/radius — plus `.themedListScreen()` on
  the card sheets) and finished the phase: themed grounds behind the whole player (`CardDeckView`),
  `FullscreenCardView`, and the illustrating overlay (each **non-Klar only**, so the baseline is untouched);
  a 4-theme `#Preview` on `FlashCardView`; and — the key correctness fix — **unified the der/die/das palette**
  by routing `CorrectionSheetView.genderInfo` and the shared `ArticleStyle.color` (ValidationReview) through
  `GenderPalette` (was blue/pink/purple, a second conflicting gender code). `FullScreenImageView` left on
  black by design (photo lightbox); `ValidationBadgeView` is a status badge, not gender. `build_sim` green.
  On-device flashcard walk deferred at Kyle's call (no in-sim decks + MLX gen unavailable); themed NavBar/
  ground confirmed the theme applies app-wide.
- **2026-07-27 (Phase 7)** — **Grammar & games themed; gender colors continue.** All 14 files migrated —
  run as one self-owned slice (the ArticleGame trio) + **two parallel subagents** (Grammar; Matching/
  PastTense/A1), disjoint file sets, one integrated `build_sim` at the end (green). List/Form screens took
  `.themedListScreen/.themedListRow/.themedSectionHeader`; `ScrollView`/`NavigationStack` screens with no
  explicit ground took a **non-Klar-only** `ThemedBackground`; icon chips/tiles → `innerRadius`, capsule
  badges → `pillShape`. Gender: the **ArticleGame was already on `GenderPalette`** (`GermanArticle.color =
  gender.color`), so only theming was needed there (ground, `.tint` progress/Weiter, `.themedLabel` hero
  noun, 4-theme `#Preview`); `MatchingGameView`/`TrickyPairsView` now color German tiles/pairs via
  `Text.gendered`; and the one remaining stray palette — `A1VocabView` `die`=.pink — was fixed to
  `GenderPalette` red. Left intentionally: grammar word-type colors (verb=green/noun=orange) and PastTense
  sein/haben auxiliary green/blue — those aren't der/die/das. Also swapped one deprecated `Text + Text`
  (`TrickyPairsView`) for an HStack. 4-theme `#Preview`s on GrammarHub, ArticleGame, Matching, PastTense.
- **2026-07-28 (Phase 8)** — **Stories & reading themed; tester voice ask done.** All 16 files — run as 2
  self-files + **3 parallel subagents** (Stories create/detail; Stories quiz/generating; Paper/PhotoScan),
  disjoint sets, one integrated `build_sim` (green, first try). Same recipe (List/Form → themed list
  modifiers; ScrollView/NavigationStack with no ground → non-Klar `ThemedBackground`; `innerRadius`/
  `pillShape` on chips/tiles/pills). **Chrome-vs-content judgment held up well:** brand-gradient rows
  (StorySetup hero/generate, StoryDetail question row, Paper accent wash) were kept as content, and
  `GeneratingStoryAnimations` (690 lines of pure animation) was correctly left untouched. Tint on the
  brand screens uses `.tint(appTheme.accent(model: theme))` placed innermost, so Klar keeps the hero-model
  accent while identity themes assert their own. **Tester ask (voice discoverability):** the read-aloud
  view already had a voice button in the transport bar; added a **one-time popover on first playback**
  (`@AppStorage readAloud.seenVoiceTip`) pointing at it, with a "Choose a voice" shortcut. 4-theme
  `#Preview`s on StoryList/Detail/Quiz, Papers, PhotoScans. No gender colors in this phase (none expected).
- **2026-07-28 (Phase 9)** — **Conversation themed; 2 tester asks split to the functional track.** All 12
  files — 1 self-file (ConversationSetupView) + **3 parallel subagents** (the 1332-line ConversationView on
  its own; list/summary/preview/scenario/sayit; phrase-library/deck/review/components/tappabletext), one
  integrated `build_sim` (green, first try). `ConversationComponents` and `TappableText` correctly needed
  **no change** (shared sections / pure text). Notable: `ConversationView.modelBubble` was a `View`
  *extension method* (can't read `@Environment`) → converted to a `ViewModifier` so it can theme its corner
  radius. `innerRadius`/`pillShape` throughout on bubbles/chips; `.tint(appTheme.accent(model: theme))`
  innermost on the brand screens. **Deliberately deferred (now §5):** the tester's "photo/URL talk-about-this"
  mode and a skippable/text-input voice path — both need `ConversationMode`/`Config`/engine/prompt + chat-
  pipeline changes and on-device MLX testing, which a theming pass can't validate. Shipping them half-built
  would be worse than logging them clearly. 4-theme `#Preview` on ConversationList.
- **2026-07-28 (Phase 10)** — **Settings & Model UI themed; model-by-goal shipped & live-verified.** All 22
  files — 2 self-files (`ModelSettingsView`, `SettingsView`) + **3 parallel subagents** (Learning/reminder;
  Settings sections/sheets; Model-brand components), one integrated `build_sim` (green, first try). Root
  Settings list + the 5 detail-wrapper Forms themed; every section-emitter got `.themedListRow/SectionHeader`.
  **Tester ask — "Pick by goal":** new section in `ModelSettingsView` mapping Best German / Fastest / Fits my
  device / Longest stories → a model (via `recommendedOrder(ramGB:)` + `germanQualityScore`/`parameterCountValue`/
  `recommended`), one tap loads it through the existing `requestLoad`; spec cards stay below. **Verified on the
  iPhone 17 sim** (screenshot): the goal picker resolves Best German → Gemma 4 E4B German Tutor, Fastest →
  Apple Intelligence, and the whole screen wears the Notebook theme. Strong **chrome-vs-content** discipline
  from the subagents: **5 pure-brand Model components** (`ModelGradientHero`, `ModelInfoSheet`,
  `ImageModelInfoSheet`, `ModelLoadingIndicator`, `ModelLoadingPanel`) correctly needed **no change** (mesh
  gradients / glows / provider logos = content), and the `ModelPicker` hero "Recommended" row was left
  unthemed so its brand highlight survives. Only **Phase 11** (Library/Queue/leaf + motif polish) remains.
- **2026-07-28 (Phase 11 — branch complete)** — **Library, Queue & leaf views themed; theme-upgrade done.**
  Final 8 files — 1 self (`UnifiedLibraryView` + `DeckStatsSheet`) + **2 parallel subagents** (Queue; Shared
  leaf views), one integrated `build_sim` (green, first try). `SelectableGermanText` correctly needed **no
  change** (pure `UITextView` text). A subagent caught a real gotcha: `pillShape` is an `AnyShape`, not an
  `InsettableShape`, so it can't back `.strokeBorder` — bordered demo capsules were left as-is rather than
  regress Klar. **Motif pass:** the mechanical motifs (Kritzel tilt + ruled paper, Grundform square + black
  rules + UPPERCASE, Sanft rounded) are delivered by the token system across all phases; bespoke celebratory
  art is logged as optional future design polish. **All 11 phases done** — every screen wears its theme, Klar
  is pixel-identical, der/die/das is one palette app-wide. Remaining work is the functional track (§5), which
  needs engine/prompt changes + on-device MLX testing, not theming.
