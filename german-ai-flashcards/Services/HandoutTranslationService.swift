//
//  HandoutTranslationService.swift
//  german-ai-flashcards
//
//  Translates a handout sentence by sentence, keeping the sentences aligned so the reader can
//  show German and English side by side. Each paragraph goes to the tutor as numbered sentences
//  and comes back as numbered lines; when the numbering doesn't survive, the paragraph is
//  translated as a block and its sentences are spread over the German ones. Progress is saved
//  after every paragraph, so a cancelled run resumes where it stopped.
//

import Foundation
import SwiftData
import NaturalLanguage

@Observable
@MainActor
final class HandoutTranslationService {
    enum Phase: Equatable {
        case idle
        case loadingModel
        case translating
        case done
        case cancelled
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var statusText: String = ""
    private var cancelRequested = false

    var isRunning: Bool {
        switch phase {
        case .loadingModel, .translating: true
        default: false
        }
    }

    private let mlxService: MLXGenerationService
    private let modelContext: ModelContext

    init(mlxService: MLXGenerationService, modelContext: ModelContext) {
        self.mlxService = mlxService
        self.modelContext = modelContext
    }

    func cancel() { cancelRequested = true }

    /// Fill in every untranslated sentence of the material's translation (built from its text if
    /// there is none yet), saving after each paragraph.
    func translate(_ material: ClassMaterial, model: MLXModel) async {
        cancelRequested = false
        var translation = material.translation ?? HandoutTranslation.skeleton(for: material.text)
        guard translation.sentenceCount > 0 else {
            phase = .failed("No sentences found in this text.")
            return
        }
        if !mlxService.isModelLoaded || mlxService.currentModel != model {
            phase = .loadingModel
            statusText = "Loading \(model.rawValue)…"
            progress = 0
            await mlxService.loadModel(model)
        }
        guard mlxService.isModelLoaded, mlxService.currentModel == model else {
            phase = .failed(mlxService.loadError ?? "Couldn't load \(model.rawValue).")
            return
        }

        phase = .translating
        let total = translation.sentenceCount
        for index in translation.paragraphs.indices where !translation.paragraphs[index].isComplete {
            if cancelRequested { break }
            let done = translation.translatedCount
            progress = Double(done) / Double(total)
            statusText = "Sentence \(done + 1) of \(total)…"
            let german = translation.paragraphs[index].german
            let english = await translateParagraph(german, model: model)
            translation.paragraphs[index].english = english
            material.setTranslation(translation)
            material.translationModelRaw = model.rawValue
            try? modelContext.save()
        }
        progress = Double(translation.translatedCount) / Double(total)
        if cancelRequested {
            phase = .cancelled
            statusText = "Stopped. \(translation.translatedCount) of \(total) sentences done."
        } else if translation.isComplete {
            phase = .done
            statusText = "Fertig!"
        } else {
            phase = .failed("Some sentences didn't come back translated. Try again to fill them in.")
        }
    }

    // MARK: - One paragraph

    private static let system = "You are a professional German-to-English translator. You only translate: you never continue, answer, or comment on the text."

    /// Numbered sentences in batches; a batch whose numbering doesn't come back intact is
    /// translated as a block and spread over its sentences.
    private func translateParagraph(_ sentences: [String], model: MLXModel) async -> [String] {
        var out: [String] = []
        let batchSize = 8
        for start in stride(from: 0, to: sentences.count, by: batchSize) {
            if cancelRequested { break }
            let batch = Array(sentences[start ..< min(start + batchSize, sentences.count)])
            if let numbered = await translateNumbered(batch, model: model) {
                out.append(contentsOf: numbered)
            } else {
                out.append(contentsOf: await translateBlock(batch, model: model))
            }
        }
        // A cancelled paragraph keeps what it got and leaves the rest empty.
        while out.count < sentences.count { out.append("") }
        return out
    }

    private func translateNumbered(_ batch: [String], model: MLXModel) async -> [String]? {
        let user = """
        Translate each numbered German sentence into natural English. Reply with exactly \(batch.count) lines, \
        each starting with its number and a period, in the same order. Output nothing else.

        \(batch.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        """
        guard let raw = try? await mlxService.generateText(
            system: Self.system, user: user, model: model, maxTokens: 40 + batch.count * 48
        ) else { return nil }
        let cleaned = ConversationPrompts.stripThinkBlocks(raw)
        var byNumber: [Int: String] = [:]
        for line in cleaned.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let match = trimmed.range(of: #"^(\d+)[.)]\s*"#, options: .regularExpression),
                  let number = Int(trimmed[match].trimmingCharacters(in: CharacterSet(charactersIn: ".) "))) else { continue }
            let text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty, byNumber[number] == nil { byNumber[number] = text }
        }
        let ordered = (1...batch.count).compactMap { byNumber[$0] }
        guard ordered.count == batch.count else { return nil }
        return ordered
    }

    private func translateBlock(_ batch: [String], model: MLXModel) async -> [String] {
        let user = """
        Translate the following German text into natural English, sentence for sentence. Output ONLY the English.

        \(batch.joined(separator: " "))
        """
        guard let raw = try? await mlxService.generateText(
            system: Self.system, user: user, model: model, maxTokens: 40 + batch.count * 48
        ) else { return Array(repeating: "", count: batch.count) }
        let cleaned = ConversationPrompts.stripThinkBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return Array(repeating: "", count: batch.count) }
        let sentences = HandoutTranslation.splitSentences(cleaned, language: .english)
        return HandoutTranslation.align(sentences, toCount: batch.count)
    }
}
