//
//  LevelSettingsView.swift
//  german-ai-flashcards
//
//  Settings ▸ Learning ▸ Your Level — where the learner says what level they are, outright.
//
//  This screen owns `MLXModelManager.germanLevel`, the one anchor every level picker in the app
//  opens at. It sits first in the Learning section because Flashcards / Conversation / Stories all
//  inherit from it.
//
//  What it deliberately does NOT do: write a `PlacementResult`. A level you assert is a preference,
//  not a measurement — it credits the Lernpyramide nothing, draws no Bauplan, and leaves the check
//  worth taking. (`docs/GAMIFICATION.md` — "Declared is not measured".)
//

import SwiftUI

struct LevelSettingsView: View {
    @Bindable var modelManager: MLXModelManager

    @State private var showPlacement = false
    /// The estimate lives in UserDefaults, which SwiftUI can't observe — bumping this re-reads it.
    /// Same manual invalidation `PyramidView` and `GamificationSettingsView` use.
    @State private var placementRevision = 0

    private var placement: PlacementResult? {
        _ = placementRevision
        return PlacementService.current
    }

    var body: some View {
        Form {
            SettingsHeader(icon: "figure.stairs", title: "Your Level")

            Section {
                LevelChoiceList(selection: Binding(
                    get: { modelManager.germanLevel },
                    // Picking here is the learner speaking for themselves, which is exactly what
                    // the flag records — a later check will clear it again.
                    set: {
                        modelManager.germanLevel = $0
                        modelManager.germanLevelIsDeclared = true
                    }
                ))
            } header: {
                Text("Wie gut sprichst du? · Your German").themedSectionHeader()
            } footer: {
                Text("Conversations, stories and queued jobs all start here. You can still pick a different level inside any of them — that applies to that one exercise and leaves this alone.")
                    .font(.caption2)
            }
            .themedListRow()

            Section {
                if let placement, !placement.declaredBeginner {
                    checkSummary(placement)
                    if placement.estimatedLevel != modelManager.germanLevel {
                        Button("Use my check's estimate (\(placement.estimatedLevel.rawValue))") {
                            modelManager.germanLevel = placement.estimatedLevel
                            // Measured, not asserted — so the flag comes back off and the copy
                            // above stops claiming the learner chose it.
                            modelManager.germanLevelIsDeclared = false
                        }
                    }
                    Button("Take the check again") { showPlacement = true }
                } else {
                    Button("Take the three-minute check") { showPlacement = true }
                }
            } header: {
                Text("Nicht sicher? · Not sure").themedSectionHeader()
            } footer: {
                Text(checkFooter).font(.caption2)
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPlacement) {
            PlacementQuizView(modelManager: modelManager) { _ in placementRevision += 1 }
        }
    }

    /// What the last check concluded, next to what's actually in force — the two can differ, and
    /// the whole point of this screen is that the learner is allowed to overrule the estimate.
    private func checkSummary(_ placement: PlacementResult) -> some View {
        HStack(spacing: 12) {
            CEFRLevelChip(level: placement.estimatedLevel)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your check said \(placement.estimatedLevel.rawValue)")
                    .font(.subheadline)
                Text(placement.takenAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your check said \(placement.estimatedLevel.rawValue), taken \(placement.takenAt.formatted(date: .abbreviated, time: .omitted))")
    }

    private var checkFooter: String {
        let level = modelManager.germanLevel.rawValue
        guard let placement else {
            return "Not sure which one you are? The check asks about words, der/die/das, cases and a few structures, and estimates a level for you. It also drafts a blueprint on your Lernpyramide — picking a level here never does that."
        }
        if placement.declaredBeginner {
            return "You said you're starting from zero, so there's no blueprint. Take the check whenever that changes."
        }
        if modelManager.germanLevelIsDeclared && placement.estimatedLevel != modelManager.germanLevel {
            return "You set \(level) yourself, and your check estimated \(placement.estimatedLevel.rawValue). Yours is what the app uses. The check's blueprint on the Lernpyramide is unaffected either way — a level you pick here is never counted as built."
        }
        return modelManager.germanLevelIsDeclared
            ? "You set \(level) yourself. A level you pick here only sets how hard the German is — it's never counted as built on your Lernpyramide."
            : "\(level) came from your check on \(placement.takenAt.formatted(date: .abbreviated, time: .omitted)). Change it above any time; the check's blueprint stays as it is."
    }
}
