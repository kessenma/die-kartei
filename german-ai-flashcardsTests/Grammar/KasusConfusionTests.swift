//
//  KasusConfusionTests.swift
//  german-ai-flashcardsTests
//
//  Verwechslungs-Paare: the analysis over synthetic rounds surfaces the pair with a known bias,
//  the thresholds hold (six misses, twice the runner-up), only form picks of the same family
//  count, and the drill a pair makes spans the cases the two forms can show on the nouns both fit.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Kasus confusion pairs")
struct KasusConfusionTests {

    private func item(answer: String, pick: String, kasus: GrammarCase = .dativ, revealed: Bool = false) -> KasusRoundItem {
        var item = KasusRoundItem(sentence: "Ich helfe \(answer) Mann.", phraseStart: 10, phrase: "\(answer) Mann", answer: answer,
                                  pick: pick, kasus: kasus, genus: .der,
                                  outcome: pick == answer ? .right : .caseMiss, explanation: "why")
        if revealed { item.revealed = true }
        return item
    }

    private func round(_ step: KasusRoundStep, _ items: [KasusRoundItem], unit: KasusUnit = .dativ) -> KasusRound {
        KasusRound(storyID: step.roundID(topicKey: unit.rawValue).isEmpty ? "ks-dat-a2-schluessel" : step.roundID(topicKey: unit.rawValue),
                   unitRaw: unit.rawValue, stepRaw: step.rawValue, askedCount: items.count,
                   firstTryCount: items.filter { $0.outcome == .right }.count, durationSeconds: 60, items: items)
    }

    @Test("A biased learner's pair comes out on top, either way round")
    func biasedPair() {
        let rounds = [
            round(.quick, [item(answer: "dem", pick: "den"), item(answer: "dem", pick: "den"), item(answer: "den", pick: "dem", kasus: .akkusativ),
                           item(answer: "dem", pick: "dem"), item(answer: "der", pick: "die", kasus: .nominativ)]),
            round(.fill, [item(answer: "dem", pick: "den"), item(answer: "dem", pick: "den"), item(answer: "dem", pick: "den"),
                          item(answer: "dem", pick: "der")]),
        ]
        let pairs = KasusConfusion.pairs(rounds: rounds)
        #expect(pairs.first == KasusConfusionPair(a: "den", b: "dem", count: 6, genus: .der))
        #expect(pairs.first?.label == "dem ↔ den")
        #expect(pairs.map(\.count) == [6, 1, 1])
        #expect(KasusConfusion.standout(rounds: rounds)?.label == "dem ↔ den")
    }

    @Test("Under six misses, or without a clear lead, there is no card")
    func thresholds() {
        let few = [round(.quick, Array(repeating: item(answer: "dem", pick: "den"), count: 5))]
        #expect(KasusConfusion.pairs(rounds: few).first?.count == 5 && KasusConfusion.standout(rounds: few) == nil)
        let close = [round(.quick, Array(repeating: item(answer: "dem", pick: "den"), count: 6)
                            + Array(repeating: item(answer: "der", pick: "die", kasus: .nominativ), count: 4))]
        #expect(KasusConfusion.standout(rounds: close) == nil)
        let clear = [round(.quick, Array(repeating: item(answer: "dem", pick: "den"), count: 8)
                            + Array(repeating: item(answer: "der", pick: "die", kasus: .nominativ), count: 4))]
        #expect(KasusConfusion.standout(rounds: clear)?.count == 8)
    }

    @Test("Only form picks of the same family count: never a role, a revealed answer or another word")
    func whatCounts() {
        let rounds = [
            // Rollen's pick is a role, not a form.
            round(.roles, Array(repeating: item(answer: "dem", pick: "den"), count: 8)),
            // Revealed answers were never the learner's.
            round(.quick, Array(repeating: item(answer: "dem", pick: "den", revealed: true), count: 8)),
            // meinem for dem is another word, not a mix-up of endings.
            round(.quick, Array(repeating: item(answer: "dem", pick: "meinem"), count: 8)),
            round(.quick, [item(answer: "einem", pick: "einen"), item(answer: "einem", pick: "einen")]),
        ]
        let pairs = KasusConfusion.pairs(rounds: rounds)
        #expect(pairs == [KasusConfusionPair(a: "einem", b: "einen", count: 2, genus: .der)])
    }

