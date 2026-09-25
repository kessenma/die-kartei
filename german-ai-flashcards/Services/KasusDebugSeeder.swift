#if DEBUG
import Foundation
import SwiftData

/// `-kasus.debugSeedRounds 1`: most of a week of grammar rounds, so Verlauf, a round's detail, a
/// unit's "Deine Runden" and the hub's dots have something to show in a simulator that can't play
/// a story. The Kasus rounds are built by the real service from the bundled story and from the
/// Schnellrunde's own questions, so their sentences and explanations are the app's; one Schnellrunde
/// is stored without answers, the way rounds from before Verlauf look.
///
/// Today's story rounds are the current exercises: Markieren in the Dativ (Am Ende, with misses and
/// wrong marks), Markieren in the Akkusativ (Sofort, all right) and Endungen at Genus-Hilfe (Am
/// Ende, answers shown afterwards). Three days ago is an Einsetzen from before Endungen, so the
/// history's old labels have something to show too.
///
/// Only rounds are inserted: no streak, XP or coach change. The story rounds use the real story
/// id, so they do mark its Markieren and Endungen as played. Idempotent: the seeded rows' dates are
/// remembered in UserDefaults, and a run that finds them does nothing. `-kasus.debugSeedRounds
/// remove` deletes exactly those rows.
enum KasusDebugSeeder {
    private static let datesKey = "kasus.debugSeededRoundDates"

    static func run(_ argument: String, in context: ModelContext) -> String {
        argument.lowercased() == "remove" ? remove(in: context) : seed(in: context)
    }

    static func seed(in context: ModelContext) -> String {
        let found = seeded(in: context)
        if found.count > 0 {
            return "already seeded (\(found.count) rounds); -kasus.debugSeedRounds remove takes them out"
        }
        guard let story = KasusStoryBank.bundled.story(id: "ks-dat-a2-schluessel") ?? KasusStoryBank.bundled.stories.first,
              let unit = story.unit else {
            return "no bundled story to build rounds from"
        }
        let playable = KasusService.prepare(story)
        let now = Date()
        let calendar = Calendar.current
        func day(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            let start = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
        }

        var kasus: [KasusRound] = []

        // Today: Markieren in the unit's case with one phrase in four missed and a few wrong marks,
        // then „Nächster Fall“ all right in Sofort, then Endungen at Genus-Hilfe with about one gap
        // in three wrong, checked at the end, and Lösung zeigen afterwards.
        let cases = KasusService.markCases(in: playable, unit: unit)
        if let first = cases.first {
            var mark = KasusService.markRound(first, in: playable, mode: .amEnde)
            for id in KasusService.debugMarks(for: mark, answers: .mixed) { mark.tap(id) }
            mark.check()
            let find = KasusService.markResult(mark, storyID: story.id, unit: unit, in: playable, durationSeconds: 251)
            kasus.append(KasusService.round(for: find, date: now.addingTimeInterval(-55 * 60)))
        }
        if cases.count > 1 {
            var next = KasusService.markRound(cases[1], in: playable, mode: .sofort)
            for id in KasusService.debugMarks(for: next, answers: .right) { next.tap(id) }
            next.check()
            let find = KasusService.markResult(next, storyID: story.id, unit: unit, in: playable, durationSeconds: 140)
            kasus.append(KasusService.round(for: find, date: now.addingTimeInterval(-50 * 60)))
        }

        var endings = KasusService.endingsRound(in: playable, unit: unit, mixed: false, hint: .genus, mode: .amEnde)
        for (id, ending) in KasusService.debugEndingPicks(for: endings.gaps, answers: .mixed) {
            endings.choose(ending, for: id)
        }
        endings.check()
        let fill = KasusService.endingsResult(endings, storyID: story.id, unit: unit, durationSeconds: 204, story: story)
        let filled = KasusService.round(for: fill, date: now.addingTimeInterval(-40 * 60))
        filled.applyAnswersShown()
        kasus.append(filled)

        // Yesterday and the day before: two Schnellrunden.
        kasus.append(quickRound(.nominativ, wrongEvery: 7, seconds: 68, date: day(1, 19, 40)))
        kasus.append(quickRound(.akkusativ, wrongEvery: 3, seconds: 97, date: day(2, 18, 5)))

        // Three days ago: an Einsetzen from before Endungen, gemischt at Ohne Hilfe, one gap in
        // five wrong. No feedback mode, so the history labels it „Einsetzen“.
        let ohne = KasusService.blanks(in: playable, unit: unit, mixed: true, hint: .ohne)
        var ohnePicks: [Int: String] = [:]
        for (i, blank) in ohne.enumerated() {
            let wrong = blank.options.filter { KasusService.grade($0, for: blank) != .right }
            ohnePicks[blank.id] = i % 5 == 4 ? (wrong.first ?? blank.answer) : blank.answer
        }
        let mixed = KasusService.fillResult(storyID: story.id, unit: unit, hint: .ohne, blanks: ohne,
                                            picks: ohnePicks, durationSeconds: 342, story: story)
        kasus.append(KasusService.round(for: mixed, date: day(3, 20, 15)))

        // Five days ago: a Dativ Schnellrunde stored the old way, with counts and no answers.
        kasus.append(KasusRound(
            storyID: KasusService.quickRoundID(for: .dativ), unitRaw: KasusUnit.dativ.rawValue,
            stepRaw: KasusRoundStep.quick.rawValue, askedCount: 10, firstTryCount: 6, durationSeconds: 95,
            perCase: [.nominativ: .init(asked: 2, firstTry: 2), .akkusativ: .init(asked: 3, firstTry: 2),
                      .dativ: .init(asked: 5, firstTry: 2)],
            date: day(5, 8, 30)
        ))

        let articles = [
            article("Goethe A1", 10, 8, 61, day(1, 20, 10)),
            article("Tricky Nouns", 10, 6, 83, day(4, 12, 45)),
        ]
        let prepositions = [
            preposition("Akkusativ or Dativ", 10, 7, 88, day(2, 18, 20)),
            preposition("All Prepositions", 12, 11, 110, day(6, 9, 0)),
        ]

        for row in kasus { context.insert(row) }
        for row in articles { context.insert(row) }
        for row in prepositions { context.insert(row) }
        try? context.save()

        let dates = kasus.map(\.date) + articles.map(\.date) + prepositions.map(\.date)
        UserDefaults.standard.set(dates.map(\.timeIntervalSinceReferenceDate), forKey: datesKey)
        let withAnswers = kasus.filter { $0.itemsData != nil }.count
        return "seeded \(kasus.count) Kasus rounds (\(withAnswers) with answers), "
            + "\(articles.count) der/die/das and \(prepositions.count) preposition rounds"
    }

