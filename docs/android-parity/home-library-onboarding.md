# Parity audit: Home, Library, App shell, Onboarding + Placement, Progress/Gamification

iOS: `german-ai-flashcards` (main @ 42b1cc7). Android: `DieKarteiAndroid/Sources/DieKartei` (android-port @ ffd2307).
Read-only audit: I read the source. I did not build anything or run `core_sync.py --prune`, so every "portable" verdict below comes from reading imports and dependencies and still has to be confirmed by a cross-compile.

## Summary table

| Area | iOS (lines) | Android | State |
|---|---|---|---|
| Tab shell / NavBar | ContentView 1443, NavBar 269, ActivityRouter, Activity | ContentView 45 (stock `TabView`) | Partial |
| Home "For You" (Today plan, level card, streak calendar, week/month) | HomeHubView 247, TodayView 654, TodayPlanner 428, StreakCalendarView 1212, LevelCardSection 177, WeekInReview 371, MonthlyNote 109 | HomeView 111 (one "Today" row + activity list) | Partial (thin) |
| Home "All Activities" hub (7 tiles + 6 wide cards) | ActivityCategoryView 399, tiles | Flat list: Vocabulary, Grammar, Hören, Spiele, Tutor | Partial |
| AI deck generation (HomeView/CardSelection/Generating/TopicBrowse) | ~1300 | none | Missing |
| Library (Decks/Chats/Reading/Phrases) | UnifiedLibraryView 590, DeckImportSheet, DeckMixPickerSheet | LibraryView 37: 3 Goethe levels | Missing (wrong content) |
| Onboarding wizard | OnboardingWizardView 518, HeroModelIntroSheet, ModelUpdateSheet | none | Missing |
| Placement quiz ("Wo stehst du?") | PlacementQuizView 205, PlacementQuizStages 830, Services 1.2k | none | Missing (engine ~portable) |
| Progress: Fortschritt, badges, XP | FortschrittView 314, Experience/Achievement services | none | Missing |
| Lernpyramide / Dein Weg (3D) | PyramidView 848, JourneyView 641, PyramidCoach 485 | none | Missing |
| Placement review / export | PlacementReviewView 645 + detail/filter | none | Missing |
| Celebrations overlay | CelebrationCenter 184, CelebrationOverlay | none | Missing |
| Förderplan | FoerderplanView 149, FoerderplanService | none | Missing |

---

## 1. App shell and tab bar

**iOS** (`App/ContentView.swift`, `App/NavBar.swift`, `App/ActivityRouter.swift`, `App/Activity.swift`)
- Custom floating `NavBar` with four tabs: Home `house`, Grammar `checklist`, Library `brain.head.profile`, Settings `gearshape.2`. Selected icons use `.fill` variants. It tints to the theme accent or the loaded model's brand colour (`ModelTheme`) and shows a `DownloadBadge` pie (model download progress) and a `GeneratingBadge`. It hides in drawing mode (`NavBarVisibility`) and its clearance is measured, not hard-coded.
- Tabs load lazily (`visitedTabs`) and are kept alive by opacity, so each keeps its state. Re-tapping a tab pops it to its root (`*ResetToken`), and going to Home always lands on the hub root.
- Hub and spoke: every immersive activity (card deck, grammar MC, matching, article game, preposition case, cloze, Kasus story, grammar drill, hangman) goes through `ActivityRouter.active`, which ContentView presents in one `.fullScreenCover`.
- Overlays: `IllustratingDeckView`, `DeckPicturesPill`, `CelebrationOverlayHost`. Sheets: card selection after generation, onboarding, ModelUpdate, What's New, deck import (in `german_ai_flashcardsApp`).
- `SettingsRouter` lets any screen deep-link into Settings (for example `.model`). Launch-sheet ordering is ModelSupersession, then What's New, then the onboarding wizard (`offerNextOnboardingStep`), mutually exclusive.

**Android** (`ContentView.swift`)
- SkipUI `TabView` with the same four tabs, in order. Each tab has its own `NavigationStack`. Icons are `house`, `checkmark.circle`, `bookmark`, `gearshape`, the closest Material equivalents.
- Missing: re-tap-to-root, the model accent tint, download and generation badges, `ActivityRouter` and full-screen covers (activities are pushed `NavigationLink`s instead), deep links into Settings, the launch-sheet sequence, the celebration overlay, and What's New.

