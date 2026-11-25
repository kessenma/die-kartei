# Android port: working log

**Goal:** die Kartei on Android, keeping as much of the app in Swift as possible.

**Branch:** `android-port`. Main stays the iOS app; this branch merges main in as it moves.

## Approach

Two layers, both Swift:

- **DieKarteiCore** (`DieKarteiCore/`): a SwiftPM package of the app's portable files. Its
  sources are *symlinks* to files in `german-ai-flashcards/`, the same pattern as
  `KarteiSyncCore`. Nothing moves, the iOS target compiles the files in place, and there are no
  `import DieKarteiCore` edits in the app. `scripts/core_sync.py` keeps the link list.
- **DieKarteiAndroid** (`DieKarteiAndroid/`): a [Skip Fuse](https://skip.dev) app. Skip compiles
  Swift natively with the official Swift SDK for Android and maps SwiftUI to Jetpack Compose, so
  the Android UI is SwiftUI too. It depends on DieKarteiCore.

The June attempt (moving files into a package and adding `import DieKarteiCore` to 41 files)
couldn't be rebased onto today's main, so it was redone this way. Its history stays on the branch.

## What stays Apple-only

SwiftData (262 files touch it), CloudKit/iCloud sync, MLX, PencilKit, Vision, Speech, RealityKit,
PDFKit, FoundationModels. On Android these need replacements behind protocols, one at a time:

| Apple | Android candidate |
| --- | --- |
| SwiftData | SQLite in Swift (Skip's SkipSQL / GRDB-style), behind a store protocol |
| iCloud sync | later; `Services/Sync/Core` already builds for Android, only the transport is Apple |
| MLX | llama.cpp (GGUF builds of the tutor models) |
| Speech / AVSpeech | Android TTS/STT through Skip's Kotlin bridging |
| PencilKit | Compose canvas; later |

## Status (2026-11-24, Mac mini)

| Step | State |
| --- | --- |
| Swift 6.4.3 via swiftly + Swift SDK for Android 6.4.3 | ✅ |
| Android Studio, SDK 37, NDK r30, emulator (Medium Phone API 37) | ✅ |
| Skip 1.9 (`skip checkup` passes) | ✅ |
| DieKarteiCore cross-compiles for `aarch64-unknown-linux-android28` | ✅ 75 app files |
| iOS app still builds with the splits below | ✅ |
| Skip Fuse app on the emulator | see below |

### App-side changes made for the core (no behaviour change on iOS)

- `Gender` and `GrammarCase` moved from `GrammarPalette.swift` (SwiftUI) to the Foundation-only
  `Models/Grammar/GrammarTerms.swift`; their `color` became an extension in GrammarPalette.
- `KasusUnit.color` moved to GrammarPalette the same way.
- `MLXModel.configuration` moved to `Models/MLXModel+MLX.swift`; the catalog has `repoID`.
- The three `Services/Sync/Core` files that hash pick CryptoKit or swift-crypto with
  `#if canImport(CryptoKit)`.
- Five files using `@Observable` import `Observation` explicitly (Apple's Foundation re-exports
  it; Android's doesn't).

## Growing the core

`python3 scripts/core_sync.py --prune` collects every app file that imports only Foundation (or
Observation, or CryptoKit behind `canImport`) and has no `@Model`, cross-compiles for Android,
and drops whatever fails until the package builds. It prints the most-missed types: each one is
a type that lives next to SwiftUI/SwiftData code and is worth splitting into its own file.

Next splits, by how much each one unlocks (the Kasus cluster is one dependency cycle, so one
leaf blocks the whole group):

- `PrepositionCase` (Preposition.swift) → VerbPreposition, WorksheetGrader
- `KasusHintLevel` / `KasusPickOutcome` / `KasusTipp` / `KasusRoundResult` / `KasusPrefill`
  (KasusService.swift) → KasusEndings and most of the Kasus engine
- `KasusConceptPlayable` (KasusConcepts.swift) → EnglishAnchors, FehlerQuestion
- `KasusRound` (a SwiftData model) → KasusConfusion, GrammarProgress
- `ChatMessage` / `ChatRole` (ChatConversation.swift) → ConversationPrompts, ChatTurnNormalizer
- `JournalKind` / `WritingSentenceCheck` (JournalEntry.swift) → the Schreiben prompt bank/check
- `WordClass` / `VocabListRow` (VocabListParser.swift) → word-class tagging
- `WorksheetExercise` & co. (WorksheetParser.swift) → worksheet grading
- `GermanArticle` / `ArticleQuestion` (ArticleGame.swift) → ArticleRules, game words
- `StudyDay`, `StoryGenre`, `GlossaryEntry`: SwiftData models; need plain-value twins

## Toolchain cheat sheet

```bash
# ~/.zprofile sets ANDROID_HOME, ANDROID_NDK_HOME, JAVA_HOME (Android Studio's JBR) and PATH;
# swiftly puts Swift 6.4.3 first on PATH (Xcode keeps its own toolchain for xcodebuild).

python3 scripts/core_sync.py            # relink from DieKarteiCore/core_files.txt
python3 scripts/core_sync.py --prune    # rediscover the portable set
swift build --package-path DieKarteiCore \
  --swift-sdk swift-6.4.3-RELEASE_android --triple aarch64-unknown-linux-android28 --static-swift-stdlib

emulator -avd Medium_Phone_API_37.0 &   # or Android Studio › Device Manager
cd DieKarteiAndroid && skip android build   # see DieKarteiAndroid/README.md
```

## Gotchas

- **Gatekeeper and Android Studio's Java:** until Android Studio has been opened once by hand,
  its bundled `java` hangs on the first-launch check (sdkmanager/gradle just stall).
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and Swift 5 mode; the core
  package mirrors that (`.defaultIsolation(MainActor.self)`), or `nonisolated` annotations in the
  shared files would mean something different in the two builds.
- The emulator on Apple Silicon is arm64, so `aarch64` is the triple to test; `x86_64` only
  matters for Intel hosts.
