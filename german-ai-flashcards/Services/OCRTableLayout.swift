//
//  OCRTableLayout.swift
//  german-ai-flashcards
//
//  Vision reads a bordered table one column at a time: every German cell on the page, then every
//  English one. A vocabulary sheet read that way reaches `VocabListParser` as a run of German lines
//  followed by a run of English lines, and pairs into a handful of cards that each hold half a
//  column. This puts the cells back into rows from where they sit on the page: a column is the
//  lines that share a left edge, a wrapped cell's lines are merged, and each cell of the first
//  column gathers the cells beside it. Columns are joined with a tab, which the parser splits on.
//
//  The rebuilt rows are used only when they read as a German | English list at least as well as
//  Vision's own order does, so a story, a letter or a two-column page of prose keeps Vision's order.
//
//  Pure Foundation + NaturalLanguage, like the parser, so it runs on a Mac against a rendered page.
//

import CoreGraphics
import Foundation

nonisolated enum OCRTableLayout {
    /// One recognized line: its text and its box, normalized to the page, origin bottom-left (Vision's).
    struct Line {
        var text: String
        var box: CGRect
    }

    /// The page's text: the rebuilt rows when the page is a German | English table, else Vision's order.
    static func text(from lines: [Line]) -> String {
        let visionOrder = lines.map(\.text).joined(separator: "\n")
        guard let rows = rowText(from: lines) else { return visionOrder }
        let table = VocabListParser.parse(rows)
        guard table.looksLikeList, englishShare(of: table.rows) >= 0.5 else { return visionOrder }
        return table.listConfidence >= VocabListParser.parse(visionOrder).listConfidence ? rows : visionOrder
    }

    private struct Cell {
        /// Vertical extents are measured from the top of the page, 0…1.
        typealias Extent = (top: CGFloat, bottom: CGFloat)

        var column: Int
        var lines: [(text: String, extent: Extent)]
        var extent: Extent { Self.span(lines.map(\.extent)) }

        static func span(_ extents: [Extent]) -> Extent {
            (extents.map(\.top).min() ?? 0, extents.map(\.bottom).max() ?? 0)
        }
    }

    /// The lines regrouped into rows, one per line of text, columns separated by a tab. Nil when
    /// the page has no two columns of at least three lines each.
    static func rowText(from lines: [Line]) -> String? {
        let lines = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.box.height > 0 }
        guard lines.count >= 6 else { return nil }
        let lineHeight = median(lines.map(\.box.height))

        // Columns: lines sharing a left edge. A jump of more than 4 % of the page width starts the next.
        let byLeft = lines.indices.sorted { lines[$0].box.minX < lines[$1].box.minX }
        var columnOf = [Int](repeating: 0, count: lines.count)
        var column = 0
        for (position, index) in byLeft.enumerated() where position > 0 {
            if lines[index].box.minX - lines[byLeft[position - 1]].box.minX > 0.04 { column += 1 }
            columnOf[index] = column
        }
        let columnSizes = Dictionary(grouping: columnOf, by: { $0 }).mapValues(\.count)
        let tableColumns = columnSizes.filter { $0.value >= 3 }.keys.sorted()
        guard tableColumns.count >= 2, let anchorColumn = tableColumns.first else { return nil }

        // Each column top to bottom, with the gap to the line above in line heights.
        var columns: [Int: [(line: Line, gap: CGFloat)]] = [:]
        for columnIndex in Set(columnOf) {
            let sorted = lines.indices.filter { columnOf[$0] == columnIndex }
                .map { lines[$0] }
                .sorted { $0.box.maxY > $1.box.maxY }
            columns[columnIndex] = sorted.enumerated().map { position, line in
                let gap = position == 0 ? .infinity : (sorted[position - 1].box.minY - line.box.maxY) / lineHeight
                return (line, gap)
            }
        }
        // A bordered table pads its rows, so most lines sit well below the one above; a line that
        // sits close under another is then the second line of a wrapped cell. On a list without
        // padding every gap is small, and every line is its own row.
        let gaps = columns.values.flatMap { $0.map(\.gap) }.filter(\.isFinite)
        let padded = !gaps.isEmpty && median(gaps) >= 1.0

        var merged: [Cell] = []
        for (columnIndex, entries) in columns {
            for entry in entries {
                let line = (text: entry.line.text, extent: (top: 1 - entry.line.box.maxY, bottom: 1 - entry.line.box.minY))
                if padded, entry.gap < 0.55, let last = merged.indices.last, merged[last].column == columnIndex {
                    merged[last].lines.append(line)
                } else {
                    merged.append(Cell(column: columnIndex, lines: [line]))
                }
            }
        }
        // Two short rows can sit closer together than a wrapped cell's lines; the column beside
        // them still shows one cell for each, so that is where the merged cell comes apart.
        let cells = merged.flatMap { cell in
            splitAtRowBreaks(cell, beside: merged.filter { $0.column != cell.column })
        }

        // Rows: every cell of the first column starts one, and each other cell joins the row it
        // overlaps most. A cell beside nothing (a wrapped gloss on an unpadded list, a heading)
        // stays a line of its own, placed where it sits.
        var rows: [[Cell]] = cells.filter { $0.column == anchorColumn }.map { [$0] }
        for cell in cells where cell.column != anchorColumn {
            let overlaps = rows.indices.map { overlap(rows[$0][0].extent, cell.extent) }
            if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 {
                rows[best].append(cell)
            } else {
                rows.append([cell])
            }
        }
        rows.sort { Cell.span($0.map(\.extent)).top < Cell.span($1.map(\.extent)).top }

        return rows.map { row in
            Dictionary(grouping: row, by: \.column)
                .sorted { $0.key < $1.key }
                .map { _, cells in
                    cells.sorted { $0.extent.top < $1.extent.top }.flatMap { $0.lines.map(\.text) }.joined(separator: " ")
                }
                .joined(separator: "\t")
        }
        .joined(separator: "\n")
    }

    /// Split a merged cell between two of its lines when a cell beside it covers only the lines
    /// above and another covers only the lines below: that is a row boundary, not a wrap.
    private static func splitAtRowBreaks(_ cell: Cell, beside others: [Cell]) -> [Cell] {
        guard cell.lines.count >= 2 else { return [cell] }
        for index in 1..<cell.lines.count {
            let upper = Cell.span(cell.lines[..<index].map(\.extent))
            let lower = Cell.span(cell.lines[index...].map(\.extent))
            let besideUpperOnly = others.contains { overlap($0.extent, upper) > 0 && overlap($0.extent, lower) <= 0 }
            let besideLowerOnly = others.contains { overlap($0.extent, lower) > 0 && overlap($0.extent, upper) <= 0 }
            if besideUpperOnly, besideLowerOnly {
                return [Cell(column: cell.column, lines: Array(cell.lines[..<index]))]
                    + splitAtRowBreaks(Cell(column: cell.column, lines: Array(cell.lines[index...])), beside: others)
            }
        }
        return [cell]
    }

    private static func overlap(_ a: Cell.Extent, _ b: Cell.Extent) -> CGFloat {
        min(a.bottom, b.bottom) - max(a.top, b.top)
    }

    /// Of the rows with both sides, how many have an English side that reads as English.
    private static func englishShare(of rows: [VocabListRow]) -> Double {
        let complete = rows.filter(\.isComplete)
        guard !complete.isEmpty else { return 0 }
        return Double(complete.filter { VocabListParser.looksEnglish($0.english) }.count) / Double(complete.count)
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }
}
