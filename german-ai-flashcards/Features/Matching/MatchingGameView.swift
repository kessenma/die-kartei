//
//  MatchingGameView.swift
//  german-ai-flashcards
//
//  The card-matching recognition game: a two-column grid of German ↔ English tiles the learner
//  pairs off against the clock. It's the recognition-based counterpart to the flashcard player —
//  many quick form↔meaning retrievals per minute, with immediate clear/flash feedback.
//
//  Presented immersively via `ActivityRouter` (`.matching`), exactly like `.cardDeck`. On round
//  complete it hands a per-pair `MatchingRoundResult` up so `ContentView` can persist it (deck
//  stats + streak via `DeckStore.saveQuizResult`, pair history via `MatchingStatsService`) and
//  gets `MatchingRoundFeedback` back — the summary uses it for "missed again" and personal-best
//  callouts without touching storage itself.
//

import SwiftUI
import Combine

struct MatchingGameView: View {
    let session: MatchingSession
    /// Gates the right/wrong vibrations (Settings ▸ Cards ▸ Haptics).
    var hapticMode: HapticFeedbackMode = .all
    /// Called once per completed round; returns history-aware feedback for the summary.
    var onComplete: (MatchingRoundResult) -> MatchingRoundFeedback
    var onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme

    // Tiles for each column, shuffled independently so the two sides never line up.
    @State private var germanTiles: [MatchTile] = []
    @State private var englishTiles: [MatchTile] = []

    // Play state.
    @State private var matched: Set<Int> = []          // pairIDs cleared from the board
    @State private var taintedPairs: Set<Int> = []      // pairIDs involved in a wrong attempt
    @State private var selectedGerman: MatchTile?
    @State private var selectedEnglish: MatchTile?
    @State private var wrongPair: (UUID, UUID)?         // the two tiles briefly flashing red
    @State private var firstTryMatches = 0
    @State private var wrongCount = 0                   // drives the error haptic
    @State private var confusionLog: [Int: [String]] = [:] // pairID → wrong English picks this round
    @State private var feedback: MatchingRoundFeedback = .empty

    // Timing. The clock runs from the moment the board appears, not from the first tap — the
    // thinking time before that first tap is part of the round.
    @State private var sessionStart: Date?
    @State private var finishedAt: Date?
    @State private var displaySeconds = 0
    @State private var showSummary = false
    /// Swaps the "how to play" hint for the match counter once the learner is under way.
    @State private var hasTapped = false

    /// `@State`, not `let`: a stored property would be rebuilt every time `ContentView` re-renders
    /// the cover, and `onReceive` would resubscribe to the fresh publisher and restart its interval
    /// — which is how the clock ends up stuck. As state it's created once per round view.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// The generating model's accent, or the app accent for bundled decks with no model.
    private var brandAccent: Color { session.generatorModel?.theme.accent ?? .accentColor }

    var body: some View {
        ZStack {
            // Klar keeps the exact system ground; the identity themes paint their own.
            if appTheme == .klar {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            } else {
                ThemedBackground().ignoresSafeArea()
            }

            if session.cards.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    topBar
                    progressHeader
                    board
                }
            }

