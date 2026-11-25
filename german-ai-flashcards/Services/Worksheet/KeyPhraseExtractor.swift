//
//  KeyPhraseExtractor.swift
//  german-ai-flashcards
//
//  Phrase cards from a lesson's exercises and her answer key (`WorksheetKeyReader`). An exercise
//  item with its blank filled by her answer is often exactly the chunk the lesson teaches:
//
//      "eine Störung ___"  + D (= beheben)          → eine Störung beheben
//      "to resolve faults ___" + Störungen beheben  → Störungen beheben = to resolve faults
//      "Ich habe Kenntnisse in ___." + her example  → Ich habe Kenntnisse in Python.
//
//  Only numbered items, filled with an answer that reads in place: not a blank after a finished
//  sentence or question (a "Muss/Kann" label, an answer to "Wie viele Stunden…?"), not a bare
//  letter, nothing longer than eight words, and no single words (those are the lesson's
//  vocabulary). The learner ticks which to keep; sentences start unticked. Pure.
//

import Foundation
import NaturalLanguage

nonisolated struct KeyPhrase: Identifiable, Hashable, Sendable {
    var german: String
    /// The item's own English when it was the prompt ("to resolve faults"); else the tutor's job.
    var english: String?
    var page: Int
    /// A whole sentence rather than a chunk: offered, but not ticked to start with.
    var isSentence: Bool
    var id: String { CardKind.matchKey(german) }
}

nonisolated enum KeyPhraseExtractor {
    static let maxWords = 8

    static func phrases(from exercises: [WorksheetExercise], key: [String: String],
                        samples: [String: String]) -> [KeyPhrase] {
        var out: [KeyPhrase] = []
        var seen = Set<String>()
        for exercise in exercises where exercise.verdict == .interactive {
            for section in exercise.sections {
                let letters: [String: String]
                if case .letters(let options)? = section.options {
                    letters = Dictionary(options.map { ($0.letter.uppercased(), $0.text) }, uniquingKeysWith: { a, _ in a })
                } else {
                    letters = [:]
                }
                for item in section.items {
                    guard let phrase = phrase(for: item, page: exercise.page, letters: letters,
                                              answers: { key[$0] ?? samples[$0] }),
                          seen.insert(phrase.id).inserted else { continue }
                    out.append(phrase)
                }
            }
        }
        return out
    }

    static func phrase(for item: WorksheetItem, page: Int, letters: [String: String],
                       answers: (String) -> String?) -> KeyPhrase? {
        guard let label = item.label, Int(label) != nil, !item.gaps.isEmpty, item.choices.isEmpty else { return nil }

        var parts: [String] = []
        var printed: [String] = []
        var replacedWhole: String?
        var fromLetter = false
        for segment in item.segments {
            switch segment {
            case .text(let text, _):
                parts.append(text)
                printed.append(text)
            case .gap(let gap):
                guard var value = answers(gap.key)?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
                // A blank after a finished sentence or question is an answer slot, not part of it.
                let before = parts.joined().trimmingCharacters(in: .whitespaces)
                if let last = before.last, ".?!:".contains(last) { return nil }
                if value.count == 1, value.first?.isUppercase == true {
                    guard let text = letters[value] else { return nil }
                    value = text
                    fromLetter = true
                }
                parts.append(value)
                replacedWhole = value
            case .lineBreak:
                parts.append(" ")
                printed.append(" ")
            case .choice:
                return nil
            }
        }
        let prompt = WorksheetText.collapse(printed.joined()).trimmingCharacters(in: .whitespaces)
        guard let answer = replacedWhole else { return nil }
        // A lone capital letter in the printed text is an option the parser glued onto the item
        // ("die Versionsverwaltung F user account"): the line isn't the item's own.
        if words(prompt).contains(where: { $0.count == 1 && $0.first?.isUppercase == true }) { return nil }

        // Matching German to English ("die Fehleranalyse ___" + C = error analysis): a word pair.
        if fromLetter, item.gaps.count == 1, isEnglish(answer), !isEnglish(prompt) {
            return make(german: prompt, english: answer, page: page)
        }
        // "to resolve faults ___" → the answer is the German, the prompt its English.
        if item.gaps.count == 1, !prompt.isEmpty, isEnglish(prompt), !isEnglish(answer) {
            return make(german: answer, english: prompt, page: page)
        }
        // Her answer is the whole line already ("Ich habe Kenntnisse in Python." for
        // "Ich habe Kenntnisse in ___."): take it as it is.
        let promptWords = Set(words(prompt).map { $0.lowercased() })
        if item.gaps.count == 1, words(answer).filter({ promptWords.contains($0.lowercased()) }).count >= 2 {
            return make(german: answer, english: nil, page: page)
        }
        let filled = WorksheetText.collapse(parts.joined()).trimmingCharacters(in: .whitespaces)
        return make(german: filled, english: nil, page: page)
    }

    private static func make(german: String, english: String?, page: Int) -> KeyPhrase? {
        let count = words(german).count
        guard count >= 2, count <= maxWords else { return nil }
        let isSentence = german.last.map { ".!?".contains($0) } == true
        guard isSentence || CardKind.isPhrase(german) else { return nil }
        return KeyPhrase(german: german, english: english, page: page, isSentence: isSentence)
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The item's printed text reads as English: "sound knowledge of Python", "to deploy software".
    static func isEnglish(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .german]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        return (hypotheses[.english] ?? 0) > 0.6
    }
}
