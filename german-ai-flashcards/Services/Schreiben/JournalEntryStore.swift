//
//  JournalEntryStore.swift
//  german-ai-flashcards
//
//  The few writes the Schreiben room makes to `JournalEntry` rows that more than one screen
//  shares: today's Tagebuch page, a fresh entry, a delete that takes the ink files with it, and
//  the day credit an entry earns when the learner puts it down.
//

import Foundation
import SwiftData
#if canImport(PencilKit)
import PencilKit
#endif

@MainActor
enum JournalEntryStore {

    /// The page's ink to its file, and what the row needs to know about it (the stroke count,
    /// so lists never open the file; the page height, so a page written on has one).
    static func saveInk(_ data: Data?, for entry: JournalEntry, in context: ModelContext) {
        JournalInkStore.write(data, for: entry.id)
        var strokes = 0
        #if canImport(PencilKit)
        if let data, let drawing = try? PKDrawing(data: data) { strokes = drawing.strokes.count }
        #else
        if data != nil { strokes = max(entry.inkStrokeCount, 1) }
        #endif
        if entry.inkStrokeCount != strokes || (data != nil && entry.inkHeight == 0) {
            entry.inkStrokeCount = strokes
            if data != nil, entry.inkHeight == 0 { entry.inkHeight = JournalInkStore.initialHeight }
            entry.touch()
            try? context.save()
        }
    }

    /// Today's Tagebuch entry, the newest if there are several, or nil.
    static func todayTagebuch(in context: ModelContext) -> JournalEntry? {
        let start = Calendar.current.startOfDay(for: .now)
        let kind = JournalKind.tagebuch.rawValue
        var d = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.day == start && $0.kindRaw == kind },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// A new entry at the learner's declared level, inserted and saved.
    @discardableResult
    static func make(kind: JournalKind, level: CEFRLevel, in context: ModelContext) -> JournalEntry {
        let entry = JournalEntry(kind: kind, level: level)
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// A new essay with its prompt frozen on it.
    @discardableResult
    static func makeEssay(de: String, en: String?, promptID: String?, source: JournalPromptSource,
                          focus: GrammarFocus?, target: ClosedRange<Int>?, level: CEFRLevel,
                          in context: ModelContext) -> JournalEntry {
        let entry = JournalEntry(kind: .aufsatz, level: level)
        entry.promptID = promptID
        entry.promptDE = de
        entry.promptEN = en
        entry.promptSource = source
        entry.promptFocus = focus
        if let target {
            entry.targetMin = target.lowerBound
            entry.targetMax = target.upperBound
        }
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// Newest first.
    static func recent(limit: Int, in context: ModelContext) -> [JournalEntry] {
        var d = FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        d.fetchLimit = limit
        return (try? context.fetch(d)) ?? []
    }

    static func fetch(id: UUID, in context: ModelContext) -> JournalEntry? {
        var d = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// SwiftData does not own the ink files.
    static func delete(_ entry: JournalEntry, in context: ModelContext) {
        JournalInkStore.deleteAll(for: entry.id)
        context.delete(entry)
        try? context.save()
    }

    /// Words the entry gained since it was last credited go to today's study day. A handful of
    /// words is not a session, so nothing under `minimumDelta` is counted; the high-water mark
    /// means a reopened entry credits only what was added.
    static let minimumDelta = 10

    static func creditWords(for entry: JournalEntry, in context: ModelContext) {
        let now = entry.wordCount
        let delta = now - entry.creditedWords
        guard delta >= minimumDelta else { return }
        StudyLogService.record(.writing(delta), in: context)
        entry.creditedWords = now
        try? context.save()
    }
}
