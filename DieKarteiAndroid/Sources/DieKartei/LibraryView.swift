@testable import DieKarteiCore
import SwiftUI

/// The Library tab: what the learner has, to browse. On iOS that's their decks, chats, reading
/// and phrases; Android has the three Goethe decks so far, each with its progress.
struct LibraryView: View {
    @State var store = StudyStore.shared
    @State var history = ChatHistory.shared

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
            Section {
                if history.chats.isEmpty {
                    Text("No conversations yet. Start one from Home ▸ Gespräch.")
                        .foregroundStyle(.secondary)
                }
                ForEach(history.chats, id: \.id) { chat in
                    NavigationLink { GespraechView(resume: chat) } label: {
                        ChatRow(chat: chat)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { history.chats[$0].id }
                    for id in ids { history.delete(id) }
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

