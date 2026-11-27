# Android persistence, phase 1: a store that mirrors iOS SwiftData

Scope: iOS `main` (`~/ws/die-kartei/german-ai-flashcards`) against `android-port`
(`~/ws/die-kartei-android`, 16 commits ahead of local `main` and 1 behind). This was a read-only
pass: nothing was built or edited in either repo. Line and file counts come from grep over the
737 iOS Swift files. 262 of those files import SwiftData, and 169 sites use `@Query`.

## 0. Summary

- `AppSchema.models` lists **35 `@Model` types**. **30** have a sync codec (`SyncRegistry`).
  **5** stay on the device: `BatchJob` and `Resume` (by design), `SchreibblattSheet` (the
  docs say "in AppSchema but not in SyncRegistry"), and `SyncRecordState`/`SyncMeta`, which are
  sync bookkeeping.
- There is no `VersionedSchema` or `SchemaMigrationPlan`. iOS relies on lightweight
  migration: new fields get declared defaults, and the store is moved aside on failure
  (`StoreRecovery`). Nothing uses `@Attribute(.unique)` or `#Unique`. The only index is
  `#Index` on `SyncRecordState`. Identity comes from `id: UUID` or natural keys that the
  codecs turn into UUIDv5.
- There are **5 relationships**, all one parent to many children with cascade delete:
  deck→cards, deck→quizResults, conversation→messages, course→entries, entry→materials.
  Every other link is a raw UUID string such as `deckIDRaw`, `courseIDRaw` or `storyID`.
- **Recommendation:** use **SkipSQLPlus** (skip-sql 0.16.x, with its own SQLite 3.51.3 and
  SQLCipher 4.14), wrapped in one generic **`record` table**. The payload in each row is
  exactly what the iOS codec's `known()` produces, plus typed index columns. Store protocols
  per aggregate go in the core. Typed value records (`CardRecord`, …) are Foundation-only and
  live in `Services/Sync/Core`.

## 1. Inventory of every `@Model`

Legend: S=String, I=Int, D=Double, B=Bool, Dt=Date, U=UUID, Da=Data (JSON blob of the type in
brackets). `?` means optional and `=x` is a declared default. Fields without a default get their
value in `init`. **Refs** counts the files that mention the type. **Id** says how the sync
record name `<Kind>:<UUID>` is derived. In **Sync**, ✓ means synced; the rules are noted
(counter, max, min, or, set, group). **Twin** names any Foundation-only value or protocol that
already exists.

### 1a. Deck, cards and quiz (the spine)

| Model | Fields | Relationships | Id | Refs / features | Sync | Twin |
|---|---|---|---|---|---|---|
| **SavedDeck** | id U, topic S, wordCount I, includeExamples B, includeGender B, wordTypeFilterRaw S, includeConjugations B, selectedTenses [S], createdAt Dt, generatorRaw S (init ""), generationTimeSeconds D, pausedProgressData Da?, pausedAt Dt?, courseIDRaw S?=nil, sourceText S?=nil, sourceFile S?=nil, macPictureRequestData Da?=nil, macPictureResultData Da?=nil | cards →[SavedCard] cascade; quizResults →[QuizResult] cascade | random UUID. For singleton generators (`goethe`, `goethe-srs`, `past-tense`(-srs), `grammar`, verb-prep) it is `SyncNameUUID.make("deck", generatorRaw, topic)`. Linked decks use `make("linked-deck", kind, parentID)` | 104: Library, Cards, ClassNotes, Conversation, Stories, DeckStore | ✓ LWW; `pausedProgressData`/`pausedAt` never sync; macPicture* are JSON LWW | none (VocabCard covers card content only) |
| **SavedCard** | id U, germanWord S, englishTranslation S, wordType S?, article S?, exampleSentence S?, conjugationsData Da? [StoredConjugation], sortOrder I, imageFileName S?, formsLine S?=nil, easeFactor D(2.5), interval I, repetitions I, nextReviewDate Dt?, totalReviews I, lapses I, leitnerBox I, lastReviewedAt Dt?, lastReviewWasCorrect B?, firstReviewedAt Dt? | deck → SavedDeck? | random UUID. In singleton decks it is `SyncSingletonDecks.cardID(deckID:germanWord:)` = `make("card", deckID, exact word)` | 70: Cards, Wortschatz, ClassNotes, SRS services | ✓ `totalReviews`/`lapses` are counters; `firstReviewedAt` min; the schedule group (ease, interval, reps, next, box, lastReviewed, lastCorrect) is taken whole from the later review. `goethe-srs` syncs only reviewed cards and its content is owned by the bundle. perStore bootstrap in singletons | **SRSCardState** (core protocol), **VocabCard** (core struct) |
| **QuizResult** | id U, date Dt, totalCards I, correctCount I, incorrectCardIndices [I], durationSeconds I, studyModeRaw S, ankiRatingsData Da? [Int:Int], subDeckLabel S? | deck → SavedDeck? | random | 17: DeckStore, Home, Progress | ✓ append-only, only rows with a deck | none |

### 1b. Study log

| Model | Fields | Rel | Id | Refs / features | Sync | Twin |
|---|---|---|---|---|---|---|
| **StudyDay** | dayStart Dt, lastActivityAt Dt, then counters, all I: cardsReviewed, grammarExercises, conversations (from init); storySeconds, storyQuestions, cardSeconds, grammarSeconds, conversationSeconds, storyQuizSeconds, gameSeconds, newWordsIntroduced, newWordsBonus, gameWordsSolved, wordsDrawn, drawingSeconds, wordsWritten, writingSeconds, sheetWordsWritten, hoerenItems, hoerenSeconds (all =0). There is **no id field** | none | natural key `SyncDayKey`: `yyyy-MM-dd` of `dayStart + 12h` | 54: StudyLogService (streak, new-word budget), Home, Grammar, Progress | ✓ every count is a counter; `lastActivityAt` max; perStore | none (ANDROID_PORT lists it as "needs a twin"); `StudyActivity`/`StudyTimeBucket` sit in a SwiftData file |

