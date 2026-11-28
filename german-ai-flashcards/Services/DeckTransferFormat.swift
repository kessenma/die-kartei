//
//  DeckTransferFormat.swift
//  german-ai-flashcards
//
//  The `.kartei` deck file itself: its JSON shape, how it's read and checked, how it's written.
//  Foundation only and shared with the Android app (DieKarteiCore), so a deck file written by one
//  app is byte-for-byte what the other writes and is read by the same checks. The reasons behind
//  the format (progress travels, pictures and results don't, second-granular dates, the deck's
//  own UUID) are in DeckTransfer.swift's header; the iOS sharing and SwiftData halves stay there
//  and in DeckImporter.swift.
//

import Foundation

/// Codable representation of a conjugation for persistence.
struct StoredConjugation: Codable, Equatable {
    var tense: String
    var ich: String
    var du: String
    var erSieEs: String
    var wir: String
    var ihr: String
    var sieSie: String

    init(from conjugation: Conjugation) {
        self.tense = conjugation.tense
        self.ich = conjugation.ich
        self.du = conjugation.du
        self.erSieEs = conjugation.erSieEs
        self.wir = conjugation.wir
        self.ihr = conjugation.ihr
        self.sieSie = conjugation.sieSie
    }

    func toConjugation() -> Conjugation {
        Conjugation(
            tense: tense,
            ich: ich,
            du: du,
            erSieEs: erSieEs,
            wir: wir,
            ihr: ihr,
            sieSie: sieSie
        )
    }
}

struct DeckTransferEnvelope: Codable, Equatable {
    struct App: Codable, Equatable {
        var name: String
        var version: String?
        var build: String?
    }

    /// One card's scheduling state. Optional on `Card` so a deck can be shared without it.
    struct Progress: Codable, Equatable {
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

    struct Card: Codable, Equatable {
        var id: String
        var germanWord: String
        var englishTranslation: String
        var wordType: String?
        var article: String?
        var exampleSentence: String?
        /// Structured rather than the stored `Data` blob: a JSON file with base64 inside it is a
        /// file no one can read, and the blob is only ever `[StoredConjugation]` anyway.
        var conjugations: [StoredConjugation]?
        var sortOrder: Int
        var progress: Progress?
    }

    struct Deck: Codable, Equatable {
        var id: String
        var topic: String
        var wordCount: Int
        var includeExamples: Bool
        var includeGender: Bool
        var wordTypeFilter: String
        var includeConjugations: Bool
        var selectedTenses: [String]
        var createdAt: Date
        var generationTimeSeconds: Double
        /// `SavedDeck.generatorRaw` — which model or source made this deck, so the receiving
        /// device shows the same badge in the Library.
        var generator: String
        var cards: [Card]
    }

    var schema: String = DeckTransferFormat.schema
    var schemaVersion: Int = DeckTransferFormat.schemaVersion
    var exportedAt: Date
    var app: App
    /// False in schema 1 — see the header. Here so a package format never needs a version bump.
    var includesImages: Bool = false
    var deck: Deck

    var includesProgress: Bool { deck.cards.contains { $0.progress != nil } }
}

extension DeckTransferEnvelope.Progress {
    /// The block to write for a card, or nil for one never studied: an untouched deck exports as
    /// plain content and the file stays readable.
    var ifStudied: Self? {
        let untouched = totalReviews == 0
            && repetitions == 0
            && leitnerBox == 0
            && lapses == 0
            && nextReviewDate == nil
            && lastReviewedAt == nil
        return untouched ? nil : self
    }
}

/// Why a file couldn't be taken in.
enum DeckTransferFailure: LocalizedError, Equatable {
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

nonisolated enum DeckTransferFormat {
    static let schema = "die-kartei.deck"
    static let schemaVersion = 1
    static let fileExtension = "kartei"
    /// Why the last file didn't decode, for the log (the learner sees `notADeck`).
    nonisolated(unsafe) static var lastDecodingError: String?

    /// The file's bytes: ISO dates (second-granular, on purpose), sorted keys, readable.
    static func encode(_ envelope: DeckTransferEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    /// A file's deck, or why it can't be taken in.
    static func decode(_ data: Data) throws -> DeckTransferEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: DeckTransferEnvelope
        do {
            envelope = try decoder.decode(DeckTransferEnvelope.self, from: data)
        } catch {
            lastDecodingError = "\(error)"
            throw DeckTransferFailure.notADeck
        }
        guard envelope.schema == schema else { throw DeckTransferFailure.notADeck }
        guard envelope.schemaVersion <= schemaVersion else {
            throw DeckTransferFailure.fromANewerVersion(envelope.schemaVersion)
        }
        guard envelope.deck.generator != "goethe-srs" else { throw DeckTransferFailure.wortschatz }
        return envelope
    }

    /// Whether a deck may leave the device: the Wortschatz box is a merged singleton keyed to the
    /// bundled Goethe index, so a second one arriving elsewhere would break the hub.
    static func canExport(generatorRaw: String) -> Bool {
        DeckKind(generatorRaw: generatorRaw) != .goetheSRS
    }

    /// A file name that survives a topic with slashes, colons or emoji in it.
    static func fileStem(_ topic: String, fallback: String = "deck") -> String {
        let allowed = topic.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? fallback : String(collapsed.prefix(40))
    }

    static func fileName(topic: String) -> String { "\(fileStem(topic)).\(fileExtension)" }
}
