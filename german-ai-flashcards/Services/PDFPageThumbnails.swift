//
//  PDFPageThumbnails.swift
//  german-ai-flashcards
//
//  The pictures behind the deck builder's page picker: "is page 23 the Wortliste?" is a question
//  only a look at page 23 answers.
//
//  Two pieces, for two reasons. The actor renders, so PDFKit work happens off the main thread and
//  one page at a time — a fast scroll over a 37-page module can never put thirty-seven bitmaps in
//  memory at once, because the actor serializes. The observable class in front of it caches what
//  came back, bounded, and is what the views read.
//
//  Memory: thumbnails are requested at the card's own width, and the cache holds a fixed number of
//  them. `purge()` exists because the builder is one button away from loading a multi-gigabyte
//  tutor, and `docs/MEMORY.md` allows one heavy resident at a time.
//

import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#endif

/// Renders one page at a time from bytes it keeps to itself. The `PDFDocument` is built inside the
/// actor and never handed out, which is the only thread-safety claim PDFKit is worth trusting on.
actor PDFPageThumbnailRenderer {
    private let data: Data
    private var document: PDFDocument?

    init(data: Data) {
        self.data = data
    }

    private func openedDocument() -> PDFDocument? {
        if let document { return document }
        document = PDFDocument(data: data)
        return document
    }

    var pageCount: Int { openedDocument()?.pageCount ?? 0 }

    /// `oneBased` is the page number the `[Seite N]` markers use.
    func image(page oneBased: Int, width: CGFloat) -> UIImage? {
        guard let doc = openedDocument(), oneBased >= 1, oneBased <= doc.pageCount,
              let page = doc.page(at: oneBased - 1) else { return nil }
        return PDFTextExtractor.thumbnail(of: page, width: width)
    }
}

@MainActor
@Observable
final class PDFPageThumbnails {
    /// How many rendered pages are kept. Past this the least recently asked for is dropped.
    static let cacheLimit = 24

    private let renderer: PDFPageThumbnailRenderer
    private var cache: [Int: UIImage] = [:]
    /// Least recently used first.
    private var order: [Int] = []
    private var inFlight: Set<Int> = []
    private(set) var documentPageCount = 0

    /// Nil unless the draft really carries a PDF. That is the whole fallback switch: a handout or a
    /// paper from "Your documents" has no bytes, a pasted text and a fetched web page have none
    /// either, and a photo is a JPEG that `PDFDocument` cannot open. All of those keep the plain
    /// number pills.
    convenience init?(draft: DocumentDeckDraft) {
        guard let data = draft.fileData, draft.fileExt == "pdf" else { return nil }
        self.init(pdfData: data)
    }

    /// Straight from a PDF's bytes: a handout's kept original, for the worksheet's page picker.
    init?(pdfData data: Data) {
        guard !data.isEmpty else { return nil }
        renderer = PDFPageThumbnailRenderer(data: data)
        documentPageCount = PDFTextExtractor.pageCount(of: data)
        guard documentPageCount > 0 else { return nil }
    }

    var cachedCount: Int { cache.count }
    func isCached(_ page: Int) -> Bool { cache[page] != nil }

    /// What is already rendered for this page, nil when it has not been asked for yet.
    ///
    /// A pure read on purpose: the cards call it from `body`, and nudging the eviction order here
    /// would be mutating observed state during a render. Eviction therefore goes by when a page was
    /// rendered, not when it was last looked at, which for a strip scrolled in one direction is the
    /// same order anyway.
    func thumbnail(page: Int) -> UIImage? { cache[page] }

    /// Renders the page unless it is already cached or already on its way.
    func request(page: Int, width: CGFloat) async {
        guard cache[page] == nil, !inFlight.contains(page) else { return }
        inFlight.insert(page)
        let image = await renderer.image(page: page, width: width)
        inFlight.remove(page)
        // A page scrolled past while it rendered is not worth a cache slot.
        guard !Task.isCancelled, let image else { return }
        cache[page] = image
        order.removeAll { $0 == page }
        order.append(page)
        while order.count > Self.cacheLimit, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
    }

    /// One page at reading size, for the preview sheet. Deliberately not cached: it is several
    /// megabytes and only one is ever on screen.
    func fullPage(_ page: Int, width: CGFloat = 1200) async -> UIImage? {
        await renderer.image(page: page, width: width)
    }

    /// Drops everything. Called when the picker goes away, and before the tutor loads.
    func purge() {
        cache = [:]
        order = []
    }
}
