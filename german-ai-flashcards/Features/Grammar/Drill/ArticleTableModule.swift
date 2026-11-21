//
//  ArticleTableModule.swift
//  german-ai-flashcards
//
//  Die Tabelle on the drill shell: the article chart as a board (`ArticleTableBoardView`), one
//  step per cell, a drop as the pick.
//
//  The one thing to know about it. Every other module answers the step the shell handed it; this
//  one grades **the cell the learner dropped on** (`pick.cell`), because the whole point of the
//  board is that they choose the order. The round's items are the board's blanks in a fixed order
//  so that the DEBUG prefill, the seeder and the progress strip have sixteen steps to walk, but a
//  real round fills them in whatever order the learner likes and each cell is answered exactly
//  once — the board view offers only open cells, and `answer` ignores a drop on anything else.
//  Anything reading back a step therefore reads the pick, never `item.blank` (`missText`).
//
//  Feedback is deferred, like the Blitzrunde's: a card between two drops would break the board up
//  into sixteen screens. A miss leaves the right form in its cell (the learner keeps a true table)
//  and the misses are read back in the summary.
//

import SwiftUI

struct ArticleTableModule: KasusDrillModule {
    typealias Item = ArticleTableTask
    typealias Pick = ArticleTablePlacement
    typealias Partial = Never

    let kind: KasusDrillKind = .tabelle
    let config: TableConfig
    /// Shared by the chart (the hero) and the tray (the panel), which are two subtrees of the
    /// shell. The module is built once per round, so this lives exactly as long as the board.
    let drag = ArticleTableDrag()

    init(session: GrammarDrillSession) {
        if case .table(let config) = session.variant {
            self.config = config
        } else {
            self.config = TableConfig()
        }
    }

    /// No card between two drops: the board stays on screen and the misses wait for the summary.
    var defersFeedback: Bool { true }

    // MARK: Items and grading

    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [ArticleTableTask]? {
        let tasks = ArticleTableRound.compose(chart: config.chart, shape: config.shape, rng: &rng)
        return tasks.isEmpty ? nil : tasks
    }

    /// Grades the dropped cell. A drop on a cell this board doesn't own is no answer.
    func answer(_ pick: ArticleTablePlacement, for item: ArticleTableTask, step: Int,
                partial: inout Never?) -> KasusDrillOutcome<Never> {
        let board = item.board
        guard board.isBlank(pick.cell) else { return .ignored }
        let outcome = board.outcome(form: pick.form, on: pick.cell)
        let result = KasusItemResult(kasus: pick.cell.kasus, genus: pick.cell.genus,
                                     firstTry: outcome.isRight,
                                     slip: outcome == .genderSlip || outcome == .numberSlip,
                                     record: board.roundItem(form: pick.form, on: pick.cell))
        return .graded(KasusGradedAnswer(outcome: outcome, kasus: pick.cell.kasus,
                                         explanation: board.feedback(form: pick.form, on: pick.cell),
                                         result: result))
    }

    /// The prefill and the seeder fill the item's own blank: right, with another case's form for
    /// that column (a case miss), or with another column of the same case (a slip).
    func debugPick(for item: ArticleTableTask, partial: Never?, want: KasusDebugWant) -> ArticleTablePlacement? {
        let cell = item.blank
        let board = item.board
        let answer = board.form(cell)
        func placement(_ form: String?) -> ArticleTablePlacement? {
            form.map { ArticleTablePlacement(cell: cell, form: $0) }
        }
        switch want {
        case .right:
            return placement(answer)
        case .wrong:
            // Not a slip: a form from outside the cell's own row. The same column first, because
            // that is the mistake a learner actually makes; „die“ in the Nominativ is the cell
            // whose whole column lives in its row, so the search widens to the chart.
            let row = Set(Gender.allCases.map { board.chart.form(cell.kasus, $0) })
            let column = GrammarCase.allCases.map { board.chart.form($0, cell.genus) }
            let anywhere = ArticleChart.allCells.map { board.chart.form($0) }
            return placement((column + anywhere).first { !row.contains($0) })
        case .slip:
            return placement(Gender.allCases.lazy
                .map { board.chart.form(cell.kasus, $0) }
                .first { $0 != answer })
        }
    }

    // MARK: Views

    /// The question: the chart's name, where the round is in it, the grid itself, and the ein
    /// chart's footnote.
    func hero(_ ctx: KasusDrillContext<Self>) -> some View {
        let board = ctx.item.board
        return VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("\(config.chart.germanTitle) · \(config.chart.englishTitle)")
                    .font(.headline)
                Text(boardLine(ctx))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ArticleTableGridView(board: board, placed: placed(ctx, board: board), drag: drag) { ctx.pick($0) }
            if let note = config.chart.note {
                Text(kasusRich: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        // A fresh grid per board: nothing stays armed from the one before.
        .id(board.id)
    }

    /// „Tabelle 2 von 4 · Dativ“ for the shapes that take several boards, the cell count for the
    /// whole table.
    private func boardLine(_ ctx: KasusDrillContext<Self>) -> String {
        let board = ctx.item.board
        let boards = ArticleTableRound.cellCount / config.shape.blanksPerBoard
        guard boards > 1 else { return "\(ArticleTableRound.cellCount) Felder · \(config.shape.englishLabel)" }
        let cases = Set(board.blanks.map(\.kasus))
        let where_ = cases.count == 1 ? " · \(cases.first?.name ?? "")" : ""
        return "Tabelle \(board.index + 1) von \(boards)\(where_)"
    }

    /// The answer: the tiles, in the thumb zone, as any other drill's inputs.
    func panel(_ ctx: KasusDrillContext<Self>) -> some View {
        let board = ctx.item.board
        return ArticleTableTrayView(board: board, placed: placed(ctx, board: board), drag: drag) { ctx.pick($0) }
            .id(board.id)
    }

    /// What the round has put in this board's cells. Every cell of a round is asked once, so a
    /// board's own answers are exactly those on its blanks.
    private func placed(_ ctx: KasusDrillContext<Self>, board: ArticleTableBoard) -> [KasusTableCell: ArticleTablePlaced] {
        var out: [KasusTableCell: ArticleTablePlaced] = [:]
        for answer in ctx.round.answers where board.isBlank(answer.pick.cell) {
            out[answer.pick.cell] = ArticleTablePlaced(answer: board.form(answer.pick.cell),
                                                      pick: answer.pick.form)
        }
        return out
    }

    func hint(_ ctx: KasusDrillContext<Self>) -> String {
        drag.selected == nil
            ? "Drag a form into its cell — or tap the form, then its cell."
            : "Now tap the cell it belongs in."
    }

    func missText(_ item: ArticleTableTask, _ answer: KasusDrillAnswer<ArticleTablePlacement>) -> Text {
        let cell = answer.pick.cell
        let board = item.board
        var out = AttributedString("\(cell.kasus.short) \(cell.genus.columnLabel): ")
        out.foregroundColor = cell.kasus.color
        var right = AttributedString(board.form(cell))
        right.foregroundColor = cell.genus.color
        right.inlinePresentationIntent = .stronglyEmphasized
        var wrong = AttributedString("  \(answer.pick.form)")
        wrong.strikethroughStyle = .single
        return Text(out + right + wrong)
    }

    func summaryNote(_ round: KasusDrillRound<Self>) -> String? {
        "Die Tabelle is built from a closed set of tiles, so a round counts for your streak, never for the coach's case skills."
    }
}
