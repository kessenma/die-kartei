//
//  JournalEntry.swift
//  german-ai-flashcards
//
//  One piece of the learner's own writing in the Schreiben room: a dated Tagebuch page (any
//  language, kept over time) or an Aufsatz written to a prompt. The text is the entry; the
//  handwriting, when there is any, is a file beside it (`JournalInkStore`), and the tutor's check
//  and the coach hand-off are recorded on the row so they survive a relaunch and a sync.
//
//  The prompt an essay was written to is frozen on the entry: the bank can change under it and
//  the essay still reads against the question it answered. The level is copied from the
//  learner's declared level when the entry is made and never written back.
//
//  Every property is defaulted so the entity is an additive migration (the app's container
//  deletes the store when a migration fails). See docs/SCHREIBEN.md.
//

import Foundation
import SwiftData

// MARK: - Kinds

enum JournalKind: String, CaseIterable, Codable, Identifiable {
    /// Free writing, kept as a diary.
    case tagebuch
    /// Writing to a prompt, checked and scored.
    case aufsatz

    var id: String { rawValue }

    var germanLabel: String {
        switch self {
        case .tagebuch: "Tagebuch"
        case .aufsatz: "Aufsatz"
        }
    }

    var englishLabel: String {
        switch self {
        case .tagebuch: "Journal"
        case .aufsatz: "Essay"
        }
    }

    var title: String { "\(germanLabel) · \(englishLabel)" }

    var systemImage: String {
        switch self {
        case .tagebuch: "book.closed"
        case .aufsatz: "doc.text"
        }
    }
}

/// Where an essay's prompt came from.
enum JournalPromptSource: String, Codable {
    case bank, coach, tutor, own
}

// MARK: - The entry

