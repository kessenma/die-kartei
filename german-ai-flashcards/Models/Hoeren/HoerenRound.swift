//
//  HoerenRound.swift
//  german-ai-flashcards
//
//  One finished round in the Hören room (docs/HOEREN.md): a Zahlen-Diktat set, a Diktat set, or
//  one story's Worum geht's? (predict, listen, summarise, compare). One model for all three, so
//  stats, the day detail and sync each have one place to read. Each round keeps its items, which
//  is what the stats screen and its confusion pairs are computed from; nothing else is stored.
//
//  Additive, with every field defaulted: the store recreates itself when a migration fails, so a
//  new model must never be the thing that makes one fail. Synced append-only by `HoerenRoundCodec`.
//

import Foundation
import SwiftData

nonisolated enum HoerenRoundKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case zahlen
    case diktat
    case gist

    var id: String { rawValue }

    var germanLabel: String {
        switch self {
        case .zahlen: "Zahlen-Diktat"
        case .diktat: "Diktat"
        case .gist:   "Worum geht's?"
        }
    }

    var englishLabel: String {
        switch self {
        case .zahlen: "Numbers, heard once"
        case .diktat: "Write what you hear"
        case .gist:   "The gist in your own words"
        }
    }

    var systemImage: String {
        switch self {
        case .zahlen: "number.circle"
        case .diktat: "text.cursor"
        case .gist:   "text.bubble"
        }
    }
}

/// Study mode lets the learner pause, replay and slow down (all counted). Single pass plays once.
nonisolated enum HoerenPlayback: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case singlePass
    case study

    var id: String { rawValue }

    var label: String {
        switch self {
        case .singlePass: "Single pass"
        case .study:      "Study mode"
        }
    }

    var detail: String {
        switch self {
        case .singlePass: "Heard once, as in the DLI test. A replay is allowed and counted."
        case .study:      "Replay and slow down as often as you like. Each one is counted."
        }
    }
}

/// One item of a round. Fields that belong to one kind are optional, so a round of any kind
/// decodes the same way and older rounds survive new fields.
nonisolated struct HoerenItem: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    /// The expected answer as shown: a number's written form, the dictated sentence, a story title.
    var expected: String
    /// What the voice read.
    var spoken: String
    /// What the learner typed.
    var typed: String = ""
    var correct: Bool = false
    var replays: Int = 0
    var slow: Bool = false

    // Zahlen-Diktat
    var numberKindRaw: String? = nil
    var numberValue: HoerenNumberValue? = nil
    var typedValue: HoerenNumberValue? = nil
    var confusionRaw: String? = nil

    // Diktat
    var diktat: DiktatResult? = nil
    var sentenceSourceRaw: String? = nil
    var headword: String? = nil
    var headwordEnglish: String? = nil

    // Worum geht's?
    var predictions: [String]? = nil
    var predictionHits: [String]? = nil
    var summary: String? = nil
    var keyPoints: [String]? = nil
    /// Per key point: 0 nein, 1 teilweise, 2 ja (self-checked).
    var selfTicks: [Int]? = nil
    var revealedEarly: Bool? = nil

    var numberKind: HoerenNumberKind? { numberKindRaw.flatMap(HoerenNumberKind.init(rawValue:)) }
    var confusion: HoerenConfusion? { confusionRaw.flatMap(HoerenConfusion.init(rawValue:)) }
    /// Heard on the first play, with no replay.
    var firstPass: Bool { correct && replays == 0 }
}

@Model
final class HoerenRound {
    var date: Date = Date()
    /// A UUID string; the sync key.
    var roundKey: String = ""
    /// A `HoerenRoundKind` raw value.
    var kindRaw: String = ""
    /// Zahlen: a `HoerenNumberMode` raw value. Diktat and gist: empty.
    var modeRaw: String = ""
    /// A `HoerenPlayback` raw value.
    var playbackRaw: String = ""
    /// A `CEFRLevel` raw value.
    var levelRaw: String = ""
    /// Where the items came from: "vocab,perfekt,kasus", "course:<id>", "story:<id>", or the
    /// Zahlen kinds joined by commas.
    var sourceRaw: String = ""
    var askedCount: Int = 0
    /// Zahlen: numbers right. Diktat: sentences with every word right. Gist: points ticked ja,
    /// counting teilweise as half, times two (so it stays an integer).
    var correctCount: Int = 0
    /// Items right with no replay.
    var firstPassCount: Int = 0
    var replayCount: Int = 0
    var durationSeconds: Int = 0
    /// Encoded `[HoerenItem]`, in order.
    var itemsData: Data? = nil

    init(kind: HoerenRoundKind, date: Date = Date(), roundKey: String = UUID().uuidString) {
        self.kindRaw = kind.rawValue
        self.date = date
        self.roundKey = roundKey
    }

    var kind: HoerenRoundKind? { HoerenRoundKind(rawValue: kindRaw) }
    var level: CEFRLevel? { CEFRLevel(rawValue: levelRaw) }
    var playback: HoerenPlayback? { HoerenPlayback(rawValue: playbackRaw) }

    var items: [HoerenItem] {
        get { itemsData.flatMap { try? JSONDecoder().decode([HoerenItem].self, from: $0) } ?? [] }
        set { itemsData = try? JSONEncoder().encode(newValue) }
    }

    /// One line for the day detail and Verlauf.
    var summaryLine: String {
        var parts: [String] = []
        switch kind {
        case .gist:
            let points = items.first?.keyPoints?.count ?? 0
            if points > 0 {
                parts.append("\(HoerenStats.halfString(correctCount)) of \(points) points (self-checked)")
            } else {
                parts.append("Summary written")
            }
        case .diktat:
            let words = items.compactMap(\.diktat).reduce(0) { $0 + $1.referenceCount }
            let right = items.compactMap(\.diktat).reduce(0) { $0 + $1.rightCount }
            parts.append("\(askedCount) sentences")
            if words > 0 { parts.append("\(Int((Double(right) / Double(words) * 100).rounded()))% of words") }
        default:
            parts.append("\(correctCount)/\(askedCount) right")
            if firstPassCount < correctCount { parts.append("\(firstPassCount) first pass") }
        }
        if replayCount > 0 { parts.append("\(replayCount) replay\(replayCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
