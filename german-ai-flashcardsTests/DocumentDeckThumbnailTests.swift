//
//  DocumentDeckThumbnailTests.swift
//  german-ai-flashcardsTests
//
//  The page pictures behind the deck builder's page picker (Services/PDFPageThumbnails.swift) and
//  the one render they go through (Services/PDFTextExtractor.swift).
//
//  Two things are worth pinning: the cache is bounded, because the motivating document is a 37-page
//  slide export and `docs/MEMORY.md` allows one heavy resident at a time; and the fallback switch is
//  exactly "the draft carries a PDF", because a handout, a paste and a photo must all keep the plain
//  numbered pills rather than render nothing.
//
//  The fixture is a PDF drawn here, so there is no file to check in.
//

import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif
import Testing
@testable import Die_Kartei

@Suite struct DocumentDeckThumbnailTests {

    /// A PDF of `pages` blank pages, letter sized.
    private static func pdf(pages: Int) -> Data {
        let out = NSMutableData()
        guard let consumer = CGDataConsumer(data: out) else { return Data() }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(box)
            context.endPDFPage()
        }
        context.closePDF()
        return out as Data
    }

    private static func draft(pages: Int, ext: String = "pdf") -> DocumentDeckDraft {
        DocumentDeckDraft(title: "Modul", text: "", sourceLabel: "PDF",
                          fileData: pdf(pages: pages), fileExt: ext, keepsSource: true)
    }

    // MARK: - The render

    @Test func everyPageOfThePDFIsCounted() {
        #expect(PDFTextExtractor.pageCount(of: Self.pdf(pages: 5)) == 5)
        #expect(PDFTextExtractor.pageCount(of: Data("not a pdf".utf8)) == 0)
    }

    @Test func aPageRendersAtTheWidthAsked() throws {
        let image = try #require(PDFTextExtractor.pageImage(from: Self.pdf(pages: 2), page: 1, width: 76))
        #expect(image.size.width == 76)
        // Letter is taller than it is wide, so the aspect has to survive.
        #expect(image.size.height > image.size.width)
    }

    @Test func aThumbnailsBitmapIsNoBiggerThanItsPoints() throws {
        // `PDFPage.thumbnail(of:for:)` does not document its scale, and 24 cached pages at 3x is a
        // very different number from 24 at 1x (docs/MEMORY.md). Pin what it actually does.
        let image = try #require(PDFTextExtractor.pageImage(from: Self.pdf(pages: 1), page: 1, width: 76))
        let pixels = image.cgImage?.width ?? 0
        #expect(pixels <= 76, "thumbnail rendered \(pixels) pixels wide for 76 points")
    }

    @Test func aPageNumberOutsideTheDocumentRendersNothing() {
        let data = Self.pdf(pages: 5)
        #expect(PDFTextExtractor.pageImage(from: data, page: 0) == nil)
        #expect(PDFTextExtractor.pageImage(from: data, page: 9) == nil)
        // 1-based, like the `[Seite N]` markers.
        #expect(PDFTextExtractor.pageImage(from: data, page: 5) != nil)
    }

    // MARK: - The cache

    @MainActor
    @Test func theCacheNeverHoldsMoreThanItsBound() async throws {
        let count = PDFPageThumbnails.cacheLimit + 6
        let store = try #require(PDFPageThumbnails(draft: Self.draft(pages: count)))
        #expect(store.documentPageCount == count)
        for page in 1...count {
            await store.request(page: page, width: 20)
        }
        #expect(store.cachedCount <= PDFPageThumbnails.cacheLimit)
        // The newest page asked for is the one still worth having.
        #expect(store.isCached(count))
    }

    @MainActor
    @Test func purgingLetsEveryPageGo() async throws {
        let store = try #require(PDFPageThumbnails(draft: Self.draft(pages: 3)))
        await store.request(page: 1, width: 20)
        #expect(store.cachedCount == 1)
        store.purge()
        #expect(store.cachedCount == 0)
        #expect(store.thumbnail(page: 1) == nil)
    }

    // MARK: - The fallback switch

    @MainActor
    @Test func aDraftWithoutAPDFHasNoThumbnails() {
        // A handout or a paper already in the app: text, no bytes.
        #expect(PDFPageThumbnails(draft: DocumentDeckDraft(title: "Handout", text: "der Tisch\ttable",
                                                           sourceLabel: "Handout")) == nil)
        // A photo: real bytes, but a JPEG.
        #expect(PDFPageThumbnails(draft: Self.draft(pages: 1, ext: "jpg")) == nil)
        // Bytes that are not a document at all.
        #expect(PDFPageThumbnails(draft: DocumentDeckDraft(title: "Odd", text: "", sourceLabel: "PDF",
                                                           fileData: Data("nope".utf8),
                                                           keepsSource: true)) == nil)
        #expect(PDFPageThumbnails(draft: Self.draft(pages: 1)) != nil)
    }
}
