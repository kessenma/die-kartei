//
//  WritingTutorCheck.swift
//  german-ai-flashcards
//
//  The prompts the Schreiben room puts to the tutor and the parsers and gates that read its
//  replies. Pure: nothing here loads a model or touches a row, so every gate has a unit test.
//
//  The shape follows the worksheet check (docs/WORKSHEETS.md ▸ The check): labelled lines, one
//  per sentence, never JSON (German quotes break the JSON sanitizer), and a reply that fails a
//  gate becomes "unsicher", never "falsch". The gates are the chat correction's echo rule (an
//  18-of-19 false-correction filter on the tuned small tutor), the worksheet's stray-noun rule,
//  and a rewrite rule of this feature's own: a correction that replaces most of a sentence is the
//  tutor writing its own sentence, which the learner cannot learn from.
//

import Foundation

nonisolated enum WritingTutorCheck {

    // MARK: - Categories

    /// Categories the tutor may name that are not grammar structures the profile tracks. Shown
    /// and counted, never written to the learner profile.
    static let extraCategories = ["wortstellung", "konjugation", "rechtschreibung", "wortwahl"]

    static var categoryKeys: [String] { GrammarFocus.allCases.map(\.rawValue) + extraCategories }

    static func categoryLabel(_ raw: String) -> String {
        if let focus = GrammarFocus(rawValue: raw) { return focus.germanLabel }
        switch raw {
        case "wortstellung": return "Wortstellung"
        case "konjugation": return "Konjugation"
        case "rechtschreibung": return "Rechtschreibung"
        case "wortwahl": return "Wortwahl"
        default: return "Sonstiges"
        }
    }

    /// The tutor's category, however it spelled it, as one of `categoryKeys`; nil otherwise.
    static func normalizeCategory(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let folded = raw.lowercased()
            .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".*-–"))
        guard !folded.isEmpty, folded != "-" else { return nil }
        if categoryKeys.contains(folded) { return folded }
        let compact = folded.replacingOccurrences(of: " ", with: "")
        if categoryKeys.contains(compact) { return compact }
        if compact.hasPrefix("konjunktiv") { return GrammarFocus.konjunktiv2.rawValue }
        if compact.hasPrefix("praeposition") || compact.hasPrefix("preposition") { return GrammarFocus.praepositionen.rawValue }
        let synonyms: [(String, String)] = [
            ("wechsel", GrammarFocus.wechselpraepositionen.rawValue),
            ("twoway", GrammarFocus.wechselpraepositionen.rawValue),
            ("verbenmit", GrammarFocus.verbenPraepositionen.rawValue),
            ("verb+", GrammarFocus.verbenPraepositionen.rawValue),
            ("reflexiv", GrammarFocus.reflexivverben.rawValue),
            ("adjektiv", GrammarFocus.adjektivendungen.rawValue),
            ("adjective", GrammarFocus.adjektivendungen.rawValue),
            ("modal", GrammarFocus.modalverben.rawValue),
            ("dativ", GrammarFocus.dativ.rawValue),
            ("dative", GrammarFocus.dativ.rawValue),
            ("akkusativ", GrammarFocus.akkusativ.rawValue),
            ("accusative", GrammarFocus.akkusativ.rawValue),
            ("genitiv", GrammarFocus.genitiv.rawValue),
            ("genitive", GrammarFocus.genitiv.rawValue),
            ("artikel", GrammarFocus.artikel.rawValue),
            ("article", GrammarFocus.artikel.rawValue),
            ("gender", GrammarFocus.artikel.rawValue),
            ("genus", GrammarFocus.artikel.rawValue),
            ("perfekt", GrammarFocus.perfekt.rawValue),
            ("perfect", GrammarFocus.perfekt.rawValue),
            ("pasttense", GrammarFocus.perfekt.rawValue),
            ("praeteritum", GrammarFocus.praeteritum.rawValue),
            ("preterite", GrammarFocus.praeteritum.rawValue),
            ("simplepast", GrammarFocus.praeteritum.rawValue),
            ("futur", GrammarFocus.futur.rawValue),
            ("future", GrammarFocus.futur.rawValue),
            ("subjunctive", GrammarFocus.konjunktiv2.rawValue),
            ("wordorder", "wortstellung"),
            ("satzbau", "wortstellung"),
            ("verbposition", "wortstellung"),
            ("spelling", "rechtschreibung"),
            ("orthograph", "rechtschreibung"),
            ("conjugation", "konjugation"),
            ("verbform", "konjugation"),
            ("verbending", "konjugation"),
            ("agreement", "konjugation"),
            ("wordchoice", "wortwahl"),
            ("vocabulary", "wortwahl"),
            ("vokabel", "wortwahl"),
            ("lexik", "wortwahl"),
        ]
        for (needle, key) in synonyms where compact.contains(needle) { return key }
        return nil
    }

    // MARK: - The per-sentence check

    /// Sentences per tutor call. Six keeps a batch and its corrections far inside the memory
    /// saver's 1024-token cache on an 8 GB iPad.
    static let batchSize = 6
    /// Sentences one run checks at most; the rest wait for the next tap.
    static let maxSentencesPerRun = 40

    static func maxTokens(sentences n: Int) -> Int { 40 + 60 * n }

    static func system(level: CEFRLevel, focus: GrammarFocus?, memoryHint: String) -> String {
        var s = "You are a meticulous German teacher checking sentences a learner wrote. "
        s += "The learner's level is \(level.rawValue). "
        if let focus {
            s += "Pay particular attention to: \(focus.germanLabel) (\(focus.englishLabel)). "
        }
        if !memoryHint.isEmpty { s += memoryHint + " " }
        s += "Judge each numbered sentence on its own. Be strict about grammar, but never invent a mistake: "
        s += "if you are not sure, say \"unsicher\". Keep the learner's meaning, style and word choice; "
        s += "fix only what is wrong. Never correct punctuation alone. "
        s += "Reply with exactly one line per sentence and nothing else."
        return s
    }

    static func prompt(sentences: [String]) -> String {
        var lines: [String] = []
        lines.append("For each number reply: number: richtig | falsch | unsicher ; the full corrected sentence (or -) ; reason in at most 12 English words ; category")
        lines.append("Category is one of: " + categoryKeys.joined(separator: ", ") + ", -")
        lines.append("")
        for (i, sentence) in sentences.enumerated() {
            lines.append("\(i + 1). \(sentence)")
        }
        return lines.joined(separator: "\n")
    }

    /// A correction that changes more than this share of the sentence's words is a rewrite.
    static let rewriteRatio = 0.5

    private static let linePattern = try! NSRegularExpression(
        pattern: #"(?i)^(\d{1,3})\s*[.:)]\s*\**\s*(richtig|falsch|unsicher|correct|right|ok|wrong|incorrect|unsure)\b\**\s*[;|:,–-]?\s*(.*)$"#
    )

    /// One verdict per sentence, in order, numbered from `startIndex`. `context` is wording a
    /// sensible correction may bring in (the prompt), on top of the sentence's own words.
    static func parse(_ reply: String, sentences: [String], startIndex: Int = 0, context: [String] = []) -> [WritingSentenceCheck] {
        var byNumber: [Int: (String, String?, String?, String?)] = [:]
        for raw in reply.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "*-• "))
            let ns = line as NSString
            guard let match = linePattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            guard let number = Int(ns.substring(with: match.range(at: 1))), byNumber[number] == nil else { continue }
            let word = ns.substring(with: match.range(at: 2)).lowercased()
            let rest = ns.substring(with: match.range(at: 3))
            let parts = rest.split(whereSeparator: { $0 == ";" || $0 == "|" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            func part(_ i: Int) -> String? {
                guard parts.indices.contains(i) else { return nil }
                let p = parts[i].trimmingCharacters(in: CharacterSet(charactersIn: "*"))
                return p.isEmpty || p == "-" || p == "–" ? nil : p
            }
            byNumber[number] = (word, part(0), part(1), part(2))
        }

        return sentences.enumerated().map { offset, original in
            let index = startIndex + offset
            guard let (word, rawCorrection, rawReason, rawCategory) = byNumber[offset + 1] else {
                return WritingSentenceCheck(index: index, original: original, outcome: .unsure,
                                            reason: "The tutor didn't answer this one.")
            }
            let correction = rawCorrection.map(stripQuotes)
            let category = normalizeCategory(rawCategory)
            let reason = rawReason.map { String($0.prefix(90)) }

            switch word {
            case "richtig", "correct", "right", "ok":
                return WritingSentenceCheck(index: index, original: original, outcome: .ok, categoryRaw: category)
            case "falsch", "wrong", "incorrect":
                guard let correction else {
                    return WritingSentenceCheck(index: index, original: original, outcome: .unsure,
                                                reason: reason ?? "The tutor gave no correction.", categoryRaw: category)
                }
                // A correction that changes nothing but punctuation, case or quotes is an echo:
                // the sentence was fine.
                if ConversationPrompts.echoNormalized(correction) == ConversationPrompts.echoNormalized(original) {
                    return WritingSentenceCheck(index: index, original: original, outcome: .ok, categoryRaw: category)
                }
                let ratio = WritingDiff.changedRatio(original, correction)
                let a = Double(WritingDiff.tokens(original).count), b = Double(WritingDiff.tokens(correction).count)
                let lengthRatio = a > 0 ? b / a : 1
                if ratio > rewriteRatio || lengthRatio < 0.6 || lengthRatio > 1.6 {
                    return WritingSentenceCheck(index: index, original: original, outcome: .unsure,
                                                corrected: correction,
                                                reason: "The tutor rewrote this sentence rather than correcting it. Ask your teacher.",
                                                categoryRaw: category)
                }
                let strays = WorksheetTutorCheck.strayNouns(in: correction, context: [original] + context)
                if !strays.isEmpty {
                    return WritingSentenceCheck(index: index, original: original, outcome: .unsure,
                                                corrected: correction,
                                                reason: "The tutor's correction brings in \(strays.joined(separator: ", ")). Ask your teacher.",
                                                categoryRaw: category)
                }
                return WritingSentenceCheck(index: index, original: original, outcome: .fix,
                                            corrected: correction, reason: reason, categoryRaw: category)
            default:
                return WritingSentenceCheck(index: index, original: original, outcome: .unsure,
                                            corrected: correction, reason: reason, categoryRaw: category)
            }
        }
    }

    private static func stripQuotes(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\"", "\""), ("„", "“"), ("“", "”"), ("«", "»"), ("'", "'")]
        for (open, close) in pairs where t.count >= 2 && t.first == open && t.last == close {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    // MARK: - The comment

    static let commentMaxTokens = 60

    static let commentSystem = """
    You are an encouraging German teacher. Write ONE sentence in English, at most 25 words, about \
    this learner's text: what went well and the one thing to work on next. No grade, no score, no \
    number, no list. Reply with that sentence only.
    """

    static func commentPrompt(text: String, check: [WritingSentenceCheck]) -> String {
        let excerpt = String(text.prefix(1200))
        let judged = check.filter { $0.outcome == .ok || $0.outcome == .fix }
        let fixes = check.filter { $0.outcome == .fix }
        var lines = ["The learner wrote:", excerpt, ""]
        lines.append("Sentences with slips: \(fixes.count) of \(judged.count).")
        if let top = topCategory(check) { lines.append("Most frequent: \(categoryLabel(top)).") }
        return lines.joined(separator: "\n")
    }

    private static let numberish = try! NSRegularExpression(
        pattern: #"(?i)\d+\s*(/|%|von|out of|points?|punkte?|words?|wörter)|\bgrade\b|\bnote\b|\bscore\b|\bbewertung\b"#
    )

    /// The tutor's comment, or nil when it broke the rules (a number, a grade, a list, too long).
    static func parseComment(_ reply: String) -> String? {
        let cleaned = ConversationPrompts.stripThinkBlocks(reply)
        guard let first = cleaned.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*-• ")) })
            .first(where: { !$0.isEmpty }) else { return nil }
        let line = stripQuotes(first)
        guard line.count <= 200, line.count >= 12 else { return nil }
        let ns = line as NSString
        if numberish.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil { return nil }
        return line
    }

    /// The app's own line when the tutor's comment failed its gate.
    static func fallbackComment(_ check: [WritingSentenceCheck]) -> String {
        let judged = check.filter { $0.outcome == .ok || $0.outcome == .fix }
        let ok = judged.filter { $0.outcome == .ok }.count
        guard !judged.isEmpty else { return "Nothing could be judged this time. Try again with a tutor loaded." }
        var s = ok == judged.count
            ? "Every judged sentence was clean."
            : "\(ok) of \(judged.count) judged sentences were clean."
        if let top = topCategory(check) { s += " \(categoryLabel(top)) came up most, so that is the one to look at next." }
        return s
    }

    static func topCategory(_ check: [WritingSentenceCheck]) -> String? {
        var counts: [String: Int] = [:]
        for s in check where s.outcome == .fix { if let c = s.categoryRaw { counts[c, default: 0] += 1 } }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    // MARK: - What the learner says they find hard

    static let struggleMaxTokens = 120
    static let struggleCap = 3

    static let struggleSystem = """
    You read a German learner's journal entry, written in any language. List what THEY SAY they find \
    hard about German, in short notes. Only what the learner states about themselves; never infer \
    anything from their mistakes. If they mention nothing, reply NONE. At most 3 lines, each exactly: \
    STRUGGLE: <paraphrase in at most 12 English words> ; <category or ->
    """

    static func strugglePrompt(text: String) -> String {
        "Category is one of: " + GrammarFocus.allCases.map(\.rawValue).joined(separator: ", ") + ", -\n\n"
            + "The entry:\n" + String(text.prefix(2000))
    }

    /// The notes the tutor read out of the entry, deduplicated and capped. A line that is a whole
    /// sentence of the entry copied out is dropped: a note, not a quotation.
    static func parseStruggles(_ reply: String, entryText: String) -> [(text: String, focus: GrammarFocus?)] {
        let cleaned = ConversationPrompts.stripThinkBlocks(reply)
        var out: [(text: String, focus: GrammarFocus?)] = []
        var seen = Set<String>()
        func key(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0 == " " }.split(separator: " ").joined(separator: " ")
        }
        let entrySentences = Set(WritingSentences.split(entryText).map(key))
        for raw in cleaned.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*-• "))
            guard let range = line.range(of: "STRUGGLE:", options: .caseInsensitive) else { continue }
            let rest = line[range.upperBound...]
            let parts = rest.split(whereSeparator: { $0 == ";" || $0 == "|" }).map { $0.trimmingCharacters(in: .whitespaces) }
            guard var text = parts.first, !text.isEmpty else { continue }
            text = stripQuotes(text)
            if text.count > SelfReportNote.maxLength { text = String(text.prefix(SelfReportNote.maxLength - 1)) + "…" }
            let textKey = key(text)
            guard textKey.count >= 4, !entrySentences.contains(textKey), seen.insert(textKey).inserted else { continue }
            let focus = parts.dropFirst().first.flatMap { normalizeCategory($0) }.flatMap(GrammarFocus.init(rawValue:))
            out.append((text: text, focus: focus))
            if out.count == struggleCap { break }
        }
        return out
    }

    // MARK: - A prompt the tutor writes

    static let promptMaxTokens = 60

    static func promptGenerationSystem(level: CEFRLevel) -> String {
        "You write ONE short writing prompt for a German learner at \(level.rawValue). German only, at most 2 "
            + "sentences, a question or an instruction, no answer, no translation, no label. Reply with the prompt only."
    }

    static func promptGenerationUser(topic: String, kind: JournalKind) -> String {
        let shape = kind == .aufsatz ? "a short essay" : "a diary entry"
        return "Topic: \(topic.trimmingCharacters(in: .whitespacesAndNewlines))\nThe learner will write \(shape) in German."
    }
}
