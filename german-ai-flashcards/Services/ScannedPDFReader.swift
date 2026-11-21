import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Text for a PDF that has no text layer: a scanned handout, the common case for anything a
/// teacher photocopies. `PDFTextExtractor` reports such a file as `looksScanned`; this renders its
/// pages and runs the same on-device Vision recognizer the photo scans use, page by page, so the
/// result carries the `[Seite N]` markers the rest of the app expects.
@MainActor
enum ScannedPDFReader {
    /// A handout is a few pages; a scanned textbook is not this feature's job.
    static let pageLimit = 12

    /// Nil when nothing readable came back from any page.
    static func extract(
        data: Data,
        ocr: PhotoOCRService,
        progress: ((_ page: Int, _ of: Int) -> Void)? = nil
    ) async -> String? {
        // One page rendered at a time, off the main actor. Rendering the whole run up front was
        // twelve 1400-point bitmaps resident at once (~130 MB) and all of it on the main thread.
        let total = min(PDFTextExtractor.pageCount(of: data), pageLimit)
        guard total > 0 else { return nil }
        var out = ""
        for index in 0..<total {
            progress?(index + 1, total)
            let jpeg = await Task.detached(priority: .userInitiated) {
                PDFTextExtractor.pageImage(from: data, page: index + 1)?.jpegData(compressionQuality: 0.85)
            }.value
            guard let jpeg else { continue }
            if case .success(let text) = await ocr.extractText(from: jpeg) {
                out += "\n\n[Seite \(index + 1)]\n" + text + "\n"
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : out
    }
}
