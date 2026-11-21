//
//  ResumePrompts.swift
//  german-ai-flashcards
//
//  The résumé's prompts, parsers and budget (roadmap item 18). Pure, so the fact matching and the
//  splitter are testable and the probe can reuse them.
//

import Foundation

nonisolated enum ResumePrompts {

    /// The Kurzprofil's share of the tutor's reading window: a fixed slice, the posting gets the rest.
    static func kurzprofilSlice(saver: Bool) -> Int { saver ? 300 : 500 }

    // MARK: - Kurzprofil

    static let kurzprofilSystem = """
    Du fasst einen Lebenslauf für ein Bewerbungsgespräch auf Deutsch zusammen. Schreibe ein \
    Kurzprofil von höchstens 500 Zeichen, sachlich, in der Ich-Form: aktuelle Rolle, wie viele \
    Jahre Erfahrung, die wichtigsten Kenntnisse, zwei konkrete Erfolge, Ausbildung, Sprachen. \
    Nur was im Lebenslauf steht, nichts erfinden. Antworte nur mit dem Kurzprofil.
    """

    static func kurzprofilUser(_ resume: String) -> String { "Lebenslauf:\n\n\(resume.prefix(8_000))" }

    static func cleanKurzprofil(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(600))
    }

    // MARK: - Facts

    static let factsSystem = """
    Zerlege einen Lebenslauf in kurze, einzelne Fakten auf Deutsch: eine Station, ein Projekt, ein \
    Abschluss, eine Kenntnis pro Zeile, jeweils höchstens 15 Wörter, mit Jahreszahlen wenn vorhanden. \
    Nur was im Lebenslauf steht. Antworte mit einer Zeile pro Fakt, beginnend mit „- “.
    """

    static func parseFacts(_ raw: String) -> [String] {
        let text = raw.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        var seen = Set<String>()
        return text.components(separatedBy: .newlines).compactMap { line in
            var s = line.trimmingCharacters(in: .whitespaces)
            if let r = s.range(of: #"^(\d+[.)]|[-•*–])\s*"#, options: .regularExpression) { s.removeSubrange(r) }
            let words = s.split(whereSeparator: { $0.isWhitespace }).count
            guard (2...20).contains(words), seen.insert(s.lowercased()).inserted else { return nil }
            return s
        }
        .prefix(25).map { $0 }
    }

    /// Without a tutor: lines that look like CV entries (a year, or a bullet), shortened.
    static func heuristicFacts(_ resume: String) -> [String] {
        var seen = Set<String>()
        return resume.components(separatedBy: .newlines).compactMap { line in
            var s = line.trimmingCharacters(in: .whitespaces)
            let bullet = s.range(of: #"^[-•*–]\s*"#, options: .regularExpression)
            let hasYear = s.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil
            guard bullet != nil || hasYear else { return nil }
            if let bullet { s.removeSubrange(bullet) }
            let words = s.split(whereSeparator: { $0.isWhitespace })
            guard words.count >= 3 else { return nil }
            let short = words.prefix(18).joined(separator: " ")
            return seen.insert(short.lowercased()).inserted ? short : nil
        }
        .prefix(25).map { $0 }
    }

    // MARK: - One fact per turn

    private static let stopwords: Set<String> = [
        "und", "oder", "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer",
        "mit", "von", "für", "in", "im", "am", "an", "auf", "zu", "zur", "zum", "bei", "als", "wie",
        "sie", "ihre", "ihr", "ich", "wir", "sehr", "gute", "guter", "gutes", "kenntnisse", "erfahrung",
        "and", "the", "with", "for", "of", "in", "a", "an", "to", "your", "you", "experience", "skills",
    ]

    static func keywords(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "+" && $0 != "#" })
            .map(String.init)
            .filter { $0.count >= 3 && !stopwords.contains($0) })
    }

    /// The fact that shares the most content words with a plan point (a stem of five letters
    /// counts, so "Projektleitung" meets "Projekte"); nil when nothing overlaps.
    static func bestFact(for point: String, facts: [String]) -> String? {
        let wanted = keywords(point)
        guard !wanted.isEmpty else { return nil }
        func score(_ fact: String) -> Int {
            let have = keywords(fact)
            return wanted.reduce(0) { sum, w in
                sum + (have.contains(w) || have.contains { $0.hasPrefix(String(w.prefix(5))) && w.count >= 5 } ? 1 : 0)
            }
        }
        let best = facts.map { ($0, score($0)) }.max { $0.1 < $1.1 }
        return (best?.1 ?? 0) > 0 ? best?.0 : nil
    }

    /// A posting-less interview: "tell me about yourself", from the Kurzprofil alone.
    static let generalPlan = [
        "Ihr beruflicher Werdegang",
        "Ihre größten Stärken",
        "eine Lücke oder ein Wechsel im Lebenslauf",
        "Ihre Ziele für die nächsten Jahre",
    ]

    // MARK: - Career words

    static let wordsSystem = """
    Wähle 8–12 Fachwörter und Ausdrücke aus dem Lebenslauf, die man im Vorstellungsgespräch über den \
    eigenen Beruf braucht, mit natürlicher englischer Übersetzung. Bei Nomen mit Artikel. \
    Eine Zeile pro Eintrag, GENAU im Format: deutsch = english
    """
}
