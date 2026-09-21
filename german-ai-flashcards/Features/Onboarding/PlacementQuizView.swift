//
//  PlacementQuizView.swift
//  german-ai-flashcards
//
//  "Wo stehst du?" — the optional three-minute placement check as a standalone sheet, used for
//  retakes from the Lernpyramide and Settings. First launch runs the same stages inside
//  `OnboardingWizardView`; the stages themselves live in `PlacementQuizStages.swift`.
//
//  Answers are marked right or wrong for half a second before the next question, and the switch
//  for that sits at the top of every question (`PlacementFeedbackOption`, default on). Turning it
//  off restores the older behaviour — silence from the first question through to the result —
//  which is the purer measurement: no teaching moment mid-check, and no chance to tune answers as
//  you go. What the switch never touches is the scoring; the marks are display only.
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
    /// Showing the hard-select door instead of the check. Reachable from the intro and from the
    /// result stage, since "the estimate is wrong" is the other moment someone wants it.
    ///
    /// Starts true under `-placement.debugOpenDeclare 1` (DEBUG), because the door is one tap past
    /// the intro and a simulator takes launch arguments but not taps.
    @State private var declaring = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "placement.debugOpenDeclare")
        #else
        return false
        #endif
    }()
    /// The attempt just recorded, so the review link opens straight onto *this* run's results
    /// rather than the whole history.
    @State private var recordedAttempt: PlacementAttempt?

    var body: some View {
        NavigationStack {
            Group {
                if declaring {
                    PlacementDeclareStage(
                        initialLevel: modelManager.germanLevel,
                        // Arriving here from a finished result, backing out returns to that
                        // result — offering to "take the check" would be nonsense, it just ran.
                        backLabel: result == nil ? "Take the check instead" : "Back to my result",
                        onConfirm: { declare($0) },
                        onBack: { withAnimation { declaring = false } },
                        onDone: { dismiss() }
                    )
                } else if let result {
                    PlacementResultStage(result: result, onDone: { dismiss() }) {
                        resultFooter
                    }
                } else if let session {
                    quizContent(session)
                } else {
                    PlacementIntroStage(
                        onStart: { withAnimation { session = PlacementSession() } },
                        onBeginner: { finishAsBeginner() },
                        onDeclareLevel: { withAnimation { declaring = true } }
                    )
                }
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // "Skip" only while there's a check to skip — picking a level isn't one.
                    Button(result == nil && !declaring ? "Skip" : "Close") {
                        if result == nil { PlacementService.markOffered() }
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(session != nil && result == nil)
    }

    private var navigationTitle: String {
        if declaring { return "Dein Niveau" }
        return session == nil && result == nil ? "Wo stehst du?" : "Einstufung"
    }

    /// Two offers under a finished result. The review link is the whole answer sheet, which matters
    /// most to someone who took the check with the marks switched off and so was told nothing about
    /// any of it. The second is the escape hatch for the other reaction to a result: "that's not
    /// right."
    @ViewBuilder
    private var resultFooter: some View {
        VStack(spacing: 12) {
            if let recordedAttempt, !recordedAttempt.records.isEmpty {
                NavigationLink {
                    PlacementAttemptDetailView(attempt: recordedAttempt)
                } label: {
                    Label("See what you missed", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
            Button("Set my level myself") { withAnimation { declaring = true } }
                .font(.subheadline)
        }
    }

    // MARK: - Quiz

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
        apply(session.result(), session: session)
    }

    private func finishAsBeginner() {
        apply(.beginner(), session: nil)
    }

    /// Stores the estimate and adopts it as the content level. Note what this does *not* do: it
    /// never writes to `LearnerProfile`. The coach's briefing has to stay measured-in-app-only, or
    /// an estimate would launder itself into the record the AI treats as fact. Recording the
    /// answers doesn't change that — `PlacementAttemptStore` is a file the review screen reads and
    /// nothing else does; only the explicit hand-off button ever crosses into the profile.
    ///
    /// The guard used to live only in `finish`, which was enough while `save` was idempotent. It
    /// has to be here now: `finishAsBeginner` calls this directly, and an *append* store turns a
    /// double-tap into two recorded attempts.
    private func apply(_ scored: PlacementResult, session: PlacementSession?) {
        guard result == nil else { return }
        PlacementService.save(scored)
        PlacementAttemptStore.record(
            result: scored,
            answers: session?.answers ?? [],
            cloze: session?.finishedCloze
        )
        recordedAttempt = PlacementAttemptStore.attempts().first
        // The level anchor follows the estimate — including for the beginner door, which used to be
        // skipped here and so left a self-declared beginner reading A2 content. `.beginner()`
        // credits the pyramid nothing either way; that's what keeps it honest, not the level.
        modelManager.germanLevel = scored.estimatedLevel
        modelManager.germanLevelIsDeclared = scored.declaredBeginner
        onFinish?(scored)
        withAnimation { result = scored }
    }

    /// The hard-select door. Note what is absent and must stay absent: no `PlacementService.save`,
    /// no `PlacementAttemptStore.record`. A declaration is a preference, not a measurement — it
    /// credits no provisional fill and draws no Bauplan. `markOffered` only stops onboarding from
    /// asking again; the check itself stays available from Your Level and the Lernpyramide.
    ///
    /// `onFinish` deliberately doesn't fire: every presenter uses it to re-read
    /// `PlacementService.current`, and declaring leaves that untouched.
    private func declare(_ level: CEFRLevel) {
        modelManager.germanLevel = level
        modelManager.germanLevelIsDeclared = true
        PlacementService.markOffered()
    }
}

#Preview {
    PlacementQuizView(modelManager: MLXModelManager())
}
