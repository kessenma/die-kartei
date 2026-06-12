import Foundation
import PDFKit

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

    /// Returns extracted text, or nil if the PDF couldn't be opened.
    static func extract(from url: URL) -> Result? {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: url) else { return nil }

        var out = ""
        for index in 0..<doc.pageCount {
            if let page = doc.page(at: index), let pageText = page.string, !pageText.isEmpty {
                out += "\n\n[Seite \(index + 1)]\n" + pageText + "\n"
            }
        }
        return Result(text: out, pageCount: doc.pageCount)
    }

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
