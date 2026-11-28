//
//  WortschatzPrefs.swift
//  german-ai-flashcards
//
//  The Wortschatz box's settings and how a session is put together, in one Foundation-only file
//  the Android app compiles too (DieKarteiCore), so both apps read the same keys and defaults and
//  pick a session's cards the same way.
//

import Foundation

/// Settings of the Wortschatz (Goethe) box.
nonisolated enum WortschatzPrefs {
    /// New words introduced per day before the box asks whether you want more.
    static let newPerDayKey = "wortschatz.newPerDay"
    static let newPerDayDefault = 15
    static let newPerDayOptions = [5, 10, 15, 20, 30, 50]

    /// Cards per session: due reviews first, then new words up to the budget.
    static let sessionCapKey = "wortschatz.sessionCap"
    static let sessionCapDefault = 40
    static let sessionCapOptions = [20, 40, 60, 100]

    /// The scheduler the box studies with — Anki or Leitner, never plain flip.
    static let styleKey = "wortschatz.style"

    /// How many new words the "Learn more" button adds to today's budget.
    static let bonusStep = 10

    static func newPerDay(_ defaults: UserDefaults = SharedDefaults.store) -> Int {
        let stored = defaults.integer(forKey: newPerDayKey)
        return stored > 0 ? stored : newPerDayDefault
    }

    static func sessionCap(_ defaults: UserDefaults = SharedDefaults.store) -> Int {
        let stored = defaults.integer(forKey: sessionCapKey)
        return stored > 0 ? stored : sessionCapDefault
    }

    static func style(_ defaults: UserDefaults = SharedDefaults.store) -> FlashcardStyle {
        guard let raw = defaults.string(forKey: styleKey), let style = FlashcardStyle(rawValue: raw),
              style != .default else { return .anki }
        return style
    }
}

/// Which cards a Wortschatz session holds, the same on iOS (`DeckStore.wortschatzSession`) and
/// Android (`StudyStore.session`): every due card, shuffled, up to the session cap, then new words
/// in list order, as many as today's budget and the room left under the cap allow.
nonisolated enum WortschatzSessionPlan {
    /// - Parameters:
    ///   - due: the cards due now.
    ///   - fresh: never-rated cards in their list order (`sortOrder`).
    ///   - newBudget: new words still allowed today.
    static func choose<Card>(due: [Card], fresh: [Card], newBudget: Int, sessionCap: Int,
                             shuffle: ([Card]) -> [Card] = { $0.shuffled() }) -> (due: [Card], fresh: [Card]) {
        let cap = max(1, sessionCap)
        let dueChosen = Array(shuffle(due).prefix(cap))
        let newAllowed = max(0, min(newBudget, cap - dueChosen.count))
        return (dueChosen, Array(fresh.prefix(newAllowed)))
    }
}