### 1c. Learner profile, grammar and game stats

| Model | Fields | Id | Refs / features | Sync | Twin |
|---|---|---|---|---|---|
| **LearnerProfile** | id U, sessionCount I, lastSessionAt Dt?, grammarData Da? [S:GrammarSkill], vocabData Da? [VocabTouch], slipsData Da? [LexicalSlip], selfReportsData Da?=nil [SelfReportNote], foerderplanData Da?=nil | fixed singleton `make("learner-profile")`. `id` never travels; the canonical row is the lowest UUID | 42: tutor memory, Grammar, Home, Progress | ✓ sessionCount counter; lastSessionAt max (cleared by normalize on reset); grammar keyed lwwBy lastSeen; vocab/slips/selfReports are sets; perStore | none; blob structs sit in the SwiftData file |
| **ArchivedMemoryItem** | id U, kindRaw S, reasonRaw S, archivedAt Dt, title S, subtitle S, payload Da? | natural key `kindRaw|<item id from payload>` | 9: memory settings | ✓ archivedAt min; perStore | none |
| **MatchingPairStat** | key S, german S, article S?, english S, timesSeen I, timesMissed I, firstTryStreak I, lastSeenAt Dt, lastMissedAt Dt?, confusionsData Da? [S:I] | natural key `key` | 20: Matching, Wortschatz, Progress | ✓ seen/missed counters, the tally is a counterMap, lastMissedAt max; perStore | none |
| **ArticleWordStat** | key, noun, articleRaw, english S; same stats as above, wrongPicksData Da? | `key` | 19: der/die/das, Progress | ✓ same rules | none |
| **PrepositionStat** | key, word, caseRaw, meaning S; same stats, wrongPicksData Da? | `key` | 15: Präpositionen | ✓ same rules | none |
| **MatchingRound** | date Dt, topic S, pairCount I, firstTryCount I, durationSeconds I | `GameStatSync.roundKey(date,topic,counts)` | 9 | ✓ append | none |
| **ArticleRound** / **PrepositionRound** | date Dt, topic S, questionCount I, firstTryCount I, durationSeconds I | roundKey | 17 each: Grammar hubs | ✓ append | none |
| **KasusRound** | date Dt=now, storyID S="", unitRaw S, stepRaw S, hintLevelRaw S="", askedCount, firstTryCount, durationSeconds I=0, perCaseData Da? [GrammarCase:CaseTally], itemsData Da?=nil [KasusRoundItem], feedbackModeRaw S="", markCaseRaw S="", wrongCount I=0, revealedAnswers B=false, roundKey S="" | `roundKey`, falling back to `date|storyID|unit|step` | 37: Kasus path, history, GrammarProgress | ✓ revealedAnswers or | KasusRoundItem (separate file); CaseTally sits inside the model |
| **GeneratedKasusStory** | id S="", date Dt, unitRaw, level, modelID, title S, planData Da? [KasusStoryPlan], storyData Da? [KasusStory], validatorSummary S, attempts I=1, generationSeconds D=0 | natural key `id` | 14: Kasus stories | ✓ LWW | KasusStory, KasusStoryPlan (separate files) |
| **HoerenRound** | date Dt, roundKey, kindRaw, modeRaw, playbackRaw, levelRaw, sourceRaw S="", askedCount, correctCount, firstPassCount, replayCount, durationSeconds I=0, itemsData Da? [HoerenItem] | natural key `roundKey` | 12: Hören | ✓ append | HoerenItem sits in the model file |

### 1d. Chats and phrases

| Model | Fields | Rel | Id | Refs / features | Sync | Twin |
|---|---|---|---|---|---|---|
| **ChatConversation** | id U, title S, createdAt/updatedAt Dt, durationSeconds I, modeRaw S, scenarioRaw S?, customScenario S?, focusRaw [S], levelRaw, formalityRaw, strictnessRaw S, feedbackStyleRaw S=tellMe, correctionsEnabled B, inputModeRaw S=speak, autoPlay B, modelRaw S, deckIDsRaw [S], deckLabel S, paperTitle S?, paperContext S?, jobTitle/jobContext/jobCompany/jobLocation/jobURL S?=nil, interviewRoundRaw/interviewFormatRaw/jobSnapshotFile/jobPostingIDRaw S?=nil, stammtischData Da?=nil, usesResume B=false, summaryData Da? [ConversationSummary], savedVocabData Da? [SavedVocabItem] | messages →[ChatMessage] cascade | random | 39: Gespräch, Home, Progress, Library | ✓ durationSeconds counter, updatedAt max, savedVocab set by lowercased german | **TutorChatRecord** protocol (`Services/Tutor/ConversationHost.swift`, **android-port only**); ConversationConfig, ConversationSummary and SavedVocabItem are in the core |
| **ChatMessage** | id U, roleRaw S, text S, createdAt Dt, sortOrder I, correctedText/correctionNote/correctionHint S?, selfCorrected B=false, correctionTranslationText S?, targetWordsUsed [S], usedHint B=false, usedPhraseHelper B=false, reviewedWords [S]=[], confirmedClean B=false, translationText S?, translationViewed B=false | conversation → ChatConversation? | random | 9 | ✓ append, with 5 flags merged by or | **TutorChatMessage** protocol; ChatRole is in the core |
| **LearnedPhrase** | id U, german S, english S, scenarioTagsRaw [S], focusAreasRaw [S], creatorModelRaw S, isActive B, surfacedCount I, lastSurfacedAt Dt?, createdAt Dt, note S? | none | random | 9: phrase helper | ✓ surfacedCount/lastSurfacedAt max | LearnedPhraseItem (german/english only, core) |

