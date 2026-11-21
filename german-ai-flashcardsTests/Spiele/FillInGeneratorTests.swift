//
//  FillInGeneratorTests.swift
//  german-ai-flashcardsTests
//
//  The packer, and the win check that must not consult the packer's answer.
//
//  The load-bearing test here is `aSwapOfIndistinguishableSlotsIsAlsoSolved`. With no clues, two
//  same-length slots that no crossing tells apart are both legitimately fillable either way, so a
//  win check written against `puzzle.solution` would tell a learner who solved the puzzle that
//  they are wrong. That test is what stops anyone "simplifying" `isSolved` into a comparison.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Einsetz-Kreuzworträtsel · generator")
struct FillInGeneratorTests {

    // MARK: - Packing

    @Test("A letter-rich list interlocks, and every slot holds the word that fits it")
    func packs() throws {
        let outcome = FillInGenerator.build(words: SpieleTestWords.küche, seed: 11)
        let puzzle: FillInPuzzle
        switch outcome {
        case .built(let built):      puzzle = built
        case .partial(let part, _):  puzzle = part
        case .failed(let failure):   throw TestFailure.packing(failure)
        }

        #expect(puzzle.slots.count >= FillInRound.requirements.wordCount.lowerBound)
        // Every slot the extractor found is one of the words that was placed — this is the
        // adjacency rules paying off, and it is what makes the tray exactly right.
        #expect(puzzle.solution.count == puzzle.slots.count)
        for slot in puzzle.slots {
            let word = try #require(puzzle.solution[slot.id])
            #expect(word.length == slot.length)
            #expect(slot.cells.count == slot.length)
        }
    }

    @Test("Crossing letters agree in both slots")
    func crossingsAgree() throws {
        switch FillInGenerator.build(words: SpieleTestWords.küche, seed: 11) {
        case .built(let puzzle), .partial(let puzzle, _): try checkCrossings(puzzle)
        case .failed(let failure):                        throw TestFailure.packing(failure)
        }
    }

