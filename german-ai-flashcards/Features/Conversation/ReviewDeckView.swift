import SwiftUI
import SwiftData

/// Build a flashcard deck from a conversation: choose where the words come from, pick which
/// to keep and how many, then start a new deck or merge into an existing one (smartly suggested).
struct ReviewDeckView: View {
    let conversation: ChatConversation
    var mlxService: MLXGenerationService?
    var modelManager: MLXModelManager?

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var allDecks: [SavedDeck]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @State private var source: WordSource = .aiReview
    @State private var count: Int = 10
    @State private var words: [ReviewWord] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var selectedDeckID: UUID?          // nil == new deck
    @State private var newDeckName: String = ""
    @State private var savedSummary: String?
    @State private var didInit = false

    enum WordSource: String, CaseIterable, Identifiable {
        case saved      = "I saved"
        case aiReview   = "AI picks"
        case saidPlusAI = "Said + AI"
        case saidOnly   = "I said"
        var id: String { rawValue }
        var usesAI: Bool { self == .aiReview || self == .saidPlusAI }
        var subtitle: String {
            switch self {
            case .saved:      "Words you tapped and saved during the chat"
            case .aiReview:   "The model picks useful words from the whole chat"
            case .saidPlusAI: "Words you used, plus the model's picks"
            case .saidOnly:   "Only deck words you actually used"
            }
        }
    }

    /// Hide the "saved" option unless the chat actually has saved words.
    private var availableSources: [WordSource] {
        WordSource.allCases.filter { $0 != .saved || !conversation.savedVocab.isEmpty }
    }

    private var existingDecks: [SavedDeck] {
        allDecks.filter(\.isBrowsableContent)
    }

    private var selectedCount: Int { words.filter(\.selected).count }

