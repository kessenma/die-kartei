//
//  ConceptModules.swift
//  german-ai-flashcards
//
//  The three Verstehen exercises on the drill shell: Rollen (role chips, or the Kasus-Check one
//  question at a time as a multi-tap step), Wer macht was? (two phrases, or two pictures, and
//  „Gleich oder anders?“) and Die Probe (the test noun's forms). The items, the round's
//  composition and the grading are `KasusConceptRound`'s (Services/KasusConcepts.swift), so the
//  engine tests keep driving the same code; the panels and heroes are the ones in
//  KasusConceptPanels.swift.
//

import SwiftUI

// MARK: - Shared

/// One step of a Verstehen round: the playable item and, for Rollen, the phrase asked.
struct KasusConceptDrillItem: Identifiable {
    let playable: KasusConceptPlayable
    /// Rollen: the asked target's index. Nil for the other exercises.
    let target: Int?

    var id: String { target.map { "\(playable.id)#\($0)" } ?? playable.id }

    var askedTarget: KasusLocatedTarget? { target.flatMap(playable.target) }
    var askedRole: KasusRole? { target.flatMap { playable.facts.roles[$0] } }
}

enum KasusConceptDrill {
    /// The seeded round from the bank as drill items, one per step. DEBUG: `-kasus.debugItem <id>`
    /// puts that item first, so a screenshot can land on it.
    @MainActor
    static func items(unit: KasusUnit, exercise: KasusConceptExercise, rolesMode: KasusRolesMode,
                      session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [KasusConceptDrillItem]? {
        var round = KasusService.conceptRound(unit: unit, exercise: exercise, rolesMode: rolesMode, seed: rng.next())
        #if DEBUG
        if session.prefill != nil, let id = UserDefaults.standard.string(forKey: "kasus.debugItem"),
           let current = round, !current.items.isEmpty {
            var items = current.items
            if let at = items.firstIndex(where: { $0.id == id }) {
                items.insert(items.remove(at: at), at: 0)
            } else if let extra = KasusService.conceptPlayables(unit: unit, exercise: exercise).first(where: { $0.id == id }) {
                items[0] = extra
            }
            round = KasusConceptRound(unit: unit, exercise: exercise, rolesMode: rolesMode, items: items)
        }
        #endif
        guard let round else { return nil }
        return round.steps.map { KasusConceptDrillItem(playable: round.items[$0.item], target: $0.target) }
    }

    static func graded(_ answer: KasusConceptAnswer, cardLine: String? = nil, cardRight: Bool? = nil) -> KasusGradedAnswer {
        KasusGradedAnswer(outcome: answer.outcome, kasus: answer.kasus, explanation: answer.explanation,
                          cardLine: cardLine, cardRight: cardRight, result: answer.result)
    }

    /// The concept answer a hero wants, rebuilt from the shell's.
    static func conceptAnswer(step: Int, _ answer: KasusDrillAnswer<KasusConceptPick>) -> KasusConceptAnswer? {
        guard let record = answer.graded.result.record else { return nil }
        return KasusConceptAnswer(step: step, pick: answer.pick, outcome: answer.graded.outcome, kasus: answer.graded.kasus,
                                  explanation: answer.graded.explanation, record: record, result: answer.graded.result)
    }

    /// The answered step's concept answer, while its card is up.
    static func shownAnswer<M: KasusDrillModule>(_ ctx: KasusDrillContext<M>) -> KasusConceptAnswer? where M.Pick == KasusConceptPick {
        guard ctx.answer != nil, ctx.round.answers.indices.contains(ctx.stepIndex) else { return nil }
        return conceptAnswer(step: ctx.stepIndex, ctx.round.answers[ctx.stepIndex])
    }
}

// MARK: - Rollen

struct RollenModule: KasusDrillModule {
    typealias Item = KasusConceptDrillItem
    typealias Pick = KasusConceptPick
    typealias Partial = KasusConceptWalk

    let unit: KasusUnit
    let mode: KasusRolesMode

    var kind: KasusDrillKind { .roles }

    init(session: GrammarDrillSession) {
        unit = session.topic.unit ?? .dativ
        if case .concept(let config) = session.variant { mode = config.rolesMode } else { mode = .direkt }
    }

    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [KasusConceptDrillItem]? {
        KasusConceptDrill.items(unit: unit, exercise: .roles, rolesMode: mode, session: session, rng: &rng)
    }

