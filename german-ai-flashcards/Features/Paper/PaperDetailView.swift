import SwiftUI
import SwiftData

/// Shows a paper's generated study materials and lets the learner discuss it with the AI.
struct PaperDetailView: View {
    let paper: StudyPaper
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Query private var allDecks: [SavedDeck]
    @Environment(\.modelContext) private var modelContext
    @Environment(ActivityRouter.self) private var router
    @Environment(\.appTheme) private var appTheme

    @State private var activeChat: ActiveChat?
    @State private var regenService: PaperStudyService?
    @State private var regenerating = false

    // On-demand flashcards: the deck is built the first time the learner picks "Make flashcards".
    @State private var deckReview: DeckReview?
    @State private var deckGenService: PaperStudyService?
    @State private var deckGenerating = false
    /// "Both": remember to offer the discussion after the flashcards session ends.
    @State private var pendingBothChat = false
    /// The `.cardDeck` activity id we launched for a "Both" flow, so we can detect its dismissal.
    @State private var launchedCardActivityID: String?
    @State private var showDiscussPrompt = false

    private var deck: SavedDeck? {
        guard let id = paper.deckID else { return nil }
        return allDecks.first { $0.id == id }
    }

    /// Brand theme of the model that generated this paper (or the current study model).
    private var theme: ModelTheme { (paper.model ?? modelManager.selectedPaperModel).theme }

    private var sourceLabel: String {
        switch paper.sourceKind {
        case .photo: "From a photo"
        case .link: "From a link"
        case .document: "From a document"
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: paper.sourceSymbol)
                        .foregroundStyle(theme.accent)
                    Text(sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let model = paper.model {
                        model.logoImage
                            .resizable().scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(4)))
                        Text(model.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(theme.accent.opacity(0.06))

            whatNextSection.themedListRow()

            Section {
                NavigationLink {
                    SourceTextView(paper: paper)
                } label: {
                    Label("View extracted text", systemImage: "doc.plaintext")
                }
                if let urlString = paper.sourceURL,
                   urlString.hasPrefix("http"),
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("Open original link", systemImage: "safari")
                    }
                }
            } footer: {
                Text("\(paper.wordCount) words extracted. Check it looks right — a little English mixed in is fine.")
                    .font(.caption2)
            }
            .themedListRow()

            if let summary = paper.germanSummary, !summary.isEmpty {
                Section {
                    Text(summary).font(.callout)
                } header: {
                    Text("Zusammenfassung").themedSectionHeader()
                }
                .themedListRow()
            }

            if !paper.keyPoints.isEmpty {
                Section {
                    ForEach(Array(paper.keyPoints.enumerated()), id: \.offset) { _, point in
                        Label(point, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle())
                            .font(.callout)
                    }
                } header: {
                    Text("Kernpunkte").themedSectionHeader()
                }
                .themedListRow()
            }

