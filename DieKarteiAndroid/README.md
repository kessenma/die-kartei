# Die Kartei for Android

A [Skip Fuse](https://skip.dev) app: Swift and SwiftUI, compiled natively for Android with the
Swift SDK for Android, with SwiftUI mapped to Jetpack Compose. See `../ANDROID_PORT.md` for the
bigger picture.

## Modules

- **DieKarteiCore** (`Sources/DieKarteiCore` → `../DieKarteiCore/Sources/DieKarteiCore`): the
  iOS app's own portable files, symlinked, not copied. Plain Swift, no Skip plugin.
- **GermanVoice**: transpiled Swift (Skip Lite) around Android's TextToSpeech, bridged to the
  native module. The place to add other Android-only APIs.
- **CLlama**: llama.cpp's C API, for the tutor models (Android only). The libraries come from
  `../scripts/build_llama_android.sh`; `TutorEngine.swift` calls them from Swift directly.
- **KarteiStore**: the app's SQLite database (`files/kartei.sqlite`) on SkipSQLPlus, which
  builds its own SQLite 3.51.3. Opened at launch by `AppDatabase`. `RecordStore` keeps synced
  data as iOS sync records (same ids and payloads, per-device counters); host tests:
  `swift test --filter KarteiStoreTests`.
- **DieKartei**: the Android screens. It uses the core through `@testable import` so the iOS
  app's internal types stay internal.

Today the tab bar matches iOS: Home, Grammar, Library, Settings.
- Home: what's due today, then Vocabulary, Grammar, Hören and Spiele.
- Library: the three Goethe decks with their progress.
- Settings: Appearance, Voice (sample + Android's voice settings), Your Level, Flashcards (new
  words per session, reset a deck), Sources & Credits.
- Karten: the Goethe deck with spaced repetition (shared SM-2, four rating buttons), with a
  speaker button. Progress is one Wortschatz deck in the database, with the iOS card ids
  (`StudyStore` on `RecordStore`; docs/android-parity/persistence.md).
- Wortschatz: the A1–B1 lists, searchable.
- Grammatik: Kasus lessons (with the case-colour markup), der/die/das with ArticleRules hints,
  Präpositionen, the four Lückensatz sets, Perfekt haben/sein, Die vier Fälle.
- Hören: Zahlen-Diktat for every number kind, spoken by Android's German voice.
- Spiele: Galgenmännchen and Wortsuche on the iOS engines.
- Tutor: Gespräch runs the iOS app's own conversation session (`ConversationSession` in the
  core; `TutorStore` answers its `TutorGenerating` protocol with llama.cpp): opener, correction
  or nudge, reply, translations, hints, summary. Typed only, kept in memory for now. Satz prüfen
  checks one sentence. Settings ▸ Tutor Model picks the model. Prompts are written out by
  `ChatPromptFormat` (core), tested against the real chat templates.

## Run it

```bash
python3 ../scripts/core_sync.py      # relink the core and copy the JSON data into Resources/
../scripts/build_llama_android.sh    # once: llama.cpp for Android into Vendor/ (gitignored)
emulator -avd Medium_Phone_API_37.0 & # or start it from Android Studio's Device Manager
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
skip app launch --android
```

`Darwin/` is Skip's iOS shell; Skip drives the build through it. The real iOS app is still
`german-ai-flashcards.xcodeproj`.

## Tutor models on the device

Settings ▸ Tutor Model downloads them from Hugging Face (`kessenma/*-gguf`; the files, sizes
and SHA-256s are `MLXModel.gguf` in `german-ai-flashcards/Models/MLXModel+Catalog.swift`) into
the app's private `files/models/`. A download continues where it stopped (`<file>.part`) and is
checked against the hash before it can load. Publishing: `../training/scripts/publish_gguf.py`;
building from a master: `../training/scripts/release_model.py` (see `../training/ANDROID_GGUF.md`).

To skip the download during development, copy a file in (it must be the published file, same name):

```bash
adb push gemma4-e2b-german-tutor-Q4_K_M.gguf /data/local/tmp/
adb shell "cat /data/local/tmp/gemma4-e2b-german-tutor-Q4_K_M.gguf | run-as com.kessenma.diekartei \
  sh -c 'cat > files/models/gemma4-e2b-german-tutor-Q4_K_M.gguf'"
adb shell rm /data/local/tmp/gemma4-e2b-german-tutor-Q4_K_M.gguf
```

The emulator's default data partition (10 GB) holds one model plus the app; the AVD here runs
with 6 cores and 8 GB RAM (`hw.cpu.ncore`, `hw.ramSize` in its config.ini). Its cores are the
Mac's, so its speed is far above a phone's: measure speed on a real phone.

## Testing on the emulator

`adb exec-out screencap -p > shot.png` for a picture; `adb shell uiautomator dump` gives every
visible text with its bounds, which is enough to tap through screens from a script.

## Things that bit

- `@State` / `@Environment` properties can't be `private` (Skip can't bridge them).
- `Text + Text` is unavailable; build an `AttributedString` (colours and bold/italic render).
- Compose needs unique `ForEach` ids across a whole `List`, not just within a section.
- Icons: SF Symbols can't ship on Android (Apple's licence), so every SF name the app uses has a
  `<name>.symbolset` in `Resources/Module.xcassets/Symbols`, drawn from Material Symbols Rounded,
  Phosphor, Lucide or Tabler (`ICON_LICENSES.txt`). SkipUI checks the catalog before its own small
  Material table, so views keep the iOS names. `python3 ../scripts/android_symbols.py` regenerates
  them from `docs/android-parity/icon-map.csv` (needs `pip install picosvg`);
  `python3 ../scripts/android_symbols.py --check` fails if a symbol literal in the UI module or
  the core has no symbolset (a missing one only shows at runtime as a ⚠ and the log line
  "Unable to find system image named").
- The JSON data files must be real files in `Resources/` (copied by `core_sync.py`, gitignored):
  the resource copy resolves symlinks logically and Skip keeps subfolders as they are.
- `@Observable` types in the core import SkipFuse on Android (`#if os(Android)`, not
  `canImport`: the Darwin build of this package can see SkipFuse but not its JNI deps), or
  Compose never hears about their changes and the screen freezes on its first state.
- llama.cpp loads its CPU backend from the extracted native-library directory, so the APK uses
  `useLegacyPackaging = true`. Foundation reads `/proc` files by their reported size (0): read
  them with `FileHandle.readDataToEndOfFile()`.
- SwiftPM looks up github.com credentials in the login keychain before downloading Skip's
  binary; with the screen locked that prompt waits forever. `swift package resolve
  --disable-keychain` once fetches it into the shared cache.
