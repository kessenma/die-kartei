//
//  PrepositionCaseGameView.swift
//  german-ai-flashcards
//
//  The Kasus drill: one preposition at a time, four case buttons (Akkusativ · Dativ · Wechsel ·
//  Genitiv), instant feedback. A correct tap auto-advances; a miss reveals the case with its
//  article forms and a worked example — both sentences for a two-way preposition, so the
//  Wohin/Wo contrast is what you actually see — and waits for "Weiter".
//
//  Presented immersively via `ActivityRouter` (`.prepositionCase`), exactly like `.articleGame`.
//  On round complete it hands a `PrepositionRoundResult` up so `ContentView` can persist it
//  (`PrepositionService.recordRound` — stats, streak, learner profile) and gets a
//  `PrepositionRoundFeedback` back for "missed again" and personal-best callouts.
//
//  Color convention: each case owns a fixed color (see `CasePalette`), deliberately
//  clear of the der/die/das gender hues. Mistakes shake and dim rather than flashing red.
//

import SwiftUI
import Combine

struct PrepositionCaseGameView: View {
    let session: PrepositionCaseSession
    /// Gates the right/wrong vibrations (Settings ▸ Cards ▸ Haptics).
    var hapticMode: HapticFeedbackMode = .all
    /// How much of the 3D scene to show, and when. `teaching` puts the answer on the question
    /// side, which is why answers given under it are stamped `scaffolded`.
    var pictureMode: PrepositionPictureMode = .on
    /// Called once per completed round; returns history-aware feedback for the summary.
    var onComplete: (PrepositionRoundResult) -> PrepositionRoundFeedback
    var onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme

    private enum Phase {
        case answering
        /// A wrong tap revealed the answer; waiting for "Weiter".
        case revealed(wrongPick: PrepositionCase)
        /// A correct tap; brief flash before auto-advance.
        case correct
    }

    // Play state.
    @State private var questions: [PrepositionQuestion] = []
    @State private var index = 0
    @State private var phase: Phase = .answering
    @State private var outcomes: [PrepositionAnswerOutcome] = []
    @State private var combo = 0
    @State private var bestCombo = 0
    @State private var correctCount = 0      // drives the success haptic
    @State private var wrongCount = 0        // drives the error haptic
    @State private var wrongShakes = 0       // drives the shake animation
    @State private var feedback: PrepositionRoundFeedback = .empty

    // Timing.
    @State private var sessionStart: Date?
    @State private var finishedAt: Date?
    @State private var displaySeconds = 0
    @State private var showSummary = false
    @State private var showRules = false

