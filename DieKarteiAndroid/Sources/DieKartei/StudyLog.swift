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
/// Screens log per answer, not per round as iOS does: the totals come out the same, and nothing
/// is lost when a round is left half done. The seconds are the time since the last answer (or
/// since the screen or round began), capped, so a round left open on the table doesn't bank an hour.
@MainActor
@Observable
final class StudyLog {
    static let shared = StudyLog()

    /// The longest gap one answer may bank.
    static let lapCap = 120

    /// iOS's Wortschatz setting (`WortschatzPrefs`): new words a day before the box asks for more.
    static let newPerDayKey = "wortschatz.newPerDay"
    static let newPerDayDefault = 15
    static var newPerDay: Int {
        let stored = UserDefaults.standard.integer(forKey: newPerDayKey)
        return stored > 0 ? stored : newPerDayDefault
    }

    /// Every logged day.
    private(set) var days: [StudyDayRecord] = []
    @ObservationIgnored private let records: RecordStore?
    @ObservationIgnored private var mark: Date?

    init(records: RecordStore? = AppDatabase.records) {
        self.records = records
        reload()
    }

    var streak: Int { StudyStreak.currentStreak(days) }
    var studiedToday: Bool { StudyStreak.studiedToday(days) }
    var newWordsLeftToday: Int { StudyStreak.newWordBudgetRemaining(days, newPerDay: Self.newPerDay) }

    /// A screen or round began: the next answer's time counts from here.
    func begin() { mark = Date() }

    /// One answer (or a finished word, a heard item) with the time since the last one.
    func answered(_ activity: StudyActivity) {
        let now = Date()
        let seconds = mark.map { min(Self.lapCap, max(0, Int(now.timeIntervalSince($0)))) } ?? 0
        mark = now
        write { try $0.recordStudy(activity, seconds: seconds, now: now) }
    }

    /// One finished activity with a known duration (a summarized chat).
    func record(_ activity: StudyActivity, seconds: Int = 0) {
        write { try $0.recordStudy(activity, seconds: seconds) }
    }

    /// Time with nothing finished (a running chat).
    func recordTime(_ bucket: StudyTimeBucket, seconds: Int) {
        write { try $0.recordStudyTime(bucket, seconds: seconds) }
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
