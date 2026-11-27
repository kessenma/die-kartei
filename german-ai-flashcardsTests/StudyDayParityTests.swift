//
//  StudyDayParityTests.swift
//  german-ai-flashcardsTests
//
//  iOS's `StudyDay` runs the shared study-day rules (`StudyDayCounts.swift`) that Android's
//  `StudyDayRecord` runs: the same activity lands in the same counters on both, and every counter
//  the row has is one sync carries.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@MainActor
@Suite struct StudyDayParityTests {
    @Test func everyCounterIsMappedOnce() {
        #expect(Set(StudyDay.counters.keys) == Set(SyncKinds.studyDayCounterFields))
        #expect(StudyDay.counters.count == SyncKinds.studyDayCounterFields.count)
    }

    static let activities: [(StudyActivity, Int)] = [
        (.cards(5), 90), (.grammar(3), 40), (.conversation, 0), (.storyReading(120), 0),
        (.storyQuestions(2), 30), (.games(4), 60), (.drawing(1), 20), (.writing(20), 0),
        (.sheetWords(8), 0), (.hoeren(6), 45),
    ]

    /// `StudyLogService.record` on iOS and `StudyDayRecord.add` (Android) produce the same payload.
    @Test func bothAppsCountTheSameDay() throws {
        let context = ModelContext(ModelContainer.inMemory([StudyDay.self]))
        let dayStart = Calendar.current.startOfDay(for: Date())
        var record = StudyDayRecord(dayStart: dayStart)
        for (activity, seconds) in Self.activities {
            StudyLogService.record(activity, seconds: seconds, in: context)
            record.add(StudyDayTally.increments(for: activity, seconds: seconds), at: Date())
        }
        StudyLogService.recordTime(.conversation, seconds: 75, in: context)
        record.add(StudyDayTally.increments(time: .conversation, seconds: 75), at: Date())
        StudyLogService.recordNewWords(3, in: context)
        record.add(["newWordsIntroduced": 3], at: nil)

        let day = try #require(try context.fetch(FetchDescriptor<StudyDay>()).first)
        var ios = StudyDayCodec.known(day)
        var android = record.payload
        // Stamped a moment apart; everything else must match.
        ios["lastActivityAt"] = nil
        android["lastActivityAt"] = nil
        #expect(ios == android)
        #expect(day.hasActivity && record.hasActivity)
        #expect(day.totalSeconds == record.totalSeconds)
        #expect(StudyLogService.currentStreak([day]) == StudyStreak.currentStreak([record]))
    }
}
