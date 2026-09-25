#if DEBUG
import Foundation
import SwiftData

/// `-sync.debugVerify 1`: two real stores (temporary SQLite files, the app's full schema) sync
/// through `FakeSyncServer` with the same tracker, applier and coordinator the app uses. A simulator
/// can't hold two iCloud devices, so this is how the merge rules are checked end to end on
/// SwiftData.
///
/// It seeds data first and refuses to pass on an empty seed (the deck-sharing verifier once
/// passed vacuously on a 0-card deck).
@MainActor
enum SyncDebugVerify {
    static func run() async -> String {
        var lines: [String] = []
        var failures = 0
        func check(_ ok: Bool, _ message: String) {
            lines.append((ok ? "PASS  " : "FAIL  ") + message)
            if !ok { failures += 1 }
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sync-verify-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        guard let phoneStore = try? makeContainer(at: root.appendingPathComponent("phone")),
              let padStore = try? makeContainer(at: root.appendingPathComponent("pad"))
        else { return "[sync.verify] FAIL could not create stores" }
        let a = phoneStore.mainContext, b = padStore.mainContext
        let server = FakeSyncServer()

        // Pre-sync history on both devices: the same day studied on each, a deck on one, a phrase
        // on the other.
        StudyLogService.record(.cards(10), seconds: 300, in: a)
        StudyLogService.record(.cards(7), seconds: 120, in: b)
        let deck = SavedDeck(topic: "Reise", wordCount: 3, includeExamples: false)
        a.insert(deck)
        for (i, word) in ["der Zug", "die Karte", "das Gleis"].enumerated() {
            let card = SavedCard(germanWord: word, englishTranslation: "—", sortOrder: i)
            a.insert(card)
            card.deck = deck
        }
        try? a.save()
        let zug = deck.cards.first { $0.germanWord == "der Zug" }!
        SpacedRepetitionService.apply(rating: .good, to: zug)
        let result = QuizResult(totalCards: 3, correctCount: 2)
        a.insert(result)
        result.deck = deck
        b.insert(LearnedPhrase(german: "Sonst noch etwas?", english: "Anything else?"))
        try? a.save()
        try? b.save()

        let seeded = today(a)?.cardsReviewed == 10 && deck.cards.count == 3 && zug.totalReviews == 1
        check(seeded, "seed: phone has 10 cards today, a 3-card deck, one reviewed card")
        guard seeded else { return report(lines, failures) }

        let phone = SyncCoordinator(context: a, identity: SyncIdentity(replica: "phone", store: "A"),
                                    transport: FakeSyncTransport(server: server), includeDocuments: false)
        let pad = SyncCoordinator(context: b, identity: SyncIdentity(replica: "pad", store: "B"),
                                  transport: FakeSyncTransport(server: server), includeDocuments: false)
        phone.start()
        pad.start()
        await rounds(phone, pad)

        // 1. First sync: independent pre-sync histories add up; content crosses over.
        check(today(a)?.cardsReviewed == 17 && today(b)?.cardsReviewed == 17,
              "first sync: both devices show 10 + 7 = 17 cards today (\(today(a)?.cardsReviewed ?? -1), \(today(b)?.cardsReviewed ?? -1))")
        check(today(a)?.cardSeconds == 420 && today(b)?.cardSeconds == 420, "first sync: card time 300 + 120 s")
        check(dayRows(a) == 1 && dayRows(b) == 1, "first sync: one StudyDay row for today on each device")
        let padDeck = fetchDeck("Reise", b)
        check(padDeck?.cards.count == 3, "first sync: the iPad has the deck with its 3 cards")
        check(card("der Zug", b)?.totalReviews == 1 && card("der Zug", b)?.repetitions == 1,
              "first sync: the reviewed card's progress arrived")
        check(padDeck?.quizResults.count == 1, "first sync: the quiz result arrived")
        check(count(LearnedPhrase.self, a) == 1, "first sync: the phrase reached the phone")

        // 2. Both devices study offline, the same card on each: counts add, the later review
        //    sets the schedule.
        StudyLogService.record(.cards(5), seconds: 60, in: a)
        SpacedRepetitionService.apply(rating: .good, to: card("der Zug", a)!)
        try? a.save()
        StudyLogService.record(.cards(3), seconds: 30, in: b)
        SpacedRepetitionService.apply(rating: .again, to: card("der Zug", b)!)
        try? b.save()
        await rounds(phone, pad)
        check(today(a)?.cardsReviewed == 25 && today(b)?.cardsReviewed == 25,
              "concurrent study: 17 + 5 + 3 = 25 on both (\(today(a)?.cardsReviewed ?? -1), \(today(b)?.cardsReviewed ?? -1))")
        let za = card("der Zug", a), zb = card("der Zug", b)
        check(za?.totalReviews == 3 && zb?.totalReviews == 3, "concurrent review: both reviews counted (3 total)")
        check(za?.lapses == 1 && za?.repetitions == 0 && zb?.repetitions == 0,
              "concurrent review: the later review (Again) set the schedule on both")

        // 3. Delete iCloud Data, then both devices re-upload everything: nothing doubles.
        server.wipe()
        phone.forgetServer()
        pad.forgetServer()
        await rounds(phone, pad)
        check(today(a)?.cardsReviewed == 25 && today(b)?.cardsReviewed == 25,
              "zone reset + re-upload: still 25, not doubled (\(today(a)?.cardsReviewed ?? -1), \(today(b)?.cardsReviewed ?? -1))")
        check(card("der Zug", a)?.totalReviews == 3 && card("der Zug", b)?.totalReviews == 3,
              "zone reset + re-upload: card still has 3 reviews")
        check(server.records.count >= 7, "zone reset: the server holds everything again (\(server.records.count) records)")

        // 4. Delete on one device reaches the other, cards included.
        if let d = fetchDeck("Reise", a) { a.delete(d) }
        try? a.save()
        await rounds(phone, pad)
        check(fetchDeck("Reise", b) == nil, "delete: the deck is gone from the iPad")
        check(card("der Zug", b) == nil, "delete: its cards went with it")
        // 5. Both devices build the Wortschatz box offline (2,825 cards each) and review a word:
        //    canonical ids make it one deck, and only reviewed cards travel.
        let words = GoetheVocabService.orderedWords.filter { $0.translation?.isEmpty == false }
        if words.count >= 2,
           let boxA = DeckStore(modelContext: a).fetchOrCreateWortschatzDeck(),
           let boxB = DeckStore(modelContext: b).fetchOrCreateWortschatzDeck() {
            check(boxA.id == boxB.id, "Wortschatz: both devices derived the same deck id")
            let w1 = words[0].word, w2 = words[1].word
            SpacedRepetitionService.apply(rating: .good, to: boxA.cards.first { $0.germanWord == w1 }!)
            SpacedRepetitionService.apply(rating: .good, to: boxB.cards.first { $0.germanWord == w2 }!)
            try? a.save()
            try? b.save()
            await rounds(phone, pad)
            check(goetheDecks(a) == 1 && goetheDecks(b) == 1,
                  "Wortschatz: one box per device after sync (\(goetheDecks(a)), \(goetheDecks(b)))")
            let cardA2 = card(w2, a), cardB1 = card(w1, b)
            check(cardA2?.repetitions == 1 && cardB1?.repetitions == 1,
                  "Wortschatz: each device's review reached the other")
            let syncedCards = server.records.keys.filter { $0.hasPrefix("SavedCard:") }.count
            check(syncedCards == 2, "Wortschatz: only the 2 reviewed cards went to iCloud (\(syncedCards))")
        } else {
            check(false, "Wortschatz: couldn't build the box (word list empty?)")
        }

        // 6. Content: a story with lookups from both devices, a chat continued on the other
        //    device (time adds up), coaching memory from both, a stat seen on both, class notes.
        let story = StudyStory(topic: "Ein Tag in Berlin", level: .a2, genre: .alltag)
        story.title = "Sync-Geschichte"
        story.storyText = "Der Zug fährt ab."
        story.generationComplete = true
        a.insert(story)
        story.recordLookup(german: "Bahnhof", english: "station")
        a.insert(StoryReadingSession(storyID: story.id, storyTitle: story.title, levelRaw: "A2",
                                     seconds: 120, wasListening: false, lookups: 1, wordsSaved: 0))
        let chat = ChatConversation(config: ConversationConfig(model: .hero))
        chat.durationSeconds = 100
        a.insert(chat)
        for (i, text) in ["Hallo!", "Hallo, wie geht's?"].enumerated() {
            let message = ChatMessage(role: i == 0 ? .user : .assistant, text: text, sortOrder: i)
            a.insert(message)
            message.conversation = chat
        }
        LearnerMemoryService.noteVocabEncounters([(german: "Hund", english: "dog")], in: a)
        LearnerMemoryService.noteVocabEncounters([(german: "Katze", english: "cat")], in: b)
        let statA = ArticleWordStat(key: "tisch", noun: "Tisch", articleRaw: "der", english: "table")
        statA.timesSeen = 3
        a.insert(statA)
        let statB = ArticleWordStat(key: "tisch", noun: "Tisch", articleRaw: "der", english: "table")
        statB.timesSeen = 2
        b.insert(statB)
        let course = ClassCourse(name: "VHS B1")
        a.insert(course)
        let entry = ClassEntryStore.todayEntry(in: course, context: a)
        let material = ClassMaterial(title: "Arbeitsblatt", text: "Die Präpositionen mit Dativ")
        a.insert(material)
        material.entry = entry
        try? a.save()
        try? b.save()
        await rounds(phone, pad)

        let padStory = fetchOne(StudyStory.self, b)
        check(padStory?.title == "Sync-Geschichte" && count(StoryReadingSession.self, b) == 1,
              "content: the story and its reading session reached the iPad")
        padStory?.recordLookup(german: "Zug", english: "train")
        if let padChat = fetchOne(ChatConversation.self, b) { padChat.durationSeconds += 50 }
        chat.durationSeconds += 30
        try? a.save()
        try? b.save()
        await rounds(phone, pad)
        let lookupsA = Set(fetchOne(StudyStory.self, a)?.lookups.map(\.german) ?? [])
        check(lookupsA == ["Bahnhof", "Zug"], "content: lookups from both devices kept (\(lookupsA.sorted()))")
        let chatA = fetchOne(ChatConversation.self, a), chatB = fetchOne(ChatConversation.self, b)
        check(chatA?.durationSeconds == 180 && chatB?.durationSeconds == 180,
              "content: chat time 100 + 50 + 30 = 180 on both (\(chatA?.durationSeconds ?? -1), \(chatB?.durationSeconds ?? -1))")
        check(chatB?.messages.count == 2, "content: the chat's 2 messages arrived")
        let vocabA = Set(fetchOne(LearnerProfile.self, a)?.vocab.map { $0.german.lowercased() } ?? [])
        let vocabB = Set(fetchOne(LearnerProfile.self, b)?.vocab.map { $0.german.lowercased() } ?? [])
        check(vocabA.isSuperset(of: ["hund", "katze"]) && vocabA == vocabB,
              "content: coaching memory holds words from both devices (\(vocabA.sorted()))")
        check(count(LearnerProfile.self, a) == 1 && count(LearnerProfile.self, b) == 1,
              "content: one learner profile per device")
        let tischA = fetchOne(ArticleWordStat.self, a), tischB = fetchOne(ArticleWordStat.self, b)
        check(count(ArticleWordStat.self, a) == 1 && count(ArticleWordStat.self, b) == 1,
              "content: one row for der Tisch per device")
        check(tischA?.timesSeen == 5 && tischB?.timesSeen == 5,
              "content: der Tisch seen 3 + 2 = 5 times (\(tischA?.timesSeen ?? -1), \(tischB?.timesSeen ?? -1))")
        let padCourse = fetchOne(ClassCourse.self, b)
        check(padCourse?.name == "VHS B1" && padCourse?.entries.first?.materials.first?.title == "Arbeitsblatt",
              "content: course → entry → handout arrived in order")

        check(phone.pendingCount == 0 && pad.pendingCount == 0,
              "settled: nothing pending (\(phone.pendingCount), \(pad.pendingCount))")

        phone.stop()
        pad.stop()
        return report(lines, failures)
    }

    // MARK: Helpers

    private static func rounds(_ x: SyncCoordinator, _ y: SyncCoordinator) async {
        for _ in 0..<3 {
            await x.syncNow()
            await y.syncNow()
        }
    }

    private static func makeContainer(at dir: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let schema = Schema(AppSchema.models)
        let config = ModelConfiguration(schema: schema, url: dir.appendingPathComponent("verify.store"),
                                        cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func today(_ context: ModelContext) -> StudyDay? {
        let start = Calendar.current.startOfDay(for: .now)
        return (try? context.fetch(FetchDescriptor<StudyDay>(predicate: #Predicate { $0.dayStart == start })))?.first
    }

    private static func dayRows(_ context: ModelContext) -> Int {
        let start = Calendar.current.startOfDay(for: .now)
        return (try? context.fetchCount(FetchDescriptor<StudyDay>(predicate: #Predicate { $0.dayStart == start }))) ?? -1
    }

    private static func fetchDeck(_ topic: String, _ context: ModelContext) -> SavedDeck? {
        (try? context.fetch(FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.topic == topic })))?.first
    }

    private static func card(_ word: String, _ context: ModelContext) -> SavedCard? {
        (try? context.fetch(FetchDescriptor<SavedCard>(predicate: #Predicate { $0.germanWord == word })))?.first
    }

    private static func fetchOne<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> T? {
        (try? context.fetch(FetchDescriptor<T>()))?.first
    }

    private static func goetheDecks(_ context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.generatorRaw == "goethe-srs" }))) ?? -1
    }

    private static func count<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    private static func report(_ lines: [String], _ failures: Int) -> String {
        let passed = lines.count - failures
        return (["[sync.verify] \(failures == 0 ? "ALL PASS" : "FAILURES") — \(passed)/\(lines.count) checks"]
                + lines.map { "[sync.verify] " + $0 }).joined(separator: "\n")
    }
}
#endif
