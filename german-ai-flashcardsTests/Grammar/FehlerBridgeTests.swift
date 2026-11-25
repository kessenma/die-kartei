//
//  FehlerBridgeTests.swift
//  german-ai-flashcardsTests
//
//  Finde den Fehler and die Pronomen-Brücke. The injector plants a form the sentence can't read
//  as right on a phrase the sentence proves, with the fix among the options; the bridge's three
//  forms agree with the tables for every gender and case; both modules grade a two- or
//  three-tap step the way the recorder expects.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Finde den Fehler")
struct FehlerTests {

    @Test("A planted mistake is a wrong form on a proven phrase, and every unit past the Nominativ has a round", arguments: [KasusUnit.akkusativ, .dativ, .genitiv, .alleFaelle])
    @MainActor
    func planted(_ unit: KasusUnit) {
        let playables = KasusService.conceptPlayables(unit: unit, exercise: .roles, lexicon: KasusTestData.lexicon)
        var rng = KasusSeededRandom(seed: 3)
        let round = FehlerQuestion.round(playables: playables, casesInPlay: unit.casesInPlay, emphasis: unit.focusCase, count: 8, rng: &rng)
        #expect(round.count == 8, Comment(rawValue: "\(unit): \(round.count)"))
        #expect(Set(round.map(\.playable.id)).count == round.count, "each item at most once")
        for q in round {
            #expect(q.target.proof == .form || q.target.proof == .preposition)
            #expect(!q.playable.facts.isOVS)
            #expect(q.wrong.lowercased() != q.answer.lowercased())
            #expect(!KasusForms.compatibleCases(determiner: q.wrong, genus: q.genus).contains(q.kasus), Comment(rawValue: "\(q.playable.id): „\(q.wrong)“ still fits \(q.kasus)"))
            #expect(q.options.contains(q.answer) && q.options.contains(q.wrong) && q.options.count >= 2)
            #expect(q.corruptedSentence.contains(q.wrong) && q.corruptedSentence != q.sentence
                    && q.corruptedSentence.count == q.sentence.count - q.answer.count + q.wrong.count,
                    Comment(rawValue: "\(q.playable.id): „\(q.corruptedSentence)“ for „\(q.sentence)“"))
            #expect(unit.casesInPlay.contains(q.kasus))
            let planted = q.playable.sentences.flatMap(\.words).filter(q.isPlanted)
            #expect(planted.count == 1, Comment(rawValue: "\(q.playable.id): \(planted.count) planted words"))
        }
        if let emphasis = unit.focusCase {
            #expect(round.filter { $0.kasus == emphasis }.count >= 3)
        }
    }

    @Test("Two taps: found then fixed is right; a missed find is practice; a wrong fix is a miss")
    @MainActor
    func grading() {
        let module = FehlerModule(session: GrammarDrillSession(kind: .fehler, topic: .kasus(.dativ)))
        var rng = KasusSeededRandom(seed: 5)
        guard let items = module.compose(GrammarDrillSession(kind: .fehler, topic: .kasus(.dativ)), rng: &rng), let item = items.first else {
            Issue.record("no round"); return
        }
        let words = item.playable.sentences.flatMap(\.words)
        let planted = words.first(where: item.isPlanted)!
        let other = words.first { !item.isInPhrase($0) }!

        var partial: FehlerFound?
        guard case .partial(let found, _, let right) = module.answer(.word(planted.id), for: item, step: 0, partial: &partial) else { Issue.record("not partial"); return }
        #expect(right && found.right && partial == found)
        guard case .graded(let fixed) = module.answer(.form(item.answer), for: item, step: 0, partial: &partial) else { Issue.record("not graded"); return }
        #expect(fixed.outcome == .right && fixed.result.firstTry && !fixed.result.scaffolded && partial == nil)
        #expect(KasusService.countsTowardSkill(fixed.result, step: .fehler, hint: nil) == (item.genus == .der || item.kasus != .akkusativ))

        guard case .partial(let missed, _, let foundRight) = module.answer(.word(other.id), for: item, step: 0, partial: &partial) else { Issue.record("not partial"); return }
        #expect(!foundRight && !missed.right)
        guard case .graded(let late) = module.answer(.form(item.answer), for: item, step: 0, partial: &partial) else { Issue.record("not graded"); return }
        #expect(late.outcome == .wrongPick && !late.result.firstTry && late.result.scaffolded)
        #expect(!KasusService.countsTowardSkill(late.result, step: .fehler, hint: nil))

        _ = module.answer(.word(planted.id), for: item, step: 0, partial: &partial)
        guard case .graded(let wrong) = module.answer(.form(item.wrong), for: item, step: 0, partial: &partial) else { Issue.record("not graded"); return }
        #expect(wrong.outcome == .caseMiss && !wrong.result.firstTry)
        #expect(module.answer(.form(item.answer), for: item, step: 0, partial: &partial) == .ignored, "a form before a find is ignored")
        #expect(module.debugPick(for: item, partial: nil, want: .right) == .word(planted.id))
        #expect(module.debugPick(for: item, partial: FehlerFound(right: true), want: .wrong) == .form(item.wrong))
        #expect(KasusItemOutcome.wrongPick.labels(for: .fehler) == ("Übersehen", "Missed the word"))
    }
}