**Approach**
- Keep the stock Material bottom bar. It is the right call on Android and the custom bar isn't worth porting. Add these:
  - a download badge on Settings once a GGUF download exists;
  - re-tap-to-root via `.id(token)` on each stack;
  - a small `ActivityRouter` plus `.fullScreenCover`, if Skip supports it (it maps to a full-screen dialog), so drills feel immersive;
  - a `SettingsRouter` equivalent.
- Effort: **S–M**.
- Depends on: a model download for the badge; launch-sheet logic, which needs onboarding first.

---

## 2. Home

### 2a. "For You" mode (iOS default)
**iOS**: `HomeHubView.forYouList`. Top to bottom: segmented For You / All Activities picker (`home.showAllActivities`), `ModelUpgradeNudge` (tutor card), `LevelCardSection` (if gamification is on), `StreakCalendarSection`, `WeekInReviewSection`, `MonthlyNoteSection`, `TodaySection(style: .hero)`. Every appearance and every StudyDay change calls `CelebrationCenter.evaluate` and `ProgressSnapshotService.recordIfDue`.

**Android**: `HomeView`. One "Today" section with a single row, "Karteikarten · Goethe A1 · N fällig · M neu", that pushes `KartenView`. Below it, an Activities list and a Tutor section (Gespräch, Satz prüfen). There is no mode picker, no streak, no level card, no week/month review and no tutor-download card.

### 2b. Today plan (TodayPlanner)
- User-visible: up to three ordered "do this next" items, from resume paused deck, class before/after, Förderplan day, worksheet redo, Wortschatz due+new, verb-pair review, class words, due-card review, coach drill, weak-grammar focus (rotated by day), easy round, Hör-Check, Tagebuch prompt, chat (always), generate deck. A cold start gives "generate" + "chat".
- Files: `Services/TodayPlanner.swift` (the planner, `TodayIntent`, `TodayRecommendation`, `TodaySnapshot`) and `Features/Home/TodayView.swift` (`TodaySection`). TodaySection gathers the snapshot from `@Query` over `LearnerProfile`, `SavedDeck`, `StudyDay`, `JournalEntry` plus courses and materials, then resolves each intent into a router launch, tab switch, push or lesson sheet.
- **Portability:** `TodayPlanner.plan(_:)` is a pure function, but the file **`import SwiftUI`** for three reasons:
  1. `TodayRecommendation.accent: Color`;
  2. it reads `HoerenTile.systemImage` / `HoerenTile.tint` (a SwiftUI view file, `Features/Hoeren/HoerenTile.swift`);
  3. it reads `Foerderplan.length` / `Foerderplan.task(day:)`. The `Foerderplan` struct is `nonisolated Codable` but sits in `Services/FoerderplanService.swift`, which `import SwiftData`.
  - **Split:** replace `accent: Color` with a token enum (`TodayAccent`), mapped to a Color in a SwiftUI extension. Inline the Hören symbol and move its tint to that extension. Move `Foerderplan` and its task table into a Foundation-only `Models/Foerderplan.swift`. After that, `TodayPlanner.swift` can go into `core_files.txt`.
  - `GrammarFocus` is already in core.
  - The snapshot gatherer stays per-platform. Android builds a `TodaySnapshot` from its own stores, at first with only `wortschatz`, `streak`, `studiedToday`, `hasStartedLearning` and `dayIndex`; the other fields keep their default `nil`/0.
- **Concrete differences on Android today:**
  - Android offers `newPerSession` fresh words **per session**, so reopening Karten gives another 10. iOS has a **daily** new-word budget: `StudyLogService.newWordBudgetRemaining` over `StudyDay.newWordsIntroduced` / `newWordsBonus` ("Learn 10 more").
  - Android shows only the current level's Goethe box. iOS keeps one Wortschatz deck across A1–B1 (`goethe-srs`).
- Effort: **M** (split S, Android gatherer and hero UI M). Depends on a StudyDay store (2c) for the streak and new-word budget.