            if !paper.questions.isEmpty {
                Section {
                    ForEach(paper.questions) { question in
                        DisclosureGroup {
                            if let answer = question.answer {
                                Text(answer).font(.callout).foregroundStyle(.secondary)
                            } else {
                                Text("Try answering out loud, then discuss it with the AI.")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        } label: {
                            Text(question.question).font(.callout)
                        }
                    }
                } header: {
                    Text("Fragen zum Üben").themedSectionHeader()
                }
                .themedListRow()
            }

            if !paper.generationComplete {
                Section {
                    if regenerating, let regenService {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: regenService.progress)
                            Text(regenService.statusText).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            regenerate()
                        } label: {
                            Label("Finish generating study materials", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle(paper.title)
        .tint(theme.accent)
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .fullScreenCover(item: $activeChat) { chat in
            ConversationView(
                conversation: chat.conversation,
                config: chat.config,
                modelManager: modelManager,
                mlxService: mlxService
            )
        }
        // "Make flashcards" on a paper with no deck yet: pick size / hand-pick words, then build it.
        .sheet(item: $deckReview) { review in
            ExtractedTextReviewView(
                title: "Make flashcards",
                text: review.text,
                accent: theme.accent,
                collectDeckOptions: true,
                confirmTitle: "Make flashcards"
            ) { deckCount, selectedWords in
                // Defer so the review sheet finishes dismissing before the progress sheet appears.
                DispatchQueue.main.async {
                    generateDeckThenLaunch(deckCount: deckCount, selectedWords: selectedWords)
                }
            }
        }
        .sheet(isPresented: $deckGenerating) {
            if let deckGenService {
                DeckGeneratingView(service: deckGenService, paper: paper) {
                    deckGenerating = false
                }
            }
        }
        // "Both": once the flashcards session we launched is dismissed, offer to discuss the paper.
        .onChange(of: router.active?.id) { oldID, newID in
            guard newID == nil, let launched = launchedCardActivityID, oldID == launched else { return }
            launchedCardActivityID = nil
            // Defer so the flashcard cover is fully gone before we prompt.
            DispatchQueue.main.async { showDiscussPrompt = true }
        }
        .confirmationDialog(
            "Ready to use those words?",
            isPresented: $showDiscussPrompt,
            titleVisibility: .visible
        ) {
            Button("Discuss this paper") { startChat() }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Nice work. Talk about the paper with the AI to put the new vocabulary to use.")
        }
    }

    // MARK: - What next? chooser

    @ViewBuilder
    private var whatNextSection: some View {
        Section {
            Button {
                startFlashcards(thenDiscuss: false)
            } label: {
                chooserRow(
                    "Make flashcards",
                    deck != nil ? "\(deck?.cards.count ?? 0) cards ready to study" : "Build a vocab deck from this text",
                    "rectangle.stack.fill"
                )
            }
            Button {
                startChat()
            } label: {
                chooserRow("Discuss this paper", "Chat with the AI examiner in German", "bubble.left.and.bubble.right.fill")
            }
            Button {
                startFlashcards(thenDiscuss: true)
            } label: {
                chooserRow("Both: cards, then chat", "Study the words, then use them in conversation", "square.stack.3d.up.fill")
            }
        } header: {
            Text("What next?").themedSectionHeader()
        } footer: {
            Text("Turn this text into vocabulary flashcards, discuss it with the AI, or do both.")
                .font(.caption2)
        }
    }

    private func chooserRow(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(theme.accent)
        }
    }

    // MARK: - Actions

    private func startChat() {
        var config = ConversationConfig(model: paper.model ?? modelManager.selectedPaperModel)
        config.learnerName = ConversationConfig.learnerName(from: modelManager.learnerName)
        config.mode = .paper
        config.paperTitle = paper.title
        config.paperContext = paper.conversationContext
        config.level = modelManager.germanLevel
        config.formality = .sie  // an examiner addresses you formally
        config.correctionsEnabled = modelManager.chatCorrectionsEnabled
        config.correctionTranslationEnabled = modelManager.chatShowCorrectionTranslation
        config.strictness = CorrectionStrictness(rawValue: modelManager.chatStrictnessRaw) ?? .balanced
        config.feedbackStyle = FeedbackStyle(rawValue: modelManager.chatFeedbackStyleRaw) ?? .tellMe
        config.autoPlay = modelManager.autoPlayReplies
        config.inputMode = modelManager.chatInputMode
        config.eagerAssist = modelManager.chatEagerAssist
        config.autoShowTranslation = modelManager.chatAutoShowTranslation
        config.hintCount = modelManager.chatHintCount
        config.autoHints = modelManager.chatAutoHints
        config.genderColors = modelManager.chatGenderColors

        let convo = ChatConversation(config: config)
        modelContext.insert(convo)
        try? modelContext.save()
        activeChat = ActiveChat(conversation: convo, config: config)
    }

    private func regenerate() {
        let svc = PaperStudyService(mlxService: mlxService, modelContext: modelContext)
        regenService = svc
        regenerating = true
        Task {
            await svc.generate(for: paper, model: paper.model ?? modelManager.selectedPaperModel, questionCount: 6)
            regenerating = false
        }
    }

    // MARK: - Flashcards (on-demand)

    /// Study the paper as flashcards. Launches immediately if the deck already exists; otherwise
    /// asks for deck options and builds it first. `thenDiscuss` chains the discussion afterward.
    private func startFlashcards(thenDiscuss: Bool) {
        if let deck, !deck.cards.isEmpty {
            launchFlashcards(deck: deck, thenDiscuss: thenDiscuss)
        } else {
            pendingBothChat = thenDiscuss
            deckReview = DeckReview(text: paper.fullText)
        }
    }

    /// Assemble a study session from the deck and present the flashcard player through the shared
    /// `ActivityRouter` (same launch path as the Library and matching game).
    private func launchFlashcards(deck: SavedDeck, thenDiscuss: Bool) {
        let session = DeckStore(modelContext: modelContext).session(for: deck, style: modelManager.flashcardStyle)
        let activity = Activity.cardDeck(session)
        launchedCardActivityID = thenDiscuss ? activity.id : nil
        router.launch(activity)
    }

    /// Build the deck on demand (shown behind a progress sheet), then launch the flashcards.
    private func generateDeckThenLaunch(deckCount: Int, selectedWords: [String]?) {
        let svc = PaperStudyService(mlxService: mlxService, modelContext: modelContext)
        deckGenService = svc
        deckGenerating = true
        let model = paper.model ?? modelManager.selectedPaperModel
        let chainChat = pendingBothChat
        Task {
            await svc.generateDeck(for: paper, model: model, deckCount: deckCount, selectedWords: selectedWords)
            if case .done = svc.phase, let newDeck = svc.generatedDeck {
                deckGenerating = false
                // Defer so the progress sheet is fully gone before the router cover appears.
                DispatchQueue.main.async { launchFlashcards(deck: newDeck, thenDiscuss: chainChat) }
            }
            // On failure the progress sheet stays up showing the error until the user dismisses it.
        }
    }
}

/// Text handed to the on-demand deck picker (`ExtractedTextReviewView`) when building flashcards.
private struct DeckReview: Identifiable {
    let id = UUID()
    let text: String
}

/// Progress sheet shown while the vocab deck is built on demand from the "Make flashcards" chooser.
/// Mirrors `PaperListView`'s import progress view, scoped to the deck-only step.
private struct DeckGeneratingView: View {
    let service: PaperStudyService
    let paper: StudyPaper
    let onClose: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch service.phase {
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                    Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
                case .done:
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                    Text("Deck ready.").multilineTextAlignment(.center)
                default:
                    ProgressView(value: service.progress)
                        .progressViewStyle(.linear)
                        .tint(service.model.theme.accent)
                        .frame(maxWidth: 260)
                    Text(service.statusText).foregroundStyle(.secondary)
                    if service.phase == .loadingModel {
                        Text("First-time use downloads \(service.model.rawValue).")
                            .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .navigationTitle("Making flashcards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(service.isRunning ? "Hide" : "Done") { onClose() }
                }
            }
            .interactiveDismissDisabled(service.isRunning)
        }
    }
}

/// Read-only viewer for the raw text extracted from the PDF/URL.
private struct SourceTextView: View {
    let paper: StudyPaper

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        ScrollView {
            Text(paper.fullText.isEmpty ? "No text was extracted." : paper.fullText)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background {
            if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
        }
        .navigationTitle("Extracted text")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.tint)
            configuration.title
        }
    }
}
