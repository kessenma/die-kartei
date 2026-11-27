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
    /// A phrase card shows with one word missing and four choices (`PhraseGapCardView`) instead of
    /// flipping. On by default.
    static let phraseGapsKey = "cards.phraseGaps"
    /// A missed card asks to be written out with the Apple Pencil (`WriteItSheet`). On by default,
    /// iPad only: the iPhone and the Mac never show the switch or the sheet.
    static let writeAfterMissKey = "cards.writeAfterMiss"

    /// Whether this device can offer the write-it sheet at all: an iPad, for the Pencil.
    static var writeAfterMissAvailable: Bool { ThisDevice.kind == .iPad }

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

// `WortschatzPrefs` lives in WortschatzPrefs.swift, shared with Android.
