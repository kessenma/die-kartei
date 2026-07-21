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

    /// Remove a story's image directory. Best-effort — called when the story is deleted.
    static func deleteImages(for storyID: UUID) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(storyID.uuidString))
    }
}
