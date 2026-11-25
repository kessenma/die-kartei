//
//  ClassTutorContext.swift
//  german-ai-flashcards
//
//  What the learner's class covered lately, rendered for the conversation tutor (docs/CLASS_NOTES.md
//  ▸ Tutors read the class). Built from the last fortnight's `ClassEntry.tutorContext`, newest
//  first, whole entries only, capped so it fits the small tutors' context next to everything else.
//  Gated by `MLXModelManager.classFeedsCoach`; never used in interview or paper chats, which carry
//  their own documents.
//

import Foundation
import SwiftData

@MainActor
enum ClassTutorContext {
    static let days = 14
    /// Characters of class context a conversation prompt may carry.
    static let cap = 1_200

    /// Entries from active courses in the last `days`, newest first, with something to say.
    static func recentEntries(in context: ModelContext, now: Date = .now) -> [ClassEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        let descriptor = FetchDescriptor<ClassEntry>(predicate: #Predicate { $0.date >= cutoff },
                                                     sortBy: [SortDescriptor(\.date, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).filter { entry in
            !entry.isEmpty && entry.date <= now && entry.course?.isArchived != true
        }
    }

    /// The entries' tutor text, whole entries until the cap. Nil when nothing recent.
    static func text(in context: ModelContext, now: Date = .now) -> String? {
        var out: [String] = []
        var used = 0
        for entry in recentEntries(in: context, now: now) {
            let block = entry.tutorContext
            guard used + block.count <= cap else { break }
            out.append(block)
            used += block.count + 2
        }
        return out.isEmpty ? nil : out.joined(separator: "\n\n")
    }

    /// The system-prompt section around the text.
    nonisolated static func promptSection(_ text: String) -> String {
        """
        The learner is taking a German class. This is what it covered recently:
        \"\"\"
        \(text)
        \"\"\"
        Where it fits naturally, use words and topics from the class and give the learner chances to \
        use its grammar. Do not quiz them on it, and do not mention the class unless they do.
        """
    }
}
