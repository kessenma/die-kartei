//
//  VerbPreposition.swift
//  german-ai-flashcards
//
//  Verben mit Präpositionen: the verb + preposition pairs whose case the *verb* fixes ("warten
//  auf" + Akkusativ, "Angst haben vor" + Dativ), decoded from verb_prepositions.json by
//  `VerbPrepositionService`.
//
//  These sit beside `Preposition` rather than inside it on purpose. A preposition's own case is
//  a fact about the preposition; a verb pair's case is a fact about the pair, and the two
//  disagree for the two-way words. auf is Akkusativ or Dativ by Wohin/Wo, yet warten auf is
//  Akkusativ with nothing moving. Keeping them apart is what lets the hub teach both rules
//  without one quietly overriding the other (docs/VERB_PREPOSITIONS.md).
//

import Foundation

/// One worked sentence for a verb pair, with what the Lückentext needs to blank it.
nonisolated struct VerbPrepositionExample: Codable, Hashable {
    var german: String
    var english: String
    /// The prepositional phrase as it appears in the sentence ("auf den Bus"). The part a scene
    /// tints and a card highlights.
    var object: String
    /// The text the Lückentext removes ("auf den", "vom", "zu den großen"). Authored, because
    /// contractions and plural adjectives make it unsafe to derive.
    var gap: String
    /// Three plausible wrong answers for the blank: the other case, and the prepositions a
    /// learner reaches for instead.
    var wrong: [String]
    /// The noun after the preposition, and its gender (m/f/n/pl), which the fill-in round
    /// carries for its explanation.
    var noun: String
    var gender: String

    /// The sentence with its gap blanked, as the fill-in round shows it.
    var blanked: String {
        german.replacingOccurrences(of: gap, with: "______")
    }
}

/// One verb + preposition pair.
nonisolated struct VerbPreposition: Codable, Identifiable, Hashable {
    /// The infinitive with its preposition, "sich" included: "sich freuen auf".
    var verb: String
    var preposition: String
    /// Always Akkusativ or Dativ: the verb fixes it, so a pair is never two-way.
    var governs: PrepositionCase
    var english: String
    /// The scene backlog's grouping: echo (the place meaning agrees with the case), trap (a
    /// two-way preposition fixed with no movement), abstract.
    var fit: String
    /// The 3D scene id. Three pairs share one (Angst haben vor / sich fürchten vor, …).
    var scene: String
    /// "A2" or "B1". A string rather than `CEFRLevel`, which is main-actor isolated and so can't
    /// be decoded inside these nonisolated content types.
    var level: String
    var examples: [VerbPrepositionExample]
    var note: String?
    /// The class sheet's original line, when it needed correcting.
    var sheet: String?

    var id: String { verb }

    enum CodingKeys: String, CodingKey {
        case verb, preposition, english, fit, scene, level, examples, note, sheet
        case governs = "case"
    }

    /// The asset key `PrepositionScene` knows this pair's scene by.
    var sceneKey: String { "verb3d-\(scene)" }

    var example: VerbPrepositionExample? { examples.first }

    /// The pair with its preposition taken out, for a card's question side: "warten ___",
    /// "sich freuen ___". The last word is always the preposition.
    var gappedVerb: String {
        var words = verb.split(separator: " ").map(String.init)
        guard words.count > 1 else { return verb }
        words[words.count - 1] = "___"
        return words.joined(separator: " ")
    }

    /// "auf + Akkusativ", the answer a card turns over to.
    var answerLine: String { "\(preposition) + \(governs.germanLabel)" }
}

/// One „Die Falle“ item: a sentence where the same preposition is either a place (two-way, the
/// Wo/Wohin rule decides) or part of a verb pair (the verb decides). The gap is only the
/// article, so the choice is purely the case.
nonisolated struct VerbFalleItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case ort, verb }

    var id: String
    var kind: Kind
    var preposition: String
    var sentence: String
    var answer: String
    var options: [String]
    var noun: String
    var gender: String
    var english: String
    /// The clause after "because" in the round's feedback, naming which rule decided it.
    var why: String
}

nonisolated struct VerbPrepositionsFile: Codable {
    let verbs: [VerbPreposition]
    let falle: [VerbFalleItem]
}