            if showSummary {
                summaryOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .tint(brandAccent)
        .onAppear { if germanTiles.isEmpty { startRound() } }
        .onReceive(ticker) { _ in
            guard let start = sessionStart, finishedAt == nil else { return }
            displaySeconds = Int(Date().timeIntervalSince(start))
        }
        .sensoryFeedback(.success, trigger: matched.count) { old, new in
            // `new > old` keeps the reset to 0 on "Play again" from buzzing.
            new > old && hapticMode.playsSuccess
        }
        .sensoryFeedback(.error, trigger: wrongCount) { old, new in
            new > old && hapticMode.playsError
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            Spacer()
            Text(session.topic)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Label(timeString(displaySeconds), systemImage: "timer")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var progressHeader: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .systemGray5))
                    Capsule()
                        .fill(brandAccent)
                        .frame(width: geo.size.width * progressFraction)
                }
            }
            .frame(height: 6)

            Text(hasTapped
                 ? "\(matched.count) / \(session.pairCount) matched"
                 : "Tap a German word, then its English match.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !session.tintLegend.isEmpty {
                tintLegend
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// What the German tiles' colors mean, when the session color-codes them.
    private var tintLegend: some View {
        HStack(spacing: 10) {
            ForEach(session.tintLegend) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 7, height: 7)
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.top, 2)
    }

    private var progressFraction: CGFloat {
        guard session.pairCount > 0 else { return 0 }
        return CGFloat(matched.count) / CGFloat(session.pairCount)
    }

    // MARK: - Board

    private var board: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                column(germanTiles)
                column(englishTiles)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func column(_ tiles: [MatchTile]) -> some View {
        VStack(spacing: 10) {
            ForEach(tiles.filter { !matched.contains($0.pairID) }) { tile in
                tileButton(tile)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func tileButton(_ tile: MatchTile) -> some View {
        let visual = visual(for: tile)
        return Button {
            handleTap(tile)
        } label: {
            tileLabel(tile)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(visual.foreground)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: appTheme.innerRadius(14), style: .continuous)
                        .fill(visual.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: appTheme.innerRadius(14), style: .continuous)
                        .strokeBorder(visual.stroke, lineWidth: visual.strokeWidth)
                )
        }
        .buttonStyle(.plain)
    }

    /// German tiles color their article by gender (der blue / die red / das green) via `Text.gendered`
    /// — the noun still follows the tile's state foreground. English tiles stay plain.
    private func tileLabel(_ tile: MatchTile) -> Text {
        tile.side == .german ? Text.gendered(tile.text, article: tile.article) : Text(tile.text)
    }

    private struct TileVisual {
        var fill: Color
        var stroke: Color
        var strokeWidth: CGFloat
        var foreground: Color
    }

    private func visual(for tile: MatchTile) -> TileVisual {
        if let wrong = wrongPair, wrong.0 == tile.id || wrong.1 == tile.id {
            return TileVisual(fill: .red.opacity(0.18), stroke: .red, strokeWidth: 2, foreground: .red)
        }
        if selectedGerman?.id == tile.id || selectedEnglish?.id == tile.id {
            return TileVisual(fill: brandAccent.opacity(0.18), stroke: brandAccent, strokeWidth: 2, foreground: brandAccent)
        }
        if let tint = tint(for: tile) {
            return TileVisual(
                fill: tint.opacity(0.14),
                stroke: tint.opacity(0.55),
                strokeWidth: 1.5,
                foreground: .primary
            )
        }
        return TileVisual(
            fill: Color(uiColor: .secondarySystemGroupedBackground),
            stroke: Color(uiColor: .systemGray4),
            strokeWidth: 1,
            foreground: .primary
        )
    }

    /// The session's color coding for this tile, if any. German column only — see
    /// `MatchingSession.germanTileTints`.
    private func tint(for tile: MatchTile) -> Color? {
        guard tile.side == .german else { return nil }
        return session.germanTileTints[tile.text.lowercased()]
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Not enough cards",
                systemImage: "square.grid.2x2",
                description: Text("This deck needs a few more word pairs to play a matching round.")
            )
            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Summary

    private var summaryOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Round complete")
                    .font(.title2.bold())

                if feedback.isPersonalBest {
                    Label("New personal best for this deck!", systemImage: "trophy.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                VStack(spacing: 12) {
                    summaryStat("Time", timeString(displaySeconds), "timer")
                    summaryStat("First-try accuracy", "\(accuracyPercent)%", "checkmark.seal")
                    summaryStat("Pairs", "\(session.pairCount)", "square.grid.2x2")
                }

                if !feedback.misses.isEmpty {
                    missRecap
                }

                VStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showSummary = false }
                        startRound()
                    } label: {
                        Text("Play again")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Done", action: onDismiss)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(40)
        }
    }

    /// The pairs that cost a first-try this round, with lifetime context: a "missed ×N" badge
    /// once a pair is a repeat offender and the wrong meaning it keeps being paired with.
    private var missRecap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Worth another look")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(feedback.misses.prefix(4)) { miss in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(miss.displayGerman) — \(miss.english)")
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if miss.timesMissed >= 2 {
                            Text("missed ×\(miss.timesMissed)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red.opacity(0.12), in: Capsule())
                        }
                    }
                    if let confusion = miss.repeatedConfusion {
                        Text("You keep pairing it with “\(confusion)”.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if feedback.misses.count > 4 {
                Text("+ \(feedback.misses.count - 4) more")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func summaryStat(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
        }
    }

    private var accuracyPercent: Int {
        guard session.pairCount > 0 else { return 0 }
        return Int((Double(firstTryMatches) / Double(session.pairCount) * 100).rounded())
    }

    // MARK: - Game logic

    private func startRound() {
        let pairs = session.cards.enumerated().map { ($0.offset, $0.element) }
        germanTiles = pairs.map { MatchTile(pairID: $0.0, text: germanText($0.1), side: .german, article: $0.1.article) }.shuffled()
        englishTiles = pairs.map { MatchTile(pairID: $0.0, text: $0.1.englishTranslation, side: .english) }.shuffled()
        matched = []
        taintedPairs = []
        selectedGerman = nil
        selectedEnglish = nil
        wrongPair = nil
        firstTryMatches = 0
        confusionLog = [:]
        feedback = .empty
        hasTapped = false
        sessionStart = Date()
        finishedAt = nil
        displaySeconds = 0
        showSummary = false
    }

    private func handleTap(_ tile: MatchTile) {
        // Ignore taps on cleared tiles or while a wrong pair is still flashing.
        guard !matched.contains(tile.pairID), wrongPair == nil else { return }
        hasTapped = true

        switch tile.side {
        case .german:
            selectedGerman = (selectedGerman?.id == tile.id) ? nil : tile
        case .english:
            selectedEnglish = (selectedEnglish?.id == tile.id) ? nil : tile
        }

        guard let g = selectedGerman, let e = selectedEnglish else { return }

        if g.pairID == e.pairID {
            if !taintedPairs.contains(g.pairID) { firstTryMatches += 1 }
            selectedGerman = nil
            selectedEnglish = nil
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                _ = matched.insert(g.pairID)
            }
            if matched.count == session.cards.count { finish() }
        } else {
            taintedPairs.insert(g.pairID)
            taintedPairs.insert(e.pairID)
            // The mistake by name: this German word was paired with that wrong English meaning.
            confusionLog[g.pairID, default: []].append(e.text)
            wrongCount += 1
            let flashing = (g.id, e.id)
            wrongPair = flashing
            Task {
                try? await Task.sleep(for: .milliseconds(550))
                // Only clear if this is still the pair we flashed (guards against a fast restart).
                if let current = wrongPair, current == flashing {
                    wrongPair = nil
                    selectedGerman = nil
                    selectedEnglish = nil
                }
            }
        }
    }

    private func finish() {
        finishedAt = Date()
        let duration = sessionStart.map { Int(finishedAt!.timeIntervalSince($0)) } ?? 0
        displaySeconds = duration

        let outcomes = session.cards.enumerated().map { index, card in
            MatchingPairOutcome(
                german: card.germanWord,
                article: card.article,
                english: card.englishTranslation,
                firstTry: !taintedPairs.contains(index),
                wrongEnglishPicks: confusionLog[index] ?? []
            )
        }
        feedback = onComplete(MatchingRoundResult(outcomes: outcomes, durationSeconds: duration))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showSummary = true }
    }

    private func germanText(_ card: VocabCard) -> String {
        card.germanWord.withArticle(card.article)
    }

    private func timeString(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }
}

/// One tile on the matching board. The German and English tiles of a pair share a `pairID`.
private struct MatchTile: Identifiable, Equatable {
    let id = UUID()
    let pairID: Int
    let text: String
    let side: Side
    /// The noun's article on a german tile, so the board can color der/die/das. `nil` on english
    /// tiles and on german words that aren't articled nouns.
    var article: String? = nil

    enum Side { case german, english }
}

#Preview("Matching game · 4 themes") {
    let cards = [
        VocabCard(germanWord: "Hund", englishTranslation: "dog", wordType: "noun", article: "der"),
        VocabCard(germanWord: "Blume", englishTranslation: "flower", wordType: "noun", article: "die"),
        VocabCard(germanWord: "Haus", englishTranslation: "house", wordType: "noun", article: "das"),
        VocabCard(germanWord: "Katze", englishTranslation: "cat", wordType: "noun", article: "die"),
    ]
    let session = MatchingSession(cards: cards, topic: "Preview Deck")
    return ForEach(AppTheme.allCases) { theme in
        MatchingGameView(session: session, onComplete: { _ in .empty }, onDismiss: {})
            .environment(\.appTheme, theme)
    }
}
