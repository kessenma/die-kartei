import SwiftUI

/// Browse the 100 bundled flashcard topics, grouped by category. Tap one to drop it into the
/// topic field; the dice picks a random idea. Presented from the Create screen.
struct FlashcardTopicBrowseSheet: View {
    var accent: Color?
    /// Called with the chosen English topic; the sheet dismisses itself afterward.
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    groupedTopics
                } else {
                    searchResults
                }
            }
            .searchable(text: $query, prompt: "Search topics")
            .navigationTitle("Topic Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let pick = FlashcardTopics.random() { choose(pick.en) }
                    } label: {
                        Label("Surprise me", systemImage: "die.face.5.fill")
                    }
                }
            }
        }
    }

    private var groupedTopics: some View {
        ForEach(FlashcardTopics.categories, id: \.self) { category in
            Section(Self.englishCategory[category] ?? category) {
                ForEach(FlashcardTopics.topics(in: category)) { topic in
                    row(topic)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let matches = FlashcardTopics.search(query)
        if matches.isEmpty {
            Text("No topics match that. You can still type your own — any topic works.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(matches) { topic in
                row(topic, showCategory: true)
            }
        }
    }

    private func row(_ topic: FlashcardTopic, showCategory: Bool = false) -> some View {
        Button {
            choose(topic.en)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.en)
                    .foregroundStyle(.primary)
                Text(showCategory
                     ? "\(topic.de) · \(Self.englishCategory[topic.category] ?? topic.category)"
                     : topic.de)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func choose(_ topic: String) {
        onSelect(topic)
        dismiss()
    }

    /// English labels for the German category keys used to group the topics.
    private static let englishCategory: [String: String] = [
        "Alltag": "Everyday",
        "Essen & Trinken": "Food & Drink",
        "Reisen": "Travel",
        "Arbeit & Beruf": "Work & Career",
        "Haus & Wohnen": "Home & Living",
        "Gesundheit & Körper": "Health & Body",
        "Einkaufen & Geld": "Shopping & Money",
        "Natur & Umwelt": "Nature & Environment",
        "Menschen & Gefühle": "People & Feelings",
        "Freizeit & Kultur": "Leisure & Culture",
    ]
}
