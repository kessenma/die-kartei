import Foundation
import UIKit

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
        let pages = PDFTextExtractor.pageImages(from: data, limit: pageLimit)
        guard !pages.isEmpty else { return nil }
        var out = ""
        for (index, image) in pages.enumerated() {
            progress?(index + 1, pages.count)
            guard let jpeg = image.jpegData(compressionQuality: 0.85) else { continue }
            if case .success(let text) = await ocr.extractText(from: jpeg) {
                out += "\n\n[Seite \(index + 1)]\n" + text + "\n"
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : out
    }
}
