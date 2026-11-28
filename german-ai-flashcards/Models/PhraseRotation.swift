//
//  PhraseRotation.swift
//  german-ai-flashcards
//
//  Which phrases from the learner's phrase library a scenario chat works in, and what starting
//  the chat with them does. Foundation only and shared with the Android app (DieKarteiCore):
//  iOS's `LearnedPhrase` and Android's `LearnedPhraseRecord` both rotate through here.
//

import Foundation

/// What rotation reads of a phrase.
protocol RotatingPhrase {
    var isActive: Bool { get }
    /// `ConversationScenario` raw values.
    var scenarioTagsRaw: [String] { get }
    /// `GrammarFocus` raw values.
    var focusAreasRaw: [String] { get }
    var german: String { get }
    var english: String { get }
    var surfacedCount: Int { get }
    var lastSurfacedAt: Date? { get }
}

extension RotatingPhrase {
    func applies(to scenario: ConversationScenario) -> Bool { scenarioTagsRaw.contains(scenario.rawValue) }
    /// A lightweight value-type copy for carrying into a session config.
    var item: LearnedPhraseItem { LearnedPhraseItem(german: german, english: english) }
}

enum PhraseRotation {
    /// Pick up to `limit` active phrases for `scenario`, preferring least-recently-surfaced ones so
    /// repeated sessions rotate through the library instead of cramming the same few in every time.
    static func sample<P: RotatingPhrase>(for scenario: ConversationScenario, from all: [P], limit: Int = 5) -> [P] {
        let candidates = all.filter { $0.isActive && $0.applies(to: scenario) }
        let sorted = candidates.sorted { a, b in
            // Never-surfaced (nil) first; then oldest surfaced; then fewest surfacings.
            switch (a.lastSurfacedAt, b.lastSurfacedAt) {
            case (nil, nil): return a.surfacedCount < b.surfacedCount
            case (nil, _):   return true
            case (_, nil):   return false
            case let (da?, db?):
                if da != db { return da < db }
                return a.surfacedCount < b.surfacedCount
            }
        }
        return Array(sorted.prefix(max(0, limit)))
    }

    /// The learner confirmed these phrases for the chat: they ride in the config, and the grammar
    /// they carry joins the chat's focus (in `GrammarFocus` order). The caller marks them surfaced.
    static func begin<P: RotatingPhrase>(_ config: inout ConversationConfig, with confirmed: [P]) {
        config.learnedPhrases = confirmed.map(\.item)
        let union = Set(config.focusAreas).union(confirmed.flatMap { $0.focusAreasRaw.compactMap(GrammarFocus.init(rawValue:)) })
        config.focusAreas = GrammarFocus.allCases.filter { union.contains($0) }
    }

    /// Surfacing a phrase advances it in the rotation.
    static func markSurfaced(count: inout Int, last: inout Date?, at date: Date = Date()) {
        count += 1
        last = date
    }
}

extension LearnedPhraseRecord: RotatingPhrase {
    mutating func markSurfaced(at date: Date = Date()) {
        PhraseRotation.markSurfaced(count: &surfacedCount, last: &lastSurfacedAt, at: date)
    }
}
