//
//  GameWordResolver.swift
//  german-ai-flashcards
//
//  Turns a chosen source into the words a game will play with, and builds the rows the setup
//  screen shows before anything is chosen.
//
//  Deck decoding and the Goethe index are both too slow for a view's body, so the setup screen
//  resolves these once in a `.task` and holds the result — the same reason
//  `ArticleGameSetupView` keeps its `deckPools` in `@State`.
//

import Foundation
import SwiftData

@MainActor
enum GameWordResolver {

    /// The words behind a source.
    ///
    /// `prepared` carries words the caller already obtained asynchronously — the tutor's topic
    /// words. This function never calls a model, so it stays cheap and synchronous.
    static func pool(for source: GameWordSource, prepared: [GameWord] = [],
                     decks: [SavedDeck], courses: [ClassCourse]) -> GameWordPool {
        switch source {
        case .deck(let id):
            guard let deck = decks.first(where: { $0.id == id }) else {
                return GameWordPool(words: [], label: "Deck", source: source, deckID: nil)
            }
            return GameWordPool(words: deck.gameWords, label: deck.topic, source: source,
                                deckID: deck.persistentModelID, generatorRaw: deck.generatorRaw)

        case .deckMix(let ids):
            let picked = decks.filter { ids.contains($0.id) }
            let label = picked.count == 1 ? picked[0].topic : "\(picked.count) Stapel"
            // No deckID: a mixed pool can't be credited to one deck.
            return GameWordPool(words: deduplicated(picked.flatMap(\.gameWords)),
                                label: label, source: source, deckID: nil)

        case .course(let id):
            let decksForCourse = courseDecks(id, decks: decks, courses: courses)
            let label = courses.first { $0.id == id }?.name ?? "Kurs"
            return GameWordPool(words: deduplicated(decksForCourse.flatMap(\.gameWords)),
                                label: label, source: source,
                                deckID: decksForCourse.count == 1 ? decksForCourse[0].persistentModelID : nil)

        case .goethe(let level):
            return GameWordPool(words: goetheCandidates(level), label: "Goethe \(level.rawValue)",
                                source: source, deckID: nil, generatorRaw: "goethe")

        case .aiTopic(let topic):
            return GameWordPool(words: deduplicated(prepared), label: topic, source: source,
                                deckID: nil)
        }
    }

    /// A bundled Goethe list as game words, from the merged index so a word carries the article
    /// and translation whichever list happened to have them.
    static func goetheCandidates(_ level: GoetheLevel) -> [GameWord] {
        GoetheVocabService.orderedWords
            .filter { $0.levels.contains(level) }
            .compactMap { GameWord($0) }
    }

    /// A course's deck: the one it names, or every deck filed under it.
    static func courseDecks(_ id: UUID, decks: [SavedDeck], courses: [ClassCourse]) -> [SavedDeck] {
        if let named = courses.first(where: { $0.id == id })?.deckID,
           let deck = decks.first(where: { $0.id == named }) {
            return [deck]
        }
        return decks.filter { $0.courseID == id }
    }

    // MARK: - Setup rows

    /// Every source worth offering, each already measured against the game's limits so a row can
    /// say „6 Wörter · zu wenige“ without the screen doing the work twice.
    static func summaries(decks: [SavedDeck], courses: [ClassCourse],
                          requirements: GameWordRequirements) -> [GameSourceSummary] {
        var rows: [GameSourceSummary] = []

        for level in GoetheLevel.allCases {
            let fit = GameWordFitter.fit(goetheCandidates(level), to: requirements)
            rows.append(GameSourceSummary(
                source: .goethe(level), title: "Goethe \(level.rawValue)",
                subtitle: level.examName, usableCount: fit.usable.count,
                isEnough: fit.isEnough, deckID: nil, generatorRaw: "goethe"))
        }

        for deck in decks where deck.isBrowsableContent {
            let fit = GameWordFitter.fit(deck.gameWords, to: requirements)
            // A deck that can't field a single round isn't worth a row the learner can tap.
            guard fit.usable.count > 0 else { continue }
            rows.append(GameSourceSummary(
                source: .deck(deck.id), title: deck.topic,
                subtitle: subtitle(for: fit, requirements: requirements),
                usableCount: fit.usable.count, isEnough: fit.isEnough,
                deckID: deck.persistentModelID, generatorRaw: deck.generatorRaw))
        }

        for course in courses {
            let words = deduplicated(courseDecks(course.id, decks: decks, courses: courses)
                .flatMap(\.gameWords))
            guard !words.isEmpty else { continue }
            let fit = GameWordFitter.fit(words, to: requirements)
            rows.append(GameSourceSummary(
                source: .course(course.id), title: course.name,
                subtitle: subtitle(for: fit, requirements: requirements),
                usableCount: fit.usable.count, isEnough: fit.isEnough, deckID: nil))
        }

        return rows
    }

    /// „12 Wörter“, or the leading reason the rest didn't make it.
    private static func subtitle(for fit: GameWordFitter.Fit,
                                 requirements: GameWordRequirements) -> String {
        let count = fit.usable.count
        let words = count == 1 ? "1 Wort" : "\(count) Wörter"
        guard !fit.isEnough, let leading = fit.reasonTally.first else { return words }
        return "\(words) · \(leading.count) \(leading.kind.englishReason)"
    }

    private static func deduplicated(_ words: [GameWord]) -> [GameWord] {
        var seen: Set<String> = []
        return words.filter { seen.insert($0.id).inserted }
    }
}
