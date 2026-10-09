//
//  GrammarDrillShell.swift
//  german-ai-flashcards
//
//  The one screen every drill plays on, laid out like the Schnellrunde it grew out of: a strip
//  of dots on top, the module's stage, the hero in the free space, the answer panel pinned in
//  the thumb zone (the verdict with its why sliding in above the inputs, a Weiter slot that never
//  moves), and a summary at the end. The shell owns the round and every piece of state; the
//  module (`KasusDrillModule`) brings the items, the grading and the views.
//
//  One round per screen, handed up once through `onComplete` for `KasusService.recordRound`. A
//  DEBUG prefill (a non-nil `session.prefill`) is never recorded and plays no haptics. Never green
//  or red: a right pick takes the case colour, a miss is grey (`KasusFeedback`). Answers given
//  with the article table pinned are recorded as scaffolded.
//

import SwiftUI

struct GrammarDrillShell<Module: KasusDrillModule>: View {
    /// Builds the module for a session; called again when a mode switch changes the variant.
    let make: (GrammarDrillSession) -> Module
    var hapticMode: HapticFeedbackMode = .all
    /// Called once per finished round; `ContentView` hands it to `KasusService.recordRound`.
    var onComplete: (KasusRoundResult) -> Void
    var onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme

    @State private var session: GrammarDrillSession
    @State private var module: Module
    /// Built on appear, not in init: composing audits a whole item bank, and a cover's content
    /// is re-evaluated on every render of its presenter.
    @State private var round: KasusDrillRound<Module>?
    @State private var didSetUp = false
    /// The pick on the step being shown, until Weiter.
    @State private var picked: Module.Pick?
    /// The graded step being shown, until Weiter.
    @State private var answer: KasusGradedAnswer?
    /// A `.partial` outcome's line, until Weiter.
    @State private var partialLine: PartialLine?
    @State private var showEnglish = false
    @State private var startedAt = Date()
    /// DEBUG prefill: the answers weren't the learner's, so the round is never recorded.
    @State private var prefilled = false
    @State private var recorded = false
    @State private var rightCount = 0
    @State private var slipCount = 0
    @State private var wrongCount = 0
    /// The question screen's height, which caps the feedback card and sizes a stage.
    @State private var playHeight: CGFloat = 0
    @State private var referencePinned = false

    /// Wide enough for a sentence in large type; iPad centres it.
    private let contentWidth: CGFloat = 640

    private struct PartialLine: Hashable {
        let text: String
        let right: Bool
    }

