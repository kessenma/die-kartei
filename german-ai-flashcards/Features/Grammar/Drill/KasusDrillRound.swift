//
//  KasusDrillRound.swift
//  german-ai-flashcards
//
//  One round of a drill module: its steps in play order, the answers so far, the scratch state
//  of a step under way, and the result `KasusService.recordRound` takes. The round holds no
//  module; the shell passes its module in, so a rebuilt module (a mode switch) plays the same
//  items.
//

import Foundation

struct KasusDrillRound<Module: KasusDrillModule> {
    /// Becomes `KasusRoundResult.id` and so `KasusRound.roundKey`.
    let id = UUID()
    private(set) var items: [Module.Item]
    private(set) var answers: [KasusDrillAnswer<Module.Pick>] = []
    /// A step under way (a walk between its questions).
    private(set) var partial: Module.Partial?

    init(items: [Module.Item]) {
        self.items = items
    }

    var cursor: Int { answers.count }
    var isFinished: Bool { cursor >= items.count }
    var current: Module.Item? { isFinished ? nil : items[cursor] }
    var firstTryCount: Int { answers.filter(\.graded.isRight).count }

    /// Grades a tap on the current step with `module`. A `.graded` outcome closes the step; a
    /// `.partial` keeps it open with its scratch state.
    mutating func answer(_ pick: Module.Pick, with module: Module) -> KasusDrillOutcome<Module.Partial> {
        guard let item = current else { return .ignored }
        var scratch = partial
        let outcome = module.answer(pick, for: item, step: cursor, partial: &scratch)
        switch outcome {
        case .graded(let graded):
            answers.append(KasusDrillAnswer(pick: pick, graded: graded))
            partial = nil
        case .partial(let state, _, _):
            partial = state
        case .ignored:
            break
        }
        return outcome
    }

    /// Marks the last answer's result as scaffolded (the table was pinned when it was given).
    mutating func markLastScaffolded() {
        guard var last = answers.popLast() else { return }
        var graded = last.graded
        graded.result.scaffolded = true
        last = KasusDrillAnswer(pick: last.pick, graded: graded)
        answers.append(last)
    }

    /// Brings the item at `index` forward to `position` (the DEBUG prefill wants a slippable
    /// question next). Only before that position is answered.
    mutating func swapItems(_ position: Int, _ index: Int) {
        guard items.indices.contains(position), items.indices.contains(index), position >= cursor else { return }
        items.swapAt(position, index)
    }

    /// The round for `KasusService.recordRound`, filed under the kind's own id in the topic.
    func result(module: Module, session: GrammarDrillSession, durationSeconds: Int) -> KasusRoundResult {
        KasusRoundResult(storyID: module.kind.step.roundID(topicKey: session.topic.key), topic: session.topic,
                         step: module.kind.step, items: answers.map(\.graded.result),
                         durationSeconds: durationSeconds, id: id)
    }

    #if DEBUG
    /// Plays the round through for the seeder: every `wrongEvery`-th step wrong (every tap of
    /// it, so a multi-tap step grades wrong), the rest right.
    mutating func playThrough(with module: Module, wrongEvery: Int) {
        var step = 0
        while let item = current {
            let want: KasusDebugWant = wrongEvery > 0 && step % wrongEvery == wrongEvery - 1 ? .wrong : .right
            var taps = 0
            while !isFinished, cursor == step, taps < 12 {
                guard let pick = module.debugPick(for: item, partial: partial, want: want)
                        ?? module.debugPick(for: item, partial: partial, want: .right) else { return }
                if case .ignored = answer(pick, with: module) { return }
                taps += 1
            }
            step += 1
        }
    }
    #endif
}
