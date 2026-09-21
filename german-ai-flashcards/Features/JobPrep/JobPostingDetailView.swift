//
//  JobPostingDetailView.swift
//  german-ai-flashcards
//
//  One job posting, read the way a tutor reads it with you: word by word, translating what you
//  don't know. Three surfaces show the same posting (the text, the saved PDF, the live page); a
//  double tap on any of them opens the same inspector, every lookup is kept with the posting, and
//  saved words build the posting's own flashcard deck. From here the learner can also rehearse an
//  interview for this posting.
//

import SwiftUI
import SwiftData

struct JobPostingDetailView: View {
    @Bindable var posting: JobPosting
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var appTheme
    @Environment(ActivityRouter.self) private var router

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]
    // See `ChatConversation.interviewModeRaw` for the literal.
    @Query(filter: #Predicate<ChatConversation> { $0.modeRaw == "Interview" },
           sort: \ChatConversation.updatedAt, order: .reverse)
    private var interviews: [ChatConversation]

    @State private var inspector: WordInspectorModel?
    @State private var phraseDraft: PhraseDraft?
    @State private var showHelp = false
    @State private var surface: JobReadingSurfaceKind = .text
    /// The words and deck sections, as a sheet over the full-screen surfaces.
    @State private var showWords = false
    @State private var showInterviewSetup = false
    @State private var activeChat: ActiveChat?
    /// The live page, created the first time that surface is chosen and torn down with the screen.
    @State private var webModel: JobReadingWebModel?
    /// Briefly the count after "Add all to deck", to confirm.
    @State private var addedCount: Int?
    /// Set when the web surface had to drop the tutor to make room for the page.
    @State private var memoryNote: String?

    // Time on posting: runs while the screen is up and the app is in the foreground.
    @State private var readingTimer = StoryReadingTimer()
    @State private var wordsSaved = 0

    /// Clearance for the floating tab bar under a pushed screen (`contentMargins` does the same
    /// for the lists).
    private static let bottomClearance: CGFloat = 96

    /// The tutor the lookups run on: the one that answered earlier lookups here, else the
    /// learner's story tutor, else whatever is on disk. Never starts a download for one word.
    private var postingModel: MLXModel {
        StoryStudyService.followUpModel(wrote: posting.model, fallback: modelManager.selectedStoryModel)
    }

    /// The live page shares memory with the tutor, so lookups there run on the lightest tutor on
    /// the device instead of the best one.
    private var webModelChoice: MLXModel {
        StoryStudyService.runnableModels.filter(\.isDownloaded).min { $0.minimumRAMGB < $1.minimumRAMGB } ?? postingModel
    }

    private func lookupModel(for kind: JobReadingSurfaceKind) -> MLXModel {
        kind == .web ? webModelChoice : postingModel
    }

    private var theme: ModelTheme { postingModel.theme }
    private var accent: Color { appTheme.accent(model: theme) }

    var body: some View {
        Group {
            if surface == .text {
                textLayout
            } else {
                immersiveLayout
            }
        }
        .tint(accent)
        .navigationTitle(posting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let pageURL = posting.pageURL {
                    Link(destination: pageURL) {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open the posting in Safari")
                }
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showHelp) {
            GestureHelpSheet(
                intro: "Two quick gestures help you learn while you read a job ad.",
                accent: theme.accent
            )
        }
        .sheet(isPresented: Binding(
            get: { inspector?.inspectedWord != nil },
            set: { if !$0 { inspector?.dismissInspector() } }
        )) {
            if let inspector {
                WordInspectorSheet(
                    source: inspector,
                    footer: "Saved words go into a flashcard deck for this posting. Find it here, under Job prep, or in Library ▸ Decks."
                )
            }
        }
        .sheet(item: $phraseDraft) { draft in
            AddEditPhraseSheet(
                modelManager: modelManager,
                mlxService: mlxService,
                anchorScenario: .jobInterview,
                phrase: nil,
                initialGerman: draft.german
            )
        }
        .sheet(isPresented: $showWords) {
            NavigationStack {
                List {
                    lookupSection
                    deckSection
                    interviewSection
                }
                .themedListScreen()
                .navigationTitle("Wörter & Deck")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showWords = false }
                    }
                }
            }
            .tint(accent)
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showInterviewSetup) {
            ConversationSetupView(
                modelManager: modelManager,
                mlxService: mlxService,
                onResume: { convo in
                    showInterviewSetup = false
                    resume(convo)
                },
                onStart: { config in
                    showInterviewSetup = false
                    startNewChat(with: config)
                },
                fixedMode: .interview,
                initialCapture: captureForInterview,
                initialSnapshotFile: posting.snapshotFile,
                jobPostingID: posting.id
            )
        }
        .fullScreenCover(item: $activeChat) { chat in
            ConversationView(
                conversation: chat.conversation,
                config: chat.config,
                modelManager: modelManager,
                mlxService: mlxService
            )
        }
        .onAppear {
            setUp()
            readingTimer.start()
            posting.lastOpenedAt = .now
        }
        .onDisappear {
            flushReading()
            webModel?.tearDown()
            webModel = nil
            // A lookup still waiting on a model load has no one to report to now.
            inspector?.tearDown()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { readingTimer.start() } else { flushReading() }
        }
        .onChange(of: surface) { _, newValue in
            switchSurface(to: newValue)
        }
    }

    // MARK: - Layouts

    private var textLayout: some View {
        List {
            headerSection.themedListRow()
            if posting.availableSurfaces.count > 1 {
                surfaceSection
            }
            readSection.themedListRow()
            lookupSection
            deckSection
            interviewSection
        }
        .themedListScreen()
        .contentMargins(.bottom, 120, for: .scrollContent)
    }

    /// The PDF and the live page want the whole screen; the words and the deck move into a sheet
    /// reached from the bar at the bottom.
    private var immersiveLayout: some View {
        VStack(spacing: 0) {
            surfacePicker
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            if let memoryNote {
                Text(memoryNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            surfaceView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .themedScreen()
        .safeAreaInset(edge: .bottom) {
            immersiveBar
                .padding(.bottom, Self.bottomClearance)
        }
    }

    @ViewBuilder
    private var surfaceView: some View {
        switch surface {
        case .text:
            ScrollView {
                JobPostingTextSurface(text: posting.text, decorations: decorations, callbacks: callbacks)
                    .padding(.horizontal, 16)
            }
        case .pdf:
            if let file = posting.snapshotFile, JobPostingSnapshotStore.exists(file) {
                JobPostingPDFSurface(
                    url: JobPostingSnapshotStore.url(for: file),
                    decorations: decorations,
                    callbacks: callbacks,
                    accent: accent
                )
            } else {
                ContentUnavailableView("No saved copy", systemImage: "doc.richtext",
                                       description: Text("This posting has no PDF copy."))
            }
        case .web:
            if let webModel, let url = posting.sourceURL {
                JobPostingWebSurface(model: webModel, url: url, decorations: decorations, accent: accent)
            } else {
                ContentUnavailableView("No link", systemImage: "safari",
                                       description: Text("This posting has no page to load."))
            }
        }
    }

    private var immersiveBar: some View {
        HStack(spacing: 12) {
            Button {
                showWords = true
            } label: {
                Label("\(posting.lookups.count) unbekannte Wörter", systemImage: "character.book.closed")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if let deck = JobDeckStore.deck(for: posting, context: modelContext) {
                Button {
                    studyDeck(deck)
                } label: {
                    Label("Deck (\(deck.cards.count))", systemImage: "rectangle.stack.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer()
            Label(StoryProgressService.formatClock(posting.readingSeconds + readingTimer.seconds), systemImage: "timer")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(posting.sourceKind.label, systemImage: posting.sourceKind.systemImage)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: appTheme.pillShape)
                    Spacer()
                    postingModel.logoImage
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
                }
                if !posting.detailLine.isEmpty {
                    Text(posting.detailLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Label("\(posting.wordCount) Wörter", systemImage: "text.alignleft")
                    Label(StoryProgressService.formatClock(posting.readingSeconds + readingTimer.seconds), systemImage: "timer")
                        .monospacedDigit()
                        .accessibilityLabel("Time spent with this posting")
                    if let file = posting.snapshotFile, JobPostingSnapshotStore.exists(file) {
                        ShareLink(item: JobPostingSnapshotStore.url(for: file)) {
                            Label("PDF", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private var surfaceSection: some View {
        Section {
            surfacePicker
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        } footer: {
            Text(surface.blurb)
        }
    }

    private var surfacePicker: some View {
        Picker("Surface", selection: $surface) {
            ForEach(posting.availableSurfaces) { kind in
                Label(kind.rawValue, systemImage: kind.systemImage).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    private var readSection: some View {
        Section {
            JobPostingTextSurface(text: posting.text, decorations: decorations, callbacks: callbacks)
        } header: {
            Text("Stellenanzeige").themedSectionHeader()
        } footer: {
            Text("Double-tap a word to translate it; select a phrase to translate or save it. Words you've saved are washed in color, words you looked up get a red dashed line.")
        }
    }

    /// The words this learner double-tapped in this posting, kept with it.
    @ViewBuilder
    private var lookupSection: some View {
        let entries = posting.lookups
        Section {
            if entries.isEmpty {
                Text("Nothing looked up yet. Double-tap a word in the posting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Text(entry.german)
                            .fontWeight(.medium)
                        Spacer()
                        Text(entry.english)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                        Button {
                            SpeechService.shared.speak(entry.german)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                }
                .onDelete(perform: removeLookups)

                let unsaved = entries.filter { !savedWords.contains(JobDeckStoreKey.key($0.german)) }.count
                Button {
                    addAllToDeck()
                } label: {
                    Label(
                        addedCount.map { "Added \($0) to the deck" }
                            ?? (unsaved == 0 ? "All in the deck" : "Add all \(unsaved) to the deck"),
                        systemImage: addedCount != nil ? "checkmark.circle.fill" : "rectangle.stack.badge.plus"
                    )
                }
                .disabled(unsaved == 0 || addedCount != nil)
            }
        } header: {
            Text("Unbekannte Wörter").themedSectionHeader()
        } footer: {
            if !entries.isEmpty {
                Text("Words and phrases you looked up here. Double-tapping one again answers straight from this list, with no wait. Swipe to remove.")
            }
        }
        .themedListRow()
    }

    @ViewBuilder
    private var deckSection: some View {
        let deck = JobDeckStore.deck(for: posting, context: modelContext)
        Section {
            if let deck, !deck.cards.isEmpty {
                Button {
                    studyDeck(deck)
                } label: {
                    Label("Study \(deck.cards.count) cards", systemImage: "rectangle.stack.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                }
                .listRowBackground(theme.linear)
            } else {
                Text("Words you save while reading become a flashcard deck for this posting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Flashcards").themedSectionHeader()
        }
        .themedListRow()
    }

    /// Interviews rehearsed for this posting: linked by id, or by the same link for chats from
    /// before the link existed.
    @ViewBuilder
    private var interviewSection: some View {
        let related = interviews.filter {
            $0.jobPostingID == posting.id || (posting.pageURL != nil && JobURL.same($0.jobURL, posting.sourceURL))
        }
        Section {
            Button {
                showInterviewSetup = true
            } label: {
                Label("Practice an interview for this posting", systemImage: "briefcase.fill")
            }
            ForEach(related) { convo in
                Button {
                    resume(convo)
                } label: {
                    ConversationRow(conversation: convo)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Interview").themedSectionHeader()
        } footer: {
            Text(related.isEmpty
                 ? "The recruiter reads this posting; the chat is in German."
                 : "Tap an earlier interview to pick it up again.")
        }
        .themedListRow()
    }

    // MARK: - Reading toolkit

    private var callbacks: JobReadingCallbacks {
        JobReadingCallbacks(
            onTapWord: { inspect($0) },
            onTranslateSelection: { inspect($0) },
            onSavePhrase: { phraseDraft = PhraseDraft(german: $0) }
        )
    }

    private var decorations: JobReadingDecorations {
        JobReadingDecorations(
            savedWords: savedWords,
            lookedUpWords: Set(posting.lookups.map { $0.german.lowercased() })
        )
    }

    /// Lowercased German words already saved to this posting's deck.
    private var savedWords: Set<String> {
        JobDeckStore.savedWords(for: posting, context: modelContext)
    }

    private func inspect(_ word: String) {
        inspector?.inspect(word)
    }

    private func setUp() {
        if inspector == nil {
            inspector = makeInspector(for: surface)
        } else {
            inspector?.knownTranslations = JobWordInspector.knownTranslations(for: posting)
        }
    }

    private func makeInspector(for kind: JobReadingSurfaceKind) -> WordInspectorModel {
        JobWordInspector.make(
            posting: posting,
            mlxService: mlxService,
            model: lookupModel(for: kind),
            feedsCoach: modelManager.storyFeedsCoach,
            onSaved: { wordsSaved += 1 },
            context: modelContext
        )
    }

    private func switchSurface(to kind: JobReadingSurfaceKind) {
        memoryNote = nil
        // The inspector's tutor may change with the surface; the answers so far carry over.
        let known = inspector?.knownTranslations ?? [:]
        inspector = makeInspector(for: kind)
        inspector?.knownTranslations.merge(known) { current, _ in current }

        if kind == .web {
            if webModel == nil { webModel = makeWebModel() }
            // WebKit's content process is the first thing iOS reclaims when memory is tight, and
            // a loaded tutor is most of this app's footprint. Under pressure, drop the tutor now;
            // the first lookup reloads it (the inspector says so while it does).
            if MemoryPressureMonitor.shared.level > .normal, mlxService.isModelLoaded {
                mlxService.unloadModel()
                MemorySaver.releaseCaches()
                memoryNote = "Memory is tight: the tutor was unloaded to make room for the page and reloads on the first lookup."
            }
        } else {
            webModel?.tearDown()
            webModel = nil
        }
    }

    private func makeWebModel() -> JobReadingWebModel {
        let model = JobReadingWebModel()
        model.onWordTap = { inspect($0) }
        model.onTranslateSelection = { inspect($0) }
        model.onSavePhrase = { phraseDraft = PhraseDraft(german: $0) }
        return model
    }

    private func removeLookups(at offsets: IndexSet) {
        var entries = posting.lookups
        entries.remove(atOffsets: offsets)
        posting.setLookups(entries)
        try? modelContext.save()
        inspector?.knownTranslations = JobWordInspector.knownTranslations(for: posting)
    }

    private func addAllToDeck() {
        let added = JobDeckStore.saveAllLookups(for: posting, feedsCoach: modelManager.storyFeedsCoach, context: modelContext)
        wordsSaved += added
        addedCount = added
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            addedCount = nil
        }
    }

    private func studyDeck(_ deck: SavedDeck) {
        router.launch(.cardDeck(DeckStore(modelContext: modelContext).session(for: deck, style: modelManager.flashcardStyle)))
    }

    /// Close the current stretch of reading and add it to the posting.
    private func flushReading() {
        let seconds = readingTimer.take()
        guard seconds > 0 else { return }
        posting.readingSeconds += seconds
        try? modelContext.save()
    }

    // MARK: - Interview

    /// The posting as the setup screen expects a captured one, so "Practice an interview" starts
    /// with everything filled in. The chat caps the text to the tutor's window on Start.
    private var captureForInterview: JobPostingCapture {
        JobPostingCapture(
            title: posting.title,
            text: posting.text,
            company: posting.company ?? "",
            location: posting.location ?? "",
            url: posting.sourceURL ?? ""
        )
    }

    private func startNewChat(with config: ConversationConfig) {
        let convo = ChatConversation(config: config)
        modelContext.insert(convo)
        try? modelContext.save()
        DispatchQueue.main.async {
            activeChat = ActiveChat(conversation: convo, config: config)
        }
    }

    private func resume(_ convo: ChatConversation) {
        DispatchQueue.main.async {
            activeChat = ActiveChat(conversation: convo, config: convo.makeConfig(modelManager: modelManager, decks: decks))
        }
    }
}

/// How a lookup entry is matched against the deck: article stripped, lowercased, the same key
/// `JobDeckStore` stores cards under.
private enum JobDeckStoreKey {
    static func key(_ german: String) -> String {
        var word = german.trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["der ", "die ", "das "] where word.lowercased().hasPrefix(article) {
            word = String(word.dropFirst(article.count)).trimmingCharacters(in: .whitespaces)
        }
        return word.lowercased()
    }
}

// MARK: - Preview

@MainActor
private func jobPostingDetailPreview() -> some View {
    let posting = JobPosting(
        title: "Werkstudent:in Softwareentwicklung (m/w/d)",
        text: "Deine Aufgaben\nDu entwickelst gemeinsam mit dem Team neue Funktionen für unsere Plattform und übernimmst eigenverantwortlich kleinere Projekte.\n\nDein Profil\nDu studierst Informatik oder ein vergleichbares Fach und bringst erste Erfahrung mit Swift mit. Zuverlässigkeit und Teamfähigkeit zeichnen dich aus.",
        sourceKind: .paste
    )
    posting.company = "Beispiel GmbH"
    posting.location = "Berlin"
    posting.setLookups([
        GlossaryEntry(german: "eigenverantwortlich", english: "on one's own responsibility"),
        GlossaryEntry(german: "Zuverlässigkeit", english: "reliability")
    ])
    return ForEach(AppTheme.allCases) { theme in
        NavigationStack {
            JobPostingDetailView(
                posting: posting,
                modelManager: MLXModelManager(),
                mlxService: MLXGenerationService()
            )
        }
        .environment(ActivityRouter())
        .environment(\.appTheme, theme)
        .modelContainer(for: [JobPosting.self, SavedDeck.self, SavedCard.self, ChatConversation.self], inMemory: true)
    }
}

#Preview("Job posting · 4 themes") { jobPostingDetailPreview() }
