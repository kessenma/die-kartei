import Foundation
import Testing
@testable import DieKarteiCore
@testable import KarteiStore

@MainActor
@Suite("StudyLog")
struct StudyLogTests {
    func store(replica: String = "android-a") throws -> (RecordStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kartei-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("kartei.sqlite")
        return (RecordStore(database: try KarteiDatabase(url: url), replica: replica), url)
    }

    static func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    @Test("A session adds to today's record, survives a reopen, and starts the streak")
    func sessionsLandInToday() throws {
        var (records, url) = try store()
        let now = Date()
        try records.recordStudy(.cards(5), seconds: 120, now: now)
        try records.recordStudy(.grammar(3), seconds: 45, now: now)
        try records.recordStudyTime(.conversation, seconds: 30, now: now)
        try records.recordNewWords(4, now: now)
        try records.database.close()

        records = RecordStore(database: try KarteiDatabase(url: url), replica: "android-a")
        let day = try #require(records.studyDay(at: now))
        #expect(day.cardsReviewed == 5 && day.cardSeconds == 120)
        #expect(day["grammarExercises"] == 3 && day["grammarSeconds"] == 45)
        #expect(day["conversationSeconds"] == 30)
        #expect(day.newWordsIntroduced == 4)
        #expect(records.count(kind: "StudyDay") == 1)
        #expect(StudyStreak.currentStreak(records.studyDays(from: now.addingTimeInterval(-30 * 86400), to: now), asOf: now) == 1)
        #expect(StudyStreak.newWordBudgetRemaining([day], newPerDay: 15, asOf: now) == 11)
    }

    @Test("The day is the learner's local date: past midnight in Berlin is still the 27th in New York")
    func daysFollowTheLocalDate() throws {
        let (records, _) = try store()
        let berlin = Self.calendar("Europe/Berlin"), newYork = Self.calendar("America/New_York")
        // 2026-11-28 00:30 in Berlin = 2026-11-27 18:30 in New York.
        let instant = berlin.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 0, minute: 30))!
        try records.recordStudy(.cards(1), now: instant, calendar: berlin)
        try records.recordStudy(.hoeren(2), now: instant, calendar: newYork)
        #expect(records.studyDay(at: instant, calendar: berlin)?.day == "2026-11-28")
        #expect(records.studyDay(at: instant, calendar: berlin)?.cardsReviewed == 1)
        #expect(records.studyDay(at: instant, calendar: newYork)?.day == "2026-11-27")
        #expect(records.studyDay(at: instant, calendar: newYork)?["hoerenItems"] == 2)
        #expect(records.studyDays(from: instant.addingTimeInterval(-86400 * 2), to: instant.addingTimeInterval(86400),
                                  calendar: berlin).map(\.day) == ["2026-11-27", "2026-11-28"])
    }

    @Test("Study counts in this install's slot; new words don't stamp the day")
    func countsArePerDevice() throws {
        let (records, _) = try store(replica: "phone-1")
        let morning = Date(timeIntervalSinceReferenceDate: 816_000_000)
        try records.recordStudy(.cards(3), seconds: 60, now: morning)
        try records.recordStudy(.cards(2), seconds: 30, now: morning.addingTimeInterval(600))
        try records.recordNewWords(2, now: morning.addingTimeInterval(1200))
        let day = try #require(records.studyDay(at: morning))
        #expect(day.lastActivityAt == morning.addingTimeInterval(600))
        let pending = try #require(records.copies(of: day.name)?.pending)
        #expect(SyncCounter(json: pending["cardsReviewed"]).p["phone-1"] == 5)
        #expect(SyncCounter(json: pending["cardSeconds"]).p["phone-1"] == 90)
        #expect(SyncCounter(json: pending["newWordsIntroduced"]).p["phone-1"] == 2)
    }

    @Test("Reading a lesson through files iOS's lesson round once and banks the time as grammar")
    func lessonReadIsFiledOnce() throws {
        let (records, _) = try store()
        let now = Date()
        #expect(!records.lessonRead(topicKey: "akkusativ"))
        #expect(try records.recordLessonRead(topicKey: "akkusativ", seconds: 95, now: now))
        #expect(records.lessonRead(topicKey: "akkusativ"))
        #expect(!records.lessonRead(topicKey: "dativ"))
        #expect(try !records.recordLessonRead(topicKey: "akkusativ", seconds: 40, now: now))
        #expect(records.studyDay(at: now)?["grammarSeconds"] == 95)
        #expect(records.count(kind: "KasusRound") == 1)
    }
}
