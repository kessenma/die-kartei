//
//  ArticleTableGame.swift
//  german-ai-flashcards
//
//  Die Tabelle · the classroom's article chart turned into a board: the grid is drawn empty and
//  the forms are tiles the learner drags into their cells. Two charts — the definite articles
//  (der die das die …) and the ein-words (ein eine ein / keine …) — and three board shapes, so
//  the same engine is a whole-table test, a row at a time, or four scattered gaps.
//
//  Nothing is authored. Every cell comes from `GrammarCase.article(_:)` and
//  `GrammarCase.einEnding(_:)`, the same table `CaseEndingsTable` renders and the Schnellrunde
//  generates from, so the game and the reference can never disagree.
//
//  Three rules the board holds:
//
//    - **A round is always the whole table.** Sixteen cells, whatever the shape, so a score means
//      the same thing across shapes and the per-case strip in Verlauf always spans four cases.
//    - **The tray is the blanks.** One stack per distinct form, counted; a cell that is answered
//      consumes one copy of *its own* form, right or wrong. So running out of „der“ is itself a
//      signal, and the counts can never drift from the cells left.
//    - **A miss leaves the right form behind.** The learner is building a reference table; a wrong
//      form left sitting in a cell would teach the wrong thing. The pick is kept for the summary.
//
//  Foundation only and `nonisolated`, like the rest of the registry's content types.
//

import Foundation

// MARK: - The charts

/// Which chart the board draws. The two halves of a classroom article table.
nonisolated enum ArticleChart: String, Codable, CaseIterable, Identifiable {
    /// der, die, das, die / den … : the definite articles.
    case definite
    /// ein, eine, ein / keine … : the ein-words, with kein in the plural column.
    case ein

    var id: String { rawValue }

    var germanTitle: String {
        switch self {
        case .definite: "Bestimmter Artikel"
        case .ein:      "Unbestimmter Artikel"
        }
    }

    var englishTitle: String {
        switch self {
        case .definite: "the"
        case .ein:      "a / an"
        }
    }

    /// The form in one cell. `ein` has no plural, so the plural column is `kein` — what a
    /// classroom chart writes there, and the negative of `eine`.
    func form(_ kasus: GrammarCase, _ genus: Gender) -> String {
        switch self {
        case .definite: kasus.article(genus)
        case .ein:      (genus == .plural ? "kein" : "ein") + kasus.einEnding(genus)
        }
    }

    func form(_ cell: KasusTableCell) -> String { form(cell.kasus, cell.genus) }

    /// The note under the chart, in `KasusRich` markup. The ein chart owes the learner the
    /// reason its plural column changes word.
    var note: String? {
        switch self {
        case .definite:
            nil
        case .ein:
            "**ein** has no plural, so the plural column is **kein** — the negative of **eine**: „In Venedig gibt es **keine** Autos.“"
        }
    }

    /// Every cell of the chart, in reading order.
    static var allCells: [KasusTableCell] {
        GrammarCase.allCases.flatMap { kasus in
            Gender.allCases.map { KasusTableCell(kasus: kasus, genus: $0) }
        }
    }
}

// MARK: - The board shapes

/// How much of the chart one board leaves blank. Every shape asks all sixteen cells per round;
/// what changes is how much of the table stands around them while they are asked.
nonisolated enum ArticleTableShape: String, Codable, CaseIterable, Identifiable {
    /// Every cell blank: one board is the round.
    case whole
    /// One case's row blank, the other three given. Four boards, one per case.
    case row
    /// Four scattered cells blank, one per case and one per gender. Four boards.
    case gaps

    var id: String { rawValue }

    var germanLabel: String {
        switch self {
        case .whole: "Ganze Tabelle"
        case .row:   "Zeile für Zeile"
        case .gaps:  "Lücken"
        }
    }

    var englishLabel: String {
        switch self {
        case .whole: "The whole table"
        case .row:   "A row at a time"
        case .gaps:  "Scattered gaps"
        }
    }

    var blurb: String {
        switch self {
        case .whole: "Sixteen empty cells and nothing to lean on."
        case .row:   "One case's row is empty, the other three stay as reference."
        case .gaps:  "Four cells per board, spread across the table."
        }
    }

    /// Blanks on one board.
    var blanksPerBoard: Int { self == .whole ? ArticleTableRound.cellCount : Gender.allCases.count }
}

