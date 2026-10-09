//
//  KasusConceptView.swift
//  german-ai-flashcards
//
//  The activity that plays the three Verstehen exercises (Rollen, Wer macht was?, Die Probe),
//  laid out like the Schnellrunde: a strip of dots on top, the sentence as the hero in the free
//  space, the answer panel pinned in the thumb zone, and the verdict with its why sliding in
//  between, so nothing is ever pushed off screen. The panels themselves are in
//  KasusConceptPanels.swift.
//
//  One round per screen (`KasusConceptRound`), handed up once through `onComplete` for
//  `KasusService.recordRound`. Rollen's mode (Schritt für Schritt or Direkt) sits in the toolbar
//  and is remembered; it can't change once an answer is in. Never green or red: a right pick
//  takes the case color, a miss is grey (`KasusFeedback`).
//

import SwiftUI
import SwiftData

struct KasusConceptView: View {
    let session: KasusConceptSession
    var hapticMode: HapticFeedbackMode = .all
    /// Called once per finished round; `ContentView` hands it to `KasusService.recordRound`.
    var onComplete: (KasusRoundResult) -> Void
    var onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme
    @AppStorage(KasusRolesMode.storageKey) private var rolesModeRaw = ""

    @State private var round: KasusConceptRound?
    /// The pick on the step being shown, until Weiter.
    @State private var pick: KasusConceptPick?
    /// The graded step being shown, until Weiter.
    @State private var answer: KasusConceptAnswer?
    /// Schritt für Schritt: the last Ja/Nein and its line, until Weiter.
    @State private var stepResult: KasusConceptStepResult?
    @State private var showEnglish = false
    @State private var startedAt = Date()
    @State private var didSetUp = false
    /// DEBUG prefill: the answers weren't the learner's, so the round is never recorded.
    @State private var prefilled = false
    @State private var recorded = false
    @State private var rightCount = 0
    @State private var wrongCount = 0
    /// The question screen's height, which caps the feedback card.
    @State private var playHeight: CGFloat = 0

    /// Wide enough for a sentence in large type; iPad centers it.
    private let contentWidth: CGFloat = 640

    init(session: KasusConceptSession, hapticMode: HapticFeedbackMode = .all,
         onComplete: @escaping (KasusRoundResult) -> Void, onDismiss: @escaping () -> Void) {
        self.session = session
        self.hapticMode = hapticMode
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        var mode = KasusRolesMode.resolve(stored: UserDefaults.standard.string(forKey: KasusRolesMode.storageKey) ?? "")
        #if DEBUG
        // `-kasus.debugRolesMode schritt|direkt` picks the mode for a launch without storing it.
        if session.prefill != nil,
           let forced = UserDefaults.standard.string(forKey: "kasus.debugRolesMode").flatMap({ KasusRolesMode(rawValue: $0.lowercased()) }) {
            mode = forced
        }
        #endif
        var round = KasusService.conceptRound(unit: session.unit, exercise: session.exercise, rolesMode: mode)
        #if DEBUG
        // `-kasus.debugItem <id>` puts that item first, so a screenshot can land on it.
        if session.prefill != nil, let id = UserDefaults.standard.string(forKey: "kasus.debugItem"),
           let current = round, !current.items.isEmpty {
            var items = current.items
            if let at = items.firstIndex(where: { $0.id == id }) {
                items.insert(items.remove(at: at), at: 0)
            } else if let extra = KasusService.conceptPlayables(unit: session.unit, exercise: session.exercise)
                .first(where: { $0.id == id }) {
                items[0] = extra
            }
            round = KasusConceptRound(unit: current.unit, exercise: current.exercise, rolesMode: current.rolesMode, items: items)
        }
        #endif
        _round = State(initialValue: round)
    }

    /// The round's mode (a DEBUG launch may force one); the stored choice before a round exists.
    private var rolesMode: KasusRolesMode { round?.rolesMode ?? KasusRolesMode.resolve(stored: rolesModeRaw) }