    /// `@State`, not `let`: as a stored property this is rebuilt whenever `ContentView` re-renders
    /// the cover, and `onReceive` resubscribes to the new publisher and restarts its interval, so
    /// the clock can sit at 0s all round. As state it is created once. Same fix as `MatchingGameView`.
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Two across for a two- or four-case board, three across for a three-case one — never an
    /// orphan button on its own row.
    private var buttonColumns: [GridItem] {
        let across = answerCases.count == 3 ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: across)
    }

    /// The cases this round offers. Older sessions (and previews) default to all four.
    private var answerCases: [PrepositionCase] {
        session.answerCases.isEmpty ? PrepositionCase.allCases : session.answerCases
    }

    var body: some View {
        ZStack {
            // Already the systemGroupedBackground Klar uses, so ThemedBackground is a no-op there
            // and paints each identity theme's ground elsewhere.
            ThemedBackground().ignoresSafeArea()

            if session.questions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    topBar
                    progressHeader
                    Spacer(minLength: 0)
                    if index < questions.count {
                        questionCard(questions[index])
                    }
                    Spacer(minLength: 0)
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
            PrepositionRulesSheet()
        }
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
                        .fill(.tint)
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
    private func questionCard(_ question: PrepositionQuestion) -> some View {
        VStack(spacing: 12) {
            scene(for: question)

            Text(question.word)
                // Klar/Sanft keep the rounded display; Kritzel/Grundform take their own face.
                .themedLabel(.system(size: 44, weight: .bold, design: .rounded), size: 44)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(isAnswering ? Color.primary : question.governs.color)
                .contentTransition(.opacity)
                .modifier(ShakeEffect(shakes: CGFloat(wrongShakes)))
                .animation(.linear(duration: 0.4), value: wrongShakes)

            Text(question.meaning)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !isAnswering {
                reveal(question)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 24)
    }

    /// The 3D relation, when this preposition has a scene and pictures are switched on.
    ///
    /// While answering it stays **neutral** — the relation without the case coding. That's what
    /// makes it safe to show up front at any level: what gives the answer away is the case
    /// color and the moving/resting contrast, not the geometry. Teaching mode overrides that on
    /// purpose, and stamps those answers `scaffolded` so they can't count as mastery.
    @ViewBuilder
    private func scene(for question: PrepositionQuestion) -> some View {
        if pictureMode.showsSceneOnQuestion, PrepositionScene.exists(for: question.word) {
            let resolved = !isAnswering || pictureMode.revealsCaseOnQuestion
            PrepositionSceneView(
                word: question.word,
                mode: resolved ? .resolved(question.governs) : .neutral,
                loops: question.governs == .wechsel
            )
            .frame(height: 168)
            .padding(.bottom, 2)
        }
    }

    /// What the answer actually teaches: the case, the article forms it produces, a worked
    /// example (both, for a two-way preposition), and the honest caveat when there is one.
    @ViewBuilder
    private func reveal(_ question: PrepositionQuestion) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label(question.governs.germanLabel.uppercased(), systemImage: question.governs.symbol)
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(question.governs.color, in: appTheme.pillShape)
                Text(question.governs.articleLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PrepositionExampleRows(examples: question.examples, governs: question.governs)

            if let note = question.note {
                Label(note, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Answers

    private var answerArea: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: buttonColumns, spacing: 10) {
                ForEach(answerCases) { group in
                    caseButton(group)
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

    private var isAnswering: Bool {
        if case .answering = phase { return true }
        return false
    }

    private func caseButton(_ group: PrepositionCase) -> some View {
        let visual = buttonVisual(group)
        return Button {
            handleTap(group)
        } label: {
            VStack(spacing: 2) {
                Label(group.germanLabel, systemImage: group.symbol)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(group.englishLabel)
                    .font(.caption2)
                    .opacity(0.75)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: appTheme.innerRadius(16), style: .continuous)
                    .fill(visual.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: appTheme.innerRadius(16), style: .continuous)
                    .strokeBorder(visual.stroke, lineWidth: visual.strokeWidth)
            )
            .foregroundStyle(visual.foreground)
            .opacity(visual.dimmed ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!isAnswering)
    }

    private struct ButtonVisual {
        var fill: Color
        var stroke: Color
        var strokeWidth: CGFloat
        var foreground: Color
        var dimmed: Bool
    }

    private func buttonVisual(_ group: PrepositionCase) -> ButtonVisual {
        let correct = questions.indices.contains(index) ? questions[index].governs : nil

        switch phase {
        case .answering:
            return ButtonVisual(
                fill: group.color.opacity(0.12),
                stroke: group.color.opacity(0.5),
                strokeWidth: 1.5,
                foreground: Color.primary,
                dimmed: false
            )
        case .correct:
            let isTheAnswer = group == correct
            return ButtonVisual(
                fill: isTheAnswer ? group.color : group.color.opacity(0.12),
                stroke: isTheAnswer ? group.color : group.color.opacity(0.3),
                strokeWidth: 1.5,
                foreground: isTheAnswer ? .white : .primary,
                dimmed: !isTheAnswer
            )
        case .revealed(let wrongPick):
            let isTheAnswer = group == correct
            return ButtonVisual(
                fill: isTheAnswer ? group.color : group.color.opacity(0.12),
                stroke: isTheAnswer ? group.color : group.color.opacity(0.3),
                strokeWidth: 1.5,
                foreground: isTheAnswer ? .white : .primary,
                dimmed: !isTheAnswer && group != wrongPick
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
        // The clock runs from the moment the round appears: reading the first preposition is
        // part of the round, and a timer that sits at 0s until the first tap reads as broken.
        sessionStart = Date()
        finishedAt = nil
        displaySeconds = 0
        showSummary = false
    }

    private func handleTap(_ picked: PrepositionCase) {
        guard isAnswering, questions.indices.contains(index) else { return }
        let question = questions[index]

        if picked == question.governs {
            correctCount += 1
            combo += 1
            bestCombo = max(bestCombo, combo)
            outcomes.append(PrepositionAnswerOutcome(
                word: question.word, governs: question.governs, meaning: question.meaning,
                firstTry: true, wrongPick: nil,
                scaffolded: pictureMode.revealsCaseOnQuestion
            ))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                phase = .correct
            }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                // Only advance if this question is still showing (guards a fast restart).
                if case .correct = phase { advance() }
            }
        } else {
            wrongCount += 1
            wrongShakes += 1
            combo = 0
            outcomes.append(PrepositionAnswerOutcome(
                word: question.word, governs: question.governs, meaning: question.meaning,
                firstTry: false, wrongPick: picked,
                scaffolded: pictureMode.revealsCaseOnQuestion
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
        feedback = onComplete(PrepositionRoundResult(outcomes: outcomes, durationSeconds: duration))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showSummary = true }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Not enough prepositions",
                systemImage: "questionmark.square.dashed",
                description: Text("Pick another group — this one has too few prepositions for a round.")
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
                        Label("New personal best for this group!", systemImage: "trophy.fill")
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

                    perCaseBreakdown

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

    /// This round's hit rate per case — makes "the Genitiv ones are your weak spot" visible.
    private var perCaseBreakdown: some View {
        VStack(spacing: 8) {
            ForEach(PrepositionCase.allCases) { group in
                let seen = outcomes.filter { $0.governs == group }
                if !seen.isEmpty {
                    let hits = seen.filter(\.firstTry).count
                    HStack(spacing: 10) {
                        Text(group.shortLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(group.color)
                            .frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(group.color.opacity(0.15))
                                Capsule()
                                    .fill(group.color)
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

    /// The prepositions missed this round, with lifetime context.
    private var missRecap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Worth another look")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(feedback.misses.prefix(4)) { miss in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(miss.word)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(miss.governs.color)
                        Text("→ \(miss.governs.germanLabel)")
                            .font(.callout)
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
                    if let repeated = miss.repeatedWrongCase {
                        Text("You keep putting it in the \(repeated.germanLabel).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(miss.meaning)
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
/// (File-private twin of the article game's; the two drills stay independently tweakable.)
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

#Preview("Kasus drill · 4 themes") {
    let session = PrepositionCaseSession(
        questions: [
            PrepositionService.preposition("durch"),
            PrepositionService.preposition("mit"),
            PrepositionService.preposition("in"),
            PrepositionService.preposition("trotz"),
        ].compactMap { $0 }.map(PrepositionQuestion.init),
        topic: "Preview"
    )
    return TabView {
        ForEach(AppTheme.allCases) { theme in
            PrepositionCaseGameView(session: session, onComplete: { _ in .empty }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}