// MARK: - A board

/// One board of a round: the chart, which of its cells are blank, and which position in the
/// round it holds (so two boards of one round never share an id).
nonisolated struct ArticleTableBoard: Hashable, Identifiable {
    let chart: ArticleChart
    let shape: ArticleTableShape
    /// The blanks, in the order the DEBUG prefill and the seeder fill them. A learner fills them
    /// in whatever order they like; the module grades the cell that was dropped on.
    let blanks: [KasusTableCell]
    let index: Int

    var id: String { "\(chart.rawValue)-\(shape.rawValue)-\(index)" }

    var blankSet: Set<KasusTableCell> { Set(blanks) }

    func form(_ cell: KasusTableCell) -> String { chart.form(cell) }

    func isBlank(_ cell: KasusTableCell) -> Bool { blanks.contains(cell) }

    /// A cell waiting for a form: this board's blank, not yet answered. The only cell a drop or a
    /// tap may land on, which is what keeps every cell answered exactly once.
    func isOpen(_ cell: KasusTableCell, placed: [KasusTableCell: ArticleTablePlaced]) -> Bool {
        isBlank(cell) && placed[cell] == nil
    }

    /// The tray: one stack per distinct form, in the table's reading order, with how many cells
    /// want it.
    var tray: [ArticleTile] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for cell in ArticleChart.allCells where blankSet.contains(cell) {
            let form = self.form(cell)
            if counts[form] == nil { order.append(form) }
            counts[form, default: 0] += 1
        }
        return order.map { ArticleTile(form: $0, count: counts[$0] ?? 1) }
    }

    // MARK: Grading

    /// Right, a gender slip (another column of the same case), a number slip (the singular where
    /// the plural was asked, or the other way round) or a case miss.
    func outcome(form: String, on cell: KasusTableCell) -> KasusItemOutcome {
        guard form != self.form(cell) else { return .right }
        let sameCase = Gender.allCases.filter { $0 != cell.genus && chart.form(cell.kasus, $0) == form }
        guard !sameCase.isEmpty else { return .caseMiss }
        // „die“ is both feminine and plural, so a column that is also a gender wins: the learner
        // picked a gender, and only a pure singular/plural mix-up is a number slip.
        let singulars = sameCase.filter { $0 != .plural }
        if cell.genus == .plural { return singulars.isEmpty ? .genderSlip : .numberSlip }
        return singulars.isEmpty ? .numberSlip : .genderSlip
    }

    /// „Dativ · maskulin: dem“ — the cell as one line, which is what the round history stores in
    /// place of a sentence and what the summary prints.
    func line(_ cell: KasusTableCell) -> String {
        "\(cell.kasus.name) · \(cell.genus.genderName): \(form(cell))"
    }

    /// Why, in `KasusRich` markup: the cell's own form, and for a miss where the dropped form
    /// does live („**den** ist {akk:Akk} m und {dat:Dat} pl“).
    func feedback(form: String, on cell: KasusTableCell) -> String {
        let answer = self.form(cell)
        let cellName = Self.name(of: cell)
        guard form != answer else {
            // The code word is the definite row's last letters; the ein-words don't spell it.
            guard chart == .definite else { return "**\(answer)** · \(cellName)." }
            return "**\(answer)** · \(cellName). Die Endungen dieser Zeile: **\(cell.kasus.code)**."
        }
        let homes = places(of: form)
        let where_ = homes.isEmpty
            ? "**\(form)** steht in dieser Tabelle nicht."
            : "**\(form)** ist \(homes)."
        return "\(cellName) ist **\(answer)**. \(where_)"
    }

    /// Where a form lives in this chart, as „{akk:Akk} m und {dat:Dat} pl“.
    func places(of form: String) -> String {
        let cells = ArticleChart.allCells.filter { chart.form($0) == form }
        guard !cells.isEmpty else { return "" }
        let parts = cells.map(Self.name(of:))
        if parts.count == 1 { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + " und " + parts[parts.count - 1]
    }

    /// „{dat:Dat} m“: a cell named in the markup, its case word in its case colour.
    static func name(of cell: KasusTableCell) -> String {
        "{\(cell.kasus.short.lowercased()):\(cell.kasus.short)} \(cell.genus.columnLabel)"
    }

    /// The round history's copy of one placement.
    func roundItem(form: String, on cell: KasusTableCell) -> KasusRoundItem {
        let answer = self.form(cell)
        let sentence = line(cell)
        return KasusRoundItem(
            sentence: sentence,
            phraseStart: sentence.utf16.count - answer.utf16.count,
            phrase: answer,
            answer: answer,
            pick: form,
            kasus: cell.kasus,
            genus: cell.genus,
            outcome: outcome(form: form, on: cell),
            explanation: feedback(form: form, on: cell),
            hasNounGender: true
        )
    }
}

