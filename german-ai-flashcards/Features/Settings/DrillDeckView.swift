import SwiftUI
import SwiftData

/// Turn the coach's memory into a flashcard deck: pick from the words you're building and the
/// slip-ups it's watching, then start a new deck or merge into an existing one. Fully offline —
/// the memory is already structured, so no model is needed. Closes the loop from conversation
/// mistakes back into spaced review.
struct DrillDeckView: View {
    @Query private var profiles: [LearnerProfile]
    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var allDecks: [SavedDeck]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var source: DrillSource = .both
    @State private var words: [ReviewWord] = []
    @State private var selectedDeckID: UUID?      // nil == new deck
    @State private var newDeckName = "Meine Schwachstellen"
    @State private var savedSummary: String?
    @State private var didInit = false

    private var profile: LearnerProfile? { profiles.first }

    enum DrillSource: String, CaseIterable, Identifiable {
        case words = "Words"
        case slips = "Slip-ups"
        case both  = "Both"
        var id: String { rawValue }
        var subtitle: String {
            switch self {
            case .words: "The words you're building"
            case .slips: "The correct forms of your repeated slip-ups"
            case .both:  "Your words and your slip-ups together"
            }
        }
    }

    private var hasVocab: Bool { !(profile?.vocab.isEmpty ?? true) }
    private var hasSlips: Bool { !(profile?.slips.isEmpty ?? true) }

    /// Only offer sources that actually have content.
    private var availableSources: [DrillSource] {
        DrillSource.allCases.filter {
            switch $0 {
            case .words: hasVocab
            case .slips: hasSlips
            case .both:  hasVocab && hasSlips
            }
        }
    }

    private var existingDecks: [SavedDeck] {
        allDecks.filter { !["goethe", "goethe-srs", "past-tense", "past-tense-srs", "grammar"].contains($0.generatorRaw) }
    }

    private var selectedCount: Int { words.filter(\.selected).count }
    private var allSelected: Bool { !words.isEmpty && words.allSatisfy(\.selected) }

    var body: some View {
        Form {
            if let savedSummary {
                Section {
                    Label(savedSummary, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Done") { dismiss() }
                }
                .themedListRow()
            } else {
                sourceSection.themedListRow()
                wordsSection.themedListRow()
                destinationSection.themedListRow()
                saveSection.themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Drill deck")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: initOnce)
        .onChange(of: source) { _, _ in rebuild() }
    }

    // MARK: - Sections

    private var sourceSection: some View {
        Section {
            if availableSources.count > 1 {
                Picker("Source", selection: $source) {
                    ForEach(availableSources) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Text(source.subtitle).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("What to drill").themedSectionHeader()
        }
    }

    @ViewBuilder private var wordsSection: some View {
        Section {
            if words.isEmpty {
                Text("Nothing to drill yet — have a few conversations and the coach will collect words and slip-ups here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach($words) { $word in
                    Button {
                        word.selected.toggle()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: word.selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(word.selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(word.german).foregroundStyle(.primary)
                                if !word.english.isEmpty {
                                    Text(word.english).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text("Cards (\(selectedCount) selected)")
                Spacer()
                if !words.isEmpty {
                    Button(allSelected ? "Deselect all" : "Select all") { toggleAll() }
                        .font(.caption).textCase(nil)
                }
            }
            .themedSectionHeader()
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
            Text("Merging skips words already in the deck.")
                .font(.caption2)
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                save()
            } label: {
                Label(selectedDeckID == nil ? "Create deck" : "Add to deck", systemImage: "tray.and.arrow.down.fill")
            }
            .disabled(selectedCount == 0 || (selectedDeckID == nil && newDeckName.trimmingCharacters(in: .whitespaces).isEmpty))
        }
    }

    // MARK: - Candidate building

    private func initOnce() {
        guard !didInit else { return }
        didInit = true
        // Default to the richest available source.
        source = availableSources.first(where: { $0 == .both })
            ?? availableSources.first
            ?? .words
        rebuild()
    }

    private func rebuild() {
        var result: [ReviewWord] = []
        var seen = Set<String>()
        func add(_ list: [ReviewWord]) {
            for w in list where !seen.contains(w.german.lowercased()) {
                seen.insert(w.german.lowercased())
                result.append(w)
            }
        }
        if source == .words || source == .both { add(vocabCandidates()) }
        if source == .slips || source == .both { add(slipCandidates()) }
        words = result
    }

    private func vocabCandidates() -> [ReviewWord] {
        (profile?.vocab ?? [])
            .sorted { $0.lastSeen > $1.lastSeen }
            .map { ReviewWord(german: $0.german, english: $0.english, selected: true) }
    }

    private func slipCandidates() -> [ReviewWord] {
        (profile?.slips ?? [])
            .sorted { $0.timesSeen > $1.timesSeen }
            .map { slip in
                let hint = slip.note.isEmpty ? "correct form — you wrote «\(slip.wrong)»" : slip.note
                return ReviewWord(german: slip.right, english: hint, selected: true)
            }
    }

    private func toggleAll() {
        let target = !allSelected
        for i in words.indices { words[i].selected = target }
    }

    // MARK: - Saving

    private func save() {
        let chosen = words.filter(\.selected)
        guard !chosen.isEmpty else { return }

        if let deckID = selectedDeckID, let deck = existingDecks.first(where: { $0.id == deckID }) {
            let existingWords = Set(deck.cards.map { $0.germanWord.lowercased() })
            var order = (deck.cards.map(\.sortOrder).max() ?? -1) + 1
            var added = 0
            for word in chosen {
                let (german, article) = splitArticle(word.german)
                guard !existingWords.contains(german.lowercased()),
                      !existingWords.contains(word.german.lowercased()) else { continue }
                let card = SavedCard(
                    germanWord: german,
                    englishTranslation: word.english,
                    wordType: article != nil ? "noun" : nil,
                    article: article,
                    sortOrder: order
                )
                card.deck = deck
                deck.cards.append(card)
                modelContext.insert(card)
                order += 1
                added += 1
            }
            deck.wordCount = deck.cards.count
            try? modelContext.save()
            savedSummary = added == 0
                ? "Those cards are already in “\(deck.topic)”."
                : "Added \(added) card\(added == 1 ? "" : "s") to “\(deck.topic)”."
        } else {
            let name = newDeckName.trimmingCharacters(in: .whitespaces)
            let vocab = chosen.map { word -> VocabCard in
                let (german, article) = splitArticle(word.german)
                return VocabCard(
                    germanWord: german,
                    englishTranslation: word.english,
                    wordType: article != nil ? "noun" : nil,
                    article: article,
                    exampleSentence: nil,
                    conjugations: nil
                )
            }
            let deck = SavedDeck(
                topic: name.isEmpty ? "Meine Schwachstellen" : name,
                wordCount: vocab.count,
                includeExamples: false,
                includeGender: vocab.contains { $0.article != nil },
                vocabCards: vocab
            )
            deck.generatorRaw = "coach-drill"
            modelContext.insert(deck)
            try? modelContext.save()
            savedSummary = "Created “\(deck.topic)” with \(vocab.count) card\(vocab.count == 1 ? "" : "s")."
        }
    }

    /// Split a leading article ("der Tisch" -> ("Tisch", "der")).
    private func splitArticle(_ word: String) -> (String, String?) {
        for article in ["der ", "die ", "das "] where word.lowercased().hasPrefix(article) {
            return (String(word.dropFirst(article.count)).trimmingCharacters(in: .whitespaces), String(article.dropLast()))
        }
        return (word, nil)
    }
}
