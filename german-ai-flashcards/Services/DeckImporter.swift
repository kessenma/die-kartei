//
//  DeckImporter.swift
//  german-ai-flashcards
//
//  The receiving half of `DeckTransfer`: turning a `.kartei` file handed over by AirDrop, Files,
//  Messages or Mail back into a deck in the Library.
//
//  Three things this has to get right, none of them obvious:
//
//  1. **The file is not ours to read yet.** A document opened from another app arrives as a
//     security-scoped URL; reading it without `startAccessingSecurityScopedResource()` fails with a
//     permissions error that looks exactly like a corrupt file. AirDrop is the exception — iOS
//     copies those into `Documents/Inbox/` first — which is why `read` also deletes the inbox copy
//     once the bytes are in memory, or every deck you ever receive stays on disk forever.
//  2. **Re-sending an updated deck must not silently fork it.** The file carries the deck's UUID,
//     so an arriving deck you already have is a *choice* (replace or keep both), not a duplicate.
//     Replacing reuses the id, so the next send from the other device still recognises it.
//  3. **Links to things that don't exist here are dropped.** `courseIDRaw` points at a
//     `ClassCourse` on the *sending* device. Carrying it over would file the deck under a course
//     this device has never heard of, where nothing would ever show it. Cleared on every import;
//     the learner can re-link it to a local course afterwards.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
enum DeckImporter {

