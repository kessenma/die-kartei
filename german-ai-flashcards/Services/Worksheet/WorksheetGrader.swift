//
//  WorksheetGrader.swift
//  german-ai-flashcards
//
//  The optional check of a worksheet: the learner asks, nothing runs on its own, and nothing it
//  says goes to the teacher. Three sources, the first that applies wins:
//
//   1. The teacher's answer key (`WorksheetSetup.key`), compared after normalizing case,
//      spacing and punctuation; ä, ö, ü and ß stay distinct.
//   2. The article rules — deterministic, for a blank or a choice that holds one article: the
//      case from the word before it (a preposition's case, "(Ort)"/"(Ziel)" for a two-way one, the
//      start of the sentence for the subject) and the gender from the sheet's own "Nomen:" line,
//      else the bundled dictionary. They judge only when every input is known; anything else is
//      left to the next source, never guessed.
//   3. The downloaded tutor, one exercise per prompt, replying one line per answer. "unsicher",
//      a missing line or a line it can't read is "prüfen", never wrong: a false "wrong" teaches
//      the wrong thing (docs/WORKSHEETS.md, and the measure-before-gating rule).
//
//  The rules and the reply parser are pure, so the tests drive them with a stub lexicon.
//

import Foundation

// MARK: - 1. The teacher's key

nonisolated enum WorksheetKeyCheck {
    static func normalize(_ text: String) -> String { WorksheetKeyReader.normalize(text) }

    /// Whether the key settles a blank either way: one of a closed set (a word bank, letters, the
    /// sheet's articles or options, a choice), where any other answer is wrong. An open blank can
    /// be right in other words ("40 Stunden" for "40 Stunden pro Woche"), so there a mismatch is
    /// left to the rules and the tutor, with her answer beside it (`mismatch`).
    static func isClosedSet(slot: String, item: WorksheetItem, options: WorksheetOptions?) -> Bool {
        if item.choices.contains(where: { $0.key == slot }) { return true }
        return options != nil && item.gaps.contains(where: { $0.key == slot })
    }

    /// An open blank whose answer isn't the key's: "prüfen", her answer as the suggestion.
    static func mismatch(_ given: String, key: String) -> WorksheetCheck {
        WorksheetCheck(outcome: .unsure, correction: key, reason: "Her key says „\(key)“.", by: .key, answer: given)
    }

    /// Against one of her examples ("Mögliche Übersetzungen"): the same words are right; anything
    /// else is "prüfen" with her example beside it, since other answers can be right too.
    static func example(_ given: String, sample: String) -> WorksheetCheck {
        if normalize(given) == normalize(sample) {
            return WorksheetCheck(outcome: .right, correction: nil, reason: "Same as her example.", by: .key, answer: given)
        }
        return WorksheetCheck(outcome: .unsure, correction: sample,
                              reason: "Her example: „\(sample)“. Other answers can be right too.", by: .key, answer: given)
    }

    static func check(_ given: String, key: String) -> WorksheetCheck {
        let right = normalize(given) == normalize(key)
        return WorksheetCheck(outcome: right ? .right : .wrong, correction: right ? nil : key,
                              reason: right ? nil : "From the teacher's answer key.", by: .key, answer: given)
    }
}

// MARK: - 2. The article rules

