//
//  JobPosting.swift
//  german-ai-flashcards
//
//  A job description the learner studies the way a tutor would read it with them: line by line,
//  translating the words they don't know. The posting is its own entity, separate from the
//  interview chats, because studying an ad and rehearsing for it are different sessions that
//  happen to share a document. Interview chats point back here through
//  `ChatConversation.jobPostingIDRaw`, so the two can be grouped per posting later.
//
//  Every property is defaulted or set in `init` so the entity is an additive migration (the app's
//  container deletes the store when a migration fails).
//

import Foundation
import SwiftData

@Model
final class JobPosting {
    var id: UUID
    var createdAt: Date
    /// Bumped on every lookup, save, or edit so the hub lists the posting being worked on first.
    var updatedAt: Date
    var title: String
    var company: String? = nil
    var location: String? = nil
    /// The page the posting was brought over from, when it came from a link or a chat that had one.
    var sourceURL: String? = nil
    /// Raw `SourceKind`.
    var sourceKindRaw: String = "paste"
    /// The full posting, uncapped: the study text, not the recruiter's context window.
    var text: String
    /// This posting's own PDF copy in `JobPostingSnapshotStore`; nil for pasted text.
    var snapshotFile: String? = nil
    /// Encoded `[GlossaryEntry]` — the words the learner looked up here, newest first.
    var lookupsData: Data? = nil
    /// Linked deck of words saved while reading (`SavedDeck.id`), created on first save.
    var deckIDRaw: String? = nil
    /// The tutor that answered the lookups, kept so later lookups don't swap models.
    var modelRaw: String? = nil
    /// Wall-clock seconds spent on the reading screen.
    var readingSeconds: Int = 0
    var lastOpenedAt: Date? = nil
    /// The interview chat this posting was adopted from, if any (`ChatConversation.id`).
    var adoptedFromChatIDRaw: String? = nil

    init(title: String, text: String, sourceKind: SourceKind = .paste, createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.title = title
        self.text = text
        self.sourceKindRaw = sourceKind.rawValue
    }

    enum SourceKind: String, CaseIterable {
        case link, pdf, paste, chat

        var label: String {
            switch self {
            case .link:  "From a link"
            case .pdf:   "PDF file"
            case .paste: "Pasted text"
            case .chat:  "From an interview"
            }
        }

        var systemImage: String {
            switch self {
            case .link:  "safari"
            case .pdf:   "doc.richtext"
            case .paste: "doc.on.clipboard"
            case .chat:  "bubble.left.and.bubble.right"
            }
        }
    }

    // MARK: Derived

    var sourceKind: SourceKind { SourceKind(rawValue: sourceKindRaw) ?? .paste }
    var model: MLXModel? { modelRaw.flatMap { MLXModel(rawValue: $0) } }

    var deckID: UUID? {
        get { deckIDRaw.flatMap { UUID(uuidString: $0) } }
        set { deckIDRaw = newValue?.uuidString }
    }

    var adoptedFromChatID: UUID? { adoptedFromChatIDRaw.flatMap { UUID(uuidString: $0) } }

    /// The PDF copy is on disk (a failed write can leave a name behind with no file).
    var hasSnapshot: Bool { JobPostingSnapshotStore.exists(snapshotFile) }

    /// A non-empty page link, or nil.
    var pageURL: URL? {
        guard let sourceURL, !sourceURL.isEmpty else { return nil }
        return URL(string: sourceURL)
    }

    /// "Company · Location", whichever parts are filled in.
    var detailLine: String {
        [company, location]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// Approximate word count, for the list rows.
    var wordCount: Int {
        text.split { $0 == " " || $0 == "\n" }.count
    }

    /// Words looked up while reading this posting, newest first.
    var lookups: [GlossaryEntry] {
        guard let lookupsData else { return [] }
        return (try? JSONDecoder().decode([GlossaryEntry].self, from: lookupsData)) ?? []
    }

    func setLookups(_ entries: [GlossaryEntry]) {
        lookupsData = try? JSONEncoder().encode(entries)
        updatedAt = .now
    }

    /// Record a word or phrase the learner looked up. Case-insensitively deduplicated on the German
    /// form, with a repeat lookup moving back to the top — "what I needed help with here", not a tally.
    func recordLookup(german: String, english: String) {
        let trimmed = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !english.isEmpty else { return }
        var entries = lookups.filter { $0.german.caseInsensitiveCompare(trimmed) != .orderedSame }
        entries.insert(GlossaryEntry(german: trimmed, english: english), at: 0)
        setLookups(entries)
    }

    /// The reading surfaces this posting can offer: the text always, the PDF when a copy was
    /// saved, the live page when there is a link to load.
    var availableSurfaces: [JobReadingSurfaceKind] {
        var kinds: [JobReadingSurfaceKind] = [.text]
        if hasSnapshot { kinds.append(.pdf) }
        if pageURL != nil { kinds.append(.web) }
        return kinds
    }

    /// Strip the `[Seite N]` page markers `PDFTextExtractor` inserts, and collapse runs of blank
    /// lines, so extracted PDF text reads as paragraphs.
    static func cleanedText(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\n?\[Seite \d+\]\n?"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
