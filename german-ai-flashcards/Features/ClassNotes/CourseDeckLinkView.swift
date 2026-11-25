import SwiftUI
import SwiftData

/// Attach a deck the learner already has (a generated topic deck, a paper's deck, a story's) to a
/// course, so it shows on the course page with the ones built from its handouts.
struct CourseDeckLinkView: View {
    let course: ClassCourse

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var candidates: [SavedDeck] {
        decks.filter { $0.isBrowsableContent && $0.courseID != course.id && !$0.cards.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    Section {
                        Text("Every deck in your Library is already on a course, or you have none yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .themedListRow()
                } else {
                    Section {
                        ForEach(candidates) { deck in
                            Button {
                                deck.courseID = course.id
                                course.updatedAt = .now
                                try? modelContext.save()
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: deck.kindSymbol ?? "rectangle.stack.fill")
                                        .foregroundStyle(.tint)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(deck.topic).font(.body).lineLimit(1)
                                        HStack(spacing: 6) {
                                            Text("\(deck.cards.count) cards")
                                            if let other = deck.courseID, other != course.id {
                                                Text("· on another course")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text("Tap a deck to put it on \(course.name). A deck belongs to one course at a time; unlink it from the course page.")
                            .font(.caption2)
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle("Link a deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
