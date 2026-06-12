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
}

struct GrammarExercisesFile: Codable {
    let categories: [GrammarCategory]
}

enum GrammarStudyMode: String, CaseIterable, Identifiable {
    case multipleChoice = "Multiple Choice"
    case flipCards = "Flip Cards"

    var id: String { rawValue }
}
