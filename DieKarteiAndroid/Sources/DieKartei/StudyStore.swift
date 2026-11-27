import Foundation
import Observation
import SkipFuse
@testable import DieKarteiCore
@testable import KarteiStore

/// The card the shared scheduler works on (`SRSScheduling`, the same SM-2 code as iOS).
@MainActor
final class StudyCard: SRSCardState {
    var record: CardRecord

    init(_ record: CardRecord) { self.record = record }

    var sortOrder: Int { record.sortOrder }
    var easeFactor: Double { get { record.easeFactor } set { record.easeFactor = newValue } }
    var interval: Int { get { record.interval } set { record.interval = newValue } }
    var repetitions: Int { get { record.repetitions } set { record.repetitions = newValue } }
    var nextReviewDate: Date? { get { record.nextReviewDate } set { record.nextReviewDate = newValue } }
    var totalReviews: Int { get { record.totalReviews } set { record.totalReviews = newValue } }
    var lapses: Int { get { record.lapses } set { record.lapses = newValue } }
    var leitnerBox: Int { get { record.leitnerBox } set { record.leitnerBox = newValue } }

    func noteReview(correct: Bool, at now: Date) {
        record.noteReview(correct: correct, at: now)
    }
}

/// The Wortschatz deck on Android, kept as iOS keeps it: one deck for A1–B1
/// (`SyncSingletonDecks.wortschatzDeckID`), one `CardRecord` per exact Goethe word with the iOS
/// card id, created the first time the word is rated. The level is only a filter over the word
/// lists. Records live in the database (`AppDatabase.records`), written through the shared sync
/// logic, so a sync transport can carry them to iOS as they are.
@MainActor
@Observable
final class StudyStore {
    static let shared = StudyStore()

    /// Where Settings ▸ Flashcards keeps the number of new words per session.
    static let newPerSessionKey = "flashcards.newPerSession"
    static let newPerSessionDefault = 10

    /// New words a session brings in, on top of everything due.
    static var newPerSession: Int {
        let stored = UserDefaults.standard.integer(forKey: newPerSessionKey)
        return stored > 0 ? stored : newPerSessionDefault
    }

    /// Reviewed cards by exact German word.
    private(set) var cards: [String: CardRecord] = [:]
    private let records: RecordStore?

    init(records: RecordStore? = AppDatabase.records) {
        self.records = records
        guard let records else {
            logger.error("StudyStore: no database, progress won't be saved")
            return
        }
        do {
            // Progress from before the database (UserDefaults `studyProgress.v1`), once.
            let outcome = try WortschatzMigration.run(
                blob: UserDefaults.standard.data(forKey: WortschatzMigration.defaultsKey),
                into: records, deck: WortschatzRecords.deck(), card: WortschatzRecords.card(for:))
            if !outcome.alreadyDone {
                logger.info("StudyStore: moved \(outcome.cards) cards to the database, left \(outcome.dropped.count) words without a card")
            }
        } catch {
            logger.error("StudyStore: migration failed: \(error)")
        }
        for card in records.records(CardRecord.self, parent: SyncSingletonDecks.wortschatzDeckID) {
            cards[card.germanWord] = card
        }
    }

    /// The level's words that have a card on iOS (those with a translation), each once.
    private func words(for level: GoetheLevel) -> [A1Entry] {
        var seen: Set<String> = []
        return GoetheVocabService.entries(for: level).filter {
            WortschatzRecords.sortOrder[$0.word] != nil && $0.translation?.isEmpty == false
                && seen.insert($0.word).inserted
        }
    }

    /// New words a session may bring in now: the per-session setting, within what's left of
    /// today's budget (iOS's daily `wortschatz.newPerDay`).
    static var newForNextSession: Int { min(newPerSession, StudyLog.shared.newWordsLeftToday) }

    /// Due reviews first (oldest due first), then up to `newForNextSession` unseen words in list order.
    func session(for level: GoetheLevel, now: Date = Date()) -> [A1Entry] {
        var due: [(A1Entry, Date)] = []
        var fresh: [A1Entry] = []
        let newLimit = Self.newForNextSession
        for entry in words(for: level) {
            if let card = cards[entry.word] {
                if let next = card.nextReviewDate, next <= now { due.append((entry, next)) }
            } else if fresh.count < newLimit {
                fresh.append(entry)
            }
        }
        return due.sorted { $0.1 < $1.1 }.map(\.0) + fresh
    }

    /// The word's card: its record once reviewed, else a fresh one with the iOS id and content.
    private func card(for entry: A1Entry) -> CardRecord? {
        cards[entry.word] ?? WortschatzRecords.card(for: entry.word)
    }

    /// The next intervals each rating would give, for the button captions ("1d", "6d", …).
    func previews(for entry: A1Entry, level: GoetheLevel, index: Int) -> [AnkiRating: String] {
        guard let record = card(for: entry) else { return [:] }
        var out: [AnkiRating: String] = [:]
        for preview in SRSScheduling.previewIntervals(for: StudyCard(record)) { out[preview.rating] = preview.label }
        return out
    }

    func rate(_ entry: A1Entry, level: GoetheLevel, index: Int, rating: AnkiRating) {
        guard let record = card(for: entry) else { return }
        let firstRating = cards[entry.word] == nil
        let card = StudyCard(record)
        SRSScheduling.apply(rating: rating, to: card)
        cards[entry.word] = card.record
        do {
            try records?.put(card.record)
        } catch {
            logger.error("StudyStore: could not save \(entry.word): \(error)")
        }
        // As iOS: the review counts toward today, a first rating against the new-word budget.
        StudyLog.shared.answered(.cards(1))
        if firstRating { StudyLog.shared.recordNewWords(1) }
    }

    func stats(for level: GoetheLevel, now: Date = Date()) -> (seen: Int, due: Int, total: Int) {
        let words = words(for: level)
        let mine = words.compactMap { cards[$0.word] }
        let due = mine.filter { ($0.nextReviewDate ?? now) <= now }.count
        return (mine.count, due, words.count)
    }

    /// Forget the level's words: their records go (an unreviewed Wortschatz word has none, on
    /// iOS as here). A word on two levels' lists is one card, so it's forgotten for both.
    func reset(level: GoetheLevel) {
        guard let records else { return }
        let gone = words(for: level).compactMap { cards[$0.word] }
        do {
            try records.transaction {
                for card in gone { try records.delete(card) }
            }
        } catch {
            logger.error("StudyStore: reset failed: \(error)")
            return
        }
        for card in gone { cards[card.germanWord] = nil }
    }
}
