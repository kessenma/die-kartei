import SwiftUI
import SwiftData

/// The user's "heard-in-the-wild" phrase library. Phrases you hear out and about but don't
/// understand (like a clerk's "Sonst noch etwas?") live here; when active, the AI works them into
/// the matching scenario chats — spoken by its character — so you get used to hearing them.
struct PhraseLibraryView: View {
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// When opened from a scenario, new phrases are pre-tagged to it.
    var anchorScenario: ConversationScenario? = nil
    /// True when rendered inline inside the Library's segmented control (rather than pushed as its
    /// own screen). The Library owns the nav bar via a principal picker, so we yield our title to it.
    var embedded: Bool = false

    @Query(sort: \LearnedPhrase.createdAt, order: .reverse) private var phrases: [LearnedPhrase]
    @Environment(\.modelContext) private var modelContext

    @State private var showingAdd = false
    @State private var editing: LearnedPhrase?
    /// Candidate phrases to turn into flashcards (all, or a single swiped row). Non-nil drives the sheet.
    @State private var deckCandidates: DeckCandidates?

    var body: some View {
        List {
            Section {
                Label {
                    Text("Phrases you hear out in the wild but don't understand — like a clerk asking “Sonst noch etwas?”. Save them here and the AI will work the active ones into your scenario chats, spoken by its character, so you get used to hearing them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "ear.badge.waveform")
                        .foregroundStyle(.tint)
                }
            }

            if phrases.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No phrases yet",
                        systemImage: "text.bubble",
                        description: Text("Tap + to save a phrase you heard in the wild.")
                    )
                }
            } else {
                Section {
                    ForEach(phrases) { phrase in
                        PhraseRow(phrase: phrase) { newValue in
                            phrase.isActive = newValue
                            try? modelContext.save()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = phrase }
                        .swipeActions(edge: .leading) {
                            Button {
                                deckCandidates = DeckCandidates(phrases: [phrase])
                            } label: {
                                Label("Flashcards", systemImage: "rectangle.stack.badge.plus")
                            }
                            .tint(.accentColor)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(phrase) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Your phrases")
                } footer: {
                    Text("Toggle a phrase off to take it out of rotation without deleting it. Swipe to delete. The logo shows which model checked the phrase.")
                        .font(.caption2)
                }
            }
        }
        // Clear both the floating FAB and the app's global NavBar (a ZStack overlay in
        // ContentView that sits on top of this view), so the last row is fully reachable.
        .contentMargins(.bottom, 170, for: .scrollContent)
        // Pick up the loaded model's brand color, mirroring Home's per-model tint.
        .tint(activeTheme?.accent)
        .navigationTitle(embedded ? "Library" : "Phrase library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !phrases.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        deckCandidates = DeckCandidates(phrases: phrases)
                    } label: {
                        Label("Add to flashcards", systemImage: "rectangle.stack.badge.plus")
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            addButton
        }
        .sheet(isPresented: $showingAdd) {
            AddEditPhraseSheet(
                modelManager: modelManager,
                mlxService: mlxService,
                anchorScenario: anchorScenario,
                phrase: nil
            )
        }
        .sheet(item: $editing) { phrase in
            AddEditPhraseSheet(
                modelManager: modelManager,
                mlxService: mlxService,
                anchorScenario: anchorScenario,
                phrase: phrase
            )
        }
        .sheet(item: $deckCandidates) { candidates in
            PhraseToDeckSheet(phrases: candidates.phrases)
        }
    }