    enum Failure: LocalizedError {
        case unreadable
        case notADeck
        case fromANewerVersion(Int)
        case wortschatz

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "This file could not be read."
            case .notADeck:
                "This isn't a Die Kartei deck."
            case .fromANewerVersion:
                "This deck was shared from a newer version of Die Kartei. Update the app and try again."
            case .wortschatz:
                "The Goethe word box can't be shared between devices — it's built from the lists already on each one."
            }
        }
    }

    enum Mode {
        /// Take the file's deck id: the deck already here is deleted first.
        case replace
        /// Fresh ids throughout, so both copies survive side by side.
        case keepBoth
    }

    // MARK: - Reading

    /// Decode a `.kartei` file. Consumes the AirDrop inbox copy on the way out.
    static func read(from url: URL) throws -> DeckTransferEnvelope {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(DeckTransferEnvelope.self, from: data),
              envelope.schema == DeckTransfer.schema else {
            throw Failure.notADeck
        }
        guard envelope.schemaVersion <= DeckTransfer.schemaVersion else {
            throw Failure.fromANewerVersion(envelope.schemaVersion)
        }
        guard envelope.deck.generator != "goethe-srs" else { throw Failure.wortschatz }

        discardInboxCopy(url)
        return envelope
    }

    /// AirDrop and Mail stage their handoff inside our own container; the URL is ours to delete
    /// and nobody else will. A file opened in place from iCloud Drive is left alone.
    private static func discardInboxCopy(_ url: URL) {
        let inbox = URL.documentsDirectory.appendingPathComponent("Inbox").standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(inbox) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Inspecting

    /// The deck already on this device carrying the file's id, if there is one.
    static func existingDeck(for envelope: DeckTransferEnvelope, in context: ModelContext) -> SavedDeck? {
        guard let id = UUID(uuidString: envelope.deck.id) else { return nil }
        let descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Inserting

    @discardableResult
    static func insert(
        _ envelope: DeckTransferEnvelope,
        mode: Mode,
        into context: ModelContext
    ) -> SavedDeck {
        let source = envelope.deck

        if mode == .replace, let existing = existingDeck(for: envelope, in: context) {
            // Cards cascade-delete, their PNGs don't — same cleanup the Library's delete does.
            if DeckIllustrationService.shared.illustratingDeckUUID == existing.id {
                DeckIllustrationService.shared.stop()
            }
            CardImageStore.deleteImages(for: existing.id)
            context.delete(existing)
        }

        let deck = SavedDeck(
            topic: source.topic,
            wordCount: source.wordCount,
            includeExamples: source.includeExamples,
            includeGender: source.includeGender,
            wordTypeFilter: WordTypeFilter(rawValue: source.wordTypeFilter) ?? .all,
            includeConjugations: source.includeConjugations,
            selectedTenses: source.selectedTenses,
            createdAt: source.createdAt
        )
        if mode == .replace, let id = UUID(uuidString: source.id) {
            deck.id = id
        }
        deck.generatorRaw = source.generator
        deck.generationTimeSeconds = source.generationTimeSeconds
        // See the header: the sending device's course is not this device's course.
        deck.courseIDRaw = nil

        deck.cards = source.cards
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { card(from: $0, keepingID: mode == .replace) }

        context.insert(deck)
        try? context.save()
        return deck
    }

    private static func card(
        from source: DeckTransferEnvelope.Card,
        keepingID: Bool
    ) -> SavedCard {
        let card = SavedCard(
            germanWord: source.germanWord,
            englishTranslation: source.englishTranslation,
            wordType: source.wordType,
            article: source.article,
            exampleSentence: source.exampleSentence,
            conjugations: source.conjugations?.map { $0.toConjugation() },
            sortOrder: source.sortOrder
        )
        if keepingID, let id = UUID(uuidString: source.id) {
            card.id = id
        }
        if let progress = source.progress {
            card.easeFactor = progress.easeFactor
            card.interval = progress.interval
            card.repetitions = progress.repetitions
            card.nextReviewDate = progress.nextReviewDate
            card.totalReviews = progress.totalReviews
            card.lapses = progress.lapses
            card.leitnerBox = progress.leitnerBox
            card.lastReviewedAt = progress.lastReviewedAt
            card.lastReviewWasCorrect = progress.lastReviewWasCorrect
            card.firstReviewedAt = progress.firstReviewedAt
        }
        return card
    }
}

#if DEBUG
extension DeckImporter {

    /// `-deckTransfer.debugVerify 1` — the whole round trip in one launch: export a real deck,
    /// write it to a file, read the file back the way an AirDrop would, insert it, and compare.
    ///
    /// This exists because the one thing that matters here cannot be tested any other way: two
    /// simulators cannot AirDrop to each other, and this one cannot be tapped. It also forces
    /// `UTType.karteiDeck` to resolve, which raises rather than returns nil when the Info.plist
    /// declaration and the identifier in `DeckTransfer` drift apart — a mismatch that would
    /// otherwise surface as "AirDrop offers every app except this one" on a device.
    ///
    /// Seed something to export first: `-screenshots.debugFill 1 -deckTransfer.debugVerify 1`.
    static func runDebugVerification(in context: ModelContext) -> String {
        var notes: [String] = ["uti=\(UTType.karteiDeck.identifier)"]

        // Pick the most-studied deck with the most cards, not merely the newest: the seeded store
        // has empty decks in it, and an empty deck round-trips perfectly while proving nothing.
        // Every check below is a comparison over `cards`, so a zero-card source is a vacuous pass.
        let descriptor = FetchDescriptor<SavedDeck>()
        let candidates = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.isBrowsableContent && !$0.cards.isEmpty }
        guard let source = candidates.max(by: { a, b in
            let studied = { (deck: SavedDeck) in deck.cards.filter { $0.totalReviews > 0 }.count }
            return (studied(a), a.cards.count) < (studied(b), b.cards.count)
        }) else {
            return "[deckTransfer] FAIL: no non-empty browsable deck to export — run with -screenshots.debugFill 1"
        }
        let studiedCards = source.cards.filter { $0.totalReviews > 0 }.count
        guard studiedCards > 0 else {
            return "[deckTransfer] FAIL: '\(source.topic)' has no reviewed cards, so progress can't be verified"
        }
        guard let document = DeckTransfer.document(for: source) else {
            return "[deckTransfer] FAIL: \(source.topic) refused export"
        }
        notes.append("\(studiedCards)/\(source.cards.count) cards carry reviews")
        notes.append("exported '\(source.topic)' \(source.cards.count) cards, \(document.data.count) bytes as \(document.fileName)")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(document.fileName)
        do {
            try document.data.write(to: url, options: .atomic)
        } catch {
            return "[deckTransfer] FAIL: could not write \(url.lastPathComponent): \(error)"
        }

        let envelope: DeckTransferEnvelope
        do {
            envelope = try read(from: url)
        } catch {
            return "[deckTransfer] FAIL: read back — \(error.localizedDescription)"
        }
        try? FileManager.default.removeItem(at: url)

        notes.append("matched existing deck: \(existingDeck(for: envelope, in: context) != nil)")
        notes.append("carries progress: \(envelope.includesProgress)")

        let copy = insert(envelope, mode: .keepBoth, into: context)
        notes.append(copy.cards.count == source.cards.count
            ? "round trip: \(copy.cards.count) cards"
            : "FAIL: \(source.cards.count) cards out, \(copy.cards.count) back")
        notes.append(copy.id != source.id ? "keepBoth forked the id" : "FAIL: keepBoth reused the id")

        // The scheduling is the point of the whole feature — compare it word by word.
        let before = Dictionary(uniqueKeysWithValues: source.cards.map { ($0.germanWord, $0) })
        let drifted: [String] = copy.cards.compactMap { after in
            guard let original = before[after.germanWord] else { return "\(after.germanWord): missing" }
            var fields: [String] = []
            if original.leitnerBox != after.leitnerBox { fields.append("leitnerBox \(original.leitnerBox)→\(after.leitnerBox)") }
            if original.repetitions != after.repetitions { fields.append("repetitions \(original.repetitions)→\(after.repetitions)") }
            if original.interval != after.interval { fields.append("interval \(original.interval)→\(after.interval)") }
            if original.totalReviews != after.totalReviews { fields.append("totalReviews \(original.totalReviews)→\(after.totalReviews)") }
            if original.lapses != after.lapses { fields.append("lapses \(original.lapses)→\(after.lapses)") }
            if original.easeFactor != after.easeFactor { fields.append("ease \(original.easeFactor)→\(after.easeFactor)") }
            // Dates are compared to the second: `.iso8601` drops the fractional part, so a
            // sub-second delta is the format working as designed (see `DeckTransfer`). Anything
            // a whole second or more out is a real bug and still fails.
            func dateDrift(_ name: String, _ a: Date?, _ b: Date?) {
                guard a != b else { return }
                guard let a, let b else { return fields.append("\(name) \(a == nil ? "nil→date" : "date→nil")") }
                let delta = b.timeIntervalSinceReferenceDate - a.timeIntervalSinceReferenceDate
                if abs(delta) >= 1 { fields.append(String(format: "\(name) %+.3fs", delta)) }
            }
            dateDrift("nextReviewDate", original.nextReviewDate, after.nextReviewDate)
            dateDrift("lastReviewedAt", original.lastReviewedAt, after.lastReviewedAt)
            dateDrift("firstReviewedAt", original.firstReviewedAt, after.firstReviewedAt)
            return fields.isEmpty ? nil : "\(after.germanWord)[\(fields.joined(separator: ", "))]"
        }
        let restored = copy.cards.filter { $0.totalReviews > 0 }.count
        notes.append(drifted.isEmpty && restored == studiedCards
            ? "progress identical on all \(copy.cards.count) cards (\(restored) reviewed)"
            : "FAIL: \(restored)/\(studiedCards) reviewed came back; \(drifted.count) drifted — \(drifted.prefix(3).joined(separator: " "))")

        // Leave no junk behind: the copy existed only to be compared.
        context.delete(copy)
        try? context.save()

        return "[deckTransfer] " + notes.joined(separator: " · ")
    }
}
#endif
