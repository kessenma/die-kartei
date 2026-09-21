import SwiftUI
import SwiftData

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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @State private var topic = ""
    @State private var isOptionsExpanded = false
    @State private var showingTenseInfo: TenseInfo?
    @State private var showingShortfallAlert = false
    @State private var showingTopicInfo = false
    @State private var showingTopicBrowser = false
    /// A fresh handful of bundled ideas for the chips, drawn once per visit to this screen.
    @State private var suggestedTopics = FlashcardTopics.sample(8)
    /// Briefly true after "Add to Batch Queue", to flash the confirmation state.
    @State private var justQueued = false

    // Persisted across launches so the only decision a returning user makes is the topic.
    @AppStorage("home.wordCount") private var wordCount = 10
    @AppStorage("home.includeExamples") private var includeExamples = true
    @AppStorage("home.includeGender") private var includeGender = true
    @AppStorage("home.wordTypeFilter") private var wordTypeFilter: WordTypeFilter = .all
    @AppStorage("home.includeConjugations") private var includeConjugations = false
    @AppStorage("home.selectedTenses") private var selectedTensesRaw = "Präsens"
    /// Shared with Settings ▸ Cards and read by the flow through `CardImageTiming.current`.
    @AppStorage(CardImageTiming.defaultsKey) private var imageTiming: CardImageTiming = .keptCards

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
        Form {
                modelSection

                topicSection

                optionsSection

                generateSection

                if let error = service.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    .themedListRow()
                }
            }
            .navigationTitle("Create")
            // Was `.tint(activeTheme?.accent)`; the theme resolves the same model accent on Klar
            // and asserts its own everywhere else.
            .themedListScreen()
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 120)
            .overlay {
                // Stays up through the picture phase — one operation, two phases.
                if service.isGenerating || service.isDrawingImages {
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

    // MARK: - Topic

    private var trimmedTopic: String {
        topic.trimmingCharacters(in: .whitespaces)
    }

    private var topicSection: some View {
        Section {
            if activeModelIsReady {
                TextField("e.g. kitchen items, travel phrases, animals...", text: $topic)
                    .textInputAutocapitalization(.never)
                    .focused($isTopicFieldFocused)
                    .onSubmit { isTopicFieldFocused = false }
                if trimmedTopic.isEmpty {
                    suggestionChips
                }

                Button {
                    if let pick = FlashcardTopics.random(excluding: trimmedTopic) {
                        topic = pick.en
                        isTopicFieldFocused = false
                    }
                } label: {
                    Label("Surprise me", systemImage: "die.face.5.fill")
                }

                Button {
                    isTopicFieldFocused = false
                    showingTopicBrowser = true
                } label: {
                    Label("Browse 100 topics", systemImage: "square.grid.2x2.fill")
                }
            } else {
                Label("Select a model above to get started", systemImage: "arrow.up")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("What do you want to learn?").themedSectionHeader()
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
            if activeModelIsReady && trimmedTopic.isEmpty {
                Text("Pick a suggestion or type your own topic.")
            }
        }
        .themedListRow()
        .alert("How Topics Work", isPresented: $showingTopicInfo) {
            Button("Got it") {}
        } message: {
            Text("Enter any topic — a theme, situation, or category — and the AI generates vocabulary flashcards tailored to it.\n\nExamples: \"kitchen items\", \"travel phrases\", \"animals\", \"business German\".")
        }
        .sheet(isPresented: $showingTopicBrowser) {
            FlashcardTopicBrowseSheet { picked in
                topic = picked
            }
        }
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestedTopics) { idea in
                    Button {
                        topic = idea.en
                        isTopicFieldFocused = false
                    } label: {
                        Text(idea.en)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill), in: theme.pillShape)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 0))
    }

    // MARK: - Options

    private var selectedTenses: Set<String> {
        let parsed = Set(selectedTensesRaw.split(separator: ",").map(String.init))
        return parsed.isEmpty ? ["Präsens"] : parsed
    }

    /// Selected tenses in canonical (pedagogical) order rather than Set order.
    private var orderedSelectedTenses: [String] {
        tenses.map(\.id).filter { selectedTenses.contains($0) }
    }

    private func setTense(_ id: String, isOn: Bool) {
        var updated = selectedTenses
        if isOn {
            updated.insert(id)
        } else if updated.count > 1 {
            updated.remove(id)
        }
        selectedTensesRaw = tenses.map(\.id).filter { updated.contains($0) }.joined(separator: ",")
    }

    private var wordTypeSummary: String {
        switch wordTypeFilter {
        case .all: "all word types"
        case .nouns: "nouns"
        case .verbs: "verbs"
        case .adjectives: "adjectives"
        case .verbsAndAdjectives: "verbs & adjectives"
        }
    }

    /// One-line recap of the current setup, shown while the options group is collapsed.
    private var optionsSummary: String {
        var parts = ["\(wordCount) cards", wordTypeSummary]
        if includeExamples {
            parts.append("examples")
        }
        if wordTypeFilter.includesVerbs {
            let selected = orderedSelectedTenses
            parts.append(selected.count == 1 ? selected[0] : "\(selected.count) tenses")
        }
        return parts.joined(separator: " · ")
    }

    private var optionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isOptionsExpanded) {
                Picker("Word type", selection: $wordTypeFilter) {
                    ForEach(WordTypeFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Number of cards")
                    Picker("Number of cards", selection: $wordCount) {
                        ForEach(wordCountOptions, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)

                Toggle("Example sentences", isOn: $includeExamples)

                // The toggle needs the model on disk. This used to be a silent hide, on the grounds
                // that there was "nothing useful to promise otherwise" — but the result was that
                // anyone making flashcards never learned the feature existed at all. So the space
                // now carries the offer instead of nothing, and it is dismissible for good.
                if ImageGenModel.current.isDownloaded {
                    Toggle(isOn: Binding(
                        get: { service.modelManager.flashcardIllustrationsEnabled },
                        set: { service.modelManager.flashcardIllustrationsEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI pictures")
                            Text("Drawn on-device as part of this run — the deck opens with its pictures already in place.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if service.modelManager.flashcardIllustrationsEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Draw pictures for")
                                .font(.subheadline)
                            Picker("Draw pictures for", selection: $imageTiming) {
                                ForEach(CardImageTiming.allCases) { timing in
                                    Text(timing.label).tag(timing)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(imageTiming.caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)

                        CardImageStyleRow(mlxService: service.mlxService)
                    }
                } else {
                    ModelUpgradeNudge(kind: .pictures)
                }

                if wordTypeFilter.includesNouns {
                    Toggle("Gender (der/die/das)", isOn: $includeGender)
                }

                if wordTypeFilter.includesVerbs {
                    Toggle("Conjugation tables", isOn: $includeConjugations)
                    if includeConjugations && wordTypeFilter == .verbsAndAdjectives {
                        Label("Conjugation tables apply to verbs only.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Tenses to include")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(tenses) { tense in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { selectedTenses.contains(tense.id) },
                                set: { setTense(tense.id, isOn: $0) }
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
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Options")
                    Text(optionsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if isOptionsExpanded {
                wordTypeFooter
            }
        }
        .themedListRow()
        .alert(item: $showingTenseInfo) { tense in
            Alert(
                title: Text("\(tense.german) — \(tense.english)"),
                message: Text("\(tense.explanation)\n\n\(tense.example)"),
                dismissButton: .default(Text("OK"))
            )
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

    // MARK: - Generate

    private var generateSection: some View {
        Section {
            Button(action: generate) {
                Label("Generate \(wordCount) Flashcards", systemImage: "sparkles")
                    .themedLabel(.headline, size: 17)
                    .textCase(theme.uppercaseSectionHeaders ? .uppercase : nil)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(activeTheme == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
            }
            .disabled(generateDisabled)
            .listRowBackground(generateRowBackground)
        } footer: {
            // Same setup, but queued for later instead of generated now (runs from
            // Home ▸ All Activities ▸ Batch). Doesn't need the model loaded.
            Button(action: addToQueue) {
                Label(
                    justQueued ? "Added to the Batch Queue" : "Add to Batch Queue instead",
                    systemImage: justQueued ? "checkmark.circle.fill" : "text.badge.plus"
                )
                .font(.subheadline)
            }
            .disabled(trimmedTopic.isEmpty || justQueued)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private func addToQueue() {
        isTopicFieldFocused = false
        let hasVerbs = wordTypeFilter.includesVerbs
        let job = BatchJob.flashcards(
            topic: trimmedTopic,
            wordCount: wordCount,
            includeExamples: includeExamples,
            includeGender: includeGender,
            wordTypeFilter: wordTypeFilter,
            includeConjugations: hasVerbs && includeConjugations,
            selectedTenses: hasVerbs ? Array(selectedTenses) : [],
            withImages: service.modelManager.flashcardIllustrationsEnabled && ImageGenModel.current.isDownloaded,
            generatorRaw: service.modelManager.selectedMLXModel.rawValue,
            sortOrder: BatchQueueService.shared.nextSortOrder(in: modelContext)
        )
        modelContext.insert(job)
        try? modelContext.save()
        justQueued = true
        topic = ""
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            justQueued = false
        }
    }

    @ViewBuilder
    private var generatingOverlay: some View {
        let illustration = DeckIllustrationService.shared
        GeneratingFlashcardsView(
            progress: service.generationProgress,
            cardsGenerated: service.cardsGenerated,
            cardsRequested: service.cardsRequested,
            isValidating: service.isValidating,
            topic: topic,
            startTime: service.generationStartTime ?? service.drawingImagesStartTime ?? Date(),
            model: service.modelManager.selectedMLXModel,
            generatedWords: service.generatedCards.map { $0.englishTranslation },
            streamingTokenCount: service.mlxService.streamingTokenCount,
            currentBatchSize: service.currentBatchSize,
            currentBatchIndex: service.currentBatchIndex,
            onStop: { service.stopGeneration() },
            isDrawingImages: service.isDrawingImages,
            imagesDrawn: illustration.completedCount,
            imagesTotal: illustration.totalCount,
            imageProgress: illustration.progress,
            onStopImages: { illustration.stop() }
        )
    }

    // MARK: - Model Status

    private var activeModelIsReady: Bool {
        service.isAvailable
    }

    /// Brand theme of the model currently loaded in memory, or `nil` when none is ready. Drives the
    /// per-model tint of the whole form and the Generate button's gradient.
    private var activeTheme: ModelTheme? {
        service.mlxService.loadedModel?.theme
    }

    private var generateDisabled: Bool {
        trimmedTopic.isEmpty
        || service.isGenerating
        || service.isDrawingImages
        || !service.isAvailable
    }

    /// A brand-gradient fill for the Generate button once a model is loaded (it's only enabled then),
    /// dimmed while disabled; falls back to the theme's own surface otherwise. The gradient is the
    /// model's, deliberately: the app theme owns the chrome, `ModelTheme` still owns this button.
    @ViewBuilder
    private var generateRowBackground: some View {
        if let activeTheme {
            activeTheme.linear.opacity(generateDisabled ? 0.4 : 1)
        } else {
            theme.surface
        }
    }

    private var modelSection: some View {
        ModelPickerButton(
            selection: Binding(
                get: { service.modelManager.selectedMLXModel },
                set: { service.modelManager.selectedMLXModel = $0 }
            ),
            modelManager: service.modelManager,
            mlxService: service.mlxService
        )
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
                    await drawPicturesIfTimedForEveryCard()
                    onGenerationComplete()
                }
            } else if service.errorMessage == nil {
                await drawPicturesIfTimedForEveryCard()
                if service.uniqueShortfall != nil {
                    showingShortfallAlert = true
                } else {
                    onGenerationComplete()
                }
            }
        }
    }

    /// The `CardImageTiming.everyCard` half of the picture setting: the words are done, so draw
    /// their pictures now, before the review, instead of after the deck is saved. The other
    /// timing (`.keptCards`) draws in `ContentView` once the learner has picked.
    private func drawPicturesIfTimedForEveryCard() async {
        guard service.modelManager.flashcardIllustrationsEnabled,
              ImageGenModel.current.isDownloaded,
              CardImageTiming.current == .everyCard,
              !service.generatedCards.isEmpty
        else { return }
        await service.drawDraftImages()
    }
}
