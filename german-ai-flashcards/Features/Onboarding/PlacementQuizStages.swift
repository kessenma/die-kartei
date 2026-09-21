//
//  PlacementQuizStages.swift
//  german-ai-flashcards
//
//  The placement check's stages as embeddable subviews, shared verbatim by the standalone sheet
//  (`PlacementQuizView`, used for retakes) and the first-launch wizard (`OnboardingWizardView`).
//  Pure presentation: every stage reports taps outward and owns no scoring or storage.
//
//  Marking answers right or wrong is a *setting*, not a property of the check: every question
//  carries the switch that turns it off (`PlacementFeedbackOption`), and with it off no stage shows
//  anything, cloze finale included. What must stay true either way is that the mark is display
//  only — nothing in `PlacementSession` or `PlacementService` reads the setting, so the same
//  answers score the same run whichever way it was taken.
//

import SwiftUI

// MARK: - Intro

struct PlacementIntroStage: View {
    var onStart: () -> Void
    var onBeginner: () -> Void
    /// The hard-select door, for someone who already knows what level they are and doesn't want to
    /// spend three minutes proving it. Credits nothing — see `PlacementDeclareStage`.
    var onDeclareLevel: () -> Void

    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bumped to replay the assembly. Not `.id()` — see `FigurSceneView.restartToken`.
    @State private var figurReplay = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    figurHero
                    Text("Where are you starting?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    Text("About three minutes of quick questions. It decides how much of your Lernpyramide is already standing, and sets the level for stories and conversations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    point("questionmark.circle", "Words, der/die/das, cases, and a few structures.")
                    point("eye.slash", "No score to fail. Nothing is shared.")
                    point("arrow.clockwise", "Retake it any time from the Lernpyramide.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16)))

                Text("What you already know becomes the pyramid's blueprint — a dashed outline that fills in solid once you prove it here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(action: onStart) {
                    Text("Start the check")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("I'm starting from zero", action: onBeginner)
                    .font(.subheadline)

                Button("I already know my level", action: onDeclareLevel)
                    .font(.subheadline)
            }
            .padding()
            .background(.bar)
        }
    }

    /// die Figur builds herself out of six parts that fall in from off-frame. This is the first
    /// screen a new learner sees, and the assembly says the thing the copy underneath says: you
    /// are not starting from an empty screen, you are starting from pieces that are about to add
    /// up to something. It replaces a static `pyramid` glyph — the pyramid is already the subject
    /// of the two paragraphs below it, and saying it twice bought nothing.
    ///
    /// Tapping replays it. That is the whole interaction budget of a stage whose real job is to
    /// be read, and it is nearly free: `restartToken` re-runs the baked clip without tearing down
    /// the RealityKit surface.
    private var hasReplayableAssembly: Bool {
        !reduceMotion && !LightweightGraphics.isActive
    }