nonisolated enum WorksheetArticleRules {

    /// What the rules look up, gathered beforehand (`WorksheetCheckRunner.lexicon`) so they stay
    /// pure: the app's preposition table and the dictionary's genders for the nouns on the page.
    struct Lexicon: Sendable {
        /// Lowercased preposition → the case it governs.
        var prepositions: [String: PrepositionCase] = [:]
        /// Noun as printed → its gender, only where the dictionary is unanimous.
        var genders: [String: Gender] = [:]

        func governs(_ word: String) -> PrepositionCase? { prepositions[word.lowercased()] }
        func gender(_ noun: String) -> Gender? { genders[noun] }
    }

    struct Expectation: Equatable, Sendable {
        var article: String
        var kasus: GrammarCase
        var reason: String
    }

    /// The article a slot needs, or nil when the rules can't be sure.
    static func expected(
        slot: String,
        in item: WorksheetItem,
        exercise: WorksheetExercise,
        candidates: [String],
        lexicon: Lexicon
    ) -> Expectation? {
        let lowered = Set(candidates.map { $0.lowercased() })
        let definite = Set(WorksheetText.definiteArticles)
        let indefinite = Set(WorksheetText.indefiniteArticles)
        guard !lowered.isEmpty else { return nil }
        let isDefinite = lowered.isSubset(of: definite)
        guard isDefinite || lowered.isSubset(of: indefinite) else { return nil }

        guard let position = item.segments.firstIndex(where: { segment in
            switch segment {
            case .gap(let gap): gap.key == slot
            case .choice(let choice): choice.key == slot
            default: false
            }
        }) else { return nil }

        let before = wordsBefore(item.segments[..<position])
        let after = wordsAfter(item.segments[(position + 1)...])
        guard let noun = after.prefix(3).first(where: { $0.first?.isUppercase == true }) else { return nil }

        // The case.
        let kasus: GrammarCase
        let why: String
        if let previous = before.last {
            guard let group = lexicon.governs(previous) else { return nil }
            switch group {
            case .akkusativ: kasus = .akkusativ
            case .dativ: kasus = .dativ
            case .genitiv: kasus = .genitiv
            case .wechsel:
                let hint = (item.hint ?? "").lowercased()
                if hint.contains("ort") || hint.hasPrefix("wo") && !hint.hasPrefix("wohin") {
                    kasus = .dativ
                } else if hint.contains("ziel") || hint.hasPrefix("wohin") {
                    kasus = .akkusativ
                } else {
                    return nil
                }
            }
            why = "\(previous) + \(kasus.name)"
        } else {
            // Nothing before the blank in its sentence: the subject.
            kasus = .nominativ
            why = "Subjekt → Nominativ"
        }

        // The gender, from the sheet's own list first.
        guard let (gender, lemma) = gender(of: noun, sheetNouns: exercise.nouns, lexicon: lexicon) else { return nil }
        let article: String
        if isDefinite {
            article = kasus.article(gender)
        } else {
            guard gender != .plural else { return nil }
            article = "ein" + kasus.einEnding(gender)
        }
        let display = "\(gender.article) \(lemma)"
        return Expectation(article: article, kasus: kasus, reason: "\(why) · \(display) → \(article) \(noun)")
    }

    /// Check an answer against the rules. Nil when they can't say.
    static func check(
        answer given: String,
        caseTag: GrammarCase?,
        slot: String,
        in item: WorksheetItem,
        exercise: WorksheetExercise,
        candidates: [String],
        lexicon: Lexicon
    ) -> WorksheetCheck? {
        guard let expected = expected(slot: slot, in: item, exercise: exercise,
                                      candidates: candidates, lexicon: lexicon) else { return nil }
        let answer = given.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !answer.isEmpty, !answer.contains(" ") else { return nil }
        if answer != expected.article {
            return WorksheetCheck(outcome: .wrong, correction: expected.article, reason: expected.reason,
                                  by: .rules, answer: given)
        }
        if let caseTag, caseTag != expected.kasus {
            return WorksheetCheck(outcome: .wrong, correction: "\(expected.article) · \(expected.kasus.short)",
                                  reason: "Right article, but the case is \(expected.kasus.name). \(expected.reason)",
                                  by: .rules, answer: given)
        }
        return WorksheetCheck(outcome: .right, correction: nil, reason: expected.reason, by: .rules, answer: given)
    }

    // MARK: Pieces

    /// The words of the slot's own sentence that come before it: from the last sentence end,
    /// line break or earlier blank on. "(3)" before a dialog blank has no letters and isn't one.
    private static func wordsBefore(_ segments: ArraySlice<WorksheetSegment>) -> [String] {
        var out: [String] = []
        for segment in segments {
            switch segment {
            case .text(let text, _):
                var rest = Substring(text)
                if let end = text.lastIndex(where: { ".!?".contains($0) }) {
                    out = []
                    rest = text[text.index(after: end)...]
                }
                out += letterWords(String(rest))
            case .lineBreak, .gap, .choice:
                out = []
            }
        }
        return out
    }

    /// The words after the slot, up to its sentence's end.
    private static func wordsAfter(_ segments: ArraySlice<WorksheetSegment>) -> [String] {
        var out: [String] = []
        for segment in segments {
            guard case .text(let text, _) = segment else { break }
            if let end = text.firstIndex(where: { ".!?".contains($0) }) {
                out += letterWords(String(text[..<end]))
                break
            }
            out += letterWords(text)
        }
        return out
    }

    private static func letterWords(_ text: String) -> [String] {
        WorksheetText.words(in: text, base: 0).map(\.text).filter { $0.contains(where: \.isLetter) }
    }

    /// The noun's gender and dictionary form: from "Nomen: der Regen, die Salate, …" when it is on
    /// the sheet (matching "Regens", "Salaten"), else the dictionary for the form as printed.
    static func gender(of noun: String, sheetNouns: [String], lexicon: Lexicon) -> (Gender, String)? {
        let forms = [noun] + ["es", "s", "en", "n"].compactMap { ending in
            noun.count > ending.count + 2 && noun.hasSuffix(ending) ? String(noun.dropLast(ending.count)) : nil
        }
        for entry in sheetNouns {
            let parts = entry.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let article = Gender(article: parts[0].lowercased()) else { continue }
            let lemma = parts[1]
            guard forms.contains(lemma) || lemma == noun else { continue }
            if article != .die { return (article, lemma) }
            // "die" is feminine or plural: plural when the word, less a plural ending, is a
            // masculine or neuter (or feminine) noun of its own and the word itself isn't.
            if lexicon.gender(lemma) == .die { return (.die, lemma) }
            let stems = ["e", "en", "n", "er", "s"].compactMap { ending in
                lemma.hasSuffix(ending) ? String(lemma.dropLast(ending.count)) : nil
            }
            if stems.contains(where: { lexicon.gender($0) != nil }) { return (.plural, lemma) }
            return nil
        }
        if let gender = lexicon.gender(noun) { return (gender, noun) }
        // Not on the sheet: a genitive "-s"/"-es" is only ever on a masculine or neuter noun.
        for ending in ["es", "s"] where noun.hasSuffix(ending) && noun.count > ending.count + 2 {
            let lemma = String(noun.dropLast(ending.count))
            if let gender = lexicon.gender(lemma), gender == .der || gender == .das { return (gender, lemma) }
        }
        return nil
    }
}

