import SwiftUI
import SwiftData

/// Shows a paper's generated study materials and lets the learner discuss it with the AI.
struct PaperDetailView: View {
    let paper: StudyPaper
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Query private var allDecks: [SavedDeck]
    @Environment(\.modelContext) private var modelContext

    @State private var activeChat: ActiveChat?
    @State private var regenService: PaperStudyService?
    @State private var regenerating = false

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
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(model.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(theme.accent.opacity(0.06))

            Section {
                Button {
                    startChat()
                } label: {
                    Label("Discuss this paper with the AI", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.body.weight(.semibold))
                }
            } footer: {
                Text("The AI acts as an examiner using this paper as its reference, and quizzes you in German — with all the usual voice-chat tools.")
                    .font(.caption2)
            }

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

            if let summary = paper.germanSummary, !summary.isEmpty {
                Section("Zusammenfassung") {
                    Text(summary).font(.callout)
                }
            }

            if !paper.keyPoints.isEmpty {
                Section("Kernpunkte") {
                    ForEach(Array(paper.keyPoints.enumerated()), id: \.offset) { _, point in
                        Label(point, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle())
                            .font(.callout)
                    }
                }
            }

            if let deck {
                Section("Vocabulary deck") {
                    HStack {
                        Label("\(deck.cards.count) cards", systemImage: "rectangle.stack.fill")
                        Spacer()
                        Text("In your Library").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !paper.questions.isEmpty {
                Section("Fragen zum Üben") {
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
                }
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
            }
        }
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
    }

    // MARK: - Actions

    private func startChat() {
        var config = ConversationConfig(model: paper.model ?? modelManager.selectedPaperModel)
        config.mode = .paper
        config.paperTitle = paper.title
        config.paperContext = paper.conversationContext
        config.level = CEFRLevel(rawValue: modelManager.chatLevelRaw) ?? .b1
        config.formality = .sie  // an examiner addresses you formally
        config.correctionsEnabled = modelManager.chatCorrectionsEnabled
        config.correctionTranslationEnabled = modelManager.chatShowCorrectionTranslation
        config.strictness = CorrectionStrictness(rawValue: modelManager.chatStrictnessRaw) ?? .balanced
        config.autoPlay = modelManager.autoPlayReplies
        config.eagerAssist = modelManager.chatEagerAssist
        config.autoShowTranslation = modelManager.chatAutoShowTranslation
        config.hintCount = modelManager.chatHintCount

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
            await svc.generate(for: paper, model: paper.model ?? modelManager.selectedPaperModel, deckCount: 15, questionCount: 6)
            regenerating = false
        }
    }
}

/// Read-only viewer for the raw text extracted from the PDF/URL.
private struct SourceTextView: View {
    let paper: StudyPaper

    var body: some View {
        ScrollView {
            Text(paper.fullText.isEmpty ? "No text was extracted." : paper.fullText)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
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
