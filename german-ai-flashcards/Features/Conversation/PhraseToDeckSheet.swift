import SwiftUI
import SwiftData

/// Turn saved phrases from the phrase library into flashcards: pick which phrases to keep, then
/// start a new deck or merge into an existing one. Mirrors `ReviewDeckView`'s create/merge flow,
/// but each phrase becomes one card (the whole phrase as the German side — no article splitting).
struct PhraseToDeckSheet: View {
    /// Candidate phrases to offer (e.g. all phrases, or a single swiped row).
    let phrases: [LearnedPhrase]

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var allDecks: [SavedDeck]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @State private var selected: Set<UUID> = []
    @State private var selectedDeckID: UUID?          // nil == new deck
    @State private var newDeckName = PhraseCards.newDeckName
    @State private var savedSummary: String?
    @State private var didInit = false

    /// User-made decks only — skip the generated catalogues, matching `ReviewDeckView`.
    private var existingDecks: [SavedDeck] {
        allDecks.filter(\.isBrowsableContent)
    }

    private var selectedCount: Int { selected.count }
    private var allSelected: Bool { !phrases.isEmpty && selected.count == phrases.count }

    var body: some View {
        NavigationStack {
            Form {
                if let savedSummary {
                    Section {
                        Label(savedSummary, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Done") { dismiss() }
                    }
                    .themedListRow()
                } else {
                    phrasesSection.themedListRow()
                    destinationSection.themedListRow()
                    saveSection.themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle("Add to flashcards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear(perform: initOnce)
        }
    }

    // MARK: - Sections

    private var phrasesSection: some View {
        Section {
            ForEach(phrases) { phrase in
                Button {
                    toggle(phrase.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected.contains(phrase.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(phrase.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(phrase.german).foregroundStyle(.primary)
                            if !phrase.english.isEmpty {
                                Text(phrase.english).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text("Phrases (\(selectedCount) selected)").themedSectionHeader()
                Spacer()
                if !phrases.isEmpty {
                    Button(allSelected ? "Deselect all" : "Select all") { toggleAll() }
                        .font(.caption)
                        .textCase(nil)
                }
            }
        }
    }

    private var destinationSection: some View {
        Section {
            Picker("Add to", selection: $selectedDeckID) {
                Text("New deck").tag(UUID?.none)
                ForEach(existingDecks) { deck in
                    Text("\(deck.topic) (\(deck.cards.count))").tag(Optional(deck.id))
                }
            }

            if selectedDeckID == nil {
                TextField("Deck name", text: $newDeckName)
            }
        } header: {
            Text("Destination").themedSectionHeader()
        } footer: {
            Text("Each phrase becomes one card. Merging skips phrases already in the deck.")
                .font(.caption2)
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                save()
            } label: {
                Label(selectedDeckID == nil ? "Create deck" : "Add to deck", systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(selectedCount == 0 || (selectedDeckID == nil && newDeckName.trimmingCharacters(in: .whitespaces).isEmpty))
        }
    }

    // MARK: - Logic

    private func initOnce() {
        guard !didInit else { return }
        didInit = true
        selected = Set(phrases.map(\.id))
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func toggleAll() {
        selected = allSelected ? [] : Set(phrases.map(\.id))
    }

    /// What the cards are is shared with Android (`PhraseCards`).
    private func save() {
        let chosen = phrases.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let shared = chosen.map { PhraseCards.Phrase(german: $0.german, english: $0.english) }

        if let deckID = selectedDeckID, let deck = existingDecks.first(where: { $0.id == deckID }) {
            let cards = PhraseCards.merge(shared, intoDeckWith: deck.cards.map(\.germanWord),
                                          lastOrder: deck.cards.map(\.sortOrder).max())
            for made in cards {
                let card = SavedCard(
                    germanWord: made.german,
                    englishTranslation: made.english,
                    wordType: made.wordType,
                    article: nil,
                    sortOrder: made.sortOrder
                )
                card.deck = deck
                deck.cards.append(card)
                modelContext.insert(card)
            }
            deck.wordCount = deck.cards.count
            try? modelContext.save()
            savedSummary = PhraseCards.addedSummary(cards.count, deck: deck.topic)
        } else {
            let vocab = PhraseCards.newDeck(shared).map { made in
                VocabCard(
                    germanWord: made.german,
                    englishTranslation: made.english,
                    wordType: made.wordType,
                    article: nil,
                    exampleSentence: nil,
                    conjugations: nil
                )
            }
            let deck = SavedDeck(
                topic: PhraseCards.deckName(newDeckName),
                wordCount: vocab.count,
                includeExamples: false,
                includeGender: false,
                vocabCards: vocab
            )
            deck.generatorRaw = PhraseCards.generator
            modelContext.insert(deck)
            try? modelContext.save()
            savedSummary = PhraseCards.createdSummary(vocab.count, deck: deck.topic)
        }
    }
}
