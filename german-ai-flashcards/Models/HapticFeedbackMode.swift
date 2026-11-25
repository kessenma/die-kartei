//
//  HapticFeedbackMode.swift
//  german-ai-flashcards
//
//  How much the app vibrates. One shared setting (Settings ▸ Cards) gates the haptics in
//  the card-matching and der/die/das games plus the conversation's soft ticks (record
//  start/stop, clean turn); "Mistakes only" keeps the corrective buzz while dropping the
//  constant success taps.
//

import Foundation

enum HapticFeedbackMode: String, CaseIterable, Identifiable {
    case all = "All"
    case errorsOnly = "Mistakes only"
    case off = "Off"

    var id: String { rawValue }

    /// Vibrate on a correct answer / cleared pair.
    var playsSuccess: Bool { self == .all }
    /// Vibrate on a wrong answer.
    var playsError: Bool { self != .off }

    var description: String {
        switch self {
        case .all:        "Vibrates on right and wrong answers in the games, and softly in chat."
        case .errorsOnly: "Vibrates only when you get one wrong — successes stay silent."
        case .off:        "Nothing vibrates."
        }
    }
}
