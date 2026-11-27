//
//  SyncGoldenTests.swift
//  german-ai-flashcardsTests
//
//  The contract between the iOS sync codecs and the shared records the Android store keeps
//  (`Services/Sync/Core/Records`). Both sides are held to one file of golden payloads,
//  `DieKarteiCore/Tests/DieKarteiCoreTests/sync_golden.json`:
//  - here, fully populated SwiftData rows must produce exactly those payloads (`known`), and the
//    payloads must apply back into rows (`insert`) that produce them again: iOS reads what
//    Android writes;
//  - in DieKarteiCore (`SyncRecordTests`, run on the Mac), every record must read and write
//    those payloads unchanged: Android writes what iOS reads.
//
//  Changed a codec on purpose? Regenerate the file, review the diff, then run both suites:
//    TEST_RUNNER_SYNC_GOLDEN_WRITE=1 xcodebuild test … -only-testing:german-ai-flashcardsTests/SyncGoldenTests
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@MainActor
@Suite struct SyncGoldenTests {
    static let goldenURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("DieKarteiCore/Tests/DieKarteiCoreTests/sync_golden.json")

    struct Sample {
        let kind: String
        let label: String
        let name: SyncRecordName
        let payload: SyncPayload
    }

    static let models: [any PersistentModel.Type] = [SavedDeck.self, SavedCard.self, QuizResult.self, StudyDay.self,
                                                     LearnerProfile.self, ChatConversation.self, ChatMessage.self,
                                                     LearnedPhrase.self]