@Suite("Pronomen-Brücke")
struct BridgeTests {

    @Test("The three forms agree with the tables for every gender and case")
    func forms() {
        #expect(BridgeQuestion.english(.der, .nominativ) == "he" && BridgeQuestion.english(.der, .dativ) == "him")
        #expect(BridgeQuestion.english(.die, .akkusativ) == "her" && BridgeQuestion.english(.plural, .nominativ) == "they")
        #expect(BridgeQuestion.pronoun(.der, .akkusativ) == "ihn" && BridgeQuestion.pronoun(.der, .dativ) == "ihm")
        #expect(BridgeQuestion.pronoun(.die, .dativ) == "ihr" && BridgeQuestion.pronoun(.plural, .dativ) == "ihnen")
        #expect(BridgeQuestion.pronoun(.die, .akkusativ) == "sie" && BridgeQuestion.pronoun(.das, .dativ) == "ihm")
        #expect(BridgeQuestion.frames(for: KasusUnit.dativ.casesInPlay).count == 7)
        #expect(BridgeQuestion.coversCases(KasusUnit.akkusativ.casesInPlay) && !BridgeQuestion.coversCases(KasusUnit.nominativ.casesInPlay))
    }

    @Test("A round chains English, pronoun and article over the unit's cases on masculine, feminine and plural nouns")
    func round() {
        var rng = KasusSeededRandom(seed: 4)
        let round = BridgeQuestion.round(cases: KasusUnit.dativ.casesInPlay, emphasis: .dativ, count: 8, rng: &rng)
        #expect(round.count == 8 && round.filter { $0.kasus == .dativ }.count >= 3)
        #expect(round.contains { $0.kasus != .dativ })
        for q in round {
            #expect(q.gender != .das)
            #expect(q.englishSentence.contains("___") && q.pronounSentence.contains("___") && q.articleSentence.contains("___"))
            #expect(!q.pronounSentence.contains("{N}") && q.articleSentence.contains(q.nounForm))
            #expect(q.englishOptions.contains(q.englishAnswer) && q.pronounOptions.contains(q.pronounAnswer) && q.articleOptions.contains(q.articleAnswer))
            #expect(q.englishOptions.count == 2 && q.pronounOptions.count >= 2 && q.articleOptions.count >= 2)
            #expect(RichMarkup.problems(q.explanation).isEmpty, Comment(rawValue: q.explanation))
        }
        let masculineDative = round.first { $0.gender == .der && $0.kasus == .dativ }
        #expect(masculineDative?.answers == ["him", "ihm", "dem"])
        #expect(masculineDative?.explanation.contains("The **m** of *him*") == true)
    }

    @Test("Three taps grade one step; a wrong stage makes the chain a miss")
    @MainActor
    func grading() {
        let module = BridgeModule(session: GrammarDrillSession(kind: .bridge, topic: .kasus(.akkusativ)))
        var rng = KasusSeededRandom(seed: 2)
        guard let items = module.compose(GrammarDrillSession(kind: .bridge, topic: .kasus(.akkusativ)), rng: &rng), let item = items.first else {
            Issue.record("no round"); return
        }
        var partial: BridgeWalk?
        guard case .partial(let one, _, let r1) = module.answer(item.answers[0], for: item, step: 0, partial: &partial) else { Issue.record("not partial"); return }
        #expect(r1 && one.filled == [item.answers[0]])
        guard case .partial(let two, _, let r2) = module.answer(item.answers[1], for: item, step: 0, partial: &partial) else { Issue.record("not partial"); return }
        #expect(r2 && two.filled.count == 2)
        guard case .graded(let graded) = module.answer(item.answers[2], for: item, step: 0, partial: &partial) else { Issue.record("not graded"); return }
        #expect(graded.outcome == .right && graded.result.firstTry && partial == nil)
        #expect(graded.result.record?.answer == item.articleAnswer && graded.result.record?.pick == item.answers.joined(separator: " · "))
        #expect(!KasusService.countsTowardSkill(graded.result, step: .bridge, hint: nil), "recognition never moves the coach")

        let wrongFirst = module.debugPick(for: item, partial: nil, want: .wrong)!
        _ = module.answer(wrongFirst, for: item, step: 0, partial: &partial)
        _ = module.answer(item.answers[1], for: item, step: 0, partial: &partial)
        guard case .graded(let miss) = module.answer(item.answers[2], for: item, step: 0, partial: &partial) else { Issue.record("not graded"); return }
        #expect(miss.outcome == .caseMiss && !miss.result.firstTry && miss.cardRight == true)
    }
}
