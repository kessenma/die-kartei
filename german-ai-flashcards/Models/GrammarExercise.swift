import Foundation

struct GrammarCategory: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let grammaticalCase: String
    let articleType: String
    let ruleNote: String
    let options: [String]
    let exercises: [GrammarExercise]
}

struct GrammarExercise: Codable, Identifiable {
    let id: String
    let sentence: String
    let correctAnswer: String
    let noun: String
    let gender: String
    let verb: String
    let options: [String]?
    let verbForm: String?
    /// The whole sentence in English, blank filled in. Sits behind the Translation button, so a
    /// learner who can't parse the sentence can still work the grammar rather than guessing.
    ///
    /// `var` with a default rather than `let`: a `let` with a default is skipped by Codable
    /// synthesis entirely, which would silently drop the field the JSON does carry.
    var english: String? = nil
    /// Why this answer is the answer, phrased as the clause after "because" and starting
    /// lowercase — the round composes "The answer is den because …" around it. Nil falls back to
    /// `GrammarExplanation`, which derives one from the case and the noun's gender.
    var why: String? = nil
}

struct GrammarExercisesFile: Codable {
    let categories: [GrammarCategory]
}

enum GrammarStudyMode: String, CaseIterable, Identifiable {
    case multipleChoice = "Multiple Choice"
    case flipCards = "Flip Cards"

    var id: String { rawValue }
}
