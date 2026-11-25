import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns whatever a cloud model sent back (PNG, JPEG or WebP, 1024² or 1600²) into the same thing
/// the on-device path writes: a PNG at the size the app displays, at the path the caller chose.
///
/// Downscaling is not cosmetic. Card pictures are shown at 512 px and story pictures at 700, and
/// both folders sync to iCloud file by file: a 1.9 MB Nano Banana original per card would be
/// several hundred MB for one illustrated deck.
nonisolated enum CloudPictureWriter {
    enum WriteError: LocalizedError {
        case undecodable
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .undecodable:  "The picture that came back couldn't be opened."
            case .encodeFailed: "The picture couldn't be saved."
            }
        }
    }

    /// The longest edge for each kind of picture.
    static let cardMaxPixel = 512
    static let storyMaxPixel = 768

    /// Decode, shrink so the long edge is at most `maxPixel` (never enlarge), write PNG atomically.
    /// Returns the image written, so a waiting screen can show it without reading the file back.
    @discardableResult
    static func write(_ data: Data, maxPixel: Int, to destination: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { throw WriteError.undecodable }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WriteError.undecodable
        }

        let output = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw WriteError.encodeFailed
        }
        CGImageDestinationAddImage(target, image, nil)
        guard CGImageDestinationFinalize(target) else { throw WriteError.encodeFailed }
        try (output as Data).write(to: destination, options: .atomic)
        return image
    }
}
