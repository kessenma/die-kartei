//
//  EnglishAnchorModules.swift
//  german-ai-flashcards
//
//  „Welche Frage?“ and „Die englische Falle“ on the drill shell. One module plays both: the task
//  is identical (which question does the marked phrase answer), only the pool differs
//  (`EnglishAnchors.items`), which is the whole argument of the feature — the trap is the same
//  question asked where an English ear answers it wrongly.
//
//  Recognition on a translation, so neither kind moves the coach (`coachPolicy: .never`); the
//  round still banks its time and its streak like Rollen and Wer macht was?.
//

import SwiftUI

struct FrageModule: KasusDrillModule {
    typealias Item = EnglishAnchorItem
    typealias Pick = KasusQuestion
    typealias Partial = Never

    let kind: KasusDrillKind
    let unit: KasusUnit
    let help: KasusHelp

    init(session: GrammarDrillSession) {
        kind = session.kind
        unit = session.topic.unit ?? .alleFaelle
        if case .english(let config) = session.variant {
            help = config.help
        } else {
            help = .normal
        }
    }

    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [EnglishAnchorItem]? {
        let items = EnglishAnchors.items(unit: unit, kind: kind, help: help,
                                         count: kind.meta.roundSize, rng: &rng)
        return items.isEmpty ? nil : items
    }

    func answer(_ pick: KasusQuestion, for item: EnglishAnchorItem, step: Int,
                partial: inout Never?) -> KasusDrillOutcome<Never> {
        guard let target = item.target else { return .ignored }
        let right = pick == item.question
        let explanation = EnglishAnchors.explanation(for: item, picked: pick, target: target)
        let record = KasusRoundItem.story(target, in: item.playable.story, pick: pick.germanLabel,
                                          outcome: right ? .right : .wrongPick, explanation: explanation)
        let result = KasusItemResult(kasus: target.kasus, genus: target.genus, firstTry: right,
                                     targetIndex: target.index, record: record)
        return .graded(KasusGradedAnswer(outcome: right ? .right : .wrongPick, kasus: target.kasus,
                                         explanation: explanation, result: result))
    }

    func debugPick(for item: EnglishAnchorItem, partial: Never?, want: KasusDebugWant) -> KasusQuestion? {
        guard want != .slip else { return nil }
        guard want == .wrong else { return item.question }
        return KasusQuestion.allCases.first { $0 != item.question }
    }

    func hero(_ ctx: KasusDrillContext<Self>) -> some View {
        EnglishAnchorHero(item: ctx.item, siblings: siblings(ctx), answer: ctx.answer,
                          given: given(ctx), help: help, counter: counter(ctx))
    }

    func panel(_ ctx: KasusDrillContext<Self>) -> some View {
        EnglishQuestionGrid(questions: questions, answer: ctx.item.question, picked: ctx.picked,
                            revealedCase: ctx.answer?.kasus ?? ctx.item.kasus, help: help) { question in
            ctx.pick(question)
        }
        .id(ctx.item.id)
    }

    func hint(_ ctx: KasusDrillContext<Self>) -> String {
        ctx.item.stage == .deutsch
            ? "Welche Frage beantwortet der markierte Teil?"
            : "Which question does the ringed part answer?"
    }

    func summaryNote(_ round: KasusDrillRound<Self>) -> String? {
        kind == .englischeFalle
            ? "These are the sentences where English points at the wrong case. The verbs are a list, not a rule."
            : "Recognition only: this round counts for your streak, never for the coach's case skills."
    }

    /// The buttons, cut to the unit's cases only at the easiest setting.
    private var questions: [KasusQuestion] {
        KasusQuestion.buttons(cases: help.limitsToUnitCases ? unit.casesInPlay : nil)
    }

    /// The other spans of this sentence the round still asks, so they can be ringed dashed.
    private func siblings(_ ctx: KasusDrillContext<Self>) -> [String] {
        guard help.ringsEveryPhrase else { return [] }
        return ctx.round.items
            .filter { $0.playable.id == ctx.item.playable.id && $0.targetIndex != ctx.item.targetIndex }
            .map(\.english)
    }

    /// The cases already answered on this sentence, so they keep their colour while the rest of it
    /// is asked.
    private func given(_ ctx: KasusDrillContext<Self>) -> [Int: GrammarCase] {
        var given: [Int: GrammarCase] = [:]
        for (index, answer) in ctx.round.answers.enumerated() {
            guard ctx.round.items.indices.contains(index) else { continue }
            let answered = ctx.round.items[index]
            guard answered.playable.id == ctx.item.playable.id else { continue }
            given[answered.targetIndex] = answer.graded.kasus
        }
        return given
    }

    /// „Fall 2 von 3“ while a sentence is asked whole.
    private func counter(_ ctx: KasusDrillContext<Self>) -> String? {
        let group = ctx.round.items.filter { $0.playable.id == ctx.item.playable.id }
        guard group.count > 1, let position = group.firstIndex(where: { $0.id == ctx.item.id }) else { return nil }
        return "Fall \(position + 1) von \(group.count)"
    }
}
