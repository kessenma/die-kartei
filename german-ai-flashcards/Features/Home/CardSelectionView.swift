import SwiftUI

/// Shown after generation finishes. Lets the user pick which freshly generated
/// cards to keep before they're saved to a deck. All cards start selected.
struct CardSelectionView: View {
    let cards: [VocabCard]
    let topic: String
    let validationResults: [ValidationResult]
    /// Scratch directory holding this run's pictures, when they were drawn before the review
    /// (`CardImageTiming.everyCard`). Nil when the pictures come later, or not at all.
    let draftImageID: UUID?
    /// Draft file name per German word, lowercased — see `DeckIllustrationService.illustrateDraft`.
    let draftImages: [String: String]
    let onSave: ([VocabCard]) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<Int>
    @State private var showingDiscardConfirm = false

    @Environment(\.appTheme) private var theme

    private let validationByWord: [String: ValidationResult]

    init(
        cards: [VocabCard],
        topic: String,
        validationResults: [ValidationResult],
        draftImageID: UUID? = nil,
        draftImages: [String: String] = [:],
        onSave: @escaping ([VocabCard]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.cards = cards
        self.topic = topic
        self.validationResults = validationResults
        self.draftImageID = draftImageID
        self.draftImages = draftImages
        self.onSave = onSave
        self.onCancel = onCancel
        _selected = State(initialValue: Set(cards.indices))
        self.validationByWord = Dictionary(
            validationResults.map { ($0.germanWord, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var allSelected: Bool { selected.count == cards.count }

    private var selectedCards: [VocabCard] {
        cards.enumerated()
            .filter { selected.contains($0.offset) }
            .map(\.element)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        cardRow(index: index, card: card)
                    }
                } header: {
                    Text("\(selected.count) of \(cards.count) selected")
                        .themedSectionHeader()
                }
                .themedListRow()
            }
            .listStyle(.insetGrouped)
            .themedListScreen()
            .navigationTitle("Keep Which Cards?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) {
                        showingDiscardConfirm = true
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        withAnimation(.easeInOut(duration: 0.15)) { toggleAll() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .confirmationDialog(
                "Discard all generated cards?",
                isPresented: $showingDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard \(cards.count) Cards", role: .destructive) { onCancel() }
                Button("Keep Reviewing", role: .cancel) {}
            } message: {
                Text("These cards won't be saved to your decks.")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func cardRow(index: Int, card: VocabCard) -> some View {
        let isSelected = selected.contains(index)

        Button {
            toggle(index)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

                if let draftImageID, let fileName = draftImages[card.germanWord.lowercased()] {
                    DraftCardThumbnail(fileName: fileName, draftImageID: draftImageID)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(germanDisplay(card))
                            .themedLabel(.headline, size: 17)
                        if let type = card.wordType, !type.isEmpty {
                            Text(type)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: theme.pillShape)
                        }
                    }

                    Text(card.englishTranslation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let example = card.exampleSentence, !example.isEmpty {
                        Text(example)
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.tertiary)
                    }

                    if let result = validationByWord[card.germanWord],
                       result.status.badgeLabel != nil {
                        ValidationBadgeView(result: result)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .opacity(isSelected ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                onSave(selectedCards)
            } label: {
                Text(saveButtonTitle)
                    .themedLabel(.headline, size: 17)
                    .textCase(theme.uppercaseSectionHeaders ? .uppercase : nil)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private var saveButtonTitle: String {
        if selected.isEmpty { return "Select Cards to Save" }
        let count = selected.count
        return "Save \(count) Card\(count == 1 ? "" : "s")"
    }

    // MARK: - Helpers

    private func germanDisplay(_ card: VocabCard) -> String {
        card.germanWord.withArticle(card.article)
    }

    private func toggle(_ index: Int) {
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
    }

    private func toggleAll() {
        if allSelected {
            selected.removeAll()
        } else {
            selected = Set(cards.indices)
        }
    }
}

// MARK: - Draft thumbnail

/// The picture a card was given before it had a deck, at row size. Loaded in a `.task` like
/// `FlashCardView` does, so scrolling never waits on a PNG decode.
private struct DraftCardThumbnail: View {
    let fileName: String
    let draftImageID: UUID

    @State private var image: UIImage?
    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        // Chrome-vs-content: the picture itself is untouched, only the frame around it is themed.
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: theme.innerRadius(8), style: .continuous))
        .task(id: fileName) {
            image = CardImageStore.loadImage(fileName: fileName, deckID: draftImageID)
        }
    }
}

@MainActor
private func cardSelectionPreview(_ theme: AppTheme) -> some View {
    CardSelectionView(
        cards: [
            VocabCard(germanWord: "Hund", englishTranslation: "dog", wordType: "noun", article: "der", exampleSentence: "Der Hund schläft."),
            VocabCard(germanWord: "laufen", englishTranslation: "to run", wordType: "verb", article: nil, exampleSentence: "Ich laufe schnell."),
            VocabCard(germanWord: "schön", englishTranslation: "beautiful", wordType: "adjective", article: nil, exampleSentence: nil),
        ],
        topic: "animals",
        validationResults: [],
        onSave: { _ in },
        onCancel: {}
    )
    .environment(\.appTheme, theme)
}

#Preview("Keep which cards · System")   { cardSelectionPreview(.klar) }
#Preview("Keep which cards · Soft")     { cardSelectionPreview(.sanft) }
#Preview("Keep which cards · Notebook") { cardSelectionPreview(.kritzel) }
#Preview("Keep which cards · Bauhaus")  { cardSelectionPreview(.grundform) }
