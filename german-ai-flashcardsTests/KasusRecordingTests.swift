//
//  KasusRecordingTests.swift
//  german-ai-flashcardsTests
//
//  What a finished round moves. Every answer counts for the streak; the coach's case skill only
//  hears about unscaffolded first picks, at least three per case, never slips, never Finden, and
//  Nominativ has no skill at all. The same twelve rounds `-kasus.debugVerifyRecord 1` runs, here
//  against an in-memory store instead of the live one.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@Suite("Kasus recording")
struct KasusRecordingTests {

    private func item(_ kasus: GrammarCase, _ genus: Gender, _ right: Bool,
                      slip: Bool = false, tipp: KasusTipp = .none) -> KasusItemResult {
        KasusItemResult(kasus: kasus, genus: genus, firstTry: right, slip: slip, tipp: tipp)
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

    /// The debug record check's rounds: #1–#10 move nothing, #11 moves Dativ, #12 Akkusativ.
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
        // The Schnellrunde names the noun with its article.
        #expect(counts(item(.akkusativ, .der, false), .quick))
        #expect(!counts(item(.akkusativ, .plural, false), .quick))
        #expect(counts(item(.dativ, .die, false), .quick))
        #expect(counts(item(.genitiv, .das, false), .quick))
    }

    @Test("The debug record check's twelve rounds move exactly what they should")
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
