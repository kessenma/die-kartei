import Foundation
import Testing
@testable import DieKarteiCore

/// The study-day rules both apps run (`StudyDayCounts.swift`), over Android's `StudyDayRecord`.
/// The iOS side checks its `StudyDay` against the same rules in `StudyDayParityTests`.
@Suite struct StudyDayCountsTests {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    static func day(_ key: String, _ counts: [String: Int] = [:]) -> StudyDayRecord {
        var d = StudyDayRecord(day: key, lastActivityAt: SyncDayKey.dayStart(for: key)!)
        for (k, v) in counts { d[k] = v }
        return d
    }

    static func noon(_ key: String) -> Date { SyncDayKey.dayStart(for: key)!.addingTimeInterval(12 * 3600) }

    @Test func eachActivityCountsIntoItsField() {
        #expect(StudyDayTally.increments(for: .cards(5), seconds: 90) == ["cardsReviewed": 5, "cardSeconds": 90])
        #expect(StudyDayTally.increments(for: .grammar(3)) == ["grammarExercises": 3])
        #expect(StudyDayTally.increments(for: .conversation, seconds: 30) == ["conversations": 1, "conversationSeconds": 30])
        // Reading's seconds are its count; the seconds argument is ignored.
        #expect(StudyDayTally.increments(for: .storyReading(120), seconds: 999) == ["storySeconds": 120])
        #expect(StudyDayTally.increments(for: .storyQuestions(2), seconds: 40) == ["storyQuestions": 2, "storyQuizSeconds": 40])
        #expect(StudyDayTally.increments(for: .games(4), seconds: 60) == ["gameWordsSolved": 4, "gameSeconds": 60])
        #expect(StudyDayTally.increments(for: .drawing(1)) == ["wordsDrawn": 1])
        #expect(StudyDayTally.increments(for: .writing(20), seconds: 10) == ["wordsWritten": 20, "writingSeconds": 10])
        #expect(StudyDayTally.increments(for: .sheetWords(8), seconds: 10) == ["sheetWordsWritten": 8, "writingSeconds": 10])
        #expect(StudyDayTally.increments(for: .hoeren(6), seconds: 45) == ["hoerenItems": 6, "hoerenSeconds": 45])
        #expect(StudyDayTally.increments(for: .cards(-2), seconds: -5) == [:])
        #expect(StudyDayTally.increments(time: .conversation, seconds: 15) == ["conversationSeconds": 15])
    }

    @Test func everyFieldIsASyncedCounter() {
        let synced = Set(SyncKinds.studyDayCounterFields)
        #expect(Set(StudyDayTally.activityFields).isSubset(of: synced))
        #expect(Set(StudyDayTally.secondsFields).isSubset(of: synced))
        #expect(StudyDayTally.secondsFields.count == 9)
    }

    @Test func aDayIsActiveOnACountOrAMinute() {
        #expect(!Self.day("2026-11-27").hasActivity)
        #expect(Self.day("2026-11-27", ["cardsReviewed": 1]).hasActivity)
        #expect(!Self.day("2026-11-27", ["conversationSeconds": 59]).hasActivity)
        #expect(Self.day("2026-11-27", ["conversationSeconds": 30, "cardSeconds": 30]).hasActivity)
        // New words alone aren't study.
        #expect(!Self.day("2026-11-27", ["newWordsIntroduced": 10, "newWordsBonus": 10]).hasActivity)
        #expect(Self.day("2026-11-27", ["cardSeconds": 30, "storySeconds": 45, "hoerenSeconds": 5]).totalSeconds == 80)
    }

    @Test func theStreakRunsBackFromTodayOrYesterday() {
        let days = [Self.day("2026-11-24", ["cardsReviewed": 3]), Self.day("2026-11-25", ["grammarExercises": 1]),
                    Self.day("2026-11-26", ["hoerenItems": 2]), Self.day("2026-11-22", ["cardsReviewed": 1])]
        // Today (27th) not studied yet: the streak is alive from yesterday.
        #expect(StudyStreak.currentStreak(days, asOf: Self.noon("2026-11-27"), calendar: Self.cal) == 3)
        #expect(!StudyStreak.studiedToday(days, asOf: Self.noon("2026-11-27"), calendar: Self.cal))
        let withToday = days + [Self.day("2026-11-27", ["cardsReviewed": 1])]
        #expect(StudyStreak.currentStreak(withToday, asOf: Self.noon("2026-11-27"), calendar: Self.cal) == 4)
        #expect(StudyStreak.studiedToday(withToday, asOf: Self.noon("2026-11-27"), calendar: Self.cal))
        // A full day missed ends it.
        #expect(StudyStreak.currentStreak(days, asOf: Self.noon("2026-11-28"), calendar: Self.cal) == 0)
        #expect(StudyStreak.currentStreak([StudyDayRecord](), calendar: Self.cal) == 0)
    }

    @Test func timeSummaryCountsActiveDaysOnly() {
        let days = [Self.day("2026-11-24", ["cardSeconds": 600]), Self.day("2026-11-25", ["cardSeconds": 20]),
                    Self.day("2026-11-26", ["grammarSeconds": 300, "grammarExercises": 5])]
        let s = StudyStreak.timeSummary(days, from: SyncDayKey.dayStart(for: "2026-11-24")!,
                                        to: SyncDayKey.dayStart(for: "2026-11-27")!)
        #expect(s.totalSeconds == 900)
        #expect(s.activeDays == 2)
        #expect(s.averageSeconds == 450)
    }

    @Test func theNewWordBudgetIsPerDay() {
        let days = [Self.day("2026-11-27", ["newWordsIntroduced": 12, "newWordsBonus": 10]),
                    Self.day("2026-11-26", ["newWordsIntroduced": 15])]
        #expect(StudyStreak.newWordBudgetRemaining(days, newPerDay: 15, asOf: Self.noon("2026-11-27"), calendar: Self.cal) == 13)
        #expect(StudyStreak.newWordBudgetRemaining(days, newPerDay: 15, asOf: Self.noon("2026-11-28"), calendar: Self.cal) == 15)
        #expect(StudyStreak.newWordBudgetRemaining(days, newPerDay: 5, asOf: Self.noon("2026-11-26"), calendar: Self.cal) == 0)
    }

    @Test func addingStampsOnlyStudy() {
        var d = Self.day("2026-11-27")
        let t = Self.noon("2026-11-27")
        d.add(["newWordsIntroduced": 2], at: nil)
        #expect(d.lastActivityAt == SyncDayKey.dayStart(for: "2026-11-27")!)
        d.add(StudyDayTally.increments(for: .cards(2), seconds: 30), at: t)
        #expect(d.lastActivityAt == t)
        #expect(d.cardsReviewed == 2 && d.cardSeconds == 30 && d.newWordsIntroduced == 2)
    }
}
