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
                for (german, english) in Self.parsePairs(raw) {
                    translations[Self.key(german)] = english
                }
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

    /// The deck, from the rows that have both sides. Nil when none do.
    @discardableResult
    func save(title: String, rows: [VocabListRow], course: ClassCourse?, sourceLabel: String?) -> SavedDeck? {
        var seen = Set<String>()
        let vocab: [VocabCard] = rows.compactMap { row in
            guard row.isComplete else { return nil }
            let key = Self.key(row.german)
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            let (word, article) = Self.splitArticle(row.german.trimmingCharacters(in: .whitespaces))
            return VocabCard(
                germanWord: word,
                englishTranslation: row.english.trimmingCharacters(in: .whitespaces),
                wordType: article != nil ? "noun" : nil,
                article: article,
                exampleSentence: nil,
                conjugations: nil
            )
        }
        guard !vocab.isEmpty else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let deck = SavedDeck(
            topic: cleanTitle.isEmpty ? (sourceLabel ?? "Document") : String(cleanTitle.prefix(90)),
            wordCount: vocab.count,
            includeExamples: false,
            includeGender: vocab.contains { $0.article != nil },
            vocabCards: vocab
        )
        deck.generatorRaw = "document"
        deck.courseID = course?.id
        modelContext.insert(deck)
        course?.updatedAt = .now
        try? modelContext.save()
        return deck
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
    static func key(_ german: String) -> String {
        splitArticle(german.trimmingCharacters(in: .whitespaces)).0.lowercased()
    }

    static func splitArticle(_ word: String) -> (String, String?) {
        for article in ["der ", "die ", "das "] where word.lowercased().hasPrefix(article) {
            return (String(word.dropFirst(article.count)).trimmingCharacters(in: .whitespaces), String(article.dropLast()))
        }
        return (word, nil)
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