@Model
final class JournalEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    /// Bumped on every save of the text, the ink, the check or the hand-off. Orders the hub.
    var updatedAt: Date = Date()
    /// The day the entry belongs to, local midnight, so "today's entry" is an equality. Travels
    /// as a calendar date, like a class entry's day.
    var day: Date = Calendar.current.startOfDay(for: Date())
    /// `JournalKind` raw value.
    var kindRaw: String = JournalKind.tagebuch.rawValue
    var title: String = ""
    /// The writing itself: typed, or read from the handwriting and confirmed. The check reads
    /// this and nothing else.
    var text: String = ""
    /// `CEFRLevel` raw value, copied from the learner's declared level when the entry is made.
    var levelRaw: String = CEFRLevel.a2.rawValue

    // MARK: Prompt (essays), frozen

    var promptID: String? = nil
    var promptDE: String? = nil
    var promptEN: String? = nil
    /// `JournalPromptSource` raw value.
    var promptSourceRaw: String? = nil
    /// `GrammarFocus` raw value the prompt was written to practise, if any.
    var promptFocusRaw: String? = nil
    var targetMin: Int = 0
    var targetMax: Int = 0

    // MARK: Ink (bytes on disk, never here)

    /// 0 for an entry never written on with the Pencil; else the page's height in points on a
    /// 768-point-wide page. Grows when the learner asks for more room.
    var inkHeight: Int = 0
    /// On the row so a list never has to open the ink file.
    var inkStrokeCount: Int = 0
    /// `PencilPaperStyle` raw value of the paper under the ink.
    var inkPaperRaw: String = "white"
    /// When the handwriting was last read and the transcript confirmed into `text`.
    var transcriptConfirmedAt: Date? = nil

    // MARK: Check

    /// Encoded `WritingCheck`.
    var checkData: Data? = nil
    var checkedAt: Date? = nil
    var checkedModelID: String? = nil
    /// A short hash of the text the check was made on; a mismatch means the check is stale.
    var checkedTextHash: String? = nil

    // MARK: Coach

    /// The last time this entry's slips, words and notes were handed to the coach. Nothing is
    /// sent twice: the hand-off only offers what is newer than this.
    var sharedWithCoachAt: Date? = nil
    /// Encoded `[JournalLookup]`.
    var lookupsData: Data? = nil
    /// Words already credited to the study day, so a reopened entry credits only what was added.
    var creditedWords: Int = 0

    init(kind: JournalKind = .tagebuch, day: Date = .now, level: CEFRLevel = .a2) {
        self.id = UUID()
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
        self.day = Calendar.current.startOfDay(for: day)
        self.kindRaw = kind.rawValue
        self.levelRaw = level.rawValue
    }

    // MARK: Derived

    var kind: JournalKind {
        get { JournalKind(rawValue: kindRaw) ?? .tagebuch }
        set { kindRaw = newValue.rawValue }
    }

    var level: CEFRLevel {
        get { CEFRLevel(rawValue: levelRaw) ?? .a2 }
        set { levelRaw = newValue.rawValue }
    }

    var promptSource: JournalPromptSource? {
        get { promptSourceRaw.flatMap(JournalPromptSource.init(rawValue:)) }
        set { promptSourceRaw = newValue?.rawValue }
    }

    var promptFocus: GrammarFocus? {
        get { promptFocusRaw.flatMap(GrammarFocus.init(rawValue:)) }
        set { promptFocusRaw = newValue?.rawValue }
    }

    var hasPrompt: Bool { !(promptDE ?? "").isEmpty }
    var hasTarget: Bool { targetMax > 0 }
    var hasInk: Bool { inkHeight > 0 && inkStrokeCount > 0 }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var wordCount: Int { WritingSentences.wordCount(text) }

    /// The first line of the text, for a row with no title.
    var firstLine: String {
        text.split(whereSeparator: \.isNewline).first.map {
            String($0).trimmingCharacters(in: .whitespaces)
        } ?? ""
    }

    /// The title, else the prompt, else the first line, else the date.
    var displayTitle: String {
        if !trimmedTitle.isEmpty { return trimmedTitle }
        if let promptDE, !promptDE.isEmpty { return promptDE }
        if !firstLine.isEmpty { return firstLine }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    /// "Mo., 21. Sept." in the device's locale.
    var dateLine: String {
        day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var isEmpty: Bool {
        trimmedTitle.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasInk
    }

    // MARK: Check

    var check: WritingCheck? {
        get {
            guard let checkData else { return nil }
            return try? JSONDecoder().decode(WritingCheck.self, from: checkData)
        }
        set {
            checkData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// True when the text has changed since the last check.
    var checkIsStale: Bool {
        guard let checkedTextHash else { return false }
        return checkedTextHash != WritingCheck.hash(of: text)
    }

    var hasCheck: Bool { checkData != nil }

    // MARK: Lookups

    var lookups: [JournalLookup] {
        get {
            guard let lookupsData else { return [] }
            return (try? JSONDecoder().decode([JournalLookup].self, from: lookupsData)) ?? []
        }
        set {
            lookupsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    func touch() { updatedAt = .now }
}

// MARK: - The check, as stored

/// What the tutor said about one piece of writing, sentence by sentence, with the app's own
/// score beside it. Stored whole on the entry.
struct WritingCheck: Codable, Hashable {
    var sentences: [WritingSentenceCheck]
    /// The tutor's one-sentence comment, or the app's line when the tutor's failed its gate.
    var comment: String?
    /// True when `comment` is the app's own fallback, not the tutor's words.
    var commentIsFallback: Bool = false
    /// Essays only; nil for a Tagebuch entry or a text too short to score.
    var score: WritingScore?
    var modelID: String?
    var checkedAt: Date
    /// When the text had more sentences than one run checks, how many were checked.
    var checkedSentenceLimit: Int?

    var okCount: Int { sentences.filter { $0.outcome == .ok }.count }
    var fixCount: Int { sentences.filter { $0.outcome == .fix }.count }
    var unsureCount: Int { sentences.filter { $0.outcome == .unsure }.count }
    var skippedCount: Int { sentences.filter { $0.outcome == .skipped }.count }

    /// Counts of corrected sentences by category, most frequent first.
    var categoryCounts: [(category: String, count: Int)] {
        var counts: [String: Int] = [:]
        for s in sentences where s.outcome == .fix {
            counts[s.categoryRaw ?? "-", default: 0] += 1
        }
        return counts.map { (category: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.category < $1.category }
    }

    /// A short, stable fingerprint of the text a check was made on. Not cryptographic: it only
    /// has to notice an edit.
    static func hash(of text: String) -> String {
        var h: UInt64 = 1_469_598_103_934_665_603
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 1_099_511_628_211
        }
        return String(h, radix: 16)
    }
}

/// One sentence's verdict.
struct WritingSentenceCheck: Codable, Hashable, Identifiable {
    enum Outcome: String, Codable {
        /// Correct as written.
        case ok
        /// The tutor offered a correction that passed every gate.
        case fix
        /// The tutor was unsure, silent, or its correction failed a gate: "prüfen", never wrong.
        case unsure
        /// Left alone: not German (a Tagebuch entry written in English).
        case skipped
    }

    var index: Int
    var original: String
    var outcome: Outcome
    var corrected: String?
    var reason: String?
    /// A `GrammarFocus` raw value, or one of the check's own extra categories
    /// (`WritingTutorCheck.extraCategories`), or nil.
    var categoryRaw: String?
    /// The learner took the correction into the text.
    var applied: Bool = false

    var id: Int { index }

    var focus: GrammarFocus? { categoryRaw.flatMap(GrammarFocus.init(rawValue:)) }
}

/// The app's score for an essay. Computed from the sentence verdicts and the prompt's target
/// length; the tutor assigns nothing.
struct WritingScore: Codable, Hashable {
    var ok: Int
    var fix: Int
    var unsure: Int
    var skipped: Int
    var words: Int
    var targetMin: Int
    var targetMax: Int

    /// Sentences with a verdict either way.
    var checked: Int { ok + fix }

    /// Too few judged sentences to put a number on.
    static let minimumChecked = 3

    var cleanRatio: Double { checked > 0 ? Double(ok) / Double(checked) : 0 }

    /// 1 inside the target, falling off linearly outside it; 1 when the prompt set no target.
    var lengthScore: Double {
        guard targetMax > 0, targetMax > targetMin else { return 1 }
        if words >= targetMin && words <= targetMax { return 1 }
        let distance = words < targetMin ? targetMin - words : words - targetMax
        return max(0, 1 - Double(distance) / Double(targetMax - targetMin))
    }

    /// 0…100, or nil when fewer than `minimumChecked` sentences were judged. Seven tenths how
    /// clean, three tenths how close to the target length.
    var points: Int? {
        guard checked >= Self.minimumChecked else { return nil }
        return Int((70 * cleanRatio + 30 * lengthScore).rounded())
    }
}

/// A word the learner looked up while writing.
struct JournalLookup: Codable, Hashable, Identifiable {
    var german: String
    var english: String
    var at: Date

    var id: String { german.lowercased() }
}
