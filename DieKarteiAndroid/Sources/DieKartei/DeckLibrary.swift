import Foundation
import Observation
import SkipFuse
import GermanVoice
@testable import DieKarteiCore
@testable import KarteiStore

/// The learner's own decks on Android: decks that arrive as `.kartei` files (from the iPhone or
/// another phone), kept as `DeckRecord`/`CardRecord` the way iOS keeps `SavedDeck`/`SavedCard`, so
/// a sync can carry them as they are. What a file becomes, what a session scores and what a result
/// row holds are the shared rules (`DeckTransferRecords`, `AnkiRound`, `QuizResultRecord`).
@MainActor
@Observable
final class DeckLibrary {
    static let shared = DeckLibrary()

    /// The Library's decks, newest first (iOS: `isBrowsableContent`, by `createdAt`).
    private(set) var decks: [DeckRecord] = []
    /// A file waiting for the learner's choice (the import sheet).
    var pending: PendingImport?
    /// Why the last file couldn't be taken in.
    var problem: String?
    private let records: RecordStore?

    struct PendingImport: Identifiable {
        let id = UUID()
        let envelope: DeckTransferEnvelope
        /// The deck already here with the file's id.
        let existing: DeckRecord?
    }

    init(records: RecordStore? = AppDatabase.records) {
        self.records = records
        reload()
    }

    func reload() {
        decks = (records?.records(DeckRecord.self) ?? [])
            .filter { DeckKind(generatorRaw: $0.generatorRaw).isBrowsableContent }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func cards(of deck: DeckRecord) -> [CardRecord] {
        (records?.records(CardRecord.self, parent: deck.id) ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    func results(of deck: DeckRecord) -> [QuizResultRecord] {
        (records?.records(QuizResultRecord.self, parent: deck.id) ?? []).sorted { $0.date > $1.date }
    }

    func dueCount(of deck: DeckRecord, now: Date = Date()) -> Int {
        cards(of: deck).filter { AnkiSessionRules.isDue(nextReviewDate: $0.nextReviewDate, now: now) }.count
    }

    // MARK: Files

    /// A file handed to the app (another app's "open with", or the picker): read and checked,
    /// then waiting in `pending` for the learner.
    func open(_ url: URL) {
        guard let data = DeckFiles.shared.read(url.absoluteString) else {
            problem = DeckTransferFailure.unreadable.errorDescription
            return
        }
        open(data)
    }

    func open(_ data: Data) {
        do {
            let envelope = try DeckTransferFormat.decode(data)
            let existing = UUID(uuidString: envelope.deck.id).flatMap { records?.record(DeckRecord.self, id: $0) }
            problem = nil
            pending = PendingImport(envelope: envelope, existing: existing)
        } catch {
            logger.warning("DeckLibrary: not taken in (\(data.count) bytes): \(error) \(DeckTransferFormat.lastDecodingError ?? "")")
            problem = (error as? DeckTransferFailure)?.errorDescription ?? DeckTransferFailure.notADeck.errorDescription
        }
    }

    /// Take the pending file in (iOS `DeckImporter.insert`): replacing drops the copy here first.
    @discardableResult
    func importPending(_ mode: DeckTransferRecords.Mode) -> DeckRecord? {
        guard let pending, let records else { return nil }
        self.pending = nil
        let made = DeckTransferRecords.records(from: pending.envelope, mode: mode)
        do {
            try records.transaction {
                if mode == .replace, let existing = pending.existing {
                    try records.delete(existing)
                }
                try records.put(made.deck)
                try records.put(made.cards)
            }
        } catch {
            logger.error("DeckLibrary: import failed: \(error)")
            problem = "The deck couldn't be saved."
            return nil
        }
        logger.info("DeckLibrary: imported '\(made.deck.topic)' with \(made.cards.count) cards (\(mode == .replace ? "replace" : "keep both"))")
        reload()
        return made.deck
    }

    /// Send a deck as a `.kartei` file (iOS: the Library's Share).
    func share(_ deck: DeckRecord) {
        let app = DeckTransferEnvelope.App(name: "Die Kartei", version: nil, build: nil)
        guard let envelope = DeckTransferRecords.envelope(deck: deck, cards: cards(of: deck), app: app),
              let data = try? DeckTransferFormat.encode(envelope) else { return }
        if !DeckFiles.shared.share(data, fileName: DeckTransferFormat.fileName(topic: deck.topic), title: deck.topic) {
            problem = "The deck couldn't be shared."
        }
    }

    /// A deck and everything on it (its cards and results go with it).
    func delete(_ deck: DeckRecord) {
        do {
            try records?.delete(deck)
        } catch {
            logger.error("DeckLibrary: delete failed: \(error)")
        }
        reload()
    }

    // MARK: Phrases

    /// Phrases into one of the learner's decks (iOS `PhraseToDeckSheet`); the summary line.
    func addPhrases(_ phrases: [PhraseCards.Phrase], to deck: DeckRecord) -> String {
        let existing = cards(of: deck)
        let made = PhraseCards.merge(phrases, intoDeckWith: existing.map(\.germanWord),
                                     lastOrder: existing.map(\.sortOrder).max())
        var deck = deck
        deck.wordCount = existing.count + made.count
        do {
            try records?.transaction {
                try records?.put(made.map { PhraseCards.record($0, deck: deck.id) })
                try records?.put(deck)
            }
        } catch {
            logger.error("DeckLibrary: phrases not added: \(error)")
        }
        reload()
        return PhraseCards.addedSummary(made.count, deck: deck.topic)
    }

    /// A new "Sätze" deck from phrases; the summary line.
    func newPhraseDeck(_ phrases: [PhraseCards.Phrase], name: String) -> String {
        let made = PhraseCards.newDeckRecords(phrases, name: name)
        do {
            try records?.transaction {
                try records?.put(made.deck)
                try records?.put(made.cards)
            }
        } catch {
            logger.error("DeckLibrary: phrase deck not saved: \(error)")
        }
        reload()
        return PhraseCards.createdSummary(made.cards.count, deck: made.deck.topic)
    }

    // MARK: Studying

    /// Schedule one card with the shared SM-2 code, as iOS's Anki mode does.
    func rate(_ card: CardRecord, _ rating: AnkiRating) -> CardRecord {
        let study = StudyCard(card)
        SRSScheduling.apply(rating: rating, to: study)
        save(study.record)
        return study.record
    }

    /// A Classic answer stamps the card's last-answer fields only (iOS `noteReview(correct:)`).
    func note(_ card: CardRecord, knewIt: Bool) {
        var card = card
        card.noteReview(correct: knewIt, at: Date())
        save(card)
    }

    /// A finished session's result row, on the deck it was studied on.
    func saveResult(_ result: QuizResultRecord) {
        do {
            try records?.put(result)
        } catch {
            logger.error("DeckLibrary: result not saved: \(error)")
        }
    }

    private func save(_ card: CardRecord) {
        do {
            try records?.put(card)
        } catch {
            logger.error("DeckLibrary: card not saved: \(error)")
        }
    }
}
