//
//  EndingsQuestionTests.swift
//  german-ai-flashcardsTests
//
//  The Schnellrunde's engine as a model: a seeded round is the same round every time, the quota
//  still asks every case in play, a frame family narrows the pool and says when it can't cover
//  a unit's cases, and the ending labels are the forms engine's.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Endings question engine")
struct EndingsQuestionTests {

    @Test("The same seed gives the same round; another seed another")
    func seeded() {
        var a = KasusSeededRandom(seed: 42), b = KasusSeededRandom(seed: 42), c = KasusSeededRandom(seed: 43)
        let cases = KasusUnit.dativ.casesInPlay
        let first = EndingsQuestion.round(cases: cases, emphasis: .dativ, rng: &a)
        let same = EndingsQuestion.round(cases: cases, emphasis: .dativ, rng: &b)
        let other = EndingsQuestion.round(cases: cases, emphasis: .dativ, rng: &c)
        func key(_ q: EndingsQuestion) -> String { "\(q.frame.singular)|\(q.noun.singular)|\(q.isPlural)|\(q.determiner)" }
        #expect(first.map(key) == same.map(key))
        #expect(first.map(key) != other.map(key))
        #expect(first.count == 10)
    }

    @Test("Every case in play is asked, the unit's own case most, in every unit")
    func quota() {
        for unit in KasusUnit.allCases {
            var rng = KasusSeededRandom(seed: 7)
            let round = EndingsQuestion.round(cases: unit.casesInPlay, emphasis: unit.focusCase, rng: &rng)
            let asked = Set(round.map(\.kasus))
            #expect(asked == Set(unit.casesInPlay), "\(unit)")
            if let own = unit.focusCase, unit != .nominativ {
                let counts = Dictionary(grouping: round, by: \.kasus).mapValues(\.count)
                #expect(counts[own] == counts.values.max(), "\(unit) leans on its own case")
            }
            #expect(Set(round.map { "\($0.kasus)|\($0.noun.singular)|\($0.isPlural)" }).count == round.count, "no repeats")
        }
    }

    @Test("A frame family narrows the pool and reports the cases it can cover")
    func families() {
        let dativVerbs = EndingsQuestion.frames(family: .dativVerb)
        #expect(dativVerbs.count == 3 && Set(dativVerbs.map(\.kasus)) == [.akkusativ, .dativ])
        #expect(EndingsQuestion.frames(family: nil).count == EndingsFrame.all.count)
        #expect(EndingsQuestion.coversCases(KasusUnit.dativ.casesInPlay, family: .dativVerb))
        #expect(!EndingsQuestion.coversCases(KasusUnit.nominativ.casesInPlay, family: .dativVerb))
        #expect(EndingsQuestion.coversCases(KasusUnit.nominativ.casesInPlay, family: nil))
        var rng = KasusSeededRandom(seed: 3)
        let round = EndingsQuestion.round(cases: KasusUnit.dativ.casesInPlay, emphasis: .dativ, family: .dativVerb, rng: &rng)
        #expect(round.allSatisfy { $0.frame.family == .dativVerb })
        #expect(Set(round.map(\.kasus)) == [.akkusativ, .dativ])
    }

    @Test("Ending labels and the forms they stand for are the forms engine's")
    func labels() {
        #expect(KasusForms.endingLabel("em") == "-em" && KasusForms.endingLabel("") == "–")
        var rng = KasusSeededRandom(seed: 11)
        for q in EndingsQuestion.round(cases: GrammarCase.allCases, rng: &rng) {
            #expect(q.endingLabels.count == q.options.count)
            #expect(q.form(endingLabel: KasusForms.endingLabel(q.answerParts.ending)) == q.answer)
            #expect(EndingsQuestion.caseWord(q.kasus) == KasusExplanation.caseName(q.kasus))
            #expect(EndingsQuestion.codeWord(q.kasus) == KasusExplanation.codeWord(q.kasus))
        }
    }
}
