import UIKit

/// Where generated story illustrations live on disk:
/// `Application Support/StoryImages/<storyUUID>/00.png`, `01.png`, …
/// Application Support rather than Caches: these are user content that must survive
/// cache eviction (the model that drew them may be gone).
nonisolated enum StoryImageStore {
    private static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent("StoryImages")
    }

    /// The image directory for one story, created on demand.
    static func directory(for storyID: UUID) -> URL {
        let dir = root.appendingPathComponent(storyID.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(fileName: String, storyID: UUID) -> URL {
        directory(for: storyID).appendingPathComponent(fileName)
    }

    static func loadImage(fileName: String, storyID: UUID) -> UIImage? {
        UIImage(contentsOfFile: url(fileName: fileName, storyID: storyID).path)
    }

    /// Load a picture no larger than `maxPixelSize` on its long edge.
    ///
    /// A generated illustration is 512×512 (`ImageGenModel.outputResolution`), which costs 1 MB
    /// of RAM once decoded however small it's drawn — and a screen showing several of them is
    /// spending that several times over, against the 250 MB `MemoryBudget.reserveMB` leaves for
    /// everything that isn't the model. Decoding straight to the size actually needed is the
    /// difference between a list of covers costing tens of megabytes and costing a couple.
    ///
    /// Falls back to a full-size decode if the file can't be read as an image source.
    static func loadImage(fileName: String, storyID: UUID, maxPixelSize: Int) -> UIImage? {
        DownsampledImage.load(at: url(fileName: fileName, storyID: storyID), maxPixelSize: maxPixelSize)
    }

    /// Remove a story's image directory. Best-effort — called when the story is deleted.
    static func deleteImages(for storyID: UUID) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(storyID.uuidString))
    }
}