    /// Floating "add phrase" button parked in the bottom-right thumb zone.
    private var addButton: some View {
        Button { showingAdd = true } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(addButtonFill, in: Circle())
                .shadow(color: (activeTheme?.accent ?? .black).opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("Add phrase")
        .padding(.trailing, 20)
        // The app's global NavBar (ContentView ZStack overlay) covers ~96pt at the bottom;
        // sit the button just above it rather than behind it.
        .padding(.bottom, 110)
    }

    /// Brand theme of the model currently loaded in memory (same source Home uses), or `nil` when
    /// none is loaded. Drives the list tint and the floating add button's fill.
    private var activeTheme: ModelTheme? {
        mlxService.loadedModel?.theme
    }

    /// The add button's circle fill: the loaded model's brand gradient, or the app accent otherwise.
    private var addButtonFill: AnyShapeStyle {
        activeTheme.map { AnyShapeStyle($0.linear) } ?? AnyShapeStyle(Color.accentColor)
    }

    private func delete(_ phrase: LearnedPhrase) {
        modelContext.delete(phrase)
        try? modelContext.save()
    }
}

/// Identifiable wrapper so a set of phrases can drive an item-based `.sheet`.
private struct DeckCandidates: Identifiable {
    let id = UUID()
    let phrases: [LearnedPhrase]
}

// MARK: - Row

private struct PhraseRow: View {
    let phrase: LearnedPhrase
    let onSetActive: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(phrase.german)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if let logo = phrase.creatorLogoName {
                        Image(logo).resizable().scaledToFit()
                            .frame(width: 15, height: 15)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(phrase.english)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !phrase.scenarios.isEmpty || !phrase.focusAreas.isEmpty {
                    FlowChips(items: phrase.scenarios.map(\.germanTitle) + phrase.focusAreas.map(\.germanLabel))
                        .padding(.top, 1)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(get: { phrase.isActive }, set: { onSetActive($0) }))
                .labelsHidden()
        }
        .padding(.vertical, 2)
        .opacity(phrase.isActive ? 1 : 0.45)
    }
}

// MARK: - Add / edit sheet

/// Add a new phrase or edit an existing one. The phrase is validated by the on-device model into
/// natural German (whether typed in English or German) before it can be saved.
struct AddEditPhraseSheet: View {
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    var anchorScenario: ConversationScenario?
    /// nil = adding; non-nil = editing.
    var phrase: LearnedPhrase?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var inputIsGerman: Bool
    @State private var inputText: String
    @State private var selectedScenarios: Set<ConversationScenario>
    @State private var selectedFocus: Set<GrammarFocus>
    @State private var isActive: Bool

    /// When on, the phrase check also asks the AI which scenario(s) you'd hear this in
    /// and auto-selects them below.
    @State private var autoScenario = false
    /// When on, the phrase check also asks the AI to tag the grammar structure(s) and
    /// auto-selects them below.
    @State private var autoGrammar = false

    @State private var checking = false
    @State private var checkError: String?
    @State private var checkResult: ConversationPrompts.PhraseCheckResult?
    @State private var checkedModelRaw: String?
    /// Set when the user tries to save without picking a scenario — drives the inline hint and a
    /// scroll to the scenario section. Cleared as soon as a scenario is selected.
    @State private var needsScenarioHint = false
    /// Set when the user asked the AI to pick a scenario but it returned nothing usable — shows an
    /// obvious "the AI couldn't categorize this" banner and scrolls to the picker. Cleared on select.
    @State private var aiCouldNotCategorize = false
    /// Setting this to the scenario anchor asks the form to scroll there. Lets the async check (which
    /// runs outside the `ScrollViewReader`) request a scroll. Reset to nil once the scroll fires.
    @State private var scrollTarget: String?
    @FocusState private var inputFocused: Bool

    /// Scroll anchor for the "Where you might hear it" section.
    private static let scenarioAnchorID = "scenarioSection"
    /// Owned here (not inside `ModelPickerButton`) so the picker sheet is anchored to this sheet's
    /// `NavigationStack` root rather than a `Form` section — a section-level `.sheet` is realized
    /// multiple times and collides ("already presenting"), collapsing both sheets. See `present:`.
    @State private var showingModelPicker = false

    /// Binding to the conversation model used by both the row and the hosted picker sheet.
    private var chatModelBinding: Binding<MLXModel> {
        Binding(get: { modelManager.selectedChatModel }, set: { modelManager.selectedChatModel = $0 })
    }

    /// Brand theme of the model currently loaded in memory, mirroring Home. Tints the sheet so it
    /// picks up the active provider's color.
    private var activeTheme: ModelTheme? {
        mlxService.loadedModel?.theme
    }

