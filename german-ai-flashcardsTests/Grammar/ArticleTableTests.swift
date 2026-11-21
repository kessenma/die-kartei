//
//  ArticleTableTests.swift
//  german-ai-flashcardsTests
//
//  Die Tabelle's board: the chart is the app's one article table and no second copy, a round asks
//  every cell exactly once whatever the shape, the tray counts the blanks, and a drop is graded
//  right / gender slip / number slip / case miss the way the Schnellrunde grades a pick.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Die Tabelle")
struct ArticleTableTests {

    @Test("The chart is the app's own table, and ein's plural column is kein")
    func charts() {
        for kasus in GrammarCase.allCases {
            for genus in Gender.allCases {
                #expect(ArticleChart.definite.form(kasus, genus) == kasus.article(genus))
                let ein = ArticleChart.ein.form(kasus, genus)
                #expect(ein == (genus == .plural ? "kein" : "ein") + kasus.einEnding(genus))
                #expect(ein.hasPrefix(genus == .plural ? "kein" : "ein"))
            }
        }
        #expect(ArticleChart.definite.form(.dativ, .der) == "dem")
        #expect(ArticleChart.definite.form(.genitiv, .plural) == "der")
        #expect(ArticleChart.ein.form(.nominativ, .der) == "ein")
        #expect(ArticleChart.ein.form(.akkusativ, .der) == "einen")
        #expect(ArticleChart.ein.form(.dativ, .plural) == "keinen")
        #expect(ArticleChart.ein.form(.genitiv, .plural) == "keiner")
        // The ein chart owes the learner the reason its plural column changes word.
        #expect(ArticleChart.definite.note == nil && ArticleChart.ein.note != nil)
        #expect(ArticleChart.allCells.count == ArticleTableRound.cellCount)
        #expect(Set(ArticleChart.allCells).count == ArticleTableRound.cellCount)
    }

    @Test("Every shape asks every cell exactly once, in boards of its own size")
    func compose() {
        for chart in ArticleChart.allCases {
            for shape in ArticleTableShape.allCases {
                var rng = KasusSeededRandom(seed: 11)
                let tasks = ArticleTableRound.compose(chart: chart, shape: shape, rng: &rng)
                #expect(tasks.count == ArticleTableRound.cellCount, "\(chart) \(shape)")
                #expect(Set(tasks.map(\.blank)).count == ArticleTableRound.cellCount)
                #expect(Set(tasks.map(\.id)).count == tasks.count)

                let boards = Dictionary(grouping: tasks, by: \.board)
                #expect(boards.count == ArticleTableRound.cellCount / shape.blanksPerBoard)
                for (board, steps) in boards {
                    #expect(board.chart == chart && board.shape == shape)
                    #expect(board.blanks.count == shape.blanksPerBoard)
                    #expect(steps.count == shape.blanksPerBoard)
                    #expect(steps.allSatisfy { board.isBlank($0.blank) })
                    switch shape {
                    case .whole:
                        #expect(Set(board.blanks) == Set(ArticleChart.allCells))
                    case .row:
                        // One case's row: four genders, one case.
                        #expect(Set(board.blanks.map(\.kasus)).count == 1)
                        #expect(Set(board.blanks.map(\.genus)) == Set(Gender.allCases))
                    case .gaps:
                        // The Latin square: never one case and never one column.
                        #expect(Set(board.blanks.map(\.kasus)) == Set(GrammarCase.allCases))
                        #expect(Set(board.blanks.map(\.genus)) == Set(Gender.allCases))
                    }
                }
            }
        }
    }

    @Test("The same seed composes the same round twice")
    func seeded() {
        var a = KasusSeededRandom(seed: 5), b = KasusSeededRandom(seed: 5), c = KasusSeededRandom(seed: 6)
        // The blanks in order, not the ids: an id is the board's position, which never varies.
        let first = ArticleTableRound.compose(chart: .definite, shape: .gaps, rng: &a).map(\.blank)
        let second = ArticleTableRound.compose(chart: .definite, shape: .gaps, rng: &b).map(\.blank)
        let other = ArticleTableRound.compose(chart: .definite, shape: .gaps, rng: &c).map(\.blank)
        #expect(first == second && !first.isEmpty)
        #expect(first != other)
    }