// MARK: - 2b. A group into a case

/// "ein Salat: ________" under "Setze die Gruppen in den Dativ mit „mit“." → "mit einem Salat".
/// Deterministic like the article rules, and as careful: the article decides right or wrong, and
/// a word the app can't line up with the expected one — usually a misread of handwriting, "mit
/// eipen Brst" for "mit einem Brot" — makes the answer "prüfen", never wrong. A plural task, the
/// Genitiv (whose nouns change ending) and any group the sheet doesn't print are left to the tutor.
nonisolated enum WorksheetGroupRules {

    struct Task: Equatable, Sendable {
        var preposition: String?
        var article: String
        var noun: String
        var kasus: GrammarCase
        /// "ein Brot" as printed.
        var given: String

        var expected: String { ([preposition, article, noun].compactMap { $0 }).joined(separator: " ") }
        var reason: String {
            "\(preposition.map { "\($0) + " } ?? "")\(kasus.name) · \(given) → \(article) \(noun)"
        }
    }

    static func task(slot: String, in item: WorksheetItem, directions: String,
                     lexicon: WorksheetArticleRules.Lexicon) -> Task? {
        guard let position = item.segments.firstIndex(where: { if case .gap(let gap) = $0 { gap.key == slot && gap.isLong } else { false } })
        else { return nil }
        let before = item.segments[..<position].compactMap { if case .text(let text, _) = $0 { text } else { nil } }
            .joined().trimmingCharacters(in: .whitespaces)
        guard let match = WorksheetText.firstMatch(#"^(der|die|das|ein|eine)\s+(\p{Lu}[\p{L}-]*)\s*:?$"#, in: before)
        else { return nil }
        let ns = before as NSString
        let givenArticle = ns.substring(with: match.range(at: 1)).lowercased()
        let noun = ns.substring(with: match.range(at: 2))

        let lower = directions.lowercased()
        guard !lower.contains("plural") else { return nil }
        let named: [GrammarCase] = [.akkusativ, .dativ, .genitiv].filter { lower.contains($0.rawValue) }
        guard named.count == 1, let kasus = named.first, kasus != .genitiv else { return nil }

        let gender: Gender
        switch givenArticle {
        case "die", "eine": gender = .die
        case "der": gender = .der
        case "das": gender = .das
        default:
            guard let found = lexicon.gender(noun), found == .der || found == .das else { return nil }
            gender = found
        }
        let definite = ["der", "die", "das"].contains(givenArticle)
        let article = definite ? kasus.article(gender) : "ein" + kasus.einEnding(gender)

        // The preposition the directions quote: „mit“.
        var preposition: String?
        if let quoted = WorksheetText.firstMatch(#"[„"“‚']([\p{L}]+)[“"”‘']"#, in: directions) {
            let word = (directions as NSString).substring(with: quoted.range(at: 1))
            if lexicon.governs(word) != nil { preposition = word.lowercased() }
        }
        return Task(preposition: preposition, article: article, noun: noun, kasus: kasus,
                    given: "\(givenArticle) \(noun)")
    }

    static func check(answer given: String, task: Task) -> WorksheetCheck {
        let tokens = WorksheetKeyCheck.normalize(given).split(separator: " ").map(String.init)
        let expected = WorksheetKeyCheck.normalize(task.expected).split(separator: " ").map(String.init)
        func unsure(_ why: String) -> WorksheetCheck {
            WorksheetCheck(outcome: .unsure, correction: task.expected, reason: why, by: .rules, answer: given)
        }
        guard tokens.count == expected.count else {
            return unsure("Expected \(expected.count) words, like „\(task.expected)“. If the reading is off, fix it.")
        }
        let articleIndex = task.preposition == nil ? 0 : 1
        if let preposition = task.preposition, tokens[0] != preposition {
            return unsure("Starts with „\(tokens[0])“, not „\(preposition)“. If the reading is off, fix it.")
        }
        let noun = task.noun.lowercased()
        let nounGiven = tokens[articleIndex + 1]
        guard nounGiven == noun || (nounGiven.hasPrefix(noun) && nounGiven.count - noun.count <= 2) else {
            return unsure("Is „\(tokens[articleIndex + 1])“ meant to be „\(task.noun)“? Fix the reading and check again.")
        }
        let article = tokens[articleIndex]
        if article == task.article {
            return WorksheetCheck(outcome: .right, correction: nil, reason: task.reason, by: .rules, answer: given)
        }
        let allArticles = Set(WorksheetText.definiteArticles + WorksheetText.indefiniteArticles)
        guard allArticles.contains(article) else {
            return unsure("„\(article)“ isn't an article. If the reading is off, fix it.")
        }
        return WorksheetCheck(outcome: .wrong, correction: task.expected, reason: task.reason, by: .rules, answer: given)
    }
}

// MARK: - 3. The tutor

nonisolated enum WorksheetTutorCheck {

    /// One answer put to the tutor: the item with the learner's answer in place.
    struct Question: Sendable {
        var key: String
        var line: String
        var answer: String
        /// The words a sensible correction can use: the item's, its task's and the sheet's nouns.
        var context: [String] = []
        /// The teacher's own answer or example for this blank, when her key has one.
        var reference: String?
    }

    static let system = """
    You check a German learner's homework from a teacher's worksheet. Judge each numbered answer \
    against the instruction. Be strict about grammar, but never invent a mistake: if you are not \
    sure, say "unsicher". Reply with exactly one line per answer and nothing else.
    """

    static func prompt(instruction: String?, nouns: [String], questions: [Question]) -> String {
        var lines: [String] = []
        if let instruction { lines.append("Instruction: \(instruction)") }
        if !nouns.isEmpty { lines.append("Nouns on the sheet: \(nouns.joined(separator: ", "))") }
        lines.append("Answers are in [brackets]. For each number reply: number: richtig | falsch | unsicher ; correct form ; reason in a few English words")
        lines.append("")
        for (index, question) in questions.enumerated() {
            let reference = question.reference.map { " (the teacher's example answer: \($0))" } ?? ""
            lines.append("\(index + 1). \(question.line)\(reference)")
        }
        return lines.joined(separator: "\n")
    }

    /// One check per question, in order. A line the tutor left out or garbled is "unsicher".
    static func parse(_ reply: String, questions: [Question]) -> [String: WorksheetCheck] {
        var byNumber: [Int: (WorksheetCheck.Outcome, String?, String?)] = [:]
        for raw in reply.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "*-• "))
            guard let match = WorksheetText.firstMatch(
                #"(?i)^(\d{1,3})\s*[.:)]\s*\**\s*(richtig|falsch|unsicher|correct|right|wrong|incorrect|unsure)\b\**\s*[;|:,–-]?\s*(.*)$"#,
                in: line
            ) else { continue }
            let ns = line as NSString
            guard let number = Int(ns.substring(with: match.range(at: 1))), byNumber[number] == nil else { continue }
            let word = ns.substring(with: match.range(at: 2)).lowercased()
            let outcome: WorksheetCheck.Outcome
            switch word {
            case "richtig", "correct", "right": outcome = .right
            case "falsch", "wrong", "incorrect": outcome = .wrong
            default: outcome = .unsure
            }
            let rest = ns.substring(with: match.range(at: 3))
            let parts = rest.split(whereSeparator: { $0 == ";" || $0 == "|" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0 != "-" && $0 != "–" }
            byNumber[number] = (outcome, parts.first, parts.dropFirst().first)
        }
        var out: [String: WorksheetCheck] = [:]
        for (index, question) in questions.enumerated() {
            if let (outcome, correction, reason) = byNumber[index + 1] {
                // A "wrong" whose correction is the answer itself is the tutor contradicting
                // itself, and one that brings in a noun the item never mentions ("mit Eiern" for
                // "ein Brot") is the tutor guessing: not sure, either way.
                let same = correction.map { WorksheetKeyCheck.normalize($0) == WorksheetKeyCheck.normalize(question.answer) } ?? false
                let strays = correction.map { strayNouns(in: $0, context: question.context + [question.answer]) } ?? []
                var settled: WorksheetCheck.Outcome = outcome == .wrong && (same || correction == nil) ? .unsure : outcome
                var why = reason
                if settled == .wrong, !strays.isEmpty {
                    settled = .unsure
                    why = "The tutor's correction (\(correction ?? "")) doesn't fit this item. Ask your teacher."
                }
                out[question.key] = WorksheetCheck(outcome: settled,
                                                   correction: settled == .right ? nil : correction,
                                                   reason: why, by: .tutor, answer: question.answer)
            } else {
                out[question.key] = WorksheetCheck(outcome: .unsure, correction: nil,
                                                   reason: "The tutor didn't answer this one.", by: .tutor,
                                                   answer: question.answer)
            }
        }
        return out
    }

    /// Capitalised words of a correction (past its first word, which may just start the sentence)
    /// that no word of the context shares a stem with: "Eiern" when the item is about "Brot".
    static func strayNouns(in correction: String, context: [String]) -> [String] {
        let words = WorksheetText.words(in: correction, base: 0).map(\.text)
        let known = context.flatMap { WorksheetText.words(in: $0, base: 0).map { $0.text.lowercased() } }
        return words.dropFirst().filter { word in
            guard word.first?.isUppercase == true, word.count >= 3 else { return false }
            let lower = word.lowercased()
            return !known.contains { other in
                let shared = zip(lower, other).prefix { $0 == $1 }.count
                return shared >= min(4, min(lower.count, other.count))
            }
        }
    }

    /// The questions for one exercise page: every answered blank, choice and sentence the earlier
    /// sources left open, each shown in its sentence with the answer in brackets — and, on a page
    /// with sections, the section's own task, since "Schreibe im Plural" changes the answer.
    /// `references`: the teacher's answers and examples by answer key, handed to the tutor beside
    /// each answer (they also become words a correction may use).
    static func questions(for exercise: WorksheetExercise, answers: [String: WorksheetAnswer],
                          open: Set<String>, references: [String: String] = [:]) -> [Question] {
        var out: [Question] = []
        for section in exercise.sections {
            let task = exercise.sections.count > 1 ? section.heading.map { "(\($0)) " } ?? "" : ""
            for item in section.items {
                let filled = task + render(item, answers: answers)
                let context = [item.anchor, section.heading ?? "", item.hint ?? ""] + exercise.nouns
                for gap in item.gaps where open.contains(gap.key) {
                    guard let text = answers[gap.key]?.text, !text.isEmpty else { continue }
                    var line = filled
                    if let tag = answers[gap.key]?.kasus { line += " (case noted: \(tag.name))" }
                    out.append(Question(key: gap.key, line: line, answer: text,
                                        context: context + [references[gap.key]].compactMap { $0 },
                                        reference: references[gap.key]))
                }
                for choice in item.choices where open.contains(choice.key) {
                    guard let picked = answers[choice.key]?.choice, choice.options.indices.contains(picked) else { continue }
                    out.append(Question(key: choice.key, line: filled, answer: choice.options[picked].text,
                                        context: context + [references[choice.key]].compactMap { $0 },
                                        reference: references[choice.key]))
                }
                if item.writeBelow, open.contains(item.writeKey), let text = answers[item.writeKey]?.text, !text.isEmpty {
                    let itemTask = WorksheetText.collapse(item.anchor)
                    out.append(Question(key: item.writeKey, line: "\(task)Task: \(itemTask) → [\(text)]",
                                        answer: text, context: context + [references[item.writeKey]].compactMap { $0 },
                                        reference: references[item.writeKey]))
                }
            }
        }
        return out
    }

    /// The item as one line with every answer bracketed in place.
    static func render(_ item: WorksheetItem, answers: [String: WorksheetAnswer]) -> String {
        let parts = item.segments.map { segment -> String in
            switch segment {
            case .text(let text, _): return text
            case .gap(let gap): return "[" + (answers[gap.key]?.text ?? "___") + "]"
            case .choice(let choice):
                if let picked = answers[choice.key]?.choice, choice.options.indices.contains(picked) {
                    return "[" + choice.options[picked].text + "]"
                }
                return choice.options.map(\.text).joined(separator: " / ")
            case .lineBreak: return " "
            }
        }
        return WorksheetText.collapse(parts.joined())
    }
}
