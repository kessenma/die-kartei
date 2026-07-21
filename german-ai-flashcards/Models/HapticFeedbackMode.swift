//
//  HapticFeedbackMode.swift
//  german-ai-flashcards
//
//  How much the games vibrate. One shared setting (Settings ▸ Cards) gates the haptics in
//  the card-matching and der/die/das games; "Mistakes only" keeps the corrective buzz while
//  dropping the constant success taps.
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
        case .all:        "Vibrates on right and wrong answers in the matching and article games."
        case .errorsOnly: "Vibrates only when you get one wrong — successes stay silent."
        case .off:        "The games never vibrate."
        }
    }
}
