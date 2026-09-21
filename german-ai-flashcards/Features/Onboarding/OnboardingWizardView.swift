//
//  OnboardingWizardView.swift
//  german-ai-flashcards
//
//  The first-launch flow: why-a-download → tutor offer → placement check → result plus download
//  status. The model downloads while the questions run, so the multi-minute wait disappears into
//  the three-minute check. Every stage comes from `PlacementQuizStages` / `HeroModelPitchContent`
//  rather than being its own copy, because both halves stay independently presentable elsewhere —
//  the pitch as `HeroModelIntroSheet` from Settings, the check as `PlacementQuizView` for retakes.
//
//  The explainer step exists because of one observation: a first-time user watched the app open on
//  a brand logo and "Download … (~5.0 GB)" and had no idea why an app would need that. Nothing
//  here says "model", "LLM" or "inference". The download is a *teacher*, and the screen's whole job
//  is to answer "why" before anything asks for five gigabytes.
//
//  The presenter writes all first-launch flags *before* this appears (crash safety, same discipline
//  as the model sheets), so Close never turns into a re-nag.
//

import SwiftUI

struct OnboardingWizardView: View {
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Dismisses this flow and lands the learner on Settings ▸ Model & Downloads. Wired to the
    /// "Maybe later" follow-up, so declining the download points somewhere real.
    var onOpenModelSettings: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    /// The steps, in order. `welcome` is the new one; the rest are what the flow always did.
    private enum Step: Int { case welcome, offer, check }
    @State private var step: Step = .welcome

    /// Whether this flow kicked off the tutor download, so the result page only talks about a
    /// download the learner actually chose.
    @State private var startedDownload = false
    /// Whether the learner said "Maybe later". Drives the note that tells them where to find a
    /// tutor afterwards — local only, since the Home card derives the same fact from readiness.
    @State private var declinedDownload = false
    @State private var session: PlacementSession?
    @State private var result: PlacementResult?
    /// Showing the hard-select door instead of the check — from the intro, or from a result the
    /// learner disagrees with.
    @State private var declaring = false

    /// Readiness as of presentation. Captured once: a download finishing mid-flow must not
    /// renumber the steps under the learner.
    private let readiness = ModelReadiness.current

    /// Whether the check runs at all. Someone who already has a stored estimate has answered these
    /// questions; re-onboarding them for the explainer must not re-test them.
    private var includesCheck: Bool { PlacementService.current == nil }

    /// Whether the tutor offer runs at all. A device no tutor fits is shown no offer — pitching a
    /// download the hardware can't hold is the bug this guard exists for.
    private var includesOffer: Bool { readiness.fittingTutor != nil }

    /// The steps this particular run will show. The indicator counts these, so a two-step flow
    /// never claims to be "1 von 4".
    private var steps: [Step] {
        var s: [Step] = [.welcome]
        if includesOffer { s.append(.offer) }
        if includesCheck { s.append(.check) }
        return s
    }

