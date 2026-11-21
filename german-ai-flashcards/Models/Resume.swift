//
//  Resume.swift
//  german-ai-flashcards
//
//  Lebenslauf (roadmap item 18, docs/JOB_PREP.md ▸ Lebenslauf): the learner's résumé for interview
//  practice. The full text is kept uncapped; the tutor only ever gets the Kurzprofil (a ~500-character
//  German digest the learner reads and edits) and one matching fact per turn.
//
//  Privacy: on this device only. Not in `SyncRegistry`, so it never reaches iCloud; never part of
//  cloud pictures or the coach hand-off. A chat that used it stores only the flag (`usesResume`).
//

import Foundation
import SwiftData

nonisolated struct ResumeFact: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    /// One short fact: a role, a project, a degree, a skill.
    var text: String
}

@Model
final class Resume {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Everything imported, uncapped, as `JobPosting.text` is.
    var fullText: String = ""
    /// "paste", "pdf", "photo".
    var sourceRaw: String = ""
    /// The digest the tutor reads. The learner's to edit; what they see is what the tutor gets.
    var kurzprofil: String = ""
    /// Encoded `[ResumeFact]`.
    var factsData: Data? = nil

    init() {}

    var facts: [ResumeFact] {
        get { factsData.flatMap { try? JSONDecoder().decode([ResumeFact].self, from: $0) } ?? [] }
        set { factsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
}

@MainActor
enum ResumeStore {
    static func current(in context: ModelContext) -> Resume? {
        var d = FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    static func orCreate(in context: ModelContext) -> Resume {
        if let existing = current(in: context) { return existing }
        let made = Resume()
        context.insert(made)
        return made
    }
}
