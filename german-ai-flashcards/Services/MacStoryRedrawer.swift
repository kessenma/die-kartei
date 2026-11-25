#if os(macOS)
import Foundation
import SwiftData

// MAC-PICTURES: "Redraw on my Mac" for stories (docs/MAC_PICTURES.md).

/// Redraws a story's pictures with the Mac's big model, from the prompts saved with them.
///
/// No tutor is involved: each `StoryImageRecord` keeps the prompt that drew it, and the story's
/// seed comes from its id the same way `StoryStudyService.illustrate` derives it, so the redrawn
/// set keeps one palette. Every picture gets a new file name and the record swaps to it, so a
/// reader keyed on file names (here and on the phone) shows the new picture; the old file is
/// deleted only after the swap is saved.
@Observable
@MainActor
final class MacStoryRedrawer {
    static let shared = MacStoryRedrawer()

    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var stepFraction: Double = 0

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, (Double(completedCount) + stepFraction) / Double(totalCount))
    }

    private init() {}

    /// The same seed `StoryStudyService` draws a story with: the first four bytes of its id.
    static func seed(for storyID: UUID) -> UInt32 {
        let b = storyID.uuid
        return UInt32(b.0) << 24 | UInt32(b.1) << 16 | UInt32(b.2) << 8 | UInt32(b.3)
    }

    static func redraw(_ story: StudyStory, in context: ModelContext,
                       mlxService: MLXGenerationService) async -> (drawn: Int, stopped: Bool) {
        await shared.run(story, in: context, mlxService: mlxService)
    }

    private func run(_ story: StudyStory, in context: ModelContext,
                     mlxService: MLXGenerationService) async -> (drawn: Int, stopped: Bool) {
        let records = story.images
        guard !records.isEmpty else { return (0, false) }
        completedCount = 0
        totalCount = records.count
        stepFraction = 0
        defer { completedCount = 0; totalCount = 0; stepFraction = 0 }

        mlxService.unloadModel()
        let service = StoryImageService.shared
        guard await service.loadPipeline() else { return (0, false) }
        defer { service.unloadPipeline() }

        let seed = Self.seed(for: story.id)
        let storyID = story.id
        var updated = records
        var drawn = 0
        for index in records.indices {
            guard !story.isDeleted else { break }
            stepFraction = 0
            let newName = String(format: "%02d-%@.png", index, String(UUID().uuidString.prefix(8)))
            let written: Bool
            do {
                written = try await service.generateImage(
                    prompt: records[index].prompt,
                    saveTo: StoryImageStore.url(fileName: newName, storyID: storyID),
                    seed: seed,
                    onStepProgress: { [weak self] fraction in self?.stepFraction = fraction }
                )
            } catch {
                completedCount += 1
                continue   // one picture failed; try the next
            }
            guard written else { return (drawn, true) }   // stopped
            guard !story.isDeleted else { break }
            let oldName = updated[index].fileName
            updated[index].fileName = newName
            story.setImages(updated)
            try? context.save()
            if oldName != newName {
                try? FileManager.default.removeItem(at: StoryImageStore.url(fileName: oldName, storyID: storyID))
            }
            drawn += 1
            completedCount += 1
        }
        return (drawn, false)
    }
}
#endif
