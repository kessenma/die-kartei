import SwiftUI

enum WordTypeFilter: String, CaseIterable, Codable {
    case all = "All"
    case nouns = "Nouns"
    case verbs = "Verbs"
    case adjectives = "Adjectives"
    case verbsAndAdjectives = "Verbs & Adj."

    var includesVerbs: Bool {
        self == .all || self == .verbs || self == .verbsAndAdjectives
    }

    var includesAdjectives: Bool {
        self == .all || self == .adjectives || self == .verbsAndAdjectives
    }

    var includesNouns: Bool {
        self == .all || self == .nouns
    }
}

struct HomeView: View {
    @Bindable var service: GenerationCoordinator
    var onGenerationComplete: () -> Void

    @FocusState private var isTopicFieldFocused: Bool
    @State private var topic = ""
    @State private var wordCount = 10
    @State private var includeExamples = true
    @State private var includeGender = true
    @State private var wordTypeFilter: WordTypeFilter = .all
    @State private var includeConjugations = false
    @State private var selectedTenses: Set<String> = ["Präsens"]
    @State private var showingTenseInfo: TenseInfo?
    @State private var showingShortfallAlert = false
    @State private var cacheRefreshID = UUID()
    @State private var showingModelPicker = false
    @State private var showingTopicInfo = false

    private let wordCountOptions = [5, 10, 15, 20, 30, 50]

    private struct TenseInfo: Identifiable {
        let id: String
        let german: String
        let english: String
        let explanation: String
        let example: String
    }

    private let tenses: [TenseInfo] = [
        TenseInfo(
            id: "Präsens",
            german: "Präsens",
            english: "Present",
            explanation: "Used for actions happening now, habitual actions, and general truths. This is the most common tense in everyday German.",
            example: "Ich mache meine Hausaufgaben. (I do my homework.)"
        ),
        TenseInfo(
            id: "Perfekt",
            german: "Perfekt",
            english: "Present Perfect",
            explanation: "The most common past tense in spoken German. Formed with haben or sein + past participle. Used for completed actions in the past.",
            example: "Ich habe meine Hausaufgaben gemacht. (I have done my homework.)"
        ),
        TenseInfo(
            id: "Präteritum",
            german: "Präteritum",
            english: "Simple Past",
            explanation: "Used primarily in written German (novels, news) and with common verbs like sein, haben, and modal verbs in speech. Also called Imperfekt.",
            example: "Ich machte meine Hausaufgaben. (I did my homework.)"
        ),
        TenseInfo(
            id: "Plusquamperfekt",
            german: "Plusquamperfekt",
            english: "Past Perfect",
            explanation: "Describes an action that was completed before another past action. Formed with hatte/war + past participle.",
            example: "Ich hatte meine Hausaufgaben gemacht, bevor ich spielte. (I had done my homework before I played.)"
        ),
    ]