### 1e. Stories, reading and papers

| Model | Fields | Id | Refs / features | Sync | Twin |
|---|---|---|---|---|---|
| **StudyStory** | id U, createdAt Dt, title, topic, levelRaw S, genreRaw S?, storyText S, englishText S?, glossaryData/questionsData/speakersData/imagesData/lookupsData Da?, modelRaw S?, deckIDRaw S?, macPictureRequestData/ResultData Da?=nil, generationComplete B, bestScore I?, lastStudiedAsListening B, keyPointsData Da?=nil, easyReading B=false, plus 5 `@Transient` caches | random | 31: Stories, Hören, queue | ✓ only once `generationComplete`; bestScore max; lookups set | StoryQuestion and GlossaryEntry sit in the model file |
| **StoryReadingSession** | id U, date Dt, storyID U, storyTitle S, levelRaw S, seconds I, wasListening B, lookups I, wordsSaved I, wordsRead I=0 | random | 11 | ✓ append | none |
| **StoryQuizAttempt** | id U, date Dt, storyID U, storyTitle, levelRaw S, questionCount, correctCount, durationSeconds I, wasListening B, writtenCount I | random | 17: Home, Progress | ✓ append | none |
| **StudyPaper** | id U, title S, createdAt Dt, fullText S, sourceURL S?, germanSummary S?, keyPoints [S], questionsData Da? [StudyQuestion], deckIDRaw S?, modelRaw S?, generationComplete B | random | 14: Paper/PhotoScan | ✓ generationComplete or | StudyQuestion sits in the model file |

### 1f. Writing

| Model | Fields | Id | Refs | Sync | Twin |
|---|---|---|---|---|---|
| **JournalEntry** | every field has a default: id U, createdAt/updatedAt Dt, day Dt=startOfDay, kindRaw=tagebuch, title "", text "", levelRaw=a2, promptID/promptDE/promptEN/promptSourceRaw/promptFocusRaw S?=nil, targetMin/targetMax I=0, inkHeight/inkStrokeCount I=0, inkPaperRaw "white", transcriptConfirmedAt Dt?, checkData Da? [WritingCheck], checkedAt Dt?, checkedModelID S?, checkedTextHash S?, sharedWithCoachAt Dt?, lookupsData Da? [JournalLookup], creditedWords I=0 | random; `day` travels as a day key | 18: Schreiben | ✓ updatedAt/sharedWithCoachAt/creditedWords max; lookups set lwwBy `at` | WritingCheck and JournalLookup sit in the model file |
| **SchreibblattSheet** | id, createdAt, updatedAt, title "", repetitions=5, prefillEnglish=true, paperRaw "a4", arrangementRaw "pages", notebookLines=false, englishColumnWidth D=0, wordsData/sourceDeckIDsData Da?, inkFileName S?, strokeCount I=0, finishedAt/loggedAt Dt?, seriesID U?, partIndex/partCount I=0, seriesTitle "" | none | 17: Schreibblatt | **local-only** (no codec) | none |

### 1g. Class notes (Deutschkurs)

| Model | Fields | Rel | Refs | Sync |
|---|---|---|---|---|
| **ClassCourse** | id U, createdAt/updatedAt Dt, name S, kindRaw="course", teacher/teacherEmail/courseURL/goal/levelRaw S?=nil, startDate/endDate Dt?=nil (travel as `startDay`/`endDay` day keys), isArchived=false, deckIDRaw S?, sortOrder=0, meetingWeekdaysRaw "", meetingMinutes=-1, nextSessionAt Dt?, questionsData Da? | entries →[ClassEntry] cascade | 43 | ✓ updatedAt max |
| **ClassEntry** | id, createdAt, updatedAt, date Dt (travels as `day`), title "", notes "", grammarFocusRaws [S]=[], topics [S]=[], wordsData Da? [ClassWord], homework "", homeworkDue Dt? (as day key), homeworkDone=false, recallData Da?, teacherCorrectionsData Da? | course → ClassCourse?; materials →[ClassMaterial] cascade | 27 | ✓ only with a course; updatedAt max; words/teacherCorrections are sets by id |
| **ClassMaterial** | id, createdAt, title "", sourceKindRaw "paste", text "", snapshotFile S?, lookupsData, modelRaw, glossaryDeckIDRaw, translationData [HandoutTranslation], translationModelRaw, originIDRaw, worksheetData [WorksheetSetup], worksheetAnswersData, redoDatesData (all optional, =nil) | entry → ClassEntry? | 39 | ✓ only when its entry syncs; lookups set |

All three use random UUIDs. HandoutTranslation and WorksheetSetup are already separate files;
ClassWord sits in `ClassEntry.swift`.

### 1h. Job prep, drawing and the rest

