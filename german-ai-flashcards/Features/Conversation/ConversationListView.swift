import SwiftUI
import SwiftData

/// The Conversation Practice home: start a new voice chat or resume/inspect a saved one.
struct ConversationListView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Query(sort: \ChatConversation.updatedAt, order: .reverse) private var conversations: [ChatConversation]
    @Query private var decks: [SavedDeck]
    @Environment(\.modelContext) private var modelContext

    @State private var showSetup = false
    @State private var activeChat: ActiveChat?
    @State private var summaryConversation: ChatConversation?

    var body: some View {
        List {
            Section {
                Button {
                    showSetup = true
                } label: {
                    Label("New Conversation", systemImage: "plus.bubble.fill")
                        .font(.body.weight(.medium))
                }
                NavigationLink {
                    PaperListView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label("Study a paper or link", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink {
                    PhotoScanListView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label("Scan text from a photo", systemImage: "camera.viewfinder")
                }
                NavigationLink {
                    PhraseLibraryView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label("Phrase library", systemImage: "ear.badge.waveform")
                }
            } footer: {
                Text("Have a spoken German conversation with the on-device AI. Pick a topic, deck, or scenario, choose a grammar focus, and talk — it corrects you as you go. Or upload a German paper to study and discuss.")
                    .font(.caption2)
            }

            if conversations.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "waveform.and.mic",
                        description: Text("Tap “New Conversation” to start talking.")
                    )
                }
            } else {
                Section("Saved conversations") {
                    ForEach(conversations) { convo in
                        Button {
                            activeChat = ActiveChat(conversation: convo, config: makeConfig(for: convo))
                        } label: {
                            ConversationRow(conversation: convo)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(convo)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if convo.summary != nil {
                                Button {
                                    summaryConversation = convo
                                } label: {
                                    Label("Report", systemImage: "doc.text.magnifyingglass")
                                }
                                .tint(.indigo)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Conversation Practice")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSetup = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showSetup) {
            ConversationSetupView(modelManager: modelManager, mlxService: mlxService) { config in
                showSetup = false
                startNewChat(with: config)
            }
        }
        .fullScreenCover(item: $activeChat) { chat in
            ConversationView(
                conversation: chat.conversation,
                config: chat.config,
                modelManager: modelManager,
                mlxService: mlxService
            )
        }
        .sheet(item: $summaryConversation) { convo in
            if let summary = convo.summary {
                ConversationSummaryView(
                    conversation: convo,
                    summary: summary,
                    mlxService: mlxService,
                    modelManager: modelManager,
                    onDone: { summaryConversation = nil }
                )
            }
        }
    }

    // MARK: - Actions

    private func startNewChat(with config: ConversationConfig) {
        let convo = ChatConversation(config: config)
        modelContext.insert(convo)
        try? modelContext.save()
        // Defer presentation a touch so the setup sheet finishes dismissing first.
        DispatchQueue.main.async {
            activeChat = ActiveChat(conversation: convo, config: config)
        }
    }

    private func delete(_ convo: ChatConversation) {
        modelContext.delete(convo)
        try? modelContext.save()
    }

    private func makeConfig(for convo: ChatConversation) -> ConversationConfig {
        let model = convo.model ?? modelManager.selectedChatModel
        var c = ConversationConfig(model: model)
        c.mode = convo.mode
        c.deckIDs = convo.deckIDsRaw.compactMap { UUID(uuidString: $0) }
        c.deckLabel = convo.deckLabel
        let ids = Set(c.deckIDs)
        c.deckWords = decks.filter { ids.contains($0.id) }.flatMap { $0.cards.map(\.germanWord) }
        c.scenario = convo.scenario
        c.customScenario = convo.customScenario ?? ""
        c.focusAreas = convo.focusAreas
        c.level = convo.level
        c.formality = convo.formality
        c.correctionsEnabled = convo.correctionsEnabled
        c.correctionTranslationEnabled = modelManager.chatShowCorrectionTranslation
        c.strictness = convo.strictness
        c.autoPlay = convo.autoPlay
        c.eagerAssist = modelManager.chatEagerAssist
        c.autoShowTranslation = modelManager.chatAutoShowTranslation
        c.hintCount = modelManager.chatHintCount
        c.paperTitle = convo.paperTitle
        c.paperContext = convo.paperContext
        return c
    }
}

/// Presentation payload binding a conversation to its reconstructed config.
struct ActiveChat: Identifiable {
    let conversation: ChatConversation
    let config: ConversationConfig
    var id: UUID { conversation.id }
}

private struct ConversationRow: View {
    let conversation: ChatConversation

    private var hintsUsed: Int {
        conversation.summary?.hintsUsed ?? conversation.messages.filter { $0.usedHint }.count
    }
    private var translationsUsed: Int {
        conversation.summary?.translationsUsed ?? conversation.messages.filter { !$0.isUser && $0.translationText != nil }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: conversation.symbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(conversation.createdAt.formatted(date: .abbreviated, time: .shortened))
                    Label(conversation.durationLabel, systemImage: "clock")
                        .labelStyle(.titleAndIcon)
                    if hintsUsed > 0 {
                        Label("\(hintsUsed)", systemImage: "lightbulb.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.yellow)
                    }
                    if translationsUsed > 0 {
                        Label("\(translationsUsed)", systemImage: "character.book.closed.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    if conversation.summary != nil {
                        Label("Report", systemImage: "checkmark.seal.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.indigo)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            if let model = conversation.model {
                model.logoImage.resizable().scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if conversation.mode == .scenario, let scenario = conversation.scenario {
            parts.append(scenario.germanTitle)
        } else {
            parts.append(conversation.mode.rawValue)
        }
        parts.append(conversation.level.rawValue)
        let focus = conversation.focusAreas
        if !focus.isEmpty {
            parts.append(focus.map(\.germanLabel).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}
