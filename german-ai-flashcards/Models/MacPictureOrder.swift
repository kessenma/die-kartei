import Foundation

// MAC-PICTURES: "Draw on my Mac" (docs/MAC_PICTURES.md).

/// A deck's (or story's) request for pictures from the learner's Mac, and the Mac's answer.
///
/// Both travel through iCloud sync as two JSON fields on the deck, each written by one side
/// only: the phone writes `Request`, the Mac (or a cancel) writes `Result`. A request is pending
/// until a result *names it* (`settles == request.id`), so there's no clock to trust and no field
/// both sides write:
/// - re-requesting while the Mac settles the old one writes a new id: still pending;
/// - cancelling while the Mac settles writes the same field, but both settle the same id;
/// - an older build carries both fields through untouched (unknown fields survive a merge).
nonisolated enum MacPictureOrder {

    struct Request: Codable, Equatable, Sendable {
        var id: UUID
        var requestedAt: Date
        /// The phone's `CardImageStyle` / `CardImageDetail` when it asked: learner prefs don't
        /// sync, so the order carries its own. nil for stories (their look comes from the genre).
        var styleRaw: String?
        var detailRaw: String?
        /// Redraw every picture, not only the missing ones.
        var redrawAll: Bool
        /// How many cards the phone saw, so the Mac can wait for the rest to sync before drawing.
        var cardCount: Int
        /// "Kyle's iPhone", for the Mac's banner.
        var fromDevice: String
    }

    enum Outcome: String, Codable, Sendable {
        /// Every picture asked for was drawn.
        case drawn
        /// Some pictures failed; the rest were drawn.
        case partial
        /// A redraw the learner stopped on the Mac (a fill-in that stops stays pending instead).
        case stopped
        /// Cancelled from either device before it was drawn.
        case cancelled
        /// Nothing was missing by the time the Mac looked.
        case nothingToDraw
        /// The deck can't take part (deleted cards, a Wortschatz deck).
        case unsupported
    }

    struct Result: Codable, Equatable, Sendable {
        /// The request this answers.
        var settles: UUID
        var outcome: Outcome
        var drawn: Int
        var finishedAt: Date
        var byDevice: String
    }

    static func isPending(_ request: Request?, _ result: Result?) -> Bool {
        guard let request else { return false }
        return result?.settles != request.id
    }

    static func newRequest(styleRaw: String?, detailRaw: String?, redrawAll: Bool, cardCount: Int,
                           fromDevice: String, now: Date = .now) -> Request {
        Request(id: UUID(), requestedAt: now, styleRaw: styleRaw, detailRaw: detailRaw,
                redrawAll: redrawAll, cardCount: cardCount, fromDevice: fromDevice)
    }

    static func settle(_ request: Request, outcome: Outcome, drawn: Int, byDevice: String, now: Date = .now) -> Result {
        Result(settles: request.id, outcome: outcome, drawn: drawn, finishedAt: now, byDevice: byDevice)
    }

    // MARK: Storage

    /// Default `JSONEncoder` on purpose: `SyncFields.set(_:jsonData:)` parses what it wrote.
    static func encode<T: Encodable>(_ value: T?) -> Data? {
        value.flatMap { try? JSONEncoder().encode($0) }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

/// The story twin of `SavedDeck`'s accessors: a story asks for a redraw of the pictures it has,
/// from the prompts saved with them (`StoryImageRecord.prompt`), so the Mac needs no tutor.
extension StudyStory {
    var macPictureRequest: MacPictureOrder.Request? {
        get { MacPictureOrder.decode(MacPictureOrder.Request.self, from: macPictureRequestData) }
        set { macPictureRequestData = MacPictureOrder.encode(newValue) }
    }

    var macPictureResult: MacPictureOrder.Result? {
        get { MacPictureOrder.decode(MacPictureOrder.Result.self, from: macPictureResultData) }
        set { macPictureResultData = MacPictureOrder.encode(newValue) }
    }

    var hasPendingMacPictures: Bool {
        MacPictureOrder.isPending(macPictureRequest, macPictureResult)
    }
}