    func answer(_ pick: KasusConceptPick, for item: KasusConceptDrillItem, step: Int,
                partial: inout KasusConceptWalk?) -> KasusDrillOutcome<KasusConceptWalk> {
        guard let target = item.askedTarget, let actual = item.askedRole else { return .ignored }
        switch (mode, pick) {
        case (.direkt, .role(let role)):
            let answer = KasusConceptRound.gradeRole(picked: role, right: role == actual, target: target, actual: actual,
                                                     item: item.playable, step: step, pick: pick)
            return .graded(KasusConceptDrill.graded(answer))
        case (.schritt, .step(_, let yes)):
            var walk = partial ?? KasusConceptWalk(questions: KasusRole.walkSteps(for: unit))
            guard walk.current != nil else { return .ignored }
            let result = KasusConceptRound.walk(&walk, yes: yes, target: target, actual: actual, item: item.playable, step: step)
            if let finished = result.finished {
                partial = nil
                return .graded(KasusConceptDrill.graded(finished, cardLine: result.line, cardRight: result.right))
            }
            partial = walk
            return .partial(walk, line: result.line, right: result.right)
        default:
            return .ignored
        }
    }

    func debugPick(for item: KasusConceptDrillItem, partial: KasusConceptWalk?, want: KasusDebugWant) -> KasusConceptPick? {
        guard let actual = item.askedRole, want != .slip else { return nil }
        switch mode {
        case .direkt:
            if want == .right { return .role(actual) }
            return .role(KasusRole.chips(for: unit).first { $0 != actual } ?? actual)
        case .schritt:
            guard let question = partial?.current ?? KasusRole.walkSteps(for: unit).first else { return nil }
            let decides = question == actual
            return .step(question, yes: want == .wrong ? !decides : decides)
        }
    }

    // MARK: Views

    func hero(_ ctx: KasusDrillContext<Self>) -> some View {
        KasusRolesHero(item: ctx.item.playable, target: ctx.item.askedTarget, answers: answersOnItem(ctx),
                       showEnglish: ctx.showEnglish)
    }

    /// The answers given on the item on screen, by target index.
    private func answersOnItem(_ ctx: KasusDrillContext<Self>) -> [Int: KasusConceptAnswer] {
        var out: [Int: KasusConceptAnswer] = [:]
        for (i, given) in ctx.round.answers.enumerated() where ctx.round.items[i].playable.id == ctx.item.playable.id {
            if let index = ctx.round.items[i].target, let answer = KasusConceptDrill.conceptAnswer(step: i, given) {
                out[index] = answer
            }
        }
        return out
    }

    func panel(_ ctx: KasusDrillContext<Self>) -> some View {
        let item = ctx.item
        let target = item.askedTarget
        let actual = item.askedRole
        return Group {
            if mode == .schritt {
                let question = pickedQuestion(ctx) ?? ctx.partial?.current ?? KasusRole.walkSteps(for: unit).first
                let decides = question != nil && question == actual
                KasusWalkPanel(
                    question: question,
                    picked: pickedYesNo(ctx),
                    answer: decides ? "Ja" : "Nein",
                    kasus: ctx.answer?.kasus ?? target?.kasus ?? .nominativ,
                    decides: decides || ctx.answer != nil,
                    graded: ctx.isShowingFeedback
                ) { yes in
                    if let question { ctx.pick(.step(question, yes: yes)) }
                }
                .id("\(ctx.stepIndex)-\(question?.rawValue ?? "")")
            } else {
                KasusRoleGrid(
                    roles: KasusRole.chips(for: unit),
                    unit: unit,
                    picked: pickedRole(ctx),
                    actual: ctx.answer == nil ? nil : actual,
                    revealedCase: target.flatMap { t in actual?.revealedCase(for: t) }
                ) { role in
                    ctx.pick(.role(role))
                }
                // Keyed on the step shown, which holds through the pick, so the shake and the pop play.
                .id(ctx.stepIndex)
            }
        }
    }

    private func pickedRole(_ ctx: KasusDrillContext<Self>) -> KasusRole? {
        if case .role(let role)? = ctx.picked { return role }
        return nil
    }

    private func pickedQuestion(_ ctx: KasusDrillContext<Self>) -> KasusRole? {
        if case .step(let question, _)? = ctx.picked { return question }
        return nil
    }

    private func pickedYesNo(_ ctx: KasusDrillContext<Self>) -> String? {
        if case .step(_, let yes)? = ctx.picked { return yes ? "Ja" : "Nein" }
        return nil
    }

    func toolbar(_ ctx: KasusDrillContext<Self>) -> some View {
        RollenModeMenu(mode: mode, locked: ctx.isLocked) { newMode in
            UserDefaults.standard.set(newMode.rawValue, forKey: KasusRolesMode.storageKey)
            ctx.restart(.concept(ConceptConfig(exercise: .roles, rolesMode: newMode)))
        }
    }

