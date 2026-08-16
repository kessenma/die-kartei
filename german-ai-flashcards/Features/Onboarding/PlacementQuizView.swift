//
//  PlacementQuizView.swift
//  german-ai-flashcards
//
//  "Wo stehst du?" — the optional three-minute placement check as a standalone sheet, used for
//  retakes from the Lernpyramide and Settings. First launch runs the same stages inside
//  `OnboardingWizardView`; the stages themselves live in `PlacementQuizStages.swift`.
//
//  Deliberately gives **no right/wrong feedback** between questions — and none on the cloze
//  finale either. This is a measurement, not a lesson: feedback would turn a placement check into
//  a teaching moment, slow it down, and let a learner tune their answers partway through. It also
//  keeps a beginner from being told "wrong" twenty times in the first three minutes of using the
//  app.
//
//  Every question comes from bundled JSON, so this runs on first launch with no model downloaded.
//

import SwiftUI

struct PlacementQuizView: View {
    var modelManager: MLXModelManager

    /// Called with the finished estimate, so the presenter can react (the pyramid re-reads it on
    /// its own; this exists for the retake flow to refresh in place).
    var onFinish: ((PlacementResult) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var session: PlacementSession?
    @State private var result: PlacementResult?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    PlacementResultStage(result: result) { dismiss() }
                } else if let session {
                    quizContent(session)
                } else {
                    PlacementIntroStage(
                        onStart: { withAnimation { session = PlacementSession() } },
                        onBeginner: { finishAsBeginner() }
                    )
                }
            }
            .navigationTitle(session == nil && result == nil ? "Wo stehst du?" : "Einstufung")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Skip" : "Close") {
                        if result == nil { PlacementService.markOffered() }
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(session != nil && result == nil)
    }

    // MARK: - Quiz

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

    // MARK: - Flow

    private func advance(_ index: Int?) {
        guard let session else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            session.answer(index)
        }
        if session.isFinished { finish(session) }
    }

    /// Guarded because the finale, `advance`, and the empty-state `onAppear` can all reach it —
    /// whichever arrives first wins, and scoring must not run (or save) twice.
    private func finish(_ session: PlacementSession) {
        guard session.isFinished, result == nil else { return }
        apply(session.result())
    }

    private func finishAsBeginner() {
        apply(.beginner())
    }

    /// Stores the estimate and adopts it as the content level. Note what this does *not* do: it
    /// never writes to `LearnerProfile`. The coach's briefing has to stay measured-in-app-only, or
    /// an estimate would launder itself into the record the AI treats as fact.
    private func apply(_ scored: PlacementResult) {
        PlacementService.save(scored)
        if !scored.declaredBeginner {
            modelManager.chatLevelRaw = scored.estimatedLevelRaw
            modelManager.storyLevelRaw = scored.estimatedLevelRaw
        }
        onFinish?(scored)
        withAnimation { result = scored }
    }
}

#Preview {
    PlacementQuizView(modelManager: MLXModelManager())
}
