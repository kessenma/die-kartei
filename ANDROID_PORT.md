# Android Port — Working Log

**Goal:** Get die Kartei running on Android while reusing as much Swift code as
possible, via the official [Swift SDK for Android](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html)
(Swift 6.3.2). UI will be Kotlin/Jetpack Compose; the shared logic stays Swift.

**Branch:** `android-port` (main holds the stable iOS app).

## Architecture

```
┌─────────────────────┐      ┌──────────────────────────┐
│  iOS app (SwiftUI)  │      │  Android app (Compose)   │
│  SwiftData, MLX,    │      │  Room/SQLite, llama.cpp  │
│  SFSpeech, Vision   │      │  or cactus, Android STT/ │
│                     │      │  TTS, ML Kit OCR         │
└─────────┬───────────┘      └──────────┬───────────────┘
          │                             │ JNI (swift-java wrap-java)
          ▼                             ▼
┌──────────────────────────────────────────────────────┐
│              DieKarteiCore (SwiftPM package)          │
│  SRS algorithms · prompts · vocab/grammar content ·   │
│  domain models · (later: conversation engine behind   │
│  a GenerationService protocol)                        │
└──────────────────────────────────────────────────────┘
```

Key decisions:
- **MLX stays untouched on iOS.** The core never imports MLX. The mapping from
  the `MLXModel` catalog to MLX registry configs lives in the app-side
  `german-ai-flashcards/Models/CoreBridging.swift`.
- **SRS works through a protocol.** `SRSCardState` (in the core) abstracts the
  card's SRS fields; the SwiftData `SavedCard` conforms on iOS, and an
  Android-side class can conform the same way. The SM-2 and Leitner algorithms
  are now 100% shared.
- **ML engine on Android:** llama.cpp via C interop is the leading candidate
  (keeps inference inside the Swift core; GGUF quants exist for all 9 catalog
  models). Cactus (https://github.com/cactus-compute/cactus) is appealing for
  CPU+GPU, but the Swift binding (https://github.com/mhayes853/swift-cactus)
  looked stale at last check — needs a fresh evaluation before committing.
- **Resources:** the five content JSONs (a1/a2/b1 vocab, past-tense verbs,
  grammar exercises) live in the package now and load via `Bundle.module`.
  `CoreResources.overrideDirectory` is the Android escape hatch — the host app
  extracts assets from the APK and points the core at that directory.

## Status (2026-06-13)

| Step | State |
|------|-------|
| Push stable app to GitHub `main` | ✅ |
| `android-port` branch | ✅ |
| Swift 6.3.2 + Android SDK toolchain install | ✅ (via swiftly) |
| Extract `DieKarteiCore` SwiftPM package | ✅ |
| Core builds for macOS (Swift 6.3.2) | ✅ |
| Core cross-compiles `aarch64-unknown-linux-android28` | ✅ |
| Core cross-compiles `x86_64-unknown-linux-android28` (emulator) | ✅ |
| iOS app builds against the package | ✅ (simulator build + launch verified) |
| Package resource bundle embedded in .app with all JSONs | ✅ |
| Package unit tests (8: resources, SM-2, Leitner, prompt parsing) | ✅ all pass |
| swift-java / JNI hello-world from Kotlin | ⬜ next |
| Android Studio project skeleton (Compose) | ⬜ |
| GenerationService protocol around MLXGenerationService | ⬜ |
| Android inference spike (llama.cpp vs cactus) | ⬜ |
| Persistence story (SQLite in core vs Room behind protocol) | ⬜ |

## What moved into DieKarteiCore

From `Models/`: `VocabCard`, `ConversationConfig` (+ all conversation enums),
`ModelConfiguration.swift` → `ModelCatalog.swift` (minus MLX bits),
`GrammarExercise`.
From `Services/`: `LeitnerService`, `SpacedRepetitionService`,
`ConversationPrompts` (now takes `TranscriptLine` instead of `ChatMessage`),
`A1VocabService`, `PastTenseVerbService`, `GrammarExerciseService`.

App-side bridging shims live in `german-ai-flashcards/Models/CoreBridging.swift`
(MLX registry mapping, `SavedCard: SRSCardState`, `ChatMessage` → transcript).

## Toolchain cheat sheet

```bash
# One-time setup (already done on this machine):
#   swiftly installed to ~/.swiftly, toolchain 6.3.2 installed + in use
#   swift sdk install <android artifactbundle URL> --checksum <…>
#   ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.1.12297006 \
#     bash ~/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle/swift-android/scripts/setup-android-sdk.sh

export PATH="$HOME/.swiftly/bin:$PATH"   # Swift 6.3.2 (Xcode keeps its own 6.2.x)
cd DieKarteiCore
swift build && swift test                # host build + tests
swift build --swift-sdk aarch64-unknown-linux-android28 --static-swift-stdlib
swift build --swift-sdk x86_64-unknown-linux-android28 --static-swift-stdlib
```

## Gotchas discovered

- **`semaphore.h not found` on first Android build:** the SDK bundle ships
  without an NDK sysroot. Run its `scripts/setup-android-sdk.sh` with
  `ANDROID_NDK_HOME` set (NDK ≥ r27; we used 27.1.12297006). It symlinks the
  NDK headers/libs into the bundle.
- **SourceKit shows phantom "cannot find type" errors** in package sources
  until Xcode opens/resolves the package — `swift build` is the source of truth.
- **Swift 6 strict concurrency:** the content services use simple
  `static var` caches, so the package pins `.swiftLanguageMode(.v5)` for now.
  Worth revisiting (make caches `Sendable`-safe) before the JNI layer, since
  Kotlin will call in from arbitrary threads.
- **Xcode 16+ synchronized folders:** moving files out of
  `german-ai-flashcards/` removes them from the app target automatically — no
  pbxproj file-list surgery needed. The local package reference was added by
  hand-editing pbxproj (`XCLocalSwiftPackageReference`, UUIDs prefixed
  `D1ECA0…`).
- 41 app files needed `import DieKarteiCore`; three more were caught by the
  compiler (property-only usages my type-name grep missed).

## Next session plan

1. **JNI spike:** new `android/` dir with a minimal Gradle/Compose project.
   Use swift-java's `wrap-java` to generate bindings for a trivial core call
   (e.g. `LeitnerService.boxLabel`), package the `.so` + Swift runtime libs
   into the APK, call it from Kotlin. The swift-android-examples repo is the
   template: https://github.com/swiftlang/swift-android-examples
2. **GenerationService protocol** in core; `MLXGenerationService` becomes the
   iOS implementation (mechanical, no behavior change).
3. **Inference spike:** llama.cpp as a conditional target dependency
   (Android-only) vs. cactus — measure tokens/sec with Qwen3 0.6B GGUF on a
   real device before choosing.
4. Decide persistence: shared SQLite schema in core (preferred) vs.
   per-platform stores behind a repository protocol.

## Open questions for Kyle

- License for the open-source repo (MIT? Apache-2.0?) — repo currently has none.
- Keep the 41 MB `wiktionary_de.db` in git, or regenerate via
  `scripts/build_wiktionary_db.py` / Git LFS? (GitHub is fine with it for now.)
