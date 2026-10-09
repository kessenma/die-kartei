//
//  KasusDrillKind+Shell.swift
//  german-ai-flashcards
//
//  The one switch over modules in the app: which module a kind plays on the shell. `ContentView`
//  asks it for the view behind `Activity.grammarDrill`, and the DEBUG seeder for a round played
//  through. Adding a kind means adding its module here and nowhere else on the launch path.
//

import SwiftUI

extension KasusDrillKind {
    /// The drill screen for a session, as the activity cover shows it.
    @MainActor
    func makeView(_ session: GrammarDrillSession, hapticMode: HapticFeedbackMode,
                  onComplete: @escaping (KasusRoundResult) -> Void, onDismiss: @escaping () -> Void) -> AnyView {
        switch self {
        case .quick, .build, .blitz, .pair, .dativVerbs:
            shell(session, hapticMode, onComplete, onDismiss, make: EndingsModule.init(session:))
        case .roles:
            shell(session, hapticMode, onComplete, onDismiss, make: RollenModule.init(session:))
        case .wer:
            shell(session, hapticMode, onComplete, onDismiss, make: WerModule.init(session:))
        case .probe:
            shell(session, hapticMode, onComplete, onDismiss, make: ProbeModule.init(session:))
        case .reflexCase, .reflexPerson:
            shell(session, hapticMode, onComplete, onDismiss, make: GapChoiceModule.init(session:))
        case .fehler, .bridge:
            shell(session, hapticMode, onComplete, onDismiss, make: UnbuiltModule.init(session:))
        }
    }

    /// The module type is erased here and nowhere else: the cover holds an `AnyView`, as the Mac
    /// cover registry already does.
    @MainActor
    private func shell<M: KasusDrillModule>(_ session: GrammarDrillSession, _ hapticMode: HapticFeedbackMode,
                                            _ onComplete: @escaping (KasusRoundResult) -> Void,
                                            _ onDismiss: @escaping () -> Void,
                                            make: @escaping (GrammarDrillSession) -> M) -> AnyView {
        AnyView(GrammarDrillShell(session: session, make: make, hapticMode: hapticMode,
                                  onComplete: onComplete, onDismiss: onDismiss))
    }

    #if DEBUG
    /// A round of this kind played through by the module itself, for the seeder: every
    /// `wrongEvery`-th step wrong. Nil when the topic can't offer the kind.
    @MainActor
    func debugRound(topic: GrammarTopic, wrongEvery: Int, seed: UInt64) -> KasusRoundResult? {
        let session = GrammarDrillSession(kind: self, topic: topic)
        switch self {
        case .quick, .build, .blitz, .pair, .dativVerbs:
            return play(EndingsModule(session: session), session, wrongEvery: wrongEvery, seed: seed)
        case .roles:
            return play(RollenModule(session: session), session, wrongEvery: wrongEvery, seed: seed)
        case .wer:
            return play(WerModule(session: session), session, wrongEvery: wrongEvery, seed: seed)
        case .probe:
            return play(ProbeModule(session: session), session, wrongEvery: wrongEvery, seed: seed)
        case .reflexCase, .reflexPerson:
            return play(GapChoiceModule(session: session), session, wrongEvery: wrongEvery, seed: seed)
        case .fehler, .bridge:
            return nil
        }
    }

    @MainActor
    private func play<M: KasusDrillModule>(_ module: M, _ session: GrammarDrillSession,
                                           wrongEvery: Int, seed: UInt64) -> KasusRoundResult? {
        var rng = KasusSeededRandom(seed: seed)
        guard let items = module.compose(session, rng: &rng), !items.isEmpty else { return nil }
        var round = KasusDrillRound<M>(items: items)
        round.playThrough(with: module, wrongEvery: wrongEvery)
        return round.answers.isEmpty ? nil : round.result(module: module, session: session, durationSeconds: 0)
    }
    #endif
}