### 2c. Streaks / StudyDay log / streak calendar
- User-visible: a flame streak, plus a Week strip / Month grid / 3-month and Year heatmap shaded by items or by time. Tapping a day opens a day sheet; there is also a time summary and a legend.
- Files:
  - `Models/StudyDay.swift`: **`@Model`**, about 20 counters and second buckets, `hasActivity`, plus `StudyTimeFormat` in the same file.
  - `Services/StudyLogService.swift`: `import SwiftData`. Writers take a `ModelContext`. The readers (`currentStreak`, `studiedToday`, `timeSummary`, `todayNewWords`, `newWordBudgetRemaining`) are pure but typed on `[StudyDay]`.
  - `Features/Home/StreakCalendarView.swift`: `@Query StudyDay`. `DayMetrics` and `StreakShade` are pure logic stuck inside the view file.
- **Portability:** the streak math is pure, but every signature uses the SwiftData `StudyDay` class.
  - **Split:**
    1. A Foundation-only `StudyDayValues` struct, or a `StudyDayRecord` protocol with the counter fields and `hasActivity`, which `StudyDay` adopts. This is the same pattern as `SRSCardState`/`SavedCard`.
    2. Move the read half of `StudyLogService` (`currentStreak`, `studiedToday`, `timeSummary`, new-word budget, `StudyActivity`, `StudyTimeBucket`) into a Foundation file generic over that protocol.
    3. Move `StudyTimeFormat`, `DayMetrics` and `StreakShade` out of their SwiftUI and SwiftData files.
  - ANDROID_PORT.md already lists `StudyDay` under "need plain-value twins".
- Android needs a `StudyLogStore`, a dictionary from day to record saved as JSON like `StudyStore`. Every activity calls `record(_:)`: Karten, Grammatik, Hören, Spiele, Gespräch. Today **nothing on Android logs activity**.
- The calendar UI is SwiftUI: Grid/LazyVGrid and custom cells. It probably compiles under Skip with modest changes, because SkipUI supports Grid and ScrollView. It reads `appTheme`/`themed*` modifiers, which Android lacks.
- Effort: **M**. This is the foundation for 2b, 2d and 5.

### 2d. Level card, Week in Review, Monatsbericht
- `LevelCardSection` shows rank, XP progress, "+N heute", the `DailyGoalRing` (Tagesziel) and a pyramid teaser. It reads 8 `@Query`s: StudyDay, LearnerProfile, SavedCard, PrepositionStat, StoryQuizAttempt, ArticleWordStat, MatchingPairStat, ChatConversation. Its links go to `FortschrittView` and `PyramidView`.
- `WeekInReviewSection` is a 2×2 grid of growth against the previous 7 days, with a "Weekly recap" chat button that needs the tutor. `WeekInReviewService` imports only Foundation but takes `[StudyDay]` and `[ChatConversation]` (SwiftData).
- `MonthlyNoteSection` builds a note from `ProgressSnapshotStore` weekly snapshots (`MonthlyNoteBuilder`).
- Android: none of these exist.
- Approach: after 2c, port the level card and goal ring first. They need only StudyDay plus `ExperienceService`/`LearnerLevel`. WeekInReview comes next, with chat counts taken from Android's conversation store once that exists. Monatsbericht waits for snapshots. Effort **M**.

### 2e. "All Activities" hub
- iOS: seven `ActivityCategory` tiles: Vocabulary, Grammar (raises its tab), Reading, Speaking, Phrasen, Spiele, Batch. Below them are six wide cards: Job prep, Deutschkurs (ClassNotes), Schreibblatt, Zeichnen, Schreiben, Hören. Vocabulary contains Generate Flashcards, Flashcards from a Document, Wortschatz · Goethe and Card Matching. Spiele contains Galgenmännchen, Card Matching, Der·Die·Das (and Wortsuche/Kreuzworträtsel per subtitle).
- Android: a flat list. Vocabulary has Karteikarten and Wortschatz; Grammar raises its tab correctly; Hören; Spiele has hangman and word search; Tutor has Gespräch and Satz prüfen. The names, blurbs and colours follow `ActivityCategory`. Reading, Phrasen, Batch, Job prep, Deutschkurs, Schreibblatt, Zeichnen and Schreiben are missing.
- `ActivityCategory` is a plain enum, but its file is SwiftUI (`tint: Color`). Moving the enum's strings and symbols into a Foundation file would let Android show the exact iOS copy.
- Approach: add a For You / All Activities picker and a 2-column tile grid (LazyVGrid works in Skip). Show only categories with Android content. Effort **S**. The missing rooms are covered by other audits.

