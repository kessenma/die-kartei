import SwiftUI

/// Visual identity for each story style — kept out of the `@Model` file so `StudyStory` stays
/// SwiftUI-free. Drives the style card gallery and the selected-style row on the setup screen.
/// Colors stay in the app's cohesive blue/indigo/violet/teal/rose/amber family.
extension StoryGenre {
    var systemImage: String {
        switch self {
        case .alltag:    "cup.and.saucer.fill"
        case .dialog:    "bubble.left.and.bubble.right.fill"
        case .brief:     "envelope.fill"
        case .krimi:     "magnifyingglass"
        case .maerchen:  "crown.fill"
        case .abenteuer: "map.fill"
        case .romanze:   "heart.fill"
        case .scifi:     "moon.stars.fill"
        case .comedy:    "theatermasks.fill"
        case .tagebuch:  "book.closed.fill"
        case .fabel:     "hare.fill"
        }
    }

    /// One-line English description shown under the German label on each style card.
    var englishSubtitle: String {
        switch self {
        case .alltag:    "A realistic slice of daily life"
        case .dialog:    "A back-and-forth between two people"
        case .brief:     "Messages sent back and forth"
        case .krimi:     "A puzzle that resolves at the end"
        case .maerchen:  "Once upon a time…"
        case .abenteuer: "A journey or a daring quest"
        case .romanze:   "Two people growing closer"
        case .scifi:     "The future, space, a big idea"
        case .comedy:    "A funny mix-up or situation"
        case .tagebuch:  "First-person, dated, personal"
        case .fabel:     "Talking animals with a moral"
        }
    }

    /// Brand colors ordered light → deep (like `ModelTheme.palette`).
    var styleColors: [Color] {
        switch self {
        case .alltag:    [Color(hex: 0x8AB4F8), Color(hex: 0x4285F4)]
        case .dialog:    [Color(hex: 0x4FC3F7), Color(hex: 0x2196F3)]
        case .brief:     [Color(hex: 0x7C86F0), Color(hex: 0x5B4FD6)]
        case .krimi:     [Color(hex: 0x5C6BC0), Color(hex: 0x2A2E5A)]
        case .maerchen:  [Color(hex: 0xB388FF), Color(hex: 0x7E57C2)]
        case .abenteuer: [Color(hex: 0x4DB6AC), Color(hex: 0x00897B)]
        case .romanze:   [Color(hex: 0xFF9EC0), Color(hex: 0xEC407A)]
        case .scifi:     [Color(hex: 0x4FC3F7), Color(hex: 0x6A5AE8)]
        case .comedy:    [Color(hex: 0xFFD54F), Color(hex: 0xFB8C00)]
        case .tagebuch:  [Color(hex: 0xE0B27A), Color(hex: 0xB07B45)]
        case .fabel:     [Color(hex: 0x9CCC65), Color(hex: 0x558B2F)]
        }
    }

    /// The single representative color — for tints, the selected-row icon, chips.
    var styleAccent: Color { styleColors.last ?? .accentColor }

    /// A top-leading → bottom-trailing gradient for the card art.
    var styleGradient: LinearGradient {
        LinearGradient(colors: styleColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
