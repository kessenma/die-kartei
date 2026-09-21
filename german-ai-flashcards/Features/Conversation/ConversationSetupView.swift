import SwiftUI
import SwiftData

/// The "Conversation Options" screen — pick mode, decks, scenario, grammar focus,
/// level, formality, and model, then start a session. Corrections, voice, and most
/// learning-aid defaults live in Settings ▸ Conversation; auto-hints is surfaced
/// here too so beginners find it when it matters.
struct ConversationSetupView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Interview mode: the learner chose to go back to an earlier chat for the same posting
    /// instead of starting a new one. The presenter closes this sheet and opens that chat.
    var onResume: ((ChatConversation) -> Void)? = nil
    var onStart: (ConversationConfig) -> Void
    /// Job prep opens this screen already in interview mode: the Type picker is hidden and the
    /// chat is an interview, full stop. Nil keeps the ordinary setup.
    var fixedMode: ConversationMode? = nil
    /// A posting the learner studied first (Job prep ▸ Study a job ad), brought in as if it had
    /// just been captured, together with its PDF copy (duplicated for the chat on Start) and the
    /// posting's id so the chat can be grouped with it.
    var initialCapture: JobPostingCapture? = nil
    var initialSnapshotFile: String? = nil
    var jobPostingID: UUID? = nil

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var allDecks: [SavedDeck]
    @Query private var allPhrases: [LearnedPhrase]
    /// Interview chats that remember their posting's link, newest first, for the "already
    /// prepared for this posting" check.
    @Query(filter: #Predicate<ChatConversation> { $0.jobURL != nil }, sort: \ChatConversation.updatedAt, order: .reverse)
    private var linkedInterviews: [ChatConversation]
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
    // Seed only; `loadDefaults()` overwrites it with the stored chat model on appear.
    @State private var model: MLXModel = .hero
    @State private var inputMode: ChatInputMode = .speak
    @State private var autoHints = false
    @State private var didLoadDefaults = false

    // Interview mode: the job posting, captured in the in-app browser or pasted in.
    @State private var jobSource: JobDescriptionSource = .link
    @State private var jobURLText = ""
    @State private var jobPastedText = ""
    @State private var jobTitleText = ""
    @State private var jobCompanyText = ""
    @State private var jobLocationText = ""
    // Remembered between sessions: most people rehearse the same kind of round several times.
    @AppStorage("interviewRoundDefault") private var interviewRoundRaw = InterviewRound.screening.rawValue
    @AppStorage("interviewFormatDefault") private var interviewFormatRaw = InterviewFormat.video.rawValue
    @State private var capturedJob: JobPostingCapture?
    /// The open browser. Owned here so nothing the cover's view does can recreate the page.
    @State private var clipper: JobPostingClipperModel?
    /// An earlier interview chat for the link the learner just entered.
    @State private var duplicate: ChatConversation?
    @State private var showDuplicate = false
    /// When the posting was reused from an earlier chat, that chat's saved copy, to duplicate.
    @State private var reusedSnapshotFile: String?
    @State private var showBudgetInfo = false
    @State private var pasteSuggestion: String?
    @FocusState private var focusedField: Field?
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelTheme) private var modelTheme

    private enum Field: Hashable { case url, pastedText, jobTitle, company, location, learnerName }

    /// Real, non-internal decks the user generated (mirrors SavedDecksView filtering).
    private var decks: [SavedDeck] {
        allDecks.filter {
            !["goethe", "goethe-srs", "past-tense", "past-tense-srs", "grammar"].contains($0.generatorRaw)
        }
    }

    private var canStart: Bool {
        if mode == .decks { return !selectedDeckIDs.isEmpty }
        if mode == .interview { return !jobDescriptionText.isEmpty }
        return true
    }

    /// The interview job description from whichever source is active.
    private var jobDescriptionText: String {
        let raw = jobSource == .link ? (capturedJob?.text ?? "") : jobPastedText
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Characters of posting the chosen tutor reads on this device; what the meters show and
    /// what `start()` injects.
    private var jobContextCap: Int { JobContextBudget.characters(for: model) }

    private var interviewRound: Binding<InterviewRound> {
        Binding(
            get: { InterviewRound(rawValue: interviewRoundRaw) ?? .screening },
            set: { interviewRoundRaw = $0.rawValue }
        )
    }

    private var interviewFormat: Binding<InterviewFormat> {
        Binding(
            get: { InterviewFormat(rawValue: interviewFormatRaw) ?? .video },
            set: { interviewFormatRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if fixedMode == nil {
                    modeSection.themedListRow()
                }

                if mode == .decks {
                    DeckMultiSelectSection(decks: decks, selectedIDs: $selectedDeckIDs)
                        .themedListRow()
                }

                if mode == .scenario {
                    scenarioSection.themedListRow()
                }

                if mode == .interview {
                    interviewSection.themedListRow()
                    interviewStyleSection.themedListRow()
                }

                GrammarFocusPickerSection(selected: $focus)
                    .themedListRow()

                levelSection.themedListRow()

                inputSection.themedListRow()

                learningAidsSection.themedListRow()

                ChatModelPickerSection(selected: $model, cacheRefreshID: UUID())
                    .themedListRow()

                // Right under the picker, so it reads as a note about the choice just made rather
                // than an advert. `model` is local state, so this appears and disappears live as
                // the picker changes — which is why it belongs on setup and not in the live chat,
                // where interrupting someone mid-conversation to sell a download would be worse
                // than saying nothing.
                if model == .appleIntelligence {
                    Section {
                        ModelUpgradeNudge(kind: .chatQuality)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(fixedMode == .interview ? "Interview practice" : "New Conversation")
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .sheet(isPresented: $showBudgetInfo) {
                JobContextInfoSheet(model: model)
            }
            .fullScreenCover(item: $clipper) { clipper in
                JobPostingClipperView(
                    model: clipper,
                    initialURL: (capturedJob?.url).flatMap { $0.isEmpty ? nil : $0 } ?? jobURLText,
                    tutor: model,
                    initialTitle: jobTitleText,
                    initialCompany: jobCompanyText,
                    initialLocation: jobLocationText,
                    accent: appTheme.accent(model: modelTheme)
                ) { capture in
                    apply(capture)
                    clipper.tearDown()
                    self.clipper = nil
                }
            }
            .confirmationDialog(
                "You already prepared for this posting",
                isPresented: $showDuplicate,
                titleVisibility: .visible,
                presenting: duplicate
            ) { existing in
                Button("Open that conversation") {
                    onResume?(existing)
                }
                Button("Reuse its posting here") {
                    reuse(existing)
                }
                Button("Start fresh in the browser") {
                    presentClipper()
                }
                Button("Cancel", role: .cancel) {}
            } message: { existing in
                Text(duplicateSummary(existing))
            }
            .onAppear(perform: loadDefaults)
            .onChange(of: mode) { _, newMode in
                // Interviews are formal by convention; the learner can still switch back.
                if newMode == .interview { formality = .sie }
            }
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
            Text("Conversation type").themedSectionHeader()
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
            Text("Scenario").themedSectionHeader()
        } footer: {
            Text("A random scenario is picked for you — tap Surprise me to reroll, or browse the full list. The AI stays in character and sets the scene. Add phrases you've heard in the wild and the AI will work them in.")
                .font(.caption2)
        }
    }

    private func activePhraseCount(for scenario: ConversationScenario) -> Int {
        allPhrases.filter { $0.isActive && $0.applies(to: scenario) }.count
    }

    private var interviewSection: some View {
        Section {
            Picker("Job description", selection: $jobSource) {
                ForEach(JobDescriptionSource.allCases) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)

            if jobSource == .link {
                if let capturedJob {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(capturedJob.title.isEmpty ? "Job posting" : capturedJob.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            let details = [capturedJob.company, capturedJob.location]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · ")
                            if !details.isEmpty {
                                Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            budgetLine(used: capturedJob.text.count)
                            if capturedJob.snapshotPDF != nil || JobPostingSnapshotStore.exists(reusedSnapshotFile) {
                                Label("Copy of the page saved with this chat", systemImage: "doc.richtext")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    if let earlier = existingInterview(for: capturedJob.url) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                            Text("You prepared for this posting on \(earlier.updatedAt.formatted(date: .abbreviated, time: .omitted)).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let onResume {
                                Button("Open") { onResume(earlier) }
                                    .buttonStyle(.borderless)
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    HStack {
                        // A posting adopted from a pasted or PDF study copy has no page to reopen.
                        if !capturedJob.url.isEmpty {
                            Button(action: presentClipper) {
                                Label("Reopen", systemImage: "safari")
                            }
                            .buttonStyle(.borderless)
                        }
                        Spacer()
                        Button("Clear", role: .destructive) {
                            self.capturedJob = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                } else {
                    HStack(spacing: 8) {
                        TextField("Link to the job posting…", text: $jobURLText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($focusedField, equals: .url)
                            .onSubmit(openClipper)
                            .onAppear {
                                if jobURLText.isEmpty { pasteSuggestion = ClipboardLink.suggestion() }
                            }
                        if !jobURLText.isEmpty {
                            Button {
                                jobURLText = ""
                                pasteSuggestion = ClipboardLink.suggestion()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Clear the link")
                        }
                    }

                    if jobURLText.isEmpty, let pasteSuggestion {
                        Button {
                            jobURLText = pasteSuggestion
                            self.pasteSuggestion = nil
                            openClipper()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.on.clipboard")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Paste copied link").font(.caption).foregroundStyle(.secondary)
                                    Text(pasteSuggestion).font(.callout).lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                    }

                    Button(action: openClipper) {
                        Label("Open posting", systemImage: "safari")
                    }
                }
            } else {
                TextField("Paste the job description here…", text: $jobPastedText, axis: .vertical)
                    .lineLimit(4...10)
                    .focused($focusedField, equals: .pastedText)
                budgetLine(used: jobPastedText.trimmingCharacters(in: .whitespacesAndNewlines).count)
            }

            TextField("Job title (used as the chat name)", text: $jobTitleText)
                .focused($focusedField, equals: .jobTitle)
            TextField("Company", text: $jobCompanyText)
                .focused($focusedField, equals: .company)
            TextField("Location", text: $jobLocationText)
                .focused($focusedField, equals: .location)
        } header: {
            Text("Job posting").themedSectionHeader()
        } footer: {
            Text("Open the posting in the built-in browser, then tap the sections that matter or highlight text on the page. Or paste the text. German or English both work; the interview itself is in German, with the AI as the recruiter.")
                .font(.caption2)
        }
    }

    /// Which round and over which channel: sets who interviews and how it opens.
    private var interviewStyleSection: some View {
        Section {
            Picker("Round", selection: interviewRound) {
                ForEach(InterviewRound.allCases) { round in
                    Text(round.label).tag(round)
                }
            }
            .pickerStyle(.segmented)
            Label(interviewRound.wrappedValue.blurb, systemImage: interviewRound.wrappedValue.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Format", selection: interviewFormat) {
                ForEach(InterviewFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }
            .pickerStyle(.segmented)
            Label(interviewFormat.wrappedValue.blurb, systemImage: interviewFormat.wrappedValue.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Interview").themedSectionHeader()
        } footer: {
            Text("Sets who interviews you and how the call opens. The technical round pulls its questions from the skills and tools named in the posting.")
                .font(.caption2)
        }
    }

    /// "1,240 / 4,500 characters" with the budget explainer a tap away.
    private func budgetLine(used: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(JobContextBudget.label(used: used, cap: jobContextCap)) characters")
                .font(.caption.monospacedDigit())
                .foregroundStyle(used > jobContextCap ? Color.orange : Color.secondary)
            Button {
                showBudgetInfo = true
            } label: {
                Image(systemName: "info.circle").font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("About the posting budget")
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

            TextField("Your name (how the AI addresses you)", text: $modelManager.learnerName)
                .textContentType(.name)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .learnerName)
        } header: {
            Text("Level & formality").themedSectionHeader()
        } footer: {
            Text("Write the name the way you want to hear it: „Kyle“, or „Herr Essenmacher“ for Sie-form chats. Saved for every conversation.")
                .font(.caption2)
        }
    }

    private var inputSection: some View {
        Section {
            Picker("Your turns", selection: $inputMode) {
                ForEach(ChatInputMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(inputMode.subtitle)
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Speak or type").themedSectionHeader()
        } footer: {
            Text("Typing is the quiet option, for a plane or an open office: replies arrive as text and nothing is spoken unless you tap play. You can switch either way mid-conversation.")
                .font(.caption2)
        }
    }

    private var learningAidsSection: some View {
        Section {
            Toggle("Hint every turn", isOn: $autoHints)
            NavigationLink {
                VoiceSettingsView(modelManager: modelManager)
            } label: {
                Label("Voice", systemImage: "waveform")
            }
        } header: {
            Text("Learning aids").themedSectionHeader()
        } footer: {
            Text("A \u{201C}you could say\u{201D} suggestion appears after every reply. Good while you're finding your feet. More aids live in Settings.")
                .font(.caption2)
        }
    }

    // MARK: - Actions

    private func loadDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        model = modelManager.selectedChatModel
        level = modelManager.germanLevel
        formality = Formality(rawValue: modelManager.chatFormalityRaw) ?? .du
        autoHints = modelManager.chatAutoHints
        inputMode = modelManager.chatInputMode
        scenario = ConversationScenario.random()
        if let fixedMode {
            mode = fixedMode
            // Set here rather than trusting `.onChange(of: mode)` to fire for a value assigned
            // during the first appearance.
            if fixedMode == .interview { formality = .sie }
        }
        if let initialCapture {
            apply(initialCapture)
            // `apply` clears the reused file; the posting's copy is what the chat duplicates.
            reusedSnapshotFile = initialSnapshotFile
        }
    }

    private func start() {
        // Persist the per-conversation choices as the new defaults. Corrections, voice, and the
        // remaining learning-aid defaults are edited directly in Settings, so they aren't written here.
        //
        // Level is deliberately *not* among them. It's the app-wide anchor (`germanLevel`, set in
        // Settings ▸ Your Level or by the placement check), and a choice made for one chat has to
        // stay with that chat — otherwise a single easier conversation quietly demotes the learner
        // everywhere, which is exactly what this screen used to do.
        modelManager.selectedChatModel = model
        modelManager.chatAutoHints = autoHints
        modelManager.chatInputMode = inputMode
        // Interviews auto-switch to "Sie" — don't let that overwrite the learner's usual default.
        if mode != .interview {
            modelManager.chatFormalityRaw = formality.rawValue
        }

        let chosenDecks = decks.filter { selectedDeckIDs.contains($0.id) }
        let deckWords = chosenDecks.flatMap { $0.cards.map(\.germanWord) }
        let deckLabel = chosenDecks.map(\.topic).joined(separator: ", ")

        var config = ConversationConfig(model: model)
        config.learnerName = ConversationConfig.learnerName(from: modelManager.learnerName)
        config.mode = mode
        config.deckIDs = chosenDecks.map(\.id)
        config.deckLabel = deckLabel
        config.deckWords = deckWords
        config.scenario = (mode == .scenario) ? scenario : nil
        config.customScenario = customScenario
        if mode == .interview {
            let title = jobTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
            config.jobTitle = title.isEmpty ? nil : String(title.prefix(ConversationConfig.jobTitleCap))
            // The posting shares the tutor's window with the conversation, so it is capped per
            // tutor and device (JobContextBudget); the setup meters showed this same number.
            config.jobContext = String(jobDescriptionText.prefix(jobContextCap))
            config.jobCompany = jobDetail(jobCompanyText)
            config.jobLocation = jobDetail(jobLocationText)
            config.jobURL = jobSource == .link ? jobDetail(capturedJob?.url ?? "", cap: 2_000) : nil
            config.interviewRound = interviewRound.wrappedValue
            config.interviewFormat = interviewFormat.wrappedValue
            config.jobSnapshotFile = jobSource == .link ? storedSnapshotFile() : nil
            config.jobPostingID = jobPostingID
        }
        config.focusAreas = GrammarFocus.allCases.filter { focus.contains($0) }
        config.level = level
        config.formality = formality
        config.correctionsEnabled = modelManager.chatCorrectionsEnabled
        config.correctionTranslationEnabled = modelManager.chatShowCorrectionTranslation
        config.strictness = CorrectionStrictness(rawValue: modelManager.chatStrictnessRaw) ?? .balanced
        config.feedbackStyle = FeedbackStyle(rawValue: modelManager.chatFeedbackStyleRaw) ?? .tellMe
        config.autoPlay = modelManager.autoPlayReplies
        config.inputMode = inputMode
        config.eagerAssist = modelManager.chatEagerAssist
        config.autoShowTranslation = modelManager.chatAutoShowTranslation
        config.hintCount = modelManager.chatHintCount
        config.autoHints = autoHints
        config.genderColors = modelManager.chatGenderColors

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

    /// Trimmed, nil when blank, capped: the shape every stored job detail takes.
    private func jobDetail(_ text: String, cap: Int = ConversationConfig.jobDetailCap) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(cap))
    }

    /// The "Open posting" path. A link the learner already interviewed for gets the choice of
    /// going back, reusing that posting, or browsing fresh; anything else opens the browser.
    private func openClipper() {
        focusedField = nil
        if capturedJob == nil, let existing = existingInterview(for: jobURLText) {
            duplicate = existing
            showDuplicate = true
            return
        }
        presentClipper()
    }

    private func presentClipper() {
        focusedField = nil
        // The browser needs no model: suggestions come from the page's own headings. A tutor left
        // loaded by an earlier chat is most of this app's footprint, and WebKit's content process
        // is the first thing iOS reclaims when memory is tight (the page reloads whenever the
        // panel uncovers it, and rendering crawls). Drop the tutor now; the interview reloads it.
        mlxService.unloadModel()
        MemorySaver.releaseCaches()
        clipper = JobPostingClipperModel()
    }

    private func existingInterview(for url: String) -> ChatConversation? {
        guard JobURL.normalized(url) != nil else { return nil }
        return linkedInterviews.first { JobURL.same($0.jobURL, url) }
    }

    /// Bring an earlier chat's posting and details over as if they had just been captured.
    private func reuse(_ existing: ChatConversation) {
        apply(JobPostingCapture(
            title: existing.jobTitle ?? existing.title,
            text: existing.jobContext ?? "",
            company: existing.jobCompany ?? "",
            location: existing.jobLocation ?? "",
            url: existing.jobURL ?? jobURLText
        ))
        reusedSnapshotFile = existing.jobSnapshotFile
    }

    /// Persist the page copy for this chat: the fresh PDF from the clipper, or a duplicate of the
    /// earlier chat's file when its posting was reused (so deleting one chat spares the other).
    private func storedSnapshotFile() -> String? {
        if let data = capturedJob?.snapshotPDF { return JobPostingSnapshotStore.save(data) }
        return JobPostingSnapshotStore.duplicate(reusedSnapshotFile)
    }

    private func duplicateSummary(_ existing: ChatConversation) -> String {
        var parts = [existing.title]
        if let company = existing.jobCompany?.trimmingCharacters(in: .whitespacesAndNewlines), !company.isEmpty {
            parts.append(company)
        }
        parts.append(existing.updatedAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    /// The clipper's details fields start from this screen's, so what comes back is the newer
    /// version of the same values and simply replaces them.
    private func apply(_ capture: JobPostingCapture) {
        capturedJob = capture
        reusedSnapshotFile = nil
        if !capture.url.isEmpty { jobURLText = capture.url }
        jobTitleText = capture.title
        jobCompanyText = capture.company
        jobLocationText = capture.location
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

/// How the learner supplies the job posting for interview mode.
private enum JobDescriptionSource: String, CaseIterable, Identifiable {
    case link
    case paste

    var id: String { rawValue }

    var label: String {
        switch self {
        case .link:  "From a link"
        case .paste: "Paste text"
        }
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
