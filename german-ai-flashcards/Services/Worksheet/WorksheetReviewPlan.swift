//
//  WorksheetReviewPlan.swift
//  german-ai-flashcards
//
//  Her review plan (docs/WORKSHEETS.md ▸ Wiederholen): a worksheet done and sent comes back the next
//  day and again a week later, with the answers hidden. And the grammar its checked mistakes point
//  at, for Today's class step. Pure, so the schedule is testable.
//

import Foundation

nonisolated enum WorksheetReviewPlan {
    /// After sending: a day, then a week.
    static let offsets: [TimeInterval] = [86_400, 7 * 86_400]

    /// The step due now (0 or 1), or nil: not sent, all steps done, or not yet time.
    static func dueStep(sentAt: Date?, redone: [Date], now: Date = .now) -> Int? {
        guard let sentAt else { return nil }
        let done = redone.filter { $0 >= sentAt }.count
        guard done < offsets.count else { return nil }
        return now >= sentAt.addingTimeInterval(offsets[done]) ? done : nil
    }

    /// The grammar the app's rule checks found wrong, most first. Only the article rules know the
    /// case they expected ("mit + Dativ · …"); key and tutor checks say nothing about grammar.
    /// A preposition in the reason points at Präpositionen, otherwise the case itself.
    static func mistakeFoci(_ answers: [WorksheetAnswer]) -> [(focus: GrammarFocus, count: Int)] {
        var counts: [GrammarFocus: Int] = [:]
        for answer in answers {
            guard let check = answer.check, check.outcome == .wrong, check.by == .rules,
                  let reason = check.reason else { continue }
            let lower = reason.lowercased()
            let kasus: GrammarFocus? =
                lower.contains("dativ") ? .dativ
                : lower.contains("akkusativ") ? .akkusativ
                : lower.contains("genitiv") ? .genitiv
                : nil
            guard let kasus else { continue }
            // "auf + Akkusativ" / "mit + Dativ": a preposition decided the case.
            let prepositional = reason.range(of: #"^\S+ \+ "#, options: .regularExpression) != nil
            counts[prepositional ? .praepositionen : kasus, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { (focus: $0.key, count: $0.value) }
    }
}
