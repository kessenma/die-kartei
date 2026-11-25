//
//  WorksheetKeyReader.swift
//  german-ai-flashcards
//
//  Reads a teacher's "Lösungen" pages into the worksheet's answer key (`WorksheetSetup.key`).
//  The parser has nothing to say about such a page (no gaps, no instruction: `.notExercise`), so
//  this works on the page's raw lines:
//
//      Lösungen · Übungen 01 und 02          ← a title starting "Lösung"
//      Übung 01            Übung 02          ← block headers, often two columns side by side
//      1 C · error analysis   1 D · beheben  ← "number answer"
//
//  A block is matched to the exercise page whose title starts with the same "Übung N" (or
//  "Aufgabe N"), and each answer to that exercise's item with the same printed number, or to the
//  gap printed with that "(N)". A block whose note says its answers are examples ("Mögliche
//  Übersetzungen", "Beispiele. Eigene Antworten sind richtig…") goes into `samples`, never into
//  the key: the check must not mark a different good answer wrong.
//
//  Pure and PDFKit-free like `WorksheetParser`, so the probe and the tests feed it lines.
//

import CoreGraphics
import Foundation

nonisolated struct WorksheetKeyReading: Equatable, Sendable {
    /// Answer key → the teacher's answer: what the check compares against.
    var key: [String: String] = [:]
    /// Answer key → an example answer. Shown and given to the tutor; never grades.
    var samples: [String: String] = [:]
    /// One line per exercise found in the key, in order.
    var exercises: [Exercise] = []
    /// Answers that found no place to go: "Übung 11 · 1 richtig".
    var unmatched: [String] = []

    struct Exercise: Equatable, Sendable {
        var number: Int
        /// The exercise's page, when one carries this number.
        var page: Int?
        var answers: Int
        var placed: Int
        var isSample: Bool
    }

    var isEmpty: Bool { key.isEmpty && samples.isEmpty }
}

