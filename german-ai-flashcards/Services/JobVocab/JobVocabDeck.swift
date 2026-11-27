//
//  JobVocabDeck.swift
//  german-ai-flashcards
//
//  From words picked in job ads to cards in a deck, many at a time. The pieces:
//   • `JobVocabRow` — one word or phrase on its way to a card, editable before it is saved;
//   • `JobVocabKnown` — English the app already has, so most rows need no tutor: words looked up in
//     any posting, cards in the learner's decks, the Goethe lists;
//   • `JobVocabTranslator` — the tutor for the rest, batched, asking for the dictionary form
//     („Kenntnissen“ → „die Kenntnis“, „entwickelst“ → „entwickeln“) as well as the English;
//   • `JobVocabSaver` — into the posting's deck, a deck the learner already has, or a new one,
//     through `DeckCardAdder` (deduped by `CardKind.matchKey`, phrase or word by `CardKind`).
//
//  The house rule holds: a card never has an empty English side. A row without English is left
//  out, and the save sheet says how many.
//

import Foundation
import SwiftData

/// A word or phrase on its way to a card.
struct JobVocabRow: Identifiable, Hashable {
    var id = UUID()
    /// What the card's German side will say. Starts as the spelling in the ad.
    var german: String
    var english: String = ""
    /// The sentence of the ad it came from, kept as the card's example.
    var example: String?
    var include = true
    /// The spelling as it stands in the ad, which is what the tutor is asked about.
    var fromText: String
    var origin: Origin = .none

    enum Origin: String, Hashable {
        case none, lookup, deck, goethe, tutor, typed

        var label: String? {
            switch self {
            case .none, .typed: nil
            case .lookup: "looked up"
            case .deck: "in a deck"
            case .goethe: "Goethe list"
            case .tutor: "tutor"
            }
        }
    }

    init(german: String, example: String? = nil) {
        self.german = german
        self.fromText = german
        self.example = example
    }

    var isPhrase: Bool { CardKind.split(german).isPhrase }

    /// Would make a card now: German, and English of its own (the document decks' gate).
    var makesCard: Bool {
        DocumentDeckService.makesCard(VocabListRow(german: german, english: english))
    }
}

// MARK: - English the app already has

enum JobVocabKnown {
    struct Entry: Hashable {
        /// The German as the source has it, with its article when it has one („die Erfahrung“).
        let german: String
        let english: String
        let origin: JobVocabRow.Origin
    }

    /// Everything known, by `CardKind.matchKey`. Looked-up words win over deck cards, which win
    /// over the Goethe lists: the nearer to this learner and these ads, the better the answer.
    static func index(postings: [JobPosting], decks: [SavedDeck]) -> [String: Entry] {
        var known: [String: Entry] = [:]
        for word in GoetheVocabService.orderedWords {
            guard let english = word.translation?.trimmingCharacters(in: .whitespaces), !english.isEmpty else { continue }
            let german = [word.article, word.word].compactMap { $0 }.joined(separator: " ")
            known[CardKind.matchKey(word.word)] = Entry(german: german, english: english, origin: .goethe)
        }
        for deck in decks where deck.isBrowsableContent {
            for card in deck.cards where !card.englishTranslation.trimmingCharacters(in: .whitespaces).isEmpty {
                let german = [card.article, card.germanWord].compactMap { $0 }.joined(separator: " ")
                known[CardKind.matchKey(card.germanWord)] = Entry(german: german, english: card.englishTranslation, origin: .deck)
            }
        }
        for posting in postings {
            for entry in posting.lookups.reversed() where !entry.english.isEmpty {
                known[CardKind.matchKey(entry.german)] = Entry(german: entry.german, english: entry.english, origin: .lookup)
            }
        }
        return known
    }

    /// The known answer for a spelling: the spelling itself, else another spelling of the same
    /// word (same stem, same capital: „Kunden“ finds „der Kunde“, „Arbeit“ never finds
    /// „arbeiten“). Phrases only match whole.
    static func lookup(_ german: String, in known: [String: Entry], stems: [String: Entry]) -> Entry? {
        if let exact = known[CardKind.matchKey(german)] { return exact }
        let split = CardKind.split(german)
        guard !split.isPhrase else { return nil }
        return stems[stemKey(split.word)]
    }

