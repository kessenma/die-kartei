//
//  DeckKind.swift
//  german-ai-flashcards
//
//  What sort of deck a `generatorRaw` names, and which word types a generated deck asked for.
//  Foundation only and shared with the Android app (DieKarteiCore), so both apps sort the same
//  decks into the Library: iOS `SavedDeck.kind`, Android's `DeckRecord`.
//

import Foundation

/// What sort of deck this is, derived from `generatorRaw`. Replaces scattered string
/// comparisons so classification stays consistent across the app.
enum DeckKind {
    /// User-generated (AI or bundled default) — the real "My Decks" content.
    case generated
    case goethe, goetheSRS
    case pastTense, pastTenseSRS
    case grammar
    /// The Verben-mit-Präpositionen review box: one card per verb pair, studied in the
    /// preposition hub's own review (VerbPrepositionReviewView), not the generic player.
    case verbPrepositionSRS
    /// Real saved-word content built from the phrase library / a conversation / a paper / a story
    /// / a job posting the learner studied / a class the learner is taking / a document (a vocab
    /// sheet, a handout) the learner turned into cards.
    case phrase, conversation, paper, story, job, classNotes, document

    /// `VerbPrepositionService.deckGenerator` on iOS (`DeckTransferParityTests` checks they agree).
    static let verbPrepositionGenerator = "verb-prep-srs"

    init(generatorRaw: String) {
        switch generatorRaw {
        case "goethe": self = .goethe
        case "goethe-srs": self = .goetheSRS
        case "past-tense": self = .pastTense
        case "past-tense-srs": self = .pastTenseSRS
        case "grammar": self = .grammar
        case Self.verbPrepositionGenerator: self = .verbPrepositionSRS
        case "phrase": self = .phrase
        case "conversation": self = .conversation
        case "paper": self = .paper
        case "story": self = .story
        case "job": self = .job
        case "class": self = .classNotes
        case "document": self = .document
        default: self = .generated // "" or an MLXModel.rawValue
        }
    }

    /// Decks that belong in the Library's browsable "Decks" list. Excludes the internal
    /// stats/SRS holders for Goethe / Past-tense / Grammar (which are activity plumbing,
    /// not standalone content).
    var isBrowsableContent: Bool {
        switch self {
        case .generated, .phrase, .conversation, .paper, .story, .job, .classNotes, .document: true
        case .goethe, .goetheSRS, .pastTense, .pastTenseSRS, .grammar, .verbPrepositionSRS: false
        }
    }
}

enum WordTypeFilter: String, CaseIterable, Codable {
    case all = "All"
    case nouns = "Nouns"
    case verbs = "Verbs"
    case adjectives = "Adjectives"
    case verbsAndAdjectives = "Verbs & Adj."

    var includesVerbs: Bool {
        self == .all || self == .verbs || self == .verbsAndAdjectives
    }

    var includesAdjectives: Bool {
        self == .all || self == .adjectives || self == .verbsAndAdjectives
    }

    var includesNouns: Bool {
        self == .all || self == .nouns
    }
}