nonisolated enum WorksheetKeyReader {

    static func read(pages: [WorksheetPageText], exercises: [WorksheetExercise]) -> WorksheetKeyReading {
        var reading = WorksheetKeyReading()
        let byNumber = exerciseNumbers(exercises)
        for page in pages {
            for block in blocks(on: page) {
                place(block, exercise: byNumber[block.number], into: &reading)
            }
        }
        return reading
    }

    // MARK: - Blocks

    struct Block: Equatable {
        var number: Int
        var answers: [(number: Int, text: String)]
        var isSample: Bool

        static func == (a: Block, b: Block) -> Bool {
            a.number == b.number && a.isSample == b.isSample
                && a.answers.map(\.number) == b.answers.map(\.number) && a.answers.map(\.text) == b.answers.map(\.text)
        }
    }

    private static let header = #"^(?:Übung|Aufgabe)(?:en)?\s+0*(\d{1,3})\s*$"#
    private static let answer = #"^(\d{1,3})\s+(.+)$"#
    private static let sampleMarkers = ["mögliche", "beispiel", "sinngleiche", "eigene antworten", "z. b.", "zum beispiel"]

    /// The key blocks of one page, or none when it isn't a key page.
    static func blocks(on page: WorksheetPageText) -> [Block] {
        let lines = page.lines.map { line -> WorksheetLine in
            var cleaned = line
            cleaned.text = WorksheetText.collapse(line.text.trimmingCharacters(in: .whitespacesAndNewlines))
            return cleaned
        }.filter { !$0.text.isEmpty }
        guard let titleIndex = lines.firstIndex(where: { $0.text.range(of: #"^Lösung(?:en)?\b"#, options: .regularExpression) != nil
                                                         && !$0.text.contains(":") })
        else { return [] }
        let title = lines[titleIndex]
        let headers = lines.enumerated().compactMap { index, line -> (Int, WorksheetLine, Int)? in
            guard let number = firstNumber(header, in: line.text) else { return nil }
            return (index, line, number)
        }

        // "Lösungen · Übung 09" with no block header under it: the whole page is that exercise.
        guard !headers.isEmpty else {
            let numbers = titleNumbers(title.text)
            guard numbers.count == 1 else { return [] }
            let rest = lines.enumerated().filter { $0.offset != titleIndex }.map(\.element)
            return [block(number: numbers[0], lines: rest)]
        }

        // Each line belongs to the header above it in its own column. With no boxes (fixtures,
        // a page PDFKit gave no geometry) it is reading order: the lines after a header.
        let hasBoxes = headers.allSatisfy { $0.1.box != .zero }
        let headerIndexes = Set(headers.map { $0.0 })
        var owned: [Int: [WorksheetLine]] = [:]
        for (index, line) in lines.enumerated() where index != titleIndex && !headerIndexes.contains(index) {
            let owner: Int?
            if hasBoxes, line.box != .zero {
                owner = columnOwner(of: line, headers: headers.map { ($0.0, $0.1.box) })
            } else {
                owner = headers.last { $0.0 < index }?.0
            }
            if let owner { owned[owner, default: []].append(line) }
        }
        return headers.map { index, _, number in block(number: number, lines: owned[index] ?? []) }
    }

    /// The header a line sits under: above it, starting left of it, and of those the rightmost
    /// column, then the nearest one up. PDF space: y grows upwards.
    private static func columnOwner(of line: WorksheetLine, headers: [(index: Int, box: CGRect)]) -> Int? {
        var best: (index: Int, box: CGRect)?
        for header in headers {
            guard header.box.midY > line.box.midY, header.box.minX <= line.box.minX + 12 else { continue }
            guard let current = best else { best = header; continue }
            if header.box.minX > current.box.minX + 1
                || (abs(header.box.minX - current.box.minX) <= 1 && header.box.midY < current.box.midY) {
                best = header
            }
        }
        return best?.index
    }

    private static func block(number: Int, lines: [WorksheetLine]) -> Block {
        var answers: [(Int, String)] = []
        var isSample = false
        for line in lines {
            if let match = WorksheetText.firstMatch(answer, in: line.text) {
                let ns = line.text as NSString
                if let n = Int(ns.substring(with: match.range(at: 1))) {
                    answers.append((n, ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }
            let lowered = line.text.lowercased()
            if sampleMarkers.contains(where: { lowered.contains($0) }) { isSample = true }
        }
        return Block(number: number, answers: answers.map { (number: $0.0, text: $0.1) }, isSample: isSample)
    }

    // MARK: - Placing

    /// Places a block's answers. Only a block whose every answer found its blank goes into the
    /// key: when some don't, the parser has likely read the page's layout wrong (a two-column
    /// table), and the ones that did land may sit in the wrong blank, so the whole block is kept as
    /// samples, a reference that never marks anything wrong.
    private static func place(_ block: Block, exercise: WorksheetExercise?, into reading: inout WorksheetKeyReading) {
        var found = WorksheetKeyReading()
        placeAll(block, exercise: exercise, into: &found)
        let complete = found.exercises.first.map { $0.placed == $0.answers } ?? false
        if complete {
            reading.key.merge(found.key) { _, new in new }
        } else {
            reading.samples.merge(found.key) { _, new in new }
        }
        reading.samples.merge(found.samples) { _, new in new }
        reading.unmatched += found.unmatched
        reading.exercises += found.exercises.map { exercise in
            var marked = exercise
            marked.isSample = exercise.isSample || !complete
            return marked
        }
    }

    private static func placeAll(_ block: Block, exercise: WorksheetExercise?, into reading: inout WorksheetKeyReading) {
        var placed = 0
        for (number, text) in block.answers {
            guard let exercise, let targets = targets(for: number, in: exercise), !targets.isEmpty else {
                reading.unmatched.append("Übung \(block.number) · \(number) \(text)")
                continue
            }
            let values = split(value(text), across: targets.count)
            guard let values else {
                reading.unmatched.append("Übung \(block.number) · \(number) \(text)")
                continue
            }
            var all = true
            for (target, raw) in zip(targets, values) {
                let slot: String
                let resolved: String?
                switch target {
                case .gap(let key):
                    (slot, resolved) = (key, raw)
                case .choice(let key, let options):
                    (slot, resolved) = (key, choose(raw, from: options))
                }
                guard let resolved else { all = false; continue }
                if block.isSample { reading.samples[slot] = resolved } else { reading.key[slot] = resolved }
            }
            if all { placed += 1 } else { reading.unmatched.append("Übung \(block.number) · \(number) \(text)") }
        }
        reading.exercises.append(.init(number: block.number, page: exercise?.page, answers: block.answers.count,
                                       placed: placed, isSample: block.isSample))
    }

    enum Target: Equatable {
        case gap(String)
        case choice(String, options: [String])
    }

    /// What answer number `n` fills: the gap printed "(n)" if there is one, else the item numbered
    /// n together with the unnumbered lines that follow it (an item can wrap its blank onto the
    /// next line).
    static func targets(for n: Int, in exercise: WorksheetExercise) -> [Target]? {
        let items = exercise.items
        let numbered = items.flatMap(\.gaps).filter { $0.number == n }
        if !numbered.isEmpty { return numbered.map { .gap($0.key) } }

        guard let start = items.firstIndex(where: { $0.label.flatMap(Int.init) == n }) else { return nil }
        var group = [items[start]]
        for item in items[(start + 1)...] {
            if item.label.flatMap(Int.init) != nil { break }
            group.append(item)
        }
        return group.flatMap { item -> [Target] in
            item.segments.compactMap { segment in
                switch segment {
                case .gap(let gap): .gap(gap.key)
                case .choice(let choice): .choice(choice.key, options: choice.options.map(\.text))
                default: nil
                }
            }
        }
    }

    /// The answer as the learner would write it: "C · error analysis" is the letter C (the part
    /// after the dot only says what C was); "falsch: Git ist erforderlich." is "falsch".
    static func value(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let match = WorksheetText.firstMatch(#"^([A-Z])\s*·\s*\S"#, in: trimmed) {
            return (trimmed as NSString).substring(with: match.range(at: 1))
        }
        if let match = WorksheetText.firstMatch(#"(?i)^(richtig|falsch)\s*:"#, in: trimmed) {
            return (trimmed as NSString).substring(with: match.range(at: 1))
        }
        return trimmed
    }

    /// One value per target. Several blanks on one numbered line take "a / b" in order.
    private static func split(_ value: String, across count: Int) -> [String]? {
        if count == 1 { return [value] }
        let parts = value.components(separatedBy: " / ").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count == count ? parts : nil
    }

    /// The printed option the answer names: the same text, or R/F for richtig/falsch.
    private static func choose(_ value: String, from options: [String]) -> String? {
        let wanted = normalize(value)
        if let exact = options.first(where: { normalize($0) == wanted }) { return exact }
        let initial = wanted.prefix(1)
        guard ["richtig", "falsch", "wahr", "true", "false"].contains(wanted) else { return nil }
        let hits = options.filter { normalize($0).prefix(1) == initial }
        return hits.count == 1 ? hits[0] : nil
    }

    /// How an answer is compared with the key: case, spacing and punctuation (except "-") ignored;
    /// ä, ö, ü and ß stay distinct. `WorksheetKeyCheck` compares with the same.
    static func normalize(_ text: String) -> String {
        let folded = text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "-")))
            .joined()
        return WorksheetText.collapse(folded)
    }

    /// A diffable summary: "key = answer" and "key ≈ example", sorted. What
    /// `scripts/worksheet_probe.sh <pdf> --key-signature` prints, and what the real-PDF test
    /// compares the iOS reading with.
    static func signature(_ reading: WorksheetKeyReading) -> String {
        (reading.key.map { "\($0.key) = \($0.value)" } + reading.samples.map { "\($0.key) ≈ \($0.value)" })
            .sorted()
            .joined(separator: "\n")
    }

    // MARK: - Numbers

    /// Exercise number → exercise, from titles like "Übung 01 · Fachwörter zuordnen".
    static func exerciseNumbers(_ exercises: [WorksheetExercise]) -> [Int: WorksheetExercise] {
        var out: [Int: WorksheetExercise] = [:]
        for exercise in exercises where exercise.verdict != .notExercise {
            guard let n = firstNumber(#"^(?:Übung|Aufgabe)\s+0*(\d{1,3})\b"#, in: exercise.title), out[n] == nil else { continue }
            out[n] = exercise
        }
        return out
    }

    /// "Lösungen · Übungen 01 und 02" → [1, 2]; "Lösungen · Übung 09" → [9].
    static func titleNumbers(_ title: String) -> [Int] {
        guard let match = WorksheetText.firstMatch(#"(?:Übung|Aufgabe)(?:en)?\s+([\d\s,und–-]+)"#, in: title) else { return [] }
        let run = (title as NSString).substring(with: match.range(at: 1))
        return run.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
    }

    private static func firstNumber(_ pattern: String, in text: String) -> Int? {
        guard let match = WorksheetText.firstMatch(pattern, in: text) else { return nil }
        return Int((text as NSString).substring(with: match.range(at: 1)))
    }
}