    func hint(_ ctx: KasusDrillContext<Self>) -> String {
        mode == .schritt ? "Answer the question for the ringed phrase." : "Tap the ringed phrase's role."
    }

    func scoreLine(_ round: KasusDrillRound<Self>) -> String {
        mode == .schritt ? "phrases walked through without a wrong step" : "right on the first try"
    }
}

/// Rollen's toolbar: Schritt für Schritt or Direkt, remembered; locked once an answer is in.
struct RollenModeMenu: View {
    let mode: KasusRolesMode
    let locked: Bool
    let onChange: (KasusRolesMode) -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { mode }, set: { newMode in
                guard !locked, newMode != mode else { return }
                onChange(newMode)
            })) {
                ForEach(KasusRolesMode.allCases) { mode in
                    Text("\(mode.germanLabel) · \(mode.englishLabel)").tag(mode)
                }
            } label: {
                Text("Fragen · How to ask")
            }
            .pickerStyle(.inline)
            .disabled(locked)
            if locked {
                Text("Finish this round to change it.")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                Text(mode.germanLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.tint.opacity(0.12), in: appTheme.pillShape)
            .contentShape(appTheme.pillShape)
        }
        .accessibilityLabel("How Rollen asks")
        .accessibilityValue(mode.germanLabel)
    }
}

// MARK: - Wer macht was?

struct WerModule: KasusDrillModule {
    typealias Item = KasusConceptDrillItem
    typealias Pick = KasusConceptPick
    typealias Partial = Never

    let unit: KasusUnit
    var kind: KasusDrillKind { .wer }

    init(session: GrammarDrillSession) {
        unit = session.topic.unit ?? .akkusativ
    }

    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [KasusConceptDrillItem]? {
        KasusConceptDrill.items(unit: unit, exercise: .wer, rolesMode: .direkt, session: session, rng: &rng)
    }

    func answer(_ pick: KasusConceptPick, for item: KasusConceptDrillItem, step: Int, partial: inout Never?) -> KasusDrillOutcome<Never> {
        let answer: KasusConceptAnswer?
        switch pick {
        case .option(let picked): answer = KasusConceptRound.gradeOption(picked, item: item.playable, step: step)
        case .same(let picked):   answer = KasusConceptRound.gradeSame(picked, item: item.playable, step: step)
        default:                  answer = nil
        }
        return answer.map { .graded(KasusConceptDrill.graded($0)) } ?? .ignored
    }

    func debugPick(for item: KasusConceptDrillItem, partial: Never?, want: KasusDebugWant) -> KasusConceptPick? {
        guard want != .slip else { return nil }
        let wrong = want == .wrong
        if let doer = item.playable.doer {
            let other = item.playable.options.first { $0.index != doer.index }?.index ?? doer.index
            return .option(wrong ? other : doer.index)
        }
        if let same = item.playable.same { return .same(wrong ? !same : same) }
        return nil
    }

    func hero(_ ctx: KasusDrillContext<Self>) -> some View {
        KasusWerHero(item: ctx.item.playable, answer: KasusConceptDrill.shownAnswer(ctx), showEnglish: ctx.showEnglish)
    }

    func panel(_ ctx: KasusDrillContext<Self>) -> some View {
        let item = ctx.item.playable
        return Group {
            if let same = item.same {
                KasusOptionGrid(options: ["Gleich", "Anders"], answer: same ? "Gleich" : "Anders",
                                kasus: ctx.answer?.kasus ?? .nominativ, picked: pickedSameLabel(ctx), columns: 2, rowHeight: 58) { option in
                    ctx.pick(.same(option == "Gleich"))
                }
            } else if let doer = item.doer, item.hasPictureChoice {
                KasusPictureChoice(item: item, doer: doer, picked: pickedOptionIndex(ctx)) { index in
                    ctx.pick(.option(index))
                }
            } else if let doer = item.doer {
                let options = item.options
                KasusOptionGrid(options: options.map(\.surface), answer: doer.surface, kasus: .nominativ,
                                picked: pickedOptionIndex(ctx).flatMap { item.target($0)?.surface }, columns: 2, rowHeight: 58,
                                font: .title3.weight(.semibold)) { option in
                    if let target = options.first(where: { $0.surface == option }) { ctx.pick(.option(target.index)) }
                }
            }
        }
        .id(item.id)
    }

    private func pickedSameLabel(_ ctx: KasusDrillContext<Self>) -> String? {
        if case .same(let same)? = ctx.picked { return same ? "Gleich" : "Anders" }
        return nil
    }

