//
//  WordSearchGenerator.swift
//  german-ai-flashcards
//
//  Hides a word list in a letter grid. Pure and seeded: the same seed is the same puzzle, which is
//  what lets a round be resumed, screenshotted and tested.
//
//  Three things here are less obvious than the placement loop, and all three are what make the
//  finished grid honest:
//
//  - **The grid may not contain a word twice.** Filler letters can accidentally spell an answer,
//    and then a learner traces a perfectly good reading that the puzzle refuses. So the filler is
//    verified with `scan` afterwards and re-rolled until every answer reads exactly one way.
//  - **A word may not hide entirely inside another.** „ROT“ laid along „BROT“ occupies no cell of
//    its own; it isn't hidden, it's a coincidence.
//  - **An umlaut must not be unique.** One Ä in the grid *is* the answer — it gives „Mädchen“ away
//    at a glance — so a few of the rarest filler letters are promoted to match it.
//

import Foundation

nonisolated enum WordSearchDirection: Int, CaseIterable, Hashable, Sendable {
    case east, southEast, south, southWest, west, northWest, north, northEast

    var delta: (dr: Int, dc: Int) {
        switch self {
        case .east:      (0, 1)
        case .southEast: (1, 1)
        case .south:     (1, 0)
        case .southWest: (1, -1)
        case .west:      (0, -1)
        case .northWest: (-1, -1)
        case .north:     (-1, 0)
        case .northEast: (-1, 1)
        }
    }

    /// Horizontal or vertical — no diagonal.
    var isAxis: Bool { delta.dr == 0 || delta.dc == 0 }

    /// Reads right-to-left or bottom-to-top, which is the "backwards" the setup toggle means.
    var isBackwards: Bool { delta.dc < 0 || (delta.dc == 0 && delta.dr < 0) }
}

nonisolated struct WordSearchPlacement: Hashable, Identifiable, Sendable {
    let word: GameWord
    let start: GridPoint
    let direction: WordSearchDirection
    let cells: [GridPoint]

    var id: String { word.id }
}

nonisolated struct WordSearchPuzzle: Hashable, Sendable {
    let size: Int
    /// Row-major, every cell filled.
    let grid: [[Character]]
    let placements: [WordSearchPlacement]
    let seed: UInt64
    let allowedBackwards: Bool
    let allowedDiagonals: Bool

    func letter(at point: GridPoint) -> Character? {
        guard grid.indices.contains(point.row), grid[point.row].indices.contains(point.col) else { return nil }
        return grid[point.row][point.col]
    }

    /// The placement a traced path found, matched **forwards or reversed** so a backwards word
    /// counts from either end — the learner traced the right cells either way.
    func placement(matching cells: [GridPoint]) -> WordSearchPlacement? {
        guard cells.count > 1 else { return nil }
        return placements.first { $0.cells == cells || $0.cells == cells.reversed() }
    }

    var words: [GameWord] { placements.map(\.word) }
}

