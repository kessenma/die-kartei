//
//  CardStudyPrefs.swift
//  german-ai-flashcards
//
//  The UserDefaults keys behind the card-study settings that several screens share — the player,
//  Settings ▸ Cards, and the Wortschatz hub all bind to the same keys through `@AppStorage`, so a
//  change made in any of them shows up in the others without plumbing.
//

import Foundation

/// Settings that apply to every flashcard session.
enum CardStudyPrefs {
    /// Which side a card shows first. German by default; the player's own picker writes it too.
    static let germanFirstKey = "cards.germanFirst"
    /// Hide a noun's article on the German side until the flip, so every noun is a gender check.
    static let articleQuizKey = "cards.articleQuiz"
    /// A card rated Again comes back a few cards later in the same session.
    static let repeatMissedKey = "cards.repeatMissed"
    /// Deal the cards in a fresh random order every time a session starts (off: the deck's order).
    static let shuffleKey = "cards.shuffle"

    static func germanFirst(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: germanFirstKey) == nil ? true : defaults.bool(forKey: germanFirstKey)
    }

    static func articleQuiz(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: articleQuizKey) == nil ? true : defaults.bool(forKey: articleQuizKey)
    }

    static func repeatMissed(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: repeatMissedKey) == nil ? true : defaults.bool(forKey: repeatMissedKey)
    }
}

/// Settings of the Wortschatz (Goethe) box.
enum WortschatzPrefs {
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

    static func newPerDay(_ defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: newPerDayKey)
        return stored > 0 ? stored : newPerDayDefault
    }

    static func sessionCap(_ defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: sessionCapKey)
        return stored > 0 ? stored : sessionCapDefault
    }

    static func style(_ defaults: UserDefaults = .standard) -> FlashcardStyle {
        guard let raw = defaults.string(forKey: styleKey), let style = FlashcardStyle(rawValue: raw),
              style != .default else { return .anki }
        return style
    }
}
