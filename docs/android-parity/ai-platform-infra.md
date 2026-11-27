# Parity audit: AI / content-creation, platform features, cross-cutting infra (Android port)

Sources read: iOS `main` (``), Android worktree `android-port`
(`-android`, 15 commits ahead of main, 1 behind). Docs: ANDROID_PORT.md,
DieKarteiAndroid/README.md, TUTOR_CORE_PLAN.md, training/ANDROID_GGUF.md, docs-site android/sync.mdx,
iOS docs/*.md. Read-only audit. Nothing was built or run.

**Android today, for this scope:** Settings ▸ Tutor Model (file picker, the models get onto the
phone with adb), **Gespräch** (the shared `ConversationSession`, typed only, kept in memory, an
optional scenario), and **Satz prüfen**. Everything else below is **Missing**. The Android app is
2,858 lines in total. TTS is `GermanVoice` (92 lines: speak/stop/open settings). Progress is JSON in
UserDefaults/SharedPreferences (`StudyStore`). There's no database, no SkipSQL dependency in
`Package.swift`, no STT, no notifications, no themes and no sync.

Effort: S ≈ ≤3 days, M ≈ 1–2 weeks, L ≈ 3+ weeks (after foundations unless noted).

---

## 1. Feature-by-feature

### Conversation / tutor (Gespräch, Stammtisch, Recruiter warm-up, Say-it, phrase decks)
- **Purpose:** a chat with the on-device German tutor. Each turn gets a correction pass (FIX/WHY)
  and then a reply, plus hints, translations, a summary and saved phrases. Stammtisch adds
  pressure: topic jumps, a reply timer and background noise. Interview mode is used by Job prep.
- **Files:** `Features/Conversation/*` (22 files, 7.6k lines), `Services/ConversationEngine.swift`
  (now a typealias over the shared `ConversationSession`), `ConversationPrompts`, `ChatTurnNormalizer`,
  `StammtischNoise`, `ConversationQualityService`, `LearnedPhrase`.
- **Apple-only:** SwiftData (`ChatConversation`, `ChatMessage`, `LearnedPhrase`, `LearnerProfile`),
  Speech (STT), AVSpeech (autoplay), WebKit/PDFKit (job-posting clipper), UIKit.
- **Android: Partial.** The session logic is shared and runs (opener, correction or nudge, reply,
  translate, hints, summary). Missing: saved chat history and the list screen, voice input,
  TTS autoplay with word highlight, Stammtisch (noise, countdown bar), phrase library and
  phrase-to-deck, review deck, say-it, conversation-quality stats, recruiter/job context.
- **Needed:** a `ConversationHost` and `TutorChatRecord` on the Android store (the protocols already
  exist in `Services/Tutor/ConversationHost.swift`). `SpeechInput` through a Kotlin-bridged
  `SpeechRecognizer`. A `SpeechOutput` with `onWord` (UtteranceProgressListener.onRangeStart) and a
  `startBackgroundNoise` (MediaPlayer). Port the iOS views (SelectableGermanText/TappableText need
  a Compose-friendly tap-a-word substitute).
- **Effort:** M for history and Stammtisch, once the store and STT exist. **Deps:** persistence, STT, TTS++.

### Stories (Kurzgeschichten: read / listen, quiz, glossary, illustrations)
- **Purpose:** the tutor writes a CEFR-levelled story with questions and a glossary. The learner
  reads it or listens to it (with word highlight and lock-screen playback), takes the quiz, and
  the results feed stats and the streak.
- **Files:** `Features/Stories/*` (19 files, 5.5k lines), `Services/StoryStudyService(+Prompt)` (949 lines,
  10 model calls), `StoryBackgroundGenerator` (BGTask), `StoryImageService` (CoreML StableDiffusion),
  `StoryProgressService`, `StorySpeechSegmenter`. `StoryStarterService` and `StoryReadingTimer` are
  already in the core.
- **Apple-only:** SwiftData (`StudyStory`, `StoryQuizAttempt`, `StoryReadingSession`,
  `GeneratedKasusStory`), NaturalLanguage (segmenting), AVSpeech + MediaPlayer (now playing),
  BackgroundTasks, CoreML diffusion.
- **Android: Missing.**
- **Needed:** move the prompt and parse code out of StoryStudyService into the core behind
  `TutorGenerating` (TUTOR_CORE_PLAN phase 2, the next item). Replace the NaturalLanguage sentence
  splitter with a pure-Swift one. TTS needs a segment queue, per-speaker voices (`Voice` selection)
  and a MediaSession for background playback. Generation in a foreground service/WorkManager so
  a 1–3 min run survives backgrounding. Pictures: leave them out at first, or use OpenRouter cloud
  pictures (`Services/Cloud`, Foundation only, but the key lives in the Keychain; on Android that
  means Keystore/EncryptedSharedPreferences).
- **Effort:** L (M without pictures or background playback). **Deps:** persistence, tutor core
  split, TTS++, model download.

### Schreiben (Tagebuch / Aufsatz)
- **Purpose:** a journal and essays. Each piece gets a sentence-by-sentence tutor check, a
  score, a lookup sheet and coach notes. On iPad, a Pencil page plus "read my handwriting".
- **Files:** `Features/Schreiben/*` (13 files, 2.5k lines, 8 model call sites),
  `Services/Schreiben/*` (`WritingDiff`, `WritingSentences` are in the core; `WritingTutorCheck`,
  `WritingCheckRunner`, `WritingPromptBank`, `JournalInkReader` (Vision), `JournalInkStore`).
- **Apple-only:** SwiftData (`JournalEntry`), PencilKit, Vision (handwriting), UIKit.
- **Android: Missing.**
- **Needed:** split out `JournalKind` and `WritingSentenceCheck` (listed in ANDROID_PORT "next
  splits"). Move WritingTutorCheck's prompt and parse into the core. Typed input comes first.
  Ink later, via a Compose canvas or androidx.ink, with handwriting read by ML Kit Digital Ink
  Recognition (de). PKDrawing ink won't open on Android, so ink needs its own stroke format; sync
  either leaves ink out or converts it.
- **Effort:** M typed, +M with ink. **Deps:** persistence, tutor core split.

### Schreibblatt (writing sheet: "five tables of five")
- **Purpose:** a copying drill. A model table, then blank tables to fill in with the Pencil, or
  a printable PDF. Nothing is graded. Includes checkpoints, a crib sheet and a 3D Figur celebration.
- **Files:** `Features/Schreibblatt/*` (13 files, 3.7k lines), `Services/Schreibblatt{Layout,Renderer,PDF,
  InkStore,Practice,TableNav}`. `SchreibblattParts` and `SchreibblattStats` are already in the core.
- **Apple-only:** SwiftData (`SchreibblattSheet`), PencilKit, PDFKit/CoreGraphics (render),
  RealityKit (Figur).
- **Android: Missing.** Its core math is shared.
- **Needed:** a store, an ink canvas, PDF export through `android.graphics.pdf.PdfDocument`
  (Kotlin bridge) plus a share intent. Show a 2D celebration in place of RealityKit.
- **Effort:** M. Ink is the hard part, and it helps a lot that the feature needs no OCR.
  **Deps:** persistence, ink module.

### ClassNotes (Deutschkurs: courses, entries, handouts, homework/worksheets, class loop)
- **Purpose:** keep what an outside class produces: courses, dated entries, homework and handouts
  (PDF, photo or text, read word by word, with translation). Each course builds its own deck.
  Worksheets turn a lesson PDF into homework you work in the app or on the slide, with an
  optional check. "Ask the teacher" and teacher reports.
- **Files:** `Features/ClassNotes/*` (30 files, **10.1k lines**, 11 model call sites),
  `Services/Worksheet/*` (14 files: parser, grader, PDF reader, ink readers),
  `HandoutTranslationService` (NaturalLanguage), `ClassMaterialStore`, `ClassTutorContext`.
  `WorksheetReviewPlan` and `ClassTutorContext+Prompt` are in the core.
- **Apple-only:** SwiftData (`ClassCourse`, `ClassEntry`, `ClassMaterial`), PDFKit (text layer +
  render), Vision (OCR + handwriting), PencilKit, QuickLook, PhotosUI, CoreText, UniformTypeIdentifiers.
- **Android: Missing.**
- **Needed:** the largest single content feature. Persistence. A PDF stack, which Android doesn't
  ship: PdfRenderer only rasterizes, so text-layer extraction needs pdfium/PDFBox-Android through
  a bridge. ML Kit Text Recognition (Latin) for photos. File and photo pickers (Skip has
  PhotosPicker/fileImporter equivalents; verify). Split `WorksheetExercise` and friends out of
  WorksheetParser. Ink for on-slide answers.
- **Effort:** L (courses, entries and homework alone: M). **Deps:** persistence, PDF/OCR module,
  tutor core split, deck store.

### JobPrep (job ad reader + interview + Lebenslauf)
- **Purpose:** study a Stellenanzeige word by word, keeping its lookups and its own deck, then
  start an interview prefilled from it. The résumé/Lebenslauf coach.
- **Files:** `Features/JobPrep/*` (12 files, 2.9k lines), `JobPostingSnapshotStore`, `JobDeckStore`,
  `Features/Conversation/JobPosting*` (clipper). `JobPostingScripts`, `JobReadingScripts`,
  `ResumePrompts` and `JobPostingCapture` are in the core.
- **Apple-only:** SwiftData (`JobPosting`, `Resume`), WebKit (web surface + clipper), PDFKit, PhotosUI.
- **Android: Missing.** Its prompts are shared already.
- **Needed:** a store, Android WebView (skip-web, or a bridge) with the JS clipper scripts (shared),
  the PDF module, an interview mode on the shared session. ResumeView's 4 model calls go into
  the core.
- **Effort:** M. **Deps:** persistence, WebView, PDF module (optional at first: paste text).

### Zeichnen (Bildermappe, Schnellskizze, Atelier, Malen nach Zahlen)
- **Purpose:** draw a word to remember it. Timed recall/copy sketches, a studio with tracing
  and halftone finishes, paint-by-number that teaches colour names, and a picture folder for each word.
- **Files:** `Features/Zeichnen/*` (14 files, 3.1k lines), `Features/Shared/Pencil/*` (PencilKit shared
  board), `Services/WordArt/*`. `GermanColorName`, `WordArtKey` and `WordArtStyle` are in the core.
- **Apple-only:** SwiftData (`WordArtwork`, `QuickDrawSet`, `WordDrawingStat`), PencilKit,
  CoreImage (halftone, region segmentation), image generation (CoreML SD / Mac / cloud).
- **Android: Missing.**
- **Needed:** the ink module (all four modes depend on it). Port CoreImage filters to
  pure Swift or android.graphics. A picture source (cloud first).
- **Effort:** L. **Deps:** ink module, persistence, image-gen decision.

### DocumentDeck (flashcards from a document)
- **Purpose:** pair a teacher's vocab sheet into cards (keeping ✓ marks, examples and plurals),
  or highlight phrases in any text. The tutor fills in missing English. Sources: file, photo,
  link or paste.
- **Files:** `Features/DocumentDeck/*` (3 files, 1.8k lines), `DocumentDeckService`, `OCRTableLayout`,
  `VocabListParser`, `PDFTextExtractor`, `WebTextExtractor`.
- **Apple-only:** SwiftData (`SavedDeck`, `SavedCard`), PhotosUI, Vision/PDFKit through the
  extractors, UIKit in WebTextExtractor.
- **Android: Missing.**
- **Needed:** a deck store (Library). Split `WordClass`/`VocabListRow` from VocabListParser. Make
  `OCRTableLayout` take plain boxes (ML Kit returns line boxes too). PDF module. Paste and link
  first.
- **Effort:** M. **Deps:** persistence (decks), OCR/PDF module, tutor core split.

### PhotoScan & Paper (study a photo / PDF / web article with the tutor)
- **Purpose:** import a photo (Vision OCR plus an AI cleanup pass), a PDF or a URL. Review the
  extracted text, then get a summary, key points and questions, a discussion with the tutor,
  and an optional deck.
- **Files:** `Features/PhotoScan/PhotoScanListView.swift` (384), `Features/Paper/*` (4 files, 1.4k),
  `PhotoOCRService` (Vision), `PaperStudyService` (4 model calls), `PDFTextExtractor`,
  `ScannedPDFReader`, `WebTextExtractor`.
- **Apple-only:** SwiftData (`StudyPaper`), Vision, PDFKit, WebKit, PhotosUI, camera (UIKit).
- **Android: Missing.**
- **Needed:** one shared "text intake" module covering ML Kit OCR, the PDF text layer and URL
  fetch plus readability, used by DocumentDeck, ClassNotes and JobPrep too. Prompts into the core.
- **Effort:** M (S once the intake module exists). **Deps:** intake module, persistence.

### Queue (batch generation overnight)
- **Purpose:** queue decks, stories and picture passes, then run them all with one tap, with
  Pause/Stop. It swaps the LLM and diffusion models in and out because they don't fit in memory together.
- **Files:** `Features/Queue/*` (3 files, 1.5k), `BatchQueueService` (441, BGTasks), `Models/BatchJob`.
- **Apple-only:** SwiftData (`BatchJob`), BackgroundTasks, diffusion.
- **Android: Missing.**
- **Needed:** WorkManager (long-running, foreground service type `dataSync`/`shortService`) bridged
  to the Swift runner. Text jobs only until image generation exists.
- **Effort:** M. **Deps:** deck generation + stories on Android, persistence, notifications.

### Keyboard extension (German writing keyboard)
- **Purpose:** a system keyboard with German keys, a suggestion strip (UITextChecker), and
  transforms (rewrite/fix/translate) through `GermanWriter` on FoundationModels (Apple
  Intelligence), plus probe/diagnostic panels.
- **Files:** `KeyboardExtension/*` (12 files), `Services/GermanWriter.swift`, Settings ▸ Keyboard.
- **Apple-only:** UIInputViewController, UITextChecker, FoundationModels, App Group memory.
- **Android: Missing.**
- **Needed:** an Android `InputMethodService` (Kotlin, with a Compose view inside the IME). Spelling
  through Android's `SpellCheckerSession` or a bundled dictionary. Transforms would need llama.cpp
  inside the IME process, and a 1.5–3 GB model in a keyboard process is risky on 4–6 GB phones.
  A better first step is an "open in Die Kartei to fix" action through the share/PROCESS_TEXT
  intent (ACTION_PROCESS_TEXT gives a text-selection menu item almost for free).
- **Effort:** S for PROCESS_TEXT, L for a full IME. **Deps:** tutor core (GermanWriter prompts into core).

### Sync
- **Purpose:** the learner's progress and content follow them across their own devices through
  the private CloudKit database (CKSyncEngine, merges field by field with per-device counters).
- **Files:** `Services/Sync/*`. The `Core/` part (7 files: merge, record logic, counters,
  digest, fake server) is shared. `Codecs/` holds 12 files, 2.9k lines, with **30 codecs**
  (every @Model except SyncMeta, SyncRecordState, BatchJob, and a couple of local-only types).
  SyncManager/CloudKitSyncTransport are CloudKit + CoreData + SwiftData.
- **Android: Missing.** The merge engine compiles for Android.
- **Plan (sync.mdx):** (1) an iOS-shaped record store with iOS ids, (2) Android Auto Backup,
  (3) Google Drive app-folder transport, one file per device. iPhone↔Android comes later.
- **Key observation:** each codec's `spec` plus its `known()` field list *is* a portable schema for
  that model. If the Android store persists **SyncPayload-shaped records** (see §2.1), sync becomes
  a transport problem, and an Android-made record is iOS-readable by construction.
- **Effort:** step 1 M (it is the persistence work, §2.1), step 2 S, step 3 M plus a Google Cloud
  project/OAuth. **Deps:** persistence.

### Notifications / reminders
- **Purpose:** "done" banners for model downloads and stories (`LocalNotificationService`), and
  opt-in practice reminders that space out the longer the learner stays away
  (`PracticeReminderService`, based on the last activity in StudyDay).
- **Apple-only:** UserNotifications, SwiftData (StudyDay).
- **Android: Missing.**
- **Needed:** a small Kotlin-bridged module (like GermanVoice) with a NotificationChannel,
  `POST_NOTIFICATIONS` runtime permission (API 33+) and WorkManager `OneTimeWorkRequest` with an
  initial delay and a unique name (replace = no duplicates; survives reboot). The checkpoint
  ladder logic is Foundation-only once split from its SwiftData query. Settings ▸ Reminders.
- **Effort:** S–M. **Deps:** a last-activity source (StudyDay twin).

### Themes / design system
- **Purpose:** four app-wide themes (Klar/System, Sanft/Soft, Kritzel/Notebook, Grundform/Bauhaus)
  from `Models/AppTheme.swift` (313 lines) and `Features/Shared/ThemeEnvironment.swift` (334).
  `.themedScreen/.themedCard/.themedListRow/.themedListScreen` (about 156 files use
  `themedListScreen`), `.themedTitle/.themedNumber`, the Kritzel ruled-paper background, the
  per-model `ModelTheme` accent, `SettingsHeader` (morphing SF Symbol title), and a custom
  `App/NavBar.swift` (269: tabs, pie download badge).
- **Android: Missing.** It has a plain Material look, an Appearance light/dark picker, and
  `AndroidPalette` (a copy of the gender/case hexes).
- **Portability through Skip:** the tokens (colours, radii, shadow values, uppercase headers) are
  plain values and port directly once they're free of `UIColor`/`Color(.systemGroupedBackground)`
  (put them behind `#if canImport(UIKit)`). Custom fonts: Noteworthy, Bradley Hand, Marker Felt and
  Futura are **Apple system fonts** that Android doesn't have. Bundle OFL substitutes (Patrick Hand
  or Caveat for Kritzel, Jost or League Spartan for Bauhaus) and resolve them by name. SF Rounded
  can become Nunito, or Compose's default. Background `Canvas`/`Path` drawing (ruled lines) works in
  SkipUI. `.symbolEffect`, `contentTransition(.symbolEffect)` and many SF Symbols don't map (the
  README warns about missing symbols), so SettingsHeader needs a simpler variant. `listRowBackground`
  and section clip radii behave differently in Compose lists. The custom NavBar could reuse
  `PieProgress` (a Shape, which ports) inside a TabView. Expect about 70% of ThemeEnvironment to
  compile after a split. Kritzel's "hand-drawn" feel depends on the fonts.
- **Effort:** M (tokens + 2 themes S; full parity M). **Deps:** none. Can run in parallel.

### Model management (Settings ▸ Model, download)
Covered in §2.2.

---

## 2. Cross-cutting

### 2.1 Persistence (the biggest blocker)
- **35 `@Model` types; 262 files import SwiftData:** ArchivedMemoryItem, ArticleRound,
  ArticleWordStat, BatchJob, ChatConversation, ChatMessage, ClassCourse, ClassEntry,
  ClassMaterial, GeneratedKasusStory, HoerenRound, JobPosting, JournalEntry, KasusRound,
  LearnedPhrase, LearnerProfile, MatchingPairStat, MatchingRound, PrepositionRound,
  PrepositionStat, QuickDrawSet, QuizResult, Resume, SavedCard, SavedDeck, SchreibblattSheet,
  StoryQuizAttempt, StoryReadingSession, StudyDay, StudyPaper, StudyStory, SyncMeta,
  SyncRecordState, WordArtwork, WordDrawingStat.
- **In this audit's scope:** Conversation (ChatConversation, ChatMessage, LearnedPhrase), Stories
  (StudyStory, StoryQuizAttempt, StoryReadingSession, GeneratedKasusStory), Schreiben (JournalEntry),
  Schreibblatt (SchreibblattSheet), ClassNotes (ClassCourse, ClassEntry, ClassMaterial), JobPrep
  (JobPosting, Resume), Zeichnen (WordArtwork, QuickDrawSet, WordDrawingStat), Paper/PhotoScan
  (StudyPaper), Queue (BatchJob). All of them sit on the shared spine: SavedDeck/SavedCard,
  StudyDay, LearnerProfile, QuizResult.
- **Android today:** `StudyStore` writes a JSON blob to UserDefaults, keyed `A1:word`, which
  doesn't match the iOS ids. It won't scale past SRS state.
- **Recommended plan:**
  1. **Plain-value twins in the core** for each model family (`struct JournalEntryRecord`…), or
     more cheaply, **SyncPayload records** keyed by `SyncRecordName`. Move each codec's
     `spec` and field names into `Services/Sync/Core`, as sync.mdx step 1 already plans for
     SavedCardCodec.
  2. **Store protocols per aggregate** in the core (`DeckStoring`, `ConversationStoring` (already
     done as ConversationHost), `JournalStoring`, `StoryStoring`, `StudyLogStoring`…). iOS adapts
     its SwiftData models to them gradually, which also unlocks moving services like
     PaperStudyService and StoryStudyService into the core.
  3. **Android backend: SkipSQL** (bundled SQLite, works from native Swift on Android). Add it
     to `Package.swift`. Schema: a generic `records(kind, id, payload JSON, server_copy,
     pending, updated_at)` table plus a few typed index columns (deckID, day, dueDate) for
     queries. This matches sync.mdx's `SyncRecordCopies`, so sync step 1 comes free. Large blobs
     (ink, images, PDFs) go in files, as on iOS (`*InkStore`, `ClassMaterialStore`).
  4. Migrate `StudyStore` to iOS card ids (`SyncSingletonDecks.cardID`) once.
- **Risk:** the 262 SwiftData files on iOS mean the shared *services* stay iOS-only until they
  take protocols. Do it by feature (TUTOR_CORE_PLAN's pattern), not as a big-bang rewrite.
- **Effort:** L in total. The spine (decks/cards, StudyDay, LearnerProfile, chats) is M.

### 2.2 Model download & management (GGUF)
- **iOS:** `MLXModelManager` (517 lines: provider, selected model, voices, picture prefs),
  `ResumableModelDownloader` (883: background URLSession, resume, hands files to HubCache),
  `ModelSettingsView` (1,415), onboarding hero/model-update sheets, RAM tiers in `MemoryBudget`
  and `DeviceCapability`, `ModelSupersession`/`OrphanedModelCache` cleanup, and download notifications.
- **Android:** `TutorModelFile` table in `TutorStore.swift`. Files go in `files/models/` by
  adb. The settings screen says "downloads come once the models are on Hugging Face".
- **Blocker:** the GGUFs aren't published yet (needs an HF login on the Mac mini; TUTOR_CORE_PLAN
  phase 3/4).
- **Needed:** (a) extend `MLXModel` in the core with GGUF repo/file/bytes/SHA-256/min RAM/quant
  and delete `TutorModelFile`. (b) A downloader: use Android `DownloadManager` through a Kotlin
  bridge, which survives process death and resumes on its own, into
  `getExternalFilesDir`, then verify SHA-256 and move to `files/models`. Or use WorkManager plus
  HTTP Range in Swift. (c) RAM gating from `ActivityManager.MemoryInfo.totalMem`, using the same
  floors as iOS (E4B 8 GB, E2B 6 GB, Granite 4 GB). (d) A storage check (StatFs). (e) Progress in
  the UI and a notification. (f) A delete/replace flow.
- **Effort:** M. **Deps:** HF publishing (external), notifications module.

### 2.3 Speech
- **TTS: Partial.** `GermanVoice` does speak(text, slow), stop, and opens the system voice
  settings. Missing for parity: word-range callbacks (`onRangeStart`) for highlighting, a segment
  queue with per-segment `Voice` (dialogue stories), pause/resume/seek, MediaSession for
  lock-screen story playback, the Stammtisch noise bed, and a voice picker (`getVoices()`
  filtered de-DE). Implement the shared `SpeechOutput` protocol. **Effort:** M.
- **STT: Missing.** iOS `SpeechRecognitionService` (320 lines: on-device, partials, level meter,
  restart, punctuation). Android: `SpeechRecognizer` with `EXTRA_LANGUAGE=de-DE`,
  `EXTRA_PARTIAL_RESULTS`, and `createOnDeviceSpeechRecognizer` (API 31+) or `EXTRA_PREFER_OFFLINE`.
  `onRmsChanged` gives the level. RECORD_AUDIO permission. On-device German needs the language
  pack, so detect it and send the learner to settings. It must be driven from the main thread on
  the Kotlin side. Implement `SpeechInput` (already defined in the core). **Effort:** S–M.
  It unlocks voice Gespräch, Say-it, Stammtisch and Hören checks.

### 2.4 Design system / themes
See the Themes section above. In short: tokens port, Apple fonts don't (bundle OFL faces), and
SF Symbols/symbol effects partly don't. Split `AppTheme` into a Foundation+SwiftUI token file
with no UIKit. Then `.themed*` modifiers compile in SkipUI with small `#if os(Android)` branches.
Do this **before** porting many more screens, or every ported screen will need re-theming later.

### 2.5 Sync
See the Sync section above. Persistence step 3 (a record-shaped store) is sync.mdx step 1, so do
them together. Auto Backup (S) gives "new phone keeps progress" well before Drive sync.

### 2.6 Other shared enablers found
- **Text intake module** (OCR + PDF text + URL readability + pickers/camera), used by PhotoScan,
  Paper, DocumentDeck, ClassNotes and JobPrep. Kotlin bridge: ML Kit Text Recognition v2 (Latin),
  pdfium/PDFBox-Android, OkHttp/WebView for fetching. **Effort:** M.
- **Ink module** (Compose canvas or androidx.ink, a stroke model, PNG/PDF render, and ML Kit
  Digital Ink Recognition for de), used by Schreiben, Schreibblatt, Worksheets and Zeichnen.
  **Effort:** L. Cross-platform ink sync needs a neutral stroke format.
- **Tutor core split (phase 2 continuation):** StoryStudyService (10 calls), PaperStudyService (4),
  Resume (4), WritingTutorCheck, DocumentDeck translation, worksheet check, handout translation
  (NaturalLanguage → pure Swift), GermanWriter. Each is prompt + parse into the core, with storage
  and UI staying outside. **Effort:** M overall, done one feature per commit.
- **Image generation:** CoreML StableDiffusion, the Mac handoff and Apple Intelligence aren't
  available on Android. The cloud route (OpenRouter, `Services/Cloud`, Foundation only plus the
  Keychain) is the realistic one. On-device diffusion on Android isn't worth it now.
- **Background work:** BGTasks for story generation and the queue become WorkManager or a
  foreground service (Kotlin bridge). Long llama.cpp runs need a foreground service to avoid
  being killed.

---

## 3. Summary table

| Feature | Android | Effort | Blocking deps |
|---|---|---|---|
| Conversation / tutor | Partial (typed, in-memory) | M | persistence, STT, TTS++ |
| Stammtisch | Missing (logic shared) | S after STT/TTS | STT, TTS noise |
| Stories | Missing | L | persistence, core split, TTS++, model DL |
| Schreiben | Missing | M (+M ink) | persistence, core split, (ink) |
| Schreibblatt | Missing (math shared) | M | persistence, ink, PDF export |
| ClassNotes + Worksheets | Missing | L | persistence, intake, ink, decks |
| JobPrep + Lebenslauf | Missing (prompts shared) | M | persistence, WebView, (PDF) |
| Zeichnen | Missing | L | ink, persistence, images |
| DocumentDeck | Missing | M | deck store, intake |
| PhotoScan / Paper | Missing | M | intake, persistence |
| Queue | Missing | M | stories/decks, WorkManager |
| Keyboard | Missing | S (PROCESS_TEXT) / L (IME) | tutor core |
| Sync | Missing (merge engine shared) | M + S + M | persistence |
| Notifications | Missing | S–M | StudyDay twin |
| Themes | Missing | M | none |
| Model download | Missing (adb only) | M | HF publishing |
| STT | Missing | S–M | none |
| TTS parity | Partial | M | none |

---

## Foundations first (ordered)

1. **Merge `android-port` into `main`** (15 ahead, 1 behind). Every later split touches iOS files,
   so landing them on a side branch gets more expensive with time (ANDROID_PORT and TUTOR_CORE_PLAN
   both say this).
2. **Persistence spine:** core store protocols plus a SkipSQL record store shaped like
   SyncPayload, with codec specs moved into `Sync/Core`. Start with decks/cards (iOS ids +
   StudyStore migration), StudyDay, LearnerProfile, ChatConversation/ChatMessage. This also
   delivers sync.mdx step 1.
3. **Model catalog + GGUF download** (publish to HF, extend `MLXModel`, DownloadManager, SHA-256,
   RAM gating). Without it no real user can reach any AI feature.
4. **Speech:** STT through SpeechRecognizer (`SpeechInput`), and a fuller TTS (`SpeechOutput`:
   ranges, segments, voices, MediaSession).
5. **Theme tokens + fonts + themed modifiers on SkipUI** (in parallel with 2–4). Do it before the
   screen-porting wave.
6. **Tutor core split, per feature:** Stories → Schreiben check → PaperStudy → DocumentDeck
   translate → Resume → worksheet/handout.
7. **Platform modules (Kotlin-bridged, GermanVoice pattern):** notifications/WorkManager (S), then
   text intake (OCR/PDF/URL) (M), then the ink module (L).
8. **Auto Backup** (S), then **Drive sync** (M, needs a Google Cloud project/OAuth).

## Top gaps by user impact

1. **No persistence for AI content.** Chats, phrases, stories and journal entries vanish, and
   there is no Library of user decks. That kills retention for every AI feature.
2. **No in-app model download.** The tutor only works for someone using adb, so for real users
   every AI feature is effectively Missing.
3. **Stories (read + listen + quiz).** The flagship comprehension feature, covering exam Lesen
   and Hören. Fully Missing.
4. **Voice conversation (STT) and Stammtisch.** The tutor can't hear you yet, and speaking is the
   hardest skill the app trains.
5. **Schreiben (typed journal/essay check).** High value, and small once persistence and the
   check prompt are in the core. Leave ink for later.
6. **Content import → decks** (DocumentDeck, PhotoScan/Paper, ClassNotes). Turns real-world
   material into study. They share one intake module.
7. **Themes/identity.** Android looks like a stock Material demo. Cheap to improve, and it
   affects every screen.
8. **Reminders/notifications.** A small effort with a direct effect on streaks and retention.
9. **Sync / backup.** Auto Backup is quick insurance. Cross-device sync matters less until
   people use Android on more than one device.
10. **Ink-based features** (Schreibblatt, Zeichnen, handwriting, worksheets on the slide), and
    then the **keyboard**. They're distinctive, but they cost the most and matter most on tablets.
    PROCESS_TEXT is a cheap stand-in for the keyboard.
