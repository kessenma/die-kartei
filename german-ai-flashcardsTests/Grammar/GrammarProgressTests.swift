//
//  GrammarProgressTests.swift
//  german-ai-flashcardsTests
//
//  The Fortschritt pane's aggregation over synthetic rounds: a read lesson is time but not a
//  listed row, the DEBUG verify rounds are neither, each (step, topic) is its own row, the two
//  drills that keep their own model get one row each, a reflexive round stays out of the case
//  bars, days bucket by local midnight, and the totals agree with what Verlauf sums.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Grammar progress")
struct GrammarProgressTests {

    // MARK: - Builders

    private func item(_ kasus: GrammarCase = .dativ, right: Bool = true) -> KasusRoundItem {
        KasusRoundItem(sentence: "Ich helfe dem Mann.", phraseStart: 10, phrase: "dem Mann", answer: "dem",
                       pick: right ? "dem" : "den", kasus: kasus, genus: .der,
                       outcome: right ? .right : .caseMiss, explanation: "why")
    }

    /// A played round of `step` in `topic`, filed the way the registry files it.
    private func round(_ step: KasusRoundStep, topic: String = "dativ", storyID: String? = nil,
                       asked: Int = 10, firstTry: Int = 8, seconds: Int = 120,
                       perCase: [GrammarCase: KasusRound.CaseTally] = [:],
                       date: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) -> KasusRound {
        let filed = step.roundID(topicKey: topic)
        return KasusRound(storyID: storyID ?? (filed.isEmpty ? "ks-dat-a2-schluessel" : filed),
                          unitRaw: topic, stepRaw: step.rawValue, askedCount: asked,
                          firstTryCount: firstTry, durationSeconds: seconds,
                          perCase: perCase, items: [], date: date)
    }

    private func article(asked: Int = 10, firstTry: Int = 7, seconds: Int = 61,
                         date: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) -> ArticleRound {
        // `init` hard-sets `date = Date()` and takes no `date:`, so assign it after.
        let round = ArticleRound(topic: "Goethe A1", questionCount: asked,
                                 firstTryCount: firstTry, durationSeconds: seconds)
        round.date = date
        return round
    }

    private func preposition(asked: Int = 12, firstTry: Int = 11, seconds: Int = 110,
                             date: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) -> PrepositionRound {
        let round = PrepositionRound(topic: "All Prepositions", questionCount: asked,
                                     firstTryCount: firstTry, durationSeconds: seconds)
        round.date = date
        return round
    }

    private func progress(kasus: [KasusRound] = [], articles: [ArticleRound] = [],
                          prepositions: [PrepositionRound] = []) -> GrammarProgress {
        GrammarProgress(kasus: kasus, articles: articles, prepositions: prepositions)
    }

    // MARK: - The predicate split

    @Test("A read lesson is grammar time but not a listed row; a verify round is neither")
    func predicateSplit() {
        let lesson = round(.lesson, asked: 0, firstTry: 0, seconds: 130)
        let real = round(.quick, asked: 10, firstTry: 8, seconds: 120)
        let debugRound = round(.quick, storyID: KasusService.debugVerifyStoryID,
                               asked: 99, firstTry: 99, seconds: 9_999)

        // The two predicates disagree on a lesson and agree on the other two.
        #expect(lesson.countsAsStudy && !lesson.isListed)
        #expect(real.countsAsStudy && real.isListed)
        #expect(!debugRound.countsAsStudy && !debugRound.isListed)

        let totals = progress(kasus: [lesson, real, debugRound])
        // The lesson's 130s is in, the verify round's 9999s is out.
        #expect(totals.totalSeconds == 250)
        #expect(totals.answers == 10)
        #expect(totals.rounds == 2)
    }

    @Test("A lesson row reports no percent rather than a fake zero")
    func lessonHasNoPercent() {
        let totals = progress(kasus: [round(.lesson, asked: 0, firstTry: 0, seconds: 130)])
        let row = try! #require(totals.exercises.first)
        #expect(row.answers == 0)
        #expect(row.firstTryPercent == nil)
        #expect(row.seconds == 130)
    }

    // MARK: - Grouping

    @Test("Five units' Schnellrunden are five rows, not one")
    func quickRoundsSplitByTopic() {
        let units: [KasusUnit] = KasusUnit.allCases
        let rounds = units.map { round(.quick, topic: $0.rawValue) }
        let totals = progress(kasus: rounds)

        #expect(totals.exercises.count == units.count)
        let ids = Set(totals.exercises.map(\.id))
        #expect(ids.count == units.count)
        for unit in units {
            #expect(ids.contains(.kasus(stepRaw: "quick", topicKey: unit.rawValue)))
        }
    }

    @Test("Story steps group by (step, topic), not by story — which is why roundID can't be the key")
    func storyStepsGroupByTopic() {
        // The registry files a story step under the story, so it has no round id of its own.
        #expect(KasusRoundStep.find.roundID(topicKey: "dativ").isEmpty)
        #expect(KasusRoundStep.fill.roundID(topicKey: "dativ").isEmpty)

        let totals = progress(kasus: [
            round(.find, storyID: "ks-dat-a2-schluessel", seconds: 100),
            round(.find, storyID: "ks-dat-b1-markt", seconds: 50),
        ])
        #expect(totals.exercises.count == 1)
        #expect(totals.exercises.first?.id == .kasus(stepRaw: "find", topicKey: "dativ"))
        #expect(totals.exercises.first?.rounds == 2)
        #expect(totals.exercises.first?.seconds == 150)
    }