### 2f. AI flashcard generation (`HomeView` (600 lines, topic + word-type filter), `GeneratingFlashcardsView`, `CardSelectionView`, `FlashcardTopicBrowseSheet`)
- This is the main source of user decks on iOS: topic, then LLM generation, then a card picker, then a saved `SavedDeck`. It is the reason the iOS Library has content.
- Android: missing.
- Blocked on the tutor model in-app (TutorStore has no download yet; models arrive by `adb push`) and on a SavedDeck store.
- `FlashcardTopicService` and `VocabCard` are already in core.
- Effort: **L**. Needs the persistence layer and the tutor model download.

---

## 3. Library — why Android "looks like an older version"

**iOS** (`Features/Library/UnifiedLibraryView.swift`): an archive of content the user made. Segments:
- **Decks**: `@Query SavedDeck` filtered by `isBrowsableContent`. The Goethe/SRS decks are **explicitly excluded** as "activity plumbing": `.goethe`, `.goetheSRS`, `.pastTense*`, `.grammar` and `.verbPrepositionSRS` all return false. Each row shows the deck topic, the generator model logo or a kind symbol, its course, its source (story, paper or handout via `DeckLinks`) and its generation time. Actions:
  - tap opens the `.cardDeck` cover;
  - the ⓘ button opens `DeckStatsSheet`, the quiz-result history with a share option;
  - leading swipe offers **Share** (`DeckTransfer` `.kartei` file) and **Course** (assign the deck to a `ClassCourse`);
  - trailing swipe deletes (and cleans up images and source files);
  - "Mix decks" (`DeckMixPickerSheet` → `deckStore.mixSession`) studies two or more decks as one session.
- **Chats**: `ConversationListView` (SwiftData `ChatConversation`).
- **Reading**: Short Stories, Papers & Links, Photo Scans, Job Postings, Class Handouts.
- **Phrases**: `PhraseLibraryView`.
- **Import**: `DeckImportSheet`, opened from the app (`german_ai_flashcardsApp.swift:252`), offers replace or keep-both for an incoming `.kartei` file.

**Android** (`LibraryView.swift`, 37 lines): one "Decks" section listing Goethe A1/A2/B1 with seen/total/due counts, each pushing `WortschatzView`. A footer says Chats, Reading and Phrases "come later".

**Why it reads as old:** Android shows exactly the decks iOS *hides*. It looks like the pre-UnifiedLibraryView, flashcard-only `SavedDecksView` era, before Goethe decks were reclassified as plumbing. Android has no user content because:
1. there is no SavedDeck / SavedCard / QuizResult store (they are `@Model`);
2. there is nothing to create decks with (generation needs the tutor; documents, photos and papers need PDFKit or Vision);
3. chats aren't persisted (`TutorViews.swift:155`: "kept in memory (no saved history yet)").

**Storage layer Android needs** (in line with `docs-site/content/docs/android/sync.mdx`, step 1: "a store shaped like iOS sync"):
- Plain Codable value types for `SavedDeck`, `SavedCard` (already mirrored by `CardProgress`), `QuizResult`, `ChatConversation`/`ChatMessage` and `SavedPhrase`, using the iOS ids: `SyncNameUUID`, `SyncSingletonDecks.cardID(deckID:germanWord:)`. Store them as JSON files, or SQLite (SkipSQL) behind a `DeckStoring` protocol, written atomically (temp file then rename), using `SyncRecordLogic.noteLocal` so Drive sync can come later.
- Migrate the Goethe progress keys from `A1:word` to the iOS single `goethe-srs` deck ids. The sync doc already calls for this.
- `DeckTransferEnvelope` (Codable) sits in `Services/DeckTransfer.swift` next to `import SwiftData` and `CoreTransferable`. Split the envelope and its `Deck`/`Card`/`Progress` structs into a Foundation file. Android could then **import `.kartei` files shared from iPhone** (via an intent filter or file picker). That is the cheapest way to put real decks in the Android Library before generation works.
- `SavedDeck.Kind` / `isBrowsableContent` / `kindSymbol` are pure logic over `generatorRaw`. Move them to a Foundation extension or helper so both platforms classify decks the same way.