    static func remove(in context: ModelContext) -> String {
        let found = seeded(in: context)
        for row in found { context.delete(row) }
        try? context.save()
        UserDefaults.standard.removeObject(forKey: datesKey)
        return "removed \(found.count) seeded rounds"
    }

    // MARK: - Pieces

    /// A Schnellrunde over the unit's cases, every `wrongEvery`-th question answered with another
    /// of its buttons.
    private static func quickRound(_ unit: KasusUnit, wrongEvery: Int, seconds: Int, date: Date) -> KasusRound {
        let session = CaseEndingsSession(unit: unit)
        let questions = EndingsQuestion.round(cases: session.cases, emphasis: session.emphasis)
        let items = questions.enumerated().map { i, q -> KasusItemResult in
            let others = q.options.filter { $0 != q.answer }
            let pick = i % wrongEvery == wrongEvery - 1 && !others.isEmpty ? others[i % others.count] : q.answer
            let isAnswer = pick == q.answer
            return KasusItemResult(kasus: q.kasus, genus: q.gender, firstTry: isAnswer,
                                   slip: !isAnswer && q.isGenderSlip(pick), record: q.roundItem(pick: pick))
        }
        return KasusService.round(for: KasusService.quickResult(unit: unit, items: items, durationSeconds: seconds),
                                  date: date)
    }

    private static func article(_ topic: String, _ count: Int, _ firstTry: Int, _ seconds: Int,
                                _ date: Date) -> ArticleRound {
        let round = ArticleRound(topic: topic, questionCount: count, firstTryCount: firstTry, durationSeconds: seconds)
        round.date = date
        return round
    }

    private static func preposition(_ topic: String, _ count: Int, _ firstTry: Int, _ seconds: Int,
                                    _ date: Date) -> PrepositionRound {
        let round = PrepositionRound(topic: topic, questionCount: count, firstTryCount: firstTry,
                                     durationSeconds: seconds)
        round.date = date
        return round
    }

    /// The rows an earlier seed inserted, found by their remembered dates.
    private static func seeded(in context: ModelContext) -> [any PersistentModel] {
        let stored = (UserDefaults.standard.array(forKey: datesKey) as? [Double]) ?? []
        guard !stored.isEmpty else { return [] }
        func isSeeded(_ date: Date) -> Bool {
            stored.contains { abs($0 - date.timeIntervalSinceReferenceDate) < 0.001 }
        }
        let kasus: [any PersistentModel] = ((try? context.fetch(FetchDescriptor<KasusRound>())) ?? [])
            .filter { isSeeded($0.date) }
        let articles: [any PersistentModel] = ((try? context.fetch(FetchDescriptor<ArticleRound>())) ?? [])
            .filter { isSeeded($0.date) }
        let prepositions: [any PersistentModel] = ((try? context.fetch(FetchDescriptor<PrepositionRound>())) ?? [])
            .filter { isSeeded($0.date) }
        return kasus + articles + prepositions
    }
}
#endif
