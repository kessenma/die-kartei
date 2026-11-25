//
//  LessonWordExtractor.swift
//  german-ai-flashcards
//
//  The nouns a lesson PDF teaches, for the course's flashcard deck. Two places a teacher puts
//  them: the "Nomen: der Salat, die Suppe, …" line under an exercise, and a vocabulary slide
//  whose lines are mostly article + noun ("der Regen der Wind der Schnee"), sometimes with the
//  English in brackets ("das Brot (bread)"). A line that only mentions a noun in passing
//  ("Zusätzlich für die Sätze: der Tisch …") is not a vocabulary line, and her inline notes
//  ("Das Café == Location", capital D) are skipped.
//
//  A plural listed beside its singular ("die Salate" with "der Salat") is dropped; the card is
//  the singular. Pure, so the tests feed it parsed pages; the screen adds the dictionary's English
//  and its opinion of the article (`WorksheetWordsSheet`).
//

import Foundation

nonisolated struct LessonWord: Hashable, Sendable, Identifiable {
    /// "der Salat"
    var german: String
    var article: String
    var noun: String
    /// The teacher's own English, when the slide gives it.
    var english: String?
    /// Every page it appears on.
    var pages: [Int]

    var id: String { german }
}

nonisolated enum LessonWordExtractor {

    /// Share of a line's words that must be article + noun pairs for it to count as vocabulary.
    /// A real vocabulary line is all pairs; her "Zusätzlich für die Sätze: der Tisch, die Küche
    /// und der Geschmack." is 0.73 and is a sentence.
    static let vocabularyShare = 0.8

    static func words(from pages: [WorksheetExercise]) -> [LessonWord] {
        var found: [LessonWord] = []
        func add(_ word: LessonWord) {
            if let index = found.firstIndex(where: { $0.german == word.german }) {
                found[index].pages = Array(Set(found[index].pages + word.pages)).sorted()
                if found[index].english == nil { found[index].english = word.english }
            } else {
                found.append(word)
            }
        }
        for page in pages {
            for entry in page.nouns {
                if let word = pair(entry, page: page.page) { add(word) }
            }
            guard !page.isExercise else { continue }
            for line in page.notes {
                for word in vocabulary(in: line, page: page.page) { add(word) }
            }
        }
        return dropPlurals(found)
    }

    /// "das Brot" → the word. Nil for anything that isn't article + capitalized noun.
    static func pair(_ text: String, page: Int) -> LessonWord? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, ["der", "die", "das"].contains(parts[0]),
              let first = parts[1].first, first.isUppercase,
              parts[1].allSatisfy({ $0.isLetter || $0 == "-" }) else { return nil }
        return LessonWord(german: "\(parts[0]) \(parts[1])", article: parts[0], noun: parts[1], english: nil, pages: [page])
    }

    /// The article + noun pairs of a line that is mostly pairs, each with its "(English)" if one
    /// follows it.
    static func vocabulary(in line: String, page: Int) -> [LessonWord] {
        let pattern = #"(?<![\p{L}])(der|die|das)\s+(\p{Lu}[\p{L}-]+)(?:\s*\(([^()]{1,30})\))?"#
        let matches = WorksheetText.matches(pattern, in: line)
        guard matches.count >= 2 else { return [] }
        let ns = line as NSString
        // Words outside the brackets, against the words the pairs account for.
        let unbracketed = line.replacingOccurrences(of: #"\([^()]*\)"#, with: " ", options: .regularExpression)
        let total = WorksheetText.words(in: unbracketed, base: 0).filter { $0.text.contains(where: \.isLetter) }.count
        guard total > 0, Double(matches.count * 2) / Double(total) >= vocabularyShare else { return [] }
        return matches.map { match in
            let article = ns.substring(with: match.range(at: 1))
            let noun = ns.substring(with: match.range(at: 2))
            let glossRange = match.range(at: 3)
            let english = glossRange.location == NSNotFound ? nil
                : ns.substring(with: glossRange).trimmingCharacters(in: .whitespaces)
            return LessonWord(german: "\(article) \(noun)", article: article, noun: noun, english: english, pages: [page])
        }
    }

    /// "die Salate" goes when "der Salat" is there, "die Wolken" when "die Wolke" is: a plural is
    /// its singular plus a short ending, and always takes "die".
    static func dropPlurals(_ words: [LessonWord]) -> [LessonWord] {
        words.filter { word in
            guard word.article == "die" else { return true }
            return !words.contains { other in
                other.noun.count < word.noun.count && word.noun.hasPrefix(other.noun)
                    && word.noun.count - other.noun.count <= 2
            }
        }
    }
}
