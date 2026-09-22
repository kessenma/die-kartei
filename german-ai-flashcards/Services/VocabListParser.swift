//
//  VocabListParser.swift
//  german-ai-flashcards
//
//  Reads a teacher's vocabulary sheet (a two-column German | English table, as PDFKit or the
//  photo scanner hands it over: one row per line, the two columns separated by nothing but a
//  space) into German/English pairs. A row that wraps onto a second line is stitched back
//  together; a ✓ in the sheet's "study for the quiz" column is kept as a mark. Where the columns
//  have no separator the split is found by cues (an article on the left, "to …" on the right, an
//  umlaut, "(pl)") plus Apple's on-device language recognizer, and rows where that was a guess are
//  flagged so the learner checks them.
//
//  Pure Foundation + NaturalLanguage, so it can be exercised on a Mac against a real PDF.
//

import Foundation
import NaturalLanguage

/// One German | English row read out of a vocabulary sheet.
nonisolated struct VocabListRow: Identifiable, Hashable {
    var id = UUID()
    var german: String
    var english: String
    /// The sheet marked the row (✓, ✔, ☑, ★).
    var marked: Bool = false
    /// The split between the two columns came from a separator or a strong cue, not a guess.
    var confident: Bool = true

    var isComplete: Bool {
        !german.trimmingCharacters(in: .whitespaces).isEmpty && !english.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

nonisolated enum VocabListParser {
    struct Result {
        var rows: [VocabListRow]
        /// A title the sheet named itself with ("Vokabelliste für „Hänsel und Gretel“"), if any.
        var title: String?
        var hasMarks: Bool { rows.contains(where: \.marked) }
        var guessedCount: Int { rows.filter { !$0.confident }.count }
        /// How many lines of the source were read as rows, 0…1. A vocabulary sheet scores high;
        /// running prose (a story, a worksheet of questions) scores low and should be picked from
        /// as text instead.
        var listConfidence: Double
        var looksLikeList: Bool { rows.count >= 3 && listConfidence >= 0.5 }
    }

    private static let markCharacters = CharacterSet(charactersIn: "✓✔☑✅★")
    private static let explicitSeparators = ["\t", " – ", " — ", " = ", "=", " - "]
    /// The English column often opens with one of these.
    private static let englishOpeners = ["to ", "the ", "a ", "an ", "old expression", "here:", "lit.", "literally", "in the ", "on the ", "at the ", "someone", "something", "sth", "sb"]
    private static let germanArticles: Set<String> = ["der", "die", "das", "ein", "eine", "einen", "einem", "einer", "sich", "den", "dem"]

    static func parse(_ text: String) -> Result {
        var rows: [VocabListRow] = []
        var title: String?
        var contentLines = 0
        var pairedLines = 0
        /// A German-only line waiting for the line that carries its English.
        var pendingGerman: String?
        var pendingMarked = false

        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.replacingOccurrences(of: #"^\[Seite \d+\]$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if title == nil, let found = titleLine(line) {
                title = found
                continue
            }
            if isHeader(line) { continue }
            contentLines += 1

            let marked = line.unicodeScalars.contains { markCharacters.contains($0) }
            line = String(String.UnicodeScalarView(line.unicodeScalars.filter { !markCharacters.contains($0) }))
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                // A mark on a line of its own belongs to the row above.
                if marked, !rows.isEmpty { rows[rows.count - 1].marked = true }
                continue
            }

            let split = splitColumns(line)
            switch split.kind {
            case .mixed:
                // Table rows are short; a sentence that happens to split is not a row.
                if split.german.split(separator: " ").count <= 8 { pairedLines += 1 }
                let german = [pendingGerman, split.german].compactMap { $0 }.joined(separator: " ")
                rows.append(VocabListRow(german: german, english: split.english, marked: marked || pendingMarked, confident: split.confident))
                pendingGerman = nil
                pendingMarked = false
            case .germanOnly:
                if marked {
                    // A marked row with no English: complete as far as the sheet goes.
                    let german = [pendingGerman, line].compactMap { $0 }.joined(separator: " ")
                    rows.append(VocabListRow(german: german, english: "", marked: true, confident: false))
                    pendingGerman = nil
                    pendingMarked = false
                } else {
                    pendingGerman = [pendingGerman, line].compactMap { $0 }.joined(separator: " ")
                }
            case .englishOnly:
                if let german = pendingGerman {
                    rows.append(VocabListRow(german: german, english: line, marked: marked || pendingMarked, confident: false))
                    pendingGerman = nil
                    pendingMarked = false
                } else if !rows.isEmpty {
                    // The English column wrapped onto a second line.
                    rows[rows.count - 1].english += " " + line
                    if marked { rows[rows.count - 1].marked = true }
                }
            }
        }
        if let german = pendingGerman {
            rows.append(VocabListRow(german: german, english: "", marked: pendingMarked, confident: false))
        }
        let confidence = contentLines == 0 ? 0 : Double(pairedLines) / Double(contentLines)
        return Result(rows: rows.map(tidy), title: title, listConfidence: confidence)
    }

    // MARK: - Lines

    private static func titleLine(_ line: String) -> String? {
        let lower = line.lowercased()
        for prefix in ["vokabelliste", "wortliste", "vokabeln", "vocabulary", "wortschatz"] where lower.hasPrefix(prefix) {
            return line
        }
        return nil
    }

    private static func isHeader(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
        let headers: Set<String> = ["deutsch", "englisch", "english", "german", "quiz", "study for", "study for quiz", "deutsch english", "deutsch englisch", "german english", "deutsch english study for", "deutsch englisch study for", "wort", "bedeutung", "word", "meaning"]
        if headers.contains(lower) { return true }
        if lower.hasPrefix("name:") { return true }
        if lower.range(of: #"^(deutsch|german)\s+(english|englisch)\b"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"^(seite|page)\s+\d+$"#, options: .regularExpression) != nil { return true }
        return false
    }

    // MARK: - Columns

    private enum LineKind { case mixed, germanOnly, englishOnly }

    private struct Split {
        var kind: LineKind
        var german: String = ""
        var english: String = ""
        var confident: Bool = true
    }

    private static func splitColumns(_ line: String) -> Split {
        // 1. An explicit separator settles it.
        for separator in explicitSeparators {
            if let range = line.range(of: separator) {
                let left = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let right = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !left.isEmpty, !right.isEmpty { return Split(kind: .mixed, german: left, english: right) }
            }
        }
        if let range = line.range(of: #"\S\s{2,}\S"#, options: .regularExpression) {
            let gap = line[range].firstIndex(where: \.isWhitespace) ?? range.lowerBound
            let left = String(line[..<gap]).trimmingCharacters(in: .whitespaces)
            let right = String(line[gap...]).trimmingCharacters(in: .whitespaces)
            if !left.isEmpty, !right.isEmpty { return Split(kind: .mixed, german: left, english: right) }
        }

        // 2. Two quoted segments: an idiom and its rendering.
        let quotes = quotedSegments(in: line)
        if quotes.count >= 2 {
            let german = quotes[0].text
            let english = String(line[quotes[0].range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !english.isEmpty { return Split(kind: .mixed, german: german, english: english) }
        }

        // 3. Score every split point between words.
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 2 else {
            return Split(kind: looksEnglish(line) ? .englishOnly : .germanOnly, confident: false)
        }
        var best = (index: tokens.count, score: -Double.infinity, strong: false)
        var second = -Double.infinity
        for index in 0...tokens.count {
            let left = tokens[..<index].joined(separator: " ")
            let right = tokens[index...].joined(separator: " ")
            let (score, strong) = splitScore(left: left, right: right)
            if score > best.score {
                second = best.score
                best = (index, score, strong)
            } else if score > second {
                second = score
            }
        }
        let margin = best.score - second
        let confident = best.strong || margin > 0.45
        switch best.index {
        case 0: return Split(kind: .englishOnly, confident: confident)
        case tokens.count: return Split(kind: .germanOnly, confident: confident)
        default:
            return Split(
                kind: .mixed,
                german: tokens[..<best.index].joined(separator: " "),
                english: tokens[best.index...].joined(separator: " "),
                confident: confident
            )
        }
    }

    /// How plausible "left is German, right is English" is, and whether a strong cue decided it.
    private static func splitScore(left: String, right: String) -> (Double, Bool) {
        var score = 0.0
        var strong = false
        let leftGerman = left.isEmpty ? 0.5 : languageProbability(left, of: .german)
        score += leftGerman
        if !right.isEmpty { score += languageProbability(right, of: .english) } else { score += 0.5 }

        let rightLower = right.lowercased()
        let leftLower = left.lowercased()
        let leftFirst = leftLower.split(separator: " ").first.map(String.init) ?? ""
        let leftHasArticle = germanArticles.contains(leftFirst)
        let leftHasUmlaut = left.unicodeScalars.contains { "äöüßÄÖÜ".unicodeScalars.contains($0) }
        // A column split needs a German-looking left side; an English line that happens to contain
        // "to …" mid-way (a wrapped gloss) is not two columns.
        let leftPlausible = left.isEmpty || leftHasArticle || leftHasUmlaut || leftGerman >= 0.3
        if !right.isEmpty, !left.isEmpty, !leftPlausible { score -= 1.2 }
        if !right.isEmpty {
            if leftPlausible, englishOpeners.contains(where: { rightLower.hasPrefix($0) }) { score += 0.9; strong = true }
            if rightLower.hasPrefix("“") || rightLower.hasPrefix("\"") { score += 0.4 }
            // A gloss never opens with a bare conjunction or "of": that word belongs to the left.
            for opener in ["of ", "and ", "or ", "und ", "oder "] where rightLower.hasPrefix(opener) { score -= 0.8 }
        }
        if !left.isEmpty {
            if leftHasArticle { score += 0.35 }
            if leftLower.hasSuffix("(pl)") || leftLower.hasSuffix("(pl.)") { score += 0.9; strong = true }
            if leftHasUmlaut { score += 0.3 }
            // A German column tends to end on a word; an English column rarely starts mid-form ("/ hat").
            if leftLower.hasSuffix("/") { score -= 0.6 }
        }
        // Umlauts on the supposedly English side count against the split.
        if right.unicodeScalars.contains(where: { "äöüßÄÖÜ".unicodeScalars.contains($0) }) { score -= 0.8 }
        // English rarely holds a German article.
        for token in rightLower.split(separator: " ").prefix(3) where germanArticles.contains(String(token)) { score -= 0.5 }
        return (score, strong)
    }

    private static func looksEnglish(_ text: String) -> Bool {
        languageProbability(text, of: .english) > languageProbability(text, of: .german)
    }

    private static func languageProbability(_ text: String, of language: NLLanguage) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        if hypotheses.isEmpty { return 0.5 }
        return hypotheses[language] ?? 0
    }

    private static func quotedSegments(in line: String) -> [(text: String, range: Range<String.Index>)] {
        var result: [(String, Range<String.Index>)] = []
        var openIndex: String.Index?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if "“„\"".contains(character), openIndex == nil {
                openIndex = index
            } else if "”“\"".contains(character), let open = openIndex, index > open {
                let inner = String(line[line.index(after: open)..<index])
                result.append((inner, open..<line.index(after: index)))
                openIndex = nil
            }
            index = line.index(after: index)
        }
        return result
    }

    private static func tidy(_ row: VocabListRow) -> VocabListRow {
        var row = row
        row.german = row.german.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        row.english = row.english.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return row
    }
}

/// The forms a teacher lists in one entry, split out so each can be found in a text:
/// "der Kieselstein/ die Kieselsteine (pl)" → ["der Kieselstein", "die Kieselsteine"];
/// "anzünden/ zündete…an/ hat angezündet" → ["anzünden", "zündete", "angezündet"].
nonisolated enum VocabForms {
    static func split(_ german: String) -> [String] {
        var out: [String] = []
        for part in german.components(separatedBy: CharacterSet(charactersIn: "/,;")) {
            for alternative in part.components(separatedBy: "->") {
                var form = alternative
                    .replacingOccurrences(of: #"\((pl|pl\.|sg|Pl\.)\)"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\s*(hat|ist|haben|sind)\s+"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                // A separable verb written "zündete…an": the finite part is what a text shows.
                if let dots = form.range(of: #"[…\.]{1,3}"#, options: .regularExpression),
                   form.distance(from: form.startIndex, to: dots.lowerBound) > 2 {
                    form = String(form[..<dots.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                form = form.trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
                if form.count >= 2 { out.append(form) }
            }
        }
        return out.isEmpty ? [german] : out
    }
}
