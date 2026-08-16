//
//  PlacementQuizStages.swift
//  german-ai-flashcards
//
//  The placement check's stages as embeddable subviews, shared verbatim by the standalone sheet
//  (`PlacementQuizView`, used for retakes) and the first-launch wizard (`OnboardingWizardView`).
//  Pure presentation: every stage reports taps outward and owns no scoring or storage.
//
//  The no-feedback invariant lives here as much as in the flow: no stage ever shows right/wrong,
//  including the cloze finale — this is a measurement, not a lesson.
//

import SwiftUI

// MARK: - Intro

struct PlacementIntroStage: View {
    var onStart: () -> Void
    var onBeginner: () -> Void

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

                Text("What you already know shows as an outline on the pyramid. It fills in solid once you prove it here.")
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

// MARK: - Single-choice questions

struct PlacementQuestionStage: View {
    var session: PlacementSession
    var onAnswer: (Int?) -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        if let item = session.current {
            VStack(spacing: 0) {
                ProgressView(value: session.progress)
                    .padding(.horizontal)
                    .padding(.top, 8)

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
                Button("Skip this one") { onAnswer(nil) }
                    .font(.subheadline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }

    private func choiceButton(item: PlacementItem, index: Int, label: String) -> some View {
        Button {
            onAnswer(index)
        } label: {
            HStack {
                Text(label)
                    .fontWeight(item.kind == .gender ? .semibold : .regular)
                    .foregroundStyle(genderTint(item: item, label: label) ?? .primary)
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
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
/// current picks shown in place, and each gap gets its own three-option row underneath. One tap
/// on "Finish" submits all three; nothing is marked right or wrong.
struct PlacementClozeStage: View {
    let cloze: PlacementClozePrompt
    var progress: Double
    var onSubmit: ([Int?]) -> Void

    @State private var picks: [Int?]

    @Environment(\.appTheme) private var appTheme

    init(cloze: PlacementClozePrompt, progress: Double, onSubmit: @escaping ([Int?]) -> Void) {
        self.cloze = cloze
        self.progress = progress
        self.onSubmit = onSubmit
        _picks = State(initialValue: Array(repeating: nil, count: cloze.gaps.count))
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: progress)
                .padding(.horizontal)
                .padding(.top, 8)

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
                    onSubmit(picks)
                } label: {
                    Text("Finish")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(picks.contains(nil))

                Button("Leave the rest blank") { onSubmit(picks) }
                    .font(.subheadline)
            }
            .padding()
            .background(.bar)
        }
    }

    /// The paragraph with each pick spliced in where its gap sits — picked words show tinted, open
    /// gaps as a placeholder line — so the learner reads their answer as a sentence, not a form.
    private var paragraphText: Text {
        var text = Text(verbatim: "")
        for (index, segment) in cloze.segments.enumerated() {
            text = text + Text(segment)
            guard index < cloze.gaps.count else { continue }
            if let pick = picks[index] {
                text = text + Text(cloze.gaps[index].choices[pick]).bold().foregroundStyle(Color.accentColor)
            } else {
                text = text + Text("＿＿").foregroundStyle(.secondary)
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
        return Button {
            picks[gap] = selected ? nil : choiceIndex
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(selected ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: appTheme.innerRadius(10))
                        .fill(selected ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                                       : AnyShapeStyle(.regularMaterial))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: appTheme.innerRadius(10))
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1)
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
                         ? "Nothing assumed. Every layer of your pyramid fills from real work."
                         : "\(result.estimatedLevel.englishLabel). Stories and conversations now start here, and you can change that any time in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !result.declaredBeginner {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Credited as a head start")
                            .font(.subheadline)
                            .fontWeight(.semibold)
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
                        Text("This shows as an outline on the pyramid until you prove it in the app. Stories and conversations are never estimated.")
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
