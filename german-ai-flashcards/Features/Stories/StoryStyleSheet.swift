import SwiftUI

/// The story "Style" gallery — one card per `StoryGenre`, an SF Symbol on the style's own
/// gradient. Tap a card to select it and dismiss. Replaces the old inline Picker.
struct StoryStyleSheet: View {
    @Binding var selected: StoryGenre

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(StoryGenre.allCases) { genre in
                        StyleCard(genre: genre, isSelected: genre == selected) {
                            selected = genre
                            dismiss()
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Story Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One tappable style card: icon + label + subtitle on the genre's gradient, with a selection ring.
private struct StyleCard: View {
    let genre: StoryGenre
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: genre.systemImage)
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(genre.label)
                        .font(.headline)
                        .lineLimit(1)
                    Text(genre.englishSubtitle)
                        .font(.caption)
                        .opacity(0.9)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(genre.styleGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white, lineWidth: isSelected ? 3 : 0)
            }
            .shadow(color: genre.styleAccent.opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}