    private func pickedOptionIndex(_ ctx: KasusDrillContext<Self>) -> Int? {
        if case .option(let index)? = ctx.picked { return index }
        return nil
    }

    func hint(_ ctx: KasusDrillContext<Self>) -> String {
        let item = ctx.item.playable
        return item.kind == .sameMeaning ? "Do the two sentences mean the same?"
            : item.hasPictureChoice ? "Tap the picture that fits the sentence."
            : "Who is the doer?"
    }
}

// MARK: - Die Probe

struct ProbeModule: KasusDrillModule {
    typealias Item = KasusConceptDrillItem
    typealias Pick = KasusConceptPick
    typealias Partial = Never

    let unit: KasusUnit
    var kind: KasusDrillKind { .probe }

    init(session: GrammarDrillSession) {
        unit = session.topic.unit ?? .dativ
    }

    private var includesGenitiv: Bool { unit.casesInPlay.contains(.genitiv) }

    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [KasusConceptDrillItem]? {
        KasusConceptDrill.items(unit: unit, exercise: .probe, rolesMode: .direkt, session: session, rng: &rng)
    }

    func answer(_ pick: KasusConceptPick, for item: KasusConceptDrillItem, step: Int, partial: inout Never?) -> KasusDrillOutcome<Never> {
        guard case .form(let form) = pick,
              let answer = KasusConceptRound.gradeForm(form, item: item.playable, step: step) else { return .ignored }
        return .graded(KasusConceptDrill.graded(answer))
    }

    func debugPick(for item: KasusConceptDrillItem, partial: Never?, want: KasusDebugWant) -> KasusConceptPick? {
        guard want != .slip, let probe = item.playable.probe else { return nil }
        let options = probe.options(includeGenitive: includesGenitiv)
        let miss = options.first { !probe.isRight($0) } ?? probe.answer
        return .form(want == .wrong ? miss : probe.answer)
    }

    func hero(_ ctx: KasusDrillContext<Self>) -> some View {
        Group {
            if let probe = ctx.item.playable.probe {
                KasusProbeHero(item: ctx.item.playable, probe: probe, answer: KasusConceptDrill.shownAnswer(ctx))
            }
        }
    }

    func panel(_ ctx: KasusDrillContext<Self>) -> some View {
        let item = ctx.item.playable
        return Group {
            if let probe = item.probe {
                let options = probe.options(includeGenitive: includesGenitiv)
                KasusOptionGrid(options: options, answer: probe.answer, kasus: probe.kasus,
                                picked: pickedForm(ctx), columns: options.count > 3 ? 2 : 3, rowHeight: 54) { option in
                    ctx.pick(.form(option))
                }
            }
        }
        .id(item.id)
    }

    private func pickedForm(_ ctx: KasusDrillContext<Self>) -> String? {
        if case .form(let form)? = ctx.picked { return form }
        return nil
    }

    func hint(_ ctx: KasusDrillContext<Self>) -> String {
        "Which form of the test noun fits the slot?"
    }
}

// MARK: - Not built yet

/// A kind in the registry whose module isn't written: the shell shows „Noch nichts zu üben“.
struct UnbuiltModule: KasusDrillModule {
    typealias Item = EndingsQuestion
    typealias Pick = String
    typealias Partial = Never

    let kind: KasusDrillKind

    init(session: GrammarDrillSession) { kind = session.kind }

    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [EndingsQuestion]? { nil }
    func answer(_ pick: String, for item: EndingsQuestion, step: Int, partial: inout Never?) -> KasusDrillOutcome<Never> { .ignored }
    func debugPick(for item: EndingsQuestion, partial: Never?, want: KasusDebugWant) -> String? { nil }
    func hero(_ ctx: KasusDrillContext<Self>) -> some View { EmptyView() }
    func panel(_ ctx: KasusDrillContext<Self>) -> some View { EmptyView() }
    func hint(_ ctx: KasusDrillContext<Self>) -> String { "" }
}

// MARK: - Previews

#Preview("Rollen · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            GrammarDrillShell(session: GrammarDrillSession(kind: .roles, topic: .kasus(.dativ)),
                              make: RollenModule.init(session:), onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}

#Preview("Wer macht was? · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            GrammarDrillShell(session: GrammarDrillSession(kind: .wer, topic: .kasus(.akkusativ)),
                              make: WerModule.init(session:), onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}

#Preview("Die Probe · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            GrammarDrillShell(session: GrammarDrillSession(kind: .probe, topic: .kasus(.genitiv)),
                              make: ProbeModule.init(session:), onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}
