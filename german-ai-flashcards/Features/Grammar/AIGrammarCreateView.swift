//
//  AIGrammarCreateView.swift
//  german-ai-flashcards
//
//  Build-your-own grammar drill: pick a structure, pick (or type, or dice-roll) a topic,
//  and the on-device model writes fresh fill-in-the-blank exercises that run in the same
//  multiple-choice player as the bundled ones. Ties into the learner profile twice: weak
//  structures are flagged (and preselected), and the prompt can weave in words the
//  learner is currently building.
//

import SwiftUI
import SwiftData

struct AIGrammarCreateView: View {
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService
    /// Launches the finished category in the multiple-choice player (the hub's launcher).
    let onStart: (_ category: GrammarCategory, _ showHints: Bool) -> Void

    private let preselectedFocus: GrammarFocus?

    init(
        modelManager: MLXModelManager,
        mlxService: MLXGenerationService,
        preselectedFocus: GrammarFocus? = nil,
        onStart: @escaping (_ category: GrammarCategory, _ showHints: Bool) -> Void
    ) {
        self.modelManager = modelManager
        self.mlxService = mlxService
        self.preselectedFocus = preselectedFocus
        self.onStart = onStart
        _focus = State(initialValue: preselectedFocus ?? .akkusativ)
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [LearnerProfile]

    @FocusState private var isTopicFieldFocused: Bool
    @State private var focus: GrammarFocus
    @State private var didApplyCoachDefault = false
    @State private var topicText = ""
    @State private var exerciseCount = 8
    @State private var showHints = true
    @State private var useLearnerWords = true
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showingLesson = false

    private let exerciseCountOptions = [5, 8, 10, 15]
    private let topics = GrammarTopicService.topics()

    var body: some View {
        Form {
            modelSection
            structureSection
            topicSection
            optionsSection
            generateSection

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("AI Exercises")
        .navigationBarTitleDisplayMode(.large)
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 120)
        .sheet(isPresented: $showingLesson) {
            GrammarLessonSheet(focus: focus)
        }
        .onAppear(perform: applyCoachDefaultFocus)
    }

    // MARK: - Learner profile inputs

    private var profile: LearnerProfile? { profiles.first }

    /// Shaky structures, worst-first (same threshold the coach and Today plan use).
    private var weakFocuses: [GrammarFocus] {
        guard let profile else { return [] }
        return profile.grammar
            .compactMap { key, skill -> (GrammarFocus, Double)? in
                guard skill.struggle >= GrammarSkill.shakyThreshold,
                      let f = GrammarFocus(rawValue: key) else { return nil }
                return (f, skill.struggle)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Recent words the learner is building — offered to the prompt so exercises reuse them.
    private var learnerWords: [String] {
        (profile?.vocab ?? [])
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(6)
            .map(\.german)
    }

    /// With no explicit preselection, start on the coach's weakest structure (once).
    private func applyCoachDefaultFocus() {
        guard !didApplyCoachDefault else { return }
        didApplyCoachDefault = true
        if preselectedFocus == nil, let weakest = weakFocuses.first {
            focus = weakest
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        ModelPickerButton(
            selection: Binding(
                get: { modelManager.selectedMLXModel },
                set: { modelManager.selectedMLXModel = $0 }
            ),
            modelManager: modelManager,
            mlxService: mlxService
        )
    }

    private var modelIsReady: Bool { mlxService.isModelLoaded }

    // MARK: - Structure

    private var structureSection: some View {
        Section {
            Picker("Structure", selection: $focus) {
                ForEach(GrammarFocus.allCases) { f in
                    if weakFocuses.contains(f) {
                        Label(f.germanLabel, systemImage: "flame").tag(f)
                    } else {
                        Text(f.germanLabel).tag(f)
                    }
                }
            }
        } header: {
            HStack {
                Text("What to practice")
                Spacer()
                Button {
                    showingLesson = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } footer: {
            if weakFocuses.contains(focus) {
                Text("\(focus.englishLabel) · the coach says this needs work — good pick.")
            } else {
                Text(focus.englishLabel)
            }
        }
    }

    // MARK: - Topic

    private var trimmedTopic: String {
        topicText.trimmingCharacters(in: .whitespaces)
    }

    private var topicSection: some View {
        Section {
            TextField("e.g. Einkaufen, ordering food, my job…", text: $topicText)
                .focused($isTopicFieldFocused)
                .onSubmit { isTopicFieldFocused = false }
            if !topics.isEmpty {
                topicBrowser
            }
        } header: {
            Text("Topic")
        } footer: {
            Text("Type your own, scroll the ideas, or let the dice pick one.")
        }
    }

    private var topicBrowser: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    rollRandomTopic(proxy: proxy)
                } label: {
                    Label("Pick a topic for me", systemImage: "dice")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: [GridItem(.fixed(44)), GridItem(.fixed(44))], spacing: 8) {
                        ForEach(topics) { topic in
                            topicChip(topic)
                                .id(topic.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func topicChip(_ topic: GrammarTopic) -> some View {
        let isSelected = topicText == topic.promptLabel
        return Button {
            topicText = topic.promptLabel
            isTopicFieldFocused = false
        } label: {
            VStack(spacing: 1) {
                Text(topic.de)
                    .font(.caption.weight(.medium))
                Text(topic.en)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func rollRandomTopic(proxy: ScrollViewProxy) {
        guard let topic = GrammarTopicService.randomTopic() else { return }
        topicText = topic.promptLabel
        isTopicFieldFocused = false
        withAnimation(.easeInOut) {
            proxy.scrollTo(topic.id, anchor: .center)
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Number of exercises")
                Picker("Number of exercises", selection: $exerciseCount) {
                    ForEach(exerciseCountOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)

            Toggle("Show hints", isOn: $showHints)

            if !learnerWords.isEmpty {
                Toggle("Use words you're learning", isOn: $useLearnerWords)
            }
        } header: {
            Text("Options")
        } footer: {
            if !learnerWords.isEmpty && useLearnerWords {
                Text("Weaves in words from your conversations, like \(learnerWords.prefix(3).joined(separator: ", ")).")
            } else if showHints {
                Text("Hints color the verb and noun and show the gender under the blank.")
            }
        }
    }

    // MARK: - Generate

    private var generateSection: some View {
        Section {
            if isGenerating {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Writing exercises…")
                            .font(.subheadline.weight(.medium))
                        if mlxService.streamingTokenCount > 0 {
                            Text("\(mlxService.streamingTokenCount) tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Stop") {
                        mlxService.isStopRequested = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                .padding(.vertical, 4)
            } else {
                Button(action: generate) {
                    Label("Generate \(exerciseCount) Exercises", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .disabled(generateDisabled)
            }
        } footer: {
            if !modelIsReady {
                Text("Select and load a model above to get started.")
            } else if trimmedTopic.isEmpty {
                Text("Pick or type a topic first.")
            }
        }
    }

    private var generateDisabled: Bool {
        trimmedTopic.isEmpty || !modelIsReady || isGenerating
    }

    private func generate() {
        isTopicFieldFocused = false
        errorMessage = nil
        isGenerating = true
        let model = modelManager.selectedMLXModel
        let words = useLearnerWords ? learnerWords : []
        let topic = trimmedTopic
        let count = exerciseCount

        Task {
            // Auto-load on a model switch (mirrors GenerationCoordinator.generateWithMLX).
            if !mlxService.isModelLoaded || mlxService.currentModel != model {
                await mlxService.loadModel(model)
                guard mlxService.isModelLoaded else {
                    errorMessage = mlxService.loadError ?? "Failed to load model."
                    isGenerating = false
                    return
                }
            }
            do {
                let exercises = try await mlxService.generateGrammarExercises(
                    topic: topic,
                    focus: focus,
                    count: count,
                    learnerWords: words,
                    model: model
                )
                isGenerating = false
                guard !exercises.isEmpty else {
                    errorMessage = "The model couldn't produce usable exercises — try again or pick a different topic."
                    return
                }
                let category = GrammarExerciseService.aiCategory(focus: focus, topic: topic, exercises: exercises)
                onStart(category, showHints)
            } catch {
                isGenerating = false
                errorMessage = "Generation failed: \(error.localizedDescription)"
            }
        }
    }
}
