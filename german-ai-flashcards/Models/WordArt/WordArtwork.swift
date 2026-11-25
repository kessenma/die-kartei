import Foundation
import SwiftData

/// One picture of one word: an AI picture in a chosen style, a quick sketch the learner kept, an
/// Atelier piece, or a paint-by-number picture.
///
/// One row (and one sync record) per picture, so pictures added on two devices never collide.
/// The bytes are files under `WordArt/<folder>/` (`WordArtStore`), synced file by file like card
/// pictures. `SavedCard.imageFileName` is untouched by any of this: a card's own picture stays
/// where it was, and "Use as card picture" copies a file into the card's folder.
@Model
final class WordArtwork {
    var id: UUID
    /// `WordArtKey.make(germanWord)`.
    var wordKey: String
    /// The word as it was shown when the picture was made ("der Tisch").
    var germanWord: String
    var english: String
    /// `WordArtworkKind.rawValue`.
    var kindRaw: String
    /// `WordArtStyle.rawValue` for AI pictures; nil for the learner's own drawings.
    var styleRaw: String?
    /// The OpenRouter model id that drew an AI picture.
    var modelID: String?
    /// The prompt sent, kept so a picture can be redrawn the same way.
    var prompt: String?
    /// The PNG's file name inside the word's folder. For a paint-by-number piece still in
    /// progress, the file may not exist yet.
    var fileName: String
    /// Studio pieces: the `PKDrawing` file next to the PNG, so the piece can be reopened.
    var inkFileName: String?
    var createdAt: Date
    var starred: Bool = false
    /// Quick sketches: `QuickDrawMode.rawValue` of the run it came from.
    var modeRaw: String?
    /// Quick sketches drawn from memory: whether the learner knew the word.
    var recalled: Bool?
    /// Paint by number: not finished yet (shows on the "Weitermalen" shelf).
    var inProgress: Bool = false
    /// A paint-by-number piece or a studio piece made from another picture: that picture's id.
    var sourceArtworkID: UUID?

    init(
        wordKey: String,
        germanWord: String,
        english: String,
        kind: WordArtworkKind,
        fileName: String,
        styleRaw: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.wordKey = wordKey
        self.germanWord = germanWord
        self.english = english
        self.kindRaw = kind.rawValue
        self.styleRaw = styleRaw
        self.fileName = fileName
        self.createdAt = createdAt
    }

    var kind: WordArtworkKind { WordArtworkKind(rawValue: kindRaw) ?? .ai }
}

nonisolated enum WordArtworkKind: String, CaseIterable, Codable, Sendable {
    /// Drawn by a cloud image model in a `WordArtStyle`.
    case ai
    /// A sketch from a Quick Draw run the learner chose to keep.
    case quick
    /// An Atelier piece.
    case studio
    /// A paint-by-number piece.
    case paintByNumber

    var isLearnerMade: Bool { self != .ai }
}

/// What a Quick Draw turn asks for, chosen per run.
nonisolated enum QuickDrawMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Draw from the German word alone, then reveal and mark it.
    case recall
    /// Sketch the AI reference picture.
    case copy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recall: "Aus dem Kopf · Recall"
        case .copy:   "Abzeichnen · Copy"
        }
    }

    var blurb: String {
        switch self {
        case .recall: "See the German word, draw it from memory, then check."
        case .copy:   "Sketch the reference picture while you read the word."
        }
    }
}
