//
//  KasusRound.swift
//  german-ai-flashcards
//
//  One scored step on the Grammatik path: a story's Finden or Einsetzen, or a unit's Schnellrunde.
//  Written by `KasusService.recordRound`, read by the day detail in the streak calendar, the story
//  rows' step marks and the hub's "Weiter" pick (`KasusPath.next`).
//
//  Everything keys on (storyID, unitRaw, stepRaw), never on a display string, so a retitled story
//  keeps its history. A Schnellrunde has no story; it is filed under "quick-<unit>".
//
//  Additive, with every field defaulted: the store recreates itself when a migration fails, so a
//  new model must never be the thing that makes one fail.
//

import Foundation
import SwiftData

/// Which exercise a `KasusRound` records.
nonisolated enum KasusRoundStep: String, Codable, CaseIterable {
    /// Finden: mark the cases in the story. Counts for the streak only.
    case find
    /// Einsetzen: fill in the articles.
    case fill
    /// Schnellrunde: the endings drill for one unit.
    case quick

    var germanLabel: String {
        switch self {
        case .find:  "Finden"
        case .fill:  "Einsetzen"
        case .quick: "Schnellrunde"
        }
    }
}

@Model
final class KasusRound {
    var date: Date = Date()
    /// The story's id, or "quick-<unit>" for a Schnellrunde (`KasusService.quickRoundID(for:)`).
    var storyID: String = ""
    /// A `KasusUnit` raw value.
    var unitRaw: String = ""
    /// A `KasusRoundStep` raw value: find · fill · quick.
    var stepRaw: String = ""
    /// A `KasusHintLevel` raw value for Einsetzen; empty for Finden and the Schnellrunde.
    var hintLevelRaw: String = ""
    var askedCount: Int = 0
    var firstTryCount: Int = 0
    var durationSeconds: Int = 0
    /// Encoded `[String: CaseTally]`, keyed by `GrammarCase` raw value.
    var perCaseData: Data?

    init(
        storyID: String,
        unitRaw: String,
        stepRaw: String,
        hintLevelRaw: String = "",
        askedCount: Int,
        firstTryCount: Int,
        durationSeconds: Int,
        perCase: [GrammarCase: CaseTally] = [:],
        date: Date = Date()
    ) {
        self.date = date
        self.storyID = storyID
        self.unitRaw = unitRaw
        self.stepRaw = stepRaw
        self.hintLevelRaw = hintLevelRaw
        self.askedCount = askedCount
        self.firstTryCount = firstTryCount
        self.durationSeconds = durationSeconds
        self.perCase = perCase
    }

    /// One case's share of the round.
    nonisolated struct CaseTally: Codable, Hashable {
        var asked: Int = 0
        var firstTry: Int = 0
    }

    var unit: KasusUnit? { KasusUnit(rawValue: unitRaw) }
    var step: KasusRoundStep? { KasusRoundStep(rawValue: stepRaw) }
    var hintLevel: KasusHintLevel? { KasusHintLevel(rawValue: hintLevelRaw) }
    var isQuickRound: Bool { step == .quick }

    var perCase: [GrammarCase: CaseTally] {
        get {
            guard let perCaseData,
                  let raw = try? JSONDecoder().decode([String: CaseTally].self, from: perCaseData)
            else { return [:] }
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, tally in
                GrammarCase(rawValue: key).map { ($0, tally) }
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            perCaseData = try? JSONEncoder().encode(raw)
        }
    }
}
