# Settings parity audit — iOS (main) vs Android (Skip Fuse, android-port)

iOS root: `german-ai-flashcards/Features/Settings/` (abbrev. `iOS/`). Android: `DieKarteiAndroid/Sources/DieKartei/SettingsView.swift` (177 lines, abbrev. `A/SV`) + `TutorViews.swift:10-75` (TutorModelView).
Most iOS prefs live on `MLXModelManager` (`Services/MLXModelManager.swift`, UserDefaults keys in `didSet`, init at L399-515) — **not in core_files.txt**, so Android re-declares its own keys.

## Structure & visuals

| Aspect | iOS | Android |
|---|---|---|
| IA source | `SettingsPane.swift` enum (17 cases, groups Account/App/Learning/Model/About/Developer, L28-45); shared by iPhone list and Mac Settings window | Hand-written `List` with 3 sections App/Learning/About (`A/SV:16-56`) |
| Row | `SettingsPaneRow` (`SettingsPane.swift:200-221`): `Label(title, systemImage:)` + trailing grey `.caption` summary; model row shows `DownloadBadge` while loading | Plain `Text` NavigationLinks, no icons, no summaries; two rows are *inline Pickers* (Appearance, Your Level) instead of push screens |
| Header | `SettingsHeader` (`Features/Shared/SettingsHeader.swift`) — large bold centered title + tinted SF Symbol morphing from `circle.dotted` via `.symbolEffect(.replace)`, on root and every pushed screen; inline nav bar | `.navigationTitle("Settings")` (Material top bar) on each screen; no header row |
| Theming | `.themedListScreen()` / `.themedListRow()` / `.themedSectionHeader()` (App/ContentView.swift) follow `AppTheme` | Default Compose list styling |
| Deep links | `App/SettingsRouter.swift`: `SettingsRoute` .model/.cards/.memory/.sync/.voice → `navigationDestination(item:)` (`SettingsView.swift:66`); re-tap tab pops to root via `resetToken` | None; Tutor views say "pick one in Settings ▸ Tutor Model" as text only (`TutorViews.swift:94`) |
| Extras | About has "Rate on the App Store" Link (`SettingsView.swift:43-50`) | About has a "Version" row (not on iOS); footer "Not on Android yet: iCloud Sync, Reminders and themes." (`A/SV:51-55`) |

