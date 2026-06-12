import Foundation

public struct GrammarCategory: Codable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let grammaticalCase: String
    public let articleType: String
    public let ruleNote: String
    public let options: [String]
    public let exercises: [GrammarExercise]
}

public struct GrammarExercise: Codable, Identifiable {
    public let id: String
    public let sentence: String
    public let correctAnswer: String
    public let noun: String
    public let gender: String
    public let verb: String
    public let options: [String]?
    public let verbForm: String?
}

public struct GrammarExercisesFile: Codable {
    public let categories: [GrammarCategory]
}

public enum GrammarStudyMode: String, CaseIterable, Identifiable {
    case multipleChoice = "Multiple Choice"
    case flipCards = "Flip Cards"

    public var id: String { rawValue }
}
