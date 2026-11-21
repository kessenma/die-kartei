//
//  FoerderplanService.swift
//  german-ai-flashcards
//
//  Förderplan (roadmap item 9, DLI-TI: a weak skill gets a written list of "deficiencies" and
//  "specific actions", then "a minimum of 10 days of tailored instruction"). Ten short daily tasks
//  on one grammar point, from the drills that exist, shown on Today. At the end, a re-check: the
//  coach's own struggle score for that point, then and now, written into the plan's record on the
//  profile.
//
//  Invariants:
//  - The plan never writes `profile.grammar`. The daily drills move it the ordinary way (that is
//    earned practice); the re-check only reads it. Estimated is not earned.
//  - Started by hand for now (Coach's Notes). An automatic suggestion waits for the weekly history
//    (`WeakSpotHistory`, Settings ▸ Developer ▸ Messungen) to show what "stays weak" looks like.
//

import Foundation
import SwiftData

nonisolated struct Foerderplan: Codable, Hashable, Sendable {
    var focusRaw: String
    var startedAt: Date
    /// The coach's struggle score when the plan began (0 solid … 1 shaky).
    var startStruggle: Double
    /// Days with the task done, as start-of-day dates. One counts per day.
    var doneDays: [Date] = []

    static let length = 10

    var focus: GrammarFocus? { GrammarFocus(rawValue: focusRaw) }
    var dayNumber: Int { min(Self.length, doneDays.count + 1) }
    var isFinished: Bool { doneDays.count >= Self.length }

    func doneToday(_ now: Date = .now) -> Bool {
        let today = Calendar.current.startOfDay(for: now)
        return doneDays.contains { Calendar.current.startOfDay(for: $0) == today }
    }

    /// What day `n` (1…10) asks: a 30-second explainer on days 1, 4 and 8, a drill round every day;
    /// day 10 is the re-check round.
    static func task(day n: Int) -> (title: String, withLesson: Bool) {
        if n == length { return ("Re-check: one round, then see how far it moved", false) }
        let lesson = [1, 4, 8].contains(n)
        return (lesson ? "The explainer, then a short round" : "A short round", lesson)
    }
}

nonisolated struct FoerderplanOutcome: Codable, Hashable, Sendable, Identifiable {
    var focusRaw: String
    var startedAt: Date
    var finishedAt: Date
    var startStruggle: Double
    var endStruggle: Double
    var id: Date { finishedAt }

    var focus: GrammarFocus? { GrammarFocus(rawValue: focusRaw) }
    var moved: Double { startStruggle - endStruggle }
}

nonisolated struct FoerderplanRecord: Codable, Hashable, Sendable {
    var current: Foerderplan?
    var history: [FoerderplanOutcome] = []
}

@MainActor
enum FoerderplanService {

    static func record(in context: ModelContext) -> FoerderplanRecord {
        let profile = LearnerMemoryService.profile(in: context)
        return profile.foerderplanData.flatMap { try? JSONDecoder().decode(FoerderplanRecord.self, from: $0) } ?? FoerderplanRecord()
    }

    private static func save(_ record: FoerderplanRecord, in context: ModelContext) {
        let profile = LearnerMemoryService.profile(in: context)
        profile.foerderplanData = try? JSONEncoder().encode(record)
        try? context.save()
    }

    static func current(in context: ModelContext) -> Foerderplan? { record(in: context).current }

    static func struggle(_ focus: GrammarFocus, in context: ModelContext) -> Double {
        LearnerMemoryService.profile(in: context).grammar[focus.rawValue]?.struggle ?? 0
    }

    /// Starts a plan on `focus`, replacing an unfinished one.
    static func start(_ focus: GrammarFocus, in context: ModelContext, now: Date = .now) {
        var r = record(in: context)
        r.current = Foerderplan(focusRaw: focus.rawValue, startedAt: now, startStruggle: struggle(focus, in: context))
        save(r, in: context)
    }

    static func stop(in context: ModelContext) {
        var r = record(in: context)
        r.current = nil
        save(r, in: context)
    }

    /// Marks today's task done (once a day). On the tenth day the plan closes with its re-check.
    static func markTodayDone(in context: ModelContext, now: Date = .now) {
        var r = record(in: context)
        guard var plan = r.current, !plan.doneToday(now) else { return }
        plan.doneDays.append(Calendar.current.startOfDay(for: now))
        if plan.isFinished, let focus = plan.focus {
            r.history.append(FoerderplanOutcome(focusRaw: plan.focusRaw, startedAt: plan.startedAt, finishedAt: now,
                                                startStruggle: plan.startStruggle,
                                                endStruggle: struggle(focus, in: context)))
            r.current = nil
        } else {
            r.current = plan
        }
        save(r, in: context)
    }

    /// The plan in plain words: the deficiency and the actions (DLI-TI's written list).
    static func writtenPlan(for focus: GrammarFocus) -> (deficiency: String, actions: [String]) {
        let deficiency = "\(focus.germanLabel) (\(focus.englishLabel.lowercased())) keeps slipping in your practice and conversations."
        let actions = [
            "Ten days, one short task a day, about five minutes.",
            "Days 1, 4 and 8 start with the 30-second explainer.",
            "Every day: a round of the \(focus.germanLabel) practice the app has.",
            "Day 10: a last round, then the coach's score for \(focus.germanLabel) then and now.",
        ]
        return (deficiency, actions)
    }
}
