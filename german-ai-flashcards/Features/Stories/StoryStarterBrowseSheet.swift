import SwiftUI

/// Browse the ~100 bundled story starters, grouped by category. Tap one to drop it into the
/// topic field; the dice picks a random idea. Presented from the New Story screen.
struct StoryStarterBrowseSheet: View {
    var accent: Color
    /// Called with the chosen German title; the sheet dismisses itself afterward.
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(StoryStarters.categories, id: \.self) { category in
                    Section(Self.englishCategory[category] ?? category) {
                        ForEach(StoryStarters.starters(in: category)) { starter in
                            Button {
                                choose(starter.en)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(starter.en)
                                        .foregroundStyle(.primary)
                                    Text(starter.de)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Story Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let pick = StoryStarters.random() { choose(pick.de) }
                    } label: {
                        Label("Surprise me", systemImage: "die.face.5.fill")
                    }
                }
            }
        }
    }

    private func choose(_ title: String) {
        onSelect(title)
        dismiss()
    }

    /// English labels for the German category keys used to group the starters.
    private static let englishCategory: [String: String] = [
        "Alltag": "Everyday",
        "Reisen": "Travel",
        "Arbeit & Schule": "Work & School",
        "Essen & Trinken": "Food & Drink",
        "Beziehungen": "Relationships",
        "Natur & Tiere": "Nature & Animals",
        "Stadt & Wohnen": "City & Home",
        "Feste & Feiern": "Celebrations",
        "Erinnerungen": "Memories",
        "Fantasie & Zukunft": "Fantasy & Future",
    ]
}
