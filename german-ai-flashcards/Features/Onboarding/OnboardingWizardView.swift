//
//  OnboardingWizardView.swift
//  german-ai-flashcards
//
//  The first-launch wizard: hero-model pitch → placement check → result plus download status.
//  The model downloads while the questions run, so the multi-minute wait disappears into the
//  three-minute check. Both halves stay independently presentable elsewhere — the pitch as
//  `HeroModelIntroSheet` from Settings, the check as `PlacementQuizView` for retakes — which is
//  why every stage here comes from `PlacementQuizStages` / `HeroModelPitchContent` rather than
//  being its own copy.
//
//  The presenter writes all first-launch flags *before* this sheet appears (crash safety, same
//  discipline as the model sheets), so Close never turns into a re-nag.
//

import SwiftUI

struct OnboardingWizardView: View {
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.dismiss) private var dismiss

    private enum Page { case pitch, quiz }
    @State private var page: Page
    /// Whether this wizard kicked off the hero download, so the result page only talks about a
    /// download the learner actually chose.
    @State private var startedDownload = false
    @State private var session: PlacementSession?
    @State private var result: PlacementResult?

    init(modelManager: MLXModelManager, mlxService: MLXGenerationService) {
        self.modelManager = modelManager
        self.mlxService = mlxService
        // A device that can't run the hero starts at the check — placement has never been
        // capability-gated and must not become so.
        _page = State(initialValue: DeviceCapability.canRunHero ? .pitch : .quiz)
    }

    private var hero: MLXModel { .hero }

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .pitch: pitchPage
                case .quiz: quizPage
                }
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(page == .pitch || result != nil ? "Close" : "Skip") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(session != nil && result == nil)
    }

    private var navigationTitle: String {
        switch page {
        case .pitch: "Willkommen"
        case .quiz: session == nil && result == nil ? "Wo stehst du?" : "Einstufung"
        }
    }

    // MARK: - Page 1: the pitch

    private var pitchPage: some View {
        ScrollView {
            HeroModelPitchContent()
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

            Button("Maybe later") { withAnimation { page = .quiz } }
                .font(.subheadline)
        }
        .padding()
        .background(.bar)
    }

    /// Same mechanics as the standalone sheet's `useHero()`, minus the dismiss: adopt the hero,
    /// start loading it in the background, and move on to the check while it downloads.
    private func startHeroAndContinue() {
        modelManager.selectedMLXModel = hero
        startedDownload = true
        Task { await mlxService.loadModel(hero) }
        withAnimation { page = .quiz }
    }

    // MARK: - Page 2: the check

    @ViewBuilder
    private var quizPage: some View {
        if let result {
            PlacementResultStage(result: result, onDone: { dismiss() }) {
                resultFooter
            }
        } else if let session {
            VStack(spacing: 0) {
                if mlxService.isLoading {
                    ModelDownloadStrip(mlxService: mlxService, model: hero)
                }
                quizContent(session)
            }
        } else {
            PlacementIntroStage(
                onStart: { withAnimation { session = PlacementSession() } },
                onBeginner: { apply(.beginner(), session: nil) }
            )
        }
    }

    @ViewBuilder
    private func quizContent(_ session: PlacementSession) -> some View {
        if session.current != nil {
            PlacementQuestionStage(session: session, onAnswer: advance)
        } else if let cloze = session.currentCloze {
            PlacementClozeStage(cloze: cloze, progress: session.progress) { picks in
                session.answerCloze(picks)
                finish(session)
            }
        } else {
            ProgressView().onAppear { finish(session) }
        }
    }

    /// Below the level card: the full loading panel while the download runs (Cancel lives here,
    /// deliberately not mid-quiz), or a quiet ready line once it landed. Nothing if the learner
    /// chose "Maybe later".
    @ViewBuilder
    private var resultFooter: some View {
        if mlxService.isLoading {
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
        apply(session.result())
    }

    /// Stores the estimate and adopts it as the content level. Never writes `LearnerProfile` —
    /// same rule as the standalone sheet, for the same reason.
    private func apply(_ scored: PlacementResult) {
        PlacementService.save(scored)
        if !scored.declaredBeginner {
            modelManager.chatLevelRaw = scored.estimatedLevelRaw
            modelManager.storyLevelRaw = scored.estimatedLevelRaw
        }
        withAnimation { result = scored }
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
