//
//  FillInGenerator.swift
//  german-ai-flashcards
//
//  Builds an interlocking grid out of a word list, for the clueless kind of crossword: the words
//  are given, grouped by length, and the puzzle is working out which goes where.
//
//  Built by growing words off each other on an unbounded lattice, not by carving a blocked pattern
//  and filling it. Pattern-carving is how newspaper crosswords are made and it needs a dictionary
//  of tens of thousands of words to fill a shape; over the eight words on a learner's deck it
//  simply fails, every time.
//
//  Two adjacency rules do the real work. An occupied cell may only be reused if a word on the
//  *other* axis holds it (so two words never lie along each other), and an empty cell must have
//  both of its perpendicular neighbours empty (so two parallel words never sit side by side and
//  spell nonsense across). Together they guarantee the property the slot extractor relies on:
//  every run of two or more letters in the finished grid is exactly one placed word.
//

import Foundation

nonisolated struct Crossing: Hashable, Sendable {
    /// The index within this slot's word.
    let myIndex: Int
    let otherSlot: Int
    let otherIndex: Int
}

nonisolated struct FillInSlot: Hashable, Identifiable, Sendable {
    enum Axis: Hashable, Sendable {
        case across, down
        var perpendicular: Axis { self == .across ? .down : .across }
        var delta: (dr: Int, dc: Int) { self == .across ? (0, 1) : (1, 0) }
    }

    let id: Int
    let axis: Axis
    let start: GridPoint
    let length: Int
    let cells: [GridPoint]
    let crossings: [Crossing]
}

nonisolated struct FillInPuzzle: Hashable, Sendable {
    let rows: Int
    let cols: Int
    /// Cells inside the bounding box that hold no letter — the black squares.
    let blocked: Set<GridPoint>
    let slots: [FillInSlot]
    /// The arrangement the generator found. **For reveal and tests only** — never the win check.
    /// With no clues, a different arrangement can be just as correct; see `FillInJudge.isSolved`.
    let solution: [Int: GameWord]
    /// The words on offer, grouped by length as the tray shows them.
    let tray: [Int: [GameWord]]
    let seed: UInt64

    var words: [GameWord] { tray.values.flatMap { $0 } }

    func slot(id: Int) -> FillInSlot? { slots.first { $0.id == id } }

    func slot(containing point: GridPoint, axis: FillInSlot.Axis) -> FillInSlot? {
        slots.first { $0.axis == axis && $0.cells.contains(point) }
    }

    /// The letter showing in a cell given what has been placed so far.
    func letter(at point: GridPoint, given placed: [Int: GameWord]) -> Character? {
        for slot in slots {
            guard let word = placed[slot.id], let offset = slot.cells.firstIndex(of: point) else { continue }
            if offset < word.letters.count { return word.letters[offset] }
        }
        return nil
    }
}