**Approach**
- Step 1, effort S: relabel or move the Goethe levels into Home ▸ Vocabulary (or a "Wortschatz" header), and give the Library a Decks / Chats / Phrases segmented picker with empty states that match iOS ("No Saved Decks — Generate vocabulary…").
- Step 2, effort M: the deck store plus `.kartei` import, deck rows, delete, the stats sheet, and Share through the Android share intent (needs a Kotlin bridge like `GermanVoice`).
- Step 3, effort M: persisted Gespräch history so the Chats segment has content.
- Step 4, effort L: Mix decks, course assignment, and Reading (needs the tutor for stories; PDF and photo need replacements).

---

## 4. Onboarding and placement quiz

### 4a. Onboarding wizard
- **iOS:** shown once, ever, gated on `hasSeenOnboardingV2`. It also writes the legacy `hasSeenOnboardingWizard` and `hasSeenHeroModelIntro`, sets all flags before presenting (crash-safe), and waits up to 10 s for an iCloud first fetch so an already-onboarded learner isn't asked again.
- Steps (`OnboardingWizardView`):
  1. **welcome**: "why a download", the teacher metaphor, never says "model".
  2. **offer**: the `HeroModelPitchContent` tutor pitch. It is skipped when no tutor fits the device (`ModelReadiness.fittingTutor`). Accepting starts the MLX download in the background (`ModelDownloadStrip`).
  3. **check**: the placement quiz runs while the model downloads. It is skipped if a `PlacementResult` already exists. Its result page shows the download status, and the learner can disagree and declare a level by hand (`PlacementDeclareStage`).
- Related: `HeroModelIntroSheet` (Settings ▸ Model), `ModelUpdateSheet` (a retired model build is still cached), `TutorSceneLab` (RealityKit, **dev-only, "Nothing here ships"**, so it is not a parity item).
- **Android:** nothing. The app opens straight on Home at the A1 default (`@AppStorage("level")`).
- Approach: a two-step Android wizard, (1) welcome and (2) placement, with the tutor offer added once GGUF download exists. Gate it on its own `hasSeenOnboardingV2` key. Effort **M**. Depends on the placement port (4b) and the tutor model download for the offer step.

### 4b. Placement quiz — is the engine portable? **Mostly yes.**
| File | Imports / ties | Verdict |
|---|---|---|
| `Services/PlacementService.swift` (705 lines): tuning, item generation, `score`, `estimate`, storage in UserDefaults `placement.result` / `placement.seen` | Foundation only ("No UI, no SwiftData"). Uses GoetheVocabService, CEFRLevel, `PrepositionService.prepositions(includeAdvanced:)` (+Content, already in core via the shim), SeededGenerator, PlacementGrammarBank, PlacementAttemptStore (debug seeding) | **Portable as-is.** Add it to core |
| `Services/PlacementSession.swift` (262 lines): adaptive staircase state machine | Foundation + Observation, `@Observable` | **Portable** |
| `Services/PlacementGrammarBank.swift` (142 lines) | Foundation, but **`Bundle.main.url(forResource: "placement_grammar")`** | Needs the one-line `AppResources.bundle` fix, the same as the six services already converted. `placement_grammar.json` also has to be copied into `DieKarteiAndroid/Sources/DieKartei/Resources/`, where it is missing today |
| `Services/PlacementAttemptStore.swift` (155 lines): JSON file under `URL.applicationSupportDirectory/Placement/attempts.json` | Foundation | Probably portable. Check that `applicationSupportDirectory` resolves on Android Foundation |
| `Models/PlacementResult.swift`, `Models/PlacementAttempt.swift` | Foundation | **Already in core** |
| `Services/PlacementCoachExport.swift` | SwiftData (`ModelContext`, LearnerProfile coach hand-off) | Not portable; later or optional |
| `Services/PlacementExport.swift` | CoreTransferable, UniformTypeIdentifiers | Needs an Android share bridge; later |
| `Features/Onboarding/PlacementQuizStages.swift` (830 lines: Intro, Declare, Question, Cloze, Result stages, `PlacementFeedbackOption`) and `PlacementQuizView.swift` | SwiftUI only (no SwiftData), plus iOS theme modifiers | UI layer. Since Skip compiles SwiftUI, it can be adapted into the Android module; expect to strip `appTheme`/`themed*` and fix animations |
| Level anchor: `MLXModelManager.germanLevel` / `germanLevelIsDeclared` / `german.level.setAt` (UserDefaults) | Lives on the MLX manager, which is not portable | **Split** into a Foundation `LearnerLevelSettings` (same keys) so both quiz paths and Android Settings write one anchor |

