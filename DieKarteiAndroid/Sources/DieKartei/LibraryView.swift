@testable import DieKarteiCore
import SwiftUI

/// The Library tab: what the learner has, to browse. On iOS that's their decks, chats, reading
/// and phrases; Android has the three Goethe decks so far, each with its progress.
struct LibraryView: View {
    @State var store = StudyStore.shared

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
            } footer: {
                Text("Chats, Reading and Phrases come later: they need the tutor model or the iOS app's own data.")
            }
        }
        .navigationTitle("Library")
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
