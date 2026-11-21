//
//  KasusDrillShellTests.swift
//  german-ai-flashcardsTests
//
//  The drill shell's round (`KasusDrillRound`) with a fake module: a graded tap closes the step,
//  a partial keeps it open, the result files under the kind's id, the DEBUG play-through makes
//  every n-th step wrong, and the real modules compose rounds for every unit that offers them.
//

import Foundation
import SwiftUI
import Testing
@testable import Die_Kartei

@Suite("Kasus drill shell")
struct KasusDrillShellTests {

    /// Two taps per item: the first is partial ("found"), the second grades.
    private struct TwoTapModule: KasusDrillModule {
        struct Item: Identifiable { let id: Int; let answer: String }
        typealias Pick = String
        typealias Partial = Int

        var kind: KasusDrillKind { .fehler }

        func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [Item]? {
            (0..<4).map { Item(id: $0, answer: "dem") }
        }

        func answer(_ pick: String, for item: Item, step: Int, partial: inout Int?) -> KasusDrillOutcome<Int> {
            if partial == nil {
                partial = 1
                return .partial(1, line: "found", right: pick == "find")
            }
            let right = pick == item.answer
            let result = KasusItemResult(kasus: .dativ, genus: .der, firstTry: right)
            return .graded(KasusGradedAnswer(outcome: right ? .right : .caseMiss, kasus: .dativ,
                                             explanation: "why", result: result))
        }

        func debugPick(for item: Item, partial: Int?, want: KasusDebugWant) -> String? {
            if partial == nil { return "find" }
            switch want {
            case .right: return item.answer
            case .wrong: return "den"
            case .slip:  return nil
            }
        }

        func hero(_ ctx: KasusDrillContext<Self>) -> some View { EmptyView() }
        func panel(_ ctx: KasusDrillContext<Self>) -> some View { EmptyView() }
        func hint(_ ctx: KasusDrillContext<Self>) -> String { "" }
    }

    @Test("A partial keeps the step open; a graded tap closes it; the result files under the kind")
    @MainActor
    func partialThenGraded() {
        let module = TwoTapModule()
        let session = GrammarDrillSession(kind: .fehler, topic: .kasus(.dativ))
        var rng = KasusSeededRandom(seed: 1)
        var round = KasusDrillRound<TwoTapModule>(items: module.compose(session, rng: &rng)!)
        #expect(round.cursor == 0 && !round.isFinished && round.partial == nil)
        if case .partial(let state, let line, let right) = round.answer("find", with: module) {
            #expect(state == 1 && line == "found" && right)
        } else { Issue.record("expected a partial outcome") }
        #expect(round.cursor == 0 && round.partial == 1)
        if case .graded(let graded) = round.answer("den", with: module) {
            #expect(!graded.isRight && graded.outcome == .caseMiss)
        } else { Issue.record("expected a graded outcome") }
        #expect(round.cursor == 1 && round.partial == nil && round.answers.count == 1)
        round.markLastScaffolded()
        #expect(round.answers[0].graded.result.scaffolded)
        #expect(!KasusService.countsTowardSkill(round.answers[0].graded.result, step: .fehler, hint: nil))

        _ = round.answer("find", with: module)
        _ = round.answer("dem", with: module)
        let result = round.result(module: module, session: session, durationSeconds: 9)
        #expect(result.storyID == "fehler-dativ" && result.step == .fehler && result.topic == .kasus(.dativ))
        #expect(result.items.count == 2 && result.firstTryCount == 1 && result.id == round.id)
    }

    @Test("The DEBUG play-through makes every n-th step wrong and finishes the round")
    @MainActor
    func playThrough() {
        let module = TwoTapModule()
        let session = GrammarDrillSession(kind: .fehler, topic: .kasus(.dativ))
        var rng = KasusSeededRandom(seed: 1)
        var round = KasusDrillRound<TwoTapModule>(items: module.compose(session, rng: &rng)!)
        round.playThrough(with: module, wrongEvery: 2)
        #expect(round.isFinished && round.answers.count == 4)
        #expect(round.answers.map(\.graded.isRight) == [true, false, true, false])
    }

    @Test("An ignored pick changes nothing")
    @MainActor
    func ignored() {
        let session = GrammarDrillSession(kind: .probe, topic: .kasus(.genitiv))
        let module = ProbeModule(session: session)
        var rng = KasusSeededRandom(seed: 3)
        guard let items = module.compose(session, rng: &rng) else { Issue.record("no items"); return }
        var round = KasusDrillRound<ProbeModule>(items: items)
        if case .ignored = round.answer(.same(true), with: module) {} else { Issue.record("a Probe takes forms only") }
        #expect(round.cursor == 0 && round.answers.isEmpty)
    }

