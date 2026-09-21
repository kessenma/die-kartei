import UIKit

/// Where generated flashcard pictures live on disk:
/// `Application Support/CardImages/<deckUUID>/<cardUUID>.png`
///
/// Deliberately not generalized with `StoryImageStore`: stories key images by position within a
/// story (`00.png`, `01.png`) while cards key them by the card's own stable UUID, and the shared
/// part is three lines of FileManager. Grouping by deck keeps deletion to one directory removal.
///
/// Application Support rather than Caches, same as stories: these are user content that must
/// survive cache eviction, since the model that drew them may be gone by then.
nonisolated enum CardImageStore {
    private static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent("CardImages")
    }

    /// The image directory for one deck, created on demand.
    static func directory(for deckID: UUID) -> URL {
        let dir = root.appendingPathComponent(deckID.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A fresh file name for a card's picture: the card's `id` plus a per-draw token, so it
    /// survives reordering and never collides with another card in the deck.
    ///
    /// The token exists for redraws. Views load the picture with `.task(id: imageFileName)`, so
    /// overwriting the same path would leave the old image on screen until the deck was reopened;
    /// a new name changes the identity and the new picture appears. The caller deletes the file it
    /// replaced (`delete(fileName:deckID:)`) once the new one is safely written.
    static func newFileName(for cardID: UUID) -> String {
        "\(cardID.uuidString)-\(UInt32.random(in: 0..<UInt32.max)).png"
    }

    /// Remove one card's picture file. Best-effort: a leftover PNG costs disk, not correctness.
    static func delete(fileName: String, deckID: UUID) {
        try? FileManager.default.removeItem(at: url(fileName: fileName, deckID: deckID))
    }

    static func url(fileName: String, deckID: UUID) -> URL {
        directory(for: deckID).appendingPathComponent(fileName)
    }

    static func loadImage(fileName: String, deckID: UUID) -> UIImage? {
        UIImage(contentsOfFile: url(fileName: fileName, deckID: deckID).path)
    }

    /// Load a card's picture no larger than `maxPixelSize` on its long edge — the same ImageIO
    /// path the story pictures use. A 48 pt thumbnail row used to decode the full 512² (1 MB)
    /// per card; see `DownsampledImage`.
    static func loadImage(fileName: String, deckID: UUID, maxPixelSize: Int) -> UIImage? {
        DownsampledImage.load(at: url(fileName: fileName, deckID: deckID), maxPixelSize: maxPixelSize)
    }

    // MARK: - Drafts

    /// A file name for a picture drawn before its card exists — `CardImageTiming.everyCard` draws
    /// during generation, while the cards are still plain `VocabCard` structs with no id and no
    /// deck. Draft pictures live in their own directory keyed by a throwaway UUID, which is why
    /// every other call here takes them without knowing the difference.
    static func draftFileName(index: Int) -> String {
        "draft-\(index)-\(UInt32.random(in: 0..<UInt32.max)).png"
    }

    /// Move a draft picture into the deck it ended up belonging to, renaming it to the card's own
    /// name. Returns the new file name, or nil if the file wasn't there — a card whose adoption
    /// failed is simply a card without a picture, and the illustrate-the-rest pass will offer to
    /// draw it again.
    static func adopt(draftFileName: String, from draftID: UUID, toCard cardID: UUID, in deckID: UUID) -> String? {
        let source = url(fileName: draftFileName, deckID: draftID)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let fileName = newFileName(for: cardID)
        do {
            try FileManager.default.moveItem(at: source, to: url(fileName: fileName, deckID: deckID))
            return fileName
        } catch {
            return nil
        }
    }

    /// Throw away a draft run's directory — after its pictures have been adopted, or when the
    /// learner discarded the whole batch of generated cards.
    static func discardDraft(_ draftID: UUID) {
        deleteImages(for: draftID)
    }

    /// Remove a deck's whole image directory. Best-effort — called when the deck is deleted.
    static func deleteImages(for deckID: UUID) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(deckID.uuidString))
    }
}
