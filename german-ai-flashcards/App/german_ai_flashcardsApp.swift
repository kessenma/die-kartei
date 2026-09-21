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
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Recreate the background download session on every launch: transfers that finished
        // or failed while the app was gone deliver their callbacks now and get settled into
        // their partial files, not only once a download screen happens to start one.
        BackgroundModelDownloadSession.shared.activate()
        // iOS's own account of crashes and memory-limit kills, filed into the memory log next to
        // the app's session-marker records (Settings ▸ Speicher).
        MetricKitSubscriber.shared.start()
        return true
    }

    /// Rarely called on iOS — a foreground quit, some background terminations — but when it is,
    /// the next launch must not report this session as a crash.
    func applicationWillTerminate(_ application: UIApplication) {
        MemoryDiagnostics.endSessionCleanly()
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundModelDownloadSession.shared.setBackgroundCompletionHandler(completionHandler)
        // Woken in the background because a file finished: keep the download moving (commit
        // the file, enqueue the next one) instead of waiting for the user to come back.
        if application.applicationState == .background {
            BackgroundDownloadResumer.kickIfNeeded()
        }
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
            BatchJob.self,
            JobPosting.self
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
                    // The session marker's app state is what decides whether an unclean exit is
                    // reported as "closed while in use" or "closed in the background".
                    MemoryDiagnostics.sceneDidChange()
                    // A model download cut off while the user was in another app resumes
                    // from its saved partial files as soon as they come back — even when
                    // the cutoff was iOS terminating the app. The background wake driver
                    // stops first: two drivers would race one repo's partials.
                    if phase == .active {
                        Task { @MainActor in
                            await BackgroundDownloadResumer.stop()
                            coordinator.mlxService.resumeInterruptedDownloadIfNeeded()
                        }
                    }
                    // Leaving the foreground with multi-GB weights resident is the single fastest
                    // way to get the app terminated: iOS ranks suspended apps for jetsam largely
                    // by footprint, so a trip to Settings (adding a German keyboard, say) is
                    // enough to lose the open conversation's in-flight turn. Shed the model on the
                    // devices that have no room to spare for it; the screen that was using it
                    // reloads it on return (see `MLXGenerationService.releaseMemory(reason:)`).
                    if phase == .background {
                        coordinator.mlxService.releaseMemory(reason: .background)
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
