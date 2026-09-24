//
//  Activity.swift
//  german-ai-flashcards
//
//  The set of immersive learning activities the app can present. Each case is a "spoke"
//  launched from the Home hub or the Library and shown via a single `.fullScreenCover`.
//

import Foundation

enum Activity: Identifiable {
    /// The flashcard player (default / Anki / Leitner / quiz), configured by a `StudySession`.
    case cardDeck(StudySession)
    /// The fill-in-the-blank grammar quiz.
    case grammarMultipleChoice(category: GrammarCategory, showHints: Bool)
    /// The card-matching recognition game, configured by a `MatchingSession`.
    case matching(MatchingSession)
    /// The der/die/das article game, configured by an `ArticleGameSession`.
    case articleGame(ArticleGameSession)
    /// The preposition Kasus drill, configured by a `PrepositionCaseSession`.
    case prepositionCase(PrepositionCaseSession)
    /// Personalized fill-in-the-blank practice over the learner's own corrected sentences.
    case cloze(ClozeSession)
    /// The case-endings drill: a Kasus unit's Schnellrunde, configured by a `CaseEndingsSession`.
    case caseEndings(CaseEndingsSession)
    /// A Kasus story (Lesen → Finden → Einsetzen → Ergebnis), configured by a `KasusSession`.
    case kasusStory(KasusSession)

    var id: String {
        switch self {
        case .cardDeck(let session):
            return "cardDeck-\(session.id.uuidString)"
        case .grammarMultipleChoice(let category, _):
            return "grammarMC-\(category.id)"
        case .matching(let session):
            return "matching-\(session.id.uuidString)"
        case .articleGame(let session):
            return "articleGame-\(session.id.uuidString)"
        case .prepositionCase(let session):
            return "prepositionCase-\(session.id.uuidString)"
        case .cloze(let session):
            return "cloze-\(session.id.uuidString)"
        case .caseEndings(let session):
            return "caseEndings-\(session.id.uuidString)"
        case .kasusStory(let session):
            return "kasusStory-\(session.id.uuidString)"
        }
    }
}