nonisolated enum FillInGenerator {

    struct Options: Sendable {
        var targetWords: ClosedRange<Int> = 6...10
        /// The longest side the grid may reach, so it stays readable on a phone.
        var maxSide = 13
        /// Seeded restarts with a different word order.
        var attempts = 40

        init(targetWords: ClosedRange<Int> = 6...10, maxSide: Int = 13, attempts: Int = 40) {
            self.targetWords = targetWords
            self.maxSide = maxSide
            self.attempts = attempts
        }
    }

    enum Failure: Equatable, Sendable {
        case tooFewWords
        /// Nothing interlocks — the words share no letters at all.
        case noSharedLetters
        /// Some fitted, but not enough of them inside `maxSide`.
        case gridTooSmall
    }

    /// Not `throws`, because a *partial* pack is the normal outcome rather than the error path:
    /// seven of ten learner words interlocking is a good puzzle, and the setup screen says so.
    enum Outcome: Sendable {
        case built(FillInPuzzle)
        case partial(FillInPuzzle, unused: [GameWord])
        case failed(Failure)
    }

    private struct Laid {
        let word: GameWord
        let start: GridPoint
        let axis: FillInSlot.Axis
        var cells: [GridPoint] {
            (0..<word.length).map { start.offset(by: axis.delta, times: $0) }
        }
    }

    static func build(words: [GameWord], options: Options = Options(), seed: UInt64) -> Outcome {
        let unique = deduplicated(words)
        guard unique.count >= options.targetWords.lowerBound else { return .failed(.tooFewWords) }

        var best: [Laid] = []
        for attempt in 0..<max(1, options.attempts) {
            let order = ordering(unique, attempt: attempt, seed: seed)
            let laid = pack(order, options: options, seed: seed &+ UInt64(attempt) &* 7_919)
            if laid.count > best.count ||
                (laid.count == best.count && area(laid) < area(best)) {
                best = laid
            }
            if best.count == unique.count { break }
        }

        guard best.count > 1 else { return .failed(.noSharedLetters) }
        guard best.count >= options.targetWords.lowerBound else { return .failed(.gridTooSmall) }

        let puzzle = assemble(best, seed: seed)
        let used = Set(best.map(\.word.id))
        let unused = unique.filter { !used.contains($0.id) }
        return unused.isEmpty ? .built(puzzle) : .partial(puzzle, unused: unused)
    }

    // MARK: - Packing

    private static func pack(_ words: [GameWord], options: Options, seed: UInt64) -> [Laid] {
        var generator = SeededGenerator(seed: seed)
        guard let first = words.first else { return [] }

        var laid = [Laid(word: first, start: GridPoint(row: 0, col: 0), axis: .across)]
        var letters: [GridPoint: Character] = [:]
        for (offset, cell) in laid[0].cells.enumerated() { letters[cell] = first.letters[offset] }

        for word in words.dropFirst() {
            var best: (laid: Laid, score: Int)?

            for anchor in laid {
                let anchorCells = anchor.cells
                for (anchorIndex, anchorCell) in anchorCells.enumerated() {
                    let anchorLetter = anchor.word.letters[anchorIndex]
                    for (index, letter) in word.letters.enumerated()
                    where GameLetters.equal(letter, anchorLetter) {
                        let axis = anchor.axis.perpendicular
                        let start = anchorCell.offset(by: axis.delta, times: -index)
                        let candidate = Laid(word: word, start: start, axis: axis)
                        guard let crossings = placement(candidate, letters: letters, laid: laid,
                                                        options: options) else { continue }
                        var score = crossings * 2 - growth(of: candidate, in: laid)
                        score += Int.random(in: 0..<2, using: &generator)
                        if score > (best?.score ?? Int.min) { best = (candidate, score) }
                    }
                }
            }

            guard let choice = best else { continue }
            for (offset, cell) in choice.laid.cells.enumerated() { letters[cell] = word.letters[offset] }
            laid.append(choice.laid)
        }
        return laid
    }

    /// How many crossings the placement makes, or nil when it is illegal.
    private static func placement(_ candidate: Laid, letters: [GridPoint: Character],
                                  laid: [Laid], options: Options) -> Int? {
        let cells = candidate.cells
        let axis = candidate.axis
        let perpendicular = axis.perpendicular.delta

        // The run may not be extended at either end, or two words merge into one longer run.
        let before = candidate.start.offset(by: axis.delta, times: -1)
        let after = candidate.start.offset(by: axis.delta, times: cells.count)
        guard letters[before] == nil, letters[after] == nil else { return nil }

        var crossings = 0
        for (index, cell) in cells.enumerated() {
            if let existing = letters[cell] {
                // Reusing a letter is only legal where a word on the other axis holds it —
                // otherwise the two words would lie along each other.
                guard GameLetters.equal(existing, candidate.word.letters[index]),
                      laid.contains(where: { $0.axis != axis && $0.cells.contains(cell) })
                else { return nil }
                crossings += 1
            } else {
                // An empty cell must be clear to both sides, or this word spells something
                // unintended across its neighbour.
                guard letters[cell.offset(by: perpendicular)] == nil,
                      letters[cell.offset(by: perpendicular, times: -1)] == nil
                else { return nil }
            }
        }
        guard crossings > 0 else { return nil }

        let box = bounds(of: laid.map(\.cells).flatMap { $0 } + cells)
        guard box.rows <= options.maxSide, box.cols <= options.maxSide else { return nil }
        return crossings
    }

    // MARK: - Slot extraction

    private static func assemble(_ laid: [Laid], seed: UInt64) -> FillInPuzzle {
        var letters: [GridPoint: Character] = [:]
        for entry in laid {
            for (offset, cell) in entry.cells.enumerated() { letters[cell] = entry.word.letters[offset] }
        }

        // Crop to the bounding box and move the origin to (0, 0).
        let box = bounds(of: Array(letters.keys))
        let shifted = Dictionary(uniqueKeysWithValues: letters.map {
            (GridPoint(row: $0.key.row - box.minRow, col: $0.key.col - box.minCol), $0.value)
        })
        let placements = laid.map {
            Laid(word: $0.word,
                 start: GridPoint(row: $0.start.row - box.minRow, col: $0.start.col - box.minCol),
                 axis: $0.axis)
        }

        // Every maximal run of two or more letters is a slot. The adjacency rules above are what
        // make this equal to the placed words exactly — pinned by a test.
        var slots: [FillInSlot] = []
        var identifier = 0
        for axis in [FillInSlot.Axis.across, .down] {
            for run in runs(in: shifted, rows: box.rows, cols: box.cols, axis: axis) {
                slots.append(FillInSlot(id: identifier, axis: axis, start: run[0], length: run.count,
                                        cells: run, crossings: []))
                identifier += 1
            }
        }
        slots = withCrossings(slots)

        var solution: [Int: GameWord] = [:]
        for slot in slots {
            if let match = placements.first(where: { $0.axis == slot.axis && $0.cells == slot.cells }) {
                solution[slot.id] = match.word
            }
        }

        var generator = SeededGenerator(seed: seed &* 97 &+ 3)
        let tray = Dictionary(grouping: placements.map(\.word), by: \.length)
            .mapValues { $0.shuffled(using: &generator) }

        var blocked: Set<GridPoint> = []
        for row in 0..<box.rows {
            for col in 0..<box.cols {
                let cell = GridPoint(row: row, col: col)
                if shifted[cell] == nil { blocked.insert(cell) }
            }
        }

        return FillInPuzzle(rows: box.rows, cols: box.cols, blocked: blocked, slots: slots,
                            solution: solution, tray: tray, seed: seed)
    }

    private static func runs(in letters: [GridPoint: Character], rows: Int, cols: Int,
                             axis: FillInSlot.Axis) -> [[GridPoint]] {
        var result: [[GridPoint]] = []
        let outer = axis == .across ? rows : cols
        let inner = axis == .across ? cols : rows
        for a in 0..<outer {
            var run: [GridPoint] = []
            for b in 0..<inner {
                let cell = axis == .across ? GridPoint(row: a, col: b) : GridPoint(row: b, col: a)
                if letters[cell] != nil {
                    run.append(cell)
                } else {
                    if run.count >= 2 { result.append(run) }
                    run = []
                }
            }
            if run.count >= 2 { result.append(run) }
        }
        return result
    }

    private static func withCrossings(_ slots: [FillInSlot]) -> [FillInSlot] {
        slots.map { slot in
            var crossings: [Crossing] = []
            for other in slots where other.id != slot.id && other.axis != slot.axis {
                for (index, cell) in slot.cells.enumerated() {
                    if let otherIndex = other.cells.firstIndex(of: cell) {
                        crossings.append(Crossing(myIndex: index, otherSlot: other.id,
                                                  otherIndex: otherIndex))
                    }
                }
            }
            return FillInSlot(id: slot.id, axis: slot.axis, start: slot.start, length: slot.length,
                              cells: slot.cells, crossings: crossings)
        }
    }

    // MARK: - Helpers

    private static func deduplicated(_ words: [GameWord]) -> [GameWord] {
        var seen: Set<String> = []
        return words.filter { seen.insert($0.id).inserted }
    }

    private static func ordering(_ words: [GameWord], attempt: Int, seed: UInt64) -> [GameWord] {
        let byLength = words.sorted { ($0.length, $0.german) > ($1.length, $1.german) }
        guard attempt > 0 else { return byLength }
        var generator = SeededGenerator(seed: seed &+ UInt64(attempt) &* 2_654_435_761)
        // The longest word still leads — it has the most crossing opportunities — but the rest
        // are reshuffled so a restart explores a different shape.
        return [byLength[0]] + byLength.dropFirst().shuffled(using: &generator)
    }

    private static func bounds(of cells: [GridPoint]) -> (minRow: Int, minCol: Int, rows: Int, cols: Int) {
        guard !cells.isEmpty else { return (0, 0, 0, 0) }
        let rows = cells.map(\.row), cols = cells.map(\.col)
        let minRow = rows.min()!, minCol = cols.min()!
        return (minRow, minCol, rows.max()! - minRow + 1, cols.max()! - minCol + 1)
    }

    private static func area(_ laid: [Laid]) -> Int {
        let box = bounds(of: laid.flatMap(\.cells))
        return box.rows * box.cols
    }

    private static func growth(of candidate: Laid, in laid: [Laid]) -> Int {
        let old = bounds(of: laid.flatMap(\.cells))
        let new = bounds(of: laid.flatMap(\.cells) + candidate.cells)
        return (new.rows + new.cols) - (old.rows + old.cols)
    }
}

/// The fill-in crossword's limits. No ß, for the same reason as the word search.
nonisolated enum FillInRound: GameRoundShape {
    static var requirements: GameWordRequirements {
        GameWordRequirements(
            lengthRange: 3...11,
            wordCount: 6...10,
            singleTokenOnly: true,
            eszett: .exclude,
            needsEnglish: false,
            alphabet: GameLetters.alphabet,
            blurb: "Needs at least 6 single words of 3–11 letters that share some letters."
        )
    }

    /// A pack that leaves words over still makes a playable round, so `.partial` counts as built.
    static func canBuild(_ words: [GameWord], seed: UInt64) -> Bool {
        switch FillInGenerator.build(words: words, seed: seed) {
        case .built, .partial: true
        case .failed:          false
        }
    }
}
