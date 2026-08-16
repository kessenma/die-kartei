//
//  ArticleGameView.swift
//  german-ai-flashcards
//
//  The der/die/das game: one noun at a time, three big color-coded article buttons, instant
//  feedback. A correct tap auto-advances; a miss reveals the right article plus a pattern
//  hint (from `ArticleRules`) and waits for "Weiter", so the lesson lands before moving on.
//
//  Presented immersively via `ActivityRouter` (`.articleGame`), exactly like `.matching`.
//  On round complete it hands an `ArticleRoundResult` up so `ContentView` can persist it
//  (`ArticleGameService.recordRound` — stats, streak, learner profile) and gets
//  `ArticleRoundFeedback` back for "missed again" and personal-best callouts.
//
//  Color convention: der = blue, die = red, das = green — fixed per article so the colors
//  themselves become a memory aid. Mistakes never flash red; they shake and dim instead,
//  so red stays owned by `die`.
//

import SwiftUI
import Combine

struct ArticleGameView: View {
    let session: ArticleGameSession
    /// Gates the right/wrong vibrations (Settings ▸ Cards ▸ Haptics).
    var hapticMode: HapticFeedbackMode = .all
    /// Called once per completed round; returns history-aware feedback for the summary.
    var onComplete: (ArticleRoundResult) -> ArticleRoundFeedback
    var onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme

    private enum Phase {
        case answering
        /// A wrong tap revealed the answer; waiting for "Weiter".
        case revealed(wrongPick: GermanArticle)
        /// A correct tap; brief flash before auto-advance.
        case correct
    }

    // Play state.
    @State private var questions: [ArticleQuestion] = []
    @State private var index = 0
    @State private var phase: Phase = .answering
    @State private var outcomes: [ArticleAnswerOutcome] = []
    @State private var combo = 0
    @State private var bestCombo = 0
    @State private var correctCount = 0      // drives the success haptic
    @State private var wrongCount = 0        // drives the error haptic
    @State private var wrongShakes = 0       // drives the shake animation
    @State private var feedback: ArticleRoundFeedback = .empty

    // Timing.
    @State private var sessionStart: Date?
    @State private var finishedAt: Date?
    @State private var displaySeconds = 0
    @State private var showSummary = false
    @State private var showRules = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Already the systemGroupedBackground Klar uses, so ThemedBackground is a no-op there
            // and paints each identity theme's ground (Kritzel's ruled paper, etc.) elsewhere.
            ThemedBackground().ignoresSafeArea()

