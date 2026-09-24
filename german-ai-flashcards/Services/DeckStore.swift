//
//  DeckStore.swift
//  german-ai-flashcards
//
//  Deck persistence + session assembly, lifted out of ContentView so any launcher
//  (Home tile, Library row, level picker) can resolve a `StudySession` and any activity
//  can save its result — without prop-drilling closures back up to ContentView.
//

import Foundation
import SwiftData

struct DeckStore {
    let modelContext: ModelContext

    // MARK: - Session builders

    /// A study session for a saved deck the user tapped in the Library.
    /// `style` is the app default (`modelManager.flashcardStyle`); the user can still
    /// re-pick on the deck's setup screen.
    func session(for deck: SavedDeck, style: FlashcardStyle) -> StudySession {
        let sortedCards = deck.cards.sorted { $0.sortOrder < $1.sortOrder }
        let outcome = WiktionaryValidator.shared.validateAndCorrect(deck.vocabCards)

        // Decks saved before an article fix existed still hold the model's original mistake.
        // Write the correction back so the rest of the app (matching game, SRS, search) sees
        // the same article the player does.
        if !outcome.corrections.isEmpty {
            for correction in outcome.corrections where sortedCards.indices.contains(correction.index) {
                sortedCards[correction.index].article = correction.to
            }
            try? modelContext.save()
        }

        return StudySession(
            cards: outcome.cards,
            topic: deck.topic,
            deckID: deck.persistentModelID,
            validationResults: outcome.results,
            savedCards: sortedCards,
            flashcardStyle: style,
            generatorRaw: deck.generatorRaw,
            subDeckLabel: nil
        )
    }

    // MARK: Wortschatz (the Goethe box)

    /// The one deck every Goethe word's progress lives on. See `WortschatzMergeService`.
    static let wortschatzTopic = "Goethe Vocabulary"
    static let wortschatzBadge = "logo-goethe-square-icon"

