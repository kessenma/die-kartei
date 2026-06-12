import DieKarteiCore
import Foundation
import SwiftData

@Model
final class QuizResult {
    var id: UUID
    var date: Date
    var totalCards: Int
    var correctCount: Int
    var incorrectCardIndices: [Int]
    var durationSeconds: Int

    /// Raw value of FlashcardStyle: "Default", "Anki", or "Leitner".
    var studyModeRaw: String

    /// JSON-encoded [Int: Int] — card index → AnkiRating.rawValue (1=again,2=hard,3=good,4=easy). Nil for non-anki modes.
    var ankiRatingsData: Data?

    /// Human-readable label describing the sub-deck studied (e.g. "20 cards · Verbs"). Used for Goethe sessions.
    var subDeckLabel: String?

    var deck: SavedDeck?

    init(
        totalCards: Int,
        correctCount: Int,
        incorrectCardIndices: [Int] = [],
        durationSeconds: Int = 0,
        date: Date = .now,
        studyMode: FlashcardStyle = .default,
        ankiRatings: [Int: AnkiRating]? = nil,
        subDeckLabel: String? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.totalCards = totalCards
        self.correctCount = correctCount
        self.incorrectCardIndices = incorrectCardIndices
        self.durationSeconds = durationSeconds
        self.studyModeRaw = studyMode.rawValue
        self.subDeckLabel = subDeckLabel
        if let ratings = ankiRatings {
            let raw: [Int: Int] = Dictionary(uniqueKeysWithValues: ratings.map { ($0.key, $0.value.rawValue) })
            self.ankiRatingsData = try? JSONEncoder().encode(raw)
        }
    }

    var studyMode: FlashcardStyle {
        FlashcardStyle(rawValue: studyModeRaw) ?? .default
    }

    /// Decoded anki ratings: card index → AnkiRating raw value (1=again, 2=hard, 3=good, 4=easy).
    var ankiRatings: [Int: Int]? {
        guard let data = ankiRatingsData else { return nil }
        return try? JSONDecoder().decode([Int: Int].self, from: data)
    }

    /// Breakdown of anki ratings in this session: (again, hard, good, easy) counts.
    var ankiRatingCounts: (again: Int, hard: Int, good: Int, easy: Int)? {
        guard let ratings = ankiRatings else { return nil }
        let vals = ratings.values
        return (
            again: vals.filter { $0 == AnkiRating.again.rawValue }.count,
            hard:  vals.filter { $0 == AnkiRating.hard.rawValue  }.count,
            good:  vals.filter { $0 == AnkiRating.good.rawValue  }.count,
            easy:  vals.filter { $0 == AnkiRating.easy.rawValue  }.count
        )
    }

    var incorrectCount: Int {
        totalCards - correctCount
    }

    var scorePercentage: Int {
        guard totalCards > 0 else { return 0 }
        return Int(Double(correctCount) / Double(totalCards) * 100)
    }

    var formattedDuration: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