    var body: some View {
        Form {
            if let savedSummary {
                Section {
                    Label(savedSummary, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
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
        .navigationTitle("Review deck")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(source.rawValue)-\(count)") {
            await rebuild()
        }
        .onAppear(perform: initDefaultsOnce)
    }

    // MARK: - Sections

    private var sourceSection: some View {
        Section {
            Picker("Source", selection: $source) {
                ForEach(availableSources) { s in Text(s.rawValue).tag(s) }
            }
            .pickerStyle(.segmented)

            Text(source.subtitle).font(.caption).foregroundStyle(.secondary)

            if source.usesAI {
                Picker("How many to suggest", selection: $count) {
                    ForEach([5, 10, 15, 20], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Where words come from").themedSectionHeader()
        }
    }

    @ViewBuilder private var wordsSection: some View {
        Section {
            if loading {
                HStack(spacing: 8) { ProgressView(); Text("Finding words…").foregroundStyle(.secondary) }
            } else if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            } else if words.isEmpty {
                Text("No words found for this option — try a different source or a longer chat.")
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
                Text("Words (\(selectedCount) selected)").themedSectionHeader()
                Spacer()
                if !words.isEmpty {
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

            if let suggested = suggestedDeck {
                if selectedDeckID == suggested.id {
                    Label("These words look like they fit your “\(suggested.topic)” deck.", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
                } else if selectedDeckID == nil && selectedCount < 4 {
                    Label("Tip: just a few words — consider adding them to “\(suggested.topic)” instead of a tiny new deck.", systemImage: "lightbulb")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Destination").themedSectionHeader()
        } footer: {
            Text("Merging skips words already in the deck. Growing existing decks keeps your library tidy.")
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

    // MARK: - Suggestion logic

    private var conversationDeckIDs: Set<UUID> {
        Set(conversation.deckIDsRaw.compactMap { UUID(uuidString: $0) })
    }

    /// Suggest a deck these words likely belong to: the chat's source decks, else a topic-keyword match.
    private var suggestedDeck: SavedDeck? {
        let sourceDecks = existingDecks.filter { conversationDeckIDs.contains($0.id) }
        if let best = sourceDecks.max(by: { $0.cards.count < $1.cards.count }) { return best }

        let keywords = Set(
            keywordsOf(conversation.title)
            + keywordsOf(conversation.scenario?.germanTitle ?? "")
            + keywordsOf(conversation.scenario?.englishDescription ?? "")
        )
        guard !keywords.isEmpty else { return nil }
        return existingDecks.first { !Set(keywordsOf($0.topic)).isDisjoint(with: keywords) }
    }

    private func keywordsOf(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 4 }
    }

    // MARK: - Building the candidate list

    private func initDefaultsOnce() {
        guard !didInit else { return }
        didInit = true
        // Default to the words the learner explicitly saved, if any.
        if !conversation.savedVocab.isEmpty { source = .saved }
        selectedDeckID = suggestedDeck?.id
        newDeckName = "Gespräch: \(conversation.title)"
    }

    private var allSelected: Bool { !words.isEmpty && words.allSatisfy(\.selected) }

    private func toggleAll() {
        let target = !allSelected
        for i in words.indices { words[i].selected = target }
    }

    private func rebuild() async {
        errorText = nil

        if source == .saved {
            words = savedWords()
            return
        }

        let said = saidWords()

        if source == .saidOnly {
            words = said
            return
        }

        guard let mlxService else {
            words = said
            if source == .aiReview { errorText = "The model isn’t available right now." }
            return
        }

        loading = true
        defer { loading = false }

        let model = conversation.model ?? modelManager?.selectedChatModel ?? .hero
        if !mlxService.isModelLoaded || mlxService.currentModel != model {
            await mlxService.loadModel(model)
        }
        guard mlxService.isModelLoaded, mlxService.currentModel == model else {
            errorText = mlxService.loadError ?? "Couldn’t load the model."
            words = (source == .saidPlusAI) ? said : []
            return
        }

        let ai = await extractAIWords(count: count, model: model, service: mlxService)

        switch source {
        case .aiReview:
            if ai.isEmpty { errorText = "Couldn’t find clear vocabulary — try a longer chat." }
            words = ai
        case .saidPlusAI:
            var merged = said
            let have = Set(said.map { $0.german.lowercased() })
            for w in ai where !have.contains(w.german.lowercased()) { merged.append(w) }
            words = merged
        case .saidOnly:
            words = said
        case .saved:
            words = savedWords()  // handled earlier; here for exhaustiveness
        }
    }

    private func savedWords() -> [ReviewWord] {
        conversation.savedVocab.map { ReviewWord(german: $0.german, english: $0.english, selected: true) }
    }

    private func saidWords() -> [ReviewWord] {
        let lookup = deckTranslationLookup()
        var seen = Set<String>()
        var result: [ReviewWord] = []
        for message in conversation.sortedMessages {
            for word in message.targetWordsUsed {
                let key = word.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(ReviewWord(german: word, english: lookup[key] ?? "", selected: true))
            }
        }
        return result
    }

    private func deckTranslationLookup() -> [String: String] {
        var dict: [String: String] = [:]
        for deck in allDecks {
            for card in deck.cards where dict[card.germanWord.lowercased()] == nil {
                dict[card.germanWord.lowercased()] = card.englishTranslation
            }
        }
        return dict
    }

    private func extractAIWords(count: Int, model: MLXModel, service: MLXGenerationService) async -> [ReviewWord] {
        let transcript = ConversationPrompts.transcript(from: conversation.sortedMessages)
        let system = """
        Extract up to \(count) useful German words or short phrases from this conversation transcript that the STUDENT should review. \
        Prefer words the student struggled with or that were new to them. For each, give the German word and a natural English translation. \
        Reply with ONE per line in EXACTLY this format and nothing else:
        german = english
        """
        do {
            let raw = try await service.generateText(system: system, user: transcript, model: model, maxTokens: 60 + count * 28)
            return parsePairs(raw, limit: count)
        } catch {
            if !(error is CancellationError) { errorText = error.localizedDescription }
            return []
        }
    }

    private func parsePairs(_ raw: String, limit: Int) -> [ReviewWord] {
        let cleaned = ConversationPrompts.stripThinkBlocks(raw)
        var result: [ReviewWord] = []
        var seen = Set<String>()
        for line in cleaned.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let sep = trimmed.range(of: "=") ?? trimmed.range(of: " - ") ?? trimmed.range(of: " — ") else { continue }
            var german = String(trimmed[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
            german = german.trimmingCharacters(in: CharacterSet(charactersIn: "-•*0123456789. )"))
            let english = String(trimmed[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard german.count >= 2, !english.isEmpty else { continue }
            let key = german.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(ReviewWord(german: german, english: english, selected: true))
            if result.count >= limit { break }
        }
        return result
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
                ? "Those words are already in “\(deck.topic)”."
                : "Added \(added) word\(added == 1 ? "" : "s") to “\(deck.topic)”."
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
                topic: name.isEmpty ? "Gespräch: \(conversation.title)" : name,
                wordCount: vocab.count,
                includeExamples: false,
                includeGender: vocab.contains { $0.article != nil },
                vocabCards: vocab
            )
            deck.generatorRaw = "conversation"
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

/// A candidate word for the review deck.
struct ReviewWord: Identifiable {
    let id = UUID()
    let german: String
    let english: String
    var selected: Bool
}
