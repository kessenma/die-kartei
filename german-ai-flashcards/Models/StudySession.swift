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

    /// The model that generated this deck, when known — used for the deck's brand tint.
    var generatorModel: MLXModel? { MLXModel(rawValue: generatorRaw) }
}
