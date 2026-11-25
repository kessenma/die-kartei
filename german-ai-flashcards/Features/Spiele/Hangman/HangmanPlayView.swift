//
//  HangmanPlayView.swift
//  german-ai-flashcards
//
//  Galgenmännchen itself: a clue, a row of blanks, a motif that comes apart, and thirty keys.
//
//  The words were chosen on the setup screen and arrive in the session, so this view has no error
//  state and never asks whether it has enough to play. It owns one `HangmanState` per word and
//  nothing else; everything about *what* a guess means lives in that pure type.
//

import SwiftUI
import SwiftData

struct HangmanPlayView: View {
    let session: HangmanSession
    var hapticMode: HapticFeedbackMode = .all
    let onFinish: (SpieleRoundResult) -> Void
    let onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelContext) private var modelContext

    @State private var index = 0
    @State private var state: HangmanState
    /// One entry per word played, in order.
    @State private var outcomes: [SpieleWordOutcome] = []
    @State private var startedAt = Date()
    @State private var showSummary = false
    /// Bumped on a hit and on a miss, for `.sensoryFeedback`.
    @State private var hits = 0
    @State private var misses = 0

    /// Letters pressed before the first frame. DEBUG only, and the reason is practical: the
    /// simulator can show a near-loss motif no other way.
    private let openingGuesses: [Character]

    init(session: HangmanSession, hapticMode: HapticFeedbackMode = .all,
         openingGuesses: [Character] = [],
         onFinish: @escaping (SpieleRoundResult) -> Void, onDismiss: @escaping () -> Void) {
        self.session = session
        self.hapticMode = hapticMode
        self.openingGuesses = openingGuesses
        self.onFinish = onFinish
        self.onDismiss = onDismiss
        var opening = HangmanState(word: session.words[0])
        for letter in openingGuesses { opening.guess(letter) }
        _state = State(initialValue: opening)
    }

    private var word: GameWord { state.word }

    private var clue: HangmanClue.Resolved {
        HangmanClue.resolve(for: word, mode: session.clueMode) { fileName in
            guard let deck = word.imageDeckID else { return false }
            return FileManager.default.fileExists(
                atPath: CardImageStore.url(fileName: fileName, deckID: deck).path)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: 18) {
                    clueView
                    HangmanFlatView(motif: session.motif, misses: state.missCount,
                                    mood: mood)
                        .frame(height: 170)
                        .animation(.snappy(duration: 0.25), value: state.missCount)
                    blanks
                    if state.isOver { verdict }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            VStack(spacing: 10) {
                if state.isOver {
                    Button(isLastWord ? "Ergebnis · Results" : "Weiter · Next") { advance() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    HangmanKeyboardView(state: state) { guess($0) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .padding(.top, 6)
        }
        .themedScreen()
        .sensoryFeedback(.success, trigger: hits) { old, new in
            new > old && hapticMode.playsSuccess
        }
        // A miss gets a light tap, not an error buzz: the motif already said what happened.
        .sensoryFeedback(.impact(weight: .light), trigger: misses) { old, new in
            new > old && hapticMode.playsError
        }
        // Presented from the root cover, outside any themed stack, so it sets its own tint.
        .tint(appTheme.accent(model: nil))
        .sheet(isPresented: $showSummary) {
            HangmanSummaryView(session: session, outcomes: outcomes) { onDismiss() }
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Button { finish(early: true) } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 1) {
                Text(session.topic).font(.footnote.weight(.semibold)).lineLimit(1)
                Text("Wort \(index + 1) von \(session.wordCount)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(repeating: "●", count: state.remaining)
                 + String(repeating: "○", count: state.missCount))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(state.remaining) Versuche übrig")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var clueView: some View {
        switch clue {
        case .picture(let fileName, let deckID):
            if let image = CardImageStore.loadImage(fileName: fileName, deckID: deckID,
                                                    maxPixelSize: 512) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12),
                                                style: .continuous))
            } else {
                clueText(word.english)
            }
        case .english(let text):  clueText(text)
        case .forms(let text):    clueText(text)
        case .wordType(let text): clueText(text)
        case .none:               clueText("—")
        }
    }

    private func clueText(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// The blanks row. Case-coloured by gender once solved, so the article is learned with the word.
    private var blanks: some View {
        HStack(spacing: 6) {
            ForEach(Array(state.revealed.enumerated()), id: \.offset) { _, letter in
                VStack(spacing: 3) {
                    Text(letter.map(String.init) ?? " ")
                        .font(.title2.weight(.bold))
                        .monospaced()
                    Rectangle().frame(height: 2).opacity(letter == nil ? 0.35 : 0.12)
                }
                .frame(width: 22)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.2), value: state.guessed.count)
    }

    @ViewBuilder
    private var verdict: some View {
        VStack(spacing: 4) {
            Text(state.isWon ? "Geschafft!" : word.display)
                .font(.title3.weight(.semibold))
                .foregroundStyle(state.isWon ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Text(state.isWon ? word.english : "Das Wort war „\(word.german)“")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var mood: HangmanFlatView.Mood {
        if state.isWon { return .jubel }
        if state.isLost { return .kummer }
        return .warten
    }

    private var isLastWord: Bool { index + 1 >= session.wordCount }

    // MARK: - Play

    private func guess(_ letter: Character) {
        switch state.guess(letter) {
        case .hit:     hits += 1
        case .miss:    misses += 1
        case .ignored: break
        }
    }

    private func advance() {
        outcomes.append(SpieleWordOutcome(word: state.word, solved: state.isWon,
                                          clean: state.isCleanWin, misses: state.missCount))
        guard !isLastWord else {
            finish(early: false)
            return
        }
        index += 1
        state = HangmanState(word: session.words[index])
    }

    private func finish(early: Bool) {
        // A word abandoned mid-guess is not recorded either way — it was neither solved nor failed.
        onFinish(SpieleRoundResult(
            kind: .hangman, topic: session.topic, deckID: session.deckID,
            outcomes: outcomes, durationSeconds: Int(Date().timeIntervalSince(startedAt)),
            toppedUp: nil
        ))
        if early { onDismiss() } else { showSummary = true }
    }
}
