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
                } footer: {
                    Text("Celebrations off keeps the numbers and badges, loses the confetti.")
                }
                .themedListRow()

                Section {
                    Button(PlacementService.current == nil ? "Take the placement check" : "Retake the placement check") {
                        showPlacement = true
                    }
                    if !PlacementAttemptStore.isEmpty {
                        NavigationLink {
                            PlacementReviewView()
                        } label: {
                            Label("See what you missed", systemImage: "list.bullet.rectangle")
                        }
                    }
                    if PlacementService.current != nil {
                        Button("Remove the estimate", role: .destructive) {
                            PlacementService.clear()
                            placementRevision += 1
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
            return "A three-minute check that outlines what you already know on the pyramid, and sets the level for stories and conversations."
        }
        if placement.declaredBeginner {
            return "You said you're starting from zero, so nothing is estimated. Take the check whenever that changes."
        }
        let when = placement.takenAt.formatted(date: .abbreviated, time: .omitted)
        return "Placed at \(placement.estimatedLevel.rawValue) on \(when). An estimate only outlines a layer — removing it leaves everything you've proven untouched, and your past answers are kept separately."
    }
}