Order iOS: Account[iCloud Sync] · App[Appearance, Reminders, Voice, Tastatur, (Mac: Schreibhilfe), Gamification] · Learning[Your Level, Flashcards, Conversation, Stories] · Model[Model & Downloads, Speicher] · About[What's New, Sources & Credits, Send Feedback, Rate] · Developer[Screenshot Data].
Order Android: App[Appearance picker, Voice] · Learning[Your Level picker, Flashcards, Tutor Model] · About[Sources & Credits, Version]. Note "Tutor Model" sits in Learning (iOS: own "Model" group, titled "Model & Downloads").

Suggested approach (M): port `SettingsPane`-style enum into Android (or move a Foundation-only `SettingsPane` metadata file into core — destinations stay per-platform). Add icons (SkipUI maps a subset of SF Symbols → Material; fallback icons needed for e.g. `figure.stairs`, `memorychip`), trailing summaries, a Compose-safe `SettingsHeader` (drop `symbolEffect`, keep big title + icon), and a simple `SettingsRoute` binding.

---

## Per-pane audit

### 1. iCloud Sync (Account) — `iOS/ICloudSyncSettingsView.swift` (351 L)
- Controls: Toggle "Sync with iCloud" (L30); "Sync Now", "Repair Sync" buttons (L53-62); NavigationLink "Sync report" (`SyncReportView`); warning label after repair; destructive "Delete iCloud Data" + alert (L95,134); "Not syncing?" section with open-Settings button (L109); "Events" log; "What syncs / In your iCloud" storage breakdown (L244); "Your devices" (L311); "Different Apple Account" choice: "Add this device's data…" / "Keep this device separate (sync off)" (L332-339).
- Storage: `SyncManager.shared` (isEnabled, refusalReason, account, engineBusy). Row summary Off / Not signed in / Syncing… / On.
- Android: **Missing** (named in footer).
- Blockers: CloudKit + SwiftData. Portable merge logic already in core (`Services/Sync/Core/*`).
- Approach: per `docs-site/content/docs/android/sync.mdx` — Step 2 Android Auto Backup (no UI, S), Step 3 Google Drive appDataFolder sync with a settings row "Google account, last sync, Sync now, Remove synced data" (L71). Needs Google Cloud project/OAuth + a Kotlin sign-in module. Rename pane "Sync" / "Google Drive Sync". Effort **L** (UI itself S).

### 2. Appearance (App) — `iOS/ThemePickerView.swift`, `Models/AppTheme.swift`
- Controls: 2-column grid of 4 theme tiles (sample "Hallo" in theme title font, swatch strip, checkmark in accent): System (`klar`), Soft (`sanft`), Notebook (`kritzel`), Bauhaus (`grundform`) — `AppTheme.swift:23-50`. Picker "3D scenes": Automatic / Stills Only / Always 3D (L55-74). Mac only: "Navigation" Sidebar/Tab bar segmented.
- Storage: `@AppStorage("app.theme")`; `UserDefaults "lightweightGraphicsMode"` (`Services/LightweightGraphics.swift`); Mac `MacNavigationStyle.defaultsKey`.
- Depends: every screen reading `\.appTheme` (backgrounds, card fill/border/radius/shadow, fonts); 3D mode gates RealityKit Die Figur / preposition scenes.
- Note: iOS has **no** light/dark override — follows system.
- Android: **Partial / different control.** Inline Picker "Appearance": System / Light / Dark under key `"appearance"` (`A/SV:9,18-22`, applied in `ContentView.swift:18-26`). No themes, no 3D-scenes picker.
- Blockers: `AppTheme` not in core (uses SwiftUI `Color(light:dark:)`, custom fonts, `ThisDevice`); Android has no RealityKit scenes so "3D scenes" is meaningless today. Mac navigation: meaningless.
- Approach: split `AppTheme` tokens (hex values, radii, border widths) into a Foundation-only core file; Android `themedList*` equivalents; theme tile grid. Keep System/Light/Dark as an Android-only extra (Material users expect it) — or add it to iOS. Ship custom fonts (SF Rounded → e.g. Nunito; Notebook hand font). Effort **M-L**.

### 3. Reminders (App) — `iOS/ReminderSettingsView.swift` (109 L)
- Controls: Toggle "Practice reminders" (L20); when on: notifications-denied warning + "Open Settings" (L29-50); section "Remind me if I haven't practiced in…" with one Toggle per checkpoint: day, 3 days, week, 2 weeks, month (`Services/PracticeReminderService.swift:8-12`).
- Storage: `practiceRemindersEnabled`, `practiceReminderCheckpointsRaw`. Summary "Off" or "1 day · 3 days…". Reschedules via `PracticeReminderService` on change; resets when the user practices.
- Android: **Missing** (named in footer).
- Blockers: `UNUserNotificationCenter`. Needs Android `POST_NOTIFICATIONS` runtime permission (API 33+), WorkManager/AlarmManager scheduling, a "last practiced" timestamp hook in StudyStore.
- Approach: small Kotlin/Skip bridge module (like `GermanVoice`) for schedule/cancel + permission; reuse checkpoint enum (move `ReminderCheckpoint` into core). Effort **M**.

### 4. Voice (App) — `iOS/VoiceSettingsView.swift`, `DialogueVoicePickerSection.swift`
- Controls: "Download your voices" section (voices chosen on another device but missing; "Show me how") (L89-115); "Pronunciation": Picker "German Voice" (System Default + installed voices, missing-voice row) (L24); Button "Preview Voice"; natural-voice notice / "You downloaded these" list; "How to download natural German voices" → `VoiceGuideSheet` (in CardSettingsView.swift:197). "Dialogue Voices": Pickers "Man's voice", "Woman's voice", (Children's voices) "Boy's voice", "Girl's voice".
- Storage: `selectedVoiceIdentifier`, `voiceMale/Female/Boy/GirlIdentifier`, `voices.setAt` stamp (synced). Summary "N to download". Used by all TTS, Dialogue/E-Mail stories.
- Android: **Partial.** `A/SV:69-94`: buttons "Probehören", "Langsam" (slow sample — iOS has no slow preview), "Android voice settings" (opens TTS settings via `GermanVoice.openSystemVoiceSettings()`). No voice picker, no dialogue voices, no summary.
- Blockers: AVSpeechSynthesisVoice → Android `TextToSpeech.getVoices()` (needs bridge in `GermanVoice` module). Dialogue voices only matter once Stories exist on Android.
- Approach: expose `TextToSpeech.voices` filtered to `de-*` (quality/network flags → "natural" badge), Picker "German Voice"; defer dialogue voices until stories port. Effort **S-M**.

### 5. Tastatur · Keyboard (App, iOS only) — `iOS/KeyboardSettingsView.swift`
- Content: setup instructions only ("Turn it on", "Use it" sections, "It never asks for Full Access", "Open Settings" button). Keyboard extension turns English into German via Apple Intelligence. Summary `GermanKeyboard.summary` (enabled or not).
- Android: **Missing.** Equivalent = an Android IME (`InputMethodService`). Blockers: FoundationModels (Apple Intelligence) — would need llama.cpp in an IME process (memory-heavy) or umlaut/ß-only keyboard. Approach: defer; if done, settings screen links `Settings.ACTION_INPUT_METHOD_SETTINGS` and checks enabled IMEs. Effort **L**.

### 6. Schreibhilfe · Writing helper — Mac only (`MacWritingHelperSettingsView.swift`). **N/A on Android.** (Closest Android analogue: `ACTION_PROCESS_TEXT` text-selection action; not a settings priority.)

### 7. Gamification (App) — `iOS/GamificationSettingsView.swift` (95 L)
- Controls: Toggle "Gamification"; Picker "Daily goal" (N min) under "Tagesziel · Daily Goal"; Toggles "Celebrations", "Badges (Abzeichen)", "Learning pyramid", "„Weißt du es noch?“"; "Einstufung · Placement": "Take/Retake the placement check" sheet + NavigationLink "Your checks".
- Storage: `gamificationEnabled`, `dailyGoalMinutes`, `gamificationCelebrationsEnabled`, `gamificationBadgesEnabled`, `gamificationPyramidEnabled`, `gamificationRememberProbeEnabled`. Summary "N min/day" / Off. Drives Home level card, Tagesziel ring, badges, Lernpyramide, Dein Weg probe.
- Android: **Missing** — and Android Home has none of those features (HomeView is a deck summary + activity rows).
- Blockers: feature itself not ported (badges/pyramid read SwiftData study history). Approach: port Tagesziel ring first (study minutes from StudyStore), then this pane. Effort **M** (pane S once features exist).

### 8. Your Level (Learning) — `iOS/LevelSettingsView.swift` (115 L)
- Controls: `LevelChoiceList` under "Wie gut sprichst du? · Your German" (CEFR A1–C1 with descriptions, `Models/ConversationConfig.swift:40`); "Nicht sicher? · Not sure": "Use my check's estimate (X)", "Take the check again" / "Take the three-minute check" (placement sheet); placement result row "Your check said X".
- Storage: `german.level` (CEFRLevel raw), `german.level.declared`, `german.level.setAt`; `PlacementService.current`. Summary "B1 · Intermediate". Seeds Conversation, Stories, queued jobs, Goethe screens.
- Android: **Partial.** Inline Picker "Your Level" over **GoetheLevel A1/A2/B1** under key `"level"`, mirrors into `"hoerenLevel"` (`A/SV:11-13,28-33`). Read by Home/Karten/Wortschatz/Grammatik/Spiele.
- Differences: different key + enum (no B2/C1, no English label, no declared flag), not a push screen, no placement check, no summary.
- Blockers: placement quiz (`PlacementService`/sheet) not in core — but `PlacementResult.swift`, `PlacementAttempt.swift` are. Approach: push screen with CEFR list (clamp to B1 for Goethe decks), store under `german.level` for future sync parity; port placement quiz UI. Effort **S** (level) + **M** (placement).

### 9. Flashcards (Learning) — `iOS/CardSettingsView.swift` (303 L) via `FlashcardsSettingsScreen`
- "Flashcard Style": Picker "Style" (FlashcardStyle cases), Toggle "Auto-advance", Picker "Front side" German/English, Toggle "Ask der / die / das first", Toggle "Repeat missed cards", Toggle "Write it after a miss" (Apple Pencil, if available), Toggle "AI pictures on new decks" + Picker "Draw pictures for" (CardImageTiming) — only if `PictureEngine.isReady`.
- "Wortschatz · Goethe": Picker "Study with" (style), "New words per day", "Cards per session".
- "Haptics": Picker "Game vibrations" (HapticFeedbackMode).
- "Card Matching": Picker "Pairs per round", Toggles "Bring back tricky pairs", "Share tricky words with the coach".
- "Der · Die · Das": Toggle "Share missed nouns with the coach". "Präpositionen": Toggle "Share tricky prepositions with the coach".
- Keys: `flashcardStyle`, `autoAdvance`, `cards.germanFirst`, `cards.articleQuiz`, `cards.repeatMissed`, `cards.writeAfterMiss`, `flashcardIllustrationsEnabled`, `cardImageTiming`, `wortschatz.style|newPerDay|sessionCap`, `hapticFeedbackMode`, `matchingPairCount|TrickyFirst|FeedsCoach`, `articleFeedsCoach`, `prepositionsFeedCoach`.
- Android: **Partial.** `A/SV:99-146`: Picker "New words per session" 5/10/15/20/30 (key `flashcards.newPerSession` — iOS analogue `wortschatz.newPerDay`/`sessionCap`, different semantics) + "Progress" list per Goethe level with "Reset" + confirm alert. (Per-level reset has no iOS counterpart in this pane.)
- Blockers: Write-after-miss = PencilKit/Vision (Missing; could use Compose canvas + ML Kit Digital Ink, L). AI pictures = image-gen (MLX/Core ML / OpenRouter) — Missing. Coach toggles need the Coach/learner memory (SwiftData). Card Matching game not on Android. Portable now: `FlashcardStyle`, `HapticFeedbackMode`, `CardImageTiming` are in core; `CardStudyPrefs` is not (Foundation-only — add to core).
- Approach: add Front side, Ask der/die/das, Repeat missed, Auto-advance, Haptics (Android Vibrator via SkipUI `sensoryFeedback`?) to KartenView + this screen; use iOS keys. Effort **S-M**.

### 10. Conversation (Learning) — `iOS/ConversationSettingsView.swift` (240 L)
- "You": TextField "Your name" (`learnerName`). "Level": link to Your Level w/ summary. "Corrections": Toggle "Show suggested corrections", "Show English meaning", Picker "Strictness", Picker "Feedback". "Speak or type": Picker "Your turns" (`chatInputModeRaw`). "Voice": Toggle "Auto-play AI replies". "Learning aids": Picker "Hints per request", Toggles "Hint every turn", "Color noun genders", "Auto-translate & pre-load hints", "Auto-show translations". "Coaching": Toggles "Personalized coaching", "Use my class notes", link "Coach's Notes" (`CoachNotesView`). "Spaced review": Toggle + Picker "Where". "Phrases": link "Phrase library".
- Keys: `learnerName`, `chatCorrectionsEnabled`, `chatShowCorrectionTranslation`, `chatStrictnessRaw`, `chatFeedbackStyleRaw`, `chatInputModeRaw`, `autoPlayReplies`, `chatHintCount`, `chatAutoHints`, `chatGenderColors`, `chatEagerAssist`, `chatAutoShowTranslation`, `chatPersonalizedCoaching`, `classFeedsCoach`, `chatSpacedReview`, `chatSpacedReviewScopeRaw` (also `chatFormalityRaw`).
- Android: **Missing** pane, though Gespräch exists: `TutorViews.swift:194-198` builds `ConversationConfig(model:)` with hard-coded `inputMode = .type` and defaults — no prefs read.
- Blockers: speech input (Speech framework → Android SpeechRecognizer), Coach notes/class notes/spaced review/phrase library = SwiftData learner memory. Portable: `ConversationConfig`, `ConversationPrompts`, `ConversationSession` already in core.
- Approach: add pane with name, corrections, strictness, feedback, hints, gender colors, translations, auto-play; feed into `ConversationConfig`. Effort **S-M** (high value, core already shared).

### 11. Stories (Learning) — `iOS/StorySettingsView.swift` (89 L)
- "Story model": `StoryModelRow` (`selectedStoryModel`/`selectedPaperModel`). "Reading": Toggle "Reading counts as study", link "Reading progress". "Coaching": Toggle "Share story words with the coach". "New story defaults": Level link, genre, Picker "Questions" 4/6/8/10, Toggles "Illustrate new stories", "Translate into English".
- Keys: `storyTimeCountsTowardStreak`, `storyFeedsCoach`, `storyGenreRaw`, `storyQuestionTypesRaw`, `storyQuestionCount`, `storyIllustrationsEnabled`, `storyImageCount`, `storyTranslationEnabled`.
- Android: **Missing** — Stories feature not ported (LibraryView.swift:20 "Chats, Reading and Phrases come later"). Blocker: SwiftData story models + image gen. Effort: pane **S** after feature (feature **L**).

### 12. Model & Downloads (Model) — `iOS/ModelSettingsView.swift` (1415 L) + `ImageGenerationSection.swift`, `CloudPicturesRows.swift`, `ModelGuideSheet.swift`
- "This device": "This device — N GB RAM", "Available to this app", Picker "Memory Saver" Automatic/Always On/Off (`memorySaverMode`, `Services/MemorySaver.swift:23-48`), status label, "Which model should I use?" → `ModelGuideSheet`.
- "Your German tutor": hero card for `MLXModel.leadTutor(ramGB:)` (download/load, "Why this model?", "Details"), shared `ModelLoadingPanel` progress, error label, "Other sizes (N)" disclosure w/ caption, rows with "Last used"/"May struggle" tags, swipe-to-delete, `MemoryCheckSheet` before oversized downloads, supersession banners for retired builds.
- "Built in to iOS": Apple Intelligence row (FoundationModels).
- Reclaim banner; "Image generation": Picker "Pictures drawn" (on-device / cloud), "Image model", Download/Delete, "Picture quality", Toggle "Watch pictures being drawn"; OpenRouter: "Sign in with OpenRouter", credit/limit links, "Disconnect" (this device / all devices).
- "Storage": per-model sizes, orphans, "Delete all downloaded models" → `ClearAllModelsSheet`.
- Keys: `selectedMLXModel`, `activeModelProvider`, `lastLoadedModel`, `selectedChatModel`, `memorySaverMode`, `allowsOversizedModels`, `lastGenSeconds_*`. Summary: `DownloadBadge` on the row + Settings tab badge.
- Android: **Partial** as "Tutor Model" (`TutorViews.swift:10-75`): list of `TutorModelFile.all` (name, "x.x GB · N GB RAM or more · on this phone / not on this phone yet", checkmark), footer "copy the files in with adb"; "Engine": "Load the model", state text, "N threads, on the fast cores", "Last answer: …" stats. Key `tutor.model`.
- Missing: in-app download + progress (blocked on GGUFs on Hugging Face), RAM readout, lead-tutor recommendation/hero card, memory-check sheet, delete/storage, model guide, image generation, OpenRouter. Apple Intelligence/MLX/Memory Saver (jetsam-specific) — N/A; Android analogue = `ActivityManager.MemoryInfo` + n_ctx/batch caps in TutorEngine.
- Approach: rename to "Model & Downloads"; add device RAM row, recommended model (port `leadTutor` logic — `ModelConfiguration.swift` is in core), DownloadManager/URLSession download w/ progress + badge, delete + storage. Effort **M-L**.

### 13. Speicher · Memory (Model) — `iOS/MemorySettingsView.swift` (445 L)
- "Jetzt · Right now" readings + Toggle "Show a live readout" (overlay); "Protokoll · Logging": Toggle "Log when memory runs short"; "Abstürze & Ereignisse": event list → detail sheet, ShareLink export, "Clear the log" + alert.
- Keys: `MemoryDiagnostics.verboseDefaultsKey`, `MemoryReadoutOverlay.defaultsKey`. Summary "N crashes"/"N events". Deep-link `.memory`.
- Android: **Missing.** Blocker: jetsam/MetricKit specifics. Android equivalent: `ApplicationExitInfo` (API 30+) for crash/LMK reasons, `Debug.getPss`. Useful given llama.cpp memory pressure. Effort **M**.

### 14. What's New (About) — `iOS/WhatsNewView.swift`
- Current release notes + "Früher · Earlier versions"; summary "vX" / "In progress". Android: **Missing.** Pure data — could share a JSON/Swift release-notes file with Android-specific entries. Effort **S**.

### 15. Sources & Credits (About) — `iOS/SourcesView.swift` (382 L)
- Sections: Goethe-Institut Word Lists, Wortkiste, Picture Models on the Mac (turbo-mlx), "Wie die Fälle erklärt werden" (IDS grammis, Friedrich, Herr Antrim, Clozemaster, Lingoda, Angelika's German), "Wie Erwachsene lernen" (DLI handbook), Wiktionary/Kaikki, Tatoeba. Links as `Label(..., systemImage: "arrow.up.right.square")`.
- Android: **Partial** (`A/SV:151-177`): Goethe, Wortkiste, Tatoeba only; plain `Link` text, no icons. Missing: Kasus teaching sources (Kasus lessons *are* on Android → credit owed), Wiktionary/Kaikki (if data shipped), DLI; should add llama.cpp + GGUF model licenses (Gemma terms). Picture Models on Mac: N/A. Effort **S**.

### 16. Send Feedback (About) — `iOS/FeedbackSection.swift`
- Links "Report a bug", "Request a feature", "Browse existing issues" (GitHub issues prefilled incl. loaded model name). Plus root "Rate on the App Store".
- Android: **Missing** both. No blocker — `FeedbackSection` is SwiftUI + URL building; add platform/device to the template. Rate → Play Store `market://details?id=com.kessenma.diekartei`. Effort **S**.

### 17. Screenshot Data / Developer (DEBUG/TestFlight) — `iOS/DeveloperSettingsView.swift`
- "Fill in screenshot data"/"Restore my real data", Wortschatz seed/restore/merge tools, "Messungen · Measurements", "Lebenslauf-Probe", Toggle "KI-Geschichten im Kasus-Pfad" (`KasusStoryGenerator.enabledKey`), "Kasus Lab".
- Android: **Missing.** Mostly SwiftData seeding → N/A; a debug-only section (gated on `BuildConfig.DEBUG`-like flag) with StudyStore seeding and TutorEngine bench would help Play screenshots. Effort **S-M**.

### Mac-only / N/A on Android
- `MacSettingsView.swift`, `MacWritingHelperSettingsView.swift`, Appearance ▸ Navigation, Mac Memory Saver copy, "Picture Models on the Mac" credits, Apple Intelligence row, Keyboard pane (iOS extension; Android IME is a separate project).

### Android-only items worth keeping
- System/Light/Dark picker; "Probehören / Langsam" slow voice sample; "Android voice settings" deep link; per-level "Reset" in Flashcards; Version row; TutorModel thread/tokens-per-sec stats (iOS has no visible equivalent).

### Key-name divergences (matter for future iPhone↔Android sync)
- Level: iOS `german.level` (CEFR A1–C1) vs Android `level` (Goethe A1–B1) + `hoerenLevel`.
- New cards: iOS `wortschatz.newPerDay` / `wortschatz.sessionCap` vs Android `flashcards.newPerSession`.
- Model: iOS `selectedMLXModel`/`selectedChatModel` vs Android `tutor.model`.
- Appearance: iOS `app.theme` vs Android `appearance` (different meaning).

---

## Top gaps by user impact
1. **Conversation settings (Missing)** — Gespräch ships on Android with hard-coded config; name, strictness, corrections, hints, translations are cheap to wire since `ConversationConfig`/prompts are shared. S-M.
2. **Model & Downloads (Partial)** — no in-app download/progress/delete or RAM-based recommendation; users must `adb push` GGUFs. Blocks the whole tutor. M-L.
3. **Reminders (Missing)** — retention feature; needs notification permission + WorkManager bridge. M.
4. **Sync (Missing)** — Auto Backup first (no UI), then Google Drive sync row per sync.mdx. L.
5. **Your Level (Partial)** — Goethe-only A1–B1 picker, no placement "three-minute check", divergent key. S + M.
6. **Flashcards (Partial)** — missing Front side, Ask der/die/das, Repeat missed, Auto-advance, Haptics; prefs files portable. S-M.
7. **Settings shell polish** — icons, grey summaries, SettingsHeader, grouped Account/App/Learning/Model/About, deep links. M.
8. **Themes (Partial)** — only light/dark; four AppThemes need tokens moved to core + fonts. M-L.
9. **Voice picker (Partial)** — no German voice selection; needs TTS `getVoices()` bridge. S-M.
10. **Feedback / Rate / What's New / fuller Sources (Missing/Partial)** — trivial, low risk. S each.
11. Memory diagnostics, Gamification, Stories, Keyboard (IME), Developer — later; depend on unported features.