    init(session: GrammarDrillSession, make: @escaping (GrammarDrillSession) -> Module,
         hapticMode: HapticFeedbackMode = .all,
         onComplete: @escaping (KasusRoundResult) -> Void, onDismiss: @escaping () -> Void) {
        self.make = make
        self.hapticMode = hapticMode
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        _session = State(initialValue: session)
        _module = State(initialValue: make(session))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let round, !round.isFinished, let ctx = context(round) {
                    play(round, ctx)
                } else if let round {
                    ScrollView {
                        summary(round)
                            .padding()
                            .frame(maxWidth: contentWidth)
                            .frame(maxWidth: .infinity)
                    }
                } else if didSetUp {
                    ContentUnavailableView("Noch nichts zu üben · Nothing to play yet", systemImage: module.meta.symbol,
                                           description: Text("This unit has no \(module.meta.germanTitle) items."))
                } else {
                    Color.clear
                }
            }
            .background(ThemedBackground().ignoresSafeArea())
            .kasusReference(pinned: module.meta.allowsReference ? $referencePinned : nil)
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let round, let ctx = context(round) {
                        module.toolbar(ctx)
                    }
                }
            }
        }
        .onAppear(perform: setUp)
        .sensoryFeedback(.success, trigger: rightCount) { old, new in
            new > old && hapticMode.playsSuccess
        }
        .sensoryFeedback(.error, trigger: wrongCount) { old, new in
            new > old && hapticMode.playsError
        }
        // A slip only gets a light tap: it was close, and the header says „Fast“, not wrong.
        .sensoryFeedback(.impact(weight: .light), trigger: slipCount) { old, new in
            new > old && hapticMode.playsError
        }
        // Presented from the root cover, outside any themed stack, so it sets its own tint.
        .tint(appTheme.accent(model: nil))
    }

    // MARK: - The step on screen

    /// The step the screen is on: the one just answered until Weiter, else the round's current.
    private func shownIndex(_ round: KasusDrillRound<Module>) -> Int {
        answer != nil ? round.cursor - 1 : round.cursor
    }

    private func context(_ round: KasusDrillRound<Module>) -> KasusDrillContext<Module>? {
        let index = min(shownIndex(round), round.items.count - 1)
        guard round.items.indices.contains(index) else { return nil }
        return KasusDrillContext(
            session: session, round: round, item: round.items[index], stepIndex: index,
            picked: picked, answer: answer, partial: round.partial, partialLine: partialLine?.text,
            playHeight: playHeight, showEnglish: $showEnglish, referencePinned: referencePinned,
            pick: { choose($0) }, restart: { restart(variant: $0) }
        )
    }

    // MARK: - Play

    private func play(_ round: KasusDrillRound<Module>, _ ctx: KasusDrillContext<Module>) -> some View {
        VStack(spacing: 0) {
            KasusProgressStrip(marks: marks(round))
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxWidth: contentWidth)

            // Outside everything that changes identity per step, so a canvas lives for the round.
            module.stage(ctx)

            GeometryReader { geo in
                ScrollView {
                    module.hero(ctx)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: contentWidth)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            answerPanel(round, ctx)
                .padding(.horizontal)
                .padding(.bottom, 6)
                .frame(maxWidth: contentWidth)
                // Sized first, so at the largest text sizes the hero scrolls instead of Weiter
                // being squeezed onto the inputs.
                .layoutPriority(1)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { playHeight = $0 }
        .animation(.snappy(duration: 0.3), value: answer)
        .animation(.snappy(duration: 0.3), value: partialLine)
    }

    /// The verdict and its why (once answered), the inputs, then Weiter. The inputs never move:
    /// the slot under them holds a hint until Weiter takes its place.
    private func answerPanel(_ round: KasusDrillRound<Module>, _ ctx: KasusDrillContext<Module>) -> some View {
        VStack(spacing: 12) {
            if let answer {
                feedbackCard(verdict: verdict(answer), kasus: answer.kasus, why: answer.cardLine ?? answer.explanation)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            } else if let partialLine {
                feedbackCard(verdict: partialLine.right ? .right : .miss, kasus: nil, why: partialLine.text)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            }
            module.panel(ctx)
            Group {
                if answer != nil || partialLine != nil {
                    Button(action: next) {
                        Text(weiterLabel(round))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text(module.hint(ctx))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(minHeight: 50)
        }
    }

    /// The card's verdict: the answer's, unless the module says the last tap deserves its own.
    private func verdict(_ answer: KasusGradedAnswer) -> KasusVerdict {
        if let cardRight = answer.cardRight { return cardRight ? .right : .miss }
        return answer.isRight ? .right : answer.isSlip ? .slip : .miss
    }

    private func weiterLabel(_ round: KasusDrillRound<Module>) -> String {
        if partialLine != nil, answer == nil { return "Weiter" }
        return round.isFinished ? "Ergebnis · Results" : "Weiter"
    }

    /// The card keeps its frame; only what's inside scrolls once it passes the cap.
    private func feedbackCard(verdict: KasusVerdict, kasus: GrammarCase?, why: String) -> some View {
        KasusCappedScroll(maxHeight: playHeight > 0 ? max(110, playHeight * 0.34) : .infinity) {
            KasusFeedbackHeader(verdict: verdict, kasus: kasus)
            Text(kasusRich: why)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    /// One dot per step: its case colour once right, a half ring for a slip, a hollow ring once
    /// missed, the ring for the step being asked (only once Weiter has moved on from the
    /// answered one).
    private func marks(_ round: KasusDrillRound<Module>) -> [KasusProgressStrip.Mark] {
        round.items.indices.map { i in
            if i < round.answers.count {
                let graded = round.answers[i].graded
                return graded.isRight ? .right(graded.kasus) : graded.isSlip ? .slip : .miss
            }
            return i == round.cursor && answer == nil ? .current : .upcoming
        }
    }

    // MARK: - Answering

    /// The first pick counts; the inputs lock after it until Weiter.
    private func choose(_ pick: Module.Pick, haptics: Bool = true) {
        guard answer == nil, partialLine == nil, var round else { return }
        let outcome = round.answer(pick, with: module)
        switch outcome {
        case .graded(let graded):
            if referencePinned { round.markLastScaffolded() }
            self.round = round
            picked = pick
            answer = graded
            guard haptics else { return }
            if graded.cardRight ?? graded.isRight { rightCount += 1 } else if graded.isSlip { slipCount += 1 } else { wrongCount += 1 }
        case .partial(_, let line, let right):
            self.round = round
            picked = pick
            partialLine = PartialLine(text: line, right: right)
            guard haptics else { return }
            if right { rightCount += 1 } else { wrongCount += 1 }
        case .ignored:
            return
        }
    }

    /// Once per answer: a fast double tap on Weiter while it fades out must not skip a step or
    /// record the round twice.
    private func next() {
        guard let round else { return }
        if partialLine != nil, answer == nil {
            // The step goes on with its next tap.
            partialLine = nil
            picked = nil
            return
        }
        guard answer != nil else { return }
        answer = nil
        picked = nil
        partialLine = nil
        if round.isFinished { record() }
    }

    /// A fresh round over the same items in another variant. Only while nothing is answered.
    private func restart(variant: DrillVariant) {
        guard let round, round.answers.isEmpty, round.partial == nil, answer == nil, partialLine == nil else { return }
        session.variant = variant
        module = make(session)
        self.round = KasusDrillRound(items: round.items)
        picked = nil
    }

    /// „Noch eine Runde“: a new round, composed again.
    private func restartFresh() {
        var rng = KasusSeededRandom(seed: UInt64.random(in: 0...UInt64.max))
        round = module.compose(session, rng: &rng).map { KasusDrillRound(items: $0) }
        answer = nil
        picked = nil
        partialLine = nil
        startedAt = Date()
        prefilled = false
        recorded = false
    }

    // MARK: - Summary

    private func summary(_ round: KasusDrillRound<Module>) -> some View {
        let right = round.firstTryCount
        let misses = Array(round.answers.enumerated().filter { !$0.element.graded.isRight })
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ergebnis · Result")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(right) of \(round.answers.count)")
                    .font(.largeTitle.weight(.bold))
                Text(module.scoreLine(round))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            KasusProgressStrip(marks: marks(round), showsScore: false)
            ForEach(GrammarCase.allCases) { kasus in
                let rows = round.answers.filter { $0.graded.kasus == kasus }
                if !rows.isEmpty {
                    HStack {
                        CaseLabel(kasus: kasus, style: .name)
                            .frame(width: 130, alignment: .leading)
                        if module.meta.summaryShowsCodeWord {
                            codeText(kasus)
                                .font(.headline.weight(.heavy))
                        }
                        Spacer()
                        Text("\(rows.filter(\.graded.isRight).count) / \(rows.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            if !misses.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Die Fehler · Your misses")
                        .font(.subheadline.weight(.semibold))
                    ForEach(misses, id: \.offset) { index, miss in
                        VStack(alignment: .leading, spacing: 6) {
                            module.missText(round.items[index], miss)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(kasusRich: miss.graded.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
            if let note = module.summaryNote(round) {
                KasusNoteLine(text: note)
            }
            Button(action: restartFresh) {
                Text("Noch eine Runde · Again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Fertig", action: onDismiss)
                .frame(maxWidth: .infinity)
        }
    }

    /// Hands the round up for `KasusService.recordRound`: the streak, a `KasusRound` for Verlauf
    /// and the calendar, and the coach's skills from the answers that count.
    private func record() {
        guard !prefilled, !recorded, let round else { return }
        recorded = true
        onComplete(round.result(module: module, session: session,
                                durationSeconds: Int(Date().timeIntervalSince(startedAt))))
    }

    // MARK: - Setup

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        var rng = KasusSeededRandom(seed: session.prefill?.seed ?? UInt64.random(in: 0...UInt64.max))
        round = module.compose(session, rng: &rng).map { KasusDrillRound(items: $0) }
        #if DEBUG
        applyDebugPrefill()
        #endif
    }

    #if DEBUG
    /// `-kasus.debugAnswers right|mixed` plays the first four steps (mixed gets one in three
    /// wrong, slips where the item has one), and `-kasus.debugQuickState right|wrong|slip|done`
    /// answers the next one that way, or the whole round for the summary. Never recorded, and no
    /// haptics.
    private func applyDebugPrefill() {
        guard let prefill = session.prefill, var round else { return }
        let state = EndingsDebugState.fromLaunchArguments()
        guard prefill.answers != nil || state != nil else { return }
        let answers = prefill.answers ?? .mixed
        prefilled = true
        let played = state == .done ? round.items.count : min(4, round.items.count - 1)
        // A slip needs an item that has one; bring one forward.
        if state == .slip, let slippable = round.items.indices.dropFirst(played).first(where: {
            module.debugPick(for: round.items[$0], partial: nil, want: .slip) != nil
        }) {
            round.swapItems(played, slippable)
        }
        for i in 0..<played {
            let wrong = answers == .mixed && i % 3 == 1
            debugPlay(&round, want: wrong ? (i % 2 == 0 ? .slip : .wrong) : .right, finish: true)
        }
        self.round = round
        guard !round.isFinished, let state else { return }
        switch state {
        case .right: debugPlay(&round, want: .right, finish: false)
        case .wrong: debugPlay(&round, want: .wrong, finish: false)
        case .slip:  debugPlay(&round, want: .slip, finish: false)
        case .done:  break
        }
        self.round = round
    }

    /// Plays one step: a pick, or a walk (one mistake at most, then right). With `finish` the
    /// step is closed (as Weiter would); without it the verdict stays on screen.
    private func debugPlay(_ round: inout KasusDrillRound<Module>, want: KasusDebugWant, finish: Bool) {
        var want = want
        var taps = 0
        while let item = round.current, taps < 12 {
            taps += 1
            guard let pick = module.debugPick(for: item, partial: round.partial, want: want)
                    ?? module.debugPick(for: item, partial: round.partial, want: .wrong)
                    ?? module.debugPick(for: item, partial: round.partial, want: .right) else { return }
            let outcome = round.answer(pick, with: module)
            switch outcome {
            case .graded(let graded):
                if !finish {
                    picked = pick
                    answer = graded
                }
                return
            case .partial(_, let line, let right):
                if !finish {
                    picked = pick
                    partialLine = PartialLine(text: line, right: right)
                    return
                }
                want = .right
            case .ignored:
                return
            }
        }
    }
    #endif
}

#if DEBUG
/// `-kasus.debugQuickState right|wrong|slip|done`, with `-kasus.debugOpen <kind>:<topic>`: the
/// step the drill opens on, answered right, with a case miss or with a gender slip, or the round
/// played through to its summary.
enum EndingsDebugState: String {
    case right, wrong, slip, done

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> EndingsDebugState? {
        defaults.string(forKey: "kasus.debugQuickState").flatMap { EndingsDebugState(rawValue: $0.lowercased()) }
    }
}
#endif
