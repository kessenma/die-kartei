import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#endif

/// Extracts text from a PDF on-device (no model needed). Mirrors the proven approach in
/// rag-mobile: per-page `PDFDocument.page(at:).string` with `[Seite N]` markers so later
/// chunking can respect page boundaries.
enum PDFTextExtractor {

    struct Result {
        let text: String
        let pageCount: Int
        /// True when the PDF opened but had essentially no extractable text (likely scanned/images).
        var looksScanned: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40
        }
    }

    /// Returns extracted text, or nil if the PDF couldn't be opened. `rebuildingTables` puts a
    /// German | English vocabulary table back into rows (see `tableRows(on:readingOrder:)`); only
    /// class material asks for it, since a two-column CV or brochure can pass for a table.
    static func extract(from url: URL, rebuildingTables: Bool = false) -> Result? {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: url) else { return nil }

        var out = ""
        for index in 0..<doc.pageCount {
            if let page = doc.page(at: index), let pageText = page.string, !pageText.isEmpty {
                let text = rebuildingTables ? tableRows(on: page, readingOrder: pageText) ?? pageText : pageText
                out += "\n\n[Seite \(index + 1)]\n" + text + "\n"
            }
        }
        return Result(text: out, pageCount: doc.pageCount)
    }

    /// A vocabulary table's rows put back together from where its lines sit on the page. iOS's
    /// PDFKit reads a bordered table a column at a time (every German cell, then every English
    /// one), so `page.string` pairs nothing and the ✓ marks land on the wrong rows; the Mac reads
    /// the same file row by row. Nil when the page isn't a table, and its own text stands.
    private static func tableRows(on page: PDFPage, readingOrder: String) -> String? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0,
              let lines = page.selection(for: pageBounds)?.selectionsByLine() else { return nil }
        let placed: [OCRTableLayout.Line] = lines.compactMap { line in
            guard let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let box = line.bounds(for: page)
            // Normalized to the page with the origin bottom-left, as Vision reports its boxes.
            return OCRTableLayout.Line(text: text, box: CGRect(
                x: (box.minX - pageBounds.minX) / pageBounds.width,
                y: (box.minY - pageBounds.minY) / pageBounds.height,
                width: box.width / pageBounds.width,
                height: box.height / pageBounds.height
            ))
        }
        // A PDF's line boxes are exact: a wrapped cell's lines touch, while two short rows can sit
        // barely half a line apart, closer than the photo default allows for.
        return OCRTableLayout.tableRows(from: placed, readingOrder: readingOrder, wrapGap: 0.25)
    }

    #if canImport(UIKit) || os(macOS)
    /// The first `limit` pages rendered as images, `width` points wide, for OCR of a PDF that has
    /// no text layer (see `ScannedPDFReader`). Takes the file's bytes rather than its URL so the
    /// caller reads a security-scoped file once.
    static func pageImages(from data: Data, limit: Int = 12, width: CGFloat = 1400) -> [UIImage] {
        guard let doc = PDFDocument(data: data) else { return [] }
        var images: [UIImage] = []
        for index in 0..<min(doc.pageCount, limit) {
            guard let page = doc.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let size = CGSize(width: width, height: width * bounds.height / bounds.width)
            images.append(page.thumbnail(of: size, for: .mediaBox))
        }
        return images
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
