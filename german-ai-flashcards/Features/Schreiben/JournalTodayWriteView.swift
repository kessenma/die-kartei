//
//  JournalTodayWriteView.swift
//  german-ai-flashcards
//
//  The Today plan's "write a few lines": today's Tagebuch page, made when this screen appears
//  (never in the planner or a view builder, which would mint a row on every render), with the
//  day's bank prompt on it when the page is still blank.
//

import SwiftData
import SwiftUI

struct JournalTodayWriteView: View {
    let prompt: String?
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @State private var entry: JournalEntry?

    var body: some View {
        if let entry {
            JournalEntryView(entry: entry, modelManager: modelManager, mlxService: mlxService)
        } else {
            Color.clear.onAppear(perform: open)
        }
    }

    private func open() {
        let page = JournalEntryStore.todayTagebuch(in: modelContext)
            ?? JournalEntryStore.make(kind: .tagebuch, level: modelManager.germanLevel, in: modelContext)
        if let prompt, page.isEmpty, !page.hasPrompt {
            let bank = WritingPromptBank.all.first { $0.de == prompt }
            page.promptID = bank?.id
            page.promptDE = prompt
            page.promptEN = bank?.en
            page.promptSource = .coach
            page.promptFocus = bank?.grammarFocus
            page.touch()
            try? modelContext.save()
        }
        entry = page
    }
}
