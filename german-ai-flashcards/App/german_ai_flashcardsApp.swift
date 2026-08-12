//
//  german_ai_flashcardsApp.swift
//  german-ai-flashcards
//
//  Created by Kyle Essenmacher on 5/14/26.
//

import SwiftUI
import SwiftData
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundModelDownloadSession.shared.setBackgroundCompletionHandler(completionHandler)
    }
}

@main
struct german_ai_flashcardsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let container: ModelContainer
    @State private var modelManager: MLXModelManager
    @State private var coordinator: GenerationCoordinator
    @Environment(\.scenePhase) private var scenePhase

    /// The app-wide visual identity. `klar` (the untouched baseline) by default, so shipping the
    /// theme system is a no-op until the learner opts into another theme in Settings.
    @AppStorage(AppTheme.defaultsKey) private var appTheme: AppTheme = .klar

    init() {
        // The Klassisch/Geschichte scene-style toggle was removed 2026-08-12 (the sets merged
        // into one curated scene per word); the key was user-visible in the preposition hub,
        // so stale devices exist.
        UserDefaults.standard.removeObject(forKey: "prepositions.sceneStyle")

        let schema = Schema([
            SavedDeck.self, SavedCard.self, QuizResult.self,
            ChatConversation.self, ChatMessage.self,
            StudyPaper.self,
            StudyStory.self,
            LearnedPhrase.self,
            LearnerProfile.self, ArchivedMemoryItem.self,
            StudyDay.self,
            MatchingPairStat.self, MatchingRound.self,
            ArticleWordStat.self, ArticleRound.self,
            PrepositionStat.self, PrepositionRound.self,
            StoryReadingSession.self, StoryQuizAttempt.self,
            BatchJob.self
        ])
        let config = SwiftData.ModelConfiguration(schema: schema)

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema changed — delete old store and recreate
            print("SwiftData migration failed: \(error). Recreating store.")
            let storeURL = config.url
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove WAL/SHM files
            let walURL = storeURL.appendingPathExtension("wal")
            let shmURL = storeURL.appendingPathExtension("shm")
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)

            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }

        let mm = MLXModelManager()
        _modelManager = State(initialValue: mm)
        _coordinator = State(initialValue: GenerationCoordinator(modelManager: mm))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: coordinator)
                .environment(coordinator.mlxService)
                .environment(\.appTheme, appTheme)
                .onChange(of: scenePhase) { _, phase in
                    // A model download cut off while the user was in another app resumes
                    // from its saved partial files as soon as they come back.
                    if phase == .active {
                        coordinator.mlxService.resumeInterruptedDownloadIfNeeded()
                    }
                    // Keep practice reminders anchored to the real last-practice date: re-derive the
                    // ladder whenever the app enters or leaves the foreground. Leaving captures any
                    // practice done this session; entering picks up permission or settings changes.
                    if phase == .active || phase == .background {
                        Task { @MainActor in
                            await PracticeReminderService.refresh(
                                context: container.mainContext,
                                modelManager: modelManager
                            )
                        }
                    }
                }
        }
        .modelContainer(container)
    }
}