- Why the engine isn't in core yet: I found no blocking dependency by reading, apart from the Bundle.main lookup. Run `core_sync.py --prune` to confirm. PlacementService has a debug `extension GoetheLevel` at the bottom, which is harmless.
- **Level model mismatch:** Android's app-wide level is `GoetheLevel` (A1–B1, key `level`, plus a separate `hoerenLevel`). Placement estimates `CEFRLevel` (A1–B2), and iOS's anchor is `german.level`. Android needs `CEFRLevel` as the anchor and a clamp to GoetheLevel for the word lists (B2 shows B1 lists).
- Placement also seeds the pyramid's provisional fill ("Bauplan", GAMIFICATION Phase 6/9). That part is meaningless on Android until a pyramid exists. Store the result anyway.
- Approach:
  1. Add PlacementService, Session, GrammarBank and AttemptStore to core, fix the Bundle lookup, copy the JSON (**S**).
  2. Android `PlacementQuizView` from the stages, reachable from onboarding and from Settings ▸ "Take the three-minute check" (iOS `LevelSettingsView`) (**M**).
- No model is needed: every item comes from bundled JSON, which is the whole design. This makes it **the cheapest big win** in this audit.

---

## 5. Progress and gamification (docs/GAMIFICATION.md, phases 1–10)

| Feature | iOS files | Portability | Android |
|---|---|---|---|
| XP, rank, daily goal | `ExperienceService` (Foundation, typed on `StudyDay`), `Models/LearnerLevel.swift` (`import SwiftUI` only for `LearnerRank.tint`) | Move tint to an extension and make the service generic over the StudyDay protocol (§2c), then both are portable | Missing |
| Badges (16 Abzeichen) | `AchievementService` + `Models/Achievement.swift` (SwiftUI because of `accent: Color`). Rules are pure over `AchievementSnapshot`; earned dates go in UserDefaults | Split `accent`; the rules then port. Snapshot fields that need Android stores: savedCards, perfect matching/article/preposition rounds, stories, solid grammar | Missing |
| Celebrations | `CelebrationCenter` (SwiftUI) + `CelebrationOverlay` (confetti); dedupe in UserDefaults `celebration.*` | The decision logic is small and can be compiled in the Android module as SwiftUI | Missing |
| Fortschritt screen | `FortschrittView`: level, badge grid, pyramid teaser, journey section | SwiftUI + `@Query` | Missing |
| Lernpyramide | `PyramidService` (Foundation, but its snapshot takes LearnerProfile, PrepositionStat, SavedCard, StoryQuizAttempt, ArticleWordStat, MatchingPairStat, ChatConversation, all `@Model`); `PyramidView` (RealityKit live stack); `PyramidGlyph` (flat 2D trapezoids, in the same file); `PyramidCoachSection` (SwiftData) | Service: change it to take plain counts. View: **use the 2D `PyramidGlyph`**, no RealityKit on Android | Missing |
| Dein Weg (journey) | `JourneyService` (SwiftUI because of `JourneyEvent.tint`), `JourneyView` (RealityKit walking figure, `figur-gehen.usdz`), `ProgressSnapshotStore` | Timeline portable after the tint split; 3D figure needs 3D or a 2D fallback | Missing |
| Placement review | `PlacementReviewView`, `PlacementAttemptDetailView`, `PlacementQuestionDetailView`, `PlacementReviewFilterBar` (SwiftUI + SwiftData for the coach hand-off) | Data (`PlacementAttemptStore`, `PlacementReviewItem`) is portable; UI adaptable without the coach button | Missing |
| Conversation quality (Spitze) | `ConversationQualityView` | Needs stored chat summaries | Missing |
| Förderplan | `FoerderplanService` (SwiftData record), `FoerderplanView` | Move the `Foerderplan` struct out (also needed for TodayPlanner); the record store needs persistence | Missing |
| Gamification settings | `GamificationSettingsView` (master toggle, goal 5–30 min, per-feature switches) | Simple | Missing |

