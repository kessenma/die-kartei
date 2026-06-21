import SwiftUI
import SwiftData

/// The "Conversation Options" screen — pick mode, decks, scenario, grammar focus,
/// level, formality, and model, then start a session. Corrections, voice, and
/// learning-aid defaults live in Settings ▸ Conversation.
struct ConversationSetupView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    var onStart: (ConversationConfig) -> Void

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var allDecks: [SavedDeck]
    @Query private var allPhrases: [LearnedPhrase]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Set when a scenario chat has phrases to review; drives the pre-start preview push.
    @State private var previewData: ScenarioPhrasePreview?

    @State private var mode: ConversationMode = .freestyle
    @State private var selectedDeckIDs: Set<UUID> = []
    @State private var scenario: ConversationScenario = .smallTalk
    @State private var customScenario: String = ""
    @State private var focus: Set<GrammarFocus> = []
    @State private var level: CEFRLevel = .a2
    @State private var formality: Formality = .du
    @State private var model: MLXModel = .qwen3_0_6B
    @State private var didLoadDefaults = false

    /// Real, non-internal decks the user generated (mirrors SavedDecksView filtering).
    private var decks: [SavedDeck] {
        allDecks.filter {
            !["goethe", "goethe-srs", "past-tense", "past-tense-srs", "grammar"].contains($0.generatorRaw)
        }
    }

    private var canStart: Bool {
        if mode == .decks { return !selectedDeckIDs.isEmpty }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                modeSection

                if mode == .decks {
                    DeckMultiSelectSection(decks: decks, selectedIDs: $selectedDeckIDs)
                }

                if mode == .scenario {
                    scenarioSection
                }

                GrammarFocusPickerSection(selected: $focus)

                levelSection

                ChatModelPickerSection(selected: $model, cacheRefreshID: UUID())
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start() }
                        .fontWeight(.semibold)
                        .disabled(!canStart)
                }
            }
            .onAppear(perform: loadDefaults)
            .navigationDestination(item: $previewData) { data in
                ConversationPhrasePreviewView(
                    phrases: data.phrases,
                    model: data.config.model,
                    mlxService: mlxService
                ) { confirmed in
                    begin(baseConfig: data.config, confirmed: confirmed)
                }
            }
        }
    }

    // MARK: - Sections

    private var modeSection: some View {
        Section {
            Picker("Type", selection: $mode) {
                ForEach(ConversationMode.setupCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Label(mode.subtitle, systemImage: mode.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Conversation type")
        }
    }

    private var scenarioSection: some View {
        Section {
            // Currently selected scenario
            HStack(spacing: 12) {
                Image(systemName: scenario.systemImage)
                    .frame(width: 28)
                    .foregroundStyle(.tint)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(scenario.germanTitle).font(.body.weight(.medium))
                    Text(scenario == .custom && !customScenario.isEmpty ? customScenario : scenario.englishDescription)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Button {
                scenario = ConversationScenario.random()
            } label: {
                Label("Surprise me", systemImage: "die.face.5.fill")
            }

            NavigationLink {
                ScenarioPickerView(selected: $scenario, modelManager: modelManager, mlxService: mlxService)
            } label: {
                Label("Browse all scenarios", systemImage: "square.grid.2x2.fill")
            }

            if scenario != .custom {
                NavigationLink {
                    PhraseLibraryView(modelManager: modelManager, mlxService: mlxService, anchorScenario: scenario)
                } label: {
                    HStack {
                        Label("Phrases for this scenario", systemImage: "ear.badge.waveform")
                        Spacer()
                        let count = activePhraseCount(for: scenario)
                        if count > 0 {
                            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }

            if scenario == .custom {
                TextField("Describe the situation (in English or German)…", text: $customScenario, axis: .vertical)
                    .lineLimit(2...4)
            }
        } header: {
            Text("Scenario")
        } footer: {
            Text("A random scenario is picked for you — tap Surprise me to reroll, or browse the full list. The AI stays in character and sets the scene. Add phrases you've heard in the wild and the AI will work them in.")
                .font(.caption2)
        }
    }

    private func activePhraseCount(for scenario: ConversationScenario) -> Int {
        allPhrases.filter { $0.isActive && $0.applies(to: scenario) }.count
    }

    private var levelSection: some View {
        Section {
            Picker("Level", selection: $level) {
                ForEach(CEFRLevel.allCases) { l in
                    Text(l.rawValue).tag(l)
                }
            }
            .pickerStyle(.segmented)
            Text("\(level.rawValue) · \(level.englishLabel) — controls how complex the AI's German is.")
                .font(.caption).foregroundStyle(.secondary)

            Picker("Address me as", selection: $formality) {
                ForEach(Formality.allCases) { f in
                    Text(f.englishLabel).tag(f)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Level & formality")
        }
    }

    // MARK: - Actions

    private func loadDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        model = modelManager.selectedChatModel
        level = CEFRLevel(rawValue: modelManager.chatLevelRaw) ?? .a2
        formality = Formality(rawValue: modelManager.chatFormalityRaw) ?? .du
        scenario = ConversationScenario.random()
    }

    private func start() {
        // Persist the per-conversation choices as the new defaults. Corrections, voice, and
        // learning-aid defaults are edited directly in Settings, so they aren't written here.
        modelManager.selectedChatModel = model
        modelManager.chatLevelRaw = level.rawValue
        modelManager.chatFormalityRaw = formality.rawValue

        let chosenDecks = decks.filter { selectedDeckIDs.contains($0.id) }
        let deckWords = chosenDecks.flatMap { $0.cards.map(\.germanWord) }
        let deckLabel = chosenDecks.map(\.topic).joined(separator: ", ")

        var config = ConversationConfig(model: model)
        config.mode = mode
        config.deckIDs = chosenDecks.map(\.id)
        config.deckLabel = deckLabel
        config.deckWords = deckWords
        config.scenario = (mode == .scenario) ? scenario : nil
        config.customScenario = customScenario
        config.focusAreas = GrammarFocus.allCases.filter { focus.contains($0) }
        config.level = level
        config.formality = formality
        config.correctionsEnabled = modelManager.chatCorrectionsEnabled
        config.correctionTranslationEnabled = modelManager.chatShowCorrectionTranslation
        config.strictness = CorrectionStrictness(rawValue: modelManager.chatStrictnessRaw) ?? .balanced
        config.autoPlay = modelManager.autoPlayReplies
        config.eagerAssist = modelManager.chatEagerAssist
        config.autoShowTranslation = modelManager.chatAutoShowTranslation
        config.hintCount = modelManager.chatHintCount

        // For a scenario chat with phrases in rotation, review them (and warm up the model)
        // before starting. Otherwise begin immediately, as before.
        if mode == .scenario, scenario != .custom {
            let sample = LearnedPhrase.sample(for: scenario, from: allPhrases)
            if !sample.isEmpty {
                previewData = ScenarioPhrasePreview(config: config, phrases: sample)
                return
            }
        }

        onStart(config)
    }

    /// Called from the phrase preview once the user confirms which phrases to keep this session.
    private func begin(baseConfig: ConversationConfig, confirmed: [LearnedPhrase]) {
        for phrase in confirmed { phrase.markSurfaced() }
        try? modelContext.save()

        var config = baseConfig
        config.learnedPhrases = confirmed.map(\.item)
        // Fold any grammar focus the surfaced phrases carry into the session's steering.
        let union = Set(config.focusAreas).union(confirmed.flatMap(\.focusAreas))
        config.focusAreas = GrammarFocus.allCases.filter { union.contains($0) }

        onStart(config)
    }
}

/// Payload for the pre-start phrase preview push. Identifiable/Hashable by id so it can drive
/// `navigationDestination(item:)` (ConversationConfig itself isn't Hashable).
struct ScenarioPhrasePreview: Identifiable, Hashable {
    let id = UUID()
    var config: ConversationConfig
    var phrases: [LearnedPhrase]

    static func == (lhs: ScenarioPhrasePreview, rhs: ScenarioPhrasePreview) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