    static func t(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

    /// Every spine kind twice: every field set, and only what the initializer sets. Parents first.
    static func samples(in context: ModelContext) -> [Sample] {
        let full = SavedDeck(topic: "Reise", wordCount: 12, includeExamples: true, includeGender: false,
                             wordTypeFilter: .nouns, includeConjugations: true,
                             selectedTenses: ["Präsens", "Perfekt"], createdAt: t(815_000_000.25))
        full.id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        full.generatorRaw = "gemma-e4b"
        full.generationTimeSeconds = 12.5
        full.courseIDRaw = "22222222-2222-4222-8222-222222222222"
        full.sourceText = "Wir fahren nach Berlin."
        full.sourceFile = "handout.pdf"
        full.macPictureRequestData = Data(#"{"id":"r1","words":["Hund","Katze"]}"#.utf8)
        full.macPictureResultData = Data(#"{"done":["Hund"],"request":"r1"}"#.utf8)

        let bare = SavedDeck(topic: "Leer", wordCount: 0, includeExamples: false, createdAt: t(815_000_100))
        bare.id = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

        let wortschatz = SavedDeck(topic: DeckStore.wortschatzTopic, wordCount: 2825, includeExamples: true,
                                   includeGender: true, createdAt: t(815_000_200))
        wortschatz.generatorRaw = "goethe-srs"
        wortschatz.id = SyncSingletonDecks.deckID(generatorRaw: wortschatz.generatorRaw, topic: DeckStore.wortschatzTopic)

        for deck in [full, bare, wortschatz] { context.insert(deck) }

        let card = SavedCard(germanWord: "fahren", englishTranslation: "to drive", wordType: "verb",
                             article: nil, exampleSentence: "Wir fahren morgen.", sortOrder: 3,
                             formsLine: "fährt · ist gefahren")
        card.id = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        card.conjugationsData = Data(#"[{"du":"fährst","erSieEs":"fährt","ich":"fahre","ihr":"fahrt","sieSie":"fahren","tense":"Präsens","wir":"fahren"}]"#.utf8)
        card.imageFileName = "fahren.jpg"
        card.easeFactor = 2.36
        card.interval = 6
        card.repetitions = 2
        card.nextReviewDate = t(815_500_000)
        card.totalReviews = 5
        card.lapses = 1
        card.leitnerBox = 3
        card.lastReviewedAt = t(815_000_400.5)
        card.lastReviewWasCorrect = false
        card.firstReviewedAt = t(814_000_000)

        let bareCard = SavedCard(germanWord: "leer", englishTranslation: "empty")
        bareCard.id = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!

        let sie = SavedCard(germanWord: "Sie", englishTranslation: "you (formal)", wordType: "pronoun",
                            article: nil, exampleSentence: "Kommen Sie aus Berlin?", sortOrder: 41)
        sie.id = SyncSingletonDecks.cardID(deckID: wortschatz.id, germanWord: "Sie")
        sie.easeFactor = 2.6
        sie.interval = 1
        sie.repetitions = 1
        sie.nextReviewDate = t(815_086_800)
        sie.totalReviews = 1
        sie.leitnerBox = 1
        sie.lastReviewedAt = t(815_000_400)
        sie.lastReviewWasCorrect = true
        sie.firstReviewedAt = t(815_000_400)

        let result = QuizResult(totalCards: 10, correctCount: 7, incorrectCardIndices: [1, 4, 9],
                                durationSeconds: 95, date: t(815_000_500), studyMode: .anki,
                                ankiRatings: [0: .good, 1: .again, 2: .easy], subDeckLabel: "Teil 1")
        result.id = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
        let bareResult = QuizResult(totalCards: 1, correctCount: 0, date: t(815_000_600))
        bareResult.id = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!

        for (c, deck) in [(card, full), (bareCard, bare), (sie, wortschatz)] {
            context.insert(c)
            c.deck = deck
        }
        for (r, deck) in [(result, full), (bareResult, bare)] {
            context.insert(r)
            r.deck = deck
        }

        let day = StudyDay(dayStart: SyncDayKey.dayStart(for: "2026-11-27")!)
        for (i, field) in SyncKinds.studyDayCounterFields.enumerated() {
            day.setValue(forKey: field, i + 1)
        }
        day.lastActivityAt = t(816_000_000.75)
        let bareDay = StudyDay(dayStart: SyncDayKey.dayStart(for: "2026-11-28")!)
        // Pinned: the initializer's `dayStart` is local midnight, which depends on the time zone.
        bareDay.lastActivityAt = t(816_100_000)
        context.insert(day)
        context.insert(bareDay)

        let profile = LearnerProfile()
        profile.sessionCount = 4
        profile.lastSessionAt = t(816_200_000.5)
        profile.grammar = ["dativ": GrammarSkill(struggle: 0.4, lastSeen: t(816_200_000), samples: ["mit der Freund → mit dem Freund"])]
        profile.vocab = [VocabTouch(german: "Bahnhof", english: "station", lastSeen: t(816_150_000), timesUsed: 2, pinned: true),
                         VocabTouch(german: "fahren", english: "to drive", lastSeen: t(816_100_000), timesUsed: 1, source: "placement")]
        profile.slips = [LexicalSlip(wrong: "der", right: "dem", note: "mit takes the Dativ", lastSeen: t(816_200_000),
                                     timesSeen: 3, sentence: "Ich fahre mit dem Bus.", blankIndex: 3)]
        profile.selfReports = [SelfReportNote(text: "dem und den nach mit", focus: "dativ", notedAt: t(816_000_000),
                                              entryID: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!)]
        profile.foerderplanData = Data(#"{"current":{"focus":"dativ","startedAt":816000000},"past":[]}"#.utf8)
        let bareProfile = LearnerProfile()
        context.insert(profile)
        context.insert(bareProfile)

        var config = ConversationConfig(model: .hero)
        config.mode = .interview
        config.level = .b1
        config.formality = .sie
        let chat = ChatConversation(config: config, createdAt: t(816_300_000))
        chat.id = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        chat.title = "Vorstellungsgespräch bei der Bahn"
        chat.updatedAt = t(816_300_900.25)
        chat.durationSeconds = 840
        chat.scenarioRaw = "restaurant"
        chat.customScenario = "Beim Bäcker"
        chat.focusRaw = ["dativ", "perfekt"]
        chat.strictnessRaw = "Strict"
        chat.feedbackStyleRaw = "Nudge me"
        chat.correctionsEnabled = false
        chat.inputModeRaw = "Type"
        chat.autoPlay = false
        chat.deckIDsRaw = ["11111111-1111-4111-8111-111111111111"]
        chat.deckLabel = "Reise"
        chat.paperTitle = "Mietvertrag"
        chat.paperContext = "§1 Mietsache"
        chat.jobTitle = "Zugbegleiter"
        chat.jobContext = "Kundenservice im Zug"
        chat.jobCompany = "Deutsche Bahn"
        chat.jobLocation = "Berlin"
        chat.jobURL = "https://example.com/job/1"
        chat.interviewRoundRaw = "screening"
        chat.interviewFormatRaw = "video"
        chat.jobSnapshotFile = "job-1.pdf"
        chat.jobPostingIDRaw = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        chat.stammtischData = Data(#"{"guests":["Lena","Jonas"],"topic":"Urlaub"}"#.utf8)
        chat.usesResume = true
        chat.summaryData = Data(#"{"headline":"Gut gemacht","wins":["Dativ nach mit"]}"#.utf8)
        chat.savedVocabData = Data(#"[{"english":"conductor","german":"Zugbegleiter"},{"english":"timetable","german":"Fahrplan"}]"#.utf8)

        let bareChat = ChatConversation(config: ConversationConfig(model: .hero), createdAt: t(816_400_000))
        bareChat.id = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        context.insert(chat)
        context.insert(bareChat)

        let message = ChatMessage(role: .user, text: "Ich fahre mit der Bus.", sortOrder: 2, createdAt: t(816_300_100))
        message.id = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
        message.correctedText = "Ich fahre mit dem Bus."
        message.correctionNote = "mit + Dativ"
        message.correctionHint = "Which case follows mit?"
        message.selfCorrected = true
        message.correctionTranslationText = "I take the bus."
        message.targetWordsUsed = ["fahren", "Bus"]
        message.usedHint = true
        message.usedPhraseHelper = true
        message.reviewedWords = ["Bus"]
        message.confirmedClean = true
        message.translationText = "I'm going by bus."
        message.translationViewed = true
        let bareMessage = ChatMessage(role: .assistant, text: "Hallo!", sortOrder: 0, createdAt: t(816_400_010))
        bareMessage.id = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
        for (m, c) in [(message, chat), (bareMessage, bareChat)] {
            context.insert(m)
            m.conversation = c
        }

        let phrase = LearnedPhrase(german: "Wie komme ich zum Bahnhof?", english: "How do I get to the station?",
                                   scenarios: [.restaurant], focusAreas: [.dativ], creatorModelRaw: "gemma-e4b",
                                   isActive: false, note: "zum = zu dem", createdAt: t(816_500_000))
        phrase.id = UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!
        phrase.surfacedCount = 3
        phrase.lastSurfacedAt = t(816_600_000)
        let barePhrase = LearnedPhrase(german: "Tschüss", english: "Bye", createdAt: t(816_500_100))
        barePhrase.id = UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!
        context.insert(phrase)
        context.insert(barePhrase)

        return [
            Sample(kind: "SavedDeck", label: "full", name: SavedDeckCodec.recordName(for: full), payload: SavedDeckCodec.known(full)),
            Sample(kind: "SavedDeck", label: "bare", name: SavedDeckCodec.recordName(for: bare), payload: SavedDeckCodec.known(bare)),
            Sample(kind: "SavedDeck", label: "wortschatz", name: SavedDeckCodec.recordName(for: wortschatz), payload: SavedDeckCodec.known(wortschatz)),
            Sample(kind: "SavedCard", label: "full", name: SavedCardCodec.recordName(for: card), payload: SavedCardCodec.known(card)),
            Sample(kind: "SavedCard", label: "bare", name: SavedCardCodec.recordName(for: bareCard), payload: SavedCardCodec.known(bareCard)),
            Sample(kind: "SavedCard", label: "wortschatz", name: SavedCardCodec.recordName(for: sie), payload: SavedCardCodec.known(sie)),
            Sample(kind: "QuizResult", label: "full", name: QuizResultCodec.recordName(for: result), payload: QuizResultCodec.known(result)),
            Sample(kind: "QuizResult", label: "bare", name: QuizResultCodec.recordName(for: bareResult), payload: QuizResultCodec.known(bareResult)),
            Sample(kind: "StudyDay", label: "full", name: StudyDayCodec.recordName(for: day), payload: StudyDayCodec.known(day)),
            Sample(kind: "StudyDay", label: "bare", name: StudyDayCodec.recordName(for: bareDay), payload: StudyDayCodec.known(bareDay)),
            Sample(kind: "LearnerProfile", label: "full", name: LearnerProfileCodec.recordName(for: profile), payload: LearnerProfileCodec.known(profile)),
            Sample(kind: "LearnerProfile", label: "bare", name: LearnerProfileCodec.recordName(for: bareProfile), payload: LearnerProfileCodec.known(bareProfile)),
            Sample(kind: "ChatConversation", label: "full", name: ChatConversationCodec.recordName(for: chat), payload: ChatConversationCodec.known(chat)),
            Sample(kind: "ChatConversation", label: "bare", name: ChatConversationCodec.recordName(for: bareChat), payload: ChatConversationCodec.known(bareChat)),
            Sample(kind: "ChatMessage", label: "full", name: ChatMessageCodec.recordName(for: message), payload: ChatMessageCodec.known(message)),
            Sample(kind: "ChatMessage", label: "bare", name: ChatMessageCodec.recordName(for: bareMessage), payload: ChatMessageCodec.known(bareMessage)),
            Sample(kind: "LearnedPhrase", label: "full", name: LearnedPhraseCodec.recordName(for: phrase), payload: LearnedPhraseCodec.known(phrase)),
            Sample(kind: "LearnedPhrase", label: "bare", name: LearnedPhraseCodec.recordName(for: barePhrase), payload: LearnedPhraseCodec.known(barePhrase)),
        ]
    }

    /// Canonical ids both apps must derive the same way.
    static var ids: [String: String] {
        let deck = SyncSingletonDecks.deckID(generatorRaw: "goethe-srs", topic: DeckStore.wortschatzTopic)
        return [
            "wortschatzDeck": deck.uuidString,
            "card:Sie": SyncSingletonDecks.cardID(deckID: deck, germanWord: "Sie").uuidString,
            "card:sie": SyncSingletonDecks.cardID(deckID: deck, germanWord: "sie").uuidString,
            "learnerProfile": LearnerProfileCodec.singletonName.description,
            "studyDay:2026-11-27": SyncRecordName(kind: "StudyDay", naturalKey: "2026-11-27").description,
        ]
    }

    static func document(_ samples: [Sample]) -> SyncJSON {
        .object([
            "ids": .object(ids.mapValues { .string($0) }),
            "records": .array(samples.map {
                .object(["kind": .string($0.kind), "label": .string($0.label),
                         "name": .string($0.name.description), "payload": .object($0.payload)])
            }),
        ])
    }

    static func loadGolden() throws -> [String: SyncJSON] {
        try #require(SyncJSON(data: Data(contentsOf: goldenURL)).objectValue)
    }

    @Test func theCodecsWriteTheGoldenPayloads() throws {
        let context = ModelContext(ModelContainer.inMemory(Self.models))
        let samples = Self.samples(in: context)
        if ProcessInfo.processInfo.environment["SYNC_GOLDEN_WRITE"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(Self.document(samples)).write(to: Self.goldenURL)
        }
        let golden = try Self.loadGolden()
        #expect(golden["ids"] == .object(Self.ids.mapValues { .string($0) }))
        let records = golden["records"]?.arrayValue ?? []
        #expect(records.count == samples.count)
        for sample in samples {
            let match = records.first { $0["kind"]?.stringValue == sample.kind && $0["label"]?.stringValue == sample.label }
            #expect(match?["name"]?.stringValue == sample.name.description, "\(sample.kind) \(sample.label)")
            #expect(match?["payload"] == .object(sample.payload), "\(sample.kind) \(sample.label) drifted from sync_golden.json")
        }
    }

    /// iOS applies what Android writes: each golden payload goes in through the codec's `insert`
    /// and comes back out of `known` unchanged.
    @Test func theCodecsApplyTheGoldenPayloads() throws {
        let context = ModelContext(ModelContainer.inMemory(Self.models))
        let records = try Self.loadGolden()["records"]?.arrayValue ?? []
        #expect(!records.isEmpty)
        for record in records {
            let kind = try #require(record["kind"]?.stringValue)
            let name = try #require(record["name"]?.stringValue.flatMap(SyncRecordName.init))
            let payload = try #require(record["payload"]?.objectValue)
            let handler = try #require(SyncRegistry.byKind[kind])
            let model = try #require(handler.insert(payload, name: name, in: context), "\(kind) didn't insert")
            #expect(handler.recordName(for: model) == name)
            #expect(handler.known(model) == payload, "\(kind) \(record["label"]?.stringValue ?? "")")
        }
    }

    /// The Wortschatz deck Android builds from records is the one `DeckStore` builds: same ids,
    /// same content, same order, for every word.
    @Test func wortschatzRecordsMatchTheDeckStore() throws {
        let context = ModelContext(ModelContainer.inMemory(Self.models))
        let deck = try #require(DeckStore(modelContext: context).fetchOrCreateWortschatzDeck())
        #expect(SavedDeckCodec.known(deck) == WortschatzRecords.deck(createdAt: deck.createdAt).payload)
        #expect(deck.cards.count > 2000)
        for card in deck.cards {
            let record = try #require(WortschatzRecords.card(for: card.germanWord), "\(card.germanWord)")
            #expect(SavedCardCodec.known(card) == record.payload, "\(card.germanWord)")
        }
        let words = Set(deck.cards.map(\.germanWord))
        let android = GoetheVocabService.orderedWords.compactMap { WortschatzRecords.card(for: $0.word) }
        #expect(android.count == deck.cards.count)
        #expect(Set(android.map(\.germanWord)) == words)
    }

    /// Every kind iOS syncs has its rules in the shared core, and the codecs use them.
    @Test func everySyncedKindIsInTheSharedCore() {
        #expect(SyncRegistry.handlers.map(\.kind) == SyncKinds.all.map(\.kind))
        for handler in SyncRegistry.handlers {
            guard let shared = SyncKinds.byKind[handler.kind] else { continue }
            #expect(handler.spec.rules == shared.rules, "\(handler.kind)")
            #expect(handler.spec.groups == shared.groups, "\(handler.kind)")
            #expect(handler.spec.generation == shared.generation, "\(handler.kind)")
            #expect((handler.spec.normalize == nil) == (shared.normalize == nil), "\(handler.kind)")
        }
        for (kind, link) in SyncKinds.parentField {
            let parent = UUID()
            let name = SyncRegistry.byKind[kind]?.parent(of: [link.field: .string(parent.uuidString)])
            #expect(name == SyncRecordName(kind: link.parentKind, id: parent), "\(kind)")
        }
        #expect(SyncSingletonDecks.generators.contains(VerbPrepositionService.deckGenerator))
        #expect(SyncSingletonDecks.wortschatzTopic == DeckStore.wortschatzTopic)
    }
}

private extension StudyDay {
    /// Test-only: set a counter by its payload name.
    func setValue(forKey field: String, _ value: Int) {
        switch field {
        case "cardsReviewed": cardsReviewed = value
        case "grammarExercises": grammarExercises = value
        case "conversations": conversations = value
        case "storySeconds": storySeconds = value
        case "storyQuestions": storyQuestions = value
        case "cardSeconds": cardSeconds = value
        case "grammarSeconds": grammarSeconds = value
        case "conversationSeconds": conversationSeconds = value
        case "storyQuizSeconds": storyQuizSeconds = value
        case "newWordsIntroduced": newWordsIntroduced = value
        case "newWordsBonus": newWordsBonus = value
        case "gameSeconds": gameSeconds = value
        case "gameWordsSolved": gameWordsSolved = value
        case "wordsDrawn": wordsDrawn = value
        case "drawingSeconds": drawingSeconds = value
        case "wordsWritten": wordsWritten = value
        case "writingSeconds": writingSeconds = value
        case "sheetWordsWritten": sheetWordsWritten = value
        case "hoerenItems": hoerenItems = value
        case "hoerenSeconds": hoerenSeconds = value
        default: Issue.record("unknown StudyDay counter \(field)")
        }
    }
}
