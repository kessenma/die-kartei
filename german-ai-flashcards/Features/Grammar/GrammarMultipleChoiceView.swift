import SwiftUI

struct GrammarMultipleChoiceView: View {
    let category: GrammarCategory
    var showHints: Bool = false
    /// Gates the right/wrong vibrations (Settings ▸ Cards ▸ Haptics).
    var hapticMode: HapticFeedbackMode = .all
    /// Called once when the round ends — (correct, total, seconds spent on the round).
    var onComplete: ((_ correct: Int, _ total: Int, _ durationSeconds: Int) -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(\.appTheme) private var appTheme

    @State private var exercises: [GrammarExercise] = []
    @State private var currentIndex = 0
    @State private var selectedAnswer: String? = nil
    @State private var correctCount = 0
    @State private var wrongCount = 0
    @State private var missedExercises: [GrammarExercise] = []
    @State private var sessionComplete = false
    /// Per-question, and reset on advance: the translation is a hint you ask for each time, not a
    /// mode you switch on once and then read the whole round in English.
    @State private var showTranslation = false
    /// When this round's first question went on screen — the round's time on task.
    @State private var startedAt = Date()

    private var current: GrammarExercise? {
        guard currentIndex < exercises.count else { return nil }
        return exercises[currentIndex]
    }

    private var progress: Double {
        exercises.isEmpty ? 0 : Double(currentIndex) / Double(exercises.count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessionComplete {
                    summaryView
                } else if let exercise = current {
                    exerciseView(exercise)
                }
            }
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss?() }
                }
            }
        }
        .onAppear {
            exercises = category.exercises.shuffled()
            startedAt = Date()
        }
        .sensoryFeedback(.success, trigger: correctCount) { old, new in
            new > old && hapticMode.playsSuccess
        }
        .sensoryFeedback(.error, trigger: wrongCount) { old, new in
            new > old && hapticMode.playsError
        }
    }

    @ViewBuilder
    private func exerciseView(_ exercise: GrammarExercise) -> some View {
        VStack(spacing: 0) {
            progressHeader
                .padding(.horizontal)
                .padding(.top, 16)

            Spacer()

            sentenceCard(exercise)
                .padding(.horizontal, 24)

            Spacer()

            optionButtons(exercise)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)

            if selectedAnswer != nil {
                nextButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Text(category.ruleNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text("\(currentIndex + 1) / \(exercises.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(.blue)
        }
    }

    private func sentenceCard(_ exercise: GrammarExercise) -> some View {
        VStack(spacing: 12) {
            if let selected = selectedAnswer {
                let isCorrect = selected == exercise.correctAnswer
                let filled = exercise.sentence.replacingOccurrences(of: "______", with: exercise.correctAnswer)
                VStack(spacing: 8) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(isCorrect ? .green : .red)
                    Text(filled)
                        .font(.title3)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                    if !exercise.noun.isEmpty {
                        Text("\(exercise.noun) · \(exercise.gender)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Only on a miss: after a correct pick this is the learner telling you the
                    // rule, and repeating it back is noise.
                    if !isCorrect {
                        whyLine(exercise)
                            .padding(.top, 4)
                    }
                    translationControl(exercise)
                        .padding(.top, 2)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16)))
            } else {
                VStack(spacing: 10) {
                    if showHints {
                        hintSentenceText(exercise)
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(exercise.sentence)
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                    }

                    if showHints && !exercise.gender.isEmpty && !exercise.noun.isEmpty {
                        genderBadge(exercise.gender)
                    }

                    translationControl(exercise)
                        .padding(.top, 2)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16)))
            }
        }
    }

    /// Tap to read the sentence in English. Hidden by default, and hidden entirely for an
    /// exercise with no translation (AI-generated rounds, where the model may not supply one) —
    /// a button that reveals nothing is worse than no button.
    @ViewBuilder
    private func translationControl(_ exercise: GrammarExercise) -> some View {
        let english = exercise.english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !english.isEmpty {
            VStack(spacing: 8) {
                if showTranslation {
                    Text(english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showTranslation.toggle() }
                } label: {
                    Label(
                        showTranslation ? "Hide translation" : "Translation",
                        systemImage: "character.book.closed"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "The answer is den because Apfel is masculine and the direct object of isst, so der
    /// becomes den." One `Text`, so it wraps as a sentence rather than as stacked fragments.
    private func whyLine(_ exercise: GrammarExercise) -> some View {
        let clause = GrammarExplanation.because(exercise, in: category)
        return (
            Text("The answer is ")
            + Text(exercise.correctAnswer).fontWeight(.semibold)
            + Text(" because \(clause)")
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private func hintSentenceText(_ exercise: GrammarExercise) -> Text {
        let tokens = exercise.sentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let verbFormLower = exercise.verbForm?.lowercased()
        let nounLower = exercise.noun.lowercased()

        var attributed = AttributedString()
        for (index, token) in tokens.enumerated() {
            let stripped = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
            let isBlank = token.contains("______")
            let isVerb = verbFormLower.map { stripped == $0 } ?? false
            let isNoun = !nounLower.isEmpty && stripped == nounLower

            var chunk = AttributedString(index < tokens.count - 1 ? token + " " : token)
            if isBlank {
                chunk.font = .system(.body, design: .default).weight(.bold)
            } else if isVerb {
                chunk.foregroundColor = .green
            } else if isNoun {
                chunk.foregroundColor = .orange
            }
            attributed.append(chunk)
        }
        return Text(attributed)
    }

    @ViewBuilder
    private func genderBadge(_ gender: String) -> some View {
        Text(gender)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.orange, in: appTheme.pillShape)
    }

    private func optionButtons(_ exercise: GrammarExercise) -> some View {
        let options = exercise.options ?? category.options
        return VStack(spacing: 12) {
            ForEach(options, id: \.self) { option in
                Button {
                    guard selectedAnswer == nil else { return }
                    selectedAnswer = option
                    if option == exercise.correctAnswer {
                        correctCount += 1
                    } else {
                        wrongCount += 1
                        missedExercises.append(exercise)
                    }
                } label: {
                    Text(option)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(buttonBackground(option: option, exercise: exercise))
                        .foregroundStyle(buttonForeground(option: option, exercise: exercise))
                        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
                        .overlay(
                            RoundedRectangle(cornerRadius: appTheme.innerRadius(12))
                                .stroke(buttonBorder(option: option, exercise: exercise), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selectedAnswer != nil)
            }
        }
    }

    private func buttonBackground(option: String, exercise: GrammarExercise) -> Color {
        guard let selected = selectedAnswer else { return Color(uiColor: .secondarySystemBackground) }
        if option == exercise.correctAnswer { return .green.opacity(0.15) }
        if option == selected { return .red.opacity(0.15) }
        return Color(uiColor: .secondarySystemBackground).opacity(0.5)
    }

    private func buttonForeground(option: String, exercise: GrammarExercise) -> Color {
        guard let selected = selectedAnswer else { return .primary }
        if option == exercise.correctAnswer { return .green }
        if option == selected { return .red }
        return .secondary
    }

    private func buttonBorder(option: String, exercise: GrammarExercise) -> Color {
        guard let selected = selectedAnswer else { return Color(uiColor: .separator) }
        if option == exercise.correctAnswer { return .green.opacity(0.6) }
        if option == selected { return .red.opacity(0.6) }
        return Color(uiColor: .separator).opacity(0.3)
    }

    private var nextButton: some View {
        Button {
            advance()
        } label: {
            Text(currentIndex + 1 < exercises.count ? "Next" : "See Results")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
        }
        .buttonStyle(.plain)
    }

    private func advance() {
        if currentIndex + 1 >= exercises.count {
            sessionComplete = true
            onComplete?(correctCount, exercises.count, max(0, Int(Date().timeIntervalSince(startedAt))))
        } else {
            currentIndex += 1
            selectedAnswer = nil
            showTranslation = false
        }
    }

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 28) {
                scoreHeader

                if !missedExercises.isEmpty {
                    missedList
                }

                actionButtons
            }
            .padding(24)
        }
    }

    private var scoreHeader: some View {
        VStack(spacing: 12) {
            let pct = exercises.isEmpty ? 0 : Int(Double(correctCount) / Double(exercises.count) * 100)
            Image(systemName: pct >= 80 ? "star.fill" : pct >= 50 ? "hand.thumbsup.fill" : "arrow.counterclockwise")
                .font(.system(size: 48))
                .foregroundStyle(pct >= 80 ? .yellow : pct >= 50 ? .blue : .orange)

            Text("\(correctCount) / \(exercises.count)")
                .font(.largeTitle.bold())

            Text(scoreMessage(pct))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    private func scoreMessage(_ pct: Int) -> String {
        switch pct {
        case 100: return "Perfekt! Ausgezeichnet!"
        case 80...: return "Sehr gut gemacht!"
        case 60...: return "Gut! Weiter so!"
        default: return "Weiter üben hilft!"
        }
    }

    private var missedList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review these")
                .font(.headline)
                .foregroundStyle(.red)

            ForEach(missedExercises) { exercise in
                let filled = exercise.sentence.replacingOccurrences(of: "______", with: exercise.correctAnswer)
                VStack(alignment: .leading, spacing: 3) {
                    Text(filled)
                        .font(.subheadline)
                    if !exercise.noun.isEmpty {
                        Text("\(exercise.correctAnswer) · \(exercise.noun) (\(exercise.gender))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(exercise.correctAnswer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // The reason travels with the sentence: a review list of answers you already
                    // got wrong teaches nothing without the rule behind them.
                    Text(GrammarExplanation.because(exercise, in: category))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10)))
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                reset()
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
            }
            .buttonStyle(.plain)

            Button {
                onDismiss?()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
            }
            .buttonStyle(.plain)
        }
    }

    private func reset() {
        exercises = category.exercises.shuffled()
        currentIndex = 0
        selectedAnswer = nil
        showTranslation = false
        correctCount = 0
        missedExercises = []
        sessionComplete = false
        startedAt = Date()
    }
}
