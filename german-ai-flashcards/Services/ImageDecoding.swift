import ImageIO
import UIKit

/// Decode a picture file no larger than needed. A generated picture is 512×512 and costs 1 MB
/// decoded *however small it's drawn*; a list of 48 pt thumbnails paying that per row is the kind
/// of quiet cost that adds up against the ~250 MB left beside a resident tutor. Both picture
/// stores (`StoryImageStore`, `CardImageStore`) decode through here.
nonisolated enum DownsampledImage {

    /// Load the image at `url` with its long edge capped at `maxPixelSize`. Never upscales: the
    /// cap is clamped to the file's own size, so asking for more than it holds costs nothing
    /// extra. Decodes immediately, on the calling thread — call it off the main actor.
    ///
    /// Falls back to a plain full-size decode if ImageIO can't read the file as an image source.
    static func load(at url: URL, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return UIImage(contentsOfFile: url.path)
        }
        // Never ask for more than the file holds: `CreateThumbnailFromImageAlways` would happily
        // scale a picture up to the request and charge RAM for the extra pixels.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let sourceLongEdge = max(
            (properties?[kCGImagePropertyPixelWidth] as? Int) ?? 0,
            (properties?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        )
        let target = sourceLongEdge > 0 ? min(maxPixelSize, sourceLongEdge) : maxPixelSize
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode now, on whichever thread called: otherwise the cost just moves to the first
            // frame that draws it, on the main thread.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(cgImage: thumbnail)
    }

    /// Pixels needed to draw `points` sharp on the current screen.
    @MainActor
    static func pixels(forPoints points: CGFloat) -> Int {
        Int((points * max(UITraitCollection.current.displayScale, 1)).rounded())
    }
}
