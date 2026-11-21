//
//  GistPrompts.swift
//  german-ai-flashcards
//
//  Worum geht's? (docs/HOEREN.md): the story's key points, written with the story, and the judge
//  that could one day say whether a learner's summary caught each one. DLI's objective is
//  "produce an English summary" of what was heard, so the points and the summary are in English.
//
//  Pure, with no app types beyond Foundation and `WritingSentences`, so the Mac probe
//  (`training/hoeren_cli`) compiles this exact file and scores tutors with the app's own parser.
//
//  The judge is DEBUG-only until the probe's numbers have been read (measure before gating). What
//  ships is the learner ticking each point themselves.
//

import Foundation

nonisolated enum GistVerdict: String, Codable, Hashable, Sendable, CaseIterable {
    case ja, teilweise, nein

    /// Halves of a point: ja 2, teilweise 1, nein 0. Self-ticks store the same numbers.
    var halves: Int {
        switch self {
        case .ja: 2
        case .teilweise: 1
        case .nein: 0
        }
    }

    var label: String {
        switch self {
        case .ja: "Ja"
        case .teilweise: "Teilweise"
        case .nein: "Nein"
        }
    }
}

nonisolated enum GistPrompts {

    // MARK: - Key points

    static let keyPointsSystem = """
    You summarise a short German text for a language learner who will listen to it. \
    Write 3 or 4 key points IN ENGLISH, each one short sentence of at most 15 words: who, what \
    happened, and how it ended. Only facts that are in the text. Answer exactly in this format:
    KERNPUNKTE:
    - <point>
    - <point>
    """

    static func keyPointsUser(title: String, text: String) -> String {
        "Title: \(title)\n\nText:\n\(text)"
    }

    /// The points, or [] when the answer fails the gate: 2–5 points of 3–20 words each, in English,
    /// no duplicates. The first four are kept.
    static func parseKeyPoints(_ raw: String) -> [String] {
        let lines = stripThinking(raw).components(separatedBy: .newlines)
        var inPoints = false
        var points: [String] = []
        var seen = Set<String>()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.uppercased().hasPrefix("KERNPUNKTE") || trimmed.uppercased().hasPrefix("KEY POINTS") {
                inPoints = true
                continue
            }
            let isBullet = trimmed.first.map { "-•*–".contains($0) } == true
                || trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil
            guard inPoints || isBullet else { continue }
            let point = stripBullet(trimmed)
            let words = point.split(whereSeparator: { $0.isWhitespace }).count
            guard (3...20).contains(words),
                  WritingSentences.guessLanguage(point) != .german,
                  seen.insert(point.lowercased()).inserted else { continue }
            points.append(point)
        }
        guard (2...5).contains(points.count) else { return [] }
        return Array(points.prefix(4))
    }

    // MARK: - Judge (DEBUG and the Mac probe only)

    static let judgeSystem = """
    You check a language learner's English summary of a German text against its key points. \
    For each numbered key point, decide whether the summary contains it. Answer ja if it does, \
    teilweise if only part of it, nein if it is missing or the summary gets it wrong. Meaning \
    counts, not wording; a summary in German counts too. Write one line per point: the number, \
    a colon, ONE of the three words, a semicolon, and a reason of at most 12 words. For example:
    1: ja ; says the train was late
    2: nein ; the tree is not mentioned
    3: teilweise ; names the fire brigade but not the time
    """

    static func judgeUser(summary: String, points: [String]) -> String {
        let numbered = points.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "Key points:\n\(numbered)\n\nLearner's summary:\n\(summary)"
    }

    /// A summary too short to judge: nothing is asked of the model, every point stays unsure.
    static func isJudgeable(_ summary: String) -> Bool {
        summary.split(whereSeparator: { $0.isWhitespace }).count >= 4
    }

    /// One verdict per point, nil where the line is missing or unreadable (shown as unsure).
    static func parseJudge(_ raw: String, count: Int) -> [GistVerdict?] {
        var out = [GistVerdict?](repeating: nil, count: count)
        for line in stripThinking(raw).components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":"),
                  let n = Int(trimmed[..<colon].filter(\.isNumber)), (1...count).contains(n) else { continue }
            let rest = trimmed[trimmed.index(after: colon)...].lowercased()
            let label = rest.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            // A model that echoes the format ("ja | teilweise | nein") has not answered.
            guard !label.contains("|"), !label.contains("/") else { continue }
            // "teilweise" first: it contains no "ja", but "nein" and "ja" must not match inside it.
            let verdict: GistVerdict? =
                label.hasPrefix("teilweise") || label.hasPrefix("partly") ? .teilweise
                : label.hasPrefix("nein") || label.hasPrefix("no") ? .nein
                : label.hasPrefix("ja") || label.hasPrefix("yes") ? .ja
                : nil
            if out[n - 1] == nil { out[n - 1] = verdict }
        }
        return out
    }

    /// The app's score, never the model's: ja + ½ teilweise, in halves.
    static func scoreHalves(_ verdicts: [GistVerdict?]) -> Int {
        verdicts.compactMap { $0?.halves }.reduce(0, +)
    }

    // MARK: - Helpers

    static func stripThinking(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
    }

    static func stripBullet(_ line: String) -> String {
        var s = line
        if let r = s.range(of: #"^(\d+[.)]|[-•*–])\s*"#, options: .regularExpression) { s.removeSubrange(r) }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