nonisolated enum WordSearchGenerator {

    struct Options: Sendable {
        /// nil lets `suggestedSize` decide from the words.
        var size: Int?
        var allowBackwards = true
        var allowDiagonals = true
        /// How many (start, direction) pairs to weigh per word. Caps the work on a big grid.
        var maxCandidateSamples = 240
        var camouflageUmlauts = true
        var refillAttempts = 6

        init(size: Int? = nil, allowBackwards: Bool = true, allowDiagonals: Bool = true,
             maxCandidateSamples: Int = 240, camouflageUmlauts: Bool = true,
             refillAttempts: Int = 6) {
            self.size = size
            self.allowBackwards = allowBackwards
            self.allowDiagonals = allowDiagonals
            self.maxCandidateSamples = maxCandidateSamples
            self.camouflageUmlauts = camouflageUmlauts
            self.refillAttempts = refillAttempts
        }
    }

    enum Failure: Error, Equatable {
        case tooFewWords
        case wordTooLongForGrid(String, Int)
        /// These words found no room. The caller drops one and retries — see `GameWordFitter.round`.
        case couldNotPlace([String])
    }

    /// Big enough for the longest word plus a margin, and for the letters to breathe, but capped
    /// at 14 so a cell stays tappable on a phone.
    static func suggestedSize(for words: [GameWord]) -> Int {
        let longest = words.map(\.length).max() ?? 0
        let letters = words.reduce(0) { $0 + $1.length }
        let byArea = Int(ceil((Double(letters) * 1.8).squareRoot()))
        return min(14, max(8, longest + 2, byArea))
    }

    static func build(words: [GameWord], options: Options = Options(),
                      seed: UInt64) throws -> WordSearchPuzzle {
        guard words.count >= 2 else { throw Failure.tooFewWords }

        let size = options.size ?? suggestedSize(for: words)
        if let tooLong = words.first(where: { $0.length > size }) {
            throw Failure.wordTooLongForGrid(tooLong.german, size)
        }

        let directions = Set(WordSearchDirection.allCases.filter {
            (options.allowBackwards || !$0.isBackwards) && (options.allowDiagonals || $0.isAxis)
        })

        var grid = [[Character?]](repeating: [Character?](repeating: nil, count: size), count: size)
        var placements: [WordSearchPlacement] = []
        var usedDirections: Set<WordSearchDirection> = []
        var unplaced: [String] = []

        // Longest first: the hardest word should pick from an empty grid. The name breaks ties,
        // which makes this a *total* order — without it two equal-length words sort arbitrarily
        // and the same word set in a different array order would yield a different puzzle from
        // the same seed.
        let ordered = words.sorted { ($0.length, $0.german) > ($1.length, $1.german) }
        for (index, word) in ordered.enumerated() {
            // A per-word sub-seed, so adding a word to the list leaves the earlier placements
            // byte-identical — a property the tests pin.
            var generator = SeededGenerator(seed: seed &+ UInt64(index) &* 0x9E37)

            var candidates: [(start: GridPoint, direction: WordSearchDirection)] = []
            for direction in directions.sorted(by: { $0.rawValue < $1.rawValue }) {
                for row in 0..<size {
                    for col in 0..<size {
                        let start = GridPoint(row: row, col: col)
                        let end = start.offset(by: direction.delta, times: word.length - 1)
                        guard (0..<size).contains(end.row), (0..<size).contains(end.col) else { continue }
                        candidates.append((start, direction))
                    }
                }
            }
            candidates = Array(candidates.shuffled(using: &generator).prefix(options.maxCandidateSamples))

            var best: (start: GridPoint, direction: WordSearchDirection, score: Int)?
            for candidate in candidates {
                guard let score = score(word.letters, at: candidate.start, direction: candidate.direction,
                                        in: grid, usedDirections: usedDirections, using: &generator)
                else { continue }
                if score > (best?.score ?? Int.min) {
                    best = (candidate.start, candidate.direction, score)
                }
            }

            guard let choice = best else {
                unplaced.append(word.german)
                continue
            }

            let cells = (0..<word.length).map { choice.start.offset(by: choice.direction.delta, times: $0) }
            for (offset, cell) in cells.enumerated() { grid[cell.row][cell.col] = word.letters[offset] }
            placements.append(WordSearchPlacement(word: word, start: choice.start,
                                                  direction: choice.direction, cells: cells))
            usedDirections.insert(choice.direction)
        }

        guard unplaced.isEmpty else { throw Failure.couldNotPlace(unplaced) }

        let answerCells = Set(placements.flatMap(\.cells))
        var filled = fill(grid, placements: placements, answerCells: answerCells,
                          directions: directions, options: options, seed: seed)
        if options.camouflageUmlauts {
            camouflage(&filled, placements: placements, answerCells: answerCells,
                       directions: directions, seed: seed)
        }

        return WordSearchPuzzle(size: size, grid: filled, placements: placements, seed: seed,
                                allowedBackwards: options.allowBackwards,
                                allowedDiagonals: options.allowDiagonals)
    }

    /// Every path along which `word` can be read. Used by the filler's verification pass and by
    /// the tests — if this returns two paths for an answer, the grid is ambiguous.
    static func scan(_ grid: [[Character]], for word: [Character],
                     directions: Set<WordSearchDirection>) -> [[GridPoint]] {
        guard let size = grid.first?.count, !word.isEmpty else { return [] }
        var found: [[GridPoint]] = []
        for direction in directions {
            for row in 0..<grid.count {
                for col in 0..<size {
                    let start = GridPoint(row: row, col: col)
                    let cells = (0..<word.count).map { start.offset(by: direction.delta, times: $0) }
                    guard cells.allSatisfy({ (0..<grid.count).contains($0.row) && (0..<size).contains($0.col) })
                    else { continue }
                    let reading = cells.map { grid[$0.row][$0.col] }
                    if zip(reading, word).allSatisfy({ GameLetters.equal($0, $1) }) { found.append(cells) }
                }
            }
        }
        return found
    }

    // MARK: - Placement scoring

    /// `nil` when the word can't go here at all; otherwise how good the spot is.
    ///
    /// Crossings are worth most: a grid where words share letters is far harder than one where
    /// they sit apart. A word entirely covered by letters already on the grid is refused — it
    /// would occupy no cell of its own and so isn't hidden.
    private static func score<G: RandomNumberGenerator>(
        _ letters: [Character], at start: GridPoint, direction: WordSearchDirection,
        in grid: [[Character?]], usedDirections: Set<WordSearchDirection>, using generator: inout G
    ) -> Int? {
        var crossings = 0
        for (offset, letter) in letters.enumerated() {
            let cell = start.offset(by: direction.delta, times: offset)
            if let existing = grid[cell.row][cell.col] {
                guard GameLetters.equal(existing, letter) else { return nil }
                crossings += 1
            }
        }
        guard crossings < letters.count else { return nil }

        var score = crossings * 3
        if !usedDirections.contains(direction) { score += 1 }
        score += Int.random(in: 0..<2, using: &generator)
        return score
    }

    // MARK: - Filler

    private static func fill(_ grid: [[Character?]], placements: [WordSearchPlacement],
                             answerCells: Set<GridPoint>, directions: Set<WordSearchDirection>,
                             options: Options, seed: UInt64) -> [[Character]] {
        var generator = SeededGenerator(seed: seed &* 31 &+ 7)
        var filled = grid.map { $0.map { $0 ?? " " } }
        let empties = grid.indices.flatMap { row in
            grid[row].indices.compactMap { col in grid[row][col] == nil ? GridPoint(row: row, col: col) : nil }
        }
        for cell in empties { filled[cell.row][cell.col] = GermanLetterFrequency.letter(using: &generator) }

        // Verification: the filler can spell an answer by accident, which would make a legitimate
        // trace fail. Re-roll only the offending filler cells, never an answer cell.
        for _ in 0..<max(0, options.refillAttempts) {
            var offenders: Set<GridPoint> = []
            for placement in placements {
                let paths = scan(filled, for: placement.word.letters, directions: directions)
                for path in paths where path != placement.cells && path != placement.cells.reversed() {
                    offenders.formUnion(path.filter { !answerCells.contains($0) })
                }
            }
            guard !offenders.isEmpty else { break }
            for cell in offenders.sorted(by: order) {
                filled[cell.row][cell.col] = GermanLetterFrequency.letter(using: &generator)
            }
        }
        return filled
    }

    /// Makes sure no umlaut in an answer is the only one of its kind: a lone Ä is a giveaway.
    private static func camouflage(_ grid: inout [[Character]], placements: [WordSearchPlacement],
                                   answerCells: Set<GridPoint>, directions: Set<WordSearchDirection>,
                                   seed: UInt64) {
        var generator = SeededGenerator(seed: seed &* 131 &+ 17)
        let umlauts: Set<Character> = ["Ä", "Ö", "Ü"]
        let wanted = Set(placements.flatMap(\.word.letters)).intersection(umlauts)
        guard !wanted.isEmpty else { return }

        let rare = Set(GermanLetterFrequency.rarest(8))
        var spare = grid.indices.flatMap { row in
            grid[row].indices.compactMap { col -> GridPoint? in
                let cell = GridPoint(row: row, col: col)
                guard !answerCells.contains(cell), rare.contains(grid[row][col]) else { return nil }
                return cell
            }
        }.shuffled(using: &generator)

        for umlaut in wanted.sorted() {
            var count = grid.reduce(0) { running, row in running + row.count { GameLetters.equal($0, umlaut) } }
            while count < 2, let cell = spare.popLast() {
                grid[cell.row][cell.col] = umlaut
                count += 1
            }
        }
    }

    private static func order(_ a: GridPoint, _ b: GridPoint) -> Bool {
        (a.row, a.col) < (b.row, b.col)
    }
}

/// The word search's limits. Short words only, so a grid stays phone-sized, and no ß — a grid
/// cell holding „ß“ next to a tray that says „Straße“ is fine, but respelling it as SS is not,
/// so those words simply aren't offered.
nonisolated enum WordSearchRound: GameRoundShape {
    static var requirements: GameWordRequirements {
        GameWordRequirements(
            lengthRange: 3...10,
            wordCount: 6...12,
            singleTokenOnly: true,
            eszett: .exclude,
            needsEnglish: false,
            alphabet: GameLetters.alphabet,
            blurb: "Needs at least 6 single words of 3–10 letters, without ß."
        )
    }

    /// Answered by attempting the build — placement can fail even when the counts look right.
    static func canBuild(_ words: [GameWord], seed: UInt64) -> Bool {
        (try? WordSearchGenerator.build(words: words, seed: seed)) != nil
    }
}
