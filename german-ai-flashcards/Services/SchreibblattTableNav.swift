//
//  SchreibblattTableNav.swift
//  german-ai-flashcards
//
//  "Nächste Tabelle": with the wrist guard on, a finger no longer scrolls with one touch, so the
//  page offers a button that brings the next writing table into view. This is the pure half:
//  which table the learner is on and which one comes next, from what is on screen and where the
//  pen last wrote. The button and the scrolling are `SchreibblattNextTableButton` and
//  `PencilBoard.reveal(sheetRect:)`.
//
//  Tested in `SchreibblattTableNavTests` on the A4 layout.
//

import CoreGraphics

nonisolated extension SchreibblattLayout {

    /// The writing tables in the order they are written: by pass, whatever the page or column.
    var writingTables: [Table] {
        tables.filter { !$0.isVorlage }.sorted { ($0.repetition ?? 0) < ($1.repetition ?? 0) }
    }

    /// The writing table the learner is on. The one under the pen's newest stroke while that
    /// stroke is on screen (they are writing there); else the one showing the most of itself,
    /// the earlier one on a tie. Nil when no writing table is on screen at all.
    func currentWritingTable(visible: CGRect, lastStroke: CGRect?) -> Table? {
        if let stroke = lastStroke, !stroke.isNull, stroke.intersects(visible),
           let cell = cell(at: CGPoint(x: stroke.midX, y: stroke.midY)),
           let table = tables.first(where: { $0.id == cell.table }), !table.isVorlage {
            return table
        }
        var best: (table: Table, share: CGFloat)?
        for table in writingTables {
            let area = table.frame.width * table.frame.height
            let seen = table.frame.intersection(visible)
            guard area > 0, !seen.isNull, !seen.isEmpty else { continue }
            let share = seen.width * seen.height / area
            // Strictly more, so the earlier table keeps a tie.
            if share > (best?.share ?? 0) + 0.001 { best = (table, share) }
        }
        return best?.table
    }

    /// The table to bring into view next: the pass after the current one. With no writing table
    /// on screen (only a Vorlage, or the header), the first one from the top of the screen down.
    /// Nil when the current table is the last pass.
    func tableAfter(visible: CGRect, lastStroke: CGRect?) -> Table? {
        let writing = writingTables
        guard let current = currentWritingTable(visible: visible, lastStroke: lastStroke),
              let pass = current.repetition
        else {
            return writing.first { $0.frame.minY >= visible.minY - 1 } ?? writing.first
        }
        return writing.first { ($0.repetition ?? 0) > pass }
    }

    /// Whether the learner is on the last pass: nothing left to scroll to.
    func isOnLastTable(visible: CGRect, lastStroke: CGRect?) -> Bool {
        guard let current = currentWritingTable(visible: visible, lastStroke: lastStroke) else { return false }
        return current.repetition == writingTables.last?.repetition
    }

    /// What to put on screen for a table: the table and its label strip, so "3" shows above it.
    func revealRect(for table: Table) -> CGRect {
        table.frame.union(table.labelFrame)
    }
}
