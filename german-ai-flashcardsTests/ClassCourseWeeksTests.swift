//
//  ClassCourseWeeksTests.swift
//  german-ai-flashcardsTests
//
//  A course's length in weeks and its end date are two views of one fact: the course editor sets
//  either and derives the other (`ClassCourse.endDate(start:weeks:calendar:)` and
//  `ClassCourse.weeks(start:end:calendar:)`). The trap is a course that starts mid-week, where
//  "start + 7·N days" lands in week N+1 by the "Woche N" count the entries use. So the round trip
//  runs for every start weekday under both a Sunday-first and a Monday-first calendar.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct ClassCourseWeeksTests {

    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// Seven consecutive days, so every weekday is a start once.
    private static func starts(in calendar: Calendar) -> [Date] {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
    }

    @Test(arguments: [1, 2])
    func weeksRoundTripForEveryStartDay(firstWeekday: Int) {
        let calendar = Self.calendar(firstWeekday: firstWeekday)
        for start in Self.starts(in: calendar) {
            for weeks in [1, 2, 10, 14, 15, 52] {
                let end = ClassCourse.endDate(start: start, weeks: weeks, calendar: calendar)
                #expect(end >= calendar.startOfDay(for: start))
                #expect(ClassCourse.weeks(start: start, end: end, calendar: calendar) == weeks,
                        "start \(start), \(weeks) weeks, end \(end)")
                // The end is the last day of its week: one more day is the next "Woche".
                let dayAfter = calendar.date(byAdding: .day, value: 1, to: end)!
                #expect(ClassCourse.weekNumber(of: dayAfter, start: start, calendar: calendar) == weeks + 1)
            }
        }
    }

    @Test func endDateMatchesTheWeekLabelsEntriesUse() {
        let calendar = Self.calendar(firstWeekday: 2)
        // A Wednesday start, ten weeks: the entries on the course's last day read "Woche 10".
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        let end = ClassCourse.endDate(start: wednesday, weeks: 10, calendar: calendar)
        #expect(ClassCourse.weekNumber(of: end, start: wednesday, calendar: calendar) == 10)
        #expect(ClassCourse.weekNumber(of: wednesday, start: wednesday, calendar: calendar) == 1)
    }

    @Test func anEndBeforeTheStartCountsAsOneWeek() {
        let calendar = Self.calendar(firstWeekday: 2)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        let earlier = calendar.date(byAdding: .day, value: -20, to: start)!
        #expect(ClassCourse.weeks(start: start, end: earlier, calendar: calendar) == 1)
    }
}
