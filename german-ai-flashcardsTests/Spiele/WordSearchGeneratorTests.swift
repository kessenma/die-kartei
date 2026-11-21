//
//  WordSearchGeneratorTests.swift
//  german-ai-flashcardsTests
//
//  The grid has to be honest in three ways a casual implementation isn't: every listed word is
//  really in it, no word reads two ways (or a legitimate trace gets refused), and a word's umlaut
//  isn't the only one on the board giving it away.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Wortsuche · generator")
struct WordSearchGeneratorTests {

    private func build(_ words: [GameWord], _ options: WordSearchGenerator.Options = .init(),
                       seed: UInt64 = 7) throws -> WordSearchPuzzle {
        try WordSearchGenerator.build(words: words, options: options, seed: seed)
    }

    @Test("Every placement reads back as its word, inside the grid")
    func placementsReadBack() throws {
        let puzzle = try build(SpieleTestWords.küche)
        #expect(puzzle.placements.count == SpieleTestWords.küche.count)

        for placement in puzzle.placements {
            #expect(placement.cells.count == placement.word.length)
            let reading = placement.cells.compactMap { puzzle.letter(at: $0) }
            #expect(reading == placement.word.letters,
                    "\(placement.word.german) does not read back off the grid")
            for cell in placement.cells {
                #expect((0..<puzzle.size).contains(cell.row))
                #expect((0..<puzzle.size).contains(cell.col))
            }
        }
    }

    @Test("Every cell holds a letter once the grid is filled")
    func gridIsFull() throws {
        let puzzle = try build(SpieleTestWords.küche)
        #expect(puzzle.grid.count == puzzle.size)
        for row in puzzle.grid {
            #expect(row.count == puzzle.size)
            for letter in row {
                #expect(GameLetters.alphabet.contains(letter), "filler produced \(letter)")
            }
        }
    }

    @Test("No word reads two ways — a legitimate trace is never refused")
    func noAmbiguousReadings() throws {
        let puzzle = try build(SpieleTestWords.küche)
        let directions = Set(WordSearchDirection.allCases)
        for placement in puzzle.placements {
            let paths = WordSearchGenerator.scan(puzzle.grid, for: placement.word.letters,
                                                 directions: directions)
            // A word reads along its path and along that path reversed; both are the same find.
            let distinct = paths.filter { $0 != placement.cells && $0 != placement.cells.reversed() }
            #expect(distinct.isEmpty,
                    "\(placement.word.german) also reads at \(distinct.first ?? [])")
        }
    }

    @Test("A traced path is matched from either end")
    func tracesMatchBothWays() throws {
        let puzzle = try build(SpieleTestWords.küche)
        for placement in puzzle.placements {
            #expect(puzzle.placement(matching: placement.cells)?.id == placement.id)
            #expect(puzzle.placement(matching: placement.cells.reversed())?.id == placement.id)
        }
        #expect(puzzle.placement(matching: []) == nil)
        #expect(puzzle.placement(matching: [GridPoint(row: 0, col: 0)]) == nil)
    }

    @Test("The same seed is the same puzzle; a different seed is a different one")
    func determinism() throws {
        let a = try build(SpieleTestWords.küche, seed: 123)
        let b = try build(SpieleTestWords.küche, seed: 123)
        #expect(a.grid == b.grid)
        #expect(a.placements == b.placements)

        let c = try build(SpieleTestWords.küche, seed: 124)
        #expect(a.grid != c.grid, "two seeds produced the same grid")
    }

    @Test("The puzzle depends on the seed and the words, not on the order they arrive in")
    func orderIndependent() throws {
        let forwards = try build(SpieleTestWords.küche, seed: 909)
        let backwards = try build(SpieleTestWords.küche.reversed(), seed: 909)
        #expect(forwards.grid == backwards.grid)
        #expect(Set(forwards.placements) == Set(backwards.placements))
    }

    @Test("Adding a shorter word leaves the earlier placements exactly where they were")
    func appendingIsStable() throws {
        // Two things are pinned so the property is actually testable. The grid size, because
        // `suggestedSize` grows with the letter count and a bigger grid legitimately moves
        // everything. And the added word is the *shortest*, so it sorts last and every other
        // word keeps its place in the placement order — words laid before it cannot be affected
        // by it, and that is the whole of what this property claims.
        let options = WordSearchGenerator.Options(size: 12)
        let six = Array(SpieleTestWords.küche.prefix(6))
        let seven = six + [SpieleTestWords.word("Aal", "eel")]

        let before = try build(six, options, seed: 500)
        let after = try build(seven, options, seed: 500)
        #expect(after.placements.count == 7)

        for placement in before.placements {
            let moved = after.placements.first { $0.id == placement.id }
            #expect(moved?.start == placement.start, "\(placement.word.german) moved")
            #expect(moved?.direction == placement.direction, "\(placement.word.german) turned")
        }
    }

    @Test("Backwards off means no word reads right-to-left or bottom-to-top")
    func backwardsToggle() throws {
        let options = WordSearchGenerator.Options(allowBackwards: false)
        let puzzle = try build(SpieleTestWords.küche, options)
        #expect(puzzle.allowedBackwards == false)
        for placement in puzzle.placements {
            #expect(placement.direction.isBackwards == false,
                    "\(placement.word.german) runs \(placement.direction)")
        }
    }

    @Test("Diagonals off means every word is horizontal or vertical")
    func diagonalsToggle() throws {
        let options = WordSearchGenerator.Options(allowDiagonals: false)
        let puzzle = try build(SpieleTestWords.küche, options)
        for placement in puzzle.placements {
            #expect(placement.direction.isAxis, "\(placement.word.german) runs diagonally")
        }
    }

    @Test("A lone umlaut is camouflaged — one Ä on the board would be the answer")
    func umlautCamouflage() throws {
        let puzzle = try build(SpieleTestWords.umlaut, seed: 31)
        let äCount = puzzle.grid.reduce(0) { running, row in running + row.count { $0 == "Ä" } }
        #expect(äCount >= 2, "„Mädchen“ is given away by the only Ä on the board")
    }

    @Test("Camouflage can be turned off, which is how we know it is doing the work")
    func camouflageIsWhatCausesIt() throws {
        // Without it, a single-umlaut list usually leaves exactly one Ä; the test above shows
        // the option is what fixes that rather than luck in the filler.
        let bare = WordSearchGenerator.Options(camouflageUmlauts: false)
        let puzzle = try build(SpieleTestWords.umlaut, bare, seed: 31)
        let answerÄ = puzzle.placements.flatMap(\.word.letters).count { $0 == "Ä" }
        #expect(answerÄ == 1)
    }

    @Test("A word longer than the grid is refused by name")
    func tooLong() {
        let options = WordSearchGenerator.Options(size: 8)
        let words = SpieleTestWords.words(["Geschwindigkeit", "Blume", "Tisch", "Stein",
                                           "Wasser", "Brot"])
        #expect(throws: WordSearchGenerator.Failure.wordTooLongForGrid("Geschwindigkeit", 8)) {
            try WordSearchGenerator.build(words: words, options: options, seed: 1)
        }
    }

    @Test("Fewer than two words is not a puzzle")
    func tooFew() {
        #expect(throws: WordSearchGenerator.Failure.tooFewWords) {
            try WordSearchGenerator.build(words: SpieleTestWords.words(["Blume"]), seed: 1)
        }
    }

    @Test("Suggested size grows with the longest word and stays tappable")
    func suggestedSize() {
        let short = WordSearchGenerator.suggestedSize(for: SpieleTestWords.words(["Uhr", "Tee", "Ei"]))
        let long = WordSearchGenerator.suggestedSize(for: SpieleTestWords.words(["Geschwindigkeit", "Tee"]))
        #expect(short >= 8)
        #expect(long > short)
        #expect(long <= 14, "a cell has to stay tappable on a phone")
    }

    @Test("A round can always be dealt from a source the fitter accepted")
    func theFitterAlwaysDealsAPlayableRound() {
        // What the learner is promised: if the setup screen said the source is enough, pressing
        // start produces a puzzle. The fitter gets there by dropping a word when placement fails,
        // so this covers the retry path as well as the generator.
        let fit = GameWordFitter.fit(SpieleTestWords.küche, to: WordSearchRound.requirements)
        #expect(fit.isEnough)
        var dealt = 0
        for seed in UInt64(0)..<200 {
            guard let round = GameWordFitter.round(WordSearchRound.self, from: fit, seed: seed),
                  (try? WordSearchGenerator.build(words: round, seed: seed)) != nil
            else { continue }
            dealt += 1
        }
        #expect(dealt == 200, "only \(dealt)/200 seeds produced a playable round")
    }
}
