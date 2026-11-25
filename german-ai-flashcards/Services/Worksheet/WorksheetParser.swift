//
//  WorksheetParser.swift
//  german-ai-flashcards
//
//  Reads a teacher's exercise sheet — a slide deck exported to PDF — into exercises the learner can
//  work in the app: the sheet's title and instruction, its numbered items, and in each item the
//  blanks ("___"), the inline choices ("der / den"), and the answer lines. Nothing here is tied to
//  one teacher: the rules are the shapes German worksheets share (an imperative instruction, a
//  numbered list, underscores for a gap, a word bank set off with " · ", lettered options for
//  matching, "A: …" sections whose numbering restarts). See docs/WORKSHEETS.md.
//
//  Pure Foundation + CoreGraphics on purpose: `scripts/worksheet_probe.sh` compiles this file on
//  the Mac against a real PDF, and the tests feed it synthesized lines. The PDFKit side (lines,
//  their boxes, a gap's rectangle) is `WorksheetPDFReader`. A page is re-parsed whenever it is
//  shown or exported, never stored: iOS and macOS PDFKit can order a page's text differently, so a
//  stored range would point at the wrong characters on the other device. Answers are keyed by what
//  is printed (section letter, item number, the "(3)" before a gap), which both read the same.
//
//  `nonisolated` because the target defaults to the main actor and a 38-page parse belongs off it.
//

import CoreGraphics
import Foundation

// MARK: - Input

/// One line of a page's text: what it says, where those characters sit in the page's `string`
/// (UTF-16, which is what PDFKit's ranges count), and its box on the page.
nonisolated struct WorksheetLine: Hashable, Sendable {
    var text: String
    var range: NSRange
    /// Page space in points, origin bottom-left as PDF has it. `.zero` when unknown; the parser
    /// then keeps the given order and treats nothing as "close below".
    var box: CGRect = .zero
}

nonisolated struct WorksheetPageText: Sendable {
    /// 1-based, the number the learner and the teacher see.
    var number: Int
    var lines: [WorksheetLine]
}

// MARK: - Output

nonisolated enum WorksheetVerdict: String, Codable, Sendable {
    /// Gaps, choices, marking or answer lines the app can offer as controls.
    case interactive
    /// An exercise the app can't model: the learner writes on the slide.
    case writeOnly
    /// An explanation, a table, a title page.
    case notExercise
}

nonisolated enum WorksheetMarkStyle: String, Codable, Sendable {
    /// "Markiere …"
    case highlight
    /// "Unterstreiche …"
    case underline
}

/// Where a gap's candidate answers come from, when the sheet names them.
nonisolated enum WorksheetOptions: Hashable, Sendable {
    /// Named in the instruction: "Ergänze dem, der oder den."
    case closedSet([String])
    /// Listed on the sheet: "Drucker · USB-Stick · Netzteil". `usedOnce` when the sheet says
    /// "Jedes Wort passt einmal", so a used chip can step back.
    case wordBank([String], usedOnce: Bool)
    /// Matching: "A keyboard", "B laptop" … the learner writes the letter.
    case letters([WorksheetLetterOption])
    /// "Ergänze den (bestimmten) Artikel" without naming them.
    case articles([String])

    var choices: [String] {
        switch self {
        case .closedSet(let words), .articles(let words): words
        case .wordBank(let words, _): words
        case .letters(let options): options.map(\.letter)
        }
    }

    var usedOnce: Bool {
        if case .wordBank(_, let once) = self { return once }
        return false
    }
}

nonisolated struct WorksheetLetterOption: Hashable, Sendable {
    var letter: String
    var text: String
}

nonisolated struct WorksheetGap: Hashable, Sendable {
    var key: String
    /// The "(3)" printed before the gap, in dialogs and letters.
    var number: Int?
    /// The underscore run in the page's `string`.
    var range: NSRange
    var length: Int
    /// A writing line ("ein Salat: ________________") rather than a slot for one word.
    var isLong: Bool
}

nonisolated struct WorksheetChoiceOption: Hashable, Sendable {
    var text: String
    var range: NSRange
}

/// "der / den", "R / F", "A speichern B löschen": the learner picks one; the export strikes the
/// others, the way teachers mark it by hand.
nonisolated struct WorksheetChoice: Hashable, Sendable {
    var key: String
    var options: [WorksheetChoiceOption]
}

nonisolated enum WorksheetSegment: Hashable, Sendable {
    case text(String, range: NSRange)
    case gap(WorksheetGap)
    case choice(WorksheetChoice)
    case lineBreak
}

/// A word of an item's printed text, for "Markiere …" and "Unterstreiche …".
nonisolated struct WorksheetWord: Hashable, Sendable {
    var text: String
    var range: NSRange
}

nonisolated struct WorksheetItem: Hashable, Sendable, Identifiable {
    var key: String
    /// The printed number ("1"), or a speaker ("A", "Alex") in a dialog.
    var label: String?
    var segments: [WorksheetSegment]
    /// A trailing "(Ort)", "(der Regen)", "(wegen des Windes)".
    var hint: String?
    /// The answer goes on a ruled line under the item, which the PDF draws as a graphic and so
    /// has no text: "Bilde ganze Sätze", "Verbinde die Sätze".
    var writeBelow: Bool
    var marks: WorksheetMarkStyle?
    /// "Notiere den Fall der Lücke": each gap also takes a case.
    var caseTag: Bool
    /// "Ich / kaufe / Brot / für / ___ Salat.": the words to build the sentence from.
    var chunks: [String]?
    /// The union of the item's lines.
    var box: CGRect
    /// The item as plain text, gaps as "___": what an answer is re-keyed by if a later parser
    /// version numbers things differently.
    var anchor: String

    var id: String { key }
    var writeKey: String { key + ".w" }
    var markKey: String { key + ".m" }

    var gaps: [WorksheetGap] {
        segments.compactMap { if case .gap(let gap) = $0 { gap } else { nil } }
    }

    var choices: [WorksheetChoice] {
        segments.compactMap { if case .choice(let choice) = $0 { choice } else { nil } }
    }

    /// The printed words, in order; a mark is stored as indexes into this.
    var words: [WorksheetWord] {
        segments.flatMap { segment -> [WorksheetWord] in
            guard case .text(let text, let range) = segment else { return [] }
            return WorksheetText.words(in: text, base: range.location)
        }
    }

    /// A line of text with nothing to answer: a letter's greeting, a column header.
    var isContext: Bool { gaps.isEmpty && choices.isEmpty && !writeBelow && marks == nil }
}