            if session.questions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    topBar
                    progressHeader
                    Spacer()
                    if index < questions.count {
                        questionCard(questions[index])
                    }
                    Spacer()
                    answerArea
                }
            }

            if showSummary {
                summaryOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .onAppear { if questions.isEmpty { startRound() } }
        .onReceive(ticker) { _ in
            guard let start = sessionStart, finishedAt == nil else { return }
            displaySeconds = Int(Date().timeIntervalSince(start))
        }
        .sensoryFeedback(.success, trigger: correctCount) { old, new in
            new > old && hapticMode.playsSuccess
        }
        .sensoryFeedback(.error, trigger: wrongCount) { old, new in
            new > old && hapticMode.playsError
        }
        .sheet(isPresented: $showRules) {
            ArticleRulesSheet()
        }
        // No model here, so on Klar this is `.accentColor` (identical); the identity themes assert
        // their own accent for the progress bar and the "Weiter" button.
        .tint(appTheme.accent(model: nil))
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
            Button {
                showRules = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
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
                        .fill(.tint)   // follows the themed tint (accentColor on Klar)
                        .frame(width: geo.size.width * progressFraction)
                }
            }
            .frame(height: 6)

            HStack {
                Label(timeString(displaySeconds), systemImage: "timer")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(min(index + 1, questions.count)) / \(questions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("×\(combo)", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(combo >= 3 ? .orange : .clear)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var progressFraction: CGFloat {
        guard !questions.isEmpty else { return 0 }
        return CGFloat(outcomes.count) / CGFloat(questions.count)
    }

    // MARK: - Question

    @ViewBuilder
    private func questionCard(_ question: ArticleQuestion) -> some View {
        VStack(spacing: 12) {
            Text(revealedArticlePrefix + question.noun)
                // Klar/Sanft keep the rounded display; Kritzel/Grundform take their own face.
                .themedLabel(.system(size: 40, weight: .bold, design: .rounded), size: 40)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(revealColor(question))
                .contentTransition(.opacity)
                .modifier(ShakeEffect(shakes: CGFloat(wrongShakes)))
                .animation(.linear(duration: 0.4), value: wrongShakes)

            Text(question.english)
                .font(.title3)
                .foregroundStyle(.secondary)

            hintText(question)
                .padding(.top, 6)
        }
        .padding(.horizontal, 24)
    }

    /// "die " once the answer is revealed (right or wrong), empty while guessing.
    private var revealedArticlePrefix: String {
        switch phase {
        case .answering: ""
        default: questions[index].article.rawValue + " "
        }
    }

    private func revealColor(_ question: ArticleQuestion) -> Color {
        switch phase {
        case .answering: .primary
        default: question.article.color
        }
    }

    /// After a miss: the best pattern tip for this noun, or the honest "just memorize it".
    @ViewBuilder
    private func hintText(_ question: ArticleQuestion) -> some View {
        if case .revealed = phase {
            Group {
                if let rule = ArticleRules.hint(for: question.noun, article: question.article) {
                    Label(rule.hintLine(for: question.noun), systemImage: "lightbulb.fill")
                } else {
                    Label(ArticleRules.noRuleHint(for: question.noun, article: question.article), systemImage: "brain")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Answers

    private var answerArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(GermanArticle.allCases) { article in
                    articleButton(article)
                }
            }

            // Reserve the row so the board doesn't jump when "Weiter" appears.
            Button {
                advance()
            } label: {
                Text("Weiter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .opacity(isRevealed ? 1 : 0)
            .disabled(!isRevealed)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private var isRevealed: Bool {
        if case .revealed = phase { return true }
        return false
    }

    private func articleButton(_ article: GermanArticle) -> some View {
        let visual = buttonVisual(article)
        return Button {
            handleTap(article)
        } label: {
            VStack(spacing: 2) {
                Text(article.rawValue)
                    .font(.title2.weight(.bold))
                Text(article.genderGerman)
                    .font(.caption2)
                    .opacity(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(visual.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(visual.stroke, lineWidth: visual.strokeWidth)
            )
            .foregroundStyle(visual.foreground)
            .opacity(visual.dimmed ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isAnswering)
    }

    private var isAnswering: Bool {
        if case .answering = phase { return true }
        return false
    }

    private struct ButtonVisual {
        var fill: Color
        var stroke: Color
        var strokeWidth: CGFloat
        var foreground: Color
        var dimmed: Bool
    }

    private func buttonVisual(_ article: GermanArticle) -> ButtonVisual {
        let correct = questions.indices.contains(index) ? questions[index].article : nil

        switch phase {
        case .answering:
            return ButtonVisual(
                fill: article.color.opacity(0.12),
                stroke: article.color.opacity(0.5),
                strokeWidth: 1.5,
                foreground: Color.primary,
                dimmed: false
            )
        case .correct:
            let isTheAnswer = article == correct
            return ButtonVisual(
                fill: isTheAnswer ? article.color : article.color.opacity(0.12),
                stroke: isTheAnswer ? article.color : article.color.opacity(0.3),
                strokeWidth: 1.5,
                foreground: isTheAnswer ? .white : .primary,
                dimmed: !isTheAnswer
            )
        case .revealed(let wrongPick):
            let isTheAnswer = article == correct
            return ButtonVisual(
                fill: isTheAnswer ? article.color : article.color.opacity(0.12),
                stroke: isTheAnswer ? article.color : article.color.opacity(0.3),
                strokeWidth: 1.5,
                foreground: isTheAnswer ? .white : .primary,
                dimmed: !isTheAnswer && article != wrongPick
            )
        }
    }

    // MARK: - Game logic

    private func startRound() {
        questions = session.questions.shuffled()
        index = 0
        phase = .answering
        outcomes = []
        combo = 0
        bestCombo = 0
        feedback = .empty
        sessionStart = nil
        finishedAt = nil
        displaySeconds = 0
        showSummary = false
    }

    private func handleTap(_ picked: GermanArticle) {
        guard isAnswering, questions.indices.contains(index) else { return }
        if sessionStart == nil { sessionStart = Date() }
        let question = questions[index]

        if picked == question.article {
            correctCount += 1
            combo += 1
            bestCombo = max(bestCombo, combo)
            outcomes.append(ArticleAnswerOutcome(
                noun: question.noun, article: question.article, english: question.english,
                firstTry: true, wrongPick: nil
            ))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                phase = .correct
            }
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                // Only advance if this question is still showing (guards a fast restart).
                if case .correct = phase { advance() }
            }
        } else {
            wrongCount += 1
            wrongShakes += 1
            combo = 0
            outcomes.append(ArticleAnswerOutcome(
                noun: question.noun, article: question.article, english: question.english,
                firstTry: false, wrongPick: picked
            ))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                phase = .revealed(wrongPick: picked)
            }
        }
    }

    private func advance() {
        if index + 1 < questions.count {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                index += 1
                phase = .answering
            }
        } else {
            finish()
        }
    }

    private func finish() {
        finishedAt = Date()
        let duration = sessionStart.map { Int(finishedAt!.timeIntervalSince($0)) } ?? 0
        displaySeconds = duration
        feedback = onComplete(ArticleRoundResult(outcomes: outcomes, durationSeconds: duration))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showSummary = true }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Not enough nouns",
                systemImage: "questionmark.square.dashed",
                description: Text("This source needs a few more nouns with articles to play a round.")
            )
            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Summary

    private var accuracyPercent: Int {
        guard !outcomes.isEmpty else { return 0 }
        let firstTry = outcomes.filter(\.firstTry).count
        return Int((Double(firstTry) / Double(outcomes.count) * 100).rounded())
    }

    private var summaryOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text("Round complete")
                        .font(.title2.bold())

                    if feedback.isPersonalBest {
                        Label("New personal best for this source!", systemImage: "trophy.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    VStack(spacing: 12) {
                        summaryStat("Time", timeString(displaySeconds), "timer")
                        summaryStat("First-try accuracy", "\(accuracyPercent)%", "checkmark.seal")
                        if bestCombo >= 3 {
                            summaryStat("Best streak", "×\(bestCombo)", "flame.fill")
                        }
                    }

                    perArticleBreakdown

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
                .frame(maxWidth: 360)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// This round's hit rate per article — makes "die is your weak spot" visible at a glance.
    private var perArticleBreakdown: some View {
        VStack(spacing: 8) {
            ForEach(GermanArticle.allCases) { article in
                let seen = outcomes.filter { $0.article == article }
                if !seen.isEmpty {
                    let hits = seen.filter(\.firstTry).count
                    HStack(spacing: 10) {
                        Text(article.rawValue)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(article.color)
                            .frame(width: 36, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(article.color.opacity(0.15))
                                Capsule()
                                    .fill(article.color)
                                    .frame(width: geo.size.width * CGFloat(hits) / CGFloat(seen.count))
                            }
                        }
                        .frame(height: 8)
                        Text("\(hits)/\(seen.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// The nouns missed this round, with lifetime context and the pattern tip when one exists.
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
                    if let repeated = miss.repeatedWrongArticle {
                        Text("You keep reaching for “\(repeated.rawValue)”.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let rule = ArticleRules.hint(for: miss.noun, article: miss.article) {
                        Text("\(rule.title) → \(rule.reliability.label) \(miss.article.rawValue)")
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

    private func timeString(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }
}

/// A quick horizontal shake for wrong answers — feedback without using red.
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(shakes * .pi * 6) * 6, y: 0))
    }
}

#Preview("Article game · 4 themes") {
    // Swipe the tabs to compare the four grounds/faces; der/die/das keep their GenderPalette colors.
    let session = ArticleGameSession(
        questions: [
            ArticleQuestion(noun: "Tisch", article: .der, english: "table"),
            ArticleQuestion(noun: "Blume", article: .die, english: "flower"),
            ArticleQuestion(noun: "Haus", article: .das, english: "house"),
        ],
        topic: "Preview"
    )
    return TabView {
        ForEach(AppTheme.allCases) { theme in
            ArticleGameView(session: session, onComplete: { _ in .empty }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}
