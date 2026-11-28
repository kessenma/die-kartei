@testable import DieKarteiCore
import SwiftUI

/// The Library tab: what the learner has, to browse. On iOS that's their decks, chats, reading
/// and phrases; Android has the three Goethe decks so far, each with its progress.
struct LibraryView: View {
    @State var store = StudyStore.shared
    @State var history = ChatHistory.shared
    @State var report: ChatConversationRecord?
    @State var filter = ConversationListFilter()

    var visibleChats: [ChatConversationRecord] { history.chats.filter { filter.matches($0) } }

    var body: some View {
        List {
            Section {
                ForEach(GoetheLevel.allCases) { level in
                    NavigationLink { WortschatzView(fixedLevel: level) } label: {
                        deckRow(level)
                    }
                }
            } header: {
                Text("Decks")
            }
            // As iOS: one conversation can't be filtered into anything but itself.
            if history.chats.count > 1 {
                filterSection
            }
            Section {
                if history.chats.isEmpty {
                    Text("No conversations yet. Start one from Home ▸ Gespräch.")
                        .foregroundStyle(.secondary)
                } else if visibleChats.isEmpty {
                    Text("Nothing in your library fits these filters yet.").foregroundStyle(.secondary)
                    Button("Clear filters") { filter = ConversationListFilter() }
                }
                ForEach(visibleChats, id: \.id) { chat in
                    NavigationLink { GespraechView(resume: chat) } label: {
                        ChatRow(chat: chat)
                    }
                    // As iOS's chats list: swipe for Delete, and Report once the chat has one.
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { history.delete(chat.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        if chat.summary != nil {
                            Button { report = chat } label: {
                                Label("Report", systemImage: "doc.text.magnifyingglass")
                            }
                            .tint(.indigo)
                        }
                    }
                }
            } header: {
                Text("Saved conversations")
            }
            Section {
                NavigationLink { PhraseLibraryView() } label: {
                    Text("Phrase library")
                }
            } footer: {
                Text("Reading comes later.")
            }
        }
        .navigationTitle("Library")
        .onAppear { history.reload() }
        .sheet(isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
            if let report, let summary = try? report.summary?.decoded(as: ConversationSummary.self) {
                NavigationStack {
                    List { SummaryCard(summary: summary) }
                        .navigationTitle(report.title)
                        .toolbar { Button("Done") { self.report = nil } }
                }
            }
        }
    }

    /// iOS's pill strips: the types the library holds, then the employers among its interviews.
    var filterSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ConversationListFilter.presentModes(history.chats)) { mode in
                        FilterPill(label: mode.libraryLabel, isOn: filter.mode == mode) {
                            filter = filter.toggling(mode: mode)
                        }
                    }
                }
            }
            let companies = ConversationListFilter.presentCompanies(history.chats)
            if !companies.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(companies, id: \.self) { company in
                            FilterPill(label: company,
                                       isOn: filter.company.map { ConversationListFilter.sameCompany($0, company) } ?? false) {
                                filter = filter.toggling(company: company)
                            }
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Filter")
                Spacer()
                if filter.isActive {
                    Button("Clear") { filter = ConversationListFilter() }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    func deckRow(_ level: GoetheLevel) -> some View {
        let stats = store.stats(for: level)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Goethe \(level.rawValue) · \(level.examName)")
                .font(.headline)
            Text("\(stats.seen) von \(stats.total) gelernt · \(stats.due) fällig")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// One saved chat (iOS `ConversationRow`): title, what it practised, when and how long.
struct ChatRow: View {
    let chat: ChatConversationRecord

    var subtitle: String {
        let setup = chat.setup
        var parts: [String] = []
        if setup.mode == .scenario, let scenario = setup.scenario {
            parts.append(scenario.germanTitle)
        } else {
            parts.append(setup.mode.rawValue)
        }
        parts.append(setup.level.rawValue)
        let focus = setup.focusAreas
        if !focus.isEmpty { parts.append(focus.map(\.germanLabel).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    var duration: String { String(format: "%d:%02d", chat.durationSeconds / 60, chat.durationSeconds % 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chat.title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(chat.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(duration)
                if chat.summary != nil { Text("Bericht ✓") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// A filter pill: a selected one carries an ✕ and clears on the next tap (iOS `FilterPill`).
struct FilterPill: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                if isOn { Image(systemName: "xmark").font(.caption2) }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(Capsule().fill(isOn ? Color.blue : Color.gray.opacity(0.15)))
        }
        .buttonStyle(.borderless)
    }
}

