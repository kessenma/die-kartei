import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Where a word's pictures live on disk:
/// `Application Support/WordArt/<WordArtKey.folderName>/<file>`.
///
/// `WordArt` is one of `FileSyncDocument.roots`, so every file here travels to the learner's other
/// devices by itself, as a CKAsset per file. Builds older than this folder ignore it (their
/// `FileSyncDocument.destination` refuses roots they don't know), so nothing lands half-understood.
///
/// Files per picture, all named after the artwork id plus a per-write token (the token changes the
/// name on a redraw, so a view keyed on the file name reloads, as `CardImageStore` does):
/// - `<id>-<token>.png`: the picture
/// - `<id>.drawing`: a studio piece's `PKDrawing`
/// - `<id>.pbn.json` / `<id>.progress.json`: a paint-by-number template and its progress
nonisolated enum WordArtStore {
    /// The folder name under Application Support. Also the `FileSyncDocument` root.
    static let rootName = "WordArt"

    /// Long edge of an AI reference picture. Larger than a card's 512 on purpose: these are
    /// traced and painted over at full canvas size.
    static let artMaxPixel = 1024
    /// Long edge of a kept quick sketch. PNG only, no `.drawing`, to keep iCloud use down.
    static let sketchMaxPixel = 768

    static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent(rootName)
    }

    /// The folder for one word, created on demand.
    static func directory(forKey key: String) -> URL {
        let dir = root.appendingPathComponent(WordArtKey.folderName(for: key))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(fileName: String, key: String) -> URL {
        directory(forKey: key).appendingPathComponent(fileName)
    }

    static func newPictureName(for artworkID: UUID) -> String {
        "\(artworkID.uuidString)-\(UInt32.random(in: 0..<UInt32.max)).png"
    }

    static func inkName(for artworkID: UUID) -> String { "\(artworkID.uuidString).drawing" }
    static func templateName(for artworkID: UUID) -> String { "\(artworkID.uuidString).pbn.json" }
    static func progressName(for artworkID: UUID) -> String { "\(artworkID.uuidString).progress.json" }

    // MARK: - Write

    /// Decode a model's reply (PNG, JPEG or WebP), shrink it to `maxPixel`, write PNG.
    @discardableResult
    static func writeDownloaded(_ data: Data, maxPixel: Int = artMaxPixel, fileName: String, key: String) throws -> CGImage {
        try CloudPictureWriter.write(data, maxPixel: maxPixel, to: url(fileName: fileName, key: key))
    }

    /// Write a rendered image (a sketch, a finished painting) as PNG.
    static func write(_ image: CGImage, fileName: String, key: String) throws {
        let output = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw CloudPictureWriter.WriteError.encodeFailed
        }
        CGImageDestinationAddImage(target, image, nil)
        guard CGImageDestinationFinalize(target) else { throw CloudPictureWriter.WriteError.encodeFailed }
        try (output as Data).write(to: url(fileName: fileName, key: key), options: .atomic)
    }

    static func writeData(_ data: Data, fileName: String, key: String) throws {
        try data.write(to: url(fileName: fileName, key: key), options: .atomic)
    }

    static func readData(fileName: String, key: String) -> Data? {
        try? Data(contentsOf: url(fileName: fileName, key: key))
    }

    // MARK: - Read

    static func exists(fileName: String, key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(fileName: fileName, key: key).path)
    }

    /// Decode a picture no larger than `maxPixelSize`. Call off the main actor for big sizes.
    static func loadImage(fileName: String, key: String, maxPixelSize: Int) -> UIImage? {
        DownsampledImage.load(at: url(fileName: fileName, key: key), maxPixelSize: maxPixelSize)
    }

    static func loadCGImage(fileName: String, key: String, maxPixelSize: Int) -> CGImage? {
        let fileURL = url(fileName: fileName, key: key)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Delete

    /// Every file a picture owns. Best-effort: a leftover file costs disk, not correctness.
    static func deleteFiles(artworkID: UUID, fileName: String, inkFileName: String?, key: String) {
        let fm = FileManager.default
        var names = [fileName, templateName(for: artworkID), progressName(for: artworkID)]
        if let inkFileName { names.append(inkFileName) }
        for name in names {
            try? fm.removeItem(at: url(fileName: name, key: key))
        }
    }

    // MARK: - Size

    /// Bytes under `WordArt/`, for the "how much iCloud does this use" line.
    static func totalBytes() -> Int64 {
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// A typical kept sketch, for the estimate shown before anything is saved.
    static let typicalSketchBytes: Int64 = 80_000

    static func sizePhrase(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Model-level operations

@MainActor
enum WordArtLibrary {
    /// Every picture of a word, newest first.
    static func artworks(forKey key: String, in context: ModelContext) -> [WordArtwork] {
        let d = FetchDescriptor<WordArtwork>(
            predicate: #Predicate { $0.wordKey == key },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(d)) ?? []
    }

    /// The picture to show for a word when one is needed: a starred one first, then the newest
    /// AI picture in `preferredStyle`, then any AI picture, then the newest of any kind.
    static func reference(forKey key: String, preferredStyle: WordArtStyle? = nil, in context: ModelContext) -> WordArtwork? {
        let all = artworks(forKey: key, in: context).filter { !$0.inProgress }
        if let preferredStyle, let match = all.first(where: { $0.kind == .ai && $0.styleRaw == preferredStyle.rawValue }) {
            return match
        }
        return all.first(where: \.starred)
            ?? all.first(where: { $0.kind == .ai })
            ?? all.first
    }

    /// Delete a picture and its files.
    static func delete(_ artwork: WordArtwork, in context: ModelContext) {
        WordArtStore.deleteFiles(artworkID: artwork.id, fileName: artwork.fileName,
                                 inkFileName: artwork.inkFileName, key: artwork.wordKey)
        context.delete(artwork)
        try? context.save()
    }

    /// Whether `card` can take a gallery picture as its own. Wortschatz cards can't: the bundle
    /// owns their content and sync never carries it (`SavedCardCodec.update`).
    static func canAdopt(into card: SavedCard) -> Bool {
        guard let deck = card.deck else { return false }
        return deck.generatorRaw != "goethe-srs"
    }

    /// Make a gallery picture the card's own picture: copy the file into the card's folder under
    /// a fresh name, point the card at it, and delete the file it replaced. Old builds see an
    /// ordinary card picture.
    @discardableResult
    static func adopt(_ artwork: WordArtwork, into card: SavedCard, in context: ModelContext) -> Bool {
        guard canAdopt(into: card), let deckID = card.deck?.id else { return false }
        let source = WordArtStore.url(fileName: artwork.fileName, key: artwork.wordKey)
        guard FileManager.default.fileExists(atPath: source.path) else { return false }
        let fileName = CardImageStore.newFileName(for: card.id)
        let destination = CardImageStore.url(fileName: fileName, deckID: deckID)
        do {
            // Card pictures are shown at 512; don't sync a 1024 copy into the deck folder.
            let data = try Data(contentsOf: source)
            try CloudPictureWriter.write(data, maxPixel: CloudPictureWriter.cardMaxPixel, to: destination)
        } catch {
            return false
        }
        let previous = card.imageFileName
        card.imageFileName = fileName
        try? context.save()
        if let previous, previous != fileName {
            CardImageStore.delete(fileName: previous, deckID: deckID)
        }
        return true
    }
}