    private var figurHero: some View {
        FigurSceneView(
            // Motion *is* the content here, so with it switched off we show the finished figure
            // rather than a canvas that plays a clip nobody asked to see. Same trade the
            // preposition canvas makes, and the rest pose is an asset we already ship.
            asset: reduceMotion ? FigurScene.ruhe : FigurScene.aufbau,
            restartToken: figurReplay,
            distance: 5.6,
            // This canvas loads while the sheet is still sliding up, and the opening beat is both
            // legs inside the first second. Waiting out the slide costs nothing and buys the
            // whole assembly.
            settleDelay: .milliseconds(350)
        )
        .frame(height: 200)
        .contentShape(Rectangle())
        .onTapGesture { figurReplay += 1 }
        .accessibilityElement()
        .accessibilityLabel("Die Figur")
        // Only promise a replay where one can actually happen. On a device drawing stills there
        // is no clip to restart, and Reduce Motion asked for none.
        .accessibilityHint(hasReplayableAssembly ? "Double tap to replay the assembly" : "")
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Hard-selected level

/// The "I already know my level" door: pick a level outright, skip the twenty-nine questions.
///
/// **What this stage must never do is write a `PlacementResult`.** A level you assert is a
/// preference, not a measurement — so it sets how hard the German is and credits the Lernpyramide
/// nothing: no provisional fill, no dashed outlines, and deliberately no `PyramidGlyph` blueprint
/// preview like `PlacementResultStage` shows. That glyph is the visual signature of evidence, and
/// there is none here. The rule it extends is *estimated ≠ earned* (docs/GAMIFICATION.md); this is
/// its stricter sibling, *declared is not even estimated*.
///
/// Generic over its footer for the same reason `PlacementResultStage` is: the onboarding wizard
/// slots the model-download panel in underneath, and the standalone retake sheet passes nothing.
struct PlacementDeclareStage<Footer: View>: View {
    var initialLevel: CEFRLevel
    var onConfirm: (CEFRLevel) -> Void
    /// Back out of this door. The label is the host's to set, because where "back" goes depends on
    /// where the learner came from — the intro (so: take the check) or a finished result (so: back
    /// to that result, which is not an offer to re-take anything).
    var backLabel: String
    var onBack: () -> Void
    var onDone: () -> Void
    @ViewBuilder var footer: Footer

    @Environment(\.appTheme) private var appTheme

    @State private var level: CEFRLevel
    /// Confirming swaps the body in place rather than pushing a stage, so the wizard's download
    /// panel keeps its slot on screen throughout.
    @State private var confirmed = false

    init(
        initialLevel: CEFRLevel,
        backLabel: String = "Take the check instead",
        onConfirm: @escaping (CEFRLevel) -> Void,
        onBack: @escaping () -> Void,
        onDone: @escaping () -> Void,
        @ViewBuilder footer: () -> Footer
    ) {
        self.initialLevel = initialLevel
        self.backLabel = backLabel
        self.onConfirm = onConfirm
        self.onBack = onBack
        self.onDone = onDone
        self.footer = footer()
        _level = State(initialValue: initialLevel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                // Outside the confirmed/choosing branch on purpose: keeping the canvas mounted
                // across the confirm means the RealityKit surface is never rebuilt (the thing
                // these scenes exist to avoid), and it reads better — she simply stays standing
                // on the step you chose while the words underneath settle.
                LevelClimbScene(selection: level)
                    .frame(height: 190)

                if confirmed { confirmation } else { chooser }
                footer
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    // MARK: Choosing

    private var chooser: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("Which one sounds like you?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text("This sets how hard the German is in stories and conversations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 4) {
                LevelChoiceList(selection: $level)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16)))

            Text(reassurance)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Confirmed

    private var confirmation: some View {
        VStack(spacing: 10) {
            // No checkmark seal here: the canvas above is already showing her standing on the step
            // that was chosen, which says "done" better than a badge, and without competing with it.
            Text("Level \(level.rawValue)")
                .font(.title2)
                .fontWeight(.bold)
            Text("\(level.englishLabel). Stories and conversations start here from now on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(reassurance)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    /// Said on both halves of the stage, because the thing that makes a hard-select feel safe is
    /// knowing it isn't final.
    private var reassurance: String {
        "Nothing is locked in. Change it any time in Settings ▸ Your Level, or pick a different level inside any single story or conversation as you go."
    }

    // MARK: Actions

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 10) {
            if confirmed {
                Button(action: onDone) {
                    Text("Done").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    onConfirm(level)
                    withAnimation { confirmed = true }
                } label: {
                    Text("Set my level to \(level.rawValue)")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(backLabel, action: onBack)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(.bar)
    }
}

extension PlacementDeclareStage where Footer == EmptyView {
    init(
        initialLevel: CEFRLevel,
        backLabel: String = "Take the check instead",
        onConfirm: @escaping (CEFRLevel) -> Void,
        onBack: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.init(
            initialLevel: initialLevel,
            backLabel: backLabel,
            onConfirm: onConfirm,
            onBack: onBack,
            onDone: onDone
        ) { EmptyView() }
    }
}

// MARK: - Answer feedback

/// Whether the check marks each answer right or wrong as it's given.
///
/// On by default. The old rule was that a placement check shows nothing, on the grounds that
/// feedback turns a measurement into a lesson and lets someone tune their answers partway through
/// — true, and the reason the switch exists at all. It stopped being worth imposing: being told
/// nothing for twenty-nine questions is the colder first three minutes, and a learner who wants
/// the measurement clean can turn the marks off from the top of any question.
///
/// The marks are display only. `PlacementSession` and `PlacementService` never read this, so a run
/// with marks on and a run with marks off score identically for identical answers.
enum PlacementFeedbackOption {
    static let defaultsKey = "placement.showsAnswerFeedback"

    /// How long a mark holds the screen before the next question. A miss lingers, because a miss
    /// is the one that also has the right answer to read.
    static func revealDuration(correct: Bool) -> Duration {
        correct ? .milliseconds(500) : .milliseconds(1100)
    }
}

/// The two states a revealed answer can be in, and how each draws. Shared so a marked gap in the
/// finale looks like a marked choice in a question.
private enum PlacementMark {
    case correct, wrong

    var symbol: String { self == .correct ? "checkmark.circle.fill" : "xmark.circle.fill" }
    var tint: Color { self == .correct ? .green : .red }
}

/// Progress plus the marks switch: one strip, shared by the questions and the finale, so the
/// switch is in the same place on every screen of the check.
private struct PlacementQuizHeader: View {
    var progress: Double
    @Binding var showsFeedback: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress)
            Toggle(isOn: $showsFeedback.animation(.easeInOut(duration: 0.15))) {
                Label(showsFeedback ? "Answers on" : "Answers off",
                      systemImage: showsFeedback ? "eye" : "eye.slash")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Show right or wrong after each answer")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Single-choice questions

struct PlacementQuestionStage: View {
    var session: PlacementSession
    /// Gates the vibration that rides along with the mark (Settings ▸ Flashcards ▸ Haptics).
    var hapticMode: HapticFeedbackMode = .all
    var onAnswer: (Int?) -> Void

    @AppStorage(PlacementFeedbackOption.defaultsKey) private var showsFeedback = true
    @Environment(\.appTheme) private var appTheme

    /// The mark on screen, and the pending advance behind it. Non-nil means mid-reveal: every tap
    /// is ignored until it clears, so an impatient double-tap can't answer the next question too.
    @State private var verdict: Verdict?

    private struct Verdict: Equatable {
        let id = UUID()
        let index: Int
        let isCorrect: Bool
    }

    var body: some View {
        if let item = session.current {
            VStack(spacing: 0) {
                PlacementQuizHeader(progress: session.progress, showsFeedback: $showsFeedback)

                ScrollView {
                    VStack(spacing: 26) {
                        VStack(spacing: 10) {
                            Text(questionLine(for: item.kind))
                                .font(.caption)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)

                            Text(item.prompt)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal)
                        .background(.regularMaterial,
                                    in: RoundedRectangle(cornerRadius: appTheme.innerRadius(18)))

                        VStack(spacing: 10) {
                            ForEach(Array(item.choices.enumerated()), id: \.offset) { index, choice in
                                choiceButton(item: item, index: index, label: choice)
                            }
                        }
                    }
                    .padding()
                    .id(item.id)
                    .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Skip this one") { answer(item, nil) }
                    .font(.subheadline)
                    .disabled(verdict != nil)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
            // Keyed on the verdict rather than a detached `Task`, so leaving the stage — finishing,
            // dismissing the sheet — cancels the pending advance instead of firing it into a view
            // that's gone.
            .task(id: verdict?.id) {
                guard let pending = verdict else { return }
                try? await Task.sleep(for: PlacementFeedbackOption.revealDuration(correct: pending.isCorrect))
                guard !Task.isCancelled else { return }
                verdict = nil
                onAnswer(pending.index)
            }
            .sensoryFeedback(.success, trigger: verdict) { _, new in
                new?.isCorrect == true && hapticMode.playsSuccess
            }
            .sensoryFeedback(.error, trigger: verdict) { _, new in
                new?.isCorrect == false && hapticMode.playsError
            }
        }
    }

    // MARK: Answering

    /// With the marks switched off this is the old path exactly: the tap answers, nothing is shown,
    /// the next question is already on screen. A skip takes that path either way — declining to
    /// answer isn't a wrong answer, and stamping a red ✗ on it would read like one.
    private func answer(_ item: PlacementItem, _ index: Int?) {
        guard verdict == nil else { return }
        guard showsFeedback, let index else {
            onAnswer(index)
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            verdict = Verdict(index: index, isCorrect: index == item.correctIndex)
        }
    }

    /// What a row draws during a reveal: the tapped row always, plus the right answer when the tap
    /// missed — "show the answers" has to mean the answer, not just the bad news.
    private func mark(item: PlacementItem, index: Int) -> PlacementMark? {
        guard let verdict else { return nil }
        if index == verdict.index { return verdict.isCorrect ? .correct : .wrong }
        if !verdict.isCorrect, index == item.correctIndex { return .correct }
        return nil
    }

    private func choiceButton(item: PlacementItem, index: Int, label: String) -> some View {
        let mark = mark(item: item, index: index)
        return Button {
            answer(item, index)
        } label: {
            HStack {
                Text(label)
                    .fontWeight(item.kind == .gender ? .semibold : .regular)
                    // The gender colors survive the reveal: der/die/das is the one cue the app
                    // teaches everywhere, and the mark says right-or-wrong in its own channel.
                    .foregroundStyle(genderTint(item: item, label: label) ?? .primary)
                Spacer()
                if let mark {
                    Image(systemName: mark.symbol)
                        .font(.headline)
                        .foregroundStyle(mark.tint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
            .overlay(
                RoundedRectangle(cornerRadius: appTheme.innerRadius(12))
                    .strokeBorder(mark?.tint ?? .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    /// der/die/das buttons carry the gender colors — the app's one consistent pedagogical cue, so
    /// the placement check teaches the same code the rest of the app uses even while measuring.
    private func genderTint(item: PlacementItem, label: String) -> Color? {
        guard item.kind == .gender, let gender = Gender(article: label) else { return nil }
        return gender.color
    }

    private func questionLine(for kind: PlacementItem.Kind) -> String {
        switch kind {
        case .vocab:       "What does this mean?"
        case .gender:      "Which article?"
        case .preposition: "Which case does it take?"
        case .grammar:     "Fill the gap"
        case .cloze:       "Fill the gaps"
        }
    }
}

// MARK: - Cloze finale

/// The three-gap paragraph that ends the check. The paragraph renders as running text with the
/// current picks shown in place, and each gap gets its own three-option row underneath. One tap on
/// "Finish" submits all three, and with the marks switched on they light up green or red for a
/// beat first — three gaps at once, so the beat is longer than a single question's.
struct PlacementClozeStage: View {
    let cloze: PlacementClozePrompt
    var progress: Double
    /// Gates the vibration that rides along with the marks (Settings ▸ Flashcards ▸ Haptics).
    var hapticMode: HapticFeedbackMode = .all
    var onSubmit: ([Int?]) -> Void

    @AppStorage(PlacementFeedbackOption.defaultsKey) private var showsFeedback = true
    @State private var picks: [Int?]
    /// Mid-reveal: the gaps are marked and the run is about to end. Also the tap guard — every
    /// control is dead while it's true, so a second tap can't submit the run twice.
    @State private var revealed = false

    @Environment(\.appTheme) private var appTheme

    /// Long enough to read three marked gaps, where a single question only has one.
    private static let revealDuration = Duration.milliseconds(1400)

    init(cloze: PlacementClozePrompt, progress: Double, hapticMode: HapticFeedbackMode = .all, onSubmit: @escaping ([Int?]) -> Void) {
        self.cloze = cloze
        self.progress = progress
        self.hapticMode = hapticMode
        self.onSubmit = onSubmit
        _picks = State(initialValue: Array(repeating: nil, count: cloze.gaps.count))
    }

    /// Every gap right — what the vibration reacts to, so the finale buzzes once rather than
    /// three times.
    private var allCorrect: Bool {
        cloze.gaps.indices.allSatisfy { picks[$0] == cloze.gaps[$0].correctIndex }
    }

    var body: some View {
        VStack(spacing: 0) {
            PlacementQuizHeader(progress: progress, showsFeedback: $showsFeedback)

            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 12) {
                        Text("One last paragraph — fill the gaps")
                            .font(.caption)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)

                        Text(cloze.title)
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        paragraphText
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 22)
                    .padding(.horizontal)
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: appTheme.innerRadius(18)))

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(cloze.gaps.indices, id: \.self) { index in
                            gapRow(index)
                        }
                    }
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    submit()
                } label: {
                    Text("Finish")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(picks.contains(nil) || revealed)

                Button("Leave the rest blank") { submit() }
                    .font(.subheadline)
                    .disabled(revealed)
            }
            .padding()
            .background(.bar)
        }
        .task(id: revealed) {
            guard revealed else { return }
            try? await Task.sleep(for: Self.revealDuration)
            guard !Task.isCancelled else { return }
            onSubmit(picks)
        }
        .sensoryFeedback(.success, trigger: revealed) { _, new in
            new && allCorrect && hapticMode.playsSuccess
        }
        .sensoryFeedback(.error, trigger: revealed) { _, new in
            new && !allCorrect && hapticMode.playsError
        }
    }

    /// With the marks off this hands the picks straight over, exactly as it always did.
    private func submit() {
        guard !revealed else { return }
        guard showsFeedback else {
            onSubmit(picks)
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { revealed = true }
    }

    /// What a gap's chip draws once revealed: the pick, plus the right option when the pick missed
    /// (or when the gap was left blank, which is the same thing with nothing to cross out).
    private func mark(gap: Int, choiceIndex: Int) -> PlacementMark? {
        guard revealed else { return nil }
        let correctIndex = cloze.gaps[gap].correctIndex
        if choiceIndex == picks[gap] { return choiceIndex == correctIndex ? .correct : .wrong }
        if picks[gap] != correctIndex, choiceIndex == correctIndex { return .correct }
        return nil
    }

    /// The paragraph with each pick spliced in where its gap sits — picked words show tinted, open
    /// gaps as a placeholder line — so the learner reads their answer as a sentence, not a form.
    private var paragraphText: Text {
        var text = Text(verbatim: "")
        for (index, segment) in cloze.segments.enumerated() {
            text = Text("\(text)\(Text(segment))")
            guard index < cloze.gaps.count else { continue }
            if let pick = picks[index] {
                let tint = revealed
                    ? (pick == cloze.gaps[index].correctIndex ? Color.green : Color.red)
                    : Color.accentColor
                let word = Text(cloze.gaps[index].choices[pick]).bold().foregroundStyle(tint)
                text = Text("\(text)\(word)")
            } else {
                text = Text("\(text)\(Text("＿＿").foregroundStyle(.secondary))")
            }
        }
        return text
    }

    private func gapRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lücke \(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(cloze.gaps[index].choices.enumerated()), id: \.offset) { choiceIndex, choice in
                    gapChoice(gap: index, choiceIndex: choiceIndex, label: choice)
                }
            }
        }
    }

    private func gapChoice(gap: Int, choiceIndex: Int, label: String) -> some View {
        let selected = picks[gap] == choiceIndex
        let mark = mark(gap: gap, choiceIndex: choiceIndex)
        return Button {
            guard !revealed else { return }
            picks[gap] = selected ? nil : choiceIndex
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(selected || mark != nil ? .semibold : .regular)
                if let mark {
                    Image(systemName: mark.symbol)
                        .font(.caption)
                        .foregroundStyle(mark.tint)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: appTheme.innerRadius(10))
                    .fill(mark.map { AnyShapeStyle($0.tint.opacity(0.18)) }
                          ?? (selected ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                                       : AnyShapeStyle(.regularMaterial)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: appTheme.innerRadius(10))
                    .strokeBorder(mark?.tint ?? (selected ? Color.accentColor : .clear), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Result

struct PlacementResultStage<Footer: View>: View {
    var result: PlacementResult
    var onDone: () -> Void
    @ViewBuilder var footer: Footer

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                        .padding(.top, 12)
                    Text(result.declaredBeginner ? "Starting fresh" : "Level \(result.estimatedLevel.rawValue)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(result.declaredBeginner
                         ? "Nothing assumed. Stories and conversations start at A1, and every layer of your pyramid fills from real work. You can change the level any time in Settings ▸ Your Level."
                         : "\(result.estimatedLevel.englishLabel). Stories and conversations now start here, and you can change that any time in Settings ▸ Your Level.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !result.declaredBeginner {
                    VStack(alignment: .leading, spacing: 12) {
                        // The quiz's payoff, visible the moment it's earned: the blueprint this
                        // check just drew, rendered with the same glyph the pyramid uses. Built
                        // from the result alone (empty stats), so it shows pure blueprint — the
                        // real pyramid folds it into any earned progress the moment this closes.
                        HStack(spacing: 14) {
                            PyramidGlyph(layers: blueprintPreview)
                                .frame(width: 64, height: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dein Bauplan · Your blueprint")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("The dashed outline this check drew on your Lernpyramide.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        ForEach(GoetheLevel.allCases) { level in
                            let known = result.vocabKnown(level)
                            if known > 0.01 {
                                HStack {
                                    Text("\(level.rawValue) vocabulary")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(Int((known * 100).rounded()))%")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if result.estimatedLevel == .b2 {
                            Text("B2 comes from your grammar. Vocabulary credit tops out at the B1 list — the bundled word lists end there.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("A blueprint is drawn, not built: it stays a dashed outline until you prove it here, and building is what makes it solid. Stories and conversations are never on the blueprint.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16)))
                }

                footer
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) {
                Text("Done").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
    }
}

extension PlacementResultStage where Footer == EmptyView {
    init(result: PlacementResult, onDone: @escaping () -> Void) {
        self.init(result: result, onDone: onDone) { EmptyView() }
    }
}

private extension PlacementResultStage {
    /// The pyramid as this result alone would outline it — the same credit math the real screen
    /// runs, fed empty stats: no earned fill, no refuted items, just the fresh blueprint.
    var blueprintPreview: [PyramidLayerState] {
        PyramidService.layers(from: PyramidService.snapshot(
            prepositionStats: [], cards: [], storyAttempts: [], profile: nil,
            studyDays: [], articleStats: [], matchingStats: [],
            placement: result, conversations: []
        ))
    }
}
