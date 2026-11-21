//
//  GridPoint.swift
//  german-ai-flashcards
//
//  A cell address, shared by the two grid games. Row-major, origin top-left, as the boards read.
//

import Foundation

nonisolated struct GridPoint: Hashable, Codable, Sendable {
    var row: Int
    var col: Int

    init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    /// Compact, for the debug launch arguments („3,2“).
    init?(argument: String) {
        let parts = argument.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let row = Int(parts[0]), let col = Int(parts[1]) else { return nil }
        self.init(row: row, col: col)
    }

    func offset(by delta: (dr: Int, dc: Int), times: Int = 1) -> GridPoint {
        GridPoint(row: row + delta.dr * times, col: col + delta.dc * times)
    }
}
