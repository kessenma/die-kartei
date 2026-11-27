import Foundation
@testable import DieKarteiCore

/// The study-day log on Android: the same writes as iOS `StudyLogService`, into `StudyDayRecord`s
/// (one per date key, `SyncDayKey`), with the increments from the shared `StudyDayTally`. Every
/// write goes through `put`, so the counters land in this install's slot and two devices studying
/// the same day add up once synced.
extension RecordStore {
    /// The record for the date `now` falls on (in `calendar`'s time zone), if anything was logged.
    func studyDay(at now: Date = Date(), calendar: Calendar = .current) -> StudyDayRecord? {
        let key = SyncDayKey.key(for: calendar.startOfDay(for: now), calendar: calendar)
        return records(StudyDayRecord.self, naturalKey: key).first
    }

    /// Days whose key lies in `from...to` (inclusive), oldest first.
    func studyDays(from: Date, to: Date, calendar: Calendar = .current) -> [StudyDayRecord] {
        records(StudyDayRecord.self,
                days: SyncDayKey.key(for: calendar.startOfDay(for: from), calendar: calendar),
                SyncDayKey.key(for: calendar.startOfDay(for: to), calendar: calendar))
    }

    /// One finished activity (`StudyLogService.record`).
    func recordStudy(_ activity: StudyActivity, seconds: Int = 0, now: Date = Date(),
                     calendar: Calendar = .current) throws {
        try addToDay(StudyDayTally.increments(for: activity, seconds: seconds), stamp: true, now: now, calendar: calendar)
    }

    /// Time with nothing finished, like a running chat (`StudyLogService.recordTime`).
    func recordStudyTime(_ bucket: StudyTimeBucket, seconds: Int, now: Date = Date(),
                         calendar: Calendar = .current) throws {
        try addToDay(StudyDayTally.increments(time: bucket, seconds: seconds), stamp: true, now: now, calendar: calendar)
    }

    /// Goethe words rated for the first time: today's new-word budget, not study on its own.
    func recordNewWords(_ n: Int, now: Date = Date(), calendar: Calendar = .current) throws {
        try addToDay(["newWordsIntroduced": n], stamp: false, now: now, calendar: calendar)
    }

    /// "Learn 10 more": widen today's budget.
    func addNewWordBonus(_ n: Int, now: Date = Date(), calendar: Calendar = .current) throws {
        try addToDay(["newWordsBonus": n], stamp: false, now: now, calendar: calendar)
    }

    /// The lesson for a topic was read through (`KasusService.recordLessonRead`): one `lesson`
    /// round per topic, its reading time banked as grammar time. False when it was already read.
    @discardableResult
    func recordLessonRead(topicKey: String, seconds: Int, now: Date = Date(), calendar: Calendar = .current) throws -> Bool {
        if lessonRead(topicKey: topicKey) { return false }
        try transaction {
            try put(KasusRoundRecord.lessonRead(topicKey: topicKey, seconds: seconds, at: now), now: now)
            if seconds > 0 {
                try recordStudyTime(StudyActivity.grammar(0).timeBucket, seconds: seconds, now: now, calendar: calendar)
            }
        }
        return true
    }

    /// The topic's lesson has been read, here or (once synced) on iOS.
    func lessonRead(topicKey: String) -> Bool {
        records(KasusRoundRecord.self, naturalKey: KasusRoundRecord.lessonStoryID(topicKey: topicKey))
            .contains { $0.unitRaw == topicKey && $0.stepRaw == KasusRoundRecord.lessonStep }
    }

    private func addToDay(_ increments: [String: Int], stamp: Bool, now: Date, calendar: Calendar) throws {
        let increments = increments.filter { $0.value > 0 }
        guard !increments.isEmpty else { return }
        let dayStart = calendar.startOfDay(for: now)
        var day = studyDay(at: now, calendar: calendar) ?? StudyDayRecord(dayStart: dayStart, calendar: calendar)
        day.add(increments, at: stamp ? now : nil)
        try put(day, now: now)
    }
}
