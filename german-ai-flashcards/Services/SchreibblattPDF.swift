//
//  SchreibblattPDF.swift
//  german-ai-flashcards
//
//  A writing sheet as a printable PDF. The learner's own drill on paper: the iPad writes on the
//  sheet directly, and everywhere else — iPhone, Mac — this is the sheet.
//
//  `CGContext(consumer:mediaBox:auxiliaryInfo:)`, not `UIGraphicsPDFRenderer`. It hands
//  `SchreibblattRenderer` the same `CGContext` the on-screen ruled view does, so there is one
//  renderer rather than two; it compiles and runs on the Mac, which is the platform with no
//  `PKCanvasView` and therefore the one that needs paper most; and it writes into a `Data` rather
//  than a file, which is what `Transferable` wants. The app's other PDF writer
//  (`JobPostingClipperModel.snapshotPDF`) is the legacy `UIGraphicsBeginPDFContextToData` C API
//  and is already `#if os(macOS) return nil`-dead; this does not follow it.
//
//  **The one coordinate flip in the feature lives here.** A PDF page is origin-bottom-left with
//  +y up; the layout is top-left with +y down. Each page flips once, and the renderer never knows.
//
//  See docs/SCHREIBBLATT.md.
//

import CoreGraphics
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated enum SchreibblattPDF {

    /// The sheet as PDF bytes, one page per `layout.pageCount`. Nil when the layout is empty or
    /// Core Graphics refuses a context.
    ///
    /// `ink` is a `PKDrawing.dataRepresentation()` and is drawn above the rules when present, so a
    /// sheet already written on exports with its handwriting.
    static func data(
        layout: SchreibblattLayout,
        title: String,
        ink: Data? = nil,
        lines: Bool = false
    ) -> Data? {
        guard layout.pageCount > 0 else { return nil }

        let out = NSMutableData()
        guard let consumer = CGDataConsumer(data: out) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: layout.paper.size)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: title,
            kCGPDFContextCreator: "Die Kartei",
        ]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox,
                                  info as CFDictionary) else { return nil }

        for page in 0..<layout.pageCount {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            // Sheet space -> this page's box: flip to y-down, then slide the stack so that this
            // page's top edge is at y = 0.
            ctx.translateBy(x: 0, y: layout.paper.size.height + layout.pageOrigin(page).y)
            ctx.scaleBy(x: 1, y: -1)

            SchreibblattRenderer.draw(layout, page: page, in: ctx, title: title, lines: lines)
            #if canImport(PencilKit)
            if let ink {
                SchreibblattRenderer.drawInk(ink, page: page, in: ctx, layout: layout)
            }
            #endif

            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()

        return out.length > 0 ? out as Data : nil
    }

    /// A file name that survives a sheet title with slashes, colons or emoji in it.
    static func fileName(for title: String) -> String {
        "\(DeckTransfer.fileStem(title, fallback: "schreibblatt")).pdf"
    }
}

// MARK: - Sharing

/// `Transferable` rather than a temp file, the same as `DeckTransfer` and `PlacementExport`: the
/// system materializes the attachment itself, so there is no file lifetime racing the share
/// sheet's dismissal.
///
/// Holds what to draw, not the bytes: the PDF is written when someone actually shares, with the
/// ink as it is on disk then. Built in the screen's `body` instead, it ran on every render and
/// shared the ink from when the screen opened.
struct SchreibblattDocument: Transferable {
    let layout: SchreibblattLayout
    let title: String
    /// The sheet's ink file in `SchreibblattInkStore`, read at share time.
    let inkFileName: String?
    /// The notebook ruling, which the learner may leave off the paper even when it is on screen.
    var lines = false

    var fileName: String { SchreibblattPDF.fileName(for: title) }

    func data() -> Data? {
        SchreibblattPDF.data(layout: layout, title: title, ink: SchreibblattInkStore.read(inkFileName),
                             lines: lines)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { document in
            guard let data = document.data() else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
        // Without this, Files and Mail name the attachment "Data".
        .suggestedFileName { $0.fileName }
    }
}