nonisolated struct WorksheetSection: Hashable, Sendable, Identifiable {
    /// "s0" for a page without sections, else "sA", "sB" from the printed letter.
    var key: String
    /// "Setze die Gruppen in den Dativ mit „mit“." for an "A: …" section.
    var heading: String?
    var options: WorksheetOptions?
    var items: [WorksheetItem]

    var id: String { key }
}

nonisolated struct WorksheetExercise: Hashable, Sendable, Identifiable {
    var page: Int
    var verdict: WorksheetVerdict
    var title: String
    var subtitle: String?
    var instruction: String?
    var sections: [WorksheetSection]
    /// "Nomen: das Brot, die Suppe, …" — the sheet's own article + noun list.
    var nouns: [String]
    /// Lines under the exercise: tips, "Lösungen: Folie 36."
    var notes: [String]
    /// "Folie 36" when the sheet says where its answers are.
    var answerKeyRef: String?
    /// The text layer already holds answers typed in during class (a filled-in copy), so the
    /// setup screen starts this page unticked.
    var hasTypedAnswers: Bool

    var id: Int { page }
    var items: [WorksheetItem] { sections.flatMap(\.items) }
    var isExercise: Bool { verdict != .notExercise }

    /// Everything the learner can answer on the page, for "3 of 8 done".
    var answerKeys: [String] {
        items.flatMap { item -> [String] in
            var keys = item.gaps.map(\.key) + item.choices.map(\.key)
            if item.writeBelow { keys.append(item.writeKey) }
            if item.marks != nil { keys.append(item.markKey) }
            return keys
        }
    }

    /// "DATIV D1: ARTIKEL ERGÄNZEN" reads better as "Dativ D1: Artikel ergänzen" in a list.
    var displayTitle: String { WorksheetText.softenCaps(title) }
}

// MARK: - Parser

