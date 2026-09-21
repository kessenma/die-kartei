//
//  WortschatzDebugSeeder.swift
//  german-ai-flashcards
//
//  Developer-only ways to put the Wortschatz box into a state worth looking at on a simulator
//  that can't tap: a spread of new / due / known / lapsed cards (reversible), the three old
//  per-level SRS decks so the one-time merge has something to merge, and a merge re-run.
//
//  Same two rules as `ScreenshotDataSeeder`: nothing is faked past the front door (the seeded
//  rows are real `SavedCard` SRS state), and every seed is reversible from a backup that lives
//  outside SwiftData.
//

import Foundation
import SwiftData

enum WortschatzDebugSeeder {

    /// A card's SRS fields, flattened for the backup file.
    nonisolated struct CardState: Codable {
        var word: String
        var easeFactor: Double
        var interval: Int
        var repetitions: Int
        var nextReviewDate: Date?
        var totalReviews: Int
        var lapses: Int
        var leitnerBox: Int
        var lastReviewedAt: Date?
        var lastReviewWasCorrect: Bool?
        var firstReviewedAt: Date?
    }

    nonisolated struct Backup: Codable {
        var createdAt: Date
        var cards: [CardState]
        var newWordsIntroduced: Int
        var newWordsBonus: Int
    }

