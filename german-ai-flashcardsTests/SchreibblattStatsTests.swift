//
//  SchreibblattStatsTests.swift
//  german-ai-flashcardsTests
//
//  The writing numbers the checkpoint and the finish screen show (Services/SchreibblattStats.swift):
//  what each counts, what is left out, and the turn from one appearance to the next.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct SchreibblattStatsTests {

    typealias Stats = SchreibblattStats
    typealias Sheet = SchreibblattStats.Sheet

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// Noon on 24 November 2026, Berlin.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))!
    }

    private let haus = Sheet.Word(id: UUID(), german: "das Haus")
    private let hund = Sheet.Word(id: UUID(), german: "der Hund")
    private let buch = Sheet.Word(id: UUID(), german: "das Buch")

    private func day(_ offset: Int, _ words: Int) -> Stats.Day {
        Stats.Day(start: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!, words: words)
    }

    private func value(_ stats: Stats, _ kind: Stats.Stat.Kind) -> String? {
        stats.stats.first { $0.kind == kind }?.value
    }

    @Test func lastHourCountsOnlySheetsLoggedInTheHour() {
        let stats = Stats(sheets: [
            Sheet(loggedAt: now.addingTimeInterval(-600), words: [haus, hund], repetitions: 5, strokes: 40),
            Sheet(loggedAt: now.addingTimeInterval(-7200), words: [buch], repetitions: 5, strokes: 10),
        ], days: [day(0, 3)], now: now, calendar: calendar)
        #expect(value(stats, .lastHour) == "2")
    }

    @Test func byHandIsWordsTimesPasses() {
        let stats = Stats(sheets: [
            Sheet(loggedAt: now, words: [haus, hund], repetitions: 5, strokes: 0),
            Sheet(loggedAt: now, words: [buch], repetitions: 3, strokes: 0),
        ], days: [], now: now, calendar: calendar)
        #expect(value(stats, .byHand) == "13")
        // No strokes recorded: that number is left out rather than shown as 0.
        #expect(value(stats, .strokes) == nil)
    }

    @Test func totalsAndTheWeekComeFromTheSyncedLog() {
        let stats = Stats(sheets: [], days: [day(0, 10), day(-3, 20), day(-9, 1_200)], now: now, calendar: calendar)
        #expect(value(stats, .today) == "10")
        #expect(value(stats, .week) == "30")
        #expect(value(stats, .total) == "1.230")
    }

    @Test func theStreakCountsBackFromTodayOrYesterday() {
        let perDay = Dictionary(uniqueKeysWithValues: [day(-1, 4), day(-2, 4), day(-3, 4), day(-5, 4)]
            .map { ($0.start, $0.words) })
        let today = calendar.startOfDay(for: now)
        // Nothing yet today: the run up to yesterday still counts.
        #expect(Stats.streak(perDay: perDay, today: today, calendar: calendar) == 3)
        var withToday = perDay
        withToday[today] = 2
        #expect(Stats.streak(perDay: withToday, today: today, calendar: calendar) == 4)
    }

    @Test func aOneDayStreakIsNotShown() {
        let stats = Stats(sheets: [], days: [day(0, 5)], now: now, calendar: calendar)
        #expect(value(stats, .streak) == nil)
    }

    @Test func theTopWordNeedsTwoSheets() {
        let once = Stats(sheets: [Sheet(loggedAt: now, words: [haus, hund], repetitions: 1, strokes: 0)],
                         days: [], now: now, calendar: calendar)
        #expect(value(once, .topWord) == nil)
        let twice = Stats(sheets: [
            Sheet(loggedAt: now, words: [haus, hund], repetitions: 1, strokes: 0),
            Sheet(loggedAt: now, words: [hund, buch], repetitions: 1, strokes: 0),
        ], days: [], now: now, calendar: calendar)
        #expect(value(twice, .topWord) == "der Hund")
        #expect(value(twice, .distinct) == "3")
    }

    @Test func nothingWrittenHasNothingToShow() {
        let stats = Stats(sheets: [], days: [], now: now, calendar: calendar)
        #expect(stats.stats.isEmpty)
        #expect(stats.next(after: nil) == nil)
    }

    @Test func eachAppearanceShowsTheNextInTurnAndWraps() {
        let stats = Stats(sheets: [
            Sheet(loggedAt: now.addingTimeInterval(-60), words: [haus], repetitions: 2, strokes: 9),
        ], days: [day(0, 1)], now: now, calendar: calendar)
        let order = stats.stats.map(\.kind)
        #expect(order.first == .lastHour)
        #expect(stats.next(after: nil)?.kind == .lastHour)
        #expect(stats.next(after: "lastHour")?.kind == order[1])
        // From the last one shown, round to the first.
        #expect(stats.next(after: order.last?.rawValue)?.kind == order.first)
        // A kind with no number now is skipped over, not shown as nothing.
        #expect(stats.next(after: "streak").map { order.contains($0.kind) } == true)
    }
}