| Model | Fields | Id | Refs / features | Sync |
|---|---|---|---|---|
| **JobPosting** | id, createdAt, updatedAt, title S, company/location/sourceURL S?=nil, sourceKindRaw "paste", text S, snapshotFile S?, lookupsData Da?, deckIDRaw/modelRaw S?, readingSeconds I=0, lastOpenedAt Dt?, adoptedFromChatIDRaw S? | random | 20: JobPrep | ✓ readingSeconds counter; updatedAt/lastOpenedAt max; lookups set |
| **Resume** | id, createdAt, updatedAt, fullText "", sourceRaw "", kurzprofil "", factsData Da? [ResumeFact] | random | 12: JobPrep, tutor | **local-only** (never leaves the device) |
| **WordArtwork** | id U, wordKey, germanWord, english, kindRaw S, styleRaw/modelID/prompt S?, fileName S, inkFileName S?, createdAt Dt, starred=false, modeRaw S?, recalled B?, inProgress=false, sourceArtworkID U? | random; bytes in `WordArt/` files | 12: Zeichnen | ✓ LWW |
| **WordDrawingStat** | key, germanWord, english S, quickCount/studioCount/paintedCount/recallRight/recallMissed I=0, lastQuickAt/lastStudioAt/lastPaintedAt Dt? | natural key `key` | 7 | ✓ counters, max dates, perStore |
| **QuickDrawSet** | id, name S, createdAt, updatedAt, cardIDsData Da? [UUID] (travels as `cardIDs` [S]) | random | 7 | ✓ LWW |
| **BatchJob** | id, createdAt, sortOrder, kindRaw, statusRaw, topic, errorMessage S?, completedAt Dt?, the deck generation options (generatorRaw, wordCount, includeExamples, includeGender, wordTypeFilterRaw, includeConjugations, selectedTenses, withImages), the story options (storyLevelRaw, storyGenreRaw, storyQuestionCount, storyQuestionKindsRaw, storyImageCount, weaveWords), targetDeckID/resultDeckID/resultStoryID U? | random | 8: overnight queue | **local-only** (invariant 7) |
| **SyncRecordState** | recordName, kind, localKey S?, serverStamp Da?, lastSeenTag S?, serverPayload/pendingPayload/heldPayload Da?, heldReason S?, needsUpload/pendingDelete B, failureCount I, lastError S?, updatedAt Dt=distantPast, serverBytes/fileBytes I. `#Index` on recordName, localKey, kind | none | 10: sync | bookkeeping |
| **SyncMeta** | historyToken Da?, initialScanDone B, bootstrapSlot S?, canonicalizedVersion I | singleton | 3 | bookkeeping |

Apart from these models, `SyncDocuments.swift` syncs records that don't come from SwiftData:
`Progress` (UserDefaults: level, badges, flags), `Journey`, `PlacementAttempts`, `Voices` and
`File`. Each has a fixed name `make("progress")` etc. These belong in the same record store
later.

**Blob types that block Android:** many `Data` fields decode to structs that are declared
*inside* SwiftData files: GrammarSkill, VocabTouch, LexicalSlip, SelfReportNote, StoryQuestion,
GlossaryEntry, StudyQuestion, ClassWord, WritingCheck, JournalLookup, HoerenItem,
KasusRound.CaseTally, ResumeFact and StoredConjugation. Each one has to be moved into a
Foundation-only file, the same way `ChatRole` and `GrammarTerms` were, before Android can read
those fields as anything but opaque JSON.

## 2. Sync codecs as the shared schema

How a codec describes a model today (`Services/Sync/SyncCodec.swift`, `Codecs/*.swift`,
3,390 lines):

- `static let spec: SyncKindSpec(kind:, generation:, rules: [field: SyncFieldRule], groups:,
  normalize:)` gives the merge semantics per field: lww, counter, counterMap, max, min, or,
  union, minMap, set(idField…), keyed, plus field groups. `SyncKindSpec` already lives in
  `Services/Sync/Core/SyncMerge.swift`, which is in the Android core.
- `recordName(for:)` returns `<Kind>:<UUID>`, from `model.id` or
  `SyncRecordName(kind:naturalKey:)`. The singleton helpers are `SyncSingletonDecks` (in
  `DeckCodecs.swift`), `SyncDayKey` (in `StudyDayCodec.swift`),
  `LearnerProfileCodec.singletonName` and `GameStatSync.roundKey`.
- `known(_:) -> SyncPayload` builds a flat JSON object through `SyncFields.set`. It writes
  every field, with `nil` as `.null`. Dates are seconds since 2001, UUIDs are strings, `Data`
  blobs are parsed JSON (with a `base64:` fallback), and counters are plain integers.
- `find/insert/update(from:)/parent/includes/bootstrap/cascadeChildren` work on
  `ModelContext` and are SwiftData-bound. `update` lists the fields a second time, and a
  "Field coverage" comment block lists them a third time.
- The registry order means parents come before children. `SyncRecordLogic` and `SyncMerge`
  (both in the core) do the compose and merge.

Can the codecs become the shared schema for Android? **Yes, as the payload schema, after a
split.** The portable half is the spec, the record-name derivation, the parent field and the
field names and encodings. That is everything Android needs to write records iOS can read.
It isn't declarative today, though: the field list is imperative code reading the `@Model`.
Proposed split, behaviour-neutral on iOS:

1. Move `SyncSingletonDecks`, `SyncDayKey`, `GameStatSync.roundKey`/`tallyJSON`, the Kasus
   and archived natural keys, and every codec's `spec` into
   `Services/Sync/Core/Kinds/<Aggregate>Kinds.swift`. These must be Foundation-only. The iOS
   codecs then say `static let spec = SavedCardKind.spec`. sync.mdx step 1 already plans this
   for SavedCard.
2. Add a value record per kind in the core (`struct CardRecord: KarteiRecord`). Its stored
   properties are the payload fields, with `init(payload:)` and `var payload`. They are the
   `known`/`update` halves, written once.
