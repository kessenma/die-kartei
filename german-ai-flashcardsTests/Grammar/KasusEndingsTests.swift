//
//  KasusEndingsTests.swift
//  german-ai-flashcardsTests
//
//  Endungen: definite and ein articles split into stem + ending, the ending buttons per family
//  and hint level, grading a chosen ending (right, case miss, gender slip, number slip) through
//  the whole-article grader, what each hint level shows, the round in both feedback modes, and
//  what its result records and lets count.
//

import Foundation
import Testing
@testable import Die_Kartei

/// A chosen ending on one gap of the Phase 1 story, gemischt at Ohne Hilfe.
nonisolated struct EndingExample: Sendable, CustomTestStringConvertible {
    let surface: String
    let ending: String
    let expected: String

    var testDescription: String { "„\(ending.isEmpty ? "–" : "-" + ending)“ on „\(surface)“ → \(expected)" }

    static let all: [EndingExample] = [
        EndingExample(surface: "dem Boden", ending: "em", expected: "right"),
        EndingExample(surface: "dem Boden", ending: "EM", expected: "right"),
        // The Nominativ left unchanged is a case miss, even though „der“ is also feminine Dativ.
        EndingExample(surface: "dem Boden", ending: "er", expected: "case miss"),
        EndingExample(surface: "dem Boden", ending: "en", expected: "case miss"),
        EndingExample(surface: "der Tasche", ending: "em", expected: "gender slip (m)"),
        EndingExample(surface: "der Tasche", ending: "ie", expected: "case miss"),
        EndingExample(surface: "den Schlüssel", ending: "ie", expected: "number slip"),
        EndingExample(surface: "den Schlüssel", ending: "er", expected: "case miss"),
        EndingExample(surface: "den Schlüssel", ending: "as", expected: "gender slip (n)"),
        EndingExample(surface: "Der Schlüssel", ending: "er", expected: "right"),
        EndingExample(surface: "Der Schlüssel", ending: "en", expected: "case miss"),
        EndingExample(surface: "einen Termin", ending: "en", expected: "right"),
        // „ein Termin“ is the Nominativ: the no-ending spot is a case miss here.
        EndingExample(surface: "einen Termin", ending: "", expected: "case miss"),
        EndingExample(surface: "einen Keks", ending: "e", expected: "gender slip (f)"),
        EndingExample(surface: "einen Keks", ending: "em", expected: "case miss"),
    ]
}

@Suite("Kasus Endungen")
struct KasusEndingsTests {
    let story: KasusStory
    let playable: KasusPlayableStory

    init() throws {
        story = try #require(KasusTestData.story(KasusTestData.schluesselID))
        playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
    }

    private var ohneGaps: [KasusEndingGap] {
        KasusService.endingGaps(in: playable, unit: .dativ, mixed: true, hint: .ohne)
    }

