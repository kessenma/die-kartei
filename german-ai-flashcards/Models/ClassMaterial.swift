//
//  ClassMaterial.swift
//  german-ai-flashcards
//
//  A handout from class, kept with the entry it was given in: the text the reader works on, the
//  original file (PDF or photo) for reference, and the words the learner looked up in it. The
//  class twin of `JobPosting`; the reading toolkit is the same, the deck is the course's.
//
//  Every property is defaulted or set in `init` so the entity is an additive migration (the app's
//  container deletes the store when a migration fails).
//

import Foundation
import SwiftData

@Model
final class ClassMaterial {
    var id: UUID
    var createdAt: Date
    var title: String = ""
    /// Raw `SourceKind`.
    var sourceKindRaw: String = "paste"
    /// The handout as text, `[Seite N]` markers stripped, uncapped.
    var text: String = ""
    /// The original in `ClassMaterialStore`: the PDF, or the photo as a JPEG. Nil for pasted text.
    var snapshotFile: String? = nil
    /// Encoded `[GlossaryEntry]`: the words the learner looked up here, newest first.
    var lookupsData: Data? = nil
    /// The tutor that answered the lookups, kept so later lookups don't swap models.
    var modelRaw: String? = nil
    /// The vocab deck (`SavedDeck.id`) whose words are marked in this text and answer a tap
    /// without the model: the teacher's list for this story. Nil until picked (or defaulted).
    var glossaryDeckIDRaw: String? = nil

    var entry: ClassEntry? = nil

    init(title: String, text: String, sourceKind: SourceKind = .paste, createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.title = title
        self.text = text
        self.sourceKindRaw = sourceKind.rawValue
    }

    enum SourceKind: String, CaseIterable {
        case pdf, photo, paste

        var label: String {
            switch self {
            case .pdf:   "PDF file"
            case .photo: "Photo"
            case .paste: "Pasted text"
            }
        }

        var systemImage: String {
            switch self {
            case .pdf:   "doc.richtext"
            case .photo: "camera"
            case .paste: "doc.on.clipboard"
            }
        }
    }

    // MARK: Derived

    var sourceKind: SourceKind { SourceKind(rawValue: sourceKindRaw) ?? .paste }
    var model: MLXModel? { modelRaw.flatMap { MLXModel(rawValue: $0) } }

    var glossaryDeckID: UUID? {
        get { glossaryDeckIDRaw.flatMap { UUID(uuidString: $0) } }
        set { glossaryDeckIDRaw = newValue?.uuidString }
    }

    /// The original is on disk (a failed write can leave a name behind with no file).
    var hasSnapshot: Bool { ClassMaterialStore.exists(snapshotFile) }

    var snapshotURL: URL? {
        guard let snapshotFile, hasSnapshot else { return nil }
        return ClassMaterialStore.url(for: snapshotFile)
    }

    /// Approximate word count, for the list rows.
    var wordCount: Int {
        text.split { $0 == " " || $0 == "\n" }.count
    }

    /// Words looked up while reading this handout, newest first.
    var lookups: [GlossaryEntry] {
        guard let lookupsData else { return [] }
        return (try? JSONDecoder().decode([GlossaryEntry].self, from: lookupsData)) ?? []
    }

    func setLookups(_ entries: [GlossaryEntry]) {
        lookupsData = try? JSONEncoder().encode(entries)
    }

    /// Record a word or phrase the learner looked up. Case-insensitively deduplicated on the German
    /// form, with a repeat lookup moving back to the top.
    func recordLookup(german: String, english: String) {
        let trimmed = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !english.isEmpty else { return }
        var entries = lookups.filter { $0.german.caseInsensitiveCompare(trimmed) != .orderedSame }
        entries.insert(GlossaryEntry(german: trimmed, english: english), at: 0)
        setLookups(entries)
    }
}