3. Later, and optionally, make the iOS codecs delegate: `known(c) = CardRecord(c).payload`
   and `update(c, flat) = CardRecord(payload: flat).apply(to: c)`. This needs an iOS test per
   kind showing that a fully populated SwiftData row gives byte-identical canonical payloads
   before and after.
4. Gate every step with an iOS test: for each kind, build a populated SwiftData row and check
   `Codec.known(row) == Record(row).payload`. On Android, check
   `Record(payload:).payload == payload` for golden payloads exported from iOS.

The special encodings must be copied exactly: day keys (StudyDay, JournalEntry,
ClassCourse/Entry), `cardIDs` as strings, tallies as counterMap objects, LearnerProfile without
`id`, and Wortschatz content never overwritten.

## 3. Technology options (native Swift on Android)

| Option | Builds natively for Android? | Notes | Verdict |
|---|---|---|---|
| **SkipSQL / SkipSQLPlus** (skiptools/skip-sql, **0.16.1**, 2026-10; 0.16.0 brought SQLite 3.51.3 and SQLCipher 4.14.0) | Docs: "with SkipFuse on Android, it communicates directly through Swift's C integration". The 0.12 release notes say "Enable building SkipSQLPlus natively for Android". **The source shows the plain `SkipSQL` `.platform` config calls `fatalError("…on Android you need to use SQLPlus")`** when `SQLite3` can't be imported, so native Android must use `SQLContext(configuration: .plus)` | SQLPlus bundles SQLite (`SQLExt` C target: FTS5, JSON1, RTREE, session, snapshot) and SQLCipher (`PRAGMA key`, `sqlcipher_export`). API: `SQLContext(path:flags:configuration:)`, `exec`, `prepare`, `selectAll`, `transaction`, `migrate(migrations:)` (user_version; each step in a transaction), `onUpdate` hook, `trace`. `SQLCodable`/`SQLTable`/`SQLColumn` give light typed mapping and FK joins; it isn't an ORM. No locking of its own, so give it one actor (MainActor here). The product is `.dynamic` and depends on SkipFoundation and SkipFFI, which are inert in native mode | **Recommended** |
| **GRDB** (v7.12.0, 2026-11; v7.10 "brings GRDB to Android") | Swift Package Index lists Android as building. But the package links SQLite through `.systemLibrary("GRDBSQLite")`, and neither the NDK nor the local Swift SDK for Android ships a `libsqlite3` (I checked the artifactbundle). You'd have to build and supply one, as is done for llama, or fork GRDB to use a source SQLite. SQLCipher needs a fork | The richest API: migrations, Codable records, `ValueObservation`, WAL pools. Heavier, and a fork to maintain if we want encryption | Runner-up |
| **Raw SQLite C** | The NDK has no public SQLite. The platform `libsqlite.so` is private, and apps can't link it since API 24. So "system module" here means vendoring the amalgamation, e.g. `swiftlang/swift-toolchain-sqlite` ("validated for … Android") | About 300 lines of our own wrapper, with no encryption. `WiktionaryValidator` already uses `import SQLite3` this way on iOS | Fallback if SkipSQLPlus won't build |
| **Room via a Kotlin bridge** | Yes, as transpiled or bridged Kotlin | The schema and DAOs would be written in Kotlin with KSP: a second copy of every model in another language, with every query crossing JNI. That breaks "keep logic in Swift" | No |
| **Plain JSON files** (sync.mdx step 1 as written) | Trivial | Fine for about 3k reviewed cards. Chats, messages, stories and logs grow without bound, the whole file is rewritten on every review, and there are no queries or partial loads | Stopgap only |
| SwiftData | Not available on Android; Skip's FAQ points to SkipSQL | | n/a |

**Why SkipSQLPlus:**
- It's maintained by the Skip team for exactly this setup: Fuse native, which the project
  already uses.
- It carries its own SQLite, so the version is the same on every phone and JSON1 and
  expression indexes are always there.
- SQLCipher is available if we ever want encryption at rest, and the same package works on
  iOS.
- Its `SQLExt` headers should also let `WiktionaryValidator` (42 MB `wiktionary_de.db`) compile
  on Android with `#if canImport(SQLite3) … #else import SQLExt`.

**Where it goes:** a new target `KarteiStore` in `DieKarteiAndroid/Package.swift`, depending on
`DieKarteiCore` and the `SkipSQLPlus` product. That keeps skip-sql out of the plain core, which
iOS tests build. The protocols and records stay in the core.

**Not verified** (read-only rule: no builds were run):
- SkipSQLPlus building with Swift 6.4.3 and SDK android28 from a non-Skip native target.
- Its APK size cost (SQLite + SQLCipher + libtomcrypt per ABI).
- Whether `SQLExt` can be imported from a client module.
- `onUpdate` working in native mode.
- GRDB actually linking on Android.

Step 0 of the build plan settles these.

## 4. Schema: generic records vs typed tables

**Recommended: one generic `record` table.** The payload is the iOS codec's `known` shape, and
a few typed index columns are written from Swift by each kind.

