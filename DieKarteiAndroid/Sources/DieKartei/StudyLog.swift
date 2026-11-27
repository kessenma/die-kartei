import Foundation
import Observation
import SkipFuse
@testable import DieKarteiCore
@testable import KarteiStore

/// Today's study log on Android: every screen reports what it finished here, and Home reads the
/// streak and the new-word budget from it. The rules (what an activity adds, when a day counts,
/// the streak) are the shared ones iOS runs (`StudyDayCounts.swift`); the rows are
/// `StudyDayRecord`s in the record store, so they sync as iOS's `StudyDay` rows.
///
/// Screens log the way iOS's do: once per round (`StudyRound`), when it ends or is left half
/// done, with the wall-clock time since it began; a chat drips its time and counts once summarized.
@MainActor
@Observable
final class StudyLog {
    static let shared = StudyLog()

    /// Every logged day.
    private(set) var days: [StudyDayRecord] = []
    @ObservationIgnored private let records: RecordStore?

    init(records: RecordStore? = AppDatabase.records) {
        self.records = records
        reload()
    }

    var streak: Int { StudyStreak.currentStreak(days) }
    var studiedToday: Bool { StudyStreak.studiedToday(days) }
    var newWordsLeftToday: Int { StudyStreak.newWordBudgetRemaining(days, newPerDay: WortschatzPrefs.newPerDay()) }

    /// One finished activity with a known duration (a round, a summarized chat).
    func record(_ activity: StudyActivity, seconds: Int = 0) {
        write { try $0.recordStudy(activity, seconds: seconds) }
    }

    /// Time with nothing finished (a running chat).
    func recordTime(_ bucket: StudyTimeBucket, seconds: Int) {
        write { try $0.recordStudyTime(bucket, seconds: seconds) }
    }

    /// A Kasus lesson read through (iOS `KasusService.recordLessonRead`): filed once per topic,
    /// its time banked as grammar time.
    func lessonRead(topicKey: String, seconds: Int) {
        write { try $0.recordLessonRead(topicKey: topicKey, seconds: seconds) }
    }

    /// Goethe words rated for the first time.
    func recordNewWords(_ n: Int) {
        write { try $0.recordNewWords(n) }
    }

    private func write(_ body: (RecordStore) throws -> Void) {
        guard let records else { return }
        do {
            try body(records)
        } catch {
            logger.error("StudyLog: could not save: \(error)")
        }
        reload()
    }

    private func reload() {
        days = records?.records(StudyDayRecord.self) ?? []
    }
}

/// One round of a drill, logged as iOS logs its rounds (`SpieleScoringService`,
/// `HoerenScoringService`, `DeckStore.saveQuizResult`, the grammar services): once, with what was
/// done and the wall-clock seconds since the round began. The screen calls `finish()` where its iOS
/// counterpart logs: Spiele at the end or on leaving (an abandoned round still banks its time),
/// Hören at the end or on leaving with at least one item, grammar drills at the end only.
@MainActor
final class StudyRound {
    /// The activity for `n` items done (`.cards(n)`, `.grammar(n)`, …).
    let activity: (Int) -> StudyActivity
    /// Fewer items than this and the round isn't logged (Hören: at least one answer).
    let minimumItems: Int
    private var startedAt: Date?
    private var done = 0

    init(minimumItems: Int = 0, _ activity: @escaping (Int) -> StudyActivity) {
        self.minimumItems = minimumItems
        self.activity = activity
    }

    /// A new round begins. An unfinished one before it is dropped, not logged.
    func start() {
        startedAt = Date()
        done = 0
    }

    /// Items done in this round (cards rated, questions answered, words solved).
    func add(_ n: Int = 1) {
        if startedAt == nil { startedAt = Date() }
        done += n
    }

    /// Log the round, once. Safe to call again, and when no round is running.
    func finish() {
        guard let startedAt else { return }
        self.startedAt = nil
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        defer { done = 0 }
        guard done >= minimumItems, done > 0 || seconds > 0 else { return }
        StudyLog.shared.record(activity(done), seconds: seconds)
    }
}
