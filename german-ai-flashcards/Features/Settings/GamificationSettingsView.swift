//
//  GamificationSettingsView.swift
//  german-ai-flashcards
//
//  Settings ▸ App ▸ Gamification — the game layer's home. Master switch (on by default), the
//  daily goal behind the Tagesziel ring, and per-feature switches for celebrations, badges and
//  the pyramid. Turning the master off hides every gamified surface; nothing stops accruing,
//  because XP, badges and pyramid fills are all derived from the study log — switching back on
//  restores the full picture.
//

import SwiftUI

struct GamificationSettingsView: View {
    @Bindable var modelManager: MLXModelManager

    @State private var showPlacement = false
    /// The estimate lives in UserDefaults, which SwiftUI can't observe — bumping this re-reads it.
    @State private var placementRevision = 0

    var body: some View {
        Form {
            SettingsHeader(icon: "gamecontroller", title: "Gamification")

            Section {
                Toggle("Gamification", isOn: $modelManager.gamificationEnabled)
            } footer: {
                Text("The level card, daily goal (Tagesziel), badges (Abzeichen) and the learning pyramid (Lernpyramide) on Home. Off hides them all — your progress keeps accruing either way.")
            }
            .themedListRow()

            if modelManager.gamificationEnabled {
                Section {
                    Picker("Daily goal", selection: $modelManager.dailyGoalMinutes) {
                        ForEach(ExperienceService.dailyGoalOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                } header: {
                    Text("Tagesziel · Daily Goal")
                } footer: {
                    Text("The ring on Home closes when you've studied this many minutes today — any activity counts.")
                }
                .themedListRow()

                Section {
                    Toggle("Celebrations", isOn: $modelManager.gamificationCelebrationsEnabled)
                    Toggle("Badges (Abzeichen)", isOn: $modelManager.gamificationBadgesEnabled)
                    Toggle("Learning pyramid", isOn: $modelManager.gamificationPyramidEnabled)
                    Toggle("„Weißt du es noch?“", isOn: $modelManager.gamificationRememberProbeEnabled)
                } footer: {
                    Text("Celebrations off keeps the numbers and badges, loses the confetti. „Weißt du es noch?“ is the one-question check on Dein Weg that re-tests something you mastered a while ago.")
                }
                .themedListRow()

                Section {
                    Button(PlacementService.current == nil ? "Take the placement check" : "Retake the placement check") {
                        showPlacement = true
                    }
                    // No "Remove the estimate" here either — switching, stopping and reviewing all
                    // live on the history screen now, where they read as managing a list rather
                    // than clearing a slot.
                    if !PlacementAttemptStore.isEmpty {
                        NavigationLink {
                            PlacementReviewView(modelManager: modelManager)
                        } label: {
                            Label("Your checks", systemImage: "list.bullet.rectangle")
                        }
                    }
                } header: {
                    Text("Einstufung · Placement")
                } footer: {
                    Text(placementFooter)
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPlacement) {
            PlacementQuizView(modelManager: modelManager) { _ in placementRevision += 1 }
        }
    }

    private var placementFooter: String {
        guard let placement = PlacementService.current else {
            return "A three-minute check that drafts a blueprint of what you already know on the pyramid, and sets the level for stories and conversations."
        }
        if placement.declaredBeginner {
            return "You said you're starting from zero, so there's no blueprint. Take the check whenever that changes."
        }
        let when = placement.takenAt.formatted(date: .abbreviated, time: .omitted)
        return "Placed at \(placement.estimatedLevel.rawValue) on \(when). A blueprint is never counted as built. Every check is kept — compare them, switch which blueprint is applied, or put it away under Your checks."
    }
}