```sql
-- migration 1 (SkipSQL migrate(), user_version = 1)
CREATE TABLE record (
  kind        TEXT NOT NULL,     -- "SavedCard" (= SyncKindSpec.kind)
  id          TEXT NOT NULL,     -- UUID; record name = kind:id (natural keys already hashed)
  payload     BLOB NOT NULL,     -- canonical JSON, flat: exactly SavedCardCodec.known(...)
  parent      TEXT,              -- parent record id (card/result→deck, message→chat, entry→course…)
  natural_key TEXT,              -- stat key, roundKey, day key: for find-by-natural-key
  day         TEXT,              -- yyyy-MM-dd (StudyDay, journal, rounds)
  due         REAL,              -- SavedCard.nextReviewDate (s since 2001); NULL = new
  sort        REAL,              -- per-kind list order (updatedAt, createdAt or sortOrder)
  updated_at  REAL NOT NULL,     -- local write time
  server      BLOB,              -- SyncRecordCopies.server   (empty until a transport exists)
  pending     BLOB,              -- SyncRecordCopies.pending  (composed: counter slots per replica)
  held        BLOB, held_reason TEXT,          -- payload whose parent hasn't arrived / newer _b
  needs_upload INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (kind, id)
) WITHOUT ROWID;
CREATE INDEX record_parent ON record(kind, parent, sort);
CREATE INDEX record_due    ON record(kind, parent, due) WHERE due IS NOT NULL;
CREATE INDEX record_day    ON record(kind, day) WHERE day IS NOT NULL;
CREATE INDEX record_sort   ON record(kind, sort);
CREATE INDEX record_nk     ON record(kind, natural_key) WHERE natural_key IS NOT NULL;
CREATE TABLE tombstone (kind TEXT, id TEXT, deleted_at REAL, server BLOB, PRIMARY KEY(kind, id));
CREATE TABLE meta (key TEXT PRIMARY KEY, value BLOB);  -- store id, migration flags, schema notes
```

The queries the app needs are all single-index lookups:

| Need | Query |
|---|---|
| Decks list | `kind='SavedDeck' ORDER BY sort DESC` (createdAt), skipping singleton generators in code |
| Due cards | `kind='SavedCard' AND parent=:deck AND due <= :now ORDER BY due LIMIT n`. New Wortschatz words come from the bundle order minus the reviewed set |
| Cards of a deck | `kind='SavedCard' AND parent=:deck ORDER BY sort` |
| Study days in a range / streak | `kind='StudyDay' AND day BETWEEN :a AND :b` |
| Chats list | `kind='ChatConversation' ORDER BY sort DESC` (updatedAt) |
| Messages | `kind='ChatMessage' AND parent=:chat ORDER BY sort` |
| Stats by word | `kind='ArticleWordStat' AND id=:uuid5(key)` (primary key) |
| Ad hoc | `json_extract(payload,'$.field')` (SQLPlus has JSON1) |

Why not typed tables (one table per model, one column per field):
- **The sync plan already uses this shape.** The store holds iOS's records, so sync steps 1–3
  are a `SELECT`. A Drive file is `[recordName: SyncRecordCopies]`. `SyncRecordState`'s 16
  fields fold into four columns.
- **iOS-readable by construction.** An Android row is exactly what `Codec.insert/update(from:)`
  reads on iOS, unknown fields included (invariant 6: older builds keep newer fields because
  local changes compose on the last copy).
- **Migrations.** iOS adds fields often: JournalEntry, ChatConversation and ClassCourse all
  carry `= default` additions. Typed tables would need an `ALTER TABLE` for every iOS field,
  on 35 tables with about 450 columns, all kept in step by hand. With JSON payloads, a new
  field means a new property on the record struct and a default when it's absent. DDL changes
  only for a new index column.
- **One code path** for put, cascade, tombstone, compose and backup across all 30 kinds.
  Adding a feature later means adding a record struct, not a table.

Costs and how to handle them:
- **JSON decode per row.** Cheap at this scale: hundreds of decks and chats, and only
  *reviewed* Wortschatz cards are stored, as on iOS's sync include rule; the bundle supplies the
  other ~2.8k. Cache the decoded arrays per kind in the @Observable stores.
- **No FK cascade.** Implement `delete(kind,id)` as a recursive delete over `parent`, using the
  five relationships from §1. Write tombstones for synced kinds.
- **Weak typing in SQL.** All access goes through typed `KarteiRecord` structs, and nothing
  reads `payload` except their `init(payload:)`.
- **Large text** (story text, handouts) stays in the payload, as on iOS. Binary files (ink,
  pictures, PDFs) stay files under the same relative names iOS uses (`WordArt/`,
  `ClassMaterialStore`, card `imageFileName`).

**Device id and backup:**
- Keep the replica id in `noBackupFilesDir`, **outside** the database, so Auto Backup never
  restores it (sync.mdx step 2).
- Run `PRAGMA journal_mode=WAL`, and on backgrounding run `wal_checkpoint(TRUNCATE)`, so a
  backup never catches a half-applied WAL.
- Auto Backup has a 25 MB per-app quota. The DB fits; the pictures may not.

## 5. Swift API

**Core (Foundation-only, `Services/Sync/Core/Records/` + `Services/Stores/`):**