    private static var fileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Developer")
            .appendingPathComponent("wortschatz-seed-backup.json")
    }

    static var hasBackup: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    // MARK: - Seed a spread of states

    /// Backs up the box (once; a second seed keeps the first backup so restore still means
    /// "as it was before I started"), then assigns roughly 60% untouched, 15% known, 12% due,
    /// 5% lapsed, 8% scheduled — deterministic, so a re-seed reproduces the same picture.
    @discardableResult
    static func seed(in context: ModelContext) -> String {
        let store = DeckStore(modelContext: context)
        guard let deck = store.fetchOrCreateWortschatzDeck() else { return "no Wortschatz deck" }
        if !hasBackup {
            saveBackup(deck: deck, in: context)
        }

        var generator = SeededGenerator(seed: 7)
        let now = Date()
        var counts = (new: 0, known: 0, due: 0, lapsed: 0, scheduled: 0)
        for card in deck.cards.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            reset(card)
            let roll = Int(generator.next() % 100)
            switch roll {
            case ..<60:
                counts.new += 1
            case ..<75:
                card.interval = 21 + Int(generator.next() % 100)
                card.repetitions = 3 + Int(generator.next() % 5)
                card.totalReviews = card.repetitions + 1
                card.leitnerBox = 5
                card.nextReviewDate = now.addingTimeInterval(Double(1 + generator.next() % 30) * 86_400)
                counts.known += 1
            case ..<87:
                card.interval = 1 + Int(generator.next() % 7)
                card.repetitions = 1 + Int(generator.next() % 2)
                card.totalReviews = card.repetitions
                card.leitnerBox = 1 + Int(generator.next() % 4)
                card.nextReviewDate = now.addingTimeInterval(-Double(1 + generator.next() % 5) * 86_400)
                counts.due += 1
            case ..<92:
                card.interval = 1
                card.repetitions = 0
                card.lapses = 1 + Int(generator.next() % 3)
                card.totalReviews = card.lapses + 1
                card.leitnerBox = 1
                card.easeFactor = 2.1
                card.nextReviewDate = now.addingTimeInterval(-86_400)
                counts.lapsed += 1
            default:
                card.interval = 3 + Int(generator.next() % 12)
                card.repetitions = 1 + Int(generator.next() % 2)
                card.totalReviews = card.repetitions
                card.leitnerBox = 2 + Int(generator.next() % 3)
                card.nextReviewDate = now.addingTimeInterval(Double(1 + generator.next() % 10) * 86_400)
                counts.scheduled += 1
            }
            // A slice of the scheduled and lapsed cards were "rated today", so the hub's Today
            // section has something to list.
            if roll >= 87, generator.next() % 3 == 0 {
                let correct = roll >= 92
                card.noteReview(correct: correct, at: now.addingTimeInterval(-Double(generator.next() % 3_600)))
                if generator.next() % 2 == 0 { card.firstReviewedAt = card.lastReviewedAt }
            }
        }
        try? context.save()
        return "seeded \(deck.cards.count) cards: \(counts.new) new · \(counts.known) known · \(counts.due) due · \(counts.lapsed) lapsed · \(counts.scheduled) scheduled"
    }

    /// Put every card back the way the backup found it, and delete the backup.
    @discardableResult
    static func restore(in context: ModelContext) -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let backup = try? decoder.decode(Backup.self, from: data),
              let deck = DeckStore(modelContext: context).fetchWortschatzDeck()
        else { return false }
        let states = Dictionary(backup.cards.map { ($0.word, $0) }, uniquingKeysWith: { first, _ in first })
        for card in deck.cards {
            reset(card)
            guard let state = states[card.germanWord] else { continue }
            card.easeFactor = state.easeFactor
            card.interval = state.interval
            card.repetitions = state.repetitions
            card.nextReviewDate = state.nextReviewDate
            card.totalReviews = state.totalReviews
            card.lapses = state.lapses
            card.leitnerBox = state.leitnerBox
            card.lastReviewedAt = state.lastReviewedAt
            card.lastReviewWasCorrect = state.lastReviewWasCorrect
            card.firstReviewedAt = state.firstReviewedAt
        }
        let today = Calendar.current.startOfDay(for: Date())
        if let day = try? context.fetch(FetchDescriptor<StudyDay>(predicate: #Predicate { $0.dayStart == today })).first {
            day.newWordsIntroduced = backup.newWordsIntroduced
            day.newWordsBonus = backup.newWordsBonus
        }
        try? context.save()
        try? FileManager.default.removeItem(at: fileURL)
        return true
    }

    // MARK: - The old per-level decks, for exercising the merge

    /// Creates "A1 Vocabulary" / "A2 Vocabulary" / "B1 Vocabulary" SRS decks the way the app did
    /// before the box existed — duplicates included — with divergent progress on the shared
    /// words, then clears the merge flag so the next launch merges them. Refuses to run once a
    /// merged deck exists, because the merge only reads decks whose topic differs from it.
    @discardableResult
    static func createLegacyDecks(in context: ModelContext) -> String {
        guard DeckStore(modelContext: context).fetchWortschatzDeck() == nil else {
            return "a Wortschatz deck already exists; restore or delete it first"
        }
        var generator = SeededGenerator(seed: 11)
        let now = Date()
        var made = 0
        for level in GoetheLevel.allCases {
            let topic = "\(level.rawValue) Vocabulary"
            let entries = GoetheVocabService.entries(for: level)
            let deck = SavedDeck(topic: topic, wordCount: entries.count, includeExamples: true, includeGender: true)
            deck.generatorRaw = "goethe-srs"
            deck.cards = entries.enumerated().compactMap { index, entry in
                guard let translation = entry.translation, !translation.isEmpty else { return nil }
                let card = SavedCard(
                    germanWord: entry.word, englishTranslation: translation, wordType: entry.wordType,
                    article: entry.article, exampleSentence: entry.example, sortOrder: index
                )
                // Every third word carries progress, with a different amount per level, so the
                // merge has copies to choose between.
                if index % 3 == 0 {
                    let bump = level == .a1 ? 0 : level == .a2 ? 8 : 16
                    card.interval = 1 + bump + Int(generator.next() % 6)
                    card.repetitions = 1 + Int(generator.next() % 3)
                    card.totalReviews = card.repetitions + Int(generator.next() % 2)
                    card.lapses = Int(generator.next() % 2)
                    card.leitnerBox = 1 + Int(generator.next() % 4)
                    card.nextReviewDate = now.addingTimeInterval(Double(Int(generator.next() % 10) - 5) * 86_400)
                }
                return card
            }
            context.insert(deck)
            made += deck.cards.count
        }
        try? context.save()
        UserDefaults.standard.removeObject(forKey: WortschatzMergeService.flagKey)
        return "created 3 legacy decks with \(made) cards; merge flag cleared"
    }

    /// Clear the flag and run the merge now.
    @discardableResult
    static func rerunMerge(in context: ModelContext) -> String {
        UserDefaults.standard.removeObject(forKey: WortschatzMergeService.flagKey)
        let summary = WortschatzMergeService.run(in: context)
        UserDefaults.standard.set(true, forKey: WortschatzMergeService.flagKey)
        return summary
    }

    // MARK: - Helpers

    private static func reset(_ card: SavedCard) {
        card.easeFactor = 2.5
        card.interval = 0
        card.repetitions = 0
        card.nextReviewDate = nil
        card.totalReviews = 0
        card.lapses = 0
        card.leitnerBox = 0
        card.lastReviewedAt = nil
        card.lastReviewWasCorrect = nil
        card.firstReviewedAt = nil
    }

    private static func saveBackup(deck: SavedDeck, in context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let day = try? context.fetch(FetchDescriptor<StudyDay>(predicate: #Predicate { $0.dayStart == today })).first
        let backup = Backup(
            createdAt: Date(),
            cards: deck.cards.map {
                CardState(word: $0.germanWord, easeFactor: $0.easeFactor, interval: $0.interval,
                          repetitions: $0.repetitions, nextReviewDate: $0.nextReviewDate,
                          totalReviews: $0.totalReviews, lapses: $0.lapses, leitnerBox: $0.leitnerBox,
                          lastReviewedAt: $0.lastReviewedAt, lastReviewWasCorrect: $0.lastReviewWasCorrect,
                          firstReviewedAt: $0.firstReviewedAt)
            },
            newWordsIntroduced: day?.newWordsIntroduced ?? 0,
            newWordsBonus: day?.newWordsBonus ?? 0
        )
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(backup) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