    var body: some View {
        NavigationStack {
            Form {
                modelSection

                // MARK: Topic
                Section {
                    if activeModelIsReady {
                        TextField("e.g. kitchen items, travel phrases, animals...", text: $topic)
                            .textInputAutocapitalization(.never)
                            .focused($isTopicFieldFocused)
                            .onSubmit { isTopicFieldFocused = false }
                    } else {
                        Label("Select a model above to get started", systemImage: "arrow.up")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("What do you want to learn?")
                        Spacer()
                        Button {
                            showingTopicInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    if activeModelIsReady && topic.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Enter a topic and the AI will generate vocabulary flashcards based on it.")
                    }
                }
                .alert("How Topics Work", isPresented: $showingTopicInfo) {
                    Button("Got it") {}
                } message: {
                    Text("Enter any topic — a theme, situation, or category — and the AI generates vocabulary flashcards tailored to it.\n\nExamples: \"kitchen items\", \"travel phrases\", \"animals\", \"business German\".")
                }

                // MARK: Options
                Section {
                    Picker("Word type", selection: $wordTypeFilter) {
                        ForEach(WordTypeFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    Toggle("Include example sentences", isOn: $includeExamples)
                    if wordTypeFilter.includesNouns {
                        Toggle("Include gender (der/die/das)", isOn: $includeGender)
                    }
                    if wordTypeFilter.includesVerbs {
                        Toggle("Show conjugation tables", isOn: $includeConjugations)
                        if includeConjugations && wordTypeFilter == .verbsAndAdjectives {
                            Label("Conjugation tables apply to verbs only.", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Options")
                } footer: {
                    wordTypeFooter
                }

                // MARK: Tenses to Include
                if wordTypeFilter.includesVerbs {
                    Section("Tenses to Include") {
                        ForEach(tenses) { tense in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { selectedTenses.contains(tense.id) },
                                    set: { isOn in
                                        if isOn {
                                            selectedTenses.insert(tense.id)
                                        } else if selectedTenses.count > 1 {
                                            selectedTenses.remove(tense.id)
                                        }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tense.german)
                                        Text(tense.english)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Button {
                                    showingTenseInfo = tense
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .alert(item: $showingTenseInfo) { tense in
                        Alert(
                            title: Text("\(tense.german) — \(tense.english)"),
                            message: Text("\(tense.explanation)\n\n\(tense.example)"),
                            dismissButton: .default(Text("OK"))
                        )
                    }
                }

                // MARK: Word Count + Generate
                Section {
                    Picker("Number of words", selection: $wordCount) {
                        ForEach(wordCountOptions, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How many Flashcards?")
                }

                Section {
                    Button(action: generate) {
                        Label("Generate Flashcards", systemImage: "sparkles")
                    }
                    .disabled(
                        topic.trimmingCharacters(in: .whitespaces).isEmpty
                        || service.isGenerating
                        || !service.isAvailable
                    )
                }

                if let error = service.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Create")
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 120)
            .sheet(isPresented: $showingModelPicker) {
                modelPickerSheet
            }
            .overlay {
                if service.isGenerating {
                    generatingOverlay
                }
            }
            .alert(
                "Fewer Cards Generated",
                isPresented: $showingShortfallAlert
            ) {
                Button("Continue") {
                    onGenerationComplete()
                }
            } message: {
                if let shortfall = service.uniqueShortfall {
                    Text("Only \(shortfall.generated) unique cards could be generated for \"\(topic)\" (you requested \(shortfall.requested)). The model ran out of unique words for this topic.")
                }
            }
        }
    }

    @ViewBuilder
    private var wordTypeFooter: some View {
        switch wordTypeFilter {
        case .all:
            Text("Generates a mix of nouns (with articles & plurals), verbs, and adjectives.")
        case .nouns:
            Text("Nouns include the article (der/die/das) and plural form.")
        case .verbs:
            Text("Verbs include infinitive forms and selected conjugation tenses.")
        case .adjectives:
            Text("Adjectives include common forms and usage examples.")
        case .verbsAndAdjectives:
            Text("Verbs include conjugation tenses; adjectives include common forms.")
        }
    }

    @ViewBuilder
    private var generatingOverlay: some View {
        GeneratingFlashcardsView(
            progress: service.generationProgress,
            cardsGenerated: service.cardsGenerated,
            cardsRequested: service.cardsRequested,
            isValidating: service.isValidating,
            topic: topic,
            startTime: service.generationStartTime ?? Date(),
            generatedWords: service.generatedCards.map { $0.englishTranslation },
            streamingTokenCount: service.mlxService.streamingTokenCount,
            currentBatchSize: service.currentBatchSize,
            currentBatchIndex: service.currentBatchIndex,
            onStop: { service.stopGeneration() }
        )
    }

    // MARK: - Model Status & Picker

    private var activeModel: MLXModel {
        let mlxService = service.mlxService
        let modelManager = service.modelManager
        if let current = mlxService.currentModel, mlxService.isModelLoaded {
            return current
        }
        return modelManager.selectedMLXModel
    }

    private var activeModelName: String {
        activeModel.rawValue
    }

    private var activeModelIsReady: Bool {
        service.isAvailable
    }

    @ViewBuilder
    private var modelSection: some View {
        let mlxService = service.mlxService

        Section {
            // Current model indicator — tap to open picker
            Button {
                showingModelPicker = true
            } label: {
                HStack {
                    Image(activeModel.logoName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeModelName)
                            .foregroundStyle(.primary)
                        if mlxService.isLoading {
                            Text("Loading…")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if activeModelIsReady {
                            Text("Ready")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("Not loaded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(mlxService.isLoading)

            // Inline loading progress when an MLX model is being loaded
            if mlxService.isLoading {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Image(activeModel.logoName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(mlxService.downloadInfo ?? "Loading model…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let progress = mlxService.downloadProgress, progress > 0 {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    HStack {
                        if let start = mlxService.loadStartTime {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text("Elapsed: \(elapsedString(since: start))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer()
                        if let bytes = mlxService.downloadBytesInfo {
                            Text(bytes)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Button("Cancel", role: .destructive) {
                        mlxService.cancelLoad()
                    }
                    .font(.caption)
                }
            }
        } header: {
            Label("Model", systemImage: "cpu")
        }

        if let error = mlxService.loadError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Model Picker Sheet

    @ViewBuilder
    private var modelPickerSheet: some View {
        let mlxService = service.mlxService
        let modelManager = service.modelManager
        let downloadedModels = MLXModel.allCases.filter { isDownloaded($0) }
        let lastLoaded = modelManager.lastLoadedModel

        NavigationStack {
            List {
                Section {
                    if downloadedModels.isEmpty {
                        Label("No models downloaded yet. Go to Settings to download one.", systemImage: "arrow.down.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(downloadedModels) { model in
                            let isActive = mlxService.isModelLoaded && mlxService.currentModel == model
                            let isLastUsed = lastLoaded == model && !isActive

                            Button {
                                modelManager.selectedMLXModel = model
                                showingModelPicker = false
                                Task {
                                    await mlxService.loadModel(model)
                                    cacheRefreshID = UUID()
                                }
                            } label: {
                                HStack {
                                    Image(model.logoName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(model.rawValue)
                                                .foregroundStyle(.primary)
                                            if isLastUsed {
                                                Text("Last used")
                                                    .font(.caption2)
                                                    .fontWeight(.semibold)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.12))
                                                    .foregroundStyle(.secondary)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text("~\(formattedSize(model.approximateSizeMB))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isActive {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("MLX Models")
                } footer: {
                    Text("Download more models in Settings.")
                }
            }
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingModelPicker = false }
                }
            }
        }
        .onChange(of: mlxService.currentModel) { _, newModel in
            if let model = newModel {
                service.modelManager.lastLoadedModel = model
            }
        }
        .presentationDetents([.medium])
    }

    private func isDownloaded(_ model: MLXModel) -> Bool {
        _ = cacheRefreshID
        return model.isDownloaded
    }

    private func formattedSize(_ mb: Int) -> String {
        if mb >= 1000 {
            let gb = Double(mb) / 1000.0
            return String(format: "%.1f GB", gb)
        }
        return "\(mb) MB"
    }

    private func elapsedString(since start: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(start))
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private func generate() {
        isTopicFieldFocused = false
        let hasVerbs = wordTypeFilter.includesVerbs
        Task {
            await service.generateVocab(
                topic: topic,
                count: wordCount,
                includeExamples: includeExamples,
                includeGender: includeGender,
                wordTypeFilter: wordTypeFilter,
                includeConjugations: hasVerbs && includeConjugations,
                selectedTenses: hasVerbs ? Array(selectedTenses) : []
            )
            if service.wasStoppedEarly {
                if !service.generatedCards.isEmpty {
                    onGenerationComplete()
                }
            } else if service.errorMessage == nil {
                if service.uniqueShortfall != nil {
                    showingShortfallAlert = true
                } else {
                    onGenerationComplete()
                }
            }
        }
    }
}


