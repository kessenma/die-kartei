# Die Kartei for Android

A [Skip Fuse](https://skip.dev) app: Swift and SwiftUI, compiled natively for Android with the
Swift SDK for Android, with SwiftUI mapped to Jetpack Compose. See `../ANDROID_PORT.md` for the
bigger picture.

## Modules

- **DieKarteiCore** (`Sources/DieKarteiCore` → `../DieKarteiCore/Sources/DieKarteiCore`): the
  iOS app's own portable files, symlinked, not copied. Plain Swift, no Skip plugin.
- **DieKartei**: the Android screens. It uses the core through `@testable import` so the iOS
  app's internal types stay internal.

Today: Wortschatz (the Goethe A1–B1 lists), Karteikarten (a shuffled round of 20, no spaced
repetition yet), and Die vier Fälle (the article table from `GrammarCase`).

## Run it

```bash
python3 ../scripts/core_sync.py      # relink the core and copy the JSON data into Resources/
emulator -avd Medium_Phone_API_37.0 & # or start it from Android Studio's Device Manager
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
skip app launch --android
```

`Darwin/` is Skip's iOS shell; Skip drives the build through it. The real iOS app is still
`german-ai-flashcards.xcodeproj`.

## Things that bit

- `@State` / `@Environment` properties can't be `private` (Skip can't bridge them).
- Compose needs unique `ForEach` ids across a whole `List`, not just within a section.
- Only some SF Symbols have Android equivalents (SkipUI `Image.swift` lists them); others
  show a warning triangle.
- The JSON data files must be real files in `Resources/` (copied by `core_sync.py`, gitignored):
  the resource copy resolves symlinks logically and Skip keeps subfolders as they are.
- SwiftPM looks up github.com credentials in the login keychain before downloading Skip's
  binary; with the screen locked that prompt waits forever. `swift package resolve
  --disable-keychain` once fetches it into the shared cache.
