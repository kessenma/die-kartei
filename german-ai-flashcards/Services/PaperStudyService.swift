import DieKarteiCore
import Foundation
import SwiftData

/// Generates German study materials (summary, vocab deck, questions) from a paper's text.
/// Pinned to the Gemma 4 model, which the user validated for this task.
@Observable
@MainActor
final class PaperStudyService {

    /// The recommended default model for this feature (Gemma 4 — strong German, multimodal-capable).
    static let requiredModel: MLXModel = .gemma4_E4B

    enum Phase: Equatable {
        case idle
        case loadingModel
        case summarizing
        case cards
        case questions
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var statusText: String = ""

    var isRunning: Bool {
        switch phase {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    private let mlxService: MLXGenerationService
    private let modelContext: ModelContext

    init(mlxService: MLXGenerationService, modelContext: ModelContext) {
        self.mlxService = mlxService
        self.modelContext = modelContext
    }

    private(set) var model: MLXModel = PaperStudyService.requiredModel

    // MARK: - Generation

    func generate(for paper: StudyPaper, model: MLXModel, deckCount: Int, questionCount: Int, selectedWords: [String]? = nil) async {
        self.model = model
        paper.modelRaw = model.rawValue
        try? modelContext.save()

        phase = .loadingModel
        progress = 0
        statusText = "Loading \(model.rawValue)…"

        if !mlxService.isModelLoaded || mlxService.currentModel != model {
            await mlxService.loadModel(model)
        }
        guard mlxService.isModelLoaded, mlxService.currentModel == model else {
            phase = .failed(mlxService.loadError ?? "Couldn’t load \(model.rawValue).")
            return
        }

        let chunks = PDFTextExtractor.chunk(paper.fullText, maxChars: 1500)
        guard !chunks.isEmpty else {
            phase = .failed("No readable text found in this PDF.")
            return
        }

        // 1. Summary + key points (from a bounded excerpt — enough to ground the discussion).
        phase = .summarizing
        statusText = "Zusammenfassung wird erstellt…"
        progress = 0.1
        await makeSummary(for: paper, chunks: chunks)

        // 2. Vocab deck.
        phase = .cards
        statusText = "Vokabeln werden extrahiert…"
        if let selectedWords, !selectedWords.isEmpty {
            await makeDeck(for: paper, words: selectedWords)
        } else {
            await makeDeck(for: paper, chunks: chunks, target: deckCount)
        }

        // 3. Questions.
        phase = .questions
        statusText = "Fragen werden erstellt…"
        progress = 0.9
        await makeQuestions(for: paper, count: questionCount)

        paper.generationComplete = true
        try? modelContext.save()
        progress = 1
        phase = .done
        statusText = "Fertig!"
    }

    // MARK: - Steps

    private func makeSummary(for paper: StudyPaper, chunks: [String]) async {
        // Use the opening chunks (abstract/intro carry the gist); bound the input size.
        let excerpt = chunks.prefix(4).joined(separator: "\n\n")
        let system = """
        Du bist ein wissenschaftlicher Assistent. Fasse den folgenden deutschen Text sachlich zusammen. \
        Antworte AUF DEUTSCH und genau in diesem Format:
        ZUSAMMENFASSUNG:
        <4–6 Sätze>
        KERNPUNKTE:
        - <Stichpunkt>
        - <Stichpunkt>
        """
        do {
            let raw = try await mlxService.generateText(system: system, user: "Text:\n\n\(excerpt)", model: model, maxTokens: 420)
            let (summary, points) = parseSummary(raw)
            paper.germanSummary = summary.isEmpty ? ConversationPrompts.stripThinkBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines) : summary
            paper.keyPoints = points
            try? modelContext.save()
        } catch {
            // Non-fatal: a missing summary falls back to a text excerpt for the chat.
        }
        progress = 0.35
    }

    private func makeDeck(for paper: StudyPaper, chunks: [String], target: Int) async {
        var pairs: [(german: String, english: String)] = []
        var seen = Set<String>()
        let chunkCap = min(chunks.count, 8)

        for (index, chunk) in chunks.prefix(chunkCap).enumerated() {
            if pairs.count >= target { break }
            let system = """
            Extrahiere wichtige deutsche Fachbegriffe oder Schlüsselwörter aus dem Text, mit einer natürlichen englischen Übersetzung. \
            Antworte mit je einem Eintrag pro Zeile, GENAU im Format:
            deutsch = english
            Keine weiteren Erklärungen.
            """
            do {
                let raw = try await mlxService.generateText(system: system, user: "Text:\n\n\(chunk)", model: model, maxTokens: 220)
                for (g, e) in parsePairs(raw) {
                    let key = g.lowercased()
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    pairs.append((g, e))
                    if pairs.count >= target { break }
                }
            } catch {
                // Skip a failed chunk.
            }
            progress = 0.35 + 0.5 * (Double(index + 1) / Double(chunkCap))
        }

        saveDeck(for: paper, pairs: pairs)
    }

    /// Build the deck from user-picked words: translate exactly those words in batches
    /// instead of letting the model mine the text for its own picks.
    private func makeDeck(for paper: StudyPaper, words: [String]) async {
        var pairs: [(german: String, english: String)] = []
        var seen = Set<String>()
        let batchSize = 12
        let batches: [[String]] = stride(from: 0, to: words.count, by: batchSize).map {
            Array(words[$0 ..< min($0 + batchSize, words.count)])
        }
        let system = """
        Übersetze die folgenden deutschen Wörter ins Englische. Bei Nomen gib den Artikel mit an (z.B. „die Katze = cat“). \
        Antworte mit je einem Eintrag pro Zeile, GENAU im Format:
        deutsch = english
        Keine weiteren Erklärungen.
        """
        for (index, batch) in batches.enumerated() {
            do {
                let raw = try await mlxService.generateText(
                    system: system,
                    user: batch.joined(separator: "\n"),
                    model: model,
                    maxTokens: 40 + batch.count * 18
                )
                for (g, e) in parsePairs(raw) {
                    let key = g.lowercased()
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    pairs.append((g, e))
                }
            } catch {
                // Skip a failed batch.
            }
            progress = 0.35 + 0.5 * (Double(index + 1) / Double(batches.count))
        }

        saveDeck(for: paper, pairs: pairs)
    }

    private func saveDeck(for paper: StudyPaper, pairs: [(german: String, english: String)]) {
        guard !pairs.isEmpty else { return }
        let vocab = pairs.map { pair -> VocabCard in
            let (german, article) = splitArticle(pair.german)
            return VocabCard(
                germanWord: german,
                englishTranslation: pair.english,
                wordType: article != nil ? "noun" : nil,
                article: article,
                exampleSentence: nil,
                conjugations: nil
            )
        }
        let deck = SavedDeck(
            topic: "Paper: \(paper.title)",
            wordCount: vocab.count,
            includeExamples: false,
            includeGender: vocab.contains { $0.article != nil },
            vocabCards: vocab
        )
        deck.generatorRaw = "paper"
        modelContext.insert(deck)
        paper.deckID = deck.id
        try? modelContext.save()
    }

    private func makeQuestions(for paper: StudyPaper, count: Int) async {
        let reference = paper.conversationContext
        let system = """
        Du bist Prüfer. Erstelle \(count) anspruchsvolle Prüfungsfragen AUF DEUTSCH zum folgenden Material. \
        Gib zu jeder Frage eine kurze Musterantwort. Antworte mit je einer Zeile, GENAU im Format:
        Frage | Musterantwort
        """
        do {
            let raw = try await mlxService.generateText(system: system, user: "Material:\n\n\(reference)", model: model, maxTokens: 120 + count * 70)
            let questions = parseQuestions(raw, limit: count)
            if !questions.isEmpty {
                paper.setQuestions(questions)
                try? modelContext.save()
            }
        } catch {
            // Non-fatal.
        }
    }

    // MARK: - Parsing

    private func parseSummary(_ raw: String) -> (summary: String, points: [String]) {
        let cleaned = ConversationPrompts.stripThinkBlocks(raw)
        var summary = ""
        var points: [String] = []
        enum Section { case none, summary, points }
        var section: Section = .none
        for line in cleaned.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let upper = trimmed.uppercased()
            if upper.hasPrefix("ZUSAMMENFASSUNG") { section = .summary; continue }
            if upper.hasPrefix("KERNPUNKTE") || upper.hasPrefix("STICHPUNKTE") { section = .points; continue }
            switch section {
            case .summary: summary += (summary.isEmpty ? "" : " ") + trimmed
            case .points:
                let item = stripBullet(trimmed)
                if !item.isEmpty { points.append(item) }
            case .none:
                summary += (summary.isEmpty ? "" : " ") + trimmed
            }
        }
        return (summary, points)
    }

