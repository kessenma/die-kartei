import SwiftUI
import SwiftData

/// The graded quiz over a story's comprehension questions. Handles all four kinds: option
/// buttons (multiple choice / blank with choices), a typed blank checked locally, and a
/// written free response the model grades. Mirrors `GrammarMultipleChoiceView`'s
/// answer → grade → missed-review → summary flow.
struct StoryQuizView: View {
    let story: StudyStory
    let service: StoryStudyService
    @Bindable var modelManager: MLXModelManager
    var isListening: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    private struct MissedQuestion: Identifiable {
        let question: StoryQuestion
        let learnerAnswer: String
        var id: String { question.id }
    }

    @State private var questions: [StoryQuestion] = []
    @State private var currentIndex = 0
    @State private var answered = false
    @State private var wasCorrect = false
    @State private var selectedIndex: Int?
    @State private var typedAnswer = ""
    @State private var freeAnswer = ""
    @State private var freeGrade: StoryStudyService.FreeResponseGrade?
    @State private var isGrading = false
    @State private var gradingFailed = false
    @State private var correctCount = 0
    @State private var missed: [MissedQuestion] = []
    @State private var sessionComplete = false
    @State private var showReference = false
    @State private var isReplaying = false
    /// When the run started, for the attempt's duration.
    @State private var startedAt = Date()
    /// Free-response questions actually answered this run.
    @State private var writtenCount = 0
    /// "You wrote → better" pairs from graded written answers, handed to the coach at the end
    /// (batched rather than per-answer so a run the learner abandons leaves no trace).
    @State private var writtenCorrections: [(original: String, corrected: String)] = []

    /// The colors follow the tutor doing the grading, which is the one the story was written with
    /// wherever it's still usable (`StoryDetailView` builds the service).
    private var theme: ModelTheme { service.model.theme }