    /// The same index by stem, for `lookup`'s second try.
    static func stemIndex(_ known: [String: Entry]) -> [String: Entry] {
        var stems: [String: Entry] = [:]
        for entry in known.values {
            let split = CardKind.split(entry.german)
            guard !split.isPhrase else { continue }
            let key = stemKey(split.word)
            // Keep the better source when two words share a stem.
            if let existing = stems[key], rank(existing.origin) >= rank(entry.origin) { continue }
            stems[key] = entry
        }
        return stems
    }

    private static func stemKey(_ word: String) -> String {
        (word.first?.isUppercase == true ? "N:" : "w:") + GermanStem.stem(word)
    }

    private static func rank(_ origin: JobVocabRow.Origin) -> Int {
        switch origin {
        case .lookup: 3
        case .deck: 2
        case .goethe: 1
        default: 0
        }
    }

    /// Fill each row's English (and, for a single word, its dictionary form) from what is known.
    /// Rows that already have English are left alone.
    static func fill(_ rows: [JobVocabRow], from known: [String: Entry]) -> [JobVocabRow] {
        let stems = stemIndex(known)
        return rows.map { row in
            guard row.english.isEmpty, let entry = lookup(row.german, in: known, stems: stems) else { return row }
            var out = row
            out.english = entry.english
            if !row.isPhrase { out.german = entry.german }
            out.origin = entry.origin
            return out
        }
    }
}

// MARK: - The tutor

@Observable
@MainActor
final class JobVocabTranslator {
    private(set) var isRunning = false
    private(set) var progress: Double = 0
    private(set) var statusText = ""
    private(set) var failure: String?

    private let mlxService: MLXGenerationService

    init(mlxService: MLXGenerationService) {
        self.mlxService = mlxService
    }

    static let system = """
    Du bekommst deutsche Wörter und Wendungen aus einer Stellenanzeige, so wie sie im Text stehen, \
    eine pro Zeile. Gib für jede Zeile die Grundform und die englische Bedeutung in einer Stellenanzeige \
    zurück, GENAU im Format:
    grundform = english
    Grundform: Nomen im Nominativ Singular mit Artikel („die Kenntnis“), Verben im Infinitiv („entwickeln“), \
    Adjektive ohne Endung („fundiert“). Wendungen aus mehreren Wörtern bleiben, wie sie sind. \
    Eine Zeile pro Eingabe, in derselben Reihenfolge, keine Erklärungen.
    """