    @Test("The two drills with their own model get one row each and never touch the case bars")
    func drillFamilies() {
        let totals = progress(kasus: [round(.quick, perCase: [.dativ: .init(asked: 10, firstTry: 8)])],
                              articles: [article(), article()],
                              prepositions: [preposition()])

        #expect(totals.exercises.contains { $0.id == .family(.article) })
        #expect(totals.exercises.contains { $0.id == .family(.preposition) })
        // Both article rounds fold into one row, despite being two rounds.
        let articles = try! #require(totals.exercises.first { $0.id == .family(.article) })
        #expect(articles.rounds == 2 && articles.answers == 20 && articles.seconds == 122)
        // Only the Kasus round's cases are in the bars.
        #expect(totals.perCase == [.dativ: .init(asked: 10, firstTry: 8)])
    }

    @Test("A reflexive round counts in the totals but not in the case bars")
    func reflexiveStaysOutOfTheBars() {
        let reflexive = round(.reflexCase, topic: GrammarTopic.reflexiv.key,
                              perCase: [.dativ: .init(asked: 6, firstTry: 4)])
        #expect(reflexive.unit == nil, "the reflexive topic is not a case unit")

        let totals = progress(kasus: [reflexive, round(.quick, perCase: [.dativ: .init(asked: 10, firstTry: 8)])])
        #expect(totals.answers == 20)
        #expect(totals.rounds == 2)
        // The reflexive round's six Dativ answers are deliberately absent.
        #expect(totals.perCase == [.dativ: .init(asked: 10, firstTry: 8)])
    }

    @Test("A Markieren round's class-sheet points stand in for its first-try count")
    func markingRoundScoresInPoints() {
        let marking = KasusRound(storyID: "ks-dat-a2-schluessel", unitRaw: "dativ",
                                 stepRaw: KasusRoundStep.find.rawValue, askedCount: 9,
                                 firstTryCount: 0, durationSeconds: 251,
                                 items: [], markCaseRaw: GrammarCase.dativ.rawValue, wrongCount: 2)
        let totals = progress(kasus: [marking])
        #expect(totals.firstTry == marking.markScore?.points)
    }

    // MARK: - Days

    @Test("Days bucket by local midnight, across all three models")
    func daysBucketByMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try! #require(TimeZone(identifier: "Europe/Berlin"))

        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        let lateSameDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 50))!
        let justAfterMidnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 0, minute: 10))!

        let totals = GrammarProgress(
            kasus: [round(.quick, seconds: 60, date: noon)],
            articles: [article(seconds: 30, date: lateSameDay)],
            prepositions: [preposition(seconds: 90, date: justAfterMidnight)],
            calendar: calendar
        )

        #expect(totals.days.count == 2)
        let first = calendar.startOfDay(for: noon)
        let second = calendar.startOfDay(for: justAfterMidnight)
        #expect(totals.days[first]?.seconds == 90)
        #expect(totals.days[first]?.rounds == 2)
        #expect(totals.days[second]?.seconds == 90)
        #expect(totals.days[second]?.rounds == 1)
        #expect(totals.activeDays == 2)
    }

    // MARK: - Ordering and agreement with Verlauf

    @Test("Rows are ordered by time spent, then by how recently they were played")
    func rowOrder() {
        let old = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let recent = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let totals = progress(kasus: [
            round(.quick, topic: "nominativ", seconds: 50, date: old),
            round(.fehler, topic: "dativ", seconds: 300, date: old),
            round(.blitz, topic: "akkusativ", seconds: 50, date: recent),
        ])
        #expect(totals.exercises.map(\.seconds) == [300, 50, 50])
        // Equal time: the one played more recently comes first.
        #expect(totals.exercises[1].id == .kasus(stepRaw: "blitz", topicKey: "akkusativ"))
    }

    @Test("The totals agree with what Verlauf sums over the same rounds, plus the lesson's time")
    func agreesWithVerlauf() {
        let lesson = round(.lesson, asked: 0, firstTry: 0, seconds: 130)
        let kasus = [round(.quick), round(.fehler, topic: "akkusativ", asked: 8, firstTry: 5), lesson]
        let articles = [article()]
        let prepositions = [preposition()]

        let totals = progress(kasus: kasus, articles: articles, prepositions: prepositions)
        let listed = GrammarHistoryEntry.all(kasus: kasus, articles: articles, prepositions: prepositions)

        // Verlauf drops the lesson from its rows, so it counts one fewer round and no fewer answers.
        #expect(listed.count == totals.rounds - 1)
        #expect(listed.reduce(0) { $0 + $1.asked } == totals.answers)
        #expect(listed.reduce(0) { $0 + $1.firstTry } == totals.firstTry)
    }
}