    private func parsePairs(_ raw: String) -> [(String, String)] {
        let cleaned = ConversationPrompts.stripThinkBlocks(raw)
        var result: [(String, String)] = []
        for line in cleaned.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let sep = trimmed.range(of: "=") ?? trimmed.range(of: " - ") ?? trimmed.range(of: " — ") else { continue }
            var german = String(trimmed[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
            german = german.trimmingCharacters(in: CharacterSet(charactersIn: "-•*0123456789. )"))
            let english = String(trimmed[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
            if german.count >= 2, !english.isEmpty { result.append((german, english)) }
        }
        return result
    }

    private func parseQuestions(_ raw: String, limit: Int) -> [StudyQuestion] {
        let cleaned = ConversationPrompts.stripThinkBlocks(raw)
        var result: [StudyQuestion] = []
        for line in cleaned.components(separatedBy: .newlines) {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            trimmed = trimmed.replacingOccurrences(of: #"^\s*(\d+[\.\)])\s*"#, with: "", options: .regularExpression)
            guard !trimmed.isEmpty else { continue }
            if let sep = trimmed.range(of: "|") {
                let q = String(trimmed[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
                let a = String(trimmed[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
                if q.count >= 4 { result.append(StudyQuestion(question: q, answer: a.isEmpty ? nil : a)) }
            } else if trimmed.hasSuffix("?") {
                result.append(StudyQuestion(question: trimmed, answer: nil))
            }
            if result.count >= limit { break }
        }
        return result
    }

    private func stripBullet(_ s: String) -> String {
        var t = s
        for p in ["- ", "• ", "* ", "– "] where t.hasPrefix(p) { t = String(t.dropFirst(p.count)); break }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private func splitArticle(_ word: String) -> (String, String?) {
        for article in ["der ", "die ", "das "] where word.lowercased().hasPrefix(article) {
            return (String(word.dropFirst(article.count)).trimmingCharacters(in: .whitespaces), String(article.dropLast()))
        }
        return (word, nil)
    }
}