    private var current: StoryQuestion? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }

    private var progress: Double {
        questions.isEmpty ? 0 : Double(currentIndex) / Double(questions.count)
    }

    var body: some View {
        Group {
            if sessionComplete {
                summaryView
            } else if let question = current {
                questionView(question)
            } else {
                ContentUnavailableView("No questions", systemImage: "questionmark.circle")
            }
        }
        .background {
            if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
        }
        .navigationTitle(isListening ? "Hören · Fragen" : "Fragen")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showReference = true
                } label: {
                    Image(systemName: isListening ? "speaker.wave.2" : "book")
                }
                .accessibilityLabel(isListening ? "Replay the story" : "Show the story")
            }
        }
        .sheet(isPresented: $showReference) { referenceSheet }
        .onAppear {
            if questions.isEmpty {
                questions = story.questions.shuffled()
                startedAt = Date()
            }
        }
        .onDisappear {
            SpeechService.shared.stop()
        }
    }

    // MARK: - Question flow

    private func questionView(_ question: StoryQuestion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                progressHeader
                questionCard(question)
                answerSurface(question)
                if answered {
                    evidenceCard(question)
                    nextButton
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var progressHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Text(story.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(currentIndex + 1) / \(questions.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
        }
    }

    private func questionCard(_ question: StoryQuestion) -> some View {
        VStack(spacing: 10) {
            Text(question.kind.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if answered {
                Image(systemName: resultIcon)
                    .font(.title)
                    .foregroundStyle(resultColor)
            }

            Text(displayedQuestionText(question))
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16)))
    }

    /// After answering, blank kinds show the filled sentence.
    private func displayedQuestionText(_ question: StoryQuestion) -> String {
        guard answered,
              question.kind == .fillInBlank || question.kind == .fillInBlankChoices,
              let answer = question.answer
        else { return question.question }
        return question.question.replacingOccurrences(of: "______", with: answer)
    }

    private var resultIcon: String {
        if wasCorrect {
            return freeGrade?.score == 1 ? "checkmark.circle" : "checkmark.circle.fill"
        }
        return "xmark.circle.fill"
    }

    private var resultColor: Color {
        if wasCorrect {
            return freeGrade?.score == 1 ? .orange : .green
        }
        return .red
    }

    @ViewBuilder
    private func answerSurface(_ question: StoryQuestion) -> some View {
        switch question.kind {
        case .multipleChoice, .fillInBlankChoices:
            optionButtons(question)
        case .fillInBlank:
            typedBlankField(question)
        case .freeResponse:
            freeResponseField(question)
        }
    }

    // MARK: Choice kinds

    private func optionButtons(_ question: StoryQuestion) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                Button {
                    guard !answered else { return }
                    selectedIndex = index
                    finishAnswer(
                        correct: index == question.correctIndex,
                        question: question,
                        learnerAnswer: option
                    )
                } label: {
                    Text(option)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(optionBackground(index, question: question))
                        .foregroundStyle(optionForeground(index, question: question))
                        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
                        .overlay(
                            RoundedRectangle(cornerRadius: appTheme.innerRadius(12))
                                .stroke(optionBorder(index, question: question), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .disabled(answered)
            }
        }
    }

    private func optionBackground(_ index: Int, question: StoryQuestion) -> Color {
        guard answered else { return Color(uiColor: .secondarySystemBackground) }
        if index == question.correctIndex { return .green.opacity(0.15) }
        if index == selectedIndex { return .red.opacity(0.15) }
        return Color(uiColor: .secondarySystemBackground).opacity(0.5)
    }

    private func optionForeground(_ index: Int, question: StoryQuestion) -> Color {
        guard answered else { return .primary }
        if index == question.correctIndex { return .green }
        if index == selectedIndex { return .red }
        return .secondary
    }

    private func optionBorder(_ index: Int, question: StoryQuestion) -> Color {
        guard answered else { return Color(uiColor: .separator) }
        if index == question.correctIndex { return .green.opacity(0.6) }
        if index == selectedIndex { return .red.opacity(0.6) }
        return Color(uiColor: .separator).opacity(0.3)
    }

    // MARK: Typed blank

    private func typedBlankField(_ question: StoryQuestion) -> some View {
        VStack(spacing: 12) {
            TextField("Das fehlende Wort…", text: $typedAnswer)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(answered)
                .onSubmit { checkTyped(question) }

            if !answered {
                Button {
                    checkTyped(question)
                } label: {
                    Text("Check")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
            } else if !wasCorrect, let answer = question.answer {
                Text("\(Text("Richtig: ").foregroundStyle(.secondary))\(Text(answer).bold())")
                    .font(.subheadline)
            }
        }
    }

    private func checkTyped(_ question: StoryQuestion) {
        guard !answered, let answer = question.answer else { return }
        let trimmed = typedAnswer.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        finishAnswer(
            correct: Self.matchesTyped(trimmed, answer: answer),
            question: question,
            learnerAnswer: trimmed
        )
    }

    /// Lenient blank matching: case-insensitive, punctuation-trimmed, article-tolerant
    /// ("der Hund" matches "Hund").
    static func matchesTyped(_ input: String, answer: String) -> Bool {
        func normalize(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for article in ["der ", "die ", "das "] where t.hasPrefix(article) {
                t = String(t.dropFirst(article.count))
            }
            return t.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"„“'’ "))
        }
        return normalize(input) == normalize(answer) && !normalize(input).isEmpty
    }

    // MARK: Free response

    private func freeResponseField(_ question: StoryQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $freeAnswer)
                .frame(minHeight: 90)
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
                .disabled(answered || isGrading)

            if !answered {
                Button {
                    grade(question)
                } label: {
                    Group {
                        if isGrading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Wird bewertet…")
                            }
                        } else {
                            Text("Bewerten")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(freeAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGrading)

                if gradingFailed {
                    Label("Grading didn’t work — try again in a moment.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let grade = freeGrade, !grade.feedback.isEmpty {
                        Text(grade.feedback)
                            .font(.subheadline)
                    }
                    if let correction = freeGrade?.correction {
                        Text("\(Text("Besser: ").foregroundStyle(.secondary))\(correction)")
                            .font(.subheadline)
                    }
                    if let muster = question.answer {
                        Text("\(Text("Musterantwort: ").foregroundStyle(.secondary))\(muster)")
                            .font(.subheadline)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
            }
        }
    }

    private func grade(_ question: StoryQuestion) {
        isGrading = true
        gradingFailed = false
        let answerText = freeAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let result = await service.gradeFreeResponse(question: question, learnerAnswer: answerText, story: story)
            isGrading = false
            if let result {
                freeGrade = result
                writtenCount += 1
                // A "Besser:" rewrite is the same evidence a conversation correction is — keep it
                // for the coach, including on a score of 1 (right idea, shaky German).
                if let correction = result.correction, result.score < 2 {
                    writtenCorrections.append((original: answerText, corrected: correction))
                }
                // "Right idea, shaky language" (1) counts as correct — content-first grading.
                finishAnswer(correct: result.score >= 1, question: question, learnerAnswer: answerText)
            } else {
                gradingFailed = true
            }
        }
    }

    // MARK: Shared answer handling

    private func finishAnswer(correct: Bool, question: StoryQuestion, learnerAnswer: String) {
        answered = true
        wasCorrect = correct
        if correct {
            correctCount += 1
        } else {
            missed.append(MissedQuestion(question: question, learnerAnswer: learnerAnswer))
            // A missed blank word is vocabulary being built — fold it into the coach's profile.
            if modelManager.storyFeedsCoach,
               question.kind == .fillInBlank || question.kind == .fillInBlankChoices,
               let word = question.answer {
                LearnerMemoryService.noteVocabEncounters([(german: word, english: "")], in: modelContext)
            }
        }
    }

    @ViewBuilder
    private func evidenceCard(_ question: StoryQuestion) -> some View {
        if let evidence = question.evidence {
            Text("\(Text("Im Text: ").foregroundStyle(.secondary))\(Text("„\(evidence)“").italic())")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
        }
    }

    private var nextButton: some View {
        Button(action: advance) {
            Text(currentIndex + 1 < questions.count ? "Weiter" : "See Results")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
        }
        .buttonStyle(.plain)
    }

    private func advance() {
        if currentIndex + 1 >= questions.count {
            finishSession()
        } else {
            currentIndex += 1
            resetQuestionState()
        }
    }

    private func resetQuestionState() {
        answered = false
        wasCorrect = false
        selectedIndex = nil
        typedAnswer = ""
        freeAnswer = ""
        freeGrade = nil
        isGrading = false
        gradingFailed = false
    }

    private func finishSession() {
        sessionComplete = true
        let pct = questions.isEmpty ? 0 : Int((Double(correctCount) / Double(questions.count) * 100).rounded())
        story.bestScore = max(story.bestScore ?? 0, pct)
        story.lastStudiedAsListening = isListening
        // Story questions are their own activity, not flashcard reviews: they keep the streak
        // alive, show in the calendar's day detail, and feed the reading-progress screen.
        StoryProgressService.recordQuiz(
            story: story,
            questionCount: questions.count,
            correctCount: correctCount,
            durationSeconds: max(0, Int(Date().timeIntervalSince(startedAt))),
            wasListening: isListening,
            writtenCount: writtenCount,
            in: modelContext
        )
        if modelManager.storyFeedsCoach {
            LearnerMemoryService.noteWrittenCorrections(writtenCorrections, in: modelContext)
        }
        try? modelContext.save()
    }

    // MARK: - Reference sheet ("Zum Text" / replay)

    private var referenceSheet: some View {
        NavigationStack {
            Group {
                if isListening && story.bestScore == nil {
                    // Hören: replay without revealing the text until a quiz is finished.
                    VStack(spacing: 20) {
                        Image(systemName: "ear")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Nochmal hören")
                            .font(.headline)
                        Button {
                            if isReplaying {
                                SpeechService.shared.stop()
                            } else {
                                isReplaying = true
                                SpeechService.shared.speak(story.storyText, onFinish: { isReplaying = false })
                            }
                        } label: {
                            Image(systemName: isReplaying ? "stop.fill" : "play.fill")
                                .font(.title)
                                .frame(width: 64, height: 64)
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(Circle())
                        Text("The text unlocks after you finish the questions once.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(story.storyText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .navigationTitle(isListening && story.bestScore == nil ? "Nochmal hören" : "Zum Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showReference = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Summary

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 28) {
                scoreHeader
                if !missed.isEmpty {
                    missedList
                }
                actionButtons
            }
            .padding(24)
        }
    }

    private var scoreHeader: some View {
        VStack(spacing: 12) {
            let pct = questions.isEmpty ? 0 : Int(Double(correctCount) / Double(questions.count) * 100)
            Image(systemName: pct >= 80 ? "star.fill" : pct >= 50 ? "hand.thumbsup.fill" : "arrow.counterclockwise")
                .font(.system(size: 48))
                .foregroundStyle(pct >= 80 ? .yellow : pct >= 50 ? theme.accent : .orange)

            Text("\(correctCount) / \(questions.count)")
                .font(.largeTitle.bold())

            Text(scoreMessage(pct))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if isListening {
                Label("Hörverstehen", systemImage: "ear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 16)
    }

    private func scoreMessage(_ pct: Int) -> String {
        switch pct {
        case 100: return "Perfekt! Ausgezeichnet!"
        case 80...: return "Sehr gut gemacht!"
        case 60...: return "Gut! Weiter so!"
        default: return "Lies noch einmal — Übung hilft!"
        }
    }

    private var missedList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review these")
                .font(.headline)
                .foregroundStyle(.red)

            ForEach(missed) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(missedQuestionText(item.question))
                        .font(.subheadline)
                    if let answer = item.question.answer {
                        Text(answer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !item.learnerAnswer.isEmpty {
                        Text("Deine Antwort: \(item.learnerAnswer)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10)))
            }
        }
    }

    private func missedQuestionText(_ question: StoryQuestion) -> String {
        if question.kind == .fillInBlank || question.kind == .fillInBlankChoices,
           let answer = question.answer {
            return question.question.replacingOccurrences(of: "______", with: answer)
        }
        return question.question
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
                    .foregroundStyle(.white)
                    .background(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
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
        questions = story.questions.shuffled()
        currentIndex = 0
        correctCount = 0
        missed = []
        sessionComplete = false
        resetQuestionState()
    }
}

#Preview("Story quiz · 4 themes") {
    let container = try! ModelContainer(
        for: StudyStory.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let story = StudyStory(topic: "Ein Tag im Park", level: .a2, genre: .alltag)
    story.title = "Ein Tag im Park"
    story.storyText = "Anna geht in den Park. Dort sieht sie einen kleinen Hund."
    story.setQuestions([
        StoryQuestion(
            kind: .multipleChoice,
            question: "Wohin geht Anna?",
            options: ["In den Park", "Nach Hause", "Zur Schule"],
            correctIndex: 0,
            answer: "In den Park",
            evidence: "Anna geht in den Park."
        ),
        StoryQuestion(
            kind: .fillInBlankChoices,
            question: "Dort sieht sie einen kleinen ______.",
            options: ["Hund", "Katze", "Vogel"],
            correctIndex: 0,
            answer: "Hund",
            evidence: "Dort sieht sie einen kleinen Hund."
        )
    ])
    let service = StoryStudyService(
        mlxService: MLXGenerationService(),
        modelContext: ModelContext(container)
    )
    return ForEach(AppTheme.allCases) { theme in
        NavigationStack {
            StoryQuizView(story: story, service: service, modelManager: MLXModelManager())
        }
        .environment(\.appTheme, theme)
    }
}
