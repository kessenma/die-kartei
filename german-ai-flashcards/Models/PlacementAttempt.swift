//
//  PlacementAttempt.swift
//  german-ai-flashcards
//
//  The recorded history of the placement probe: one `PlacementAttempt` per finished run, holding
//  the estimate it produced *and* every question that produced it.
//
//  Why these types exist alongside `PlacementItem` / `PlacementAnswer` rather than as conformances
//  on them: those two are the **scorer's** language — choice *indices*, a runtime `let id = UUID()`,
//  an enum whose cases mirror the adaptive staircase. Freezing that shape on disk would mean a new
//  `Kind` case or an edit to `placement_grammar.json` could stop old history decoding, and Codable
//  synthesis on that `id` would mint a fresh UUID on every decode (the store decodes on access, so
//  `ForEach` would churn identities every render). These types are instead a **historical** record:
//  flat, self-contained, and readable years later with the bank long since re-authored.
//
//  Nothing here ever reaches a prompt or the pyramid. It is what the learner sees on the review
//  screen, what the JSON export writes, and the source the coach hand-off reads — see
//  `PlacementCoachExport` for why that hand-off deliberately routes around `LearnerProfile.grammar`.
//

import Foundation

// MARK: - One question

/// One recorded question from a finished run.
struct PlacementRecord: Codable, Hashable {

    /// Which block of the probe asked this. Mirrors `PlacementItem.Kind` without its payloads —
    /// the payloads are flattened into the fields below so the shape can't drift with the enum.
    enum Block: String, Codable, CaseIterable, Identifiable {
        case vocab
        case gender
        case preposition
        case grammar
        case cloze

        var id: String { rawValue }

        var label: String {
            switch self {
            case .vocab:       "Words"
            case .gender:      "der · die · das"
            case .preposition: "Cases"
            case .grammar:     "Grammar"
            case .cloze:       "Cloze"
            }
        }

        var systemImage: String {
            switch self {
            case .vocab:       "text.book.closed"
            case .gender:      "a.circle"
            case .preposition: "arrow.triangle.branch"
            case .grammar:     "textformat.abc"
            case .cloze:       "text.insert"
            }
        }
    }

    var block: Block
    /// `GoetheLevel.rawValue` for vocabulary, `CEFRLevel.rawValue` for grammar and cloze. Nil for
    /// gender and prepositions: neither `Kind` case carries a level, and giving `.gender` one would
    /// mean editing the measurement path to serve a filter facet.
    var levelRaw: String?
    /// Bank construct id (`"perfekt-aux"`), for grammar and cloze only.
    var construct: String?
    /// Which gap of the cloze paragraph this was.
    var gap: Int?
    /// One of the two fixed A2 anchors — asked every single run, so these dominate any
    /// "missed most often" ranking. Worth being able to tell apart.
    var isAnchor: Bool = false

    var prompt: String
    var subtitle: String?
    /// Surrounding text the prompt can't carry alone. Today only the cloze finale, rendered with
    /// *this* gap blanked and the others filled in — a paragraph title plus three orphaned options
    /// doesn't read back as a question.
    var context: String?
    var choices: [String]
    var correctIndex: Int
    /// Nil = skipped. Scores as wrong, stays distinguishable — same contract as `PlacementAnswer`.
    var chosenIndex: Int?
    /// Bank id: the grammar item, or the cloze paragraph. The only handle back to the authored
    /// `english` / `why` explanations, which are looked up live rather than stored.
    var sourceID: String?

    var isCorrect: Bool { chosenIndex == correctIndex }
    var wasSkipped: Bool { chosenIndex == nil }

    var correctChoice: String { choices.indices.contains(correctIndex) ? choices[correctIndex] : "" }
    var chosenChoice: String? { chosenIndex.flatMap { choices.indices.contains($0) ? choices[$0] : nil } }

    /// Identity of the *question*, stable across runs and across the per-run option reshuffle — the
    /// key behind "missed N times". Mirrors the two keys `PlacementSession` already dedupes on: the
    /// bank id for grammar and cloze (`usedGrammarIDs`), the word itself for the rest (`usedWords`,
    /// which is `prompt.lowercased()`). The block tag is required because the same noun can be a
    /// vocabulary item in one run and a gender item in the next.
    var questionKey: String {
        switch block {
        case .grammar: "grammar:\(sourceID ?? prompt.lowercased())"
        case .cloze:   "cloze:\(sourceID ?? "?")#\(gap ?? 0)"
        default:       "\(block.rawValue):\(prompt.lowercased())"
        }
    }

    /// The `CEFRLevel` this record counts as evidence at, where it has one.
    var cefrLevel: CEFRLevel? { levelRaw.flatMap(CEFRLevel.init(rawValue:)) }

    /// Flattens one live answer. `context` is supplied by the recorder, which is the only place
    /// that still has the cloze paragraph to rebuild it from.
    init(_ answer: PlacementAnswer, context: String? = nil) {
        let item = answer.item
        self.prompt = item.prompt
        self.subtitle = item.subtitle
        self.context = context
        self.choices = item.choices
        self.correctIndex = item.correctIndex
        self.chosenIndex = answer.chosenIndex
        self.sourceID = item.sourceID

        switch item.kind {
        case .vocab(let level):
            block = .vocab
            levelRaw = level.rawValue
        case .gender:
            block = .gender
        case .preposition:
            block = .preposition
        case .grammar(let level, let construct, let isAnchor):
            block = .grammar
            levelRaw = level.rawValue
            self.construct = construct
            self.isAnchor = isAnchor
        case .cloze(let level, let construct, let gap):
            block = .cloze
            levelRaw = level.rawValue
            self.construct = construct
            self.gap = gap
        }
    }
}

// MARK: - One run

/// One finished run of the probe: the estimate it produced, plus every question that produced it.
struct PlacementAttempt: Codable, Identifiable, Hashable {
    var id: UUID
    var result: PlacementResult
    var records: [PlacementRecord]
    /// `PlacementGrammarFile.version` at the time of the run, so a failed explanation lookup can
    /// say *why* it failed instead of rendering a blank row.
    var bankVersion: Int
    var appVersion: String?

    /// The single source of truth for the timeline — deliberately not a second stored date, which
    /// could drift from the one the pyramid reads.
    var takenAt: Date { result.takenAt }

    var correctCount: Int { records.filter(\.isCorrect).count }
    var skippedCount: Int { records.filter(\.wasSkipped).count }
    /// The "I'm starting from zero" door: a real, dated attempt that asked nothing.
    var isBeginnerDeclaration: Bool { result.declaredBeginner && records.isEmpty }

    init(
        id: UUID = UUID(),
        result: PlacementResult,
        records: [PlacementRecord],
        bankVersion: Int,
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    ) {
        self.id = id
        self.result = result
        self.records = records
        self.bankVersion = bankVersion
        self.appVersion = appVersion
    }
}

// MARK: - Review row

/// One row of the review list: a record plus which attempt it came from.
///
/// `PlacementRecord` is deliberately *not* `Identifiable` — `questionKey` repeats across attempts
/// on purpose (that repetition is the "missed N times" feature), so keying a flattened `ForEach`
/// on it would collide. Identity belongs here instead, where the attempt disambiguates it.
struct PlacementReviewItem: Identifiable, Hashable {
    let attemptID: UUID
    let attemptAt: Date
    /// Position within its attempt, in ask-order.
    let index: Int
    let record: PlacementRecord

    var id: String { "\(attemptID.uuidString)#\(index)" }
}
