//
//  WorksheetPDFReader.swift
//  german-ai-flashcards
//
//  The PDFKit side of the worksheet parser: a page's lines with their UTF-16 ranges and boxes
//  in, and, the other way, where a parsed gap, choice or word sits on the page — what the renderer
//  draws an answer into. `WorksheetParser` never sees PDFKit, so the probe and the tests can feed
//  it lines of their own.
//
//  Ranges are always UTF-16 offsets into `page.string`, because that is what
//  `PDFPage.selection(for:)` counts; a `String.Index` distance would drift on any decomposed
//  umlaut. And a range is only ever resolved against the same page string it came from, on the
//  same device: see `WorksheetParser`'s header for why nothing positional is stored.
//

import CoreGraphics
import Foundation
import PDFKit

nonisolated enum WorksheetPDFReader {

    /// Every page as lines, for `WorksheetParser.parse`.
    static func pageTexts(of document: PDFDocument) -> [WorksheetPageText] {
        (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else {
                return WorksheetPageText(number: index + 1, lines: [])
            }
            return WorksheetPageText(number: index + 1, lines: lines(on: page))
        }
    }

    static func lines(on page: PDFPage) -> [WorksheetLine] {
        let raw = rawLines(on: page)
        // iOS PDFKit can hand back one "line" that is really several: a column of item numbers
        // glued to the first item ("1. 2. 3. 4. 5. 6. für der / den Salat", 232 points tall), or a
        // subtitle run together with whatever sits beside or under it. The Mac reads the same page
        // as separate lines. A line much taller than the page's usual line, or wider than half the
        // page, is cut back into its real rows by where its characters sit.
        let heights = raw.map(\.box.height).filter { $0 > 0 }.sorted()
        guard !heights.isEmpty else { return raw }
        let typical = heights[heights.count / 2]
        let pageWidth = page.bounds(for: .mediaBox).width
        return raw.flatMap { line -> [WorksheetLine] in
            let tall = line.box.height > typical * 1.5
            let wide = line.box.width > pageWidth * 0.5
            guard tall || wide else { return [line] }
            return split(line, on: page, typical: typical)
        }
    }

    /// One PDFKit line cut where its characters change row, or jump far to the side: each run of
    /// characters on one row, close together, is a line of its own with its own range and box.
    static func split(_ line: WorksheetLine, on page: PDFPage, typical: CGFloat) -> [WorksheetLine] {
        let ns = line.text as NSString
        struct Run { var start: Int; var end: Int; var box: CGRect; var last: CGRect }
        var runs: [Run] = []
        var current: Run?
        let rowTolerance = typical * 0.5
        let sideJump = typical * 8
        for offset in 0..<ns.length {
            let unit = ns.character(at: offset)
            if let scalar = Unicode.Scalar(unit), CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            // A one-character selection, not `characterBounds(at:)`: that one counts characters
            // differently from `page.string` (the image placeholders throw it off), so its boxes
            // land a few letters away. Selections use the same ranges as the lines themselves.
            let box = page.selection(for: NSRange(location: line.range.location + offset, length: 1))?
                .bounds(for: page) ?? .zero
            guard box.width > 0 || box.height > 0 else {
                current?.end = offset + 1
                continue
            }
            if var run = current {
                let sameRow = abs(box.midY - run.last.midY) < rowTolerance
                let near = box.minX - run.last.maxX < sideJump && box.minX > run.last.minX - typical
                if sameRow && near {
                    run.end = offset + 1
                    run.box = run.box.union(box)
                    run.last = box
                    current = run
                    continue
                }
                runs.append(run)
            }
            current = Run(start: offset, end: offset + 1, box: box, last: box)
        }
        if let current { runs.append(current) }
        guard runs.count > 1 else { return [line] }
        return runs.map { run in
            let local = NSRange(location: run.start, length: run.end - run.start)
            return WorksheetLine(text: ns.substring(with: local),
                                 range: NSRange(location: line.range.location + run.start, length: local.length),
                                 box: run.box)
        }
    }

    private static func rawLines(on page: PDFPage) -> [WorksheetLine] {
        guard let string = page.string, !string.isEmpty else { return [] }
        let ns = string as NSString
        var out: [WorksheetLine] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { substring, range, _, _ in
            guard let substring else { return }
            // Trim, keeping the range on the characters that remain.
            let leading = substring.prefix { $0.isWhitespace || $0 == "\u{FFFC}" }
            let trailing = substring.reversed().prefix { $0.isWhitespace || $0 == "\u{FFFC}" }
            let leadingUTF16 = String(leading).utf16.count
            let trailingUTF16 = String(trailing).utf16.count
            let length = range.length - leadingUTF16 - trailingUTF16
            guard length > 0 else { return }
            let trimmedRange = NSRange(location: range.location + leadingUTF16, length: length)
            let box = page.selection(for: trimmedRange)?.bounds(for: page) ?? .zero
            out.append(WorksheetLine(text: ns.substring(with: trimmedRange), range: trimmedRange, box: box))
        }
        return out
    }

    /// Parse a whole document. Off the main actor: 38 slides is a few hundred selections.
    static func parse(_ document: PDFDocument) -> [WorksheetExercise] {
        WorksheetParser.parse(pageTexts(of: document))
    }

    static func parse(data: Data) -> [WorksheetExercise]? {
        guard let document = PDFDocument(data: data) else { return nil }
        return parse(document)
    }

    /// The same, reporting (pages read, page count) as it goes: the import's progress card. The
    /// slow part is reading each page's lines, so that is what is counted.
    static func parse(data: Data, progress: (_ done: Int, _ of: Int) -> Void) -> [WorksheetExercise]? {
        guard let document = PDFDocument(data: data) else { return nil }
        let count = document.pageCount
        let pages = (0..<count).map { index -> WorksheetPageText in
            defer { progress(index + 1, count) }
            guard let page = document.page(at: index) else { return WorksheetPageText(number: index + 1, lines: []) }
            return WorksheetPageText(number: index + 1, lines: lines(on: page))
        }
        return WorksheetParser.parse(pages)
    }

    /// One page, parsed with the document's running header and footer known, so it reads the same
    /// as it did in the full parse. `chrome` comes from `WorksheetParser.chrome(in:)`.
    static func parse(page: PDFPage, number: Int, chrome: Set<String>) -> WorksheetExercise {
        WorksheetParser.parsePage(WorksheetPageText(number: number, lines: lines(on: page)), chrome: chrome)
    }

    static func chrome(of document: PDFDocument) -> Set<String> {
        WorksheetParser.chrome(in: pageTexts(of: document))
    }

    /// Where a range of the page's text sits, in page space. Nil for a range PDFKit can't place —
    /// synthesized whitespace answers with a zero rect, which would put an answer in a corner.
    static func rect(for range: NSRange, on page: PDFPage) -> CGRect? {
        guard range.location != NSNotFound, range.length > 0,
              let selection = page.selection(for: range) else { return nil }
        let bounds = selection.bounds(for: page)
        guard bounds.width > 0.5, bounds.height > 0.5, !bounds.isInfinite, !bounds.isNull else { return nil }
        return bounds
    }

    /// Where every answerable part of an exercise sits on its page.
    static func geometry(of exercise: WorksheetExercise, on page: PDFPage) -> WorksheetGeometry {
        var geometry = WorksheetGeometry(pageBounds: page.bounds(for: .mediaBox))
        for item in exercise.items {
            if item.box != .zero { geometry.items[item.key] = item.box }
            for gap in item.gaps {
                if let rect = rect(for: gap.range, on: page) { geometry.gaps[gap.key] = rect }
                else { geometry.unplaced.append(gap.key) }
            }
            for choice in item.choices {
                let rects = choice.options.map { rect(for: $0.range, on: page) }
                if rects.allSatisfy({ $0 != nil }) { geometry.choices[choice.key] = rects.compactMap { $0 } }
                else { geometry.unplaced.append(choice.key) }
            }
            if item.marks != nil {
                geometry.words[item.key] = item.words.map { rect(for: $0.range, on: page) ?? .zero }
            }
        }
        return geometry
    }
}

/// An exercise's answerable parts, placed on its page. Page space, origin bottom-left.
nonisolated struct WorksheetGeometry: Sendable {
    var pageBounds: CGRect
    var items: [String: CGRect] = [:]
    var gaps: [String: CGRect] = [:]
    /// Per choice, one rect per option, in printed order.
    var choices: [String: [CGRect]] = [:]
    /// Per markable item, one rect per word (`.zero` for a word PDFKit couldn't place).
    var words: [String: [CGRect]] = [:]
    /// Keys PDFKit could not place; the page is then offered for the Pencil instead.
    var unplaced: [String] = []
}
