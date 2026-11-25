//
//  DocumentDeckService.swift
//  german-ai-flashcards
//
//  Turns the rows the learner assembled from a document into a flashcard deck: the tutor pairs a
//  list the parser couldn't, translates the German that came without English (a phrase highlighted
//  in a story, a word the sheet left blank), and the deck is saved, linked to a course when it
//  came from one. The tutor is loaded only when there is something for it to do, so a sheet that
//  already carries both columns becomes a deck without a model in memory.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class DocumentDeckService {
    enum Phase: Equatable {
        case idle
        case loadingModel
        case pairing
        case translating
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var statusText: String = ""

    var isRunning: Bool {
        switch phase {
        case .idle, .done, .failed: false
        default: true
        }
    }

    private let mlxService: MLXGenerationService
    private let modelContext: ModelContext

    init(mlxService: MLXGenerationService, modelContext: ModelContext) {
        self.mlxService = mlxService
        self.modelContext = modelContext
    }

    // MARK: - Pairing

    /// Ask the tutor to read a vocabulary list (one row per line, columns unmarked) into pairs.
    /// The fallback for a sheet the parser misreads. Nil when the model couldn't load or answered
    /// nothing usable.
    func pair(lines: [String], model: MLXModel) async -> [VocabListRow]? {
        guard await ensureLoaded(model) else { return nil }
        phase = .pairing
        statusText = "Der Tutor liest die Liste…"
        progress = 0.2
        let system = """
        Du bekommst Zeilen aus einer Vokabelliste (Deutsch und Englisch in einer Zeile, ohne Trennzeichen). \
        Gib für jede Zeile das deutsche Wort oder die deutsche Wendung und die englische Bedeutung zurück, \
        GENAU im Format:
        deutsch = english
        Behalte Artikel und Pluralformen beim deutschen Teil. Erfinde nichts, lass keine Zeile aus, keine Erklärungen.
        """
        var rows: [VocabListRow] = []
        let batchSize = 15
        let batches: [[String]] = stride(from: 0, to: lines.count, by: batchSize).map {
            Array(lines[$0 ..< min($0 + batchSize, lines.count)])
        }
        for (index, batch) in batches.enumerated() {
            if let raw = try? await mlxService.generateText(
                system: system,
                user: batch.joined(separator: "\n"),
                model: model,
                maxTokens: 60 + batch.count * 28
            ) {
                for (german, english) in Self.parsePairs(raw) {
                    rows.append(VocabListRow(german: german, english: english, marked: false, confident: true))
                }
            }
            progress = 0.2 + 0.7 * Double(index + 1) / Double(batches.count)
        }
        phase = rows.isEmpty ? .failed("The tutor couldn't read that list.") : .done
        progress = 1
        return rows.isEmpty ? nil : rows
    }

    // MARK: - Translation

    /// Fill in the English of every row that has none. Rows already complete are returned as they
    /// are; a row the tutor didn't answer keeps its empty English.
    func translate(_ rows: [VocabListRow], model: MLXModel) async -> [VocabListRow] {
        let pending = rows.filter { !$0.isComplete && !$0.german.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !pending.isEmpty else { return rows }
        guard await ensureLoaded(model) else { return rows }
        phase = .translating
        statusText = "Wörter werden übersetzt…"
        progress = 0.2
        let system = """
        Übersetze die folgenden deutschen Wörter und Wendungen ins Englische. Bei Nomen gib den Artikel mit an \
        (z.B. „die Katze = cat“). Antworte mit je einem Eintrag pro Zeile, GENAU im Format:
        deutsch = english
        Keine weiteren Erklärungen.
        """
        var translations: [String: String] = [:]
        let batchSize = 12
        let words = pending.map { $0.german.trimmingCharacters(in: .whitespaces) }
        let batches: [[String]] = stride(from: 0, to: words.count, by: batchSize).map {
            Array(words[$0 ..< min($0 + batchSize, words.count)])
        }
        for (index, batch) in batches.enumerated() {
            if let raw = try? await mlxService.generateText(
                system: system,
                user: batch.joined(separator: "\n"),
                model: model,
                maxTokens: 40 + batch.count * 22
            ) {
                Self.assign(Self.parsePairs(raw), to: batch, into: &translations)
            }
            progress = 0.2 + 0.7 * Double(index + 1) / Double(batches.count)
        }
        var out = rows
        for index in out.indices where !out[index].isComplete {
            if let english = translations[Self.key(out[index].german)] {
                out[index].english = english
            }
        }
        phase = .done
        progress = 1
        return out
    }

    // MARK: - Saving

    /// The deck, from the rows that make a card (`makesCard`). Nil when none do. A document brought
    /// in from outside is kept with the deck (`keeping`), so it can join a course as a handout later.
    @discardableResult
    func save(title: String, rows: [VocabListRow], course: ClassCourse?, sourceLabel: String?,
              keeping source: DocumentDeckDraft? = nil) -> SavedDeck? {
        let vocab = Self.merge(rows)
        guard !vocab.isEmpty else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let deck = SavedDeck(
            topic: cleanTitle.isEmpty ? (sourceLabel ?? "Document") : String(cleanTitle.prefix(90)),
            wordCount: vocab.count,
            includeExamples: vocab.contains { $0.exampleSentence != nil },
            includeGender: vocab.contains { $0.article != nil },
            vocabCards: vocab
        )
        deck.generatorRaw = "document"
        deck.courseID = course?.id
        if let source, source.keepsSource {
            deck.sourceText = source.text
            deck.sourceFile = source.fileData.flatMap { ClassMaterialStore.save($0, ext: source.fileExt) }
        }
        modelContext.insert(deck)
        course?.updatedAt = .now
        try? modelContext.save()
        return deck
    }

    /// The rows as cards. A word the sheet lists twice — a Wortliste repeating what the lesson
    /// pages taught — is one card that gathers what each mention had. Keeping the first and
    /// dropping the rest would be right only as long as the richer mention happened to come first.
    ///
    /// Word class: **an article always wins.** `der Tisch` is a noun because the sheet says so, and
    /// no inference can argue; a row with no article takes whatever `WordClassInference` worked out,
    /// and an article arriving on a later mention upgrades a card the first mention only guessed at.
    /// Inference only ever speaks where there is no article.
    ///
    /// Its own function, and not `nonisolated`, because `VocabCard`'s memberwise init is main-actor
    /// isolated like everything else in this target.
    static func merge(_ rows: [VocabListRow]) -> [VocabCard] {
        var vocab: [VocabCard] = []
        var index: [String: Int] = [:]
        for row in rows where makesCard(row) {
            let key = Self.key(row.german)
            let split = CardKind.split(row.german)
            let (word, article) = (split.word, split.article)
            if let existing = index[key] {
                if vocab[existing].exampleSentence == nil { vocab[existing].exampleSentence = row.example }
                if vocab[existing].forms == nil { vocab[existing].forms = row.forms }
                // A phrase stays a phrase: no word class or article from a later mention.
                if vocab[existing].wordType == CardKind.phrase || split.isPhrase { continue }
                if vocab[existing].wordType == nil, let inferred = row.wordClass?.rawValue {
                    vocab[existing].wordType = inferred
                }
                if vocab[existing].article == nil, let article {
                    vocab[existing].article = article
                    vocab[existing].wordType = "noun"
                }
                continue
            }
            index[key] = vocab.count
            vocab.append(VocabCard(
                germanWord: word,
                englishTranslation: row.english.trimmingCharacters(in: .whitespaces),
                wordType: split.isPhrase ? CardKind.phrase : (article != nil ? "noun" : row.wordClass?.rawValue),
                article: article,
                exampleSentence: row.example,
                conjugations: nil,
                forms: row.forms
            ))
        }
        return vocab
    }

    // MARK: - What makes a card

    /// Whether a row becomes a card: German, and English of its own. Not a blank, not a dash or a
    /// "?" (no letter), not German ("in diesem Lernkontext ohne Plural.", or the tutor answering in
    /// German), and not the German word again with nothing to learn: "Python" → "Python" is left
    /// out, while "der Server" → "server" stays, since its article is the point. The one rule every
    /// way into a document deck goes through (`merge`), so no card is ever saved half empty.
    nonisolated static func makesCard(_ row: VocabListRow) -> Bool {
        let english = row.english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !row.german.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              english.contains(where: \.isLetter),
              !VocabListParser.readsGerman(english) else { return false }
        return !repeatsGerman(row)
    }

    /// The English is the German again ("SQL" → "SQL") and the German has no article to teach.
    nonisolated static func repeatsGerman(_ row: VocabListRow) -> Bool {
        guard CardKind.split(row.german).article == nil else { return false }
        func letters(_ text: String) -> String { String(text.lowercased().filter { $0.isLetter || $0.isNumber }) }
        return letters(row.german) == letters(row.english)
    }

    // MARK: - Helpers

    private func ensureLoaded(_ model: MLXModel) async -> Bool {
        if !mlxService.isModelLoaded || mlxService.currentModel != model {
            phase = .loadingModel
            statusText = "Loading \(model.rawValue)…"
            progress = 0.05
            await mlxService.loadModel(model)
        }
        guard mlxService.isModelLoaded, mlxService.currentModel == model else {
            phase = .failed(mlxService.loadError ?? "Couldn't load \(model.rawValue).")
            return false
        }
        return true
    }

    /// Lowercased, article stripped: how a German entry is matched against the tutor's answer.
    static func key(_ german: String) -> String { CardKind.matchKey(german) }

    /// One batch's answers into `translations`, by German. A tutor that rewords a phrase
    /// ("Störungen beheben" → "eine Störung beheben") still answers it, under a German the key
    /// can't find, and the row used to be dropped for having no English. When the tutor answered
    /// every line of the batch, the misses fall back to position.
    static func assign(_ pairs: [(String, String)], to batch: [String], into translations: inout [String: String]) {
        for (german, english) in pairs { translations[key(german)] = english }
        guard pairs.count == batch.count else { return }
        for (german, pair) in zip(batch, pairs) where translations[key(german)] == nil {
            translations[key(german)] = pair.1
        }
    }

    /// `deutsch = english` lines, bullets and numbering stripped.
    static func parsePairs(_ raw: String) -> [(String, String)] {
        let cleaned = ConversationPrompts.stripThinkBlocks(raw)
        var result: [(String, String)] = []
        for line in cleaned.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.range(of: "=") ?? trimmed.range(of: " - ") ?? trimmed.range(of: " — ") else { continue }
            var german = String(trimmed[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            german = german.trimmingCharacters(in: CharacterSet(charactersIn: "-•*0123456789. )"))
            let english = String(trimmed[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            if german.count >= 2, !english.isEmpty { result.append((german, english)) }
        }
        return result
    }
}
