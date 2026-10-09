//
//  GapChoiceTests.swift
//  german-ai-flashcardsTests
//
//  The gap-choice format and its gate: the bundled pack passes with its golden numbers and every
//  planted error trips exactly its code (the same block `-kasus.debugVerify 1` prints), the
//  tables agree with themselves, a round composes with both cases, and a graded answer records
//  the way the recorder expects (a case miss, another person, an inline chip as practice).
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Gap-choice items")
struct GapChoiceTests {

    @Test("The bundled pack passes the gate, the golden numbers and every planted error")
    @MainActor
    func bundledPack() {
        let result = GapChoiceFixtures.verify(bank: GapChoiceBank.bundledUnchecked, lexicon: KasusTestData.lexicon)
        #expect(result.failures.isEmpty, Comment(rawValue: result.text))
        #expect(result.text.hasSuffix("Gaps ALL OK"))
    }

    @Test("Every planted error trips its code and nothing rejects the good item", arguments: GapChoiceFixtures.planted.indices)
    @MainActor
    func planted(_ index: Int) {
        let planted = GapChoiceFixtures.planted[index]
        let result = GapChoiceCheck.run(planted.item, lexicon: KasusTestData.lexicon)
        #expect(result.codes.contains(planted.code), Comment(rawValue: "\(planted.name): got \(result.codes.map(\.rawValue))"))
        #expect(!result.passes)
    }

    @Test("Every rejecting code has a planted error")
    func plantedCoverage() {
        let covered = Set(GapChoiceFixtures.planted.map(\.code))
        for code in GapChoiceCheckCode.allCases where code.rejects {
            #expect(covered.contains(code), Comment(rawValue: code.rawValue))
        }
    }

    @Test("The tables agree with themselves")
    func tables() {
        for verb in ReflexivVerb.table {
            #expect(verb.forms.count == 6, Comment(rawValue: verb.lemma))
            #expect(Set(verb.forms).count >= 3, Comment(rawValue: "\(verb.lemma) has too few distinct forms"))
            #expect(verb.takes == .akk ? verb.objects.isEmpty : !verb.objects.isEmpty, Comment(rawValue: verb.lemma))
            #expect(verb.takes == .akk ? verb.en.dat == nil : verb.en.dat != nil, Comment(rawValue: verb.lemma))
            #expect(verb.takes == .dat ? verb.en.akk == nil : verb.en.akk != nil, Comment(rawValue: verb.lemma))
        }
        #expect(ReflexivVerb.named("waschen")?.form(person: 2, number: .sg) == "wäschst")
        #expect(ReflexivVerb.named("abtrocknen")?.form(person: 3, number: .sg) == "trocknet")
        #expect(ReflexivVerb.named("leisten")?.form(person: 2, number: .sg) == "leistest")
        #expect(ReflexivVerb.named("putzen")?.form(person: 2, number: .sg) == "putzt")
        #expect(ReflexivVerb.named("anziehen")?.infinitive == "sich anziehen")
        for subject in ReflexivSubject.all {
            #expect(ReflexivPronoun.form(person: subject.person, number: subject.number, kasus: .akkusativ) != nil)
            #expect(ReflexivPronoun.form(person: subject.person, number: subject.number, kasus: .dativ) != nil)
        }
        #expect(ReflexivPronoun.form(person: 1, number: .sg, kasus: .dativ) == "mir")
        #expect(ReflexivPronoun.form(person: 3, number: .pl, kasus: .dativ) == "sich")
        #expect(ReflexivPronoun.otherCase(of: "dich") == "dir" && ReflexivPronoun.otherCase(of: "uns") == nil)
        #expect(ReflexivPronoun.visibleCase(of: "mir") == .dativ && ReflexivPronoun.visibleCase(of: "sich") == nil)
    }

    @Test("The sentence helpers fill and locate the gaps")
    func sentence() {
        let item = GapChoiceFixtures.good
        #expect(item.filled == "Ich wasche mir die Hände.")
        #expect(item.sentence(filling: { _ in nil }) == "Ich wasche ___ die Hände.")
        #expect(item.answerStart(of: 0) == "Ich wasche ".utf16.count)
        #expect(item.placeholderNumbers == [1] && item.kasus == .dativ)
        let explanation = ReflexivExplanation.why(item)
        #expect(explanation.contains("{dat:mir}") && RichMarkup.problems(explanation).isEmpty)
        #expect(ReflexivExplanation.feedback(item, pick: "mich").hasPrefix("„*mich*“ is the right person but the wrong case."))
        #expect(ReflexivExplanation.feedback(item, pick: "dir").hasPrefix("„*dir*“ belongs to another person."))
    }