nonisolated enum WorksheetParser {

    /// Bump when keys or segmentation change, so stored answers know to re-key by anchor text.
    static let version = 1

    /// Every page, exercise or not, in page order.
    static func parse(_ pages: [WorksheetPageText]) -> [WorksheetExercise] {
        let chrome = chrome(in: pages)
        return pages.map { parsePage($0, chrome: chrome) }
    }

    /// Lines that repeat on at least half the pages of a longer document: the running header,
    /// the footer, the copyright. Digits count as one so "Folie 3" and "Folie 4" match.
    static func chrome(in pages: [WorksheetPageText]) -> Set<String> {
        guard pages.count >= 4 else { return [] }
        var counts: [String: Int] = [:]
        for page in pages {
            for key in Set(page.lines.map { chromeKey($0.text) }) where !key.isEmpty {
                counts[key, default: 0] += 1
            }
        }
        let threshold = (pages.count + 1) / 2
        return Set(counts.filter { $0.value >= threshold }.map(\.key))
    }

    static func chromeKey(_ text: String) -> String {
        let digitsFolded = text.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
        return digitsFolded.lowercased()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: One page

    static func parsePage(_ page: WorksheetPageText, chrome: Set<String>) -> WorksheetExercise {
        let lines = arrange(page.lines.filter { line in
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.contains(where: { $0 != "\u{FFFC}" }) else { return false }
            return !chrome.contains(chromeKey(line.text))
        })
        var builder = PageBuilder(page: page.number, lines: lines)
        return builder.build()
    }

    /// Reading order from the boxes: top to bottom by rows, left to right within a row, a lone
    /// "1." merged into the text beside it, and a line PDFKit ran across two columns split in two.
    static func arrange(_ lines: [WorksheetLine]) -> [WorksheetLine] {
        let split = lines.flatMap(splitColumns)
        guard split.contains(where: { $0.box != .zero }) else { return split }
        let sorted = split.sorted { $0.box.midY > $1.box.midY }
        var rows: [[WorksheetLine]] = []
        for line in sorted {
            if let last = rows.last?.first,
               abs(last.box.midY - line.box.midY) < 0.45 * max(min(last.box.height, line.box.height), 1) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        var out: [WorksheetLine] = []
        for row in rows {
            var pending: WorksheetLine?
            for line in row.sorted(by: { $0.box.minX < $1.box.minX }) {
                if let label = pending {
                    out.append(mergeLabel(label, into: line))
                    pending = nil
                } else if WorksheetText.isLabelOnly(line.text) {
                    pending = line
                } else {
                    out.append(line)
                }
            }
            if let pending { out.append(pending) }
        }
        return out
    }

    /// "1." and "Ich esse …" as two runs on one baseline become one line. The label's own range
    /// is dropped: only the content's characters are ever located on the page.
    private static func mergeLabel(_ label: WorksheetLine, into line: WorksheetLine) -> WorksheetLine {
        let labelText = label.text.trimmingCharacters(in: .whitespaces)
        var merged = line
        merged.text = labelText + " " + line.text
        merged.range = NSRange(location: line.range.location - (labelText as NSString).length - 1,
                               length: (merged.text as NSString).length)
        merged.box = label.box.union(line.box)
        return merged
    }

    /// "1. ___ Salat schmeckt gut. 5. Ich lege …" — two columns read as one line — split at the
    /// second number. Only when the line starts with a number itself and the later one is higher.
    private static func splitColumns(_ line: WorksheetLine) -> [WorksheetLine] {
        let ns = line.text as NSString
        guard let first = WorksheetText.firstMatch(#"^\s*(\d{1,2})[.)]\s"#, in: line.text),
              let firstNumber = Int(ns.substring(with: first.range(at: 1))) else { return [line] }
        let later = WorksheetText.matches(#"\s(\d{1,2})[.)]\s"#, in: line.text)
            .filter { $0.range.location > first.range.upperBound }
        guard let cut = later.first(where: { (Int(ns.substring(with: $0.range(at: 1))) ?? 0) > firstNumber })
        else { return [line] }
        let leftLength = cut.range.location
        let rightStart = cut.range.location + 1
        var left = line
        left.text = ns.substring(to: leftLength)
        left.range = NSRange(location: line.range.location, length: leftLength)
        var right = line
        right.text = ns.substring(from: rightStart)
        right.range = NSRange(location: line.range.location + rightStart, length: ns.length - rightStart)
        if line.box != .zero {
            // No per-character boxes here; halve the line so the rows still sort.
            let share = CGFloat(leftLength) / CGFloat(max(ns.length, 1))
            left.box = CGRect(x: line.box.minX, y: line.box.minY,
                              width: line.box.width * share, height: line.box.height)
            right.box = CGRect(x: line.box.minX + line.box.width * share, y: line.box.minY,
                               width: line.box.width * (1 - share), height: line.box.height)
        }
        return [left] + splitColumns(right)
    }
}

// MARK: - Building one page

/// A line already assigned to an item, before it becomes segments.
private nonisolated struct RawLine {
    var line: WorksheetLine
    /// Where the item's content starts in `line.text` (after "1." or "Alex:"), UTF-16.
    var contentOffset: Int
    /// "A speichern B löschen" under an item: the whole line is one choice.
    var isChoiceLine = false
}

private nonisolated struct RawItem {
    var label: String?
    var labelKind: WorksheetText.LabelKind?
    var lines: [RawLine]
}

private nonisolated struct RawSection {
    var letter: String?
    var heading: String?
    var items: [RawItem] = []
}

private nonisolated struct PageBuilder {
    let page: Int
    let lines: [WorksheetLine]

    var title: String?
    var subtitle: String?
    var instruction: String?
    var sections: [RawSection] = [RawSection()]
    var wordBank: [String] = []
    var letterLines: Set<Int> = []
    var letters: [WorksheetLetterOption] = []
    var notes: [String] = []
    var nouns: [String] = []
    var answerKeyRef: String?

    init(page: Int, lines: [WorksheetLine]) {
        self.page = page
        self.lines = lines
    }

    mutating func build() -> WorksheetExercise {
        findLetterOptions()
        let lastItemLine = lines.lastIndex { line in
            let label = WorksheetText.label(of: line.text)
            return label?.kind == .number || WorksheetText.hasGap(line.text)
        }
        var sawItem = false

        for (index, line) in lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if letterLines.contains(index) { continue }

            if let nounList = WorksheetText.nounList(in: text) {
                nouns += nounList
                notes.append(text)
                answerKeyRef = answerKeyRef ?? WorksheetText.answerKeyRef(in: text)
                continue
            }
            if let ref = WorksheetText.answerKeyRef(in: text) {
                answerKeyRef = answerKeyRef ?? ref
                notes.append(text)
                continue
            }

            let label = WorksheetText.label(of: text)
            let hasGap = WorksheetText.hasGap(text)
            let isItemish = label?.kind == .number || hasGap

            if title == nil, !isItemish, !WorksheetText.isInstruction(text) {
                title = text
                continue
            }
            if let header = WorksheetText.sectionHeader(text) {
                startSection(letter: header.letter, heading: header.heading)
                continue
            }
            if !sawItem, !isItemish, WorksheetText.isInstruction(text) {
                instruction = instruction.map { $0 + " " + text } ?? text
                continue
            }
            if !sawItem, instruction == nil, subtitle == nil, !isItemish {
                subtitle = text
                continue
            }
            if !sawItem, instruction != nil, let bank = WorksheetText.wordBank(in: text) {
                wordBank += bank
                continue
            }
            if WorksheetText.isChoiceLine(text), var item = sections[sections.count - 1].items.last {
                item.lines.append(RawLine(line: line, contentOffset: 0, isChoiceLine: true))
                sections[sections.count - 1].items[sections[sections.count - 1].items.count - 1] = item
                continue
            }

            if let label, label.kind == .number {
                sawItem = true
                appendItem(RawItem(label: label.text, labelKind: label.kind,
                                   lines: [RawLine(line: line, contentOffset: label.contentOffset)]))
                continue
            }
            if hasGap {
                // A line of only underscores right under an item is that item's answer line.
                if WorksheetText.isOnlyGap(text), let target = continuationTarget(for: line, reach: 2) {
                    append(RawLine(line: line, contentOffset: 0), toItem: target)
                    continue
                }
                sawItem = true
                let speaker = label.flatMap { $0.kind == .speaker || $0.kind == .letter ? $0 : nil }
                appendItem(RawItem(label: speaker?.text, labelKind: speaker?.kind,
                                   lines: [RawLine(line: line, contentOffset: speaker?.contentOffset ?? 0)]))
                continue
            }
            // A plain line. Under an item and close to it: more of that item ("Das ist …").
            // After the last item and further down: a note. Otherwise context (a greeting, a
            // column header) that stays on screen without asking for anything.
            if sawItem, let target = continuationTarget(for: line) {
                append(RawLine(line: line, contentOffset: 0), toItem: target)
            } else if let lastItemLine, index > lastItemLine,
                      !(lastLine.map { isClose(line, below: $0) } ?? false) {
                notes.append(text)
            } else if instruction != nil || sawItem {
                appendItem(RawItem(label: nil, labelKind: nil, lines: [RawLine(line: line, contentOffset: 0)]))
            } else {
                notes.append(text)
            }
        }
        return finish()
    }

    // MARK: Assembly

    private var lastLine: WorksheetLine? {
        sections.last?.items.last?.lines.last?.line
    }

    /// Directly under `previous`: less than one line height of space between them. Without
    /// boxes nothing is close.
    /// `reach` is in line heights: 0.9 for more text, more for an answer line, which teachers
    /// set off with some room to write.
    private func isClose(_ line: WorksheetLine, below previous: WorksheetLine, reach: CGFloat = 0.9) -> Bool {
        guard line.box != .zero, previous.box != .zero else { return false }
        let space = previous.box.minY - line.box.maxY
        return space > -line.box.height * 0.5 && space < max(previous.box.height, line.box.height) * reach
    }

    private mutating func startSection(letter: String, heading: String) {
        if sections.count == 1, sections[0].items.isEmpty, sections[0].letter == nil {
            sections[0] = RawSection(letter: letter, heading: heading)
        } else {
            sections.append(RawSection(letter: letter, heading: heading))
        }
    }

    private mutating func appendItem(_ item: RawItem) {
        sections[sections.count - 1].items.append(item)
    }

    private mutating func append(_ line: RawLine, toItem index: Int) {
        sections[sections.count - 1].items[index].lines.append(line)
    }

    /// The numbered item this line continues: one whose last line sits directly above it in the
    /// same column. Searching every item rather than the last one is what keeps a two-column
    /// sheet ("1 Nenne ein Gerät." beside "2 Sage, …", each with its starter and answer line
    /// underneath) from handing the left column's lines to the right column's item.
    private func continuationTarget(for line: WorksheetLine, reach: CGFloat = 0.9) -> Int? {
        let items = sections[sections.count - 1].items
        for index in items.indices.reversed() where items[index].labelKind == .number {
            guard let last = items[index].lines.last?.line else { continue }
            let overlaps = line.box.minX < last.box.maxX && line.box.maxX > last.box.minX
            if overlaps, isClose(line, below: last, reach: reach) { return index }
        }
        return nil
    }

    /// "A keyboard", "B laptop", "C screen / monitor" … — three or more lines whose letters run
    /// A, B, C with nothing to fill in: the options of a matching exercise.
    private mutating func findLetterOptions() {
        var found: [(index: Int, option: WorksheetLetterOption)] = []
        for (index, line) in lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !WorksheetText.hasGap(text), !WorksheetText.isChoiceLine(text),
                  let label = WorksheetText.label(of: text), label.kind == .letter else { continue }
            let rest = (text as NSString).substring(from: label.contentOffset)
                .trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty else { continue }
            found.append((index, WorksheetLetterOption(letter: label.text, text: rest)))
        }
        let sorted = found.sorted { $0.option.letter < $1.option.letter }
        let expected = sorted.indices.map { String(UnicodeScalar(UInt8(65 + $0))) }
        guard sorted.count >= 3, sorted.map(\.option.letter) == expected else { return }
        letterLines = Set(sorted.map(\.index))
        letters = sorted.map(\.option)
    }

    private func finish() -> WorksheetExercise {
        let pageInstruction = instruction ?? sections.first?.heading
        let usedOnce = (pageInstruction ?? "").range(of: "einmal", options: .caseInsensitive) != nil

        var builtSections: [WorksheetSection] = []
        for (sectionIndex, raw) in sections.enumerated() {
            let sectionKey = raw.letter.map { "s" + $0 } ?? "s\(sectionIndex)"
            let directions = [instruction, raw.heading].compactMap { $0 }.joined(separator: " ")
            // The most specific source wins: what this section's heading names, what the page's
            // instruction names, a printed word bank, lettered options, then "den Artikel".
            let options: WorksheetOptions?
            let fromHeading: [String]? = raw.heading.flatMap { WorksheetText.closedSet($0) }
            let fromInstruction: [String]? = instruction.flatMap { WorksheetText.closedSet($0) }
            if let named = fromHeading ?? fromInstruction {
                options = .closedSet(named)
            } else if !wordBank.isEmpty {
                options = .wordBank(wordBank, usedOnce: usedOnce)
            } else if !letters.isEmpty {
                options = .letters(letters)
            } else {
                options = WorksheetText.articleSet(directions: directions, subtitle: subtitle)
            }
            let marks = WorksheetText.markStyle(in: directions)
            let caseTag = WorksheetText.asksForCase(directions)
            let writes = WorksheetText.asksForSentences(directions)
            let hasUnderscores = lines.contains { $0.text.contains("__") }
            // "…" is a blank only on a sheet that says what to do and has no underscores at all;
            // anywhere else it is an ellipsis ("mit, nach, zu …" on an overview slide).
            let ellipsisGaps = !hasUnderscores && pageInstruction != nil

            var unlabeled = 0
            var items = raw.items.map { rawItem -> WorksheetItem in
                let itemKey: String
                if let label = rawItem.label, rawItem.labelKind == .number {
                    itemKey = "p\(page).\(sectionKey).i\(label)"
                } else {
                    itemKey = "p\(page).\(sectionKey).r\(unlabeled)"
                    unlabeled += 1
                }
                return buildItem(rawItem, key: itemKey, sectionKey: sectionKey,
                                 marks: marks, caseTag: caseTag, writes: writes,
                                 ellipsisGaps: ellipsisGaps)
            }
            // Two columns read row by row (1, 5, 2, 6 …); the printed numbers are the order.
            let numbers = items.compactMap { item in item.label.flatMap(Int.init) }
            if numbers.count == items.count, Set(numbers).count == numbers.count {
                items.sort { Int($0.label ?? "") ?? 0 < Int($1.label ?? "") ?? 0 }
            }
            builtSections.append(WorksheetSection(key: sectionKey, heading: raw.heading,
                                                  options: options, items: items))
        }

        let items = builtSections.flatMap(\.items)
        let answerable = items.filter { !$0.isContext }
        let numbered = items.filter { $0.label.flatMap(Int.init) != nil }
        let verdict: WorksheetVerdict
        let underscoreItems = items.filter { item in item.gaps.contains { $0.length >= 2 && $0.length != 3 || $0.isLong } || item.gaps.count > 0 && lines.contains { $0.text.contains("__") } }
        if !answerable.isEmpty, pageInstruction != nil || underscoreItems.count >= 2 {
            verdict = .interactive
        } else if pageInstruction != nil, numbered.count >= 2 {
            verdict = .writeOnly
        } else {
            verdict = .notExercise
        }

        let withGaps = items.filter { !$0.gaps.isEmpty }
        let typed = withGaps.filter(WorksheetText.carriesTypedAnswer)
        let hasTypedAnswers = !withGaps.isEmpty && typed.count * 2 >= withGaps.count

        return WorksheetExercise(
            page: page,
            verdict: verdict,
            title: title ?? "Seite \(page)",
            subtitle: subtitle,
            instruction: pageInstruction,
            sections: verdict == .notExercise ? [] : builtSections,
            nouns: nouns,
            notes: notes,
            answerKeyRef: answerKeyRef,
            hasTypedAnswers: hasTypedAnswers
        )
    }

    private func buildItem(
        _ raw: RawItem,
        key: String,
        sectionKey: String,
        marks: WorksheetMarkStyle?,
        caseTag: Bool,
        writes: Bool,
        ellipsisGaps: Bool
    ) -> WorksheetItem {
        var segments: [WorksheetSegment] = []
        var gapIndex = 0
        var choiceIndex = 0
        var anchorParts: [String] = []
        var box = CGRect.null

        // Pieces per line first, so the whole item can settle what is a gap and what a choice:
        // an item with a real blank ("9 faulty / broken" + "____") is answered in the blank, so its
        // slash is a gloss, not a choice; and an item with a choice ("Ich möchte sie …" over
        // "A speichern B löschen") is answered by the choice, so its "…" is just text.
        let piecesPerLine: [[WorksheetText.Piece]?] = raw.lines.map { rawLine in
            guard !rawLine.isChoiceLine else { return nil }
            let ns = rawLine.line.text as NSString
            let content = ns.substring(from: min(rawLine.contentOffset, ns.length))
            return WorksheetText.segments(of: content, base: rawLine.line.range.location + rawLine.contentOffset,
                                          ellipsisGaps: ellipsisGaps)
        }
        let allPieces = piecesPerLine.compactMap { $0 }.flatMap { $0 }
        let hasBlank = allPieces.contains { if case .gap(_, _, _, false) = $0 { true } else { false } }
        let hasChoice = raw.lines.contains(where: \.isChoiceLine)
            || (!hasBlank && allPieces.contains { if case .choice = $0 { true } else { false } })

        for (lineIndex, rawLine) in raw.lines.enumerated() {
            if lineIndex > 0 { segments.append(.lineBreak) }
            box = box.union(rawLine.line.box)
            let ns = rawLine.line.text as NSString
            let content = ns.substring(from: min(rawLine.contentOffset, ns.length))
            let base = rawLine.line.range.location + rawLine.contentOffset

            if rawLine.isChoiceLine, let options = WorksheetText.choiceLineOptions(content, base: base) {
                segments.append(.choice(WorksheetChoice(key: "\(key).c\(choiceIndex)", options: options)))
                choiceIndex += 1
                anchorParts.append(options.map(\.text).joined(separator: " / "))
                continue
            }
            let pieces = (piecesPerLine[lineIndex] ?? []).map { piece -> WorksheetText.Piece in
                switch piece {
                case .choice(let options) where hasBlank:
                    return WorksheetText.textPiece(spanning: options, in: content, base: base)
                case .gap(_, let range, _, true) where hasChoice:
                    return .text((content as NSString).substring(with: NSRange(location: range.location - base,
                                                                               length: range.length)),
                                 range: range)
                default:
                    return piece
                }
            }
            for piece in pieces {
                switch piece {
                case .text(let text, let range):
                    segments.append(.text(text, range: range))
                    anchorParts.append(text)
                case .gap(let number, let range, let length, _):
                    let gapKey: String
                    if let printed = number {
                        gapKey = "p\(page).\(sectionKey).n\(printed)"
                    } else {
                        gapKey = "\(key).g\(gapIndex)"
                    }
                    segments.append(.gap(WorksheetGap(key: gapKey, number: number, range: range,
                                                      length: length, isLong: length >= 10)))
                    gapIndex += 1
                    anchorParts.append("___")
                case .choice(let options):
                    segments.append(.choice(WorksheetChoice(key: "\(key).c\(choiceIndex)", options: options)))
                    choiceIndex += 1
                    anchorParts.append(options.map(\.text).joined(separator: " / "))
                }
            }
        }

        let anchor = WorksheetText.collapse(([raw.label].compactMap { $0 } + anchorParts).joined(separator: " "))
        let isNumbered = raw.labelKind == .number
        let gaps = segments.filter { if case .gap = $0 { true } else { false } }
        let hasLongGap = segments.contains { if case .gap(let gap) = $0 { gap.isLong } else { false } }
        let chunks = WorksheetText.chunks(of: WorksheetText.collapse(anchorParts.joined(separator: " ")))

        return WorksheetItem(
            key: key,
            label: raw.label,
            segments: segments,
            hint: WorksheetText.trailingHint(anchor),
            writeBelow: writes && isNumbered && !hasLongGap,
            marks: isNumbered ? marks : nil,
            caseTag: caseTag && !gaps.isEmpty,
            chunks: chunks,
            box: box.isNull ? .zero : box,
            anchor: anchor
        )
    }
}

// MARK: - Text rules

/// The small rules the parser is made of, each testable on its own.
nonisolated enum WorksheetText {

    enum LabelKind: Sendable { case number, speaker, letter }

    struct Label {
        var text: String
        var kind: LabelKind
        /// Where the content starts after the label and its space, UTF-16.
        var contentOffset: Int
    }

    enum Piece {
        /// `number` is the printed "(3)", nil when unnumbered.
        case gap(number: Int?, range: NSRange, length: Int, ellipsis: Bool)
        case text(String, range: NSRange)
        case choice([WorksheetChoiceOption])
    }

    /// Imperatives a worksheet instruction starts with. Lowercased, compared per sentence.
    static let instructionVerbs: Set<String> = [
        "ergänze", "ergänzt", "wähle", "wählt", "bilde", "bildet", "setze", "setzt", "schreibe",
        "schreibt", "verbinde", "verbindet", "ordne", "ordnet", "markiere", "markiert",
        "unterstreiche", "unterstreicht", "notiere", "notiert", "lies", "lest", "korrigiere",
        "ersetze", "finde", "findet", "kreuze", "kreuzt", "beantworte", "übersetze", "sortiere",
        "trage", "fülle", "nutze", "verwende", "bringe", "forme", "kombiniere", "sprich", "höre",
        "hör", "frage", "antworte", "konjugiere", "dekliniere", "streiche",
    ]

    static let definiteArticles = ["der", "die", "das", "den", "dem", "des"]
    static let indefiniteArticles = ["ein", "eine", "einen", "einem", "einer", "eines"]

    // MARK: Lines

    static func isLabelOnly(_ text: String) -> Bool {
        firstMatch(#"^\s*(\d{1,2}[.)]?|[A-H])\s*$"#, in: text) != nil
    }

    /// "1.", "1)", "1 " → number; "A " before a gap or as a matching option → letter; "Alex:" →
    /// speaker. "A: …" is a section header, not a label; "(3)" belongs to its gap.
    static func label(of text: String) -> Label? {
        let ns = text as NSString
        if let match = firstMatch(#"^\s*(\d{1,2})(?:[.)]\s*|\s+)(?=\S)"#, in: text) {
            return Label(text: ns.substring(with: match.range(at: 1)), kind: .number,
                         contentOffset: match.range.upperBound)
        }
        if sectionHeader(text) != nil { return nil }
        if let match = firstMatch(#"^\s*([A-H])\s+(?=\S)"#, in: text) {
            return Label(text: ns.substring(with: match.range(at: 1)), kind: .letter,
                         contentOffset: match.range.upperBound)
        }
        if hasGap(text), let match = firstMatch(#"^\s*([A-ZÄÖÜ][a-zäöüß]{1,15}):\s+"#, in: text) {
            let name = ns.substring(with: match.range(at: 1))
            guard !["Nomen", "Lösung", "Lösungen", "Hinweis", "Tipp", "Beispiel", "Achtung"].contains(name)
            else { return nil }
            return Label(text: name, kind: .speaker, contentOffset: match.range.upperBound)
        }
        return nil
    }

    /// "A: Setze die Gruppen in den Dativ mit „mit“." → ("A", heading).
    static func sectionHeader(_ text: String) -> (letter: String, heading: String)? {
        guard let match = firstMatch(#"^\s*([A-H])[:.)]\s+(.+)$"#, in: text) else { return nil }
        let ns = text as NSString
        let heading = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        guard isInstruction(heading) else { return nil }
        return (ns.substring(with: match.range(at: 1)), heading)
    }

    /// Any sentence of the line starts with an imperative, or it is "Richtig oder falsch?".
    static func isInstruction(_ text: String) -> Bool {
        if text.range(of: "richtig oder falsch", options: .caseInsensitive) != nil { return true }
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?/"))
        return sentences.contains { sentence in
            let first = sentence.trimmingCharacters(in: .whitespaces)
                .split(separator: " ").first.map { String($0).lowercased() } ?? ""
            return instructionVerbs.contains(first.trimmingCharacters(in: .punctuationCharacters))
        }
    }

    static func hasGap(_ text: String) -> Bool {
        text.contains("__")
    }

    static func isOnlyGap(_ text: String) -> Bool {
        let stripped = text.replacingOccurrences(of: #"[_\s]"#, with: "", options: .regularExpression)
        return stripped.isEmpty && text.contains("__")
    }

    /// "Drucker · USB-Stick · Netzteil · Headset · Kabel": three or more short parts.
    static func wordBank(in text: String) -> [String]? {
        guard !hasGap(text) else { return nil }
        let parts = text.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 25 && $0.split(separator: " ").count <= 3 })
        else { return nil }
        return parts
    }

    /// "A speichern B löschen" (and "C …"): a choice of lettered words on a line of its own.
    static func isChoiceLine(_ text: String) -> Bool {
        firstMatch(#"^\s*A\s+\S.*?\s+B\s+\S"#, in: text) != nil && !hasGap(text)
            && firstMatch(#"^\s*A\s+\S+(?:\s\S+)?\s+B\s+\S+(?:\s\S+)?(?:\s+C\s+\S+(?:\s\S+)?)?\s*$"#, in: text) != nil
    }

    static func choiceLineOptions(_ text: String, base: Int) -> [WorksheetChoiceOption]? {
        guard let match = firstMatch(
            #"^\s*A\s+(\S+(?:\s\S+)?)\s+B\s+(\S+(?:\s\S+)?)(?:\s+C\s+(\S+(?:\s\S+)?))?\s*$"#, in: text
        ) else { return nil }
        let ns = text as NSString
        return (1...3).compactMap { group in
            let range = match.range(at: group)
            guard range.location != NSNotFound else { return nil }
            return WorksheetChoiceOption(text: ns.substring(with: range),
                                         range: NSRange(location: base + range.location, length: range.length))
        }
    }

    // MARK: Items

    /// An item's content cut into text, gaps and inline choices, with page ranges.
    static func segments(of content: String, base: Int, ellipsisGaps: Bool) -> [Piece] {
        let ns = content as NSString
        var marks: [(range: NSRange, piece: Piece)] = []

        // "(3) ____" and "____". Runs split by a space stay two gaps: a sorting table prints two
        // blanks per row that way.
        for match in matches(#"(?:\((\d{1,2})\)\s*)?(_{2,})"#, in: content) {
            let run = match.range(at: 2)
            let numberRange = match.range(at: 1)
            let number = numberRange.location != NSNotFound ? Int(ns.substring(with: numberRange)) : nil
            let underscores = ns.substring(with: run).filter { $0 == "_" }.count
            marks.append((run, .gap(number: number, range: NSRange(location: base + run.location, length: run.length),
                                    length: underscores, ellipsis: false)))
        }
        if ellipsisGaps, marks.isEmpty {
            for match in matches(#"…|\.{3,}"#, in: content) {
                marks.append((match.range, .gap(number: nil, range: NSRange(location: base + match.range.location,
                                                                            length: match.range.length),
                                                length: 3, ellipsis: true)))
            }
        }
        // "der / den", "der / die / das", "R / F" — only where "/" isn't a word separator
        // (three or more slashes is "Ich / kaufe / Brot / …").
        let slashes = content.filter { $0 == "/" }.count
        if slashes >= 1, slashes <= 2 {
            let pattern = slashes == 2
                ? #"(?<![\p{L}\p{N}])(\p{L}[\p{L}-]{0,15})[ \t]*/[ \t]*(\p{L}[\p{L}-]{0,15})[ \t]*/[ \t]*(\p{L}[\p{L}-]{0,15})(?![\p{L}\p{N}])"#
                : #"(?<![\p{L}\p{N}])(\p{L}[\p{L}-]{0,15})[ \t]*/[ \t]*(\p{L}[\p{L}-]{0,15})(?![\p{L}\p{N}])"#
            for match in matches(pattern, in: content)
            where !marks.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
                let options = (1..<match.numberOfRanges).map { group -> WorksheetChoiceOption in
                    let range = match.range(at: group)
                    return WorksheetChoiceOption(text: ns.substring(with: range),
                                                 range: NSRange(location: base + range.location, length: range.length))
                }
                marks.append((match.range, .choice(options)))
            }
        }

        marks.sort { $0.range.location < $1.range.location }
        var pieces: [Piece] = []
        var cursor = 0
        for mark in marks {
            // A gap's "(3)" stays as text before it; it's what the learner sees on her slide.
            if mark.range.location > cursor {
                let range = NSRange(location: cursor, length: mark.range.location - cursor)
                appendText(ns.substring(with: range), at: base + cursor, to: &pieces)
            }
            pieces.append(mark.piece)
            cursor = mark.range.upperBound
        }
        if cursor < ns.length {
            appendText(ns.substring(from: cursor), at: base + cursor, to: &pieces)
        }
        return pieces
    }

    /// An inline choice turned back into the text it was printed as ("faulty / broken").
    static func textPiece(spanning options: [WorksheetChoiceOption], in content: String, base: Int) -> Piece {
        guard let first = options.first, let last = options.last else { return .text("", range: NSRange()) }
        let range = NSRange(location: first.range.location, length: last.range.upperBound - first.range.location)
        let local = NSRange(location: range.location - base, length: range.length)
        return .text((content as NSString).substring(with: local), range: range)
    }

    private static func appendText(_ text: String, at location: Int, to pieces: inout [Piece]) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        pieces.append(.text(text, range: NSRange(location: location, length: (text as NSString).length)))
    }

    /// "(Ort)", "(der Regen)", "(wegen des Windes)" at the end of an item.
    static func trailingHint(_ text: String) -> String? {
        guard let match = firstMatch(#"\(([^()]{1,40})\)\s*\.?\s*$"#, in: text) else { return nil }
        let hint = (text as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        // "(4)" before a blank is the blank's number, not a hint.
        return hint.allSatisfy(\.isNumber) ? nil : hint
    }

    /// "Ich / kaufe / Brot / für / ___ Salat." → the parts, when the item is built from chunks.
    static func chunks(of text: String) -> [String]? {
        let parts = text.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 4, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return parts
    }

    /// The printed words of a text run, with page ranges.
    static func words(in text: String, base: Int) -> [WorksheetWord] {
        let ns = text as NSString
        return matches(#"[\p{L}\p{N}][\p{L}\p{N}'’-]*"#, in: text).map { match in
            WorksheetWord(text: ns.substring(with: match.range),
                          range: NSRange(location: base + match.range.location, length: match.range.length))
        }
    }

    /// AK2-style: the item's line runs on past its gap's sentence with a whole new sentence —
    /// answers typed into the slide during class.
    static func carriesTypedAnswer(_ item: WorksheetItem) -> Bool {
        guard let lastGap = item.segments.lastIndex(where: { if case .gap = $0 { true } else { false } })
        else { return false }
        let after = item.segments[(lastGap + 1)...].compactMap {
            if case .text(let text, _) = $0 { text } else { nil }
        }.joined(separator: " ")
        guard let end = after.firstIndex(where: { ".!?".contains($0) }) else { return false }
        let rest = after[after.index(after: end)...]
        return rest.split(separator: " ").filter { $0.contains(where: \.isLetter) }.count >= 3
    }

    // MARK: Directions

    /// "Ergänze dem, der oder den." → [dem, der, den]; "Setze ein, eine oder einen ein." → [ein,
    /// eine, einen].
    static func closedSet(_ instruction: String) -> [String]? {
        let verbs = "Ergänze|Ergänzt|Setze|Setzt|Wähle|Wählt|Schreibe|Nimm"
        guard let match = firstMatch(
            "(?:\(verbs))\\s+((?:\\p{L}+,\\s*)*\\p{L}+\\s+oder\\s+\\p{L}+)", in: instruction
        ) else { return nil }
        let list = (instruction as NSString).substring(with: match.range(at: 1))
        let words = list.replacingOccurrences(of: " oder ", with: ",")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard words.count >= 2, words.count <= 6, words.allSatisfy({ $0.count <= 12 }) else { return nil }
        return words
    }

    static func articleSet(directions: String, subtitle: String?) -> WorksheetOptions? {
        let text = (directions + " " + (subtitle ?? "")).lowercased()
        guard text.contains("artikel") else { return nil }
        // "bestimmten Artikel" in the instruction wins over an "UNBESTIMMTE" subtitle.
        let instruction = directions.lowercased()
        if instruction.contains("unbestimmt") { return .articles(indefiniteArticles) }
        if instruction.contains("bestimmt") { return .articles(definiteArticles) }
        return .articles(text.contains("unbestimmt") ? indefiniteArticles : definiteArticles)
    }

    static func markStyle(in directions: String) -> WorksheetMarkStyle? {
        let lower = directions.lowercased()
        if lower.contains("unterstreich") { return .underline }
        if lower.contains("markier") { return .highlight }
        return nil
    }

    static func asksForCase(_ directions: String) -> Bool {
        firstMatch(#"\b(Fall|Kasus)\b"#, in: directions) != nil
    }

    /// "Bilde ganze Sätze", "Verbinde die Sätze", "Schreibe einen Satz", "Forme … um".
    static func asksForSentences(_ directions: String) -> Bool {
        firstMatch(#"\b(Bilde|Bildet|Schreibe|Schreibt)\b[^.]*\bS[äa]tz"#, in: directions) != nil
            || firstMatch(#"\b(Verbinde|Verbindet)\b"#, in: directions) != nil
            || firstMatch(#"\b(Forme|Formt)\b[^.]*\bum\b"#, in: directions) != nil
    }

    // MARK: Footer

    /// "Nomen: das Brot, die Suppe, das Essen. Lösung: Folie 37." → the nouns.
    static func nounList(in text: String) -> [String]? {
        guard let match = firstMatch(#"^\s*(?:Nomen|Wörter|Wortschatz)\s*:\s*(.+)$"#, in: text) else { return nil }
        var list = (text as NSString).substring(with: match.range(at: 1))
        if let stop = list.range(of: #"\.\s|\.$"#, options: .regularExpression) {
            list = String(list[..<stop.lowerBound])
        }
        let nouns = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return nouns.isEmpty ? nil : nouns
    }

    static func answerKeyRef(in text: String) -> String? {
        guard let match = firstMatch(#"Lösung(?:en)?\s*:?\s*(?:auf\s+)?(Folie|Seite|S\.)\s*(\d+)"#, in: text)
        else { return nil }
        let ns = text as NSString
        return ns.substring(with: match.range(at: 1)) + " " + ns.substring(with: match.range(at: 2))
    }

    // MARK: Helpers

    static func collapse(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "DATIV D1: ARTIKEL ERGÄNZEN" → "Dativ D1: Artikel ergänzen". Mixed-case titles are kept.
    static func softenCaps(_ title: String) -> String {
        let letters = title.filter(\.isLetter)
        guard letters.count >= 4, letters.allSatisfy({ !$0.isLowercase }) else { return title }
        var first = true
        return title.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let w = String(word)
            // Codes like "D1", "AK2", "M1" stay as they are.
            if w.contains(where: \.isNumber) { return w }
            let lower = w.lowercased()
            defer { first = false }
            if first || nounLikeCaps.contains(lower.trimmingCharacters(in: .punctuationCharacters)) {
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            return lower
        }.joined(separator: " ")
    }

    /// Title words that are nouns, so they keep their capital when a shouted title is softened.
    /// Anything else reads lowercase, which is right for the verbs and adjectives titles use.
    private static let nounLikeCaps: Set<String> = [
        "akkusativ", "dativ", "genitiv", "nominativ", "artikel", "präposition", "präpositionen",
        "sätze", "satz", "formen", "form", "übung", "subjekt", "fall", "fälle", "wechselpräpositionen",
        "gemischte", "plural", "singular", "nomen", "wörter", "wortschatz", "verben", "verb",
        "dialog", "text", "gruppe", "gruppen", "endung", "endungen",
    ]

    static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        regex(pattern)?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        regex(pattern)?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? []
    }

    private static let cache = RegexCache()

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        cache.regex(pattern)
    }
}

/// Compiled patterns, shared across threads: a parse runs off the main actor and the probe and
/// tests may run several at once.
private nonisolated final class RegexCache: @unchecked Sendable {
    private var compiled: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = compiled[pattern] { return hit }
        let made = try? NSRegularExpression(pattern: pattern)
        compiled[pattern] = made
        return made
    }
}
