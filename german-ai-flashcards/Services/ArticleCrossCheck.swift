import Foundation
import Observation

/// Asks a local model about every unresolved noun at once.
///
/// The previous per-word cross-check loaded an entire model into memory for a single article,
/// then did it again for the next word. This sends one prompt covering all of them and prefers
/// the model that is already resident, so the common case costs no load at all.
@Observable
final class ArticleCrossCheck {
    /// Lowercased German word → the article the model gave.
    private(set) var answers: [String: String] = [:]
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    /// One prompt gets unreliable past roughly this many words, so long lists are chunked.
    private let batchSize = 12

    // MARK: - Model selection

    /// Prefer whatever is already loaded; otherwise the first downloaded model.
    func model(service: MLXGenerationService) -> MLXModel? {
        if service.isModelLoaded, let current = service.currentModel { return current }
        return MLXModel.allCases.first { $0.isDownloaded }
    }

    func isSupported(service: MLXGenerationService) -> Bool {
        model(service: service) != nil
    }

    func modelName(service: MLXGenerationService) -> String {
        model(service: service)?.displayName ?? "model"
    }

    // MARK: - Run

    func run(words: [(german: String, english: String)], service: MLXGenerationService) async {
        guard !words.isEmpty, let model = model(service: service) else { return }

        isRunning = true
        errorMessage = nil
        defer { isRunning = false }

        if !service.isModelLoaded || service.currentModel != model {
            await service.loadModel(model)
            guard service.isModelLoaded else {
                errorMessage = service.loadError ?? "Couldn't load \(model.displayName)."
                return
            }
        }

        for chunk in stride(from: 0, to: words.count, by: batchSize).map({
            Array(words[$0..<min($0 + batchSize, words.count)])
        }) {
            do {
                let listing = chunk.enumerated()
                    .map { "\($0.offset + 1). \($0.element.german) (\($0.element.english))" }
                    .joined(separator: "\n")

                let raw = try await service.generateText(
                    system: """
                        You are a German grammar expert. For each numbered noun, give its correct \
                        definite article. Reply with one line per noun in the form "number. article", \
                        using only der, die or das. No explanations.
                        """,
                    user: "Give the article for each noun:\n\(listing)",
                    model: model,
                    // Roughly 6 tokens a line, plus headroom for a stray preamble.
                    maxTokens: chunk.count * 8 + 16
                )

                merge(parse(raw, into: chunk), from: chunk)
            } catch {
                errorMessage = "The model couldn't be reached: \(error.localizedDescription)"
                return
            }
        }

        if answers.isEmpty {
            errorMessage = "\(model.displayName) didn't give a usable answer."
        }
    }

    // MARK: - Parsing

    /// Maps the model's reply back onto the words asked about. Accepts both "3. die" and
    /// "Handschuh: der", since small models drift between the two no matter how you prompt.
    private func parse(_ raw: String, into chunk: [(german: String, english: String)]) -> [Int: String] {
        var found: [Int: String] = [:]

        for line in raw.split(whereSeparator: \.isNewline) {
            let lower = line.lowercased()
            guard let article = ArticleStyle.all.first(where: { article in
                lower.range(of: "\\b\(article)\\b", options: .regularExpression) != nil
            }) else { continue }

            // Leading number wins, since it's unambiguous.
            if let numberText = lower.prefix(while: { $0.isNumber }).nilIfEmpty,
               let number = Int(numberText),
               (1...chunk.count).contains(number) {
                found[number - 1] = article
                continue
            }

            // Otherwise match on the word itself.
            if let index = chunk.firstIndex(where: { lower.contains($0.german.lowercased()) }) {
                found[index] = article
            }
        }

        return found
    }

    private func merge(_ found: [Int: String], from chunk: [(german: String, english: String)]) {
        for (index, article) in found where chunk.indices.contains(index) {
            answers[chunk[index].german.lowercased()] = article
        }
    }
}

private extension Substring {
    var nilIfEmpty: String? { isEmpty ? nil : String(self) }
}
