//
//  ClassEntry.swift
//  german-ai-flashcards
//
//  One class session as the learner logged it: the date, what grammar and topics were covered,
//  the new words, free notes, the homework, and any handouts brought over. The page of a
//  notebook, dated, filed under its course. The tutors will read `tutorContext` later; this pass
//  only records it.
//
//  Every property is defaulted or set in `init` so the entity is an additive migration (the app's
//  container deletes the store when a migration fails).
//

import Foundation
import SwiftData

@Model
final class ClassEntry {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    /// The day of the class, normalized to the start of the day so "today's entry" is an equality
    /// and week grouping is stable.
    var date: Date
    /// "Kapitel 4 · Wechselpräpositionen". Optional; `displayTitle` falls back to the week or date.
    var title: String = ""
    var notes: String = ""
    /// Raw `GrammarFocus` values the class covered.
    var grammarFocusRaws: [String] = []
    /// Free-text themes ("Wohnen", "Im Restaurant").
    var topics: [String] = []
    /// Encoded `[ClassWord]`.
    var wordsData: Data? = nil
    var homework: String = ""
    var homeworkDue: Date? = nil
    var homeworkDone: Bool = false

    var course: ClassCourse? = nil

    @Relationship(deleteRule: .cascade, inverse: \ClassMaterial.entry)
    var materials: [ClassMaterial] = []

    init(date: Date, title: String = "", createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.date = Calendar.current.startOfDay(for: date)
        self.title = title
    }

    // MARK: Derived

    var grammarFoci: [GrammarFocus] {
        get { grammarFocusRaws.compactMap { GrammarFocus(rawValue: $0) } }
        set { grammarFocusRaws = newValue.map(\.rawValue) }
    }

    var words: [ClassWord] {
        guard let wordsData else { return [] }
        return (try? JSONDecoder().decode([ClassWord].self, from: wordsData)) ?? []
    }

    func setWords(_ words: [ClassWord]) {
        wordsData = words.isEmpty ? nil : try? JSONEncoder().encode(words)
        updatedAt = .now
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The title, else "Woche N" in a dated course, else the date.
    var displayTitle: String {
        if !trimmedTitle.isEmpty { return trimmedTitle }
        if let week = course?.weekNumber(for: date) { return "Woche \(week)" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// "Mo., 21. Sept." in the device's locale.
    var dateLine: String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var hasHomework: Bool { !homework.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasOpenHomework: Bool { hasHomework && !homeworkDone }
    var homeworkIsOverdue: Bool {
        guard hasOpenHomework, let homeworkDue else { return false }
        return homeworkDue < Calendar.current.startOfDay(for: .now)
    }

    /// Short chips for a list row: the first grammar point (+ how many more), words, handouts.
    var summaryParts: [String] {
        var parts: [String] = []
        let foci = grammarFoci
        if let first = foci.first {
            parts.append(foci.count > 1 ? "\(first.germanLabel) +\(foci.count - 1)" : first.germanLabel)
        }
        if !topics.isEmpty { parts.append(topics.count == 1 ? topics[0] : "\(topics.count) topics") }
        let wordCount = words.count
        if wordCount > 0 { parts.append("\(wordCount) word\(wordCount == 1 ? "" : "s")") }
        if !materials.isEmpty { parts.append("\(materials.count) handout\(materials.count == 1 ? "" : "s")") }
        if hasOpenHomework { parts.append("Hausaufgabe") }
        return parts
    }

    var summaryLine: String { summaryParts.joined(separator: " · ") }

    /// Nothing worth saving yet: the editor's Save stays off.
    var isEmpty: Bool {
        trimmedTitle.isEmpty
            && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasHomework
            && grammarFocusRaws.isEmpty && topics.isEmpty && words.isEmpty
    }

    /// The entry rendered for a tutor prompt: what the class covered, in the labels the tutors
    /// already use, capped so a fortnight of entries fits a context window. Not injected anywhere
    /// yet; the follow-on that feeds class notes to the conversation will read this.
    var tutorContext: String {
        var lines: [String] = []
        var header = "Unterricht am \(date.formatted(date: .long, time: .omitted))"
        if let course { header += " (\(course.name))" }
        if !trimmedTitle.isEmpty { header += ": \(trimmedTitle)" }
        lines.append(header)
        let foci = grammarFoci
        if !foci.isEmpty {
            lines.append("Grammatik: " + foci.map(\.germanLabel).joined(separator: ", "))
        }
        if !topics.isEmpty {
            lines.append("Themen: " + topics.joined(separator: ", "))
        }
        let words = words
        if !words.isEmpty {
            lines.append("Neue Wörter: " + words.prefix(30).map {
                $0.english.isEmpty ? $0.german : "\($0.german) (\($0.english))"
            }.joined(separator: ", "))
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            lines.append("Notizen: " + String(trimmedNotes.prefix(600)))
        }
        if hasOpenHomework {
            lines.append("Hausaufgabe: " + String(homework.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))
        }
        return String(lines.joined(separator: "\n").prefix(2000))
    }
}

// MARK: - Words

/// A word the class introduced, as the learner wrote it down. `english` may be empty when the
/// learner only caught the German; those wait for a translation before they become cards.
nonisolated struct ClassWord: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var german: String
    var english: String = ""
    /// Saved into the course's deck already (the row shows a check).
    var addedToDeck: Bool = false

    var trimmedGerman: String { german.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedEnglish: String { english.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Both halves present, so it can be a card.
    var isComplete: Bool { !trimmedGerman.isEmpty && !trimmedEnglish.isEmpty }
    /// How words are matched against each other and the deck: article stripped, lowercased.
    var key: String { ClassWord.key(trimmedGerman) }

    static func key(_ german: String) -> String {
        var word = german.trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["der ", "die ", "das "] where word.lowercased().hasPrefix(article) {
            word = String(word.dropFirst(article.count)).trimmingCharacters(in: .whitespaces)
        }
        return word.lowercased()
    }

    /// Parse a pasted vocabulary list, one word per line: `der Tisch – table`, `gehen = to go`,
    /// `Buch: book`, `Haus<tab>house`, or a bare German word. Leading bullets and numbers are
    /// dropped; duplicates (by `key`) keep their first line.
    static func parseList(_ raw: String) -> [ClassWord] {
        let separators = ["\t", " – ", " — ", " = ", "=", " - ", ": "]
        var out: [ClassWord] = []
        var seen = Set<String>()
        for line in raw.components(separatedBy: .newlines) {
            let cleaned = line
                .replacingOccurrences(of: #"^\s*(?:[-•*·]|\d+[.)])\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { continue }
            var german = cleaned
            var english = ""
            for separator in separators {
                if let range = cleaned.range(of: separator) {
                    german = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    english = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            let word = ClassWord(german: german, english: english)
            guard word.trimmedGerman.count >= 2, !seen.contains(word.key) else { continue }
            seen.insert(word.key)
            out.append(word)
        }
        return out
    }
}