    @Test("Every shipped kind composes a round where its unit offers it, and files under its id")
    @MainActor
    func modulesCompose() {
        for kind in [KasusDrillKind.quick, .build, .roles, .wer, .probe, .dativVerbs, .fehler, .bridge] {
            for unit in KasusUnit.allCases {
                let topic = GrammarTopic.kasus(unit)
                let offered = topic.exercises().contains(kind)
                let result = kind.debugRound(topic: topic, wrongEvery: 3, seed: 42)
                #expect((result != nil) == offered, "\(kind) in \(unit)")
                if let result {
                    #expect(result.storyID == kind.step.roundID(topicKey: unit.rawValue))
                    #expect(result.step == kind.step && !result.items.isEmpty)
                    #expect(result.items.contains { !$0.firstTry }, "\(kind) in \(unit) has a wrong answer")
                }
            }
        }
        // Die Tabelle generates its chart, so it composes on any topic; it is launched from the
        // Artikel room on Alle Fälle, and a round is the whole table whatever the shape.
        for shape in ArticleTableShape.allCases {
            for chart in ArticleChart.allCases {
                var session = GrammarDrillSession(kind: .tabelle, topic: .kasus(.alleFaelle))
                session.variant = .table(TableConfig(chart: chart, shape: shape))
                let result = KasusDrillKind.tabelle.debugRound(session: session, wrongEvery: 3, seed: 42)
                #expect(result?.storyID == "tabelle-alleFaelle" && result?.step == .tabelle)
                #expect(result?.items.count == ArticleTableRound.cellCount, "\(chart) \(shape)")
                #expect(result?.items.contains { !$0.firstTry } == true)
                // Every cell of the chart exactly once, so the four cases are always in play.
                let cells = Set((result?.items ?? []).map { KasusTableCell(kasus: $0.kasus, genus: $0.genus) })
                #expect(cells.count == ArticleTableRound.cellCount, "\(chart) \(shape) repeats a cell")
            }
        }
        // The reflexive drills compose from the bundled gap-choice items, both cases in a case round.
        for kind in [KasusDrillKind.reflexCase, .reflexPerson] {
            let result = kind.debugRound(topic: .reflexiv, wrongEvery: 3, seed: 42)
            #expect(result?.storyID == kind.step.roundID(topicKey: "reflexiv") && result?.topic == .reflexiv)
            #expect(result?.items.count == kind.meta.roundSize, "\(kind): \(result?.items.count ?? 0) items")
            if kind == .reflexCase {
                #expect(result?.items.contains { $0.kasus == .akkusativ } == true && result?.items.contains { $0.kasus == .dativ } == true)
            }
            #expect(result?.items.contains { !$0.firstTry } == true)
            for unit in KasusUnit.allCases { #expect(kind.debugRound(topic: .kasus(unit), wrongEvery: 3, seed: 1) == nil) }
        }
    }

    @Test("The same seed composes the same endings round twice")
    @MainActor
    func seededEndings() {
        let session = GrammarDrillSession(kind: .quick, topic: .kasus(.dativ))
        let module = EndingsModule(session: session)
        var a = KasusSeededRandom(seed: 9), b = KasusSeededRandom(seed: 9)
        let first = module.compose(session, rng: &a)!.map { "\($0.frame.singular)|\($0.noun.singular)|\($0.determiner)" }
        let second = module.compose(session, rng: &b)!.map { "\($0.frame.singular)|\($0.noun.singular)|\($0.determiner)" }
        #expect(first == second && first.count == 10)
        #expect(module.hint(KasusDrillContext(session: session, round: KasusDrillRound(items: []), item: EndingsQuestion.round(cases: [.dativ])[0], stepIndex: 0, picked: nil, answer: nil, partial: nil, partialLine: nil, playHeight: 0, showEnglish: .constant(false), referencePinned: false, pick: { _ in }, restart: { _ in }, finish: {})) == "Tap the article that fits.")
    }

    @Test("Rollen in Schritt für Schritt walks a phrase as partials until the deciding question")
    @MainActor
    func rollenWalk() {
        var session = GrammarDrillSession(kind: .roles, topic: .kasus(.dativ))
        session.variant = .concept(ConceptConfig(exercise: .roles, rolesMode: .schritt))
        let module = RollenModule(session: session)
        var rng = KasusSeededRandom(seed: 7)
        guard let items = module.compose(session, rng: &rng), let first = items.first,
              let actual = first.askedRole else { Issue.record("no Rollen items"); return }
        var round = KasusDrillRound<RollenModule>(items: items)
        var taps = 0
        var finished = false
        while !finished, taps < 8 {
            let question = round.partial?.current ?? KasusRole.walkSteps(for: .dativ).first!
            let outcome = round.answer(.step(question, yes: question == actual), with: module)
            taps += 1
            switch outcome {
            case .partial(_, _, let right): #expect(right)
            case .graded(let graded):
                finished = true
                #expect(graded.isRight && graded.cardLine != nil && graded.cardRight == true)
            case .ignored: Issue.record("ignored at tap \(taps)")
            }
        }
        #expect(finished && round.cursor == 1 && round.partial == nil)
    }

    @Test("The debug-open argument parses every shell kind by its raw value, and nothing else as one")
    func debugOpenParses() {
        #expect(KasusDebugOpen(argument: "quick:dativ") == .drill(.quick, .kasus(.dativ)))
        #expect(KasusDebugOpen(argument: "build:Dativ") == .drill(.build, .kasus(.dativ)))
        #expect(KasusDebugOpen(argument: "roles:akkusativ") == .drill(.roles, .kasus(.akkusativ)))
        #expect(KasusDebugOpen(argument: "probe:genitiv")?.id == "probe:genitiv")
        #expect(KasusDebugOpen(argument: "fill:dativ") == nil)
        #expect(KasusDebugOpen(argument: "quick:nirgends") == nil)
        #expect(KasusDebugOpen(argument: "fill") == .story(.fill))
        #expect(KasusDebugOpen(argument: "tabelle:alleFaelle") == .drill(.tabelle, .kasus(.alleFaelle)))
    }
}