    @Test("A pair's drill spans the cases the forms can show, on the nouns both forms fit, with only the two buttons")
    func drill() {
        let session = KasusConfusion.drill(for: KasusConfusionPair(a: "dem", b: "den", count: 9, genus: .der))
        guard let session, case .endings(let config) = session.variant else { Issue.record("no drill"); return }
        #expect(session.kind == .pair && session.topic == .kasus(.dativ))
        #expect(config.options == ["dem", "den"] && config.determiners == [.definite])
        #expect(Set(config.cases) == [.akkusativ, .dativ] && config.genders == [.der])
        // Without a gender from the misses, the forms' own fit decides (dem and den are one gender anyway).
        #expect(KasusConfusion.drill(for: KasusConfusionPair(a: "dem", b: "den", count: 9))?.topic == .kasus(.dativ))
        var rng = KasusSeededRandom(seed: 5)
        let round = EndingsQuestion.round(cases: config.cases, count: 10, genders: config.genders,
                                          determiners: config.determiners, options: config.options, rng: &rng)
        #expect(round.count == 10)
        #expect(round.allSatisfy { $0.options == ["dem", "den"] && $0.options.contains($0.answer) && $0.determiner == .definite })
        #expect(round.allSatisfy { $0.gender == .der || $0.gender == .plural })
        #expect(round.contains { $0.kasus == .akkusativ } && round.contains { $0.kasus == .dativ })

        let nominative = KasusConfusion.drill(for: KasusConfusionPair(a: "der", b: "den", count: 6, genus: .der))
        #expect(nominative?.topic == .kasus(.akkusativ))
        // der and den on plural nouns are the Genitiv and Dativ plural: a different drill.
        #expect(KasusConfusion.drill(for: KasusConfusionPair(a: "der", b: "den", count: 6, genus: .plural))?.topic == .kasus(.genitiv))
        // A pair that can't span two cases, or isn't one family, has no drill.
        #expect(KasusConfusion.drill(for: KasusConfusionPair(a: "dem", b: "meinem", count: 6)) == nil)
        #expect(KasusConfusion.drill(for: KasusConfusionPair(a: "dieser", b: "diesen", count: 6)) == nil)
    }

    @Test("The Dativ-Verben family spans both its cases, and the Blitz round has a minute's worth of questions")
    func variants() {
        #expect(EndingsQuestion.coversCases(KasusUnit.dativ.casesInPlay, family: .dativVerb))
        #expect(!EndingsQuestion.coversCases(KasusUnit.nominativ.casesInPlay, family: .dativVerb))
        let frames = EndingsQuestion.frames(family: .dativVerb)
        #expect(frames.count >= 15 && frames.contains { $0.kasus == .akkusativ } && frames.filter { $0.kasus == .dativ }.count >= 12)
        guard case .endings(let dativ) = DrillVariant.standard(for: .dativVerbs, in: .kasus(.dativ)) else { Issue.record("not endings"); return }
        #expect(dativ.family == .dativVerb && dativ.emphasis == .dativ)
        guard case .endings(let blitz) = DrillVariant.standard(for: .blitz, in: .kasus(.akkusativ)) else { Issue.record("not endings"); return }
        #expect(blitz.timeLimit == 60 && blitz.deferredFeedback && blitz.count == 60)
        var rng = KasusSeededRandom(seed: 1)
        let round = EndingsQuestion.round(cases: KasusUnit.akkusativ.casesInPlay, count: 60, rng: &rng)
        #expect(round.count >= 40, "\(round.count) questions")
        #expect(KasusRoundStep.blitz.meta.placement == .ueben && KasusRoundStep.dativVerbs.meta.placement == .ueben)
        #expect(!KasusRoundStep.blitz.meta.allowsReference && KasusRoundStep.pair.meta.placement == .hidden)
    }
}
