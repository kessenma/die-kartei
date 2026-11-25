import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#endif

/// Extracts text from a PDF on-device (no model needed). Mirrors the proven approach in
/// rag-mobile: per-page `PDFDocument.page(at:).string` with `[Seite N]` markers so later
/// chunking can respect page boundaries.
///
/// `nonisolated` on purpose. The target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// so an unannotated enum here *is* main-actor, and a 37-page table rebuild could only ever run on
/// the main thread — which is exactly why importing a slide export froze the screen. Every caller
/// now hops off the main actor first. `scripts/vocab_sheet_probe.sh` compiles this file with no
/// default isolation at all, which is why the probe never showed the freeze.
nonisolated enum PDFTextExtractor {

    struct Result {
        let text: String
        let pageCount: Int
        /// True when the PDF opened but had essentially no extractable text (likely scanned/images).
        var looksScanned: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40
        }
    }

    /// Returns extracted text, or nil if the PDF couldn't be opened. `rebuildingTables` puts a
    /// vocabulary table back into rows (see `tableRows(on:readingOrder:)`); only class material
    /// asks for it, since a two-column CV or brochure can pass for a table.
    static func extract(from url: URL, rebuildingTables: Bool = false) -> Result? {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: url) else { return nil }
        return extract(doc, rebuildingTables: rebuildingTables)
    }

    /// The same, from bytes already in hand — a PDF downloaded from a link, which has no file of
    /// its own, or one the caller read once out of a security-scoped URL.
    /// `progress` is called after each page with (pages done, page count), on the calling thread.
    static func extract(from data: Data, rebuildingTables: Bool = false,
                        progress: ((_ done: Int, _ of: Int) -> Void)? = nil) -> Result? {
        guard let doc = PDFDocument(data: data) else { return nil }
        return extract(doc, rebuildingTables: rebuildingTables, progress: progress)
    }

    private static func extract(_ doc: PDFDocument, rebuildingTables: Bool,
                                progress: ((_ done: Int, _ of: Int) -> Void)? = nil) -> Result? {
        var out = ""
        for index in 0..<doc.pageCount {
            if let page = doc.page(at: index), let pageText = page.string, !pageText.isEmpty {
                let text = rebuildingTables ? tableRows(on: page, readingOrder: pageText) ?? pageText : pageText
                out += "\n\n[Seite \(index + 1)]\n" + text + "\n"
            }
            progress?(index + 1, doc.pageCount)
        }
        return Result(text: out, pageCount: doc.pageCount)
    }

    /// A PDF's line boxes are exact — a wrapped cell's lines touch — so this path trusts a gap far
    /// smaller than a photo's. Measured on a PowerPoint vocabulary slide: −0.01 line heights within
    /// a noun's "der Computer / die Computer" cell, +0.26 between two rows.
    static let pdfTouchGap: CGFloat = 0.08

    /// The page's lines with their boxes, normalized to the page with the origin bottom-left, as
    /// Vision reports its boxes. Nil when the page has no bounds or no selectable text.
    static func placedLines(on page: PDFPage) -> [OCRTableLayout.Line]? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0,
              let lines = page.selection(for: pageBounds)?.selectionsByLine() else { return nil }
        return lines.compactMap { line in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let box = line.bounds(for: page)
            return OCRTableLayout.Line(text: text, box: CGRect(
                x: (box.minX - pageBounds.minX) / pageBounds.width,
                y: (box.minY - pageBounds.minY) / pageBounds.height,
                width: box.width / pageBounds.width,
                height: box.height / pageBounds.height
            ))
        }
    }

    /// A vocabulary table's rows put back together from where its lines sit on the page. iOS's
    /// PDFKit reads a bordered table a column at a time (every German cell, then every English
    /// one), so `page.string` pairs nothing and the ✓ marks land on the wrong rows; the Mac reads
    /// the same file row by row. Nil when the page isn't a table, and its own text stands.
    static func tableRows(on page: PDFPage, readingOrder: String) -> String? {
        guard let placed = placedLines(on: page) else { return nil }
        // A PDF's line boxes are exact: a wrapped cell's lines touch, while two short rows can sit
        // barely half a line apart, closer than the photo default allows for.
        return OCRTableLayout.tableRows(from: placed, readingOrder: readingOrder,
                                        wrapGap: 0.25, touchGap: pdfTouchGap)
    }

    /// How many pages the file has, 0 when it cannot be opened. Cheap: PDFKit reads the page tree,
    /// not the pages.
    static func pageCount(of data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }

    #if canImport(UIKit) || os(macOS)
    /// One page as a picture, `width` points wide with the page's own aspect kept. The single
    /// render in the app: the OCR of a text-layer-less PDF (`ScannedPDFReader`) and the builder's
    /// page thumbnails (`PDFPageThumbnails`) both come through here, so "a page as a picture" means
    /// one thing. On macOS `UIImage` is `NSImage` (`App/MacCompat.swift`) and `PDFPage.thumbnail`
    /// already returns it, so there is no platform branch.
    static func thumbnail(of page: PDFPage, width: CGFloat) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0, width > 0 else { return nil }
        let size = CGSize(width: width, height: width * bounds.height / bounds.width)
        return page.thumbnail(of: size, for: .mediaBox)
    }

    /// The same, from bytes and a 1-based page number — the numbering the `[Seite N]` markers use.
    /// Rendering one page per call rather than a whole array is deliberate: twelve pages at 1400
    /// points were about 130 MB resident at once (see `docs/MEMORY.md`).
    static func pageImage(from data: Data, page oneBased: Int, width: CGFloat = 1400) -> UIImage? {
        guard let doc = PDFDocument(data: data), oneBased >= 1, oneBased <= doc.pageCount,
              let page = doc.page(at: oneBased - 1) else { return nil }
        return thumbnail(of: page, width: width)
    }
    #endif

    /// Split text into character chunks (~`maxChars`) without spanning `[Seite N]` markers,
    /// breaking on paragraph/sentence boundaries where possible.
    static func chunk(_ text: String, maxChars: Int = 1500) -> [String] {
        // Split on page markers first so chunks never cross page boundaries.
        let pages = text.components(separatedBy: "\n[Seite ")
        var chunks: [String] = []
        for page in pages {
            let cleaned = page.replacingOccurrences(of: #"^\d+\]\n"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            if cleaned.count <= maxChars {
                chunks.append(cleaned)
                continue
            }
            // Break long pages on paragraph boundaries, then hard-wrap if needed.
            var current = ""
            for paragraph in cleaned.components(separatedBy: "\n\n") {
                if current.count + paragraph.count + 2 > maxChars, !current.isEmpty {
                    chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                }
                if paragraph.count > maxChars {
                    // Very long paragraph — hard split.
                    var remainder = Substring(paragraph)
                    while remainder.count > maxChars {
                        let cut = remainder.index(remainder.startIndex, offsetBy: maxChars)
                        chunks.append(String(remainder[..<cut]))
                        remainder = remainder[cut...]
                    }
                    current = String(remainder)
                } else {
                    current += (current.isEmpty ? "" : "\n\n") + paragraph
                }
            }
            if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return chunks.filter { $0.count >= 20 }
    }
}
