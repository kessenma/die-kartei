//
//  PlacementResult.swift
//  german-ai-flashcards
//
//  The value types behind the optional intro placement probe — the app's one chance to learn what
//  a new learner already knows before they've done anything here.
//
//  Why this exists: every mastery signal the pyramid reads is longitudinal (three weeks of SRS
//  spacing, three clean game rounds, a drilled grammar focus). Those measure *time in the app*, so
//  without a probe a B2 speaker and an absolute beginner both start at zero and stay there for
//  weeks. The probe supplies a second, instant evidence source.
//
//  What it is NOT: proof. A `PlacementResult` only ever feeds the pyramid's *provisional* channel
//  (see `PyramidLayerState`), never `LearnerProfile` — the coach's briefing has to stay
//  measured-in-app-only, or an estimate would launder itself into the record the AI trusts.
//
//  Stored as a Codable blob in UserDefaults, never SwiftData: the app's store deletes and recreates
//  itself on migration failure, so gamification data stays out of the schema (docs/GAMIFICATION.md).
//

import Foundation

// MARK: - Result

/// What a finished probe concluded. Every accuracy is 0…1.
struct PlacementResult: Codable, Equatable, Hashable {
    var takenAt: Date
    /// `CEFRLevel.rawValue`. Vocabulary evidence caps at B1 — the bundled Goethe lists stop there —
    /// but the estimate itself can read B2 when held B1 vocabulary meets held B2 grammar plus a
    /// confirmed cloze. `vocabKnown` never gains a B2 key; a B2 reading is grammar evidence only.
    var estimatedLevelRaw: String
    /// `GoetheLevel.rawValue` → the fraction of that word list the learner appears to know.
    var vocabKnown: [String: Double]
    /// der/die/das accuracy across the sampled nouns.
    var articleAccuracy: Double
    /// Accuracy at naming the case a preposition governs.
    var prepositionAccuracy: Double
    /// Placement-bank construct id (e.g. `"perfekt-aux"`) → accuracy, only for constructs the probe
    /// actually tested. Absent means "not asked", which is different from "got it wrong" and must
    /// stay distinguishable. (Keys were `GrammarFocus` raw values before the authored bank; no
    /// consumer reads them semantically, so old blobs stay decodable.)
    var grammarAccuracy: [String: Double]
    var itemsAnswered: Int
    /// Took the "I'm starting from zero" door instead of answering. Credits nothing, and is not a
    /// failure state: it's the honest answer for a true beginner and skips a pointless quiz.
    var declaredBeginner: Bool

    /// Highest grammar-staircase level held (raw ≥ pass rate over ≥2 items), `CEFRLevel.rawValue`.
    /// Optional so results stored before the staircase existed keep decoding.
    var grammarLevelRaw: String?
    /// The level the cloze finale tested, and how many of its gaps were right. Both nil when the
    /// run ended before the finale (or predates it).
    var clozeLevelRaw: String?
    var clozeCorrect: Int?

    var estimatedLevel: CEFRLevel { CEFRLevel(rawValue: estimatedLevelRaw) ?? .a1 }
    var grammarLevel: CEFRLevel? { grammarLevelRaw.flatMap(CEFRLevel.init(rawValue:)) }

    func vocabKnown(_ level: GoetheLevel) -> Double { vocabKnown[level.rawValue] ?? 0 }

    /// Accuracy for a construct, or nil when the probe never asked about it.
    func accuracy(construct: String) -> Double? { grammarAccuracy[construct] }

    /// The result recorded when someone says they're starting from scratch: an A1 estimate that
    /// credits nothing, so the pyramid stays honestly empty and fills only from real work.
    static func beginner(at date: Date = Date()) -> PlacementResult {
        PlacementResult(
            takenAt: date,
            estimatedLevelRaw: CEFRLevel.a1.rawValue,
            vocabKnown: [:],
            articleAccuracy: 0,
            prepositionAccuracy: 0,
            grammarAccuracy: [:],
            itemsAnswered: 0,
            declaredBeginner: true
        )
    }
}

// MARK: - Items

/// One question in the probe. Deliberately plain data: the quiz UI renders these, and the scorer
/// reads the answers back, so neither needs to know how the other works.
struct PlacementItem: Identifiable {
    enum Kind: Equatable {
        /// Meaning of a word drawn from that level's Goethe list.
        case vocab(GoetheLevel)
        /// der/die/das for a noun.
        case gender
        /// Which case a preposition governs.
        case preposition
        /// An authored single-gap item from the placement grammar bank. Anchors are the two fixed
        /// A2 items that pick the staircase's starting level; they still count as A2 evidence.
        case grammar(level: CEFRLevel, construct: String, isAnchor: Bool)
        /// One gap of the cloze finale — three of these are recorded per paragraph.
        case cloze(level: CEFRLevel, construct: String, gap: Int)
    }

    let id = UUID()
    let kind: Kind
    /// The thing being asked about — a German word, or a sentence with a blank.
    let prompt: String
    /// Optional supporting line (a gloss or example), shown smaller.
    let subtitle: String?
    let choices: [String]
    let correctIndex: Int
    /// The bank id behind a grammar/cloze item, so the session can dedupe against the bank rather
    /// than against prompts. Nil for vocab/gender/preposition, whose dedupe key is the word itself.
    var sourceID: String? = nil

    var correctChoice: String { choices[correctIndex] }
}

// MARK: - Cloze prompt

/// The cloze finale as the UI renders it: the paragraph split around its gaps, each gap carrying
/// pre-shuffled options. Built once by `PlacementService.clozePrompt(level:)` so shuffling can't
/// differ between what's shown and what's scored.
struct PlacementClozePrompt: Identifiable {
    struct Gap {
        let construct: String
        let choices: [String]
        let correctIndex: Int
    }

    let id: String
    let level: CEFRLevel
    let title: String
    /// Text pieces between gaps: `segments[i]` precedes `gaps[i]`; the last segment closes the text.
    /// Always `gaps.count + 1` entries (empty strings where a gap starts or ends the paragraph).
    let segments: [String]
    let gaps: [Gap]
}

/// A given answer. `chosenIndex == nil` means skipped, which scores as wrong but is tracked
/// separately so a rushed probe can be told apart from a failed one.
struct PlacementAnswer {
    let item: PlacementItem
    let chosenIndex: Int?

    var isCorrect: Bool { chosenIndex == item.correctIndex }
    var wasSkipped: Bool { chosenIndex == nil }
}