    @Test("The tray is the blanks: one stack per form, counted")
    func tray() {
        let whole = ArticleTableBoard(chart: .definite, shape: .whole, blanks: ArticleChart.allCells, index: 0)
        let stacks = whole.tray
        // der die das den dem des: the six forms of the definite table, nothing else.
        #expect(stacks.map(\.form) == ["der", "die", "das", "den", "dem", "des"])
        #expect(stacks.map(\.count) == [4, 4, 2, 2, 2, 2])
        #expect(stacks.reduce(0) { $0 + $1.count } == ArticleTableRound.cellCount)
        #expect(Set(stacks.map(\.id)).count == stacks.count)

        let row = ArticleTableBoard(chart: .definite, shape: .row,
                                    blanks: Gender.allCases.map { KasusTableCell(kasus: .dativ, genus: $0) },
                                    index: 2)
        #expect(row.tray.map(\.form) == ["dem", "der", "den"])
        #expect(row.tray.map(\.count) == [2, 1, 1])
        #expect(row.id == "definite-row-2")
    }

    @Test("A drop is right, a gender slip, a number slip or a case miss")
    func grading() {
        let board = ArticleTableBoard(chart: .definite, shape: .whole, blanks: ArticleChart.allCells, index: 0)
        func outcome(_ form: String, _ kasus: GrammarCase, _ genus: Gender) -> KasusItemOutcome {
            board.outcome(form: form, on: KasusTableCell(kasus: kasus, genus: genus))
        }
        #expect(outcome("dem", .dativ, .der) == .right)
        // Another column of the same row: a gender slip.
        #expect(outcome("der", .dativ, .der) == .genderSlip)
        #expect(outcome("dem", .dativ, .die) == .genderSlip)
        // Another row entirely: a case miss. „den“ is the Akkusativ m (and the Dativ pl).
        #expect(outcome("den", .nominativ, .der) == .caseMiss)
        #expect(outcome("des", .dativ, .der) == .caseMiss)
        // The plural cell filled with a singular of its own row, and the other way round.
        #expect(outcome("dem", .dativ, .plural) == .numberSlip)
        #expect(outcome("den", .dativ, .der) == .numberSlip)
        // „die“ is feminine and plural at once, so a gender wins over a number.
        #expect(outcome("die", .nominativ, .das) == .genderSlip)
        // A form that isn't in the chart at all is a case miss, not a crash.
        #expect(outcome("einem", .dativ, .der) == .caseMiss)
    }

    @Test("A graded cell keeps its own form and names where the wrong one lives")
    func feedbackAndRecord() {
        let board = ArticleTableBoard(chart: .definite, shape: .whole, blanks: ArticleChart.allCells, index: 0)
        let cell = KasusTableCell(kasus: .dativ, genus: .der)
        let right = board.feedback(form: "dem", on: cell)
        #expect(right.contains("**dem**") && right.contains("{dat:Dat} m"))
        #expect(right.contains("mrmn"), "the definite row's code word belongs in its feedback")
        let wrong = board.feedback(form: "den", on: cell)
        #expect(wrong.contains("ist **dem**") && wrong.contains("{akk:Akk} m") && wrong.contains("{dat:Dat} pl"))
        // The ein chart spells no code word, so it never claims one.
        let ein = ArticleTableBoard(chart: .ein, shape: .whole, blanks: ArticleChart.allCells, index: 0)
        #expect(!ein.feedback(form: "einem", on: cell).contains("Endungen dieser Zeile"))

        let item = board.roundItem(form: "den", on: cell)
        #expect(item.answer == "dem" && item.pick == "den" && item.phrase == "dem")
        #expect(item.caseRaw == GrammarCase.dativ.rawValue && item.genusRaw == Gender.der.rawValue)
        // „den“ is the Dativ plural as well as the Akkusativ m, so the charitable reading wins:
        // the row was right, the column wasn't.
        #expect(item.outcomeRaw == KasusItemOutcome.numberSlip.rawValue)
        #expect(item.sentence == "Dativ · masculine: dem")
        // The phrase has to be findable in the sentence for the round detail's strike-through.
        #expect(item.phraseStart == item.sentence.utf16.count - item.phrase.utf16.count)
        #expect(KasusRich.plain(item.explanation).contains("dem"))
    }

