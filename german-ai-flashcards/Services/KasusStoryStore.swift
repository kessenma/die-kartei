//
//  KasusStoryStore.swift
//  german-ai-flashcards
//
//  The tutor-written Kasus stories beside the bundled ones (Phase 3): saving a story that passed
//  the check, the unit's list („Deine KI-Geschichten“), deleting one, and one bank with both for
//  anything that looks a story up by id (a round's title in Verlauf, the calendar's day detail).
//
//  A generated story is launched with its story attached (`KasusSession(generated:unit:)`), so
//  the player never has to find it; its rounds file under its id like a bundled story's.
//  Deleting a story keeps its rounds: they hold their sentences and answers already.
//

import Foundation
import SwiftData

@MainActor
enum KasusStoryStore {

    /// Saves the story a generation passed. Nil unless the result is `.generated`.
    @discardableResult
    static func save(_ result: KasusGenerationResult, in context: ModelContext) -> GeneratedKasusStory? {
        guard result.outcome == .generated, let story = result.story, let attempt = result.passing else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let row = GeneratedKasusStory(
            id: story.id,
            unitRaw: story.unitRaw,
            level: story.level,
            modelID: result.modelID,
            title: story.title,
            planData: try? encoder.encode(attempt.plan),
            storyData: try? encoder.encode(story),
            validatorSummary: attempt.check?.summaryLine ?? "",
            attempts: attempt.number,
            generationSeconds: attempt.seconds
        )
        context.insert(row)
        try? context.save()
        return row
    }

    /// The unit's generated stories, newest first.
    static func stories(for unit: KasusUnit, in context: ModelContext) -> [GeneratedKasusStory] {
        let raw = unit.rawValue
        let descriptor = FetchDescriptor<GeneratedKasusStory>(
            predicate: #Predicate { $0.unitRaw == raw },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// A tutor-written story's id („kg-dativ-a2-3f9a1c0b“, `KasusStoryPlan.newStoryID`), so a
    /// title lookup only reaches for the store when it could find something there.
    static func isGenerated(id: String) -> Bool { id.hasPrefix("kg-") }

    /// The title of a tutor-written story still in the store, for rounds played on it.
    static func title(id: String, in context: ModelContext) -> String? {
        guard isGenerated(id: id) else { return nil }
        return row(id: id, in: context)?.title
    }

    static func row(id: String, in context: ModelContext) -> GeneratedKasusStory? {
        let descriptor = FetchDescriptor<GeneratedKasusStory>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    /// A generated story by id, decoded.
    static func story(id: String, in context: ModelContext) -> KasusStory? {
        row(id: id, in: context)?.story
    }

    /// Removes the story. Its rounds stay.
    static func delete(_ row: GeneratedKasusStory, in context: ModelContext) {
        context.delete(row)
        try? context.save()
    }

    /// The bundled stories and every generated one, for lookups by id. The bundled list stays
    /// what the path, the hub's dots and `GrammarRoute` use.
    static func bank(in context: ModelContext) -> KasusStoryBank {
        let generated = ((try? context.fetch(FetchDescriptor<GeneratedKasusStory>())) ?? []).compactMap(\.story)
        return KasusStoryBank.bundled.merging(generated)
    }
}