    /// A Wortschatz session: the reviews due now (shuffled), then never-seen words up to what
    /// today's budget still allows, in the lists' introduction order. `cards` is built *from* the
    /// chosen rows, so the player's index-aligned `savedCards` can never drift. Nil when there is
    /// nothing to study in this scope.
    func wortschatzSession(
        scope: WortschatzScope, style: FlashcardStyle, newBudget: Int, sessionCap: Int, now: Date = .now
    ) -> StudySession? {
        guard let deck = fetchOrCreateWortschatzDeck() else { return nil }
        let style = style == .default ? .anki : style
        let leitnerSession = deck.quizResults.count
        let inScope = deck.cards.filter { WortschatzService.inScope($0, scope) }

        let due = inScope
            .filter { WortschatzService.isDue($0, style: style, leitnerSession: leitnerSession, now: now) }
            .shuffled()
        let cap = max(1, sessionCap)
        let newAllowed = max(0, min(newBudget, cap - min(due.count, cap)))
        let fresh = inScope
            .filter { WortschatzService.isNew($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
            .prefix(newAllowed)
        let chosen = Array(due.prefix(cap)) + Array(fresh)
        guard !chosen.isEmpty else { return nil }

        return StudySession(
            cards: chosen.map(\.vocabCard),
            topic: scope.topic,
            deckID: deck.persistentModelID,
            savedCards: chosen,
            flashcardStyle: style,
            generatorRaw: "goethe-srs",
            subDeckLabel: "\(min(due.count, cap)) due · \(fresh.count) new · \(scope.summary)",
            badgeLogoName: Self.wortschatzBadge,
            autoStart: true
        )
    }

    /// Flip through words in scope without touching progress: no deck, no saved cards, so the
    /// player runs in plain browse mode and records nothing.
    func wortschatzPreviewSession(scope: WortschatzScope, count: Int) -> StudySession? {
        let cards = GoetheVocabService.words(in: scope).compactMap(\.vocabCard).shuffled().prefix(max(1, count))
        guard !cards.isEmpty else { return nil }
        return StudySession(
            cards: Array(cards),
            topic: scope.topic,
            deckID: nil,
            flashcardStyle: .default,
            generatorRaw: "goethe",
            subDeckLabel: "Preview · \(cards.count) cards",
            badgeLogoName: Self.wortschatzBadge
        )
    }

    /// Due / new / unseen counts for the hero and the Today plan. Reads only; the deck is not
    /// created here, so a learner who never opened the box gets zeros, not 2,800 new cards.
    func wortschatzSummary(
        scope: WortschatzScope, style: FlashcardStyle, budgetRemaining: Int, now: Date = .now
    ) -> WortschatzService.Summary? {
        guard let deck = fetchWortschatzDeck() else { return nil }
        return WortschatzService.summary(
            cards: deck.cards, scope: scope, style: style == .default ? .anki : style,
            leitnerSession: deck.quizResults.count, budgetRemaining: budgetRemaining, now: now
        )
    }

    /// A past-tense (Perfekt) verb session. Mirrors the Goethe SRS-vs-stats split.
    func pastTenseSession(cards: [VocabCard], topic: String, style: FlashcardStyle, label: String) -> StudySession {
        var savedCards: [SavedCard] = []
        var deckID: PersistentIdentifier?
        if (style == .anki || style == .leitner), let srsDeck = fetchOrCreatePastTenseSRSDeck(for: topic, cards: cards) {
            let lookup = Dictionary(
                srsDeck.cards.map { ($0.germanWord, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            savedCards = cards.compactMap { lookup[$0.germanWord] }
            deckID = srsDeck.persistentModelID
        } else {
            deckID = fetchOrCreatePastTenseStatsDeck(for: topic)?.persistentModelID
        }
        return StudySession(
            cards: cards, topic: topic, deckID: deckID,
            savedCards: savedCards, flashcardStyle: style, subDeckLabel: label
        )
    }

    /// Rebuild a resumable session for a deck with a paused snapshot (`pausedAt != nil`), for the
    /// Home ▸ Today "Resume" recommendation. Returns `nil` when the deck can't be reconstructed
    /// (e.g. grammar flip decks store no card payload) or the saved position is stale.
    func resumeSession(for deck: SavedDeck) -> StudySession? {
        guard let data = deck.pausedProgressData,
              let progress = try? JSONDecoder().decode(DeckSessionProgress.self, from: data)
        else { return nil }
        let style = FlashcardStyle(rawValue: progress.studyModeRaw) ?? .default

        let cards: [VocabCard]
        var savedCards: [SavedCard] = []

        switch deck.kind {
        case .generated, .phrase, .conversation, .paper, .story, .job, .classNotes, .document:
            // These store their cards on the deck.
            cards = deck.vocabCards
            savedCards = deck.cards.sorted { $0.sortOrder < $1.sortOrder }
        case .goetheSRS, .pastTenseSRS:
            // The SRS stores hold the whole list; the session studied a subset of it. Rebuild that
            // subset from the saved word order, or give up if any word has since vanished.
            guard let words = progress.cardGermanWords, !words.isEmpty else { return nil }
            let lookup = Dictionary(deck.cards.map { ($0.germanWord, $0) }, uniquingKeysWith: { first, _ in first })
            savedCards = words.compactMap { lookup[$0] }
            guard savedCards.count == words.count else { return nil }
            cards = savedCards.map(\.vocabCard)
        case .goethe:
            // Stats-only Goethe deck — rebuild the studied subset from the saved word order.
            guard let level = goetheLevel(for: deck.topic),
                  let words = progress.cardGermanWords, !words.isEmpty else { return nil }
            let lookup = Dictionary(
                GoetheVocabService.entries(for: level).map { ($0.word, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            cards = GoetheVocabService.toVocabCards(words.compactMap { lookup[$0] })
        case .pastTense:
            guard let level = pastTenseLevel(for: deck.topic),
                  let words = progress.cardGermanWords, !words.isEmpty else { return nil }
            let lookup = Dictionary(
                PastTenseVerbService.entries(for: level).map { ($0.infinitive, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            cards = PastTenseVerbService.toVocabCards(words.compactMap { lookup[$0] })
        case .grammar:
            return nil // grammar flip sessions carry no reconstructable card payload
        }

        guard progress.cardIndex < cards.count else { return nil }

        return StudySession(
            cards: cards,
            topic: deck.topic,
            deckID: deck.persistentModelID,
            savedCards: savedCards,
            flashcardStyle: style,
            generatorRaw: deck.generatorRaw,
            subDeckLabel: nil,
            autoResume: true,
            badgeLogoName: deck.kind == .goetheSRS ? Self.wortschatzBadge : nil
        )
    }

    private func goetheLevel(for topic: String) -> GoetheLevel? {
        switch topic {
        case "A1 Vocabulary": return .a1
        case "A2 Vocabulary": return .a2
        case "B1 Vocabulary": return .b1
        default: return nil
        }
    }

    private func pastTenseLevel(for topic: String) -> PastTenseLevel? {
        switch topic {
        case "A1 Past Tense Verbs": return .a1
        case "A2 Past Tense Verbs": return .a2
        case "B1 Past Tense Verbs": return .b1
        default: return nil
        }
    }

    // MARK: - Matching game sessions

    /// A card-matching round for a saved deck: up to `maxPairs` sampled cards that have both a
    /// German word and an English translation, so the grid always shows valid pairs.
    /// Reuses the deck's own `deckID` + `generatorRaw`, so the round's result slots into per-deck
    /// stats and the streak via `saveQuizResult` — no schema change.
    func matchingSession(from deck: SavedDeck, maxPairs: Int = 8, trickyFirst: Bool = false) -> MatchingSession {
        let usable = deck.vocabCards.filter {
            !$0.germanWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.englishTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let sample = matchingSample(from: usable, maxPairs: maxPairs, trickyFirst: trickyFirst)
        return MatchingSession(
            cards: sample,
            topic: deck.topic,
            deckID: deck.persistentModelID,
            generatorRaw: deck.generatorRaw,
            subDeckLabel: "Matching · \(sample.count) pairs"
        )
    }

    /// A card-matching round seeded from bundled Goethe vocabulary. Tracks results on the same
    /// stats deck the flashcard player uses, so matching counts toward per-level stats + the streak.
    /// `toVocabCards` already drops entries without a translation, so every sampled card is a valid pair.
    func goetheMatchingSession(level: GoetheLevel, maxPairs: Int = 8, trickyFirst: Bool = false) -> MatchingSession {
        let cards = GoetheVocabService.toVocabCards(GoetheVocabService.entries(for: level))
        let sample = matchingSample(from: cards, maxPairs: maxPairs, trickyFirst: trickyFirst)
        let topic = "\(level.rawValue) Vocabulary"
        return MatchingSession(
            cards: sample,
            topic: topic,
            deckID: fetchOrCreateGoetheStatsDeck(for: topic)?.persistentModelID,
            generatorRaw: "goethe",
            subDeckLabel: "Matching · \(sample.count) pairs"
        )
    }

    /// Sample a round's pairs. With `trickyFirst` on, up to half the board is drawn from pairs
    /// the learner keeps missing (`MatchingPairStat.isTricky`) so mistakes come back around —
    /// the rest stays random so rounds never feel like a pure punishment drill.
    private func matchingSample(from cards: [VocabCard], maxPairs: Int, trickyFirst: Bool) -> [VocabCard] {
        guard trickyFirst else { return Array(cards.shuffled().prefix(maxPairs)) }
        let trickyKeys = MatchingStatsService.trickyPairKeys(in: modelContext)
        guard !trickyKeys.isEmpty else { return Array(cards.shuffled().prefix(maxPairs)) }

        var tricky: [VocabCard] = []
        var rest: [VocabCard] = []
        for card in cards {
            let key = MatchingStatsService.pairKey(german: card.germanWord, english: card.englishTranslation)
            if trickyKeys.contains(key) { tricky.append(card) } else { rest.append(card) }
        }
        let trickyTake = Array(tricky.shuffled().prefix(maxPairs / 2))
        let restTake = Array(rest.shuffled().prefix(maxPairs - trickyTake.count))
        return trickyTake + restTake
    }

    // MARK: - Result persistence

    func saveQuizResult(
        deckID: PersistentIdentifier?,
        correct: Int, total: Int, missedIndices: [Int],
        durationSeconds: Int, mode: FlashcardStyle,
        ankiRatings: [Int: AnkiRating]?, subDeckLabel: String? = nil
    ) {
        // Count the review toward today's streak even for cross-deck "Daily Review" sessions,
        // which carry no deckID and would otherwise bail before recording anything. The same is
        // true of its time — banked here so it lands whether or not there's a deck to attach to.
        StudyLogService.record(.cards(total), seconds: durationSeconds, in: modelContext)

        guard let deckID, let deck = modelContext.model(for: deckID) as? SavedDeck else { return }
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

    func saveGrammarQuizResult(
        correct: Int, total: Int, category: GrammarCategory, durationSeconds: Int = 0
    ) {
        StudyLogService.record(.grammar(total), seconds: durationSeconds, in: modelContext)
        guard let deck = fetchOrCreateGrammarStatsDeck(for: category.title) else { return }
        let result = QuizResult(
            totalCards: total,
            correctCount: correct,
            incorrectCardIndices: [],
            durationSeconds: durationSeconds,
            studyMode: .default,
            ankiRatings: nil,
            subDeckLabel: "\(total) exercises · \(category.subtitle)"
        )
        result.deck = deck
        modelContext.insert(result)
        try? modelContext.save()
    }

    // MARK: - Fetch-or-create backing decks

    func fetchOrCreateGoetheStatsDeck(for topic: String) -> SavedDeck? {
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

    /// The merged Wortschatz deck if the learner has one. Read-only companion to the fetch-or-create.
    func fetchWortschatzDeck() -> SavedDeck? {
        let topic = Self.wortschatzTopic
        let descriptor = FetchDescriptor<SavedDeck>(
            predicate: #Predicate { $0.generatorRaw == "goethe-srs" && $0.topic == topic }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// The one SRS deck for every Goethe word: one `SavedCard` per headword in the merged index,
    /// in introduction order. An existing deck is backfilled with any word the lists gained and
    /// stripped of duplicate rows (the old per-level create path never deduped).
    func fetchOrCreateWortschatzDeck() -> SavedDeck? {
        let words = GoetheVocabService.orderedWords

        if let deck = fetchWortschatzDeck() {
            var seen: Set<String> = []
            for card in deck.cards.sorted(by: { ($1.interval, $1.repetitions) < ($0.interval, $0.repetitions) }) {
                if seen.insert(card.germanWord).inserted { continue }
                modelContext.delete(card)
            }
            var nextOrder = (deck.cards.map(\.sortOrder).max() ?? -1) + 1
            for word in words where !seen.contains(word.word) {
                guard let card = Self.makeCard(for: word, sortOrder: nextOrder) else { continue }
                deck.cards.append(card)
                modelContext.insert(card)
                nextOrder += 1
            }
            deck.wordCount = words.count
            try? modelContext.save()
            return deck
        }

        let deck = SavedDeck(
            topic: Self.wortschatzTopic,
            wordCount: words.count,
            includeExamples: true,
            includeGender: true
        )
        deck.generatorRaw = "goethe-srs"
        deck.cards = words.enumerated().compactMap { index, word in Self.makeCard(for: word, sortOrder: index) }
        modelContext.insert(deck)
        try? modelContext.save()
        return deck
    }

    private static func makeCard(for word: GoetheWord, sortOrder: Int) -> SavedCard? {
        guard let translation = word.translation, !translation.isEmpty else { return nil }
        return SavedCard(
            germanWord: word.word,
            englishTranslation: translation,
            wordType: word.rawWordType,
            article: word.article,
            exampleSentence: word.example?.isEmpty == false ? word.example : nil,
            sortOrder: sortOrder
        )
    }

    func fetchOrCreatePastTenseStatsDeck(for topic: String) -> SavedDeck? {
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

    func fetchOrCreatePastTenseSRSDeck(for topic: String, cards: [VocabCard]) -> SavedDeck? {
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

    func fetchOrCreateGrammarStatsDeck(for topic: String) -> SavedDeck? {
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
}