    @Test("The module grades the cell that was dropped on, and ignores a stray drop")
    @MainActor
    func moduleGradesThePick() {
        var session = GrammarDrillSession(kind: .tabelle, topic: .kasus(.alleFaelle))
        session.variant = .table(TableConfig(chart: .definite, shape: .row))
        let module = ArticleTableModule(session: session)
        var rng = KasusSeededRandom(seed: 3)
        guard let items = module.compose(session, rng: &rng), let first = items.first else {
            Issue.record("no items"); return
        }
        var round = KasusDrillRound<ArticleTableModule>(items: items)

        // A cell of this board that is *not* the step's own blank still grades, because the
        // learner picks the order.
        guard let other = first.board.blanks.first(where: { $0 != first.blank }) else {
            Issue.record("a row board has four blanks"); return
        }
        let placement = ArticleTablePlacement(cell: other, form: first.board.form(other))
        guard case .graded(let graded) = round.answer(placement, with: module) else {
            Issue.record("expected a graded drop"); return
        }
        #expect(graded.isRight && graded.kasus == other.kasus)
        #expect(graded.result.genus == other.genus)
        #expect(round.cursor == 1)

        // A drop on a cell another board owns is no answer at all.
        let elsewhere = ArticleChart.allCells.first { !first.board.isBlank($0) }
        if let elsewhere {
            let stray = ArticleTablePlacement(cell: elsewhere, form: "der")
            if case .ignored = round.answer(stray, with: module) {} else {
                Issue.record("a drop outside the board graded")
            }
            #expect(round.cursor == 1)
        }
    }

    @Test("The prefill asks for a right pick, a case miss and a slip on the step's own cell")
    @MainActor
    func debugPicks() {
        var session = GrammarDrillSession(kind: .tabelle, topic: .kasus(.alleFaelle))
        session.variant = .table(TableConfig(chart: .definite, shape: .whole))
        let module = ArticleTableModule(session: session)
        var rng = KasusSeededRandom(seed: 8)
        guard let items = module.compose(session, rng: &rng) else { Issue.record("no items"); return }
        for item in items {
            let board = item.board
            for want in [KasusDebugWant.right, .wrong, .slip] {
                guard let pick = module.debugPick(for: item, partial: nil, want: want) else {
                    Issue.record("\(want) has no pick for \(item.blank)"); continue
                }
                #expect(pick.cell == item.blank)
                let outcome = board.outcome(form: pick.form, on: pick.cell)
                switch want {
                case .right: #expect(outcome == .right)
                case .wrong: #expect(outcome == .caseMiss, "a wrong pick must not be a slip")
                case .slip:  #expect(outcome == .genderSlip || outcome == .numberSlip)
                }
            }
        }
    }

    @Test("The remembered setup round-trips, and an unknown stored value falls back")
    func storedConfig() {
        let defaults = UserDefaults(suiteName: "tabelle-tests")!
        defaults.removePersistentDomain(forName: "tabelle-tests")
        #expect(TableConfig.stored(defaults) == TableConfig(chart: .definite, shape: .whole))
        defaults.set(ArticleChart.ein.rawValue, forKey: TableConfig.chartKey)
        defaults.set(ArticleTableShape.gaps.rawValue, forKey: TableConfig.shapeKey)
        #expect(TableConfig.stored(defaults) == TableConfig(chart: .ein, shape: .gaps))
        defaults.set("nirgends", forKey: TableConfig.shapeKey)
        #expect(TableConfig.stored(defaults).shape == .whole)
        defaults.removePersistentDomain(forName: "tabelle-tests")
    }
}
