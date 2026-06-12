//
//  german_ai_flashcardsApp.swift
//  german-ai-flashcards
//
//  Created by Kyle Essenmacher on 5/14/26.
//

import SwiftUI
import SwiftData

@main
struct german_ai_flashcardsApp: App {
    let container: ModelContainer
    @State private var modelManager: MLXModelManager
    @State private var coordinator: GenerationCoordinator

    init() {
        let schema = Schema([
            SavedDeck.self, SavedCard.self, QuizResult.self,
            ChatConversation.self, ChatMessage.self,
            StudyPaper.self
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
        }
        .modelContainer(container)
    }
}
