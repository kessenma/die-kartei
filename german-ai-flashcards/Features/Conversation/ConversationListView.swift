import SwiftUI
import SwiftData

/// The Conversation Practice home: start a new voice chat or resume/inspect a saved one.
struct ConversationListView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// When false (embedded as the Library's "Chats" section), the create-actions header and the
    /// "+" toolbar are hidden so this reads as a pure browse/resume list of saved conversations.
    var showsCreateActions: Bool = true

    @Query(sort: \ChatConversation.updatedAt, order: .reverse) private var conversations: [ChatConversation]
    @Query private var decks: [SavedDeck]
    @Environment(\.modelContext) private var modelContext

    @State private var showSetup = false
    @State private var activeChat: ActiveChat?
    @State private var summaryConversation: ChatConversation?
    @State private var filter = ConversationListFilter()

    private var visibleConversations: [ChatConversation] {
        conversations.filter(filter.matches)
    }

    /// Conversation types the library holds, in declaration order.
    private var presentModes: [ConversationMode] {
        let present = Set(conversations.map(\.mode))
        return ConversationMode.allCases.filter { present.contains($0) }
    }

    /// Employers among the interview chats, most frequent first, one spelling per company.
    private var presentCompanies: [String] {
        var counts: [String: (label: String, count: Int)] = [:]
        for convo in conversations where convo.mode == .interview {
            guard let company = convo.jobCompany?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !company.isEmpty else { continue }
            counts[ConversationListFilter.normalized(company), default: (company, 0)].count += 1
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
            .prefix(10)
            .map(\.label)
    }

    var body: some View {
        List {
            if showsCreateActions {
                Section {
                    Button {
                        showSetup = true
                    } label: {
                        Label("New Conversation", systemImage: "plus.bubble.fill")
                            .font(.body.weight(.medium))
                    }
                    NavigationLink {
                        PhraseLibraryView(modelManager: modelManager, mlxService: mlxService)
                    } label: {
                        Label("Phrase library", systemImage: "ear.badge.waveform")
                    }
                } footer: {
                    Text("Have a German conversation with the on-device AI — out loud, or typed when you'd rather stay quiet. Pick a topic, deck, or scenario, choose a grammar focus, and go: it corrects you as you do.")
                        .font(.caption2)
                }
                .themedListRow()
            }

            // One conversation can't be filtered into anything but itself.
            if conversations.count > 1 {
                filterSection
            }

            if conversations.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text("Tap “New Conversation” to start talking — or typing.")
                    )
                }
                .themedListRow()
            } else if visibleConversations.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No conversations match", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Nothing in your library fits these filters yet.")
                    } actions: {
                        Button("Clear filters") { clearFilter() }
                    }
                }
                .themedListRow()
            } else {
                Section {
                    ForEach(visibleConversations) { convo in
                        Button {
                            activeChat = ActiveChat(conversation: convo, config: convo.makeConfig(modelManager: modelManager, decks: decks))
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
                } header: {
                    HStack {
                        Text("Saved conversations").themedSectionHeader()
                        Spacer()
                        if filter.isActive {
                            Text("\(visibleConversations.count) of \(conversations.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle(showsCreateActions ? "Conversation Practice" : "Library")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            if showsCreateActions {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSetup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showSetup) {
            ConversationSetupView(
                modelManager: modelManager,
                mlxService: mlxService,
                onResume: { convo in
                    showSetup = false
                    resume(convo)
                }
            ) { config in
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

    // MARK: - Sections

    private var filterSection: some View {
        Section {
            ConversationFilterBar(filter: $filter, modes: presentModes, companies: presentCompanies)
                // The pills are their own chrome; a row card behind them would box in a strip
                // that is meant to scroll past the section's edges.
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } header: {
            HStack {
                Text("Filter").themedSectionHeader()
                Spacer()
                if filter.isActive {
                    Button("Clear") { clearFilter() }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)          // grouped headers uppercase their text; a button isn't a header
                }
            }
        }
    }

    // MARK: - Actions

    private func clearFilter() {
        withAnimation(.snappy(duration: 0.25)) { filter = ConversationListFilter() }
    }

    private func startNewChat(with config: ConversationConfig) {
        let convo = ChatConversation(config: config)
        modelContext.insert(convo)
        try? modelContext.save()
        // Defer presentation a touch so the setup sheet finishes dismissing first.
        DispatchQueue.main.async {
            activeChat = ActiveChat(conversation: convo, config: config)
        }
    }

    /// Open an existing chat from the setup sheet (an interview for a posting already prepared).
    private func resume(_ convo: ChatConversation) {
        // Same deferral as `startNewChat`: let the setup sheet finish dismissing first.
        DispatchQueue.main.async {
            activeChat = ActiveChat(conversation: convo, config: convo.makeConfig(modelManager: modelManager, decks: decks))
        }
    }

    private func delete(_ convo: ChatConversation) {
        JobPostingSnapshotStore.delete(convo.jobSnapshotFile)
        modelContext.delete(convo)
        try? modelContext.save()
    }

    // `makeConfig(for:)` moved to `ChatConversation.makeConfig(modelManager:decks:)`
    // (ConversationLaunch.swift) so the Job prep hub can resume interviews the same way.
}

/// Presentation payload binding a conversation to its reconstructed config.
struct ActiveChat: Identifiable {
    let conversation: ChatConversation
    let config: ConversationConfig
    var id: UUID { conversation.id }
}

/// One saved chat. Internal rather than private since the Job prep hub lists interviews with it.
struct ConversationRow: View {
    let conversation: ChatConversation

    @Environment(\.appTheme) private var appTheme

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
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))

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
                    if conversation.inputMode == .type {
                        Label("Typed", systemImage: "keyboard.fill")
                            .labelStyle(.iconOnly)
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
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(5)))
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if conversation.mode == .scenario, let scenario = conversation.scenario {
            parts.append(scenario.germanTitle)
        } else if conversation.mode == .interview {
            // "Interview prep · Technical round · Company · City": what the chat rehearsed.
            parts.append(conversation.mode.libraryLabel)
            if let round = conversation.interviewRound { parts.append(round.label) }
            for detail in [conversation.jobCompany, conversation.jobLocation] {
                if let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                    parts.append(detail)
                }
            }
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

#Preview("Conversations · 4 themes") {
    ForEach(AppTheme.allCases) { theme in
        NavigationStack {
            ConversationListView(modelManager: MLXModelManager(), mlxService: MLXGenerationService())
        }
        .environment(\.appTheme, theme)
        .modelContainer(for: [ChatConversation.self, SavedDeck.self], inMemory: true)
    }
}
