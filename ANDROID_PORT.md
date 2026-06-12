# Android Port — Working Log

**Goal:** Get die Kartei running on Android while reusing as much Swift code as
possible, via the official [Swift SDK for Android](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html)
(Swift 6.3.2). UI will be Kotlin/Jetpack Compose; the shared logic stays Swift.

**Branch:** `android-port` (main holds the stable iOS app).

## Architecture plan

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
- **MLX stays untouched on iOS.** The core never imports MLX; iOS-only bits
  (e.g. `MLXModel.configuration`) live in app-side extensions.
- **ML engine on Android:** llama.cpp via C interop is the leading candidate
  (keeps inference inside the Swift core). Cactus is appealing
  (CPU+GPU, https://github.com/cactus-compute/cactus) but the Swift binding
  (https://github.com/mhayes853/swift-cactus) looks stale — needs evaluation.
- **Resources:** vocab/grammar JSONs move into the package (`Bundle.module`),
  with `CoreResources.overrideDirectory` as the Android escape hatch (APK
  assets get extracted to a directory at first launch).

## Status

| Step | State |
|------|-------|
| Push stable app to GitHub `main` | ✅ done |
| `android-port` branch | ✅ done |
| Swift 6.3.2 + Android SDK toolchain install | ⏳ running in background |
| Extract `DieKarteiCore` SwiftPM package | ⏳ in progress |
| iOS app builds against the package | ⬜ |
| Cross-compile core for `aarch64-unknown-linux-android28` | ⬜ |
| swift-java / JNI hello-world from Kotlin | ⬜ |
| GenerationService protocol around MLXGenerationService | ⬜ |
| Android inference spike (llama.cpp or cactus) | ⬜ |

## Notes / gotchas

(updated as discovered)