    /// The tutor this phone is pitched. Never the raw hero: a 6 GB phone gets the E2B tutor and a
    /// 4 GB phone a Granite one.
    private var hero: MLXModel { readiness.fittingTutor ?? .hero }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator
                Group {
                    switch step {
                    case .welcome: welcomePage
                    case .offer: pitchPage
                    case .check: quizPage
                    }
                }
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // A cover has no swipe-to-dismiss, so this is the only way out — it must be
                    // present on every step. "Skip" only while a check is mid-flight; everywhere
                    // else leaving costs the learner nothing, so it reads as "Close".
                    Button(isMidCheck ? "Skip" : "Close") { dismiss() }
                }
            }
        }
    }

    /// Whether a started-but-unfinished check is on screen. The one moment where leaving discards
    /// work, and so the one moment the exit is labelled "Skip".
    private var isMidCheck: Bool { step == .check && session != nil && result == nil && !declaring }

    /// "Schritt 2 von 3", plus a bar. Counts only the steps this run will actually show.
    @ViewBuilder
    private var stepIndicator: some View {
        let all = steps
        if all.count > 1, let index = all.firstIndex(of: step) {
            VStack(spacing: 6) {
                HStack {
                    Text("Step \(index + 1) of \(all.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                ProgressView(value: Double(index + 1), total: Double(all.count))
                    .controlSize(.mini)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    private var navigationTitle: String {
        switch step {
        case .welcome: "Willkommen"
        case .offer: "Dein Tutor"
        case .check where declaring: "Dein Niveau"
        case .check: session == nil && result == nil ? "Wo stehst du?" : "Einstufung"
        }
    }

    /// Moves to the next step this run includes, skipping any that don't apply. Dismisses when
    /// there is nothing left — which is what ends a returning user's two-step run.
    private func advanceStep() {
        let all = steps
        guard let index = all.firstIndex(of: step), index + 1 < all.count else {
            dismiss()
            return
        }
        withAnimation { step = all[index + 1] }
    }

    // MARK: - Step 1: why a download

    /// The screen that answers "why". Deliberately plain: no logo, no brand name, no gigabyte
    /// figure above the fold, and not one word of machine-learning vocabulary.
    private var welcomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your German teacher lives on this iPhone")
                        .font(.title2)
                        .fontWeight(.bold)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Most tutor apps send what you write to a company's servers for processing and storage. This one doesn't. "
                         + "Everything happens on your phone. "
                         + "It works with no signal, and there is nothing to pay.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if includesOffer {
                        Text("The trade: that teacher is a file you download once... and it's a big one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    capabilityRow(
                        symbol: "checkmark.circle.fill",
                        tint: .green,
                        title: "Works right now:",
                        // Only promise the check when this run actually includes it — someone who
                        // already has an estimate is never shown one, and pointing at a screen
                        // they'll never reach would be a small lie on the honesty screen.
                        detail: includesCheck
                            ? "built-in grammar games: der · die · das, prepositions, matching, and the check on the next "
                              + "screen. No download, no signal needed."
                            : "built-in grammar games: der · die · das, prepositions, matching, and every drill. "
                              + "No download, no signal needed."
                    )
                    if includesOffer {
                        capabilityRow(
                            symbol: "arrow.down.circle.fill",
                            tint: hero.theme.accent,
                            title: "With the teacher download (~\(hero.approximateSizeLabel), once): ",
                            detail: "AI-generated stories, and conversation practice with AI"
                                  + "coaching that explains what you got wrong."
                        )
                    }
                    capabilityRow(
                        symbol: "photo.circle.fill",
                        tint: .secondary,
                        title: "Optional:",
                        detail: "There is a secondary \"image generation\" model you can download later that enhances the app further with AI-generated pictures drawn for your flashcards cards and stories. A separate, smaller download "
                              + "you can add any time."
                    )
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    advanceStep()
                } label: {
                    Text("Next")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.bar)
        }
    }

    private func capabilityRow(
        symbol: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Step 2: the tutor offer

    private var pitchPage: some View {
        ScrollView {
            HeroModelPitchContent(model: hero)
                .padding()
                .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) { pitchActionBar }
        .background { ModelSheetBackground(model: hero) }
    }

    private var pitchActionBar: some View {
        VStack(spacing: 10) {
            Button {
                startHeroAndContinue()
            } label: {
                Text(hero.isDownloaded
                     ? "Use \(hero.rawValue)"
                     : "Download \(hero.rawValue) (~\(hero.approximateSizeLabel))")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(hero.theme.accent)

            // Declining is a first-class answer, not a trapdoor. It records the choice so the rest
            // of the flow can say where a tutor lives, rather than moving on in silence.
            Button("Maybe later") {
                declinedDownload = true
                advanceStep()
            }
            .font(.subheadline)
        }
        .padding()
        .background(.bar)
    }

    /// Where to find a tutor, shown once the learner has declined one. Appears on the check's intro
    /// (so someone who skips the check still sees it) and again beside the result.
    @ViewBuilder
    private var declinedNote: some View {
        if declinedDownload, !mlxService.isLoading {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No teacher yet")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Stories and conversation practice need one. You'll find it in "
                             + "Settings ▸ Model & Downloads, any time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    // Dismiss first: the route lands on a tab behind this cover, and pushing it
                    // while the cover is still up would put the destination under it.
                    dismiss()
                    onOpenModelSettings()
                } label: {
                    Text("Take me there")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Same mechanics as the standalone sheet's `useHero()`, minus the dismiss: adopt the hero,
    /// start loading it in the background, and move on to the check while it downloads.
    private func startHeroAndContinue() {
        modelManager.selectedMLXModel = hero
        startedDownload = true
        Task { await mlxService.loadModel(hero) }
        advanceStep()
    }

    // MARK: - Step 3: the check

    @ViewBuilder
    private var quizPage: some View {
        if declaring {
            // Wrapped like the quiz itself: the download runs underneath either door, and the
            // strip is what says so while a level is being picked.
            VStack(spacing: 0) {
                if mlxService.isLoading {
                    ModelDownloadStrip(mlxService: mlxService, model: hero)
                }
                PlacementDeclareStage(
                    initialLevel: modelManager.germanLevel,
                    backLabel: result == nil ? "Take the check instead" : "Back to my result",
                    onConfirm: { declare($0) },
                    onBack: { withAnimation { declaring = false } },
                    onDone: { dismiss() }
                ) {
                    resultFooter
                }
            }
        } else if let result {
            PlacementResultStage(result: result, onDone: { dismiss() }) {
                resultFooter
                Button("Set my level myself") { withAnimation { declaring = true } }
                    .font(.subheadline)
            }
        } else if let session {
            VStack(spacing: 0) {
                if mlxService.isLoading {
                    ModelDownloadStrip(mlxService: mlxService, model: hero)
                }
                quizContent(session)
            }
        } else {
            // The note rides above the intro so someone who declines the tutor and then skips the
            // check still leaves knowing where a tutor lives.
            VStack(spacing: 0) {
                if mlxService.isLoading {
                    ModelDownloadStrip(mlxService: mlxService, model: hero)
                }
                declinedNote
                    .padding(.horizontal)
                    .padding(.top, 8)
                PlacementIntroStage(
                    onStart: { withAnimation { session = PlacementSession() } },
                    onBeginner: { apply(.beginner(), session: nil) },
                    onDeclareLevel: { withAnimation { declaring = true } }
                )
            }
        }
    }

    @ViewBuilder
    private func quizContent(_ session: PlacementSession) -> some View {
        if session.current != nil {
            PlacementQuestionStage(
                session: session,
                hapticMode: modelManager.hapticFeedbackMode,
                onAnswer: advance
            )
        } else if let cloze = session.currentCloze {
            PlacementClozeStage(
                cloze: cloze,
                progress: session.progress,
                hapticMode: modelManager.hapticFeedbackMode
            ) { picks in
                session.answerCloze(picks)
                finish(session)
            }
        } else {
            ProgressView().onAppear { finish(session) }
        }
    }

    /// Below the level card: the full loading panel while the download runs (Cancel lives here,
    /// deliberately not mid-quiz), a quiet ready line once it landed, or — if the learner chose
    /// "Maybe later" — where to find a tutor when they want one.
    @ViewBuilder
    private var resultFooter: some View {
        if declinedDownload, !mlxService.isLoading {
            declinedNote
        } else if mlxService.isLoading {
            VStack(alignment: .leading, spacing: 8) {
                ModelLoadingPanel(mlxService: mlxService, showsHeader: true, headerModel: hero)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else if startedDownload, mlxService.isModelLoaded {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(hero.rawValue) is ready. Stories and conversations now run on it.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Flow (mirrors PlacementQuizView; the invariants travel with it)

    private func advance(_ index: Int?) {
        guard let session else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            session.answer(index)
        }
        if session.isFinished { finish(session) }
    }

    private func finish(_ session: PlacementSession) {
        guard session.isFinished, result == nil else { return }
        apply(session.result(), session: session)
    }

    /// Stores the estimate and adopts it as the content level. Never writes `LearnerProfile` —
    /// same rule as the standalone sheet, for the same reason.
    ///
    /// The guard used to live only in `finish`, which was enough while `save` was idempotent. It
    /// has to be here now: the beginner door calls this directly with no `finish` in front of it,
    /// and an *append* store turns a double-tap into two recorded attempts.
    private func apply(_ scored: PlacementResult, session: PlacementSession?) {
        guard result == nil else { return }
        PlacementService.save(scored)
        PlacementAttemptStore.record(
            result: scored,
            answers: session?.answers ?? [],
            cloze: session?.finishedCloze
        )
        // The level anchor follows the estimate — including for the beginner door, which used to be
        // skipped here and so left a self-declared beginner reading A2 content. `.beginner()`
        // credits the pyramid nothing either way; that's what keeps it honest, not the level.
        modelManager.germanLevel = scored.estimatedLevel
        modelManager.germanLevelIsDeclared = scored.declaredBeginner
        withAnimation { result = scored }
    }

    /// The hard-select door. As in `PlacementQuizView`: no `PlacementService.save`, no
    /// `PlacementAttemptStore.record`. A declaration is a preference, not a measurement — it
    /// credits no provisional fill and draws no Bauplan.
    private func declare(_ level: CEFRLevel) {
        modelManager.germanLevel = level
        modelManager.germanLevelIsDeclared = true
        PlacementService.markOffered()
    }
}

// MARK: - Download strip

/// One slim line above the questions while the model downloads: brand ring, status, and a thin
/// bar when the fraction is real. No Cancel here — mid-quiz is the wrong moment to offer one;
/// the result page's full panel has it.
struct ModelDownloadStrip: View {
    var mlxService: MLXGenerationService
    var model: MLXModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ModelLoadingIndicator(model: model, progress: mlxService.downloadProgress, size: 18)
                Text(mlxService.downloadInfo ?? "Downloading your tutor…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            if let progress = mlxService.downloadProgress, progress > 0 {
                ProgressView(value: progress)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

#Preview {
    OnboardingWizardView(modelManager: MLXModelManager(), mlxService: MLXGenerationService())
}
