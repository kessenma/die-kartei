@testable import DieKarteiCore
import SwiftUI

/// The word games, on the iOS app's own engines (HangmanState, WordSearchGenerator,
/// GameWordFitter) with the Goethe list as the word source.
struct SpieleView: View {
    @AppStorage("level") var levelRaw = GoetheLevel.a1.rawValue

    var body: some View {
        List {
            Section {
                Picker("Wörter aus", selection: $levelRaw) {
                    ForEach(GoetheLevel.allCases) { level in
                        Text("Goethe \(level.rawValue)").tag(level.rawValue)
                    }
                }
            }
            Section {
                NavigationLink { HangmanView() } label: {
                    gameRow(.hangman)
                }
                NavigationLink { WortsucheView() } label: {
                    gameRow(.wordSearch)
                }
            }
        }
        .navigationTitle("Spiele")
    }

    func gameRow(_ kind: SpielKind) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kind.germanTitle)
            Text("\(kind.blurb) · ~\(kind.minutes) min")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The Goethe words of the chosen level as game words, fitted to a game's limits.
@MainActor
enum GameWords {
    static func round<Shape: GameRoundShape>(_ shape: Shape.Type, levelRaw: String, seed: UInt64) -> [GameWord] {
        let level = GoetheLevel(rawValue: levelRaw) ?? .a1
        let words = GoetheVocabService.entries(for: level).compactMap { entry in
            GameWord(german: entry.word, english: entry.translation ?? "", article: entry.article,
                     wordType: entry.wordType)
        }
        let fit = GameWordFitter.fit(words, to: Shape.requirements)
        return GameWordFitter.round(shape, from: fit, seed: seed) ?? []
    }

    static func newSeed() -> UInt64 { UInt64.random(in: 1...UInt64.max) }
}

// MARK: - Galgenmännchen

struct HangmanView: View {
    @AppStorage("level") var levelRaw = GoetheLevel.a1.rawValue
    @State var words: [GameWord] = []
    @State var index = 0
    @State var state: HangmanState?
    @State var won = 0
    /// Logged at the end or on leaving (abandoned time counts), as iOS's SpieleScoringService.
    @State var studyRound = StudyRound { .games($0) }
    @Environment(\.colorScheme) var scheme

    let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

    var body: some View {
        VStack(spacing: 16) {
            if let state {
                Text("Wort \(index + 1) von \(words.count) · gelöst: \(won)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                gallows(misses: state.missCount)
                    .frame(height: 140)
                Text(state.word.english)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                blanks(state)
                if state.isOver {
                    VStack(spacing: 8) {
                        // Giving up reveals every letter, so a reveal counts as won by the letters alone.
                        Text(state.isWon && !state.isLost ? "Gelöst!" : "Das Wort war:")
                            .font(.headline)
                        Text(state.word.display).font(.title2)
                        Button(index + 1 < words.count ? "Nächstes Wort" : "Neue Runde") { next() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("Noch \(state.remaining) Fehler frei")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    keyboard(state)
                    Button("Aufgeben") { self.state?.reveal() }
                        .font(.footnote)
                }
            } else {
                ProgressView()
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Galgenmännchen")
        .onAppear { if words.isEmpty { newRound() } }
        .onDisappear { studyRound.finish() }
    }

    func blanks(_ state: HangmanState) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(state.revealed.enumerated()), id: \.offset) { _, letter in
                Text(letter.map { String($0) } ?? "_")
                    .font(.title2)
                    .frame(minWidth: 18)
            }
        }
    }

    func keyboard(_ state: HangmanState) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(GameLetters.hangmanKeys.map { String($0) }, id: \.self) { key in
                let letter = Character(key)
                let tried = state.guessed.contains(letter)
                Button {
                    let result = self.state?.guess(letter)
                    if case .some(.hit) = result, self.state?.isWon == true { won += 1 }
                } label: {
                    Text(key)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .tint(tried ? (state.word.letters.contains(letter) ? Color.green : Color.gray) : Color.accentColor)
                .disabled(tried)
            }
        }
    }

    /// A simple figure that gains a part per miss (six, like the iOS motifs).
    func gallows(misses: Int) -> some View {
        let ink = scheme == .dark ? Color.white : Color.black
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Circle().stroke(ink, lineWidth: 3).frame(width: 30, height: 30).opacity(misses >= 1 ? 1 : 0.1)
                HStack(spacing: 0) {
                    Rectangle().fill(ink).frame(width: 26, height: 3).opacity(misses >= 3 ? 1 : 0.1)
                    Rectangle().fill(ink).frame(width: 3, height: 44).opacity(misses >= 2 ? 1 : 0.1)
                    Rectangle().fill(ink).frame(width: 26, height: 3).opacity(misses >= 4 ? 1 : 0.1)
                }
                HStack(spacing: 18) {
                    Rectangle().fill(ink).frame(width: 3, height: 40).rotationEffect(.degrees(20)).opacity(misses >= 5 ? 1 : 0.1)
                    Rectangle().fill(ink).frame(width: 3, height: 40).rotationEffect(.degrees(-20)).opacity(misses >= 6 ? 1 : 0.1)
                }
            }
        }
    }

    func newRound() {
        studyRound.start()
        words = GameWords.round(HangmanRound.self, levelRaw: levelRaw, seed: GameWords.newSeed())
        index = 0
        won = 0
        state = words.first.map { HangmanState(word: $0) }
    }

    func next() {
        // A finished word: solved counts. A word left mid-guess doesn't, as on iOS.
        if let state, state.isOver, state.isWon, !state.isLost { studyRound.add() }
        if index + 1 < words.count {
            index += 1
            state = HangmanState(word: words[index])
        } else {
            studyRound.finish()
            newRound()
        }
    }
}

