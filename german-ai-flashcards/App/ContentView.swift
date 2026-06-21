//
//  ContentView.swift
//  german-ai-flashcards
//
//  Created by Kyle Essenmacher on 5/14/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab: MenuTab = .home
    @State private var visitedTabs: Set<MenuTab> = [.home]
    @Bindable var coordinator: GenerationCoordinator
    @State private var displayedCards: [VocabCard] = []
    @State private var displayedTopic: String = ""
    @State private var displayedValidation: [ValidationResult] = []
    @State private var currentDeckID: PersistentIdentifier?
    @State private var displayedSavedCards: [SavedCard] = []
    @State private var displayedFlashcardStyle: FlashcardStyle = .default
    /// Raw generator of the displayed deck (`MLXModel.rawValue`, or `"goethe"`/`""` for bundled
    /// content). Drives the per-model brand theming of the card deck.
    @State private var displayedGeneratorRaw: String = ""
    @State private var cardsResetToken: Int = 0
    @State private var settingsResetToken: Int = 0
    @State private var pendingSubDeckLabel: String?
    @State private var grammarMultipleChoiceCategory: GrammarCategory?
    @State private var grammarMultipleChoiceShowHints = false
    @State private var showingCardSelection = false
    @State private var pendingSelectionCards: [VocabCard] = []
    @State private var pendingSelectionValidation: [ValidationResult] = []
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                HomeView(service: coordinator) {
                    pendingSelectionCards = coordinator.generatedCards
                    pendingSelectionValidation = coordinator.validationResults
                    showingCardSelection = true
                }
                .opacity(selectedTab == .home ? 1 : 0)
                .allowsHitTesting(selectedTab == .home)

                if visitedTabs.contains(.cards) {
                    CardDeckView(
                        cards: displayedCards,
                        topic: displayedTopic,
                        deckID: currentDeckID,
                        validationResults: displayedValidation,
                        onQuizComplete: { correct, total, missedIndices, duration, mode, ankiRatings in
                            saveQuizResult(correct: correct, total: total, missedIndices: missedIndices, durationSeconds: duration, mode: mode, ankiRatings: ankiRatings, subDeckLabel: pendingSubDeckLabel)
                            pendingSubDeckLabel = nil
                        },
                        savedCards: displayedSavedCards,
                        flashcardStyle: displayedFlashcardStyle,
                        generatorModel: MLXModel(rawValue: displayedGeneratorRaw),
                        onStartGoetheStudy: { cards, topic, style, label in
                            displayedCards = cards
                            displayedTopic = topic
                            displayedValidation = []
                            displayedSavedCards = []
                            displayedGeneratorRaw = ""
                            currentDeckID = fetchOrCreateGoetheStatsDeck(for: topic)?.persistentModelID
                            pendingSubDeckLabel = label
                        },
                        resetTrigger: cardsResetToken,
                        autoAdvance: coordinator.modelManager.autoAdvance,
                        isActiveTab: selectedTab == .cards
                    )
                    .environment(coordinator.mlxService)
                    .opacity(selectedTab == .cards ? 1 : 0)
                    .allowsHitTesting(selectedTab == .cards)
                }

                if visitedTabs.contains(.library) {
                    SavedDecksView(
                        onSelectDeck: { deck in
                            currentDeckID = deck.persistentModelID
                            displayedCards = deck.vocabCards
                            displayedTopic = deck.topic
                            displayedValidation = WiktionaryValidator.shared.validate(deck.vocabCards)
                            displayedSavedCards = deck.cards.sorted { $0.sortOrder < $1.sortOrder }
                            displayedFlashcardStyle = coordinator.modelManager.flashcardStyle
                            displayedGeneratorRaw = deck.generatorRaw
                            selectedTab = .cards
                        },
                        onSelectGoetheLevel: { cards, topic, style, label in
                            displayedCards = cards
                            displayedTopic = topic
                            displayedValidation = []
                            displayedFlashcardStyle = style
                            displayedGeneratorRaw = ""
                            pendingSubDeckLabel = label

                            if style == .anki || style == .leitner,
                               let srsDeck = fetchOrCreateGoetheSRSDeck(for: topic) {
                                let lookup = Dictionary(
                                    srsDeck.cards.map { ($0.germanWord, $0) },
                                    uniquingKeysWith: { first, _ in first }
                                )
                                displayedSavedCards = cards.compactMap { lookup[$0.germanWord] }
                                currentDeckID = srsDeck.persistentModelID
                            } else {
                                displayedSavedCards = []
                                currentDeckID = fetchOrCreateGoetheStatsDeck(for: topic)?.persistentModelID
                            }

                            selectedTab = .cards
                        },
                        onSelectPastTenseLevel: { cards, topic, style, label in
                            displayedCards = cards
                            displayedTopic = topic
                            displayedValidation = []
                            displayedFlashcardStyle = style
                            displayedGeneratorRaw = ""
                            pendingSubDeckLabel = label

                            if style == .anki || style == .leitner,
                               let srsDeck = fetchOrCreatePastTenseSRSDeck(for: topic, cards: cards) {
                                let lookup = Dictionary(
                                    srsDeck.cards.map { ($0.germanWord, $0) },
                                    uniquingKeysWith: { first, _ in first }
                                )
                                displayedSavedCards = cards.compactMap { lookup[$0.germanWord] }
                                currentDeckID = srsDeck.persistentModelID
                            } else {
                                displayedSavedCards = []
                                currentDeckID = fetchOrCreatePastTenseStatsDeck(for: topic)?.persistentModelID
                            }

                            selectedTab = .cards
                        },
                        onSelectGrammarFlipCards: { cards, topic, style, label in
                            displayedCards = cards
                            displayedTopic = topic
                            displayedValidation = []
                            displayedFlashcardStyle = style
                            displayedSavedCards = []
                            displayedGeneratorRaw = ""
                            pendingSubDeckLabel = label
                            currentDeckID = fetchOrCreateGrammarStatsDeck(for: topic)?.persistentModelID
                            selectedTab = .cards
                        },
                        onSelectGrammarMultipleChoice: { category, hints in
                            grammarMultipleChoiceShowHints = hints
                            grammarMultipleChoiceCategory = category
                        }
                    )
                    .fullScreenCover(item: $grammarMultipleChoiceCategory) { category in
                        GrammarMultipleChoiceView(
                            category: category,
                            showHints: grammarMultipleChoiceShowHints,
                            onComplete: { correct, total in
                                saveGrammarQuizResult(correct: correct, total: total, category: category)
                            },
                            onDismiss: {
                                grammarMultipleChoiceCategory = nil
                            }
                        )
                    }
                    .opacity(selectedTab == .library ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library)
                }

                if visitedTabs.contains(.conversation) {
                    NavigationStack {
                        ConversationListView(
                            modelManager: coordinator.modelManager,
                            mlxService: coordinator.mlxService
                        )
                    }
                    .opacity(selectedTab == .conversation ? 1 : 0)
                    .allowsHitTesting(selectedTab == .conversation)
                }

                if visitedTabs.contains(.settings) {
                    SettingsView(
                        modelManager: coordinator.modelManager,
                        mlxService: coordinator.mlxService,
                        resetToken: settingsResetToken
                    )
                    .opacity(selectedTab == .settings ? 1 : 0)
                    .allowsHitTesting(selectedTab == .settings)
                }
            }
            .onChange(of: selectedTab) { _, newTab in
                visitedTabs.insert(newTab)
            }

            VStack {
                Spacer()

                if let saveError {
                    Text("Save failed: \(saveError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                NavBar(
                    selectedTab: $selectedTab,
                    isGenerating: coordinator.isGenerating,
                    isDownloading: coordinator.mlxService.isLoading,
                    downloadProgress: coordinator.mlxService.downloadProgress,
                    modelTheme: coordinator.mlxService.loadedModel?.theme,
                    onReselect: { tab in
                        if tab == .cards { cardsResetToken += 1 }
                        // Re-tapping Settings while it's already active pops any pushed
                        // sub-screen back to the root Settings view.
                        if tab == .settings { settingsResetToken += 1 }
                    }
                )
            }
        }
        .sheet(isPresented: $showingCardSelection) {
            CardSelectionView(
                cards: pendingSelectionCards,
                topic: coordinator.lastTopic,
                validationResults: pendingSelectionValidation,
                onSave: { selected in
                    showingCardSelection = false
                    finalizeSession(with: selected)
                },
                onCancel: {
                    showingCardSelection = false
                }
            )
        }
    }

    @State private var saveError: String?

    /// Persist only the cards the user chose to keep, then navigate to the deck.
    private func finalizeSession(with selectedCards: [VocabCard]) {
        guard !selectedCards.isEmpty else { return }
        let deck = saveCurrentSession(cards: selectedCards)
        currentDeckID = deck?.persistentModelID
        displayedCards = selectedCards
        displayedTopic = coordinator.lastTopic
        displayedValidation = WiktionaryValidator.shared.validate(selectedCards)
        displayedSavedCards = deck?.cards.sorted { $0.sortOrder < $1.sortOrder } ?? []
        displayedFlashcardStyle = coordinator.modelManager.flashcardStyle
        displayedGeneratorRaw = coordinator.lastGeneratorRaw
        selectedTab = .cards
    }

    @discardableResult
    private func saveCurrentSession(cards: [VocabCard]) -> SavedDeck? {
        let deck = SavedDeck(
            topic: coordinator.lastTopic,
            wordCount: coordinator.lastWordCount,
            includeExamples: coordinator.lastIncludeExamples,
            includeGender: coordinator.lastIncludeGender,
            wordTypeFilter: coordinator.lastWordTypeFilter,
            includeConjugations: coordinator.lastIncludeConjugations,
            selectedTenses: coordinator.lastSelectedTenses,
            vocabCards: cards
        )
        deck.generatorRaw = coordinator.lastGeneratorRaw
        deck.generationTimeSeconds = coordinator.lastGenerationTimeSeconds
        modelContext.insert(deck)
        do {
            try modelContext.save()
            return deck
        } catch {
            saveError = error.localizedDescription
            print("SwiftData save failed: \(error)")
            return nil
        }
    }

    private func fetchOrCreateGoetheStatsDeck(for topic: String) -> SavedDeck? {
        let validTopics = ["A1 Vocabulary", "A2 Vocabulary", "B1 Vocabulary"]
        guard validTopics.contains(topic) else { return nil }
        let descriptor = FetchDescriptor<SavedDeck>(
            predicate: #Predicate { $0.generatorRaw == "goethe" && $0.topic == topic }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        let deck = SavedDeck(topic: topic, wordCount: 0, includeExamples: false, includeGender: false)
        deck.generatorRaw = "goethe"
        modelContext.insert(deck)
        try? modelContext.save()
        return deck
    }

    private func fetchOrCreateGoetheSRSDeck(for topic: String) -> SavedDeck? {
        let level: GoetheLevel
        switch topic {
        case "A1 Vocabulary": level = .a1
        case "A2 Vocabulary": level = .a2
        case "B1 Vocabulary": level = .b1
        default: return nil
        }

        let allEntries = GoetheVocabService.entries(for: level)
        let descriptor = FetchDescriptor<SavedDeck>(
            predicate: #Predicate { $0.generatorRaw == "goethe-srs" && $0.topic == topic }
        )

        if let deck = (try? modelContext.fetch(descriptor))?.first {
            let existingWords = Set(deck.cards.map { $0.germanWord })
            var nextOrder = (deck.cards.map(\.sortOrder).max() ?? -1) + 1
            for entry in allEntries {
                guard let translation = entry.translation, !translation.isEmpty else { continue }
                guard !existingWords.contains(entry.word) else { continue }
                let card = SavedCard(
                    germanWord: entry.word,
                    englishTranslation: translation,
                    wordType: entry.wordType,
                    article: entry.article,
                    exampleSentence: entry.example?.isEmpty == false ? entry.example : nil,
                    sortOrder: nextOrder
                )
                deck.cards.append(card)
                modelContext.insert(card)
                nextOrder += 1
            }
            try? modelContext.save()
            return deck
        }

        let deck = SavedDeck(
            topic: topic,
            wordCount: allEntries.count,
            includeExamples: true,
            includeGender: true
        )
        deck.generatorRaw = "goethe-srs"
        deck.cards = allEntries.enumerated().compactMap { index, entry in
            guard let translation = entry.translation, !translation.isEmpty else { return nil }
            return SavedCard(
                germanWord: entry.word,
                englishTranslation: translation,
                wordType: entry.wordType,
                article: entry.article,
                exampleSentence: entry.example?.isEmpty == false ? entry.example : nil,
                sortOrder: index
            )
        }
        modelContext.insert(deck)
        try? modelContext.save()
        return deck
    }

    private func fetchOrCreatePastTenseStatsDeck(for topic: String) -> SavedDeck? {
        let validTopics = ["A1 Past Tense Verbs", "A2 Past Tense Verbs", "B1 Past Tense Verbs"]
        guard validTopics.contains(topic) else { return nil }
        let descriptor = FetchDescriptor<SavedDeck>(
            predicate: #Predicate { $0.generatorRaw == "past-tense" && $0.topic == topic }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first { return existing }
        let deck = SavedDeck(topic: topic, wordCount: 0, includeExamples: true, includeGender: false)
        deck.generatorRaw = "past-tense"
        modelContext.insert(deck)
        try? modelContext.save()
        return deck
    }

    private func fetchOrCreatePastTenseSRSDeck(for topic: String, cards: [VocabCard]) -> SavedDeck? {
        let validTopics = ["A1 Past Tense Verbs", "A2 Past Tense Verbs", "B1 Past Tense Verbs"]
        guard validTopics.contains(topic) else { return nil }
        let descriptor = FetchDescriptor<SavedDeck>(
            predicate: #Predicate { $0.generatorRaw == "past-tense-srs" && $0.topic == topic }
        )

        if let deck = (try? modelContext.fetch(descriptor))?.first {
            let existingWords = Set(deck.cards.map { $0.germanWord })
            var nextOrder = (deck.cards.map(\.sortOrder).max() ?? -1) + 1
            for card in cards where !existingWords.contains(card.germanWord) {
                let saved = SavedCard(
                    germanWord: card.germanWord,
                    englishTranslation: card.englishTranslation,
                    wordType: card.wordType,
                    article: nil,
                    exampleSentence: card.exampleSentence,
                    sortOrder: nextOrder
                )
                deck.cards.append(saved)
                modelContext.insert(saved)
                nextOrder += 1
            }
            try? modelContext.save()
            return deck
        }

        let deck = SavedDeck(topic: topic, wordCount: cards.count, includeExamples: true, includeGender: false)
        deck.generatorRaw = "past-tense-srs"
        deck.cards = cards.enumerated().map { index, card in
            SavedCard(
                germanWord: card.germanWord,
                englishTranslation: card.englishTranslation,
                wordType: card.wordType,
                article: nil,
                exampleSentence: card.exampleSentence,
                sortOrder: index
            )
        }
        modelContext.insert(deck)
        try? modelContext.save()
        return deck
    }

    private func fetchOrCreateGrammarStatsDeck(for topic: String) -> SavedDeck? {
        let descriptor = FetchDescriptor<SavedDeck>(
            predicate: #Predicate { $0.generatorRaw == "grammar" && $0.topic == topic }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first { return existing }
        let deck = SavedDeck(topic: topic, wordCount: 0, includeExamples: false, includeGender: false)
        deck.generatorRaw = "grammar"
        modelContext.insert(deck)
        try? modelContext.save()
        return deck
    }

    private func saveGrammarQuizResult(correct: Int, total: Int, category: GrammarCategory) {
        let deck = fetchOrCreateGrammarStatsDeck(for: category.title)
        guard let deck else { return }
        let result = QuizResult(
            totalCards: total,
            correctCount: correct,
            incorrectCardIndices: [],
            durationSeconds: 0,
            studyMode: .default,
            ankiRatings: nil,
            subDeckLabel: "\(total) exercises · \(category.subtitle)"
        )
        result.deck = deck
        modelContext.insert(result)
        try? modelContext.save()
    }

    private func saveQuizResult(correct: Int, total: Int, missedIndices: [Int], durationSeconds: Int, mode: FlashcardStyle, ankiRatings: [Int: AnkiRating]?, subDeckLabel: String? = nil) {
        guard let deckID = currentDeckID else { return }
        guard let deck = modelContext.model(for: deckID) as? SavedDeck else { return }
        let result = QuizResult(
            totalCards: total,
            correctCount: correct,
            incorrectCardIndices: missedIndices,
            durationSeconds: durationSeconds,
            studyMode: mode,
            ankiRatings: mode == .anki ? ankiRatings : nil,
            subDeckLabel: subDeckLabel
        )
        result.deck = deck
        modelContext.insert(result)
        do {
            try modelContext.save()
        } catch {
            print("Failed to save quiz result: \(error)")
        }
    }
}

#Preview {
    ContentView(coordinator: GenerationCoordinator(modelManager: MLXModelManager()))
        .modelContainer(for: SavedDeck.self, inMemory: true)
}
