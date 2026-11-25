//
//  RightAndFastTests.swift
//  german-ai-flashcardsTests
//
//  Roadmap phase 2 (docs/FSI_DLI_ROADMAP.md items 5–7): the easy round's place in the Today plan,
//  the answer-time percentiles, and the words-read estimate.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct RightAndFastTests {

    private func snapshot() -> TodaySnapshot {
        TodaySnapshot(dueCardCount: 0, weaknesses: [], hasCoachContent: false, streak: 1,
                      studiedToday: true, hasStartedLearning: true, dayIndex: 0)
    }

    @Test func easyRoundNeedsAKnownPoolAndAReason() {
        var s = snapshot()
        s.knownCardCount = 20
        #expect(!TodayPlanner.plan(s).contains { $0.id == "easy" }, "no hard session, no weak spots")
        s.hardSessionToday = true
        #expect(TodayPlanner.plan(s).contains { $0.id == "easy" })
        s.knownCardCount = 5
        #expect(!TodayPlanner.plan(s).contains { $0.id == "easy" }, "too few known cards")
    }

    @Test func easyRoundWhenThePlanIsAllWeakSpots() {
        var s = snapshot()
        s.knownCardCount = 12
        s.weaknesses = [.dativ, .akkusativ]
        let plan = TodayPlanner.plan(s)
        #expect(plan.contains { $0.id == "easy" })
        #expect(plan.first { $0.id == "easy" }?.intent == .easyRound(count: 10))
    }

    @Test func percentiles() {
        #expect(AnswerTimeLog.percentiles([1000, 2000, 3000, 4000, 5000], [0.5]) == [3000])
        #expect(AnswerTimeLog.percentiles([], [0.5]) == [0])
    }

    @Test func wordsReadAreCappedByTheStoryAndAReadingSpeed() {
        #expect(StoryProgressService.estimatedWordsRead(storyWords: 120, seconds: 600) == 120)
        #expect(StoryProgressService.estimatedWordsRead(storyWords: 120, seconds: 20) == 50)
    }

    @Test func easyReadingLevels() {
        #expect(CEFRLevel.a1.oneBelow == .a1)
        #expect(CEFRLevel.b1.oneBelow == .a2)
        #expect(CEFRLevel.a2.oneBelow.oneAbove == .a2)
        let prompt = StoryStudyService.storyPrompt(topic: "Markt", level: .a1, genre: .alltag, easyLength: .a2)
        #expect(prompt.user.contains("120–180"))
        #expect(prompt.user.contains("Leicht zu lesen"))
    }
}
