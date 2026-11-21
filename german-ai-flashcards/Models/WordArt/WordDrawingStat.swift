import Foundation
import SwiftData

/// Lifetime drawing history for one word, kept whether or not a sketch was saved: how often it
/// was sketched, drawn in the Atelier and painted by number, and how often it was recalled.
///
/// One row per `WordArtKey`. The counts are per-device counters in sync, so drawing on an iPad
/// and an iPhone adds up.
@Model
final class WordDrawingStat {
    var key: String
    var germanWord: String
    var english: String

    var quickCount: Int = 0
    var studioCount: Int = 0
    var paintedCount: Int = 0
    /// Quick sketches drawn from memory that the learner knew / didn't.
    var recallRight: Int = 0
    var recallMissed: Int = 0

    var lastQuickAt: Date?
    var lastStudioAt: Date?
    var lastPaintedAt: Date?

    init(key: String, germanWord: String, english: String) {
        self.key = key
        self.germanWord = germanWord
        self.english = english
    }

    var totalDrawn: Int { quickCount + studioCount + paintedCount }
}
