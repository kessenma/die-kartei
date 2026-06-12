import Foundation

/// The flashcard review style.
enum FlashcardStyle: String, CaseIterable, Codable {
    case `default` = "Default"
    case anki = "Anki"
    case leitner = "Leitner"

    var description: String {
        switch self {
        case .default:
            "Classic flip cards — browse at your own pace."
        case .anki:
            "Spaced repetition — rate each card and review based on memory strength."
        case .leitner:
            "Box system — correct cards advance a box, wrong cards go back to Box 1."
        }
    }
}