/// One tray stack: a form, and how many cells of the board want it.
nonisolated struct ArticleTile: Hashable, Identifiable {
    let form: String
    let count: Int

    var id: String { form }
}

/// A drop: the form, and the cell it landed in. The pick the shell records.
nonisolated struct ArticleTablePlacement: Hashable {
    let cell: KasusTableCell
    let form: String
}

/// One step of the round: a board and one of its blanks. The blank is the order the prefill and
/// the seeder work in; real play grades the cell the learner dropped on, which is why the module
/// reads `pick.cell` and not `item.blank`.
nonisolated struct ArticleTableTask: Hashable, Identifiable {
    let board: ArticleTableBoard
    let blank: KasusTableCell
    let step: Int

    var id: String { "\(board.id)#\(step)" }
}

// MARK: - The round

nonisolated enum ArticleTableRound {
    /// Sixteen: four cases × four genders, and the length of every round whatever the shape.
    static var cellCount: Int { GrammarCase.allCases.count * Gender.allCases.count }

    /// The round's steps: every cell of the chart asked exactly once, grouped into boards.
    static func compose(chart: ArticleChart, shape: ArticleTableShape,
                        rng: inout KasusSeededRandom) -> [ArticleTableTask] {
        let boards: [[KasusTableCell]]
        switch shape {
        case .whole:
            boards = [ArticleChart.allCells.shuffled(using: &rng)]
        case .row:
            boards = GrammarCase.allCases.shuffled(using: &rng).map { kasus in
                Gender.allCases.map { KasusTableCell(kasus: kasus, genus: $0) }.shuffled(using: &rng)
            }
        case .gaps:
            // A Latin square: board i takes one cell per case, the columns rotated, so every cell
            // is asked exactly once across the four boards and no board is one case or one gender.
            let columns = Gender.allCases.shuffled(using: &rng)
            boards = (0..<Gender.allCases.count).map { i in
                GrammarCase.allCases.enumerated().map { j, kasus in
                    KasusTableCell(kasus: kasus, genus: columns[(j + i) % columns.count])
                }.shuffled(using: &rng)
            }
        }
        return boards.enumerated().flatMap { index, blanks in
            let board = ArticleTableBoard(chart: chart, shape: shape, blanks: blanks, index: index)
            return blanks.enumerated().map { step, cell in
                ArticleTableTask(board: board, blank: cell, step: step)
            }
        }
    }
}

// MARK: - What the board already holds

/// A cell the round has answered: the form that belongs there, and the form the learner dropped
/// on it (the same one when it was right). The cell keeps the *answer* either way — the learner
/// is building a reference table — and the pick is what the summary and Verlauf report.
nonisolated struct ArticleTablePlaced: Hashable {
    let answer: String
    let pick: String

    var isRight: Bool { answer == pick }
}
