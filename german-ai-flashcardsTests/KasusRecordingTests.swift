//
//  KasusRecordingTests.swift
//  german-ai-flashcardsTests
//
//  What a finished round moves. Every answer counts for the streak; the coach's case skill only
//  hears about unscaffolded first picks, at least three per case, never slips, never Markieren (or
//  the old Finden), never Lernhilfe or Viel Hilfe, never an answer Lösung zeigen showed, and
//  Nominativ has no skill at all. The same fifteen rounds `-kasus.debugVerifyRecord 1` runs, here
//  against an in-memory store instead of the live one. Also: Lösung zeigen after recording flags
//  the same row, and older rounds (no new fields) still read.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@Suite("Kasus recording")
struct KasusRecordingTests {

    private func item(_ kasus: GrammarCase, _ genus: Gender, _ right: Bool,
                      slip: Bool = false, tipp: KasusTipp = .none, revealed: Bool = false) -> KasusItemResult {
        KasusItemResult(kasus: kasus, genus: genus, firstTry: right, slip: slip, tipp: tipp, revealed: revealed)
    }

    /// Markieren: 10 Dativ words, 8 marked, 2 other words marked.
    private var marking: KasusRoundResult {
        KasusRoundResult(storyID: "test", unit: .dativ, step: .find, items: [], durationSeconds: 30,
                         feedbackMode: .amEnde, markCase: .dativ,
                         markScore: KasusMarkScore(caseWords: 10, right: 8, wrong: 2))
    }

    private func round(_ step: KasusRoundStep, _ unit: KasusUnit, _ hint: KasusHintLevel?,
                       _ items: [KasusItemResult], painted: Int? = nil) -> KasusRoundResult {
        KasusRoundResult(storyID: "test", unit: unit, step: step, hintLevel: hint, items: items,
                         durationSeconds: 30, paintedCount: painted)
    }

