//
//  ClassLoopTests.swift
//  german-ai-flashcardsTests
//
//  Roadmap phase 4 (items 12–17): the course schedule, teacher corrections as slips, the report
//  PDF, and Today's before/after class step.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct ClassLoopTests {

    private var cal: Calendar { Calendar.current }

    @Test func nextAndPreviousSession() {
        let monday = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9))!   // a Monday
        let raw = ClassSchedule.raw([2, 4])                                                    // Mon, Wed
        #expect(ClassSchedule.nextSessionDay(weekdaysRaw: raw, oneOff: nil, from: monday) == cal.startOfDay(for: monday))
        let tuesday = cal.date(byAdding: .day, value: 1, to: monday)!
        let wednesday = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: monday))!
        #expect(ClassSchedule.nextSessionDay(weekdaysRaw: raw, oneOff: nil, from: tuesday) == wednesday)
        #expect(ClassSchedule.previousSessionDay(weekdaysRaw: raw, from: wednesday) == cal.startOfDay(for: monday))
        // A one-off date wins when it is sooner; a past one is ignored.
        #expect(ClassSchedule.nextSessionDay(weekdaysRaw: raw, oneOff: tuesday, from: monday.addingTimeInterval(86_400)) == cal.startOfDay(for: tuesday))
        #expect(ClassSchedule.nextSessionDay(weekdaysRaw: "", oneOff: monday, from: tuesday) == nil)
        #expect(ClassSchedule.weekdays("2, 4,9") == [2, 4])
    }

    @Test func aTeacherCorrectionIsAClozeReadySlip() {
        let one = TeacherCorrectionStore.slip(for: TeacherCorrection(said: "Ich fahre mit der Bus", better: "Ich fahre mit dem Bus"))
        #expect(one.wrong == "der" && one.right == "dem")
        #expect(one.blankIndex == 3)
        #expect(one.source == MemorySource.teacher)
        let whole = TeacherCorrectionStore.slip(for: TeacherCorrection(said: "Ich habe gegangen", better: "Ich bin gegangen worden"))
        #expect(whole.right == "Ich bin gegangen worden")
    }

    @Test func reportPDF() {
        let data = TeacherReportPDF.data(String(repeating: "Zeile mit Text.\n", count: 200))
        #expect(data.map { String(decoding: $0.prefix(4), as: UTF8.self) } == "%PDF")
    }

    @Test func todayLeadsWithTheClass() {
        var s = TodaySnapshot(dueCardCount: 5, weaknesses: [], hasCoachContent: false, streak: 1,
                              studiedToday: false, hasStartedLearning: true, dayIndex: 0)
        let id = UUID()
        s.classSession = .init(courseID: id, courseName: "Deutsch A2", moment: .after, detail: "x")
        #expect(TodayPlanner.plan(s).first?.intent == .afterClass(courseID: id))
        s.classSession = .init(courseID: id, courseName: "Deutsch A2", moment: .before, detail: "x")
        #expect(TodayPlanner.plan(s).first?.title == "Vor der Stunde · Deutsch A2 tomorrow")
    }
}