// MARK: - Wortsuche

/// Tap a word's first letter, then its last. The grid and the check are the iOS engine's.
struct WortsucheView: View {
    @AppStorage("level") var levelRaw = GoetheLevel.a1.rawValue
    @State var puzzle: WordSearchPuzzle?
    @State var found: Set<String> = []
    @State var start: GridPoint?
    @State var message = ""
    @State var studyRound = StudyRound { .games($0) }
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 12) {
            if let puzzle {
                Text("\(found.count) von \(puzzle.placements.count) gefunden")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                grid(puzzle)
                Text(message).font(.footnote).frame(minHeight: 18)
                wordList(puzzle)
                if found.count == puzzle.placements.count {
                    Button("Neues Rätsel") { newPuzzle() }.buttonStyle(.borderedProminent)
                }
            } else {
                Text(message)
                ProgressView()
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Wortsuche")
        .onAppear { if puzzle == nil { newPuzzle() } }
        .onDisappear { studyRound.finish() }
    }

    func grid(_ puzzle: WordSearchPuzzle) -> some View {
        let foundCells = Set(puzzle.placements.filter { found.contains($0.id) }.flatMap(\.cells))
        return VStack(spacing: 2) {
            ForEach(0..<puzzle.size, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<puzzle.size, id: \.self) { col in
                        let point = GridPoint(row: row, col: col)
                        Text(puzzle.letter(at: point).map { String($0) } ?? "")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background(cellColor(point, found: foundCells))
                            .onTapGesture { tap(point, in: puzzle) }
                    }
                }
            }
        }
    }

    func cellColor(_ point: GridPoint, found: Set<GridPoint>) -> Color {
        if point == start { return Color.orange.opacity(0.5) }
        if found.contains(point) { return Color.green.opacity(0.35) }
        return Color.gray.opacity(0.12)
    }

    func wordList(_ puzzle: WordSearchPuzzle) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(puzzle.placements) { placement in
                Text(found.contains(placement.id) ? placement.word.german : placement.word.english)
                    .font(.caption)
                    .strikethrough(found.contains(placement.id))
                    .foregroundStyle(found.contains(placement.id) ? Color.secondary : Color.primary)
            }
        }
    }

    func tap(_ point: GridPoint, in puzzle: WordSearchPuzzle) {
        guard let first = start else {
            start = point
            message = "Jetzt den letzten Buchstaben"
            return
        }
        start = nil
        guard let cells = line(from: first, to: point) else {
            message = "Gerade Linie: waagerecht, senkrecht oder diagonal"
            return
        }
        if let placement = puzzle.placement(matching: cells), !found.contains(placement.id) {
            found.insert(placement.id)
            studyRound.add()
            if found.count == puzzle.placements.count { studyRound.finish() }
            message = "\(placement.word.display) = \(placement.word.english)"
        } else {
            message = "Kein Wort"
        }
    }

    /// The straight run of cells between two taps, or nil when they aren't on one line.
    func line(from a: GridPoint, to b: GridPoint) -> [GridPoint]? {
        let dr = b.row - a.row, dc = b.col - a.col
        guard dr == 0 || dc == 0 || abs(dr) == abs(dc), (dr, dc) != (0, 0) else { return nil }
        let steps = max(abs(dr), abs(dc))
        let sr = dr.signum(), sc = dc.signum()
        return (0...steps).map { GridPoint(row: a.row + $0 * sr, col: a.col + $0 * sc) }
    }

    func newPuzzle() {
        studyRound.finish()   // a grid left half done still banks its time, as on iOS
        studyRound.start()
        found = []
        start = nil
        message = ""
        let seed = GameWords.newSeed()
        // Ten columns is what fits a phone, so the words stay under that.
        let words = Array(GameWords.round(WordSearchRound.self, levelRaw: levelRaw, seed: seed)
            .filter { $0.length <= 9 }.prefix(8))
        let options = WordSearchGenerator.Options(size: 10)
        puzzle = try? WordSearchGenerator.build(words: words, options: options, seed: seed)
        if puzzle == nil { message = "Kein Rätsel gebaut, nochmal versuchen" }
    }
}
