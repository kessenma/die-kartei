//
//  GameWordSource.swift
//  german-ai-flashcards
//
//  Where a game's words come from. Identified by `UUID` rather than `PersistentIdentifier` so the
//  learner's last choice can sit in `@AppStorage` and survive a relaunch and a sync.
//

import Foundation
import SwiftData

nonisolated enum GameWordSource: Hashable, Codable, Identifiable, Sendable {
    /// One of the learner's own decks, by `SavedDeck.id`.
    case deck(UUID)
    /// Several decks played as one pool, via the Library's existing mix picker.
    case deckMix([UUID])
    /// A Deutschkurs course's deck, by `ClassCourse.id`.
    case course(UUID)
    /// A bundled Goethe list — the source that works on a fresh install.
    case goethe(GoetheLevel)
    /// Words the tutor wrote for a topic the learner typed. The only source needing a model.
    case aiTopic(String)

    var id: String {
        switch self {
        case .deck(let deck):      "deck-\(deck.uuidString)"
        case .deckMix(let decks):  "mix-" + decks.map(\.uuidString).sorted().joined(separator: "+")
        case .course(let course):  "course-\(course.uuidString)"
        case .goethe(let level):   "goethe-\(level.rawValue)"
        case .aiTopic(let topic):  "ai-\(topic.lowercased())"
        }
    }

    /// Whether picking this source needs a tutor on the device.
    var needsModel: Bool {
        if case .aiTopic = self { return true }
        return false
    }
}

/// A resolved source: the words, plus everything a result needs to be credited to the right place.
struct GameWordPool {
    var words: [GameWord]
    /// Learner-facing label for the top bar and the saved result.
    var label: String
    var source: GameWordSource
    /// Set only for a single-deck source, so a result can be credited to that deck.
    var deckID: PersistentIdentifier?
    /// `MLXModel.rawValue`, "goethe", or "" — the brand tint, as everywhere else.
    var generatorRaw: String = ""
    /// Where any topped-up words came from, so the summary can say so.
    var toppedUp: GameTopUp?

    var count: Int { words.count }
}

/// How a thin source was filled out.
nonisolated enum GameTopUp: Hashable, Sendable {
    case goethe(GoetheLevel)
    case model(topic: String)
    case moreDecks

    var germanLabel: String {
        switch self {
        case .goethe(let level): "aufgefüllt mit \(level.rawValue)"
        case .model:             "aufgefüllt vom Tutor"
        case .moreDecks:         "aufgefüllt aus weiteren Stapeln"
        }
    }

    var englishLabel: String {
        switch self {
        case .goethe(let level): "topped up from \(level.rawValue)"
        case .model:             "topped up by the tutor"
        case .moreDecks:         "topped up from more decks"
        }
    }
}

/// One row on the setup screen: a source, and whether it can actually be played.
struct GameSourceSummary: Identifiable {
    var source: GameWordSource
    var title: String
    var subtitle: String
    /// Words left after the game's limits are applied — what the row reports.
    var usableCount: Int
    var isEnough: Bool
    var deckID: PersistentIdentifier?
    var generatorRaw: String = ""

    var id: String { source.id }
}
