//
//  ArticleGameSetupView.swift
//  german-ai-flashcards
//
//  The der/die/das launcher: pick where the nouns come from — bundled Goethe lists, a random
//  shuffle of the on-device dictionary, words the coach knows you're learning, your own saved
//  decks, or an AI-generated topic — and start a round through the shared `ActivityRouter`.
//  The progress strip on top reads the persisted `ArticleRound` / `ArticleWordStat` history,
//  and the toolbar's question mark opens the gender-rules cheat sheet.
//

import SwiftUI
import SwiftData

struct ArticleGameSetupView: View {
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]
    @Query(sort: \ArticleRound.date, order: .reverse) private var rounds: [ArticleRound]
    @Query private var wordStats: [ArticleWordStat]
    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @AppStorage("articleGame.questionCount") private var questionCount = 10
    @AppStorage("articleGame.trickyFirst") private var trickyFirst = true

    @FocusState private var isTopicFieldFocused: Bool
    @State private var topicText = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showRules = false

    /// Sources resolved once per appearance (dictionary lookups + deck decodes off the hot path).
    @State private var learnerQuestions: [ArticleQuestion] = []
    @State private var deckPools: [(deckID: PersistentIdentifier, topic: String, questions: [ArticleQuestion])] = []
    @State private var sourcesResolved = false

    private let questionCountOptions = [5, 10, 15, 20]

    private var trickyCount: Int { wordStats.filter(\.isTricky).count }

    /// First-try accuracy across the most recent rounds, as a whole percent.
    private var recentAccuracy: Int? {
        let recent = rounds.prefix(10)
        let questions = recent.reduce(0) { $0 + $1.questionCount }
        guard questions > 0 else { return nil }
        let hits = recent.reduce(0) { $0 + $1.firstTryCount }
        return Int((Double(hits) / Double(questions) * 100).rounded())
    }

    var body: some View {
        List {
            if !rounds.isEmpty {
                progressSection
            }
            optionsSection
            goetheSection
            dictionarySection
            if !learnerQuestions.isEmpty {
                learnerSection
            }
            if !deckPools.isEmpty {
                deckSection
            }
            aiSection

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Der · Die · Das")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRules = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $showRules) {
            ArticleRulesSheet()
        }
        .task {
            guard !sourcesResolved else { return }
            learnerQuestions = ArticleGameService.learnerWordQuestions(in: modelContext)
            deckPools = decks
                .filter { $0.isBrowsableContent && $0.cards.count >= ArticleGameService.minQuestions }
                .compactMap { deck in
                    let questions = ArticleGameService.deckQuestions(from: deck)
                    guard questions.count >= ArticleGameService.minQuestions else { return nil }
                    return (deck.persistentModelID, deck.topic, questions)
                }
            sourcesResolved = true
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        Section {
            HStack(spacing: 0) {
                progressStat("\(rounds.count)", rounds.count == 1 ? "round" : "rounds")
                if let accuracy = recentAccuracy {
                    Divider().padding(.vertical, 6)
                    progressStat("\(accuracy)%", "first-try, last 10")
                }
                Divider().padding(.vertical, 6)
                progressStat("\(trickyCount)", trickyCount == 1 ? "tricky noun" : "tricky nouns")
            }

            if trickyCount >= ArticleGameService.minQuestions {
                Button {
                    let pool = ArticleGameService.trickyQuestions(in: modelContext)
                    launch(topic: "Tricky Nouns", pool: pool, trickyBias: false)
                } label: {
                    Label(
                        "Drill your tricky nouns",
                        systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
                    )
                    .font(.subheadline)
                }
            }
        } header: {
            Text("Your Progress")
        }
    }

    private func progressStat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Round options

    private var optionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nouns per round")
                Picker("Nouns per round", selection: $questionCount) {
                    ForEach(questionCountOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)

            Toggle("Bring back tricky nouns", isOn: $trickyFirst)
        } footer: {
            Text("With tricky nouns on, up to half of each round re-asks words you've missed before.")
        }
    }

    // MARK: - Sources

    private var goetheSection: some View {
        Section {
            ForEach(GoetheLevel.allCases) { level in
                Button {
                    launch(
                        topic: "Goethe \(level.rawValue)",
                        pool: ArticleGameService.goetheQuestions(level: level)
                    )
                } label: {
                    sourceRow("Goethe \(level.rawValue) Nouns", level.examName, "text.book.closed")
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Goethe Vocabulary")
        } footer: {
            Text("Exam-list nouns with their articles — the words certification levels expect you to know.")
        }
    }

    private var dictionarySection: some View {
        Section {
            Button {
                // Oversample so the round stays fresh; tricky bias mixes your misses back in.
                let pool = ArticleGameService.wiktionaryQuestions(count: questionCount * 2)
                    + (trickyFirst ? ArticleGameService.trickyQuestions(in: modelContext) : [])
                launch(topic: "Dictionary Shuffle", pool: pool)
            } label: {
                sourceRow("Dictionary Shuffle", "Random nouns from the on-device dictionary", "shuffle")
            }
            .buttonStyle(.plain)
        } header: {
            Text("Wiktionary")
        } footer: {
            Text("93,000+ nouns offline — expect surprises beyond the textbook.")
        }
    }

    private var learnerSection: some View {
        Section {
            Button {
                launch(topic: "Your Words", pool: learnerQuestions)
            } label: {
                sourceRow(
                    "Words You're Learning",
                    "\(learnerQuestions.count) nouns from your practice",
                    "brain.head.profile"
                )
            }
            .buttonStyle(.plain)
        } header: {
            Text("From Your Coach")
        } footer: {
            Text("Nouns the coach has seen you working on, with articles checked against the dictionary.")
        }
    }

    private var deckSection: some View {
        Section("Your Decks") {
            ForEach(deckPools, id: \.deckID) { pool in
                Button {
                    launch(topic: pool.topic, pool: pool.questions)
                } label: {
                    sourceRow(
                        pool.topic,
                        "\(pool.questions.count) nouns with articles",
                        "rectangle.stack"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - AI topic

    private var trimmedTopic: String {
        topicText.trimmingCharacters(in: .whitespaces)
    }

    private var aiSection: some View {
        Section {
            ModelPickerButton(
                selection: Binding(
                    get: { modelManager.selectedMLXModel },
                    set: { modelManager.selectedMLXModel = $0 }
                ),
                modelManager: modelManager,
                mlxService: mlxService
            )

            TextField("e.g. kitchen, animals, my office…", text: $topicText)
                .focused($isTopicFieldFocused)
                .onSubmit { isTopicFieldFocused = false }

            if isGenerating {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Collecting nouns…")
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
                    Label("Generate a \(questionCount)-Noun Round", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .disabled(trimmedTopic.isEmpty || !mlxService.isModelLoaded)
            }
        } header: {
            Text("Make Your Own Topic")
        } footer: {
            if !mlxService.isModelLoaded {
                Text("Select and load a model above to generate topic nouns.")
            } else {
                Text("The AI picks nouns for your topic; every article is checked against the dictionary before play.")
            }
        }
    }

    private func generate() {
        isTopicFieldFocused = false
        errorMessage = nil
        isGenerating = true
        let model = modelManager.selectedMLXModel
        let topic = trimmedTopic
        let count = questionCount

        Task {
            // Auto-load on a model switch (mirrors AIGrammarCreateView.generate).
            if !mlxService.isModelLoaded || mlxService.currentModel != model {
                await mlxService.loadModel(model)
                guard mlxService.isModelLoaded else {
                    errorMessage = mlxService.loadError ?? "Failed to load model."
                    isGenerating = false
                    return
                }
            }
            do {
                let questions = try await mlxService.generateArticleNouns(
                    topic: topic,
                    count: count,
                    model: model
                )
                isGenerating = false
                guard questions.count >= ArticleGameService.minQuestions else {
                    errorMessage = "The model couldn't produce enough usable nouns — try again or pick a different topic."
                    return
                }
                launch(topic: topic, pool: questions, trickyBias: false)
            } catch {
                isGenerating = false
                errorMessage = "Generation failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Launch

    private func launch(topic: String, pool: [ArticleQuestion], trickyBias: Bool? = nil) {
        guard let session = ArticleGameService.session(
            topic: topic,
            pool: pool,
            count: questionCount,
            trickyFirst: trickyBias ?? trickyFirst,
            in: modelContext
        ) else {
            errorMessage = "Not enough nouns with articles in this source for a round."
            return
        }
        errorMessage = nil
        router.launch(.articleGame(session))
    }

    // MARK: - Shared row

    @ViewBuilder
    private func sourceRow(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
