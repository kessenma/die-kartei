//
//  JobPrepHubView.swift
//  german-ai-flashcards
//
//  The Job prep landing page: two front doors (rehearse an interview, study a job ad), then what
//  the learner already has — the postings being studied, the decks those produced, and the past
//  interviews. Interviews open the existing conversation setup locked to interview mode, so the
//  feature is one tap from Home instead of a choice inside the conversation Type picker.
//

import SwiftUI
import SwiftData

struct JobPrepHubView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Query(sort: \JobPosting.updatedAt, order: .reverse) private var postings: [JobPosting]
    // The literal must track `ConversationMode.interview.rawValue` (Models/ConversationConfig.swift);
    // `#Predicate` can't read the enum. See `ChatConversation.interviewModeRaw`.
    @Query(filter: #Predicate<ChatConversation> { $0.modeRaw == "Interview" },
           sort: \ChatConversation.updatedAt, order: .reverse)
    private var interviews: [ChatConversation]
    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(ActivityRouter.self) private var router

    @State private var showInterviewSetup = false
    @State private var showImport = false
    @State private var activeChat: ActiveChat?
    @State private var summaryConversation: ChatConversation?
    /// A posting just imported, pushed straight into the reader.
    @State private var openedPosting: JobPosting?

    private var jobDecks: [SavedDeck] { decks.filter { $0.kind == .job } }
    private var deckStore: DeckStore { DeckStore(modelContext: modelContext) }

    var body: some View {
        List {
            practiceSection
            postingsSection
            if !jobDecks.isEmpty {
                decksSection
            }
            interviewsSection
        }
        .themedListScreen()
        .navigationTitle("Job prep")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .navigationDestination(item: $openedPosting) { posting in
            JobPostingDetailView(posting: posting, modelManager: modelManager, mlxService: mlxService)
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
                fixedMode: .interview
            )
        }
        .sheet(isPresented: $showImport) {
            JobPostingImportView(modelManager: modelManager, mlxService: mlxService) { posting in
                // Let the import sheet finish dismissing before the push.
                DispatchQueue.main.async { openedPosting = posting }
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

    // MARK: - Practice

    private var practiceSection: some View {
        Section {
            Button {
                showInterviewSetup = true
            } label: {
                JobPrepHeroRow(
                    title: "Interview practice",
                    subtitle: "Rehearse with an AI recruiter for a real posting, in German.",
                    systemImage: "briefcase.fill",
                    accent: JobPrepTile.tint
                )
            }
            .buttonStyle(.plain)

            Button {
                showImport = true
            } label: {
                JobPrepHeroRow(
                    title: "Study a job ad",
                    subtitle: "Read a posting line by line. Double-tap the words you don't know, save them as flashcards.",
                    systemImage: "doc.text.magnifyingglass",
                    accent: JobPrepTile.tint
                )
            }
            .buttonStyle(.plain)
        } header: {
            Text("Practice").themedSectionHeader()
        } footer: {
            Text("Bring a posting over from a link, a PDF, pasted text, or an interview you already prepared for.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Postings

    @ViewBuilder
    private var postingsSection: some View {
        Section {
            if postings.isEmpty {
                Text("No postings yet. Study a job ad to start one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(postings) { posting in
                    NavigationLink {
                        JobPostingDetailView(posting: posting, modelManager: modelManager, mlxService: mlxService)
                    } label: {
                        JobPostingRow(posting: posting, deck: JobDeckStore.deck(for: posting, context: modelContext))
                    }
                }
                .onDelete(perform: deletePostings)
            }
        } header: {
            HStack {
                Text("Job postings").themedSectionHeader()
                Spacer()
                if postings.count > 3 {
                    NavigationLink {
                        JobPostingListView(modelManager: modelManager, mlxService: mlxService)
                    } label: {
                        Text("All \(postings.count)")
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                    }
                }
            }
        }
        .themedListRow()
    }

    private func deletePostings(at offsets: IndexSet) {
        for index in offsets {
            let posting = postings[index]
            JobPostingSnapshotStore.delete(posting.snapshotFile)
            // The deck stays: it's library content the learner built, and it lives on its own.
            modelContext.delete(posting)
        }
        try? modelContext.save()
    }

    // MARK: - Decks

    private var decksSection: some View {
        Section {
            ForEach(jobDecks) { deck in
                Button {
                    router.launch(.cardDeck(deckStore.session(for: deck, style: modelManager.flashcardStyle)))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deck.topic.replacingOccurrences(of: "Job: ", with: ""))
                                .font(.body)
                                .lineLimit(1)
                            Text("\(deck.cards.count) cards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Job decks").themedSectionHeader()
        } footer: {
            Text("Words saved while reading a posting. Also under Library ▸ Decks.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Interviews

    @ViewBuilder
    private var interviewsSection: some View {
        Section {
            if interviews.isEmpty {
                Text("No interviews yet. Start one above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(interviews) { convo in
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
            }
        } header: {
            Text("Past interviews").themedSectionHeader()
        } footer: {
            if !interviews.isEmpty {
                Text("Tap to pick up where you left off. Also under Library ▸ Chats.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    // MARK: - Chat presentation (mirrors ConversationListView)

    private func startNewChat(with config: ConversationConfig) {
        let convo = ChatConversation(config: config)
        modelContext.insert(convo)
        try? modelContext.save()
        // Defer presentation a touch so the setup sheet finishes dismissing first.
        DispatchQueue.main.async {
            activeChat = ActiveChat(conversation: convo, config: config)
        }
    }

    private func resume(_ convo: ChatConversation) {
        DispatchQueue.main.async {
            activeChat = ActiveChat(conversation: convo, config: convo.makeConfig(modelManager: modelManager, decks: decks))
        }
    }

    private func delete(_ convo: ChatConversation) {
        JobPostingSnapshotStore.delete(convo.jobSnapshotFile)
        modelContext.delete(convo)
        try? modelContext.save()
    }
}

// MARK: - Hero row

/// One of the two front doors: the `TodayHeroRow` look, without the Start pill (the row itself is
/// the button).
struct JobPrepHeroRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(accent, in: RoundedRectangle(cornerRadius: theme.innerRadius(12), style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .themedLabel(.headline, size: 18)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Posting row

/// One posting in a list: title, employer, where it came from, and how far the learner got.
struct JobPostingRow: View {
    let posting: JobPosting
    var deck: SavedDeck? = nil

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: posting.sourceKind.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))
            VStack(alignment: .leading, spacing: 2) {
                Text(posting.title)
                    .font(.body)
                    .lineLimit(1)
                if !posting.detailLine.isEmpty {
                    Text(posting.detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(posting.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Text("\(posting.wordCount) Wörter")
                    let lookups = posting.lookups.count
                    if lookups > 0 {
                        Label("\(lookups)", systemImage: "character.book.closed.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    if let deck {
                        Label("\(deck.cards.count)", systemImage: "rectangle.stack.fill")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview("Job prep hub · 4 themes") {
    ForEach(AppTheme.allCases) { theme in
        NavigationStack {
            JobPrepHubView(modelManager: MLXModelManager(), mlxService: MLXGenerationService())
        }
        .environment(ActivityRouter())
        .environment(\.appTheme, theme)
        .modelContainer(for: [JobPosting.self, ChatConversation.self, SavedDeck.self, SavedCard.self], inMemory: true)
    }
}