    private func gap(_ surface: String, hint: KasusHintLevel = .ohne) throws -> KasusEndingGap {
        try #require(KasusService.endingGaps(in: playable, unit: .dativ, mixed: true, hint: hint)
            .first { $0.target.surface == surface }, "no gap „\(surface)“")
    }

    private func tally(_ gaps: [KasusEndingGap]) -> [GrammarCase: Int] {
        gaps.reduce(into: [:]) { $0[$1.kasus, default: 0] += 1 }
    }

    private func describe(_ outcome: KasusPickOutcome) -> String {
        switch outcome {
        case .right:                 "right"
        case .genderSlip(let other): "gender slip (\(other?.columnLabel ?? "?"))"
        case .numberSlip:            "number slip"
        case .caseMiss:              "case miss"
        }
    }

    // MARK: Families and gaps

    @Test("The two families' ending rows, in table order")
    func families() {
        #expect(KasusEndingFamily.definite.endings(includeGenitive: false) == ["er", "ie", "as", "en", "em"])
        #expect(KasusEndingFamily.definite.endings(includeGenitive: true) == ["er", "ie", "as", "en", "em", "es"])
        #expect(KasusEndingFamily.ein.endings(includeGenitive: false) == ["", "e", "en", "em", "er"])
        #expect(KasusEndingFamily.ein.endings(includeGenitive: true) == ["", "e", "en", "em", "er", "es"])
        #expect(KasusEndingFamily.definite.ending(of: "Dem") == "em" && KasusEndingFamily.ein.ending(of: "ein") == "")
        #expect(KasusEndingFamily(.definite) == .definite && KasusEndingFamily(.ein) == .ein)
        #expect(KasusEndingFamily(.kein) == nil && KasusEndingFamily(.possessive) == nil && KasusEndingFamily(.derWord) == nil)
        #expect(KasusEndingGap.label("em") == "-em" && KasusEndingGap.label("") == "–")
    }

    @Test("Gaps follow the blank rules, but only definite and ein articles become gaps")
    func gapSelection() {
        for hint in KasusHintLevel.allCases {
            #expect(tally(KasusService.endingGaps(in: playable, unit: .dativ, mixed: false, hint: hint)) == [.dativ: 8],
                    "\(hint.germanLabel): „seiner Mutter“ stays written out")
        }
        #expect(tally(KasusService.endingGaps(in: playable, unit: .dativ, mixed: true, hint: .genus)) == [.akkusativ: 8, .dativ: 8])
        #expect(tally(KasusService.endingGaps(in: playable, unit: .dativ, mixed: true, hint: .lern)) == [.akkusativ: 8, .dativ: 8],
                "the Nominativ only at Ohne Hilfe")
        #expect(tally(ohneGaps) == [.nominativ: 6, .akkusativ: 8, .dativ: 8])
        #expect(!ohneGaps.contains { $0.target.parsed?.family == .possessive })
        #expect(KasusService.effectiveHintLevel(.lern, unit: .nominativ, mixed: false) == .ohne)
        let round = KasusService.endingsRound(in: playable, unit: .dativ, mixed: false, hint: .viel, mode: .sofort)
        #expect(round.gaps.count == 8 && round.hint == .viel && round.mode == .sofort)
    }

    @Test("Every gap: its stem as written, its answer among its buttons", arguments: BundledStories.ids)
    func everyGap(_ id: String) throws {
        let story = try #require(KasusTestData.story(id))
        let playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
        let unit = try #require(story.unit)
        for hint in KasusHintLevel.allCases {
            for gap in KasusService.endingGaps(in: playable, unit: unit, mixed: true, hint: hint) {
                let label = "\(gap.target.surface) at \(hint.germanLabel)"
                #expect(gap.target.kind == .article && [KasusFamily.definite, .ein].contains(gap.target.parsed?.family), "\(label)")
                #expect(gap.answerForm == gap.target.determiner, "\(label): \(gap.stem) + \(gap.answer)")
                #expect(gap.stem.lowercased() == gap.family.stem, "\(label)")
                #expect(gap.stem.first?.isUppercase == gap.target.determiner.first?.isUppercase, "\(label) keeps its capital")
                #expect(gap.options.contains(gap.answer), "\(label): \(gap.options)")
                #expect(Set(gap.options).count == gap.options.count, "\(label) repeats a button")
                #expect(gap.options.count >= 3, "\(label) is a coin flip")
                #expect(KasusService.grade(ending: gap.answer, for: gap) == .right, "\(label)")
                let order = gap.family.endings(includeGenitive: true)
                #expect(gap.options == order.filter(gap.options.contains), "\(label) is in table order")
                for ending in gap.options {
                    #expect(KasusService.grade(ending: ending, for: gap) == KasusService.grade(gap.family.stem + ending, for: gap.target),
                            "\(label): -\(ending) grades like the whole article")
                }
            }
        }
    }

    @Test("Stems and buttons, pinned")
    func pinnedButtons() throws {
        let boden = try gap("dem Boden")
        #expect(boden.gapText == "d__" && boden.answer == "em" && boden.family == .definite)
        #expect(boden.options == ["er", "ie", "as", "en", "em"])
        #expect(KasusService.endingOptions(for: boden.target, hint: .viel, includeGenitive: false) == ["er", "en", "em"])
        #expect(KasusService.endingOptions(for: boden.target, hint: .lern, includeGenitive: false) == ["er", "en", "em"])
        #expect(KasusService.endingOptions(for: boden.target, hint: .genus, includeGenitive: true) == ["er", "ie", "as", "en", "em", "es"])
        let tasche = try gap("der Tasche")
        #expect(KasusService.endingOptions(for: tasche.target, hint: .viel, includeGenitive: false) == ["er", "ie", "em"])
        let capital = try gap("Der Schlüssel")
        #expect(capital.gapText == "D__" && capital.form("en") == "Den" && capital.answerForm == "Der")
        let termin = try gap("einen Termin")
        #expect(termin.gapText == "ein__" && termin.answer == "en" && termin.family == .ein)
        #expect(termin.options == ["", "e", "en", "em", "er"])
        #expect(termin.form("") == "ein" && termin.options.map(KasusEndingGap.label) == ["–", "-e", "-en", "-em", "-er"])
        #expect(KasusService.endingOptions(for: termin.target, hint: .viel, includeGenitive: false) == ["", "en", "em"])
        #expect(KasusService.endingOptions(for: termin.target, hint: .ohne, includeGenitive: true) == ["", "e", "en", "em", "er", "es"])
        // A feminine ein-word: its own two forms, padded with the masculine Dativ.
        let foto = try #require(KasusTestData.story("ks-nom-a1-foto"))
        let frau = try #require(KasusService.prepare(foto, lexicon: KasusTestData.lexicon).targets.first { $0.surface == "eine Frau" })
        #expect(KasusService.endingOptions(for: frau, hint: .viel, includeGenitive: false) == ["e", "em", "er"])
        // Possessives, kein and dieser stay written out.
        let seiner = try #require(playable.targets.first { $0.surface == "seiner Mutter" })
        #expect(KasusService.endingGap(for: seiner, hint: .ohne, includeGenitive: false) == nil)
        #expect(KasusService.endingOptions(for: seiner, hint: .ohne, includeGenitive: false).isEmpty)
    }

    // MARK: Grading

    @Test("A chosen ending is graded right, case miss, gender slip or number slip", arguments: EndingExample.all)
    func grade(_ example: EndingExample) throws {
        let gap = try gap(example.surface)
        #expect(describe(KasusService.grade(ending: example.ending, for: gap)) == example.expected)
    }

    @Test("Feedback after a wrong ending: the slip note for a slip, the explanation for a case miss")
    func feedback() throws {
        let tasche = try gap("der Tasche")
        let slip = KasusService.grade(ending: "em", for: tasche)
        #expect(KasusService.endingFeedback(for: slip, ending: "em", gap: tasche, in: story)
                == KasusExplanation.genderSlipNote(pick: "dem", answer: "der", genus: .die, kasus: .dativ))
        let miss = KasusService.grade(ending: "ie", for: tasche)
        #expect(KasusService.endingFeedback(for: miss, ending: "ie", gap: tasche, in: story)
                == KasusService.explanation(for: tasche.target, in: story))
        #expect(KasusService.endingFeedback(for: .right, ending: "er", gap: tasche, in: story) == nil)
        let key = try gap("den Schlüssel")
        #expect(KasusService.endingFeedback(for: .numberSlip, ending: "ie", gap: key, in: story)?
            .hasPrefix("Right case, **wrong number**") == true)
    }

    // MARK: What each level shows

    @Test("Lernhilfe shows the table with the cell, Viel Hilfe the table, Genus-Hilfe the gender, Ohne Hilfe nothing")
    func hintLevels() throws {
        let lern = try gap("dem Boden", hint: .lern)
        #expect(lern.showsCaseTable && lern.highlightsCell && lern.showsGenderChip && lern.showsCaseChip)
        #expect(lern.showsGenderTag && lern.underlinesTrigger && !lern.showsNumberTag)
        #expect(lern.cell == KasusTableCell(kasus: .dativ, genus: .der))
        #expect(lern.genderChip == "Boden · m" && lern.genderTag == "(m)")
        let viel = try gap("dem Boden", hint: .viel)
        #expect(viel.showsCaseTable && !viel.highlightsCell && viel.showsGenderChip && !viel.showsCaseChip)
        #expect(viel.showsGenderTag && viel.underlinesTrigger)
        let genus = try gap("dem Boden", hint: .genus)
        #expect(!genus.showsCaseTable && !genus.highlightsCell && genus.showsGenderChip && genus.showsGenderTag)
        #expect(!genus.underlinesTrigger && !genus.showsCaseChip)
        let ohne = try gap("den Schlüssel")
        #expect(!ohne.showsCaseTable && !ohne.showsGenderChip && !ohne.showsGenderTag && !ohne.showsCaseChip)
        #expect(ohne.showsNumberTag && ohne.numberTag == "sg")
        #expect(KasusHintLevel.lern.showsCaseTable && KasusHintLevel.viel.showsCaseTable && !KasusHintLevel.genus.showsCaseTable)
    }

    // MARK: The round

    @Test("Sofort: the first pick is graded and locked; Lösung zeigen fills the rest, which never count")
    func sofortRound() throws {
        var round = KasusService.endingsRound(in: playable, unit: .dativ, mixed: false, hint: .ohne, mode: .sofort)
        let gaps = round.gaps
        #expect(round.choose(gaps[0].answer, for: gaps[0].id) == .right)
        let wrong = try #require(gaps[1].options.first { KasusService.grade(ending: $0, for: gaps[1]) == .caseMiss })
        #expect(round.choose(wrong, for: gaps[1].id) == .caseMiss)
        #expect(round.choose(gaps[1].answer, for: gaps[1].id) == nil && round.pick(for: gaps[1].id) == wrong, "locked")
        #expect(round.outcome(for: gaps[1].id) == .caseMiss && round.showsAnswer(for: gaps[1].id))
        #expect(round.outcome(for: gaps[2].id) == nil && !round.showsAnswer(for: gaps[2].id))
        #expect(!round.isFinished && round.rightCount == 1)
        round.recordTipp(.gender, for: gaps[2].id)
        round.recordTipp(.trigger, for: gaps[2].id)
        #expect(round.tipps[gaps[2].id] == .gender, "the Tipp never goes back")
        round.recordTipp(.answer, for: gaps[0].id)
        #expect(round.tipps[gaps[0].id] == nil, "a Tipp after the pick doesn't count")

        round.showAnswers()
        #expect(round.isFinished && round.answersShown && round.revealed.count == gaps.count - 2)
        #expect(round.choose(gaps[3].answer, for: gaps[3].id) == nil, "a filled gap takes no pick")

        let result = KasusService.endingsResult(round, storyID: story.id, unit: .dativ, durationSeconds: 60, story: story)
        #expect(result.revealedAnswers && result.feedbackMode == .sofort && result.hintLevel == .ohne && result.id == round.id)
        #expect(result.askedCount == gaps.count && result.answeredCount == 2 && result.firstTryCount == 1)
        #expect(result.items.filter(\.revealed).count == gaps.count - 2)
        #expect(result.items[2].tipp == .gender)
        let records = result.items.compactMap(\.record)
        #expect(records[0].outcome == .right && records[0].pick == gaps[0].answerForm)
        #expect(records[1].outcome == .caseMiss && records[1].wasRevealed)
        #expect(records.dropFirst(2).allSatisfy { $0.outcome == .revealed && $0.wasRevealed && $0.pick == nil })
        #expect(KasusService.skillMoves(for: result).isEmpty, "two answers of the learner's own, under three")
    }

    @Test("Am Ende: picks change freely, Prüfen grades them all, then Lösung zeigen and Noch mal")
    func amEndeRound() throws {
        var round = KasusService.endingsRound(in: playable, unit: .dativ, mixed: false, hint: .genus, mode: .amEnde)
        let gaps = round.gaps
        let wrong = try #require(gaps[0].options.first { $0 != gaps[0].answer })
        #expect(round.choose(wrong, for: gaps[0].id) == nil, "nothing is judged before Prüfen")
        #expect(round.outcome(for: gaps[0].id) == nil)
        round.choose(gaps[0].answer, for: gaps[0].id)
        #expect(round.pick(for: gaps[0].id) == gaps[0].answer, "a later pick replaces the first")
        round.choose(wrong, for: gaps[1].id)
        round.clear(gaps[1].id)
        #expect(round.pick(for: gaps[1].id) == nil)
        round.showAnswers()
        #expect(!round.answersShown, "Lösung zeigen comes after Prüfen")
        for gap in gaps.dropFirst() { round.choose(gap.answer, for: gap.id) }
        let slipGap = try #require(gaps.first { gap in gap.options.contains { KasusService.grade(ending: $0, for: gap).isSlip } })
        let slip = try #require(slipGap.options.first { KasusService.grade(ending: $0, for: slipGap).isSlip })
        round.choose(slip, for: slipGap.id)
        #expect(round.allFilled && !round.isFinished)

        round.check()
        #expect(round.isFinished && round.outcome(for: slipGap.id)?.isSlip == true)
        #expect(round.choose(slipGap.answer, for: slipGap.id) == nil && round.pick(for: slipGap.id) == slip, "frozen after Prüfen")
        let result = KasusService.endingsResult(round, storyID: story.id, unit: .dativ, durationSeconds: 45, story: story)
        #expect(result.firstTryCount == gaps.count - 1 && result.answeredCount == gaps.count && !result.revealedAnswers)
        #expect(result.items.first { $0.targetIndex == slipGap.id }?.slip == true)

        round.showAnswers()
        #expect(round.answersShown && round.showsAnswer(for: slipGap.id) && round.revealed.isEmpty)
        let id = round.id
        round.reset()
        #expect(round.id == id && round.attempt == 2 && round.picks.isEmpty && !round.isChecked && !round.answersShown)
    }

    @Test("A gap left empty at Prüfen is asked but not answered, and never counts")
    func emptyGaps() throws {
        var round = KasusService.endingsRound(in: playable, unit: .dativ, mixed: false, hint: .ohne, mode: .amEnde)
        round.check()
        let result = KasusService.endingsResult(round, storyID: story.id, unit: .dativ, durationSeconds: 5, story: story)
        #expect(result.askedCount == round.gaps.count && result.answeredCount == 0 && result.firstTryCount == 0)
        #expect(result.items.allSatisfy { $0.unanswered && !$0.isAnswered })
        #expect(result.items.compactMap(\.record).allSatisfy { $0.outcome == .unanswered })
        #expect(KasusService.skillMoves(for: result).isEmpty)
    }

    @Test("Lernhilfe never moves the coach; Ohne Hilfe does")
    func counting() throws {
        func allWrong(_ hint: KasusHintLevel) throws -> KasusRoundResult {
            var round = KasusService.endingsRound(in: playable, unit: .dativ, mixed: false, hint: hint, mode: .sofort)
            for gap in round.gaps {
                let wrong = try #require(gap.options.first { KasusService.grade(ending: $0, for: gap) == .caseMiss })
                round.choose(wrong, for: gap.id)
            }
            #expect(round.isFinished)
            return KasusService.endingsResult(round, storyID: story.id, unit: .dativ, durationSeconds: 30, story: story)
        }
        #expect(KasusService.skillMoves(for: try allWrong(.lern)).isEmpty)
        #expect(KasusService.skillMoves(for: try allWrong(.viel)).isEmpty)
        let ohne = try allWrong(.ohne)
        #expect(KasusService.skillMoves(for: ohne) == [KasusSkillMove(focus: .dativ, correct: 0, total: ohne.items.count)])
        let stored = KasusService.round(for: try allWrong(.lern))
        #expect(stored.hintLevel == .lern && stored.feedbackMode == .sofort && stored.stepLabel == "Endungen")
        #expect(stored.items.allSatisfy { !$0.countsTowardSkill })
    }
}
