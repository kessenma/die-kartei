//
//  PrepositionPictureMode.swift
//  german-ai-flashcards
//
//  How much of the 3D scene the preposition exercises show, and when.
//
//  The design rests on one observation: what gives a preposition's case away is the *color
//  coding* and the *two-state contrast*, not the scene itself. A ball resting on a table says
//  nothing about whether `auf` is fixed-Dativ or two-way; a **teal** ball says Dativ, and a
//  moving/resting **pair** says Wechsel.
//
//  So the picture splits in two, and the default mode shows the innocent half up front:
//  the relation while the question is up (neutral, static), the case when it's answered.
//  That teaches a beginner what the word means without answering the question being asked,
//  which is why it needs no scaffold gate.
//

import Foundation

enum PrepositionPictureMode: String, CaseIterable, Codable, Identifiable {
    /// Neutral scene on the question, resolved scene on reveal. The default.
    case on
    /// Fully resolved scene — case color and all — on the question side too.
    case teaching
    /// Text only.
    case off

    var id: String { rawValue }

    static let defaultsKey = "prepositionPictureMode"

    var label: String {
        switch self {
        case .on:       "Show pictures"
        case .teaching: "Teaching mode"
        case .off:      "Text only"
        }
    }

    var explanation: String {
        switch self {
        case .on:
            "A picture of the relation while you answer, and the case colors once you have."
        case .teaching:
            "The answer is in the picture from the start. Rounds played this way still count toward your streak, but they don't move your Präpositionen skill."
        case .off:
            "No pictures anywhere in the preposition exercises."
        }
    }

    /// Whether the question side shows a scene at all.
    var showsSceneOnQuestion: Bool { self != .off }

    /// Whether that scene already carries the answer — the case color and the moving state.
    /// This is the only mode whose answers have to be discounted for mastery.
    var revealsCaseOnQuestion: Bool { self == .teaching }
}