```swift
protocol KarteiRecord: Sendable, Hashable {
    static var spec: SyncKindSpec { get }           // moved from the codec
    var recordName: SyncRecordName { get }          // same derivation as the codec
    init(payload: SyncPayload) throws               // ≙ Codec.update(from:)
    var payload: SyncPayload { get }                // ≙ Codec.known(_:)
    var index: RecordIndex { get }                  // parent / naturalKey / day / due / sort
}
// Spine records: DeckRecord, CardRecord, QuizResultRecord, StudyDayRecord,
// LearnerProfileRecord (+ GrammarSkill/VocabTouch/LexicalSlip/SelfReportNote moved out),
// ConversationRecord, MessageRecord, PhraseRecord.

@MainActor protocol DeckStoring: AnyObject {
    func decks() -> [DeckRecord]
    func cards(inDeck id: UUID) -> [CardRecord]
    func dueCards(inDeck id: UUID, asOf: Date, limit: Int?) -> [CardRecord]
    func wortschatzProgress() -> [String: CardRecord]       // reviewed cards by exact word
    func save(_ card: CardRecord)
    func save(_ deck: DeckRecord, cards: [CardRecord])      // .kartei import, generation
    func delete(deck id: UUID)                              // cascades cards + results
    func add(_ result: QuizResultRecord)
}
@MainActor protocol StudyLogStoring: AnyObject {
    func record(_ activity: StudyActivity, seconds: Int, now: Date)
    func recordTime(_ bucket: StudyTimeBucket, seconds: Int, now: Date)
    func days(from: Date, to: Date) -> [StudyDayRecord]
}
@MainActor protocol LearnerProfileStoring: AnyObject {
    var profile: LearnerProfileRecord { get }
    func update(_ change: (inout LearnerProfileRecord) -> Void)
}
@MainActor protocol ConversationStoring: AnyObject {
    associatedtype Host: ConversationHost
    func conversations() -> [ConversationRecord]            // list rows, no messages
    func open(_ id: UUID) -> Host?
    func create(_ config: ConversationConfig) -> Host
    func delete(_ id: UUID)
}
@MainActor protocol PhraseStoring: AnyObject { func phrases(active: Bool) -> [PhraseRecord]; func save(_ p: PhraseRecord) }
```

`ConversationHost`, `TutorChatRecord`, `TutorChatMessage`, `ConversationReviewing`,
`SpeechInput` and `SpeechOutput` already exist in `Services/Tutor/ConversationHost.swift`, but
**only on android-port** (commit 229eda4; iOS `main` has no `Services/Tutor`). Land them on main
first. `ConversationStoring` only adds list, open, create and delete around them. Android's
`TutorStore` swaps its in-memory record classes for record-backed ones: classes conforming to
`TutorChatRecord`/`TutorChatMessage` whose `save()` writes `ConversationRecord`/`MessageRecord`.

**Shared read logic, the SRSCardState pattern:** the pure functions take a protocol that both
the `@Model` and the record adopt.
- `StudyLogService`'s streak, `todayNewWords`, `newWordBudgetRemaining` and `timeSummary`
  move to the core over `protocol StudyDayCounts { var dayStart: Date { get }; var
  cardsReviewed: Int { get } … }`, with `extension StudyDay: StudyDayCounts {}` on iOS.
- `StudyActivity`/`StudyTimeBucket` move out of `StudyLogService.swift` into a Foundation file.
- Cards keep `SRSCardState`. Android's `StudyCard` wrapper holds a `CardRecord` instead of
  `CardProgress`.

**iOS adopts gradually, with no behaviour change:**
1. Moves only (specs, keys, blob structs, StudyActivity): xcodebuild plus the sync tests.
2. SwiftData adapters, e.g. `struct SwiftDataStudyLog: StudyLogStoring { let context:
   ModelContext }`, which call today's `StudyLogService.record`. They're used only by services
   as those services move into the core (StoryStudyService, PaperStudyService, …). Views keep
   `@Query`. Nothing is rewritten.
3. Optional: codecs delegate `known`/`update` to the records (§2.3), proven byte-identical.

**Change notifications on Android:**
- `KarteiStore.RecordDB` (MainActor, one `SQLContext`, `.plus`) bumps a per-kind `revision`
  after each committed transaction. That covers learner writes and, later, sync-apply writes,
  which replace iOS's `.syncedFileLanded`.
- The Android stores are `@Observable` classes in the UI module (`import SkipFuse`), e.g.
  `final class DeckStore: DeckStoring`. Their computed lists read `db.revision[kind]` and
  cache decoded records, so Compose recomposes on change.
- Any `@Observable` type placed in the core uses `#if os(Android) import SkipFuse #endif`
  (README: `canImport` is wrong here). Otherwise the screen freezes on its first state.
- Keep the `onUpdate` hook as a DEBUG check that every write went through the store.

## 6. Migrating Android's `StudyStore` to iOS ids

Today the progress lives in UserDefaults `studyProgress.v1` as `[String: CardProgress]`, keyed
`"<A1|A2|B1>:<word>"`. `sortOrder` is the index within the level list.

One-time migration, run when `KarteiStore` first opens (`meta.migrated.studyProgress.v1`
absent):
1. `deckID = SyncSingletonDecks.deckID(generatorRaw: "goethe-srs", topic: "Goethe
   Vocabulary")`, which is `DeckStore.wortschatzTopic` on iOS. Write the `DeckRecord` with
   iOS's values: wordCount = `orderedWords.count`, includeExamples, includeGender.
2. For each key, `word = key.split(":", maxSplits: 1)[1]`. Group by the exact word, with no
   lowercasing: `sie`/`Sie` are two cards on iOS.
3. When a word has progress on several levels (A1 and A2 both list it), merge with
   `SavedCardSpec` semantics:
   - take the schedule group from the later `lastReviewedAt` (tiebreak repetitions, interval,
     ease);
   - sum `totalReviews` and `lapses`, since they were separate reviews on this device;
   - take the minimum `firstReviewedAt`.
4. `id = SyncSingletonDecks.cardID(deckID:germanWord:)`. `sortOrder` = the index in
   `GoetheVocabService.orderedWords`, not the level index. Content (translation, article,
   example, formsLine) comes from `GoetheVocabService.index[word]`. Drop words iOS has no card
   for (no translation) and log how many.
5. Credit the counters to the per-store bootstrap slot (`"store-" + storeID`, as iOS does for
   singleton-deck cards, `SyncBootstrap.perStore`) when composing `pending`.
6. Do it all in one transaction, then set the flag. Keep the UserDefaults blob for one release
   (rollback), then delete it.
