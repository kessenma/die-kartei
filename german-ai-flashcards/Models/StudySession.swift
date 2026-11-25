//
//  StudySession.swift
//  german-ai-flashcards
//

import Foundation
import SwiftData

/// The payload for launching the flashcard player. Carries the "deck identity" that used to
/// live as scattered `@State` on `ContentView` (`displayedCards`, `displayedTopic`,
/// `currentDeckID`, …). Built by `DeckStore` and handed to a `.cardDeck` `Activity`.
struct StudySession: Identifiable {
    let id = UUID()

    var cards: [VocabCard]
    var topic: String
    /// Backing `SavedDeck` id — enables quiz-result saving and pause/resume persistence.
    /// `nil` only for throwaway sessions (closed once auto-save lands in Phase 3).
    var deckID: PersistentIdentifier?
    var validationResults: [ValidationResult] = []
    /// SRS-backed cards for Anki/Leitner modes; empty for default/quiz.
    var savedCards: [SavedCard] = []
    var flashcardStyle: FlashcardStyle = .default
    /// `MLXModel.rawValue` (or "goethe"/"" for bundled content) — drives brand theming.
    var generatorRaw: String = ""
    /// Label stamped onto the saved `QuizResult` (e.g. "20 cards · Nouns").
    var subDeckLabel: String?
    /// When true (launched from Home ▸ Continue), the player restores the paused position on
    /// appear instead of showing the setup screen's "you have a paused session" prompt.
    var autoResume: Bool = false
    /// Asset name of the badge the card wears when no model logo applies (the Goethe mark on
    /// Wortschatz cards). The player also infers it from the backing deck; this covers sessions
    /// with no saved cards, like a Vorschau.
    var badgeLogoName: String? = nil
    /// When true the player skips its setup screen and begins at once — for launchers that are
    /// themselves the setup screen (the Wortschatz hub). A paused session still wins.
    var autoStart: Bool = false
    /// Several saved decks studied as one (Library ▸ Decks ▸ Mix). `deckID` stays nil, so the
    /// session can't pause; the player credits each deck its share of the result instead.
    var isDeckMix: Bool = false
    /// Where the learner goes after the cards, when the launcher has a next step (the next part
    /// of a Schreibblatt set, or finishing it). The player makes it the main button on its
    /// summary and its start screen; nil leaves both as they were.
    var onward: StudyOnward? = nil

    /// The model that generated this deck, when known — used for the deck's brand tint.
    var generatorModel: MLXModel? { MLXModel(rawValue: generatorRaw) }
}

/// The player's way on (`StudySession.onward`). Tapping it closes the player and calls `action`
/// at once; a launcher that presents something itself should wait for the cover to be down
/// (the router's `active` going nil), since a cover cannot open over one still leaving.
struct StudyOnward {
    /// "Weiter: Teil 4 schreiben".
    let title: String
    let systemImage: String
    let action: @MainActor () -> Void
}