    @Test("A graded answer records a case miss, another person, and an inline chip as practice")
    @MainActor
    func grading() {
        let module = GapChoiceModule(session: GrammarDrillSession(kind: .reflexCase, topic: .reflexiv))
        let item = GapChoiceFixtures.good
        var partial: GapWalk?
        guard case .graded(let right) = module.answer("mir", for: item, step: 0, partial: &partial) else { Issue.record("not graded"); return }
        #expect(right.outcome == .right && right.kasus == .dativ && right.result.firstTry && !right.result.scaffolded)
        #expect(right.result.record?.sentence == "Ich wasche mir die Hände." && right.result.record?.phrase == "mir")
        guard case .graded(let miss) = module.answer("mich", for: item, step: 0, partial: &partial) else { Issue.record("not graded"); return }
        #expect(miss.outcome == .caseMiss && !miss.result.firstTry && !miss.isSlip)
        guard case .graded(let person) = module.answer("dir", for: item, step: 0, partial: &partial) else { Issue.record("not graded"); return }
        #expect(person.outcome == .wrongPick)
        var inline = item
        inline.presentation = .inline
        guard case .graded(let chip) = module.answer("mir", for: inline, step: 0, partial: &partial) else { Issue.record("not graded"); return }
        #expect(chip.result.scaffolded, "two chips are practice, never evidence")
        #expect(!KasusService.countsTowardSkill(chip.result, step: .reflexCase, hint: nil))
        #expect(KasusService.countsTowardSkill(right.result, step: .reflexCase, hint: nil))
        #expect(module.debugPick(for: item, partial: nil, want: .wrong) == "mich")
        #expect(module.debugPick(for: item, partial: nil, want: .slip) == nil)
    }

    @Test("A multi-gap item plays one gap per tap")
    @MainActor
    func multiGap() {
        let module = GapChoiceModule(session: GrammarDrillSession(kind: .reflexCase, topic: .reflexiv))
        let item = GapChoiceItem(id: "rx-t-multi", topic: "reflexiv", focus: .multi, level: "A2",
                                 sentence: "Ich {1} {2} die Hände.", english: "I wash my hands.",
                                 gaps: [GapChoiceGap(kind: .verb, answer: "wasche", options: ["wasche", "wäschst"]),
                                        GapChoiceGap(answer: "mir", options: ["mich", "mir"], kasus: .dativ)],
                                 subject: GapSubject(person: 1, number: .sg, text: "Ich"),
                                 verb: GapVerb(lemma: "waschen", form: "wasche", takes: .both),
                                 secondObject: GapObject(text: "die Hände", lemma: "Hand", genus: .die, number: .pl))
        var partial: GapWalk?
        guard case .partial(let walk, _, let right) = module.answer("wasche", for: item, step: 0, partial: &partial) else { Issue.record("not partial"); return }
        #expect(right && walk.filled == ["wasche"] && partial == walk)
        guard case .graded(let graded) = module.answer("mir", for: item, step: 0, partial: &partial) else { Issue.record("not graded"); return }
        #expect(graded.outcome == .right && partial == nil && graded.result.record?.pick == "wasche · mir")
    }

    @Test("Pooled skill moves for a topic: six counting answers, both cases together")
    func pooledMoves() {
        func item(_ kasus: GrammarCase, _ right: Bool, scaffolded: Bool = false) -> KasusItemResult {
            KasusItemResult(kasus: kasus, genus: .der, firstTry: right, scaffolded: scaffolded)
        }
        let moved = KasusRoundResult(storyID: "reflexcase-reflexiv", topic: .reflexiv, step: .reflexCase,
                                     items: [item(.akkusativ, true), item(.akkusativ, false), item(.dativ, true),
                                             item(.dativ, true), item(.dativ, false), item(.akkusativ, true)],
                                     durationSeconds: 10)
        #expect(KasusService.skillMoves(for: moved) == [KasusSkillMove(focus: .reflexivverben, correct: 4, total: 6)])
        let few = KasusRoundResult(storyID: "reflexcase-reflexiv", topic: .reflexiv, step: .reflexCase,
                                   items: Array(repeating: item(.dativ, true), count: 5), durationSeconds: 10)
        #expect(KasusService.skillMoves(for: few).isEmpty)
        let chips = KasusRoundResult(storyID: "reflexcase-reflexiv", topic: .reflexiv, step: .reflexCase,
                                     items: Array(repeating: item(.dativ, true, scaffolded: true), count: 8), durationSeconds: 10)
        #expect(KasusService.skillMoves(for: chips).isEmpty)
    }

    @Test("The debug argument opens the reflexive lesson and drills")
    func debugOpen() {
        #expect(KasusDebugOpen(argument: "lesson:reflexiv") == .lesson(.reflexiv))
        #expect(KasusDebugOpen(argument: "lesson:dativ") == .lesson(.kasus(.dativ)))
        #expect(KasusDebugOpen(argument: "reflexcase:reflexiv") == .drill(.reflexCase, .reflexiv))
        #expect(KasusDebugOpen(argument: "reflexperson:reflexiv") == .drill(.reflexPerson, .reflexiv))
        #expect(KasusDebugOpen(argument: "reflexcase:dativ") == .drill(.reflexCase, .kasus(.dativ)))
    }
}