7. The level becomes a filter only: `GoetheWord.levels`. `stats(for:)` and `reset(level:)`
   query the reviewed cards whose word is in that level's list.

Tests (core, `swift test`):
- A fixture blob with a cross-level duplicate, a `sie`/`Sie` pair, a word containing `:` and a
  word without a translation.
- Assert the ids against golden UUIDs from an iOS test that calls the same `SyncNameUUID`.
- Merge rules: summed counts, min first-review date, later schedule.
- Running the migration twice changes nothing.

## 7. Build plan (phase 1)

Every step is verified with `swift test` (core / KarteiStore on the macOS host), with
`skip app launch --android` plus a tap-through, a restart to prove persistence and
logcat clean of FATAL, and with xcodebuild plus the sync tests for any iOS-side move.

| # | Step | Verifiable outcome | Effort | Unblocks |
|---|---|---|---|---|
| 0 | **Spike:** add skip-sql 0.16.1 `SkipSQLPlus` to a `KarteiStore` target; open `files/kartei.sqlite`, run `migrate`, insert and select | logcat shows `sqlite_version()` 3.51.3 on the emulator; APK size delta recorded; `swift test` passes on the Mac. If it fails, fall back to swift-toolchain-sqlite plus a thin wrapper | S | everything below |
| 1 | **Move specs and keys into `Services/Sync/Core`** (SyncSingletonDecks, SyncDayKey, the 8 spine specs, LearnerProfile name), plus `StudyActivity`/`StudyTimeBucket` and the LearnerProfile blob structs into Foundation files. Land on main | iOS builds; sync and FakeSyncServer tests pass; `core_sync.py --prune` picks the files up | S | 2, sync step 1 |
| 2 | **Spine records:** Deck, Card, QuizResult, StudyDay, LearnerProfile, Conversation, Message, Phrase, with `RecordIndex` | iOS test: `Codec.known(fullRow) == Record(fullRow).payload` for all 8. Core test: payload round trip | M | 3–7 |
| 3 | **RecordDB** in KarteiStore: schema v1, put/get/query, cascade delete, tombstones, transactions, revisions, meta, WAL checkpoint | Host tests: CRUD, a cascade (deck→cards→results), revision bumps, migration idempotent. Emulator: data survives force-stop | M | 4–9 |
| 4 | **DeckStoring and Wortschatz on RecordDB,** plus the StudyStore migration (§6); Karten, Home "due today" and Settings reset read from it | Migration tests green; on the emulator, rate 5 cards, restart, and the due counts match; ids equal the iOS golden | M | Library decks, Matching, `ConversationReviewing` (due words in chat), `.kartei` import |
| 5 | **StudyLogStoring:** cards, grammar, Hören, Spiele and tutor time write StudyDay; streak and new-word budget come from the shared `StudyDayCounts` logic | Test: day keys across time zones (Berlin vs NY) and range queries. Emulator: Home streak 1 after a session, and still there after a restart | S–M | streak, daily goal ring and XP, reminders, Progress calendar |
| 6 | **LearnerProfileStoring** (singleton record name) wired into `sessionSummarized` | Test: canonical name equals iOS. Emulator: after a chat, the profile vocab shows the words | S | tutor memory, Förderplan, grammar progress, placement level |
| 7 | **ConversationStoring and PhraseStoring:** TutorStore persists `ConversationRecord`/`MessageRecord`; Library ▸ Chats segment; saved phrases | Emulator: chat, kill the app, reopen, and messages, corrections and summary are all there; delete cascades | M | saved chats, LearnedPhrase helper, Stammtisch, job-interview chats |
| 8 | **QuizResult writes and `.kartei` import** (split `DeckTransferEnvelope` out) | Emulator: open a `.kartei` exported from iOS; deck and cards appear; a session adds a result | S–M | user decks, deck mix |
| 9 | **Sync-shaped writes:** every put runs `SyncRecordLogic.noteLocal` with this install's replica slot; device id in `noBackupFilesDir`; Auto Backup rules include only the DB and settings | Two simulated devices merge per sync.mdx step 1. `bmgr backupnow` → uninstall → restore brings progress back with a new device id | S–M | Drive sync (sync.mdx step 3) |
| 10 | **iOS reads Android:** export Android records as golden JSON; an iOS test applies them through `Codec.insert/update` into an in-memory container | the iOS test passes for all 8 spine kinds | S | iPhone↔Android later |

After the spine, each feature gets a record struct and its own small store, with no schema
change. Rough order: grammar and game stats plus rounds (Matching, Article, Preposition),
KasusRound and GeneratedKasusStory (after the Kasus value-type split), HoerenRound, then
StudyStory, ReadingSession, QuizAttempt and StudyPaper (needs StoryQuestion/GlossaryEntry
moved out), then JournalEntry, the ClassCourse/Entry/Material trio, JobPosting, the drawing
kinds (they need the ink module), `SyncDocuments` kinds (Progress, Journey, Placement), and
finally the local-only BatchJob, Resume and SchreibblattSheet (records with no sync columns
in use).

Phase total: about M–L. Steps 0–5 are the critical path, at about two weeks. Steps 6–10 can
interleave with phase 6 tutor work.

## 8. Open questions

- Is `SchreibblattSheet` being local-only intentional long term? The docs say it isn't in
  SyncRegistry; its words count toward StudyDay, which does sync.
- Should we encrypt at rest (SQLCipher with a key in the Android Keystore through
  skip-keychain)? It isn't needed for parity, since iOS relies on file protection only.
- ConversationHost and the other android-port core splits must land on main before iOS can
  adopt `ConversationStoring`. Check branch distance live before advising the merge.
