//
//  ClassLoopPrereqTests.swift
//  german-ai-flashcardsTests
//
//  Roadmap phase 3: tutors read the class, Today plans from it, and her worksheet review plan.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct ClassLoopPrereqTests {

    @Test func reviewPlanSteps() {
        let sent = Date(timeIntervalSince1970: 1_000_000)
        #expect(WorksheetReviewPlan.dueStep(sentAt: nil, redone: [], now: sent) == nil)
        #expect(WorksheetReviewPlan.dueStep(sentAt: sent, redone: [], now: sent.addingTimeInterval(3_600)) == nil)
        #expect(WorksheetReviewPlan.dueStep(sentAt: sent, redone: [], now: sent.addingTimeInterval(90_000)) == 0)
        let first = sent.addingTimeInterval(90_000)
        #expect(WorksheetReviewPlan.dueStep(sentAt: sent, redone: [first], now: sent.addingTimeInterval(3 * 86_400)) == nil)
        #expect(WorksheetReviewPlan.dueStep(sentAt: sent, redone: [first], now: sent.addingTimeInterval(8 * 86_400)) == 1)
        let second = sent.addingTimeInterval(8 * 86_400)
        #expect(WorksheetReviewPlan.dueStep(sentAt: sent, redone: [first, second], now: sent.addingTimeInterval(30 * 86_400)) == nil)
        // A redo from before the worksheet was sent again doesn't count.
        #expect(WorksheetReviewPlan.dueStep(sentAt: sent, redone: [sent.addingTimeInterval(-10)], now: first) == 0)
    }

    @Test func mistakesPointAtTheirGrammar() {
        func wrong(_ reason: String, by: WorksheetCheck.Checker = .rules) -> WorksheetAnswer {
            var a = WorksheetAnswer(text: "den")
            a.check = WorksheetCheck(outcome: .wrong, correction: "dem", reason: reason, by: by, answer: "den")
            return a
        }
        let foci = WorksheetReviewPlan.mistakeFoci([
            wrong("mit + Dativ · Tisch → dem Tisch"),
            wrong("mit + Dativ · Haus → dem Haus"),
            wrong("Right article, but the case is Dativ. Subjekt → Nominativ"),
            wrong("From the teacher's answer key.", by: .key),
        ])
        #expect(foci.first?.focus == .praepositionen)
        #expect(foci.first?.count == 2)
        #expect(foci.contains { $0.focus == .dativ && $0.count == 1 })
        #expect(foci.count == 2, "key checks say nothing about grammar")
    }

    @Test func classContextReachesThePrompt() {
        var config = ConversationConfig(model: .hero)
        #expect(!ConversationPrompts.systemPrompt(for: config).contains("German class"))
        config.classContext = "Unterricht am 3. Mai: Dativ\\nGrammatik: Dativ"
        let prompt = ConversationPrompts.systemPrompt(for: config)
        #expect(prompt.contains("taking a German class"))
        #expect(prompt.contains("Grammatik: Dativ"))
    }

    @Test func todayPlansFromTheClass() {
        var s = TodaySnapshot(dueCardCount: 0, weaknesses: [.genitiv], hasCoachContent: false, streak: 1,
                              studiedToday: false, hasStartedLearning: true, dayIndex: 0)
        s.classFocus = .init(focus: .dativ, reason: "Covered in class this week")
        s.classWordsDue = 4
        let redoID = UUID()
        s.worksheetRedo = .init(materialID: redoID, title: "Dativ D1", step: 0)
        let plan = TodayPlanner.plan(s)
        #expect(plan.first?.intent == .worksheetRedo(materialID: redoID))
        #expect(plan.contains { $0.intent == .classWords(count: 4) })
        #expect(plan.contains { $0.intent == .grammar(.dativ) }, "the class's grammar wins over the weak spot")
        #expect(!plan.contains { $0.intent == .grammar(.genitiv) })
    }
}
