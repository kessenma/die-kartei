# Die Kartei on macOS

The Mac app is the **same target** as the iPhone and iPad app, compiled for macOS: same bundle
ID (so it's one app record and a universal purchase), same SwiftUI screens, same iCloud container.
The screens are the phone's; the window around them is the Mac's: a sidebar, a menu bar, and a
Settings window.

## Navigation

- **The sidebar** (`App/MacSidebarShell.swift`) is the default, a `NavigationSplitView`.
  - **What it lists** (`MacDestination` in `App/MacNavigator.swift`):
    - Home (For You only)
    - Üben · Practice: Home's six categories
    - Ziele · Goals: Deutschkurs and Job Prep
    - Library
    - a footer with the download and generation badges and the Settings button
  - **Only the chosen place is alive.** A Mac window has one toolbar, and every live
    navigation stack writes its title and buttons into it. So, unlike the iPhone's tabs, choosing a
    place opens it at its first screen.
  - **Compact mode:** the sidebar shrinks to icons only (names become tooltips) with the toolbar
    button or View ▸ Compact Sidebar (⌃⌘S). That replaces the system's hide-sidebar toggle, so
    there is one control.
- **The tab bar** is the iPhone layout, kept as a choice: `mac.navigationStyle` is `sidebar` or
  `tabBar`. Switch it from View ▸ Navigation or Settings ▸ Appearance ▸ Navigation. (Not "Show
  Tab Bar": that's the system's window-tab command, and window tabbing is off for this one-window
  app.)
  `ContentView` picks `shell` (`MacSidebarShell` or the unchanged `tabShell`), and every sheet,
  cover and overlay hangs off whichever shows.
- **Settings is its own window** (⌘,), `Features/Settings/MacSettingsView.swift`:
  - The panes come from `SettingsPane`, the same list the iPhone's Settings builds its rows from.
    A new setting is one new case, and both platforms show it.
  - Deep links (`SettingsRouter`, e.g. a nudge's "open Model settings") open the window on that
    pane via `MacSettingsSelection`.
  - In tab-bar mode the in-window Settings tab stays too.
- **Menu bar** (`App/MacCommands.swift`):
  - Go: ⌘1–⌘0 to the sidebar's places.
  - File: Import Deck… (⌘O), which takes the place of New Window since the app is one window.
  - View: the navigation choices.
  - Help: What's New and Send Feedback.
- **Full-screen covers open in their own window** (`App/MacCoverWindow.swift`): activities,
  chats, the web clippers, the onboarding wizard and the rest.
  - **Why not a sheet:** a Mac sheet draws no toolbar, so a cover's close button, title and
    trailing buttons (a story's step bar, the Kasus-Check) would all be missing.
  - **How it works:** `fullScreenCover` in MacCompat registers the cover's view with
    `MacCoverRegistry` and opens a `cover` window. The window gets the opener's environment (model
    context, theme, routers, tutor service).
  - **Closing:** the window's close button, ⌘W and the screen's own `dismiss()` all end the cover.
  - **The opener** shows "Open in its own window" with a Show Window button while it's open.
- **Reading text size** (`App/MacReadingTextSize.swift`):
  - View ▸ Bigger Text / Smaller Text (⌘+ / ⌘−, ⌘= as well) sizes the German you read: chat,
    stories, class notes, job postings. It works through `\.macReadingScale` in the Mac
    `SelectableGermanText` and `WrappedText`.
  - The default is 1.3×, because Mac text styles run a quarter smaller than the iPhone's.
  - It isn't whole-window zoom: macOS ignores Dynamic Type, and scaling the window's content (both
    AppKit bounds and SwiftUI `scaleEffect`) broke the layout and the window's minimum size.
- On the Mac, chat uses `SelectableGermanText` too (`ConversationView`'s guards include macOS),
  so double-click and right-click work in messages.
- **Readable width:** `themedScreen()` / `themedListScreen()` centre scrolling content in a column
  of at most 760 pt (`\.macReadableWidth`, off in the Settings window), using safe-area padding
  (a Mac `List` ignores `contentMargins`).
- **Sheet size:** a Mac sheet (and popover) opens at its content's ideal size, and a `List` has
  none: it measures 0×0, so a `List` sheet opened as a bare title bar and Cancel button with
  nothing under it. `macSheetSize()` gives it an ideal 560×660, which is only read when nothing
  proposes a size, so the main window, cover windows and split views are untouched.
  `themedListScreen()` applies it. **A new `List` sheet without `themedListScreen()` needs
  `.macSheetSize()` on its `List`.** A `Form` or `ScrollView` sizes to its content and needs nothing.

## Device words

`Models/ThisDevice` gives copy the device's name ("iPhone", "iPad", "Mac"), its system ("iOS",
"iPadOS", "macOS") and its settings app ("Settings" or "System Settings"). Use it instead of
writing "iPhone" or "your phone" into a string. It's nonisolated, so services off the main actor
(the memory saver's notices, a model's load error) can use it.

## How it compiles

- **`App/MacCompat.swift`** (macOS-only) gives the iOS APIs the app uses a Mac meaning, so view
  files don't need to know they're on a Mac:
  - `UIImage`/`UIColor`/`UIFont` are type aliases for the AppKit classes.
  - The iOS system colors are drawn with iOS's own light/dark values, so the palette matches the
    phone.
  - `UIApplication`, `UIDevice`, `UIPasteboard`, `AVAudioSession`, `UIGraphicsImageRenderer` and
    the `BGTask` types are small stand-ins.
  - iOS-only SwiftUI modifiers either do nothing (`navigationBarTitleDisplayMode`,
    `textInputAutocapitalization`, `keyboardType`, `listSectionSpacing`) or become the nearest
    Mac thing (`fullScreenCover` → its own window, `.topBarTrailing` →
    `.primaryAction`, `.insetGrouped` → `.inset`, `.page` → the automatic tab style).
- **The rule:** a stand-in keeps the iOS name and shape. When a screen genuinely has to behave
  differently on the Mac, guard *that screen* with `#if os(macOS)`; don't bend a stand-in to
  fit one caller.
- **`import UIKit` is always wrapped** in `#if canImport(UIKit)`. A bare one stops the Mac build
  at dependency scanning, before any other error is reported.
- **Views that wrap UIKit have Mac twins** with the same name and parameters, in `+macOS` files
  or `#else` branches:
  - `SelectableGermanText` and `WrappedText` sit on a Mac `WrappingTextView` (an `NSTextView`).
    It gives the same styling, pictures that the text flows around, double-click to inspect a
    word, and "Translate" / "Save phrase" in the right-click menu.
  - `WebViewContainer` and the job sheet's `PDFKitView` wrap the same `WKWebView` / `PDFView`.
- **The chat composer** uses the existing non-UIKit fallback (a vertical `TextField`). The Mac has
  no per-field keyboard language; input sources are system-wide.

## Project settings (macOS only)

| Setting | Why |
|---|---|
| `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` → `german-ai-flashcards-macOS.entitlements` | Mac push key (`com.apple.developer.aps-environment`) and the iCloud keys, without the iOS-only keys (continued processing, increased memory limit) |
| `INFOPLIST_FILE[sdk=macosx*]` → `Info-macOS.plist` | `Info.plist` minus iOS-only keys (`LSSupportsOpeningDocumentsInPlace = NO` is a Mac build error). Keep its document types in step with `Info.plist`. |
| `ENABLE_OUTGOING_NETWORK_CONNECTIONS`, `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT`, `ENABLE_USER_SELECTED_FILES = readwrite` | Sandbox access for model downloads, CloudKit and the web clipper; the microphone; `.kartei` export and PDF import |
| `ARCHS[sdk=macosx*] = arm64` | MLX needs Apple Silicon |
| `LSApplicationCategoryType = public.app-category.education` | Required by the Mac App Store |
| The keyboard extension is embedded with `platformFilters = (ios)` | iOS keyboard extensions don't exist on macOS |
| `NSServices` in `Info-macOS.plist` | The Schreibhilfe's four Services menu items; see [Schreibhilfe](#schreibhilfe-the-german-writing-helper) |
| `Services/GermanWriter.swift` belongs to the app target, plus the keyboard through a `PBXFileSystemSynchronizedBuildFileExceptionSet` | The keyboard and the Mac helper share one copy of the prompts |

## What differs on the Mac

- **Lifecycle:** an `NSApplicationDelegate` does the iOS delegate's launch work. It also turns
  memory-pressure events into the memory-warning notification (`MacMemoryPressure`), and quits
  when the window closes, unless the Schreibhilfe panel is open or a Services request is running.
- **iCloud Sync:**
  - It flushes on quit and when the app goes inactive, because a Mac app rarely reaches
    `.background`.
  - The foreground send-and-fetch is throttled to once a minute, since `.active` fires on every
    app switch.
  - The replica id lives in the data-protection keychain, so a Migration Assistant copy starts
    as a new replica.
  - The device list shows the Mac as "Mac".
- **Models:**
  - Downloads land in the sandbox container's Caches (`HubCacheLocation` has the Mac branch).
  - The memory budget falls back to half the physical RAM, because macOS has no
    `os_proc_available_memory`. That's conservative, and tuning it is a follow-up.
  - Story and card pictures from the Core ML models run on the Neural Engine: fp16 Core ML
    diffusion on the Mac GPU renders solid black. The Mac-only MLX picture models (Z-Image Turbo,
    FLUX.2 klein) run on the GPU without that problem, with their own drawing budget, and draw
    decks and stories other devices send. See [MAC_PICTURES.md](MAC_PICTURES.md).
- **Background generation** runs inline: the `BGTaskScheduler` stand-in refuses every submit, and
  `StoryBackgroundGenerator` already falls back to running the job in the app. Long jobs hold off
  idle sleep instead of the iOS idle timer.
- **Hidden on the Mac:**
  - the camera buttons (no `UIImagePickerController`; `PhotosPicker` and the file importer stay)
  - the keyboard setup row in Settings (the Mac has App ▸ Schreibhilfe instead)
  - Job Prep's saved-PDF and live-page reading surfaces (the text surface works)
- **Window:** 1100×900 by default, with a minimum of 760×820 so phone-shaped screens and their
  sheets fit, and a unified toolbar. `Form`s use `.grouped` app-wide, because the Mac default is a
  two-column layout.

## Schreibhilfe: the German writing helper

The Mac's stand-in for the iOS keyboard. macOS has no keyboard extensions, and an InputMethodKit
input method can't ship on the Mac App Store, so the keyboard's two jobs, „Auf Deutsch" and
„Korrigieren", come to the Mac as two things inside the app:

- **Services menu items** (`Services/MacWritingServices.swift`, declared under `NSServices` in
  `Info-macOS.plist`): „Auf Deutsch (Sie)", „Auf Deutsch (du)" and „Deutsch korrigieren" replace
  the selection in any app; „In der Schreibhilfe öffnen" hands it to the panel. Learners bind
  shortcuts in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services.
- **The Schreibhilfe panel** (`App/MacWritingHelper.swift`): a floating, non-activating panel
  (editor, streaming reply, „Kopieren & schließen"). It opens from Edit ▸ Schreibhilfe… (⌥⌘D) and
  from every request that can't finish in place.
- **Settings:** App ▸ Schreibhilfe (`SettingsPane.writingHelper`, Mac only).

The prompts and the model call are shared with the keyboard: `GermanWriting` in
`Services/GermanWriter.swift`.

**Invariants:**
- `GermanWriting` stays `nonisolated` and `perform` stays `@concurrent`. A service must have its
  result on the pasteboard when its method returns, so the provider waits on the main thread by
  spinning the run loop in 50 ms slices. A hidden hop to the main actor (this project's default
  isolation) inside the core would hang until the deadline. Don't swap the spin for a semaphore.
- Nothing is written back unless it's a clean German reply that didn't hit the token cap. Too
  long (over 1,500 characters), unavailable, not German, cut short or too slow: the selection
  stays untouched and the panel opens with the text and the reason.
- The Services path uses the non-streaming `respond`. Apple rate-limits streaming for an app that
  isn't frontmost, which a Services provider never is.
- `NSTimeout` (45 s) stays well above the provider's own 20 s deadline: it also has to cover a
  cold launch.
- Never rename the service titles or `NSMessage`. Learners' custom shortcuts are keyed by them.
- Never read `NSPasteboard.general` (macOS prompts for paste permission). The panel only writes to
  it; the learner pastes with ⌘V. The panel handles ⌘V/⌘C/⌘X/⌘A/⌘Z itself, because while another
  app is active the menu bar is that app's.
- Send and return types are exactly `public.utf8-plain-text`: Chrome and Electron apps only offer a
  service for that type. Formatting in the selection comes back plain.
- The translate prompt's wording was tuned against the model (see the comment on
  `GermanWriting.instructions`); rerun the comparison before changing it.

**Checking it** (no UI, no keystrokes):
- `swift scripts/mac_service_probe.swift "Auf Deutsch (Sie)" "Hi Anna, can we move our call?"`
  runs a service end to end and prints `ok`, `changed`, the seconds and the reply. `changed=false`
  means nothing was written back.
- After a build: `/System/Library/CoreServices/pbs -update`, then
  `pbs -dump | grep -A12 'Auf Deutsch'` to see the registered items. Old Die Kartei copies in
  DerivedData don't declare the services, so the newest build wins; a TestFlight copy in
  /Applications would compete.
- Measured on this Mac (2026-10-04, macOS 27.2): about 0.6–3 s per email warm, 8 s on a cold
  launch; ten requests in a row weren't rate-limited.

**Known gaps:** a cold launch opens the main window behind the app you're in. Korrigieren, on
Apple's model, misses some errors (it left „habe … gegangen"). Only the macOS 27 error and usage
paths have run for real; the 26.x paths rest on the unit tests.

## Running and checking it

- **Build:** `xcodebuild -scheme german-ai-flashcards -destination 'platform=macOS,arch=arm64' build`.
  Add `-allowProvisioningUpdates` and the API-key flags from `scripts/deploy.py` for a signed
  build; iCloud needs one.
- **Sync, in this order:**
  1. `-sync.debugVerify 1`
  2. Mac Debug + iPhone Debug with `-sync.enable 1`. Both Xcode builds talk to CloudKit
     Development.
  3. Both on TestFlight (Production).
- **Before shipping:** `codesign -d --entitlements - "Die Kartei.app"` on an archive should list the
  sandbox, network client, audio input, `aps-environment` and iCloud keys, and the bundle must
  have no `PlugIns/*.appex`.
- **The iOS build must stay green** after every Mac change.

## Releasing

`python3 scripts/deploy.py --mac` (Cmd+Shift+M in VS Code) for TestFlight, and `release --mac`
for the Mac App Store. See [DEPLOY_SETUP.md](DEPLOY_SETUP.md#the-mac-app), including the one-time
App Store Connect step (add the macOS platform, Mac screenshots and description).

## Known gaps (v1)

- **Card carousels:** `.tabViewStyle(.page)` becomes a plain tab view on the Mac. Preposition
  Cards has its own Mac layout (one card at a time, the pager and ←/→); the render-test lab doesn't.
- **Job Prep:** the PDF and live-page surfaces aren't built for the Mac yet.
- **Still to come for the Mac:**
  - keyboard control in study sessions (Space to flip, 1–4 to grade, ←/→)
  - right-click menus mirroring swipe actions
  - dropping files onto the window
  - a deck or story in its own window
