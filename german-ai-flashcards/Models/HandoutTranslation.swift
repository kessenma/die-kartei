//
//  HandoutTranslation.swift
//  german-ai-flashcards
//
//  A handout's English, sentence by sentence, so the two languages can be shown side by side and
//  scrolled together: paragraph N sentence M in German is paragraph N sentence M in English.
//  Stored on the `ClassMaterial` as JSON; built by `HandoutTranslationService`.
//

import Foundation
import NaturalLanguage

nonisolated struct HandoutTranslation: Codable, Equatable {
    struct Paragraph: Codable, Equatable, Identifiable {
        var id: Int
        var german: [String]
        /// Parallel to `german`; an empty string is a sentence not translated yet.
        var english: [String]

        var isComplete: Bool { english.count == german.count && !english.contains { $0.isEmpty } }
    }

    var paragraphs: [Paragraph]

    var sentenceCount: Int { paragraphs.reduce(0) { $0 + $1.german.count } }
    var translatedCount: Int { paragraphs.reduce(0) { $0 + $1.english.filter { !$0.isEmpty }.count } }
    var isComplete: Bool { !paragraphs.isEmpty && paragraphs.allSatisfy(\.isComplete) }

    /// The German text as untranslated paragraphs of sentences, ready to fill in.
    static func skeleton(for text: String) -> HandoutTranslation {
        let paragraphs = splitParagraphs(text).enumerated().map { index, sentences in
            Paragraph(id: index, german: sentences, english: Array(repeating: "", count: sentences.count))
        }
        return HandoutTranslation(paragraphs: paragraphs)
    }

    // MARK: - Splitting

    /// Paragraphs (blank-line separated, `[Seite N]` markers dropped) as sentences.
    static func splitParagraphs(_ text: String) -> [[String]] {
        let cleaned = text.replacingOccurrences(of: #"\n?\[Seite \d+\]\n?"#, with: "\n\n", options: .regularExpression)
        var paragraphs: [[String]] = []
        for block in cleaned.components(separatedBy: "\n\n") {
            // A PDF wraps lines mid-sentence; a line break inside a paragraph is a space.
            let joined = block.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !joined.isEmpty else { continue }
            let sentences = splitSentences(joined, language: .german)
            if !sentences.isEmpty { paragraphs.append(sentences) }
        }
        return paragraphs
    }

    static func splitSentences(_ text: String, language: NLLanguage) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(language)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { out.append(sentence) }
            return true
        }
        return out
    }

    /// Spread `english` sentences over `count` German ones when the two counts differ: the
    /// translation of a paragraph as a block rarely lands on the same sentence boundaries. Extra
    /// English sentences are joined onto their neighbour; missing ones leave a gap that the next
    /// sentence's text fills proportionally.
    static func align(_ english: [String], toCount count: Int) -> [String] {
        guard count > 0 else { return [] }
        guard !english.isEmpty else { return Array(repeating: "", count: count) }
        if english.count == count { return english }
        var out = Array(repeating: "", count: count)
        for (index, sentence) in english.enumerated() {
            let slot = min(count - 1, Int((Double(index) / Double(english.count)) * Double(count)))
            out[slot] = out[slot].isEmpty ? sentence : out[slot] + " " + sentence
        }
        // A German sentence with nothing: borrow the previous one's text rather than show a hole.
        for index in out.indices where out[index].isEmpty {
            if index > 0 { out[index] = out[index - 1] }
        }
        return out
    }
}
