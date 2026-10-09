//
//  KasusDrillModule.swift
//  german-ai-flashcards
//
//  What an exercise type gives the drill shell (`GrammarDrillShell`): its items, how a tap on
//  one is graded, and the views for the hero, the answer panel, an optional stage above the hero
//  and an optional toolbar item. The shell owns every piece of state (the round, the pick, the
//  card, the summary, haptics, recording, the DEBUG prefill); a module is a value that reads a
//  context and calls back.
//
//  A step is usually one tap. A multi-tap step (Rollen's Ja/Nein walk, Finde den Fehler's "found,
//  now fix it") keeps scratch state in `Partial` and answers `.partial` until the tap that grades.
//

import SwiftUI

// MARK: - Outcomes

/// One graded step, as the shell, the summary and `KasusService.recordRound` need it.
nonisolated struct KasusGradedAnswer: Hashable {
    let outcome: KasusItemOutcome
    /// The case the answer revealed: the header's colour, the progress dot, the summary's row.
    let kasus: GrammarCase
    /// Why, in the `KasusRich` markup; the summary's line under a miss.
    let explanation: String
    /// What the feedback card shows instead of the explanation (a walk's last line). Nil: the
    /// explanation.
    var cardLine: String? = nil
    /// The card's verdict when it isn't the answer's: a walk's last step was right although an
    /// earlier step cost the phrase. Nil: the answer's own.
    var cardRight: Bool? = nil
    /// What `recordRound` sees. The shell marks it scaffolded when the table was pinned.
    var result: KasusItemResult

    var isRight: Bool { outcome.isRight }
    var isSlip: Bool { outcome == .genderSlip || outcome == .numberSlip }
}

/// What one tap did.
nonisolated enum KasusDrillOutcome<Partial: Hashable>: Hashable {
    case graded(KasusGradedAnswer)
    /// The step stays open: a walk's next question, Finde den Fehler's "found, now fix it". The
    /// line is shown on the feedback card until Weiter.
    case partial(Partial, line: String, right: Bool)
    /// A pick the module doesn't take.
    case ignored
}

/// A step's answer with the pick that made it, as the shell keeps them.
nonisolated struct KasusDrillAnswer<Pick: Hashable>: Hashable {
    let pick: Pick
    let graded: KasusGradedAnswer
}

/// What the DEBUG prefill asks a module for.
nonisolated enum KasusDebugWant: Hashable {
    case right, wrong, slip
}

// MARK: - The module

@MainActor
protocol KasusDrillModule {
    /// One question. Identifiable so the shell can key panels and misses on it.
    associatedtype Item: Identifiable
    /// What the learner tapped.
    associatedtype Pick: Hashable
    /// Scratch state between the taps of one step. `Never` for a one-tap module, whose `answer`
    /// then spells `inout Never?`.
    associatedtype Partial: Hashable = Never
    associatedtype Hero: View
    associatedtype Panel: View
    associatedtype Stage: View = EmptyView
    associatedtype Toolbar: View = EmptyView

    /// The kind this module plays; its step is what the round records as.
    var kind: KasusDrillKind { get }

    /// The round's steps in play order. Nil when the topic can't offer the kind (no items, or a
    /// variant that would turn single-case).
    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [Item]?
    /// Grades a tap on `item`, the step at `step`, reading and writing the step's scratch state.
    func answer(_ pick: Pick, for item: Item, step: Int, partial: inout Partial?) -> KasusDrillOutcome<Partial>
    /// The pick the DEBUG prefill and the seeder make for `want`. Nil when the item has none
    /// (no gender slip on a plural question).
    func debugPick(for item: Item, partial: Partial?, want: KasusDebugWant) -> Pick?

    @ViewBuilder func hero(_ ctx: KasusDrillContext<Self>) -> Hero
    @ViewBuilder func panel(_ ctx: KasusDrillContext<Self>) -> Panel
    /// Above the hero, outside the per-step identity: the 3D word, a timer.
    @ViewBuilder func stage(_ ctx: KasusDrillContext<Self>) -> Stage
    /// A trailing toolbar item (Rollen's mode menu).
    @ViewBuilder func toolbar(_ ctx: KasusDrillContext<Self>) -> Toolbar
    /// The line under the inputs until a pick is made.
    func hint(_ ctx: KasusDrillContext<Self>) -> String
    /// A miss in the summary: the sentence with the answer in place.
    func missText(_ item: Item, _ answer: KasusDrillAnswer<Pick>) -> Text
    /// The summary's line under the score.
    func scoreLine(_ round: KasusDrillRound<Self>) -> String
    /// The summary's note at the bottom (recognition only …). Nil for none.
    func summaryNote(_ round: KasusDrillRound<Self>) -> String?
}

extension KasusDrillModule {
    var meta: KasusDrillMeta { kind.meta }

    func missText(_ item: Item, _ answer: KasusDrillAnswer<Pick>) -> Text {
        answer.graded.result.record.map(KasusConceptSentence.text) ?? Text("")
    }

    func scoreLine(_ round: KasusDrillRound<Self>) -> String { "right on the first try" }

    func summaryNote(_ round: KasusDrillRound<Self>) -> String? {
        meta.coachPolicy == .never
            ? "Recognition only: this round counts for your streak, never for the coach's case skills."
            : nil
    }
}

extension KasusDrillModule where Stage == EmptyView {
    func stage(_ ctx: KasusDrillContext<Self>) -> EmptyView { EmptyView() }
}

extension KasusDrillModule where Toolbar == EmptyView {
    func toolbar(_ ctx: KasusDrillContext<Self>) -> EmptyView { EmptyView() }
}

// MARK: - The context

/// What a module's views are handed: the step on screen and the shell's state around it. Views
/// read it and call `pick` or `restart`; they never hold state of their own about the round.
struct KasusDrillContext<Module: KasusDrillModule> {
    let session: GrammarDrillSession
    let round: KasusDrillRound<Module>
    /// The step on screen: the one just answered until Weiter, else the round's current.
    let item: Module.Item
    let stepIndex: Int
    /// This step's pick, until Weiter.
    let picked: Module.Pick?
    /// This step's grade, until Weiter.
    let answer: KasusGradedAnswer?
    /// The step's scratch state (a walk in progress).
    let partial: Module.Partial?
    /// A `.partial` outcome's line, shown on the card until Weiter.
    let partialLine: String?
    /// The play area's height, for a stage that takes a share of it.
    let playHeight: CGFloat
    /// The English toggle, kept across items.
    let showEnglish: Binding<Bool>
    /// The article table is pinned over the round.
    let referencePinned: Bool
    /// Hands a pick to the shell.
    let pick: (Module.Pick) -> Void
    /// Rebuilds the round over the same items with another variant (a mode switch). Only before
    /// the first answer; the shell ignores it afterwards.
    let restart: (DrillVariant) -> Void

    /// Something was answered or a step is under way: a mode can't change any more.
    var isLocked: Bool { !round.answers.isEmpty || partial != nil || partialLine != nil || answer != nil }

    /// A pick is showing (graded or partial): the inputs are locked until Weiter.
    var isShowingFeedback: Bool { answer != nil || partialLine != nil }
}