Suggested order on Android:
1. StudyDay store (§2c).
2. XP, level card and daily-goal ring on Home (**M**).
3. Badges and celebrations (**M**).
4. A 2D pyramid with the layers Android can feed: Wortschatz A1/A2 from StudyStore, Fundament from the preposition drill stats once they are persisted, Grammatik-Kern once the LearnerProfile grammar tallies exist. Stories and Spitze stay empty until the tutor ships. Effort **L**.
5. Journey and Monatsbericht last.

Hard blockers: RealityKit for the 3D pyramid and the journey figure (use 2D, or Filament/SceneView later), and a LearnerProfile equivalent (the grammar mastery store) for most pyramid layers and badges.

---

## Cross-cutting splits (iOS-side, no behaviour change; all small)
1. `PlacementGrammarBank`: `Bundle.main` → `AppResources.bundle`. Add the Placement* services to `core_files.txt`; copy `placement_grammar.json`.
2. `TodayPlanner`: `Color` → token; inline the HoerenTile constants; `Foerderplan` struct → `Models/Foerderplan.swift`.
3. `StudyDay` → a Foundation `StudyDayRecord` protocol or struct. Readers from `StudyLogService` → Foundation file. `StudyTimeFormat`, `DayMetrics`, `StreakShade` out of their SwiftData and SwiftUI files.
4. `LearnerRank.tint`, `Achievement.accent`, `JourneyEvent.tint`, `ActivityCategory.tint` → SwiftUI extensions (the same pattern as GrammarPalette).
5. `germanLevel` / `germanLevelIsDeclared` → Foundation `LearnerLevelSettings`.
6. `DeckTransferEnvelope` and `SavedDeck.Kind`/`isBrowsableContent` → Foundation files.
7. `PyramidService.snapshot` → accept plain counts (or protocols) instead of `@Model` arrays.

---

## Top gaps by user impact
1. **No onboarding or placement.** A new Android user lands on Home at A1 whatever their real level. The placement engine is already Foundation-only and needs no model, so this is low cost for a large gain (S core + M UI).
2. **The Library shows the wrong thing.** It lists the Goethe decks iOS hides, and has no user decks, chats or phrases. This needs a SavedDeck/Chat store in the sync-record shape. `.kartei` import from iPhone is the quickest way to give it content (M).
3. **No StudyDay log, streak or calendar.** Nothing on Android records activity, so the streak, Today plan, XP and badges all have no data. It is the base for gamification (M).
4. **Home is a static list, not "For You".** No Today plan, which on iOS removes the "what do I do now" decision. TodayPlanner is a short split away from core (M).
5. **The new-word budget differs.** It is per session on Android and per day on iOS (`newWordsIntroduced`), so Android users can flood themselves with new words. A correctness fix once StudyDay exists (S).
6. **No gamification surfaces**: level card, Tagesziel, badges, celebrations, Fortschritt (M each).
7. **No AI deck generation**, the main source of iOS Library content. Blocked on in-app tutor download plus the deck store (L).
8. **No Lernpyramide or Dein Weg.** RealityKit-only on iOS; use the 2D `PyramidGlyph`. Most layers also need LearnerProfile grammar data (L).
9. **Shell polish**: re-tap-to-root, immersive covers via an ActivityRouter, Settings deep links, download badge, What's New (S–M).