    /// Once anything was answered the mode holds until the round ends.
    private var modeLocked: Bool {
        guard let round else { return false }
        return !round.answers.isEmpty || stepResult != nil || (round.walk?.position ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Group {
                if let round, !round.isFinished {
                    play(round)
                } else if let round {
                    ScrollView {
                        summary(round)
                            .padding()
                            .frame(maxWidth: contentWidth)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ContentUnavailableView("Noch nichts zu üben · Nothing to play yet", systemImage: session.exercise.symbol,
                                           description: Text("This unit has no \(session.exercise.germanTitle) items."))
                }
            }
            .background(ThemedBackground().ignoresSafeArea())
            .kasusReference()
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                if session.exercise == .roles {
                    ToolbarItem(placement: .topBarTrailing) {
                        modeMenu
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
        // Presented from the root cover, outside any themed stack, so it sets its own tint.
        .tint(appTheme.accent(model: nil))
    }

    // MARK: - Mode

    private var modeMenu: some View {
        Menu {
            Picker(selection: Binding(get: { rolesMode }, set: switchMode)) {
                ForEach(KasusRolesMode.allCases) { mode in
                    Text("\(mode.germanLabel) · \(mode.englishLabel)").tag(mode)
                }
            } label: {
                Text("Fragen · How to ask")
            }
            .pickerStyle(.inline)
            .disabled(modeLocked)
            if modeLocked {
                Text("Finish this round to change it.")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                Text(rolesMode.germanLabel)
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
        .accessibilityValue(rolesMode.germanLabel)
    }

    /// A fresh round over the same items in the other mode. Only while nothing is answered.
    private func switchMode(_ mode: KasusRolesMode) {
        guard !modeLocked, let round else { return }
        rolesModeRaw = mode.rawValue
        self.round = KasusConceptRound(unit: round.unit, exercise: round.exercise, rolesMode: mode, items: round.items)
        pick = nil
        answer = nil
        stepResult = nil
    }

    // MARK: - The step on screen

    /// The step the screen is on: the one just answered until Weiter, else the round's current.
    private func shown(_ round: KasusConceptRound) -> KasusConceptStep? {
        if let answer { return round.steps[answer.step] }
        if let finished = stepResult?.finished { return round.steps[finished.step] }
        return round.current
    }

    private func shownItem(_ round: KasusConceptRound) -> KasusConceptPlayable? {
        shown(round).map { round.items[$0.item] }
    }

    private func shownTarget(_ round: KasusConceptRound) -> KasusLocatedTarget? {
        guard let step = shown(round), let index = step.target else { return nil }
        return round.items[step.item].target(index)
    }

    /// Rollen: the answers given on the item on screen, by target index.
    private func itemAnswers(_ round: KasusConceptRound) -> [Int: KasusConceptAnswer] {
        guard let step = shown(round) else { return [:] }
        var out: [Int: KasusConceptAnswer] = [:]
        for given in round.answers where round.steps[given.step].item == step.item {
            if let index = round.steps[given.step].target { out[index] = given }
        }
        return out
    }

    // MARK: - Play

    private func play(_ round: KasusConceptRound) -> some View {
        VStack(spacing: 0) {
            KasusProgressStrip(marks: marks(round))
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxWidth: contentWidth)

            GeometryReader { geo in
                ScrollView {
                    hero(round)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: contentWidth)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            answerPanel(round)
                .padding(.horizontal)
                .padding(.bottom, 6)
                .frame(maxWidth: contentWidth)
                .layoutPriority(1)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { playHeight = $0 }
        .animation(.snappy(duration: 0.3), value: answer)
        .animation(.snappy(duration: 0.3), value: stepResult)
    }

    @ViewBuilder
    private func hero(_ round: KasusConceptRound) -> some View {
        if let item = shownItem(round) {
            switch round.exercise {
            case .roles:
                KasusRolesHero(item: item, target: shownTarget(round), answers: itemAnswers(round),
                               showEnglish: $showEnglish)
            case .wer:
                KasusWerHero(item: item, answer: answer, showEnglish: $showEnglish)
            case .probe:
                if let probe = item.probe {
                    KasusProbeHero(item: item, probe: probe, answer: answer)
                }
            }
        }
    }

    /// The verdict and its why (once answered), the inputs, then Weiter. The inputs never move:
    /// the slot under them holds a hint until Weiter takes its place.
    private func answerPanel(_ round: KasusConceptRound) -> some View {
        VStack(spacing: 12) {
            if let answer, answer.pick != stepPick(of: answer) {
                feedbackCard(verdict: answer.isRight ? .right : .miss, kasus: answer.kasus, why: answer.explanation)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            } else if let stepResult {
                feedbackCard(verdict: stepResult.right ? .right : .miss,
                             kasus: stepResult.finished?.kasus, why: stepResult.line)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            }
            inputs(round)
            Group {
                if answer != nil || stepResult != nil {
                    Button(action: next) {
                        Text(weiterLabel(round))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text(hint(round))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(minHeight: 50)
        }
    }

    /// A walk's final answer carries a `.step` pick; its card is the step line's, not the answer's.
    private func stepPick(of answer: KasusConceptAnswer) -> KasusConceptPick? {
        if case .step = answer.pick { return answer.pick }
        return nil
    }

    private func weiterLabel(_ round: KasusConceptRound) -> String {
        if let stepResult, stepResult.finished == nil { return "Weiter" }
        return round.isFinished ? "Ergebnis · Results" : "Weiter"
    }

    private func hint(_ round: KasusConceptRound) -> String {
        switch round.exercise {
        case .roles: round.rolesMode == .schritt ? "Answer the question for the ringed phrase." : "Tap the ringed phrase's role."
        case .wer:
            shownItem(round)?.kind == .sameMeaning ? "Do the two sentences mean the same?"
                : shownItem(round)?.hasPictureChoice == true ? "Tap the picture that fits the sentence."
                : "Who is the doer?"
        case .probe: "Which form of the test noun fits the slot?"
        }
    }

    @ViewBuilder
    private func inputs(_ round: KasusConceptRound) -> some View {
        if let item = shownItem(round) {
            switch round.exercise {
            case .roles:
                if round.rolesMode == .schritt {
                    walkPanel(round, item: item)
                } else {
                    rolePanel(round, item: item)
                }
            case .wer:
                werPanel(round, item: item)
            case .probe:
                probePanel(round, item: item)
            }
        }
    }

    private func rolePanel(_ round: KasusConceptRound, item: KasusConceptPlayable) -> some View {
        let target = shownTarget(round)
        let actual = target.flatMap { item.facts.roles[$0.index] }
        var pickedRole: KasusRole?
        if case .role(let role)? = pick { pickedRole = role }
        return KasusRoleGrid(
            roles: KasusRole.chips(for: round.unit),
            unit: round.unit,
            picked: pickedRole,
            actual: answer == nil ? nil : actual,
            revealedCase: target.flatMap { t in actual?.revealedCase(for: t) }
        ) { role in
            choose(.role(role))
        }
        // Keyed on the step shown, which holds through the pick, so the shake and the pop play.
        .id(shownIndex(round))
    }

    /// The index of the step on screen: the one just answered until Weiter, else the current.
    private func shownIndex(_ round: KasusConceptRound) -> Int {
        answer?.step ?? stepResult?.finished?.step ?? round.cursor
    }

    private func walkPanel(_ round: KasusConceptRound, item: KasusConceptPlayable) -> some View {
        let question = stepResult?.question ?? round.walk?.current
        let target = shownTarget(round)
        let decides = question != nil && question == target.flatMap { item.facts.roles[$0.index] }
        return KasusWalkPanel(
            question: question,
            picked: stepResult.map { $0.yes ? "Ja" : "Nein" },
            answer: decides ? "Ja" : "Nein",
            kasus: stepResult?.finished?.kasus ?? target?.kasus ?? .nominativ,
            decides: decides || stepResult?.finished != nil,
            graded: stepResult != nil
        ) { yes in
            chooseStep(yes)
        }
        .id("\(shownIndex(round))-\(question?.rawValue ?? "")")
    }

    private func werPanel(_ round: KasusConceptRound, item: KasusConceptPlayable) -> some View {
        Group {
            if let same = item.same {
                KasusOptionGrid(options: ["Gleich", "Anders"], answer: same ? "Gleich" : "Anders",
                                kasus: answer?.kasus ?? .nominativ, picked: pickedSameLabel, columns: 2, rowHeight: 58) { option in
                    choose(.same(option == "Gleich"))
                }
            } else if let doer = item.doer, item.hasPictureChoice {
                KasusPictureChoice(item: item, doer: doer, picked: pickedOptionIndex) { index in
                    choose(.option(index))
                }
            } else if let doer = item.doer {
                let options = item.options
                KasusOptionGrid(options: options.map(\.surface), answer: doer.surface, kasus: .nominativ,
                                picked: pickedOptionLabel(item), columns: 2, rowHeight: 58,
                                font: .title3.weight(.semibold)) { option in
                    if let target = options.first(where: { $0.surface == option }) { choose(.option(target.index)) }
                }
            }
        }
        .id(item.id)
    }

    private var pickedSameLabel: String? {
        if case .same(let same)? = pick { return same ? "Gleich" : "Anders" }
        return nil
    }

    private var pickedOptionIndex: Int? {
        if case .option(let index)? = pick { return index }
        return nil
    }

    private func pickedOptionLabel(_ item: KasusConceptPlayable) -> String? {
        if case .option(let index)? = pick { return item.target(index)?.surface }
        return nil
    }

    private func probePanel(_ round: KasusConceptRound, item: KasusConceptPlayable) -> some View {
        Group {
            if let probe = item.probe {
                let options = probe.options(includeGenitive: round.unit.casesInPlay.contains(.genitiv))
                KasusOptionGrid(options: options, answer: probe.answer, kasus: probe.kasus,
                                picked: pickedForm, columns: options.count > 3 ? 2 : 3, rowHeight: 54) { option in
                    choose(.form(option))
                }
            }
        }
        .id(item.id)
    }

    private var pickedForm: String? {
        if case .form(let form)? = pick { return form }
        return nil
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

    /// One dot per step: its case color once right, a hollow ring once not, the ring for the
    /// step being asked.
    private func marks(_ round: KasusConceptRound) -> [KasusProgressStrip.Mark] {
        let showingAnswer = answer != nil || stepResult?.finished != nil
        return round.steps.indices.map { i in
            if i < round.answers.count {
                let given = round.answers[i]
                return given.isRight ? .right(given.kasus) : .miss
            }
            // The next dot rings only once Weiter has moved on from the answered one.
            return i == round.cursor && !showingAnswer ? .current : .upcoming
        }
    }

    // MARK: - Answering

    /// The first pick counts; the inputs lock after it.
    private func choose(_ pick: KasusConceptPick, haptics: Bool = true) {
        guard answer == nil, var round else { return }
        guard let graded = round.answer(pick) else { return }
        self.round = round
        self.pick = pick
        answer = graded
        guard haptics else { return }
        if graded.isRight { rightCount += 1 } else { wrongCount += 1 }
    }

    /// Schritt für Schritt: one Ja or Nein.
    private func chooseStep(_ yes: Bool, haptics: Bool = true) {
        guard stepResult == nil, var round else { return }
        guard let result = round.answerStep(yes: yes) else { return }
        self.round = round
        stepResult = result
        guard haptics else { return }
        if result.right { rightCount += 1 } else { wrongCount += 1 }
    }

    /// Once per answer: a fast double tap on Weiter while it fades out must not skip a step or
    /// record the round twice.
    private func next() {
        guard let round else { return }
        if let stepResult, stepResult.finished == nil {
            // The walk goes on with the next question.
            self.stepResult = nil
            return
        }
        guard answer != nil || stepResult != nil else { return }
        answer = nil
        pick = nil
        stepResult = nil
        if round.isFinished { record() }
    }

    // MARK: - Summary

    private func summary(_ round: KasusConceptRound) -> some View {
        let right = round.firstTryCount
        let misses = round.answers.filter { !$0.isRight }
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ergebnis · Result")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(right) of \(round.answers.count)")
                    .font(.largeTitle.weight(.bold))
                Text(round.exercise == .roles && round.rolesMode == .schritt
                     ? "phrases walked through without a wrong step"
                     : "right on the first try")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            KasusProgressStrip(marks: marks(round), showsScore: false)
            ForEach(GrammarCase.allCases) { kasus in
                let rows = round.answers.filter { $0.kasus == kasus }
                if !rows.isEmpty {
                    HStack {
                        CaseLabel(kasus: kasus, style: .name)
                            .frame(width: 130, alignment: .leading)
                        Spacer()
                        Text("\(rows.filter(\.isRight).count) / \(rows.count)")
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
                    ForEach(misses) { miss in
                        VStack(alignment: .leading, spacing: 6) {
                            KasusConceptSentence.text(miss.record)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(kasusRich: miss.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
            if round.exercise != .probe {
                KasusNoteLine(text: "Recognition only: this round counts for your streak, never for the coach's case skills.")
            }
            Button {
                self.round = KasusService.conceptRound(unit: round.unit, exercise: round.exercise, rolesMode: round.rolesMode)
                answer = nil
                pick = nil
                stepResult = nil
                startedAt = Date()
                prefilled = false
                recorded = false
            } label: {
                Text("Noch eine Runde · Again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Fertig", action: onDismiss)
                .frame(maxWidth: .infinity)
        }
    }

    /// Hands the round up for `KasusService.recordRound`: the streak, a `KasusRound` for Verlauf
    /// and the calendar, and (Probe only) the coach's case skills.
    private func record() {
        guard !prefilled, !recorded, let round else { return }
        recorded = true
        onComplete(round.result(durationSeconds: Int(Date().timeIntervalSince(startedAt))))
    }

    // MARK: - Setup

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        #if DEBUG
        applyDebugPrefill()
        #endif
    }

    #if DEBUG
    /// `-kasus.debugAnswers right|mixed` plays the first four steps (mixed gets one in three
    /// wrong), and `-kasus.debugQuickState right|wrong|done` answers the next one that way, or
    /// the whole round for the summary. Never recorded, and no haptics.
    private func applyDebugPrefill() {
        guard let prefill = session.prefill, var round else { return }
        let state = EndingsDebugState.fromLaunchArguments()
        guard prefill.answers != nil || state != nil else { return }
        let answers = prefill.answers ?? .mixed
        prefilled = true
        let played = state == .done ? round.steps.count : min(4, round.steps.count - 1)
        for i in 0..<played {
            debugPlay(&round, step: i, wrong: answers == .mixed && i % 3 == 1, finish: true)
        }
        self.round = round
        guard !round.isFinished, let state else { return }
        switch state {
        case .right:        debugPlay(&round, step: round.cursor, wrong: false, finish: false)
        case .wrong, .slip: debugPlay(&round, step: round.cursor, wrong: true, finish: false)
        case .done:         break
        }
        self.round = round
    }

    /// Plays one step: a pick, or a walk. With `finish` the step is closed (as Weiter would);
    /// without it the verdict stays on screen.
    private func debugPlay(_ round: inout KasusConceptRound, step: Int, wrong: Bool, finish: Bool) {
        if round.exercise == .roles, round.rolesMode == .schritt {
            guard let target = round.currentTarget, let item = round.currentItem,
                  let actual = item.facts.roles[target.index] else { return }
            var mistaken = false
            while let question = round.walk?.current {
                let decides = question == actual
                let yes = wrong && !mistaken ? !decides : decides
                if wrong && !mistaken { mistaken = true }
                guard let result = round.answerStep(yes: yes) else { break }
                if !finish {
                    stepResult = result
                    return
                }
                if result.finished != nil { break }
            }
            return
        }
        guard let pick = KasusService.debugConceptPick(for: round, step: step, wrong: wrong),
              let graded = round.answer(pick) else { return }
        if !finish {
            self.pick = pick
            answer = graded
        }
    }
    #endif
}

// MARK: - Previews

#Preview("Rollen · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            KasusConceptView(session: KasusConceptSession(unit: .dativ, exercise: .roles),
                             onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}

#Preview("Wer macht was? · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            KasusConceptView(session: KasusConceptSession(unit: .akkusativ, exercise: .wer),
                             onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}

#Preview("Die Probe · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            KasusConceptView(session: KasusConceptSession(unit: .genitiv, exercise: .probe),
                             onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}