    /// Fill in the rows without English. Returns the rows; a row the tutor didn't answer keeps its
    /// empty English (and so is left out of the deck unless the learner types one).
    func translate(_ rows: [JobVocabRow], model: MLXModel) async -> [JobVocabRow] {
        let pending = rows.indices.filter { rows[$0].include && rows[$0].english.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !pending.isEmpty else { return rows }
        isRunning = true
        failure = nil
        defer { isRunning = false }

        if !mlxService.isModelLoaded || mlxService.currentModel != model {
            statusText = "Loading \(model.rawValue)…"
            progress = 0.05
            await mlxService.loadModel(model)
        }
        guard mlxService.isModelLoaded, mlxService.currentModel == model else {
            failure = mlxService.loadError ?? "Couldn't load \(model.rawValue)."
            return rows
        }

        statusText = "Der Tutor übersetzt…"
        var out = rows
        let batchSize = 12
        let batches = stride(from: 0, to: pending.count, by: batchSize).map {
            Array(pending[$0 ..< min($0 + batchSize, pending.count)])
        }
        for (number, batch) in batches.enumerated() {
            let asked = batch.map { out[$0].fromText.trimmingCharacters(in: .whitespaces) }
            if let raw = try? await mlxService.generateText(
                system: Self.system,
                user: asked.joined(separator: "\n"),
                model: model,
                maxTokens: 40 + batch.count * 26
            ) {
                let answers = Self.assign(DocumentDeckService.parsePairs(raw), to: asked)
                for (position, index) in batch.enumerated() {
                    guard let answer = answers[position] else { continue }
                    out[index].english = answer.english
                    // A phrase stays the phrase the learner picked; a word takes its dictionary form.
                    if !out[index].isPhrase { out[index].german = answer.german }
                    out[index].origin = .tutor
                }
            }
            progress = Double(number + 1) / Double(batches.count)
        }
        statusText = ""
        return out
    }

    /// The tutor's answers to one batch, by position in `asked`. Answering every line means the
    /// order holds, so each answer goes to its line; otherwise an answer goes to the line it names
    /// (the same word, or one with the same stem). A dictionary form is taken only when it is
    /// recognisably the same word as the spelling asked about; else the spelling stays.
    static func assign(_ pairs: [(String, String)], to asked: [String]) -> [Int: (german: String, english: String)] {
        var out: [Int: (german: String, english: String)] = [:]
        if pairs.count == asked.count {
            for (index, pair) in pairs.enumerated() {
                out[index] = (sameWord(asked[index], pair.0) ? pair.0 : asked[index], pair.1)
            }
            return out
        }
        for pair in pairs {
            guard let index = asked.indices.first(where: { out[$0] == nil && sameWord(asked[$0], pair.0) }) else { continue }
            out[index] = (pair.0, pair.1)
        }
        return out
    }

    /// Whether the tutor's German is a form of the asked spelling: the same key, or for a single
    /// word the same stem or the same first five letters („Kenntnissen“ / „die Kenntnis“).
    static func sameWord(_ asked: String, _ answered: String) -> Bool {
        let a = CardKind.matchKey(asked), b = CardKind.matchKey(answered)
        if a == b { return true }
        let left = CardKind.split(asked), right = CardKind.split(answered)
        guard !left.isPhrase, !right.isPhrase else { return false }
        if GermanStem.stem(left.word) == GermanStem.stem(right.word) { return true }
        let prefix = min(5, a.count, b.count)
        return prefix >= 4 && a.prefix(prefix) == b.prefix(prefix)
    }
}

// MARK: - Saving

/// Where the picked words go.
enum JobVocabDeckChoice: Hashable {
    /// The posting's own deck, created on the first save.
    case posting(UUID)
    case existing(UUID)
    case new
}

enum JobVocabSaver {
    /// The rows that make a card, into `deck`. Returns how many were added (a word already in the
    /// deck is not added twice).
    @discardableResult
    static func save(_ rows: [JobVocabRow], into deck: SavedDeck, feedsCoach: Bool, context: ModelContext) -> Int {
        var added: [(german: String, english: String)] = []
        for row in rows where row.include && row.makesCard {
            let german = row.german.trimmingCharacters(in: .whitespacesAndNewlines)
            let english = row.english.trimmingCharacters(in: .whitespacesAndNewlines)
            let example = row.example.flatMap { $0.caseInsensitiveCompare(german) == .orderedSame ? nil : $0 }
            if DeckCardAdder.add(german: german, english: english, example: example, to: deck, context: context) {
                added.append((CardKind.split(german).word, english))
            }
        }
        if added.isEmpty { return 0 }
        if rows.contains(where: { $0.include && $0.example != nil }) { deck.includeExamples = true }
        try? context.save()
        if feedsCoach {
            LearnerMemoryService.noteVocabEncounters(added, source: "job", in: context)
        }
        return added.count
    }

    /// A new deck for words gathered across ads. A job deck, so it sits under Job prep ▸ Job
    /// decks and wears the briefcase in the Library.
    static func makeDeck(named name: String, context: ModelContext) -> SavedDeck {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let deck = SavedDeck(topic: trimmed.isEmpty ? "Job-Wortschatz" : String(trimmed.prefix(90)),
                             wordCount: 0, includeExamples: true, includeGender: true)
        deck.generatorRaw = JobDeckStore.generatorRaw
        context.insert(deck)
        return deck
    }
}
