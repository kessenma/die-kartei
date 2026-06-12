import SwiftUI
import SwiftData

/// The "Conversation Options" screen — pick mode, decks, scenario, grammar focus,
/// level, formality, corrections, and model, then start a session.
struct ConversationSetupView: View {
    @Bindable var modelManager: MLXModelManager
    var onStart: (ConversationConfig) -> Void

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var allDecks: [SavedDeck]
    @Environment(\.dismiss) private var dismiss

    @State private var mode: ConversationMode = .freestyle
    @State private var selectedDeckIDs: Set<UUID> = []
    @State private var scenario: ConversationScenario = .smallTalk
    @State private var customScenario: String = ""
    @State private var focus: Set<GrammarFocus> = []
    @State private var level: CEFRLevel = .a2
    @State private var formality: Formality = .du
    @State private var corrections: Bool = true
    @State private var strictness: CorrectionStrictness = .balanced
    @State private var model: MLXModel = .qwen3_0_6B
    @State private var eager: Bool = false
    @State private var autoShowTranslation: Bool = true
    @State private var hintCount: Int = 1
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
                correctionsSection

                ChatModelPickerSection(selected: $model, cacheRefreshID: UUID())

                voiceSection
                learningAidsSection
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
                ScenarioPickerView(selected: $scenario)
            } label: {
                Label("Browse all scenarios", systemImage: "square.grid.2x2.fill")
            }

            if scenario == .custom {
                TextField("Describe the situation (in English or German)…", text: $customScenario, axis: .vertical)
                    .lineLimit(2...4)
            }
        } header: {
            Text("Scenario")
        } footer: {
            Text("A random scenario is picked for you — tap Surprise me to reroll, or browse the full list. The AI stays in character and sets the scene.")
                .font(.caption2)
        }
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

    private var correctionsSection: some View {
        Section {
            Toggle("Correct my mistakes", isOn: $corrections)
            if corrections {
                Picker("Strictness", selection: $strictness) {
                    ForEach(CorrectionStrictness.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                Text(strictness.subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Corrections")
        } footer: {
            Text("When on, the corrected sentence and a short explanation appear above your message whenever something needs fixing.")
                .font(.caption2)
        }
    }

    private var voiceSection: some View {
        Section {
            Toggle("Auto-play AI replies", isOn: $modelManager.autoPlayReplies)
        } header: {
            Text("Voice")
        } footer: {
            Text("Replies are spoken aloud automatically. You can always replay them with the play / slow buttons.")
                .font(.caption2)
        }
    }

    private var learningAidsSection: some View {
        Section {
            Picker("Hints per request", selection: $hintCount) {
                Text("1").tag(1)
                Text("2").tag(2)
                Text("3").tag(3)
            }
            .pickerStyle(.segmented)

            Toggle("Auto-translate & pre-load hints", isOn: $eager)

            if eager {
                Toggle("Auto-show translations", isOn: $autoShowTranslation)
            }
        } header: {
            Text("Learning aids")
        } footer: {
            Text(learningAidsFooter)
                .font(.caption2)
        }
    }

    private var learningAidsFooter: String {
        if !eager {
            return "Pick how many hint suggestions to generate. Turn on auto-translate to prepare translations and hints in the background so they’re instant."
        }
        if autoShowTranslation {
            return "Translations appear automatically under each reply, and hints are pre-loaded so they show instantly. Great for early learners — uses a bit more battery."
        }
        return "Translations and hints are prepared in the background but stay hidden until you tap, so taps are instant. Uses a bit more battery."
    }

    // MARK: - Actions

    private func loadDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        model = modelManager.selectedChatModel
        level = CEFRLevel(rawValue: modelManager.chatLevelRaw) ?? .a2
        formality = Formality(rawValue: modelManager.chatFormalityRaw) ?? .du
        strictness = CorrectionStrictness(rawValue: modelManager.chatStrictnessRaw) ?? .balanced
        corrections = modelManager.chatCorrectionsEnabled
        eager = modelManager.chatEagerAssist
        autoShowTranslation = modelManager.chatAutoShowTranslation
        hintCount = modelManager.chatHintCount
        scenario = ConversationScenario.random()
    }

    private func start() {
        // Persist choices as the new defaults.
        modelManager.selectedChatModel = model
        modelManager.chatLevelRaw = level.rawValue
        modelManager.chatFormalityRaw = formality.rawValue
        modelManager.chatStrictnessRaw = strictness.rawValue
        modelManager.chatCorrectionsEnabled = corrections
        modelManager.chatEagerAssist = eager
        modelManager.chatAutoShowTranslation = autoShowTranslation
        modelManager.chatHintCount = hintCount

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
        config.correctionsEnabled = corrections
        config.strictness = strictness
        config.autoPlay = modelManager.autoPlayReplies
        config.eagerAssist = eager
        config.autoShowTranslation = autoShowTranslation
        config.hintCount = hintCount

        onStart(config)
    }
}