    private func checkCrossings(_ puzzle: FillInPuzzle) throws {
        for slot in puzzle.slots {
            let mine = try #require(puzzle.solution[slot.id])
            for crossing in slot.crossings {
                let theirs = try #require(puzzle.solution[crossing.otherSlot])
                #expect(GameLetters.equal(mine.letters[crossing.myIndex],
                                          theirs.letters[crossing.otherIndex]),
                        "\(mine.german) and \(theirs.german) disagree where they cross")
            }
        }
    }

    @Test("Every word crosses at least one other — nothing floats unattached")
    func everythingIsConnected() throws {
        guard case .built(let puzzle) = FillInGenerator.build(words: SpieleTestWords.küche, seed: 11)
        else { return }  // a partial pack is covered by its own test
        for slot in puzzle.slots {
            #expect(slot.crossings.isEmpty == false, "slot \(slot.id) is not attached to anything")
        }
    }

    @Test("The grid stays inside the side limit")
    func sideLimit() throws {
        let options = FillInGenerator.Options(maxSide: 11)
        let outcome = FillInGenerator.build(words: SpieleTestWords.küche, options: options, seed: 3)
        switch outcome {
        case .built(let puzzle), .partial(let puzzle, _):
            #expect(puzzle.rows <= 11)
            #expect(puzzle.cols <= 11)
        case .failed(let failure):
            throw TestFailure.packing(failure)
        }
    }

    @Test("The same seed is the same grid")
    func determinism() {
        let a = FillInGenerator.build(words: SpieleTestWords.küche, seed: 77)
        let b = FillInGenerator.build(words: SpieleTestWords.küche, seed: 77)
        switch (a, b) {
        case (.built(let x), .built(let y)), (.partial(let x, _), .partial(let y, _)):
            #expect(x.slots == y.slots)
            #expect(x.rows == y.rows && x.cols == y.cols)
        default:
            Issue.record("two runs of one seed disagreed about the outcome")
        }
    }

    @Test("A partial pack accounts for every word it was given")
    func partialLosesNothing() {
        // Ten words rarely all interlock; whatever happens, nothing may vanish silently.
        for seed in UInt64(0)..<40 {
            let outcome = FillInGenerator.build(words: SpieleTestWords.küche, seed: seed)
            guard case .partial(let puzzle, let unused) = outcome else { continue }
            let placed = Set(puzzle.solution.values.map(\.id))
            let left = Set(unused.map(\.id))
            #expect(placed.isDisjoint(with: left))
            #expect(placed.union(left) == Set(SpieleTestWords.küche.map(\.id)),
                    "seed \(seed) lost a word")
        }
    }

    @Test("Words that share no letters cannot interlock, and say so")
    func noSharedLetters() {
        // "Hund" and "Katze" have no letter in common, so there is nothing to build on.
        let options = FillInGenerator.Options(targetWords: 2...4)
        let outcome = FillInGenerator.build(words: SpieleTestWords.strangers,
                                            options: options, seed: 5)
        guard case .failed(let failure) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(failure == .noSharedLetters)
    }

    @Test("Too few words is refused before any packing")
    func tooFewWords() {
        let outcome = FillInGenerator.build(words: SpieleTestWords.words(["Blume", "Tisch"]), seed: 1)
        guard case .failed(let failure) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(failure == .tooFewWords)
    }

    @Test("How often ten learner words pack — recorded, not gated")
    func packRateSurvey() {
        var built = 0, partial = 0, failed = 0
        for seed in UInt64(0)..<200 {
            switch FillInGenerator.build(words: SpieleTestWords.küche, seed: seed) {
            case .built:   built += 1
            case .partial: partial += 1
            case .failed:  failed += 1
            }
        }
        // The number that justifies designing the setup screen around `.partial`. The assertion is
        // deliberately loose: it pins the promise (a letter-rich list yields a playable grid), not
        // the ratio, which is free to drift as the scorer changes.
        #expect(built + partial == 200, "\(failed)/200 seeds produced no grid at all")
        print("[fillin] built \(built) · partial \(partial) · failed \(failed) of 200")
    }

    // MARK: - The judge

    /// Two across slots of length 4 with nothing crossing them, so no crossing can tell them
    /// apart. Hand-built rather than generated, because the whole point is a puzzle whose answer
    /// is genuinely not unique.
    private func ambiguousPuzzle() -> (puzzle: FillInPuzzle, haus: GameWord, hund: GameWord) {
        let haus = SpieleTestWords.word("Haus", "house")
        let hund = SpieleTestWords.word("Hund", "dog")
        let top = FillInSlot(id: 0, axis: .across, start: GridPoint(row: 0, col: 0), length: 4,
                             cells: (0..<4).map { GridPoint(row: 0, col: $0) }, crossings: [])
        let bottom = FillInSlot(id: 1, axis: .across, start: GridPoint(row: 2, col: 0), length: 4,
                                cells: (0..<4).map { GridPoint(row: 2, col: $0) }, crossings: [])
        let blocked = Set((0..<4).map { GridPoint(row: 1, col: $0) })
        let puzzle = FillInPuzzle(rows: 3, cols: 4, blocked: blocked, slots: [top, bottom],
                                  solution: [0: haus, 1: hund], tray: [4: [haus, hund]], seed: 1)
        return (puzzle, haus, hund)
    }

    @Test("Swapping two indistinguishable slots is also solved")
    func aSwapOfIndistinguishableSlotsIsAlsoSolved() {
        let (puzzle, haus, hund) = ambiguousPuzzle()

        #expect(FillInJudge.isSolved([0: haus, 1: hund], in: puzzle))
        // The arrangement the generator did *not* pick. Nothing on the board contradicts it, so
        // it is just as solved — checking against `puzzle.solution` would fail the learner here.
        #expect(FillInJudge.isSolved([0: hund, 1: haus], in: puzzle))
    }

    @Test("An unfinished or double-used board is not solved")
    func unsolvedBoards() {
        let (puzzle, haus, _) = ambiguousPuzzle()
        #expect(FillInJudge.isSolved([:], in: puzzle) == false)
        #expect(FillInJudge.isSolved([0: haus], in: puzzle) == false)
        // One tile cannot satisfy two slots.
        #expect(FillInJudge.isSolved([0: haus, 1: haus], in: puzzle) == false)
    }

    /// A crossing puzzle: „Haus“ across, a three-letter word down through its first letter.
    private func crossingPuzzle() -> FillInPuzzle {
        let across = FillInSlot(id: 0, axis: .across, start: GridPoint(row: 0, col: 0), length: 4,
                                cells: (0..<4).map { GridPoint(row: 0, col: $0) },
                                crossings: [Crossing(myIndex: 0, otherSlot: 1, otherIndex: 0)])
        let down = FillInSlot(id: 1, axis: .down, start: GridPoint(row: 0, col: 0), length: 3,
                              cells: (0..<3).map { GridPoint(row: $0, col: 0) },
                              crossings: [Crossing(myIndex: 0, otherSlot: 0, otherIndex: 0)])
        return FillInPuzzle(rows: 3, cols: 4, blocked: [], slots: [across, down],
                            solution: [:], tray: [:], seed: 1)
    }

    @Test("A wrong letter at a crossing is named, a right one is allowed")
    func conflictsNameTheCrossing() {
        let puzzle = crossingPuzzle()
        let haus = SpieleTestWords.word("Haus", "house")
        let placed = [0: haus]

        let clash = FillInJudge.conflicts(slot: 1, word: SpieleTestWords.word("Tee", "tea"),
                                          placed: placed, in: puzzle)
        #expect(clash.count == 1)
        #expect(clash.first?.otherSlot == 0)
        #expect(FillInJudge.canPlace(word: SpieleTestWords.word("Tee", "tea"), on: 1,
                                     placed: placed, in: puzzle) == false)

        // „Hut“ starts with the H that „Haus“ already put in that cell.
        let hut = SpieleTestWords.word("Hut", "hat")
        #expect(FillInJudge.conflicts(slot: 1, word: hut, placed: placed, in: puzzle).isEmpty)
        #expect(FillInJudge.canPlace(word: hut, on: 1, placed: placed, in: puzzle))
    }

    @Test("A word of the wrong length never fits a slot")
    func lengthGate() {
        let puzzle = crossingPuzzle()
        #expect(FillInJudge.canPlace(word: SpieleTestWords.word("Tisch", "table"), on: 1,
                                     placed: [:], in: puzzle) == false)
        #expect(FillInJudge.openSlots(for: SpieleTestWords.word("Hut", "hat"),
                                      placed: [:], in: puzzle) == [1])
    }

    @Test("Open slots shrink as the board fills")
    func openSlots() {
        let (puzzle, haus, hund) = ambiguousPuzzle()
        #expect(Set(FillInJudge.openSlots(for: haus, placed: [:], in: puzzle)) == [0, 1])
        #expect(FillInJudge.openSlots(for: haus, placed: [1: hund], in: puzzle) == [0])
    }

    private enum TestFailure: Error {
        case packing(FillInGenerator.Failure)
    }
}