    private var allScenarios: [ConversationScenario] {
        ConversationScenario.allCases.filter { $0 != .custom }
    }

    init(
        modelManager: MLXModelManager,
        mlxService: MLXGenerationService,
        anchorScenario: ConversationScenario?,
        phrase: LearnedPhrase?,
        initialGerman: String? = nil
    ) {
        self.modelManager = modelManager
        self.mlxService = mlxService
        self.anchorScenario = anchorScenario
        self.phrase = phrase
        if let phrase {
            _inputIsGerman = State(initialValue: true)
            _inputText = State(initialValue: phrase.german)
            _selectedScenarios = State(initialValue: Set(phrase.scenarios))
            _selectedFocus = State(initialValue: Set(phrase.focusAreas))
            _isActive = State(initialValue: phrase.isActive)
            _checkResult = State(initialValue: ConversationPrompts.PhraseCheckResult(
                german: phrase.german, english: phrase.english, fixed: false, note: phrase.note
            ))
            _checkedModelRaw = State(initialValue: phrase.creatorModelRaw.isEmpty ? nil : phrase.creatorModelRaw)
        } else {
            _inputIsGerman = State(initialValue: true)
            _inputText = State(initialValue: initialGerman ?? "")
            _selectedScenarios = State(initialValue: anchorScenario.map { [$0] } ?? [])
            _selectedFocus = State(initialValue: [])
            _isActive = State(initialValue: true)
            _checkResult = State(initialValue: nil)
            _checkedModelRaw = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    ModelPickerButton(
                        selection: chatModelBinding,
                        modelManager: modelManager,
                        mlxService: mlxService,
                        footer: "This model checks your phrase. Pick a capable model for the most reliable results — tiny models sometimes can't read the phrase cleanly.",
                        present: $showingModelPicker
                    )
                    inputSection
                    if let result = checkResult { resultSection(result) }
                    scenarioSection
                        .id(Self.scenarioAnchorID)
                    GrammarFocusPickerSection(selected: $selectedFocus)
                    activeSection
                }
                .scrollDismissesKeyboard(.interactively)
                .tint(activeTheme?.accent)
                .navigationTitle(phrase == nil ? "New phrase" : "Edit phrase")
                .navigationBarTitleDisplayMode(.inline)
                // Reuse a model that's already resident in memory (e.g. loaded on Home) so the
                // picker shows it as "Ready" instead of asking the user to load again.
                .onAppear(perform: adoptLoadedModel)
                // A scenario is required to save; clear both nudges the moment one is picked.
                .onChange(of: selectedScenarios) { _, new in
                    if !new.isEmpty {
                        needsScenarioHint = false
                        aiCouldNotCategorize = false
                    }
                }
                // Honor scroll requests coming from the async check or the Save tap.
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                    scrollTarget = nil
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { attemptSave() }
                            .fontWeight(.semibold)
                            // Enabled once a phrase is checked; a missing scenario is handled by
                            // attemptSave (scroll + hint) rather than a silent disable.
                            .disabled(checkResult == nil)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { inputFocused = false }
                    }
                }
                // Anchored to the NavigationStack root (a single, stable host) so it doesn't collide
                // with this sheet's presentation the way a Form-section-level `.sheet` does.
                .sheet(isPresented: $showingModelPicker) {
                    ModelPickerSheet(
                        selection: chatModelBinding,
                        modelManager: modelManager,
                        mlxService: mlxService
                    )
                }
            }
        }
    }

    // MARK: Sections

    private var inputSection: some View {
        Section {
            Picker("I'll type it in", selection: $inputIsGerman) {
                Text("German").tag(true)
                Text("English").tag(false)
            }
            .pickerStyle(.segmented)

            TextField(
                inputIsGerman ? "z. B. „Sonst noch etwas?“" : "e.g. “Anything else?”",
                text: $inputText,
                axis: .vertical
            )
            .lineLimit(1...3)
            .focused($inputFocused)
            .onChange(of: inputText) { _, _ in clearCheck() }
            .onChange(of: inputIsGerman) { _, _ in clearCheck() }

            Toggle(isOn: $autoScenario) {
                Label("Let the AI pick where you'd hear it", systemImage: "mappin.and.ellipse")
                    .font(.callout)
            }
            Toggle(isOn: $autoGrammar) {
                Label("Let the AI tag the grammar", systemImage: "text.book.closed")
                    .font(.callout)
            }

            Button {
                runCheck()
            } label: {
                if checking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    }
                } else {
                    Label(inputIsGerman ? "Check this German" : "Translate & check", systemImage: "checkmark.seal")
                }
            }
            .disabled(checking || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if mlxService.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(mlxService.downloadInfo ?? "Loading \(modelManager.selectedChatModel.rawValue)…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let checkError {
                Label(checkError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Phrase")
        } footer: {
            Text("These are phrases you hear out in the wild — usually things said to you. We'll confirm the natural German before saving. Turn on the toggles to let the AI also fill in the scenario and grammar tags below.")
                .font(.caption2)
        }
    }

    private func resultSection(_ result: ConversationPrompts.PhraseCheckResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.german)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        SpeechService.shared.speak(result.german)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                }

                Text(result.english)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    statusBadge(result.fixed)
                    if let note = result.note, !note.isEmpty {
                        Text(note).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } header: {
            Text("Checked")
        }
    }

    private var scenarioSection: some View {
        Section {
            if aiCouldNotCategorize && selectedScenarios.isEmpty {
                Label {
                    Text("The AI wasn't sure where you'd hear this phrase. Pick a category below so it can be saved.")
                        .font(.callout.weight(.medium))
                } icon: {
                    Image(systemName: "questionmark.circle.fill")
                }
                .foregroundStyle(.orange)
                .padding(.vertical, 2)
            }

            WrapLayout(spacing: 6) {
                ForEach(allScenarios) { scenario in
                    scenarioChip(scenario)
                }
            }
            .padding(.vertical, 2)
        } header: {
            HStack {
                Text("Where you might hear it")
                if scenarioPromptActive {
                    Spacer()
                    Text("Required")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        } footer: {
            if aiCouldNotCategorize && selectedScenarios.isEmpty {
                Label("Tap one or more places you'd hear this phrase.", systemImage: "hand.tap.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if needsScenarioHint && selectedScenarios.isEmpty {
                Label("Pick at least one place you'd hear this phrase — it's required before you can save.", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text(selectedScenarios.isEmpty
                     ? "Pick at least one scenario this phrase belongs to."
                     : "Active in \(selectedScenarios.count) scenario\(selectedScenarios.count == 1 ? "" : "s").")
                .font(.caption2)
            }
        }
    }

    /// Whether either "pick a scenario" nudge is currently showing.
    private var scenarioPromptActive: Bool {
        (needsScenarioHint || aiCouldNotCategorize) && selectedScenarios.isEmpty
    }

    private var activeSection: some View {
        Section {
            Toggle("Active — quiz me on this", isOn: $isActive)
        } footer: {
            Text("When active, this phrase is in rotation and the AI may weave it into matching scenario chats.")
                .font(.caption2)
        }
    }

    // MARK: Pieces

    private func statusBadge(_ fixed: Bool) -> some View {
        let text = fixed ? "Cleaned up" : "Looks good"
        let color: Color = fixed ? .orange : .green
        let icon = fixed ? "pencil.and.outline" : "checkmark.circle.fill"
        return Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func scenarioChip(_ scenario: ConversationScenario) -> some View {
        let on = selectedScenarios.contains(scenario)
        return Button {
            if on { selectedScenarios.remove(scenario) } else { selectedScenarios.insert(scenario) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scenario.systemImage).font(.caption2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(scenario.germanTitle).font(.caption)
                    Text(scenario.englishTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(on ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
            .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .overlay(Capsule().strokeBorder(on ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    /// Reset the check result and any "pick a scenario" nudges when the input changes.
    private func clearCheck() {
        checkResult = nil
        checkError = nil
        needsScenarioHint = false
        aiCouldNotCategorize = false
    }

    /// If a model is already loaded in memory (e.g. the one loaded on the Home screen), adopt it as
    /// the chat model so the picker reflects it as "Ready" and the phrase check reuses it instead of
    /// triggering a redundant reload. No-op when nothing is loaded or it already matches.
    private func adoptLoadedModel() {
        guard let loaded = mlxService.loadedModel, modelManager.selectedChatModel != loaded else { return }
        modelManager.selectedChatModel = loaded
    }

    private func ensureModelLoaded() async -> Bool {
        let model = modelManager.selectedChatModel
        if mlxService.isModelLoaded, mlxService.currentModel == model { return true }
        await mlxService.loadModel(model)
        return mlxService.isModelLoaded && mlxService.currentModel == model
    }

    private func runCheck() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputFocused = false
        checking = true
        checkError = nil
        checkResult = nil
        needsScenarioHint = false
        aiCouldNotCategorize = false
        Task {
            guard await ensureModelLoaded() else {
                checkError = mlxService.loadError ?? "Couldn't load the model. Try again."
                checking = false
                return
            }
            let model = modelManager.selectedChatModel
            do {
                let raw = try await mlxService.generateText(
                    system: ConversationPrompts.phraseCheckSystemPrompt(
                        inputIsGerman: inputIsGerman,
                        suggestScenarios: autoScenario,
                        suggestGrammar: autoGrammar
                    ),
                    user: ConversationPrompts.phraseCheckUserPrompt(text),
                    model: model,
                    maxTokens: (autoScenario || autoGrammar) ? 256 : 160
                )
                if let result = ConversationPrompts.parsePhraseCheck(raw) {
                    checkResult = result
                    checkedModelRaw = model.rawValue
                    applyAISuggestions(result)
                } else {
                    checkError = "Couldn't read a clear answer. Try rephrasing the phrase."
                }
            } catch {
                checkError = "The check failed. Make sure the model is loaded and try again."
            }
            checking = false
        }
    }

    /// Fold the AI's scenario/grammar suggestions into the pickers when the matching toggle is on.
    /// Scenarios only overwrite when the AI returned at least one (we never want to clear the
    /// required selection); the anchor scenario, if any, is always kept. Grammar mirrors the AI's
    /// answer exactly — an empty result is a valid "no notable structure".
    private func applyAISuggestions(_ result: ConversationPrompts.PhraseCheckResult) {
        if autoScenario {
            if !result.scenarios.isEmpty {
                var picked = Set(result.scenarios)
                if let anchorScenario { picked.insert(anchorScenario) }
                selectedScenarios = picked
            } else if selectedScenarios.isEmpty {
                // The user asked the AI to categorize but it couldn't — make that obvious and send
                // them down to pick a category by hand.
                aiCouldNotCategorize = true
                scrollTarget = Self.scenarioAnchorID
            }
        }
        if autoGrammar {
            selectedFocus = Set(result.focusAreas)
        }
    }

    /// Save, or — when no scenario is picked — nudge the user to the scenario section instead of
    /// silently failing. The Save button stays enabled so this guidance can fire.
    private func attemptSave() {
        guard checkResult != nil else { return }
        if selectedScenarios.isEmpty {
            inputFocused = false
            withAnimation { needsScenarioHint = true }
            scrollTarget = Self.scenarioAnchorID
            return
        }
        save()
    }

    private func save() {
        guard let result = checkResult else { return }
        let scenarios = Array(selectedScenarios)
        let focus = Array(selectedFocus)

        if let phrase {
            phrase.german = result.german
            phrase.english = result.english
            phrase.scenarioTagsRaw = scenarios.map(\.rawValue)
            phrase.focusAreasRaw = focus.map(\.rawValue)
            phrase.isActive = isActive
            phrase.note = result.note
            if let checkedModelRaw { phrase.creatorModelRaw = checkedModelRaw }
        } else {
            let new = LearnedPhrase(
                german: result.german,
                english: result.english,
                scenarios: scenarios,
                focusAreas: focus,
                creatorModelRaw: checkedModelRaw ?? "",
                isActive: isActive,
                note: result.note
            )
            modelContext.insert(new)
        }
        try? modelContext.save()
        dismiss()
    }
}