    /// A fresh store with just the rows `recordRound` touches. The container is returned too, so it
    /// outlives the context.
    private func store() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try ModelContainer(for: LearnerProfile.self, StudyDay.self, KasusRound.self,
                                           configurations: SwiftData.ModelConfiguration(isStoredInMemoryOnly: true))
        return (container, ModelContext(container))
    }

    private func grammarExercises(_ context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<StudyDay>()).reduce(0) { $0 + $1.grammarExercises }
    }

    private func skills(_ context: ModelContext) throws -> [String: GrammarSkill] {
        try context.fetch(FetchDescriptor<LearnerProfile>()).first?.grammar ?? [:]
    }

    /// The debug record check's rounds: #1–#13 move nothing, #14 moves Dativ, #15 Akkusativ.
    private var scenarios: [(name: String, result: KasusRoundResult, moves: Set<GrammarFocus>)] {
        [
            ("Viel Hilfe · 5 Akk m, all wrong (scaffolded)",
             round(.fill, .akkusativ, .viel, Array(repeating: item(.akkusativ, .der, false), count: 5)), []),
            ("Ohne Hilfe · 2 Dat, both wrong (under 3)",
             round(.fill, .dativ, .ohne, Array(repeating: item(.dativ, .die, false), count: 2)), []),
            ("Genus-Hilfe · 5 Akk f/n/pl, all wrong (the tag gives them away)",
             round(.fill, .akkusativ, .genus, [.die, .das, .plural, .die, .das].map { item(.akkusativ, $0, false) }), []),
            ("Ohne Hilfe · 4 Akk m, the Tipp showed the case or the answer",
             round(.fill, .akkusativ, .ohne, [KasusTipp.kasus, .answer, .kasus, .answer].map {
                 item(.akkusativ, .der, false, tipp: $0)
             }), []),
            ("Ohne Hilfe · 4 Dat gender slips",
             round(.fill, .dativ, .ohne, Array(repeating: item(.dativ, .die, false, slip: true), count: 4)), []),
            ("Ohne Hilfe · 4 Akk f/n/pl, the Tipp showed the gender",
             round(.fill, .akkusativ, .ohne, [.die, .das, .plural, .die].map {
                 item(.akkusativ, $0, false, tipp: .gender)
             }), []),
            ("Schnellrunde · 6 Nom, all wrong (Nominativ has no skill)",
             round(.quick, .nominativ, nil, Array(repeating: item(.nominativ, .der, false), count: 6)), []),
            ("Schnellrunde · 4 Akk f/n/pl (the header names the article)",
             round(.quick, .akkusativ, nil, [.die, .das, .plural, .die].map { item(.akkusativ, $0, false) }), []),
            ("Schnellrunde · 4 Dat gender slips",
             round(.quick, .dativ, nil, Array(repeating: item(.dativ, .die, false, slip: true), count: 4)), []),
            ("Finden · 6 Akk + 6 Dat marked, 5 painted (recognition only)",
             round(.find, .dativ, nil, Array(repeating: item(.akkusativ, .der, false), count: 6)
                   + Array(repeating: item(.dativ, .der, false), count: 6), painted: 5), []),
            ("Lernhilfe · 5 Akk m, all wrong (never counts)",
             round(.fill, .akkusativ, .lern, Array(repeating: item(.akkusativ, .der, false), count: 5)), []),
            ("Ohne Hilfe · 2 Dat wrong + 4 Dat Lösung zeigen filled (2 answered, under 3)",
             round(.fill, .dativ, .ohne, Array(repeating: item(.dativ, .die, false), count: 2)
                   + Array(repeating: item(.dativ, .die, false, revealed: true), count: 4)), []),
            ("Markieren · Dativ, 8 of 10 words + 2 wrong marks (recognition only)", marking, []),
            ("Ohne Hilfe · 4 Dat wrong + 2 Nom → moves Dativ",
             round(.fill, .dativ, .ohne, Array(repeating: item(.dativ, .die, false), count: 4)
                   + Array(repeating: item(.nominativ, .die, false), count: 2)), [.dativ]),
            ("Genus-Hilfe · 3 Akk m wrong + 3 Akk f → moves Akkusativ (m only, exactly 3)",
             round(.fill, .akkusativ, .genus, Array(repeating: item(.akkusativ, .der, false), count: 3)
                   + Array(repeating: item(.akkusativ, .die, true), count: 3)), [.akkusativ]),
        ]
    }

    // MARK: The rules, pure

    @Test("Which answers may move the coach")
    func countsTowardSkill() {
        func counts(_ item: KasusItemResult, _ step: KasusRoundStep, _ hint: KasusHintLevel? = nil) -> Bool {
            KasusService.countsTowardSkill(item, step: step, hint: hint)
        }
        // Finden is recognition, and Nominativ has no skill.
        #expect(!counts(item(.dativ, .der, true), .find))
        #expect(!counts(item(.nominativ, .der, true), .fill, .ohne))
        #expect(!counts(item(.nominativ, .der, true), .quick))
        // Slips say nothing about the case.
        #expect(!counts(item(.dativ, .der, false, slip: true), .fill, .ohne))
        #expect(!counts(item(.dativ, .der, false, slip: true), .quick))
        // Viel Hilfe never; Genus-Hilfe only masculine.
        #expect(!counts(item(.akkusativ, .der, true), .fill, .viel))
        #expect(counts(item(.akkusativ, .der, true), .fill, .genus))
        #expect(!counts(item(.akkusativ, .die, true), .fill, .genus))
        #expect(!counts(item(.dativ, .plural, true), .fill, .genus))
        // Ohne Hilfe: unless the Tipp showed the case or answer, or an f/n/pl Akkusativ's gender.
        #expect(counts(item(.dativ, .die, true), .fill, .ohne))
        #expect(counts(item(.dativ, .die, true, tipp: .trigger), .fill, .ohne))
        #expect(counts(item(.dativ, .die, true, tipp: .gender), .fill, .ohne))
        #expect(counts(item(.akkusativ, .der, true, tipp: .gender), .fill, .ohne))
        #expect(!counts(item(.akkusativ, .das, true, tipp: .gender), .fill, .ohne))
        #expect(!counts(item(.genitiv, .der, true, tipp: .kasus), .fill, .ohne))
        #expect(!counts(item(.genitiv, .der, true, tipp: .answer), .fill, .ohne))
        // Lernhilfe never, whatever the gender; an answer Lösung zeigen showed, or a gap left
        // empty, never either.
        #expect(!counts(item(.akkusativ, .der, true), .fill, .lern))
        #expect(!counts(item(.dativ, .die, false), .fill, .lern))
        #expect(!counts(item(.dativ, .die, false, revealed: true), .fill, .ohne))
        #expect(!counts(KasusItemResult(kasus: .dativ, genus: .die, firstTry: false, unanswered: true), .fill, .ohne))
        #expect(!counts(item(.akkusativ, .der, false, revealed: true), .fill, .genus))
        #expect(KasusHintLevel.lern.neverCountsTowardSkill && KasusHintLevel.viel.neverCountsTowardSkill)
        #expect(!KasusHintLevel.genus.neverCountsTowardSkill && !KasusHintLevel.ohne.neverCountsTowardSkill)
        // The Schnellrunde names the noun with its article.
        #expect(counts(item(.akkusativ, .der, false), .quick))
        #expect(!counts(item(.akkusativ, .plural, false), .quick))
        #expect(counts(item(.dativ, .die, false), .quick))
        #expect(counts(item(.genitiv, .das, false), .quick))
    }

    @Test("The debug record check's fifteen rounds move exactly what they should")
    func skillMoves() {
        for scenario in scenarios {
            #expect(Set(KasusService.skillMoves(for: scenario.result).map(\.focus)) == scenario.moves, "\(scenario.name)")
        }
    }

    @Test("A case needs three answers that count, once per case per round")
    func minimumPerCase() {
        let two = round(.fill, .dativ, .ohne, Array(repeating: item(.dativ, .der, true), count: 2))
        #expect(KasusService.skillMoves(for: two).isEmpty)
        let three = round(.fill, .dativ, .ohne, [item(.dativ, .der, true), item(.dativ, .die, false), item(.dativ, .das, true)])
        #expect(KasusService.skillMoves(for: three) == [KasusSkillMove(focus: .dativ, correct: 2, total: 3)])
        let both = round(.fill, .alleFaelle, .ohne, Array(repeating: item(.genitiv, .der, true), count: 3)
                         + Array(repeating: item(.akkusativ, .der, false), count: 4))
        #expect(KasusService.skillMoves(for: both) == [KasusSkillMove(focus: .akkusativ, correct: 0, total: 4),
                                                       KasusSkillMove(focus: .genitiv, correct: 3, total: 3)],
                "one move per case, in table order")
        #expect(KasusService.minItemsPerCase == 3)
    }

    // MARK: recordRound, in memory

    @Test("recordRound adds the day's count, one round, and only the skills that count")
    func recordRoundScenarios() throws {
        let (container, context) = try store()
        defer { withExtendedLifetime(container) {} }
        for scenario in scenarios {
            let exercisesBefore = try grammarExercises(context)
            let roundsBefore = try context.fetchCount(FetchDescriptor<KasusRound>())
            let skillsBefore = try skills(context)

            let moves = KasusService.recordRound(scenario.result, in: context)

            #expect(Set(moves.map(\.focus)) == scenario.moves, "\(scenario.name)")
            #expect(try grammarExercises(context) - exercisesBefore == scenario.result.answeredCount, "\(scenario.name)")
            #expect(try context.fetchCount(FetchDescriptor<KasusRound>()) == roundsBefore + 1, "\(scenario.name)")
            let skillsAfter = try skills(context)
            for focus in [GrammarFocus.akkusativ, .dativ, .genitiv] {
                let moved = skillsAfter[focus.rawValue]?.struggle != skillsBefore[focus.rawValue]?.struggle
                #expect(moved == scenario.moves.contains(focus), "\(scenario.name): \(focus.rawValue)")
            }
        }
        let skills = try skills(context)
        #expect(Set(skills.keys) == [GrammarFocus.dativ.rawValue, GrammarFocus.akkusativ.rawValue])
        #expect(skills[GrammarCase.nominativ.rawValue] == nil, "Nominativ writes nothing")
        #expect((skills[GrammarFocus.dativ.rawValue]?.struggle ?? 0) > 0, "four wrong Dativ answers raise its struggle")
    }

    @Test("Finden counts the painted phrases for the streak, never the coach")
    func findenStreakOnly() throws {
        let (container, context) = try store()
        defer { withExtendedLifetime(container) {} }
        let find = round(.find, .dativ, nil, Array(repeating: item(.dativ, .der, false), count: 12), painted: 5)
        #expect(KasusService.recordRound(find, in: context).isEmpty)
        #expect(try grammarExercises(context) == 5)
        #expect(try skills(context).isEmpty)
        let stored = try #require(try context.fetch(FetchDescriptor<KasusRound>()).first)
        #expect(stored.askedCount == 12)
        #expect(stored.step == .find)
    }

    @Test("Markieren counts its words for the streak, stores its case and wrong marks, never the coach")
    func markingRound() throws {
        let (container, context) = try store()
        defer { withExtendedLifetime(container) {} }
        let marking = self.marking     // one result, one id
        #expect(marking.askedCount == 10 && marking.firstTryCount == 8 && marking.wrongCount == 2)
        #expect(marking.answeredCount == 10, "answered = the words to find")
        #expect(abs(marking.score - 0.6) < 0.0001, "(8 − 2) / 10")
        #expect(marking.perCase == [.dativ: KasusRound.CaseTally(asked: 10, firstTry: 6)],
                "the case bar counts the sheet's points, so it agrees with the score")
        #expect(KasusService.recordRound(marking, in: context).isEmpty)
        #expect(try grammarExercises(context) == 10)
        #expect(try skills(context).isEmpty)
        let stored = try #require(try context.fetch(FetchDescriptor<KasusRound>()).first)
        #expect(stored.isMarkingRound && stored.markCase == .dativ && stored.feedbackMode == .amEnde)
        #expect(stored.askedCount == 10 && stored.firstTryCount == 8 && stored.wrongCount == 2)
        #expect(stored.markScore?.scoreLabel == "6 / 10")
        #expect(stored.markScore?.countsLabel == "8 richtig · 2 falsch · 2 übersehen")
        #expect(stored.stepLabel == "Markieren · Dativ")
        #expect(stored.roundKey == marking.id.uuidString)
        #expect(!stored.revealedAnswers)
        #expect(stored.perCase == [.dativ: KasusRound.CaseTally(asked: 10, firstTry: 6)])

        // A row stored with the old tally (right words, not points) still reads as points.
        let old = KasusRound(storyID: "test", unitRaw: "dativ", stepRaw: "find", askedCount: 18, firstTryCount: 18,
                             durationSeconds: 30, perCase: [.dativ: .init(asked: 18, firstTry: 18)],
                             feedbackModeRaw: "amEnde", markCaseRaw: "dativ", wrongCount: 86)
        #expect(old.perCase == [.dativ: KasusRound.CaseTally(asked: 18, firstTry: 0)], "marking everything fills no bar")

        // Prüfen with nothing marked (giving up to see the answers) answers nothing.
        let empty = KasusRoundResult(storyID: "test", unit: .dativ, step: .find, items: [], durationSeconds: 5,
                                     feedbackMode: .amEnde, markCase: .dativ,
                                     markScore: KasusMarkScore(caseWords: 10, right: 0, wrong: 0))
        #expect(empty.answeredCount == 0 && !empty.isEmpty, "stored, but nothing for the streak")
    }

    @Test("Lösung zeigen after a Markieren round is recorded flags only what it showed")
    func markingAnswersShownAfterRecording() throws {
        let story = try #require(KasusTestData.story(KasusTestData.schluesselID))
        let playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
        var round = KasusService.markRound(.dativ, in: playable, mode: .amEnde)
        for id in KasusService.debugMarks(for: round, answers: .mixed) { round.tap(id) }
        // A word of an Akkusativ phrase too, for a wrongPick row.
        let akk = try #require(playable.numbered.caseWords(.akkusativ).first)
        round.tap(akk.id)
        round.check()
        let result = KasusService.markResult(round, storyID: story.id, unit: .dativ, in: playable, durationSeconds: 60)

        let (container, context) = try store()
        defer { withExtendedLifetime(container) {} }
        KasusService.recordRound(result, in: context)
        round.showAnswers()
        #expect(KasusService.markAnswersShown(roundID: round.id, in: context))

        let stored = try #require(try context.fetch(FetchDescriptor<KasusRound>()).first)
        #expect(stored.revealedAnswers)
        let items = stored.items
        let byOutcome = Dictionary(grouping: items, by: \.outcome)
        #expect(!(byOutcome[.missed] ?? []).isEmpty && (byOutcome[.missed] ?? []).allSatisfy(\.wasRevealed))
        #expect(!(byOutcome[.wrongMark] ?? []).isEmpty && (byOutcome[.wrongMark] ?? []).allSatisfy { !$0.wasRevealed },
                "a wrong mark was the learner's; Lösung zeigen didn't show it")
        #expect(!(byOutcome[.wrongPick] ?? []).isEmpty && (byOutcome[.wrongPick] ?? []).allSatisfy { !$0.wasRevealed })
        #expect((byOutcome[.right] ?? []).allSatisfy { !$0.wasRevealed })
        // The same flags markResult gives when Lösung zeigen comes before recording.
        let before = KasusService.markResult(round, storyID: story.id, unit: .dativ, in: playable, durationSeconds: 60)
        #expect(before.items.compactMap(\.record).map(\.wasRevealed) == items.map(\.wasRevealed))
    }

    @Test("Lösung zeigen after recording flags the same round and the answers it showed")
    func answersShownAfterRecording() throws {
        let story = try #require(KasusTestData.story(KasusTestData.schluesselID))
        let playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
        var round = KasusService.endingsRound(in: playable, unit: .dativ, mixed: false, hint: .ohne, mode: .amEnde)
        let gaps = round.gaps
        try #require(gaps.count >= 3)
        round.choose(gaps[0].answer, for: gaps[0].id)                                     // right
        let wrong = try #require(gaps[1].options.first { $0 != gaps[1].answer })
        round.choose(wrong, for: gaps[1].id)                                              // wrong
        round.check()                                                                     // the rest empty
        let result = KasusService.endingsResult(round, storyID: story.id, unit: .dativ, durationSeconds: 60, story: story)
        #expect(result.answeredCount == 2, "empty gaps aren't answered")
        #expect(result.feedbackMode == .amEnde && result.id == round.id)

        let (container, context) = try store()
        defer { withExtendedLifetime(container) {} }
        KasusService.recordRound(result, in: context)
        #expect(try grammarExercises(context) == 2)
        round.showAnswers()
        #expect(KasusService.markAnswersShown(roundID: round.id, in: context))
        #expect(!KasusService.markAnswersShown(roundID: UUID(), in: context), "no round has that id")

        let stored = try #require(try context.fetch(FetchDescriptor<KasusRound>()).first)
        #expect(stored.revealedAnswers)
        #expect(stored.askedCount == gaps.count && stored.firstTryCount == 1, "the counts don't change")
        let items = stored.items
        #expect(items[0].outcome == .right && !items[0].wasRevealed)
        #expect(items[1].outcome == .caseMiss || items[1].outcome.rawValue.hasSuffix("Slip"))
        #expect(items[1].wasRevealed, "a wrong answer keeps its outcome and is marked as shown")
        #expect(items.dropFirst(2).allSatisfy { $0.outcome == .revealed && $0.wasRevealed })
        #expect(try skills(context).isEmpty, "Ohne Hilfe, but fewer than three Dativ answers counted")
    }

    @Test("Rounds from before Markieren and Endungen still read")
    func legacyRounds() throws {
        let find = KasusRound(storyID: "ks-dat-a2-schluessel", unitRaw: "dativ", stepRaw: "find",
                              askedCount: 12, firstTryCount: 9, durationSeconds: 60)
        #expect(find.isLegacyStoryRound && !find.isMarkingRound && find.markScore == nil)
        #expect(find.stepLabel == "Finden")
        let fill = KasusRound(storyID: "ks-dat-a2-schluessel", unitRaw: "dativ", stepRaw: "fill", hintLevelRaw: "genus",
                              askedCount: 9, firstTryCount: 7, durationSeconds: 60)
        #expect(fill.stepLabel == "Einsetzen" && fill.hintLevel == .genus && fill.feedbackMode == nil)
        let quick = KasusRound(storyID: "quick-dativ", unitRaw: "dativ", stepRaw: "quick",
                               askedCount: 10, firstTryCount: 6, durationSeconds: 60)
        #expect(quick.stepLabel == "Schnellrunde" && !quick.isLegacyStoryRound)
        let endings = KasusRound(storyID: "ks-dat-a2-schluessel", unitRaw: "dativ", stepRaw: "fill", hintLevelRaw: "lern",
                                 askedCount: 8, firstTryCount: 8, durationSeconds: 60, feedbackModeRaw: "sofort")
        #expect(endings.stepLabel == "Endungen" && endings.hintLevel == .lern)

        // An item saved before `revealed`, `markedWords` and `wordCount` existed.
        let old = #"[{"sentence":"Er spielt mit dem Schlüssel!","phraseStart":14,"phrase":"dem Schlüssel","answer":"dem","pick":"den","caseRaw":"dativ","genusRaw":"der","outcomeRaw":"caseMiss","countsTowardSkill":true,"explanation":"x","targetIndex":10}]"#
        find.itemsData = Data(old.utf8)
        let item = try #require(find.items.first)
        #expect(item.outcome == .caseMiss && item.revealed == nil && item.markedWords == nil && !item.wasRevealed)
        #expect(item.formGenus == .der)
    }

    @Test("An empty round records nothing")
    func emptyRound() throws {
        let (container, context) = try store()
        defer { withExtendedLifetime(container) {} }
        #expect(KasusService.recordRound(round(.fill, .dativ, .ohne, []), in: context).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<KasusRound>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<StudyDay>()) == 0)
    }

    @Test("A story round keeps its answers, each marked with whether it counted")
    func storyRoundKeepsItsAnswers() throws {
        let story = try #require(KasusTestData.story(KasusTestData.schluesselID))
        let playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
        let blanks = KasusService.blanks(in: playable, unit: .dativ, mixed: false, hint: .genus)
        var picks = Dictionary(uniqueKeysWithValues: blanks.map { ($0.id, $0.answer) })
        let boden = try #require(blanks.first { $0.target.noun == "Boden" })
        let tasche = try #require(blanks.first { $0.target.surface == "der Tasche" })
        picks[boden.id] = "der"     // a case miss on a masculine noun: counts
        picks[tasche.id] = "dem"    // a gender slip on a feminine one: doesn't
        let result = KasusService.fillResult(storyID: story.id, unit: .dativ, hint: .genus, blanks: blanks,
                                             picks: picks, durationSeconds: 120, story: story)

        let (container, context) = try store()
        defer { withExtendedLifetime(container) {} }
        let moves = KasusService.recordRound(result, in: context)
        let masculine = blanks.filter { $0.genus == .der }
        #expect(moves == [KasusSkillMove(focus: .dativ, correct: masculine.count - 1, total: masculine.count)],
                "Genus-Hilfe: only the masculine Dativ answers count")

        let stored = try #require(try context.fetch(FetchDescriptor<KasusRound>()).first)
        #expect(stored.storyID == story.id)
        #expect(stored.unit == .dativ && stored.step == .fill && stored.hintLevel == .genus)
        #expect(stored.askedCount == blanks.count)
        #expect(stored.firstTryCount == blanks.count - 2)
        #expect(stored.durationSeconds == 120)
        #expect(stored.perCase[.dativ] == KasusRound.CaseTally(asked: blanks.count, firstTry: blanks.count - 2))
        #expect(stored.items.count == blanks.count)
        for item in stored.items {
            #expect(item.countsTowardSkill == (item.genus == .der), "\(item.phrase)")
            #expect(!item.sentence.isEmpty && !item.explanation.isEmpty, "\(item.phrase)")
        }
        #expect(stored.items.first { $0.targetIndex == boden.id }?.outcome == .caseMiss)
        #expect(stored.items.first { $0.targetIndex == tasche.id }?.outcome == .genderSlip)
        #expect(stored.items.first { $0.targetIndex == boden.id }?.pick == "der")
    }
}
