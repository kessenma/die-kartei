//
//  KasusQuestion.swift
//  german-ai-flashcards
//
//  The four anchor questions an English speaker already recognises, plus the honest fifth answer.
//  „Englisch & Fälle“ asks which one a marked phrase answers; every other grammar screen decides
//  with the Kasus-Check instead, and that stays the rule — a question test cannot see a Dativ verb
//  (`KasusLesson`'s „Die Falle“ cards, docs/kasus-exercise-ideas/ENGLISH_ANCHORS.md).
//
//    Wer oder was?   who or what      the one doing it            Nominativ
//    Wen oder was?   whom or what     the one it is done to       Akkusativ
//    Wem?            to whom/for whom the receiver                Dativ
//    Wessen?         whose            whose it is                 Genitiv
//    Keine Frage                      a preposition decided it    any
//
//  A question is never authored: it is read off the phrase's `KasusRole`, which the validator's
//  proof already settled (`KasusConceptFacts.roles`). The fifth answer is not a case, so it has no
//  colour of its own and never borrows the Nominativ's graphite.
//
//  Foundation only and `nonisolated`, like the rest of the Kasus models.
//

import Foundation

nonisolated enum KasusQuestion: String, CaseIterable, Identifiable, Hashable {
    case wer
    case wen
    case wem
    case wessen
    /// A preposition in front decided the case, so none of the four gets asked. Kasus-Check
    /// question one, and the reason this exercise can't be played with four buttons.
    case keine

    var id: String { rawValue }

    /// The button's German, which is the question the learner is meant to start asking themselves.
    var germanLabel: String {
        switch self {
        case .wer:    "Wer oder was?"
        case .wen:    "Wen oder was?"
        case .wem:    "Wem?"
        case .wessen: "Wessen?"
        case .keine:  "Keine Frage"
        }
    }

    /// The gloss under it, at the easier settings.
    var englishGloss: String {
        switch self {
        case .wer:    "who or what"
        case .wen:    "whom or what"
        case .wem:    "to whom, for whom"
        case .wessen: "whose"
        case .keine:  "a preposition decided it"
        }
    }

    /// The case the question names. Nil for `keine`: the preposition picks the case, and which one
    /// it picked is not what the question is about.
    var kasus: GrammarCase? {
        switch self {
        case .wer:    .nominativ
        case .wen:    .akkusativ
        case .wem:    .dativ
        case .wessen: .genitiv
        case .keine:  nil
        }
    }

    /// The question a phrase's role answers. Total over `KasusRole`, so a new Check step has to
    /// decide here too rather than defaulting into „Wen oder was?“.
    init(role: KasusRole) {
        switch role {
        case .praeposition:   self = .keine
        case .gehoertZu:      self = .wessen
        case .subjekt:        self = .wer
        // „Der Bruder ist ein Chef“: the second noun answers „Wer oder was?“ as well, which is
        // exactly why the Nominativ owns both of them.
        case .gleichSubjekt:  self = .wer
        case .empfaenger:     self = .wem
        case .direktesObjekt: self = .wen
        }
    }

    /// The buttons a round shows: the four in table order, then `Keine Frage` on its own row.
    /// `cases` narrows the four at the easiest setting (a unit's `casesInPlay`); `keine` is always
    /// offered, because an exercise that hides it teaches that every phrase answers one of the four.
    static func buttons(cases: [GrammarCase]? = nil) -> [KasusQuestion] {
        let four: [KasusQuestion] = [.wer, .wen, .wem, .wessen]
        guard let cases else { return four + [.keine] }
        return four.filter { question in question.kasus.map(cases.contains) ?? true } + [.keine]
    }
}
