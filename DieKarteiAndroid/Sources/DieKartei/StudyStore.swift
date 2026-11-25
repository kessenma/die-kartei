import Foundation
import Observation
import SkipFuse
@testable import DieKarteiCore

/// One Goethe word's review progress, as stored. The iOS app keeps the same fields on its
/// SwiftData `SavedCard`; here they are plain values saved as JSON.
struct CardProgress: Codable, Hashable {
    var sortOrder: Int
    var easeFactor = 2.5
    var interval = 0
    var repetitions = 0
    var nextReviewDate: Date?
    var totalReviews = 0
    var lapses = 0
    var leitnerBox = 0
    var firstReviewedAt: Date?
    var lastReviewedAt: Date?
    var lastReviewWasCorrect: Bool?
}

/// The card the shared scheduler works on (`SRSScheduling`, the same SM-2 code as iOS).
@MainActor
final class StudyCard: SRSCardState {
    var progress: CardProgress

    init(_ progress: CardProgress) { self.progress = progress }

    var sortOrder: Int { progress.sortOrder }
    var easeFactor: Double { get { progress.easeFactor } set { progress.easeFactor = newValue } }
    var interval: Int { get { progress.interval } set { progress.interval = newValue } }
    var repetitions: Int { get { progress.repetitions } set { progress.repetitions = newValue } }
    var nextReviewDate: Date? { get { progress.nextReviewDate } set { progress.nextReviewDate = newValue } }
    var totalReviews: Int { get { progress.totalReviews } set { progress.totalReviews = newValue } }
    var lapses: Int { get { progress.lapses } set { progress.lapses = newValue } }
    var leitnerBox: Int { get { progress.leitnerBox } set { progress.leitnerBox = newValue } }

    func noteReview(correct: Bool, at now: Date) {
        progress.lastReviewedAt = now
        progress.lastReviewWasCorrect = correct
        if progress.firstReviewedAt == nil { progress.firstReviewedAt = now }
    }
}

/// The Wortschatz deck on Android: every Goethe word of a level is a card; a word gets progress
/// the first time it's rated. Saved as JSON in UserDefaults (SharedPreferences on Android).
@MainActor
@Observable
final class StudyStore {
    static let shared = StudyStore()

    /// New words a session brings in, on top of everything due.
    static let newPerSession = 10

    private(set) var progress: [String: CardProgress] = [:]
    private let defaultsKey = "studyProgress.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([String: CardProgress].self, from: data) {
            progress = saved
        }
    }

    static func key(_ entry: A1Entry, _ level: GoetheLevel) -> String {
        "\(level.rawValue):\(entry.word)"
    }

    /// Due reviews first (oldest due first), then up to `newPerSession` unseen words in list order.
    func session(for level: GoetheLevel, now: Date = Date()) -> [A1Entry] {
        let entries = GoetheVocabService.entries(for: level)
        var due: [(A1Entry, Date)] = []
        var fresh: [A1Entry] = []
        for entry in entries {
            if let p = progress[Self.key(entry, level)] {
                if let next = p.nextReviewDate, next <= now { due.append((entry, next)) }
            } else if fresh.count < Self.newPerSession {
                fresh.append(entry)
            }
        }
        return due.sorted { $0.1 < $1.1 }.map(\.0) + fresh
    }

    /// The next intervals each rating would give, for the button captions ("1d", "6d", …).
    func previews(for entry: A1Entry, level: GoetheLevel, index: Int) -> [AnkiRating: String] {
        let card = StudyCard(progress[Self.key(entry, level)] ?? CardProgress(sortOrder: index))
        var out: [AnkiRating: String] = [:]
        for preview in SRSScheduling.previewIntervals(for: card) { out[preview.rating] = preview.label }
        return out
    }

    func rate(_ entry: A1Entry, level: GoetheLevel, index: Int, rating: AnkiRating) {
        let key = Self.key(entry, level)
        let card = StudyCard(progress[key] ?? CardProgress(sortOrder: index))
        SRSScheduling.apply(rating: rating, to: card)
        progress[key] = card.progress
        save()
    }

    func stats(for level: GoetheLevel, now: Date = Date()) -> (seen: Int, due: Int, total: Int) {
        let prefix = level.rawValue + ":"
        let mine = progress.filter { $0.key.hasPrefix(prefix) }.map(\.value)
        let due = mine.filter { ($0.nextReviewDate ?? now) <= now }.count
        return (mine.count, due, GoetheVocabService.entries(for: level).count)
    }

    func reset(level: GoetheLevel) {
        let prefix = level.rawValue + ":"
        progress = progress.filter { !$0.key.hasPrefix(prefix) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
