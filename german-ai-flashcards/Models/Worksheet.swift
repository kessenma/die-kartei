//
//  Worksheet.swift
//  german-ai-flashcards
//
//  A handout's homework: which of its pages the learner is working, how (answering in the app or
//  writing on the slide), and what they answered. Stored on the `ClassMaterial` as two JSON blobs
//  (`worksheetData`, `worksheetAnswersData`) rather than as entities of their own, so a handout and
//  its homework travel as one record. The ink is not here: one PencilKit drawing per page lives in
//  a file beside the PDF (`WorksheetInkStore`). See docs/WORKSHEETS.md.
//
//  What is parsed is never stored — a page is parsed again whenever it is shown (see
//  `WorksheetParser`) — only the learner's choices and answers, keyed by what the sheet prints.
//

import Foundation

/// The homework set up on one handout.
nonisolated struct WorksheetSetup: Codable, Hashable, Sendable {
    /// `WorksheetParser.version` when the pages were picked. A later version re-keys answers by
    /// each item's anchor text instead of trusting the keys.
    var parserVersion: Int
    var pages: [WorksheetPagePlan]
    var status: Status = .working
    var createdAt: Date = .now
    /// When the learner said it went to the teacher.
    var sentAt: Date?
    /// The teacher's answers, by answer key, read from her "Lösungen" pages
    /// (`WorksheetKeyReader`). The check uses it first. Empty, not nil, once the PDF was read and
    /// had none, so it isn't read again on every open.
    var key: [String: String]?
    /// Her example answers ("Mögliche Übersetzungen", "Beispiele"), and the answers of an exercise
    /// whose key only partly fitted the parsed page. Shown and handed to the tutor; never grades.
    /// Optional, so setups written before it decode.
    var samples: [String: String]?

    enum Status: String, Codable, Sendable {
        case working, sent
    }

    var answerPages: [WorksheetPagePlan] { pages.filter { $0.mode == .answer } }
}

nonisolated struct WorksheetPagePlan: Codable, Hashable, Sendable, Identifiable {
    /// 1-based, as the teacher numbers her slides.
    var page: Int
    var mode: Mode
    var title: String
    /// Each item's anchor text (`WorksheetItem.anchor`) by its key, so answers can be re-keyed
    /// if a later parser numbers the page differently.
    var anchors: [String: String] = [:]
    /// Paper added around the slide on the Pencil canvas for the learner's own notes and questions.
    /// Optional, so plans written before it decode (and an older app's re-encode drops it, nothing
    /// worse). The notes stay in the app: the export is her slide.
    var notes: WorksheetNotesMargins?

    var id: Int { page }

    enum Mode: String, Codable, Sendable {
        /// Gaps, chips and choices in the app; ink on top is still possible.
        case answer
        /// The slide itself, written on with the Pencil.
        case pencil
    }
}

/// Which sides of a slide get extra paper to write notes on, each a fixed share of the slide:
/// left and right 60% of its width, top and bottom 60% of its height.
nonisolated struct WorksheetNotesMargins: Codable, Hashable, Sendable {
    var left = false
    var right = false
    var top = false
    var bottom = false

    static let share: CGFloat = 0.6

    var isEmpty: Bool { !(left || right || top || bottom) }

    /// The paper added on each side of a slide of `size`, in its points.
    func insets(for size: CGSize) -> (top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        (top ? size.height * Self.share : 0, left ? size.width * Self.share : 0,
         bottom ? size.height * Self.share : 0, right ? size.width * Self.share : 0)
    }
}

/// What the learner gave for one answer key: a gap, a choice, a write-below line, or an item's
/// marked words.
nonisolated struct WorksheetAnswer: Codable, Hashable, Sendable {
    var text: String?
    /// Index into the choice's options.
    var choice: Int?
    /// Indexes into the item's `words`.
    var marks: [Int]?
    /// Raw `GrammarCase`, for "Notiere den Fall".
    var caseTag: String?
    /// Where the text came from: typed (or Scribbled) in the app, or read from ink and confirmed.
    var source: Source?
    /// The optional check, made for the answer as it stood (`check.answer`).
    var check: WorksheetCheck?
    /// Last edit. Answers merge per key across devices, the later edit winning
    /// (`ClassMaterialCodec`: `.keyed(item: .lwwBy("at"))`).
    var at: Date = .now

    enum Source: String, Codable, Sendable { case typed, ink }

    var isEmpty: Bool {
        (text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && choice == nil && (marks?.isEmpty ?? true) && caseTag == nil
    }

    var kasus: GrammarCase? { caseTag.flatMap(GrammarCase.init(rawValue:)) }
}

/// The app's opinion of one answer. Never part of what goes to the teacher.
nonisolated struct WorksheetCheck: Codable, Hashable, Sendable {
    var outcome: Outcome
    /// The form the checker expected, when it has one.
    var correction: String?
    /// One line on why.
    var reason: String?
    var by: Checker
    /// The answer this was made for; an edit since makes the check stale.
    var answer: String

    enum Outcome: String, Codable, Sendable {
        case right
        /// The checker wasn't sure, or couldn't tell. Shown as "prüfen", never as wrong.
        case unsure
        case wrong
    }

    enum Checker: String, Codable, Sendable {
        /// The teacher's own answer key.
        case key
        /// The app's article rules: preposition → case, gender from the sheet's "Nomen:" line.
        case rules
        /// The downloaded tutor model.
        case tutor
    }
}

// MARK: - Coding

nonisolated enum WorksheetCoding {
    static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
