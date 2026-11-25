//
//  DiagnoseTailorTests.swift
//  german-ai-flashcardsTests
//
//  Roadmap phase 5 (items 9–11): the Förderplan's ten days and its read-only re-check, the
//  monthly note, and Today's Förderplan and Hör-Check steps.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@MainActor
@Suite struct DiagnoseTailorTests {

    private func context() -> (ModelContainer, ModelContext) {
        let container = ModelContainer.inMemory([LearnerProfile.self, ArchivedMemoryItem.self])
        return (container, ModelContext(container))
    }

    @Test func tenDaysThenTheRecheckReadsTheScore() {
        let (container, ctx) = context()
        _ = container
        let profile = LearnerMemoryService.profile(in: ctx)
        var grammar = profile.grammar
        grammar[GrammarFocus.dativ.rawValue] = GrammarSkill(struggle: 0.5, lastSeen: .now, samples: [])
        profile.grammar = grammar

        FoerderplanService.start(.dativ, in: ctx)
        #expect(FoerderplanService.current(in: ctx)?.startStruggle == 0.5)
        let start = Calendar.current.startOfDay(for: .now)
        for day in 0..<9 {
            FoerderplanService.markTodayDone(in: ctx, now: start.addingTimeInterval(Double(day) * 86_400 + 3_600))
            // Twice on one day counts once.
            FoerderplanService.markTodayDone(in: ctx, now: start.addingTimeInterval(Double(day) * 86_400 + 7_200))
        }
        #expect(FoerderplanService.current(in: ctx)?.doneDays.count == 9)
        #expect(FoerderplanService.current(in: ctx)?.dayNumber == 10)

        // The drills moved the score the ordinary way; the plan only reads it.
        grammar = profile.grammar
        grammar[GrammarFocus.dativ.rawValue]?.struggle = 0.15
        profile.grammar = grammar
        FoerderplanService.markTodayDone(in: ctx, now: start.addingTimeInterval(9 * 86_400 + 3_600))
        let record = FoerderplanService.record(in: ctx)
        #expect(record.current == nil)
        #expect(record.history.first?.startStruggle == 0.5)
        #expect(record.history.first?.endStruggle == 0.15)
        #expect(profile.grammar[GrammarFocus.dativ.rawValue]?.struggle == 0.15, "the re-check writes no score")
    }

    @Test func taskShape() {
        #expect(Foerderplan.task(day: 1).withLesson)
        #expect(!Foerderplan.task(day: 2).withLesson)
        #expect(Foerderplan.task(day: 10).title.hasPrefix("Re-check"))
    }

    private func snapshot(_ days: Double, fill: Double, a1: Int, struggle: [String: Double]? = nil) -> ProgressSnapshot {
        ProgressSnapshot(takenAt: Date(timeIntervalSince1970: 1_800_000_000 + days * 86_400),
                         earnedFill: [PyramidLayerID.fundament.rawValue: fill], blueprintFill: 0.3,
                         learnedA1: a1, learnedA2: 0, solidCoreGrammar: 1, wellHeldConversations: 0,
                         streak: 3, level: 2, totalXP: Int(days) * 10, grammarStruggle: struggle)
    }

    @Test func monthlyNoteNeedsAMonth() {
        #expect(MonthlyNoteBuilder.note(snapshots: [snapshot(0, fill: 0.1, a1: 10), snapshot(14, fill: 0.2, a1: 20)],
                                        now: Date(timeIntervalSince1970: 1_800_000_000 + 15 * 86_400)) == nil)
        let note = MonthlyNoteBuilder.note(
            snapshots: [snapshot(0, fill: 0.1, a1: 10, struggle: ["dativ": 0.4, "akkusativ": 0.3]),
                        snapshot(28, fill: 0.25, a1: 40, struggle: ["dativ": 0.1, "akkusativ": 0.35])],
            now: Date(timeIntervalSince1970: 1_800_000_000 + 29 * 86_400))
        #expect(note != nil)
        #expect(note?.better.contains { $0.contains("+15%") } == true)
        #expect(note?.better.contains { $0.contains("30 more Goethe words") } == true)
        #expect(note?.better.contains { $0.contains("No longer shaky: Dativ") } == true)
        #expect(note?.next.first?.contains("Akkusativ") == true)
    }

    @Test func todaySteps() {
        var s = TodaySnapshot(dueCardCount: 0, weaknesses: [], hasCoachContent: false, streak: 1,
                              studiedToday: false, hasStartedLearning: true, dayIndex: 0)
        s.foerderplan = .init(focus: .dativ, day: 3)
        s.hoerCheckDue = true
        let plan = TodayPlanner.plan(s)
        #expect(plan.first?.intent == .foerderplan(day: 3))
        #expect(plan.contains { $0.intent == .hoerCheck })
    }
}
