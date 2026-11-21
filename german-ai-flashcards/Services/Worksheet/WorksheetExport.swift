//
//  WorksheetExport.swift
//  german-ai-flashcards
//
//  The homework as it goes back to the teacher: her slides, only the ones the learner worked, in
//  her order, each drawn by `WorksheetRenderer` with the answers in her blanks and the ink on top.
//  Each page keeps its own size, so her 16:9 slides stay 16:9.
//
//  Built when the share sheet asks for it, never in a view's body, and only once per share:
//  `WorksheetDocument` carries a snapshot (bytes, plan, answers) and a box that keeps the result,
//  since some share targets ask for the data twice. Rendering is one page at a time.
//

import CoreGraphics
import CoreTransferable
import Foundation
import PDFKit
import UniformTypeIdentifiers

nonisolated enum WorksheetExport {

    /// Everything the export needs, taken from the model on the main actor so the render can run
    /// anywhere.
    struct Snapshot: Sendable {
        var pdfData: Data
        var materialID: UUID
        var title: String
        var pages: [WorksheetPagePlan]
        var answers: [String: WorksheetAnswer]
        var outlinesGaps = false
        /// Draw the optional check's marks (✓ ? ✗ and the right form) on the pages too. Off unless
        /// the learner picks "With the check marks".
        var showsChecks = false
    }

    static func pdf(_ snapshot: Snapshot) -> Data? {
        guard let document = PDFDocument(data: snapshot.pdfData), !snapshot.pages.isEmpty else { return nil }
        let chrome = WorksheetPDFReader.chrome(of: document)

        let out = NSMutableData()
        guard let consumer = CGDataConsumer(data: out) else { return nil }
        var defaultBox = CGRect(origin: .zero, size: CGSize(width: 960, height: 540))
        let info: [CFString: Any] = [
            kCGPDFContextTitle: snapshot.title,
            kCGPDFContextCreator: "Die Kartei",
        ]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &defaultBox, info as CFDictionary) else { return nil }

        var wrote = 0
        for plan in snapshot.pages.sorted(by: { $0.page < $1.page }) {
            guard let page = document.page(at: plan.page - 1) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            var box = CGRect(origin: .zero, size: bounds.size)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
            ctx.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            ctx.saveGState()
            ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
            WorksheetRenderer.draw(page: page, input: input(for: plan, page: page, chrome: chrome, snapshot: snapshot),
                                   in: ctx)
            ctx.restoreGState()
            ctx.endPDFPage()
            wrote += 1
        }
        ctx.closePDF()
        return wrote > 0 && out.length > 0 ? out as Data : nil
    }

    /// The page re-parsed (never a stored parse; see `WorksheetParser`), its answers, its ink.
    /// A Pencil page still gets its typed answers drawn if it has any: switching a page to the
    /// Pencil mid-way keeps what was typed.
    static func input(for plan: WorksheetPagePlan, page: PDFPage, chrome: Set<String>,
                      snapshot: Snapshot) -> WorksheetRenderer.Input {
        let exercise = WorksheetPDFReader.parse(page: page, number: plan.page, chrome: chrome)
        let geometry = exercise.isExercise ? WorksheetPDFReader.geometry(of: exercise, on: page) : nil
        return WorksheetRenderer.Input(
            exercise: exercise.isExercise ? exercise : nil,
            geometry: geometry,
            answers: snapshot.answers,
            ink: WorksheetInkStore.read(snapshot.materialID, page: plan.page),
            outlinesGaps: snapshot.outlinesGaps,
            showsChecks: snapshot.showsChecks
        )
    }

    /// "Präpositionen-Artikel-bearbeitet.pdf" ("-geprueft" with the check marks), safe for any title.
    static func fileName(for title: String, checked: Bool = false) -> String {
        "\(DeckTransfer.fileStem(title, fallback: "uebungen"))-\(checked ? "geprueft" : "bearbeitet").pdf"
    }
}

// MARK: - Sharing

/// The finished homework for `ShareLink`. Rendered lazily by the share sheet and kept, so a target
/// that asks twice gets the same bytes without a second render.
nonisolated struct WorksheetDocument: Transferable, Sendable {
    let snapshot: WorksheetExport.Snapshot
    private let cache = RenderCache()

    init(snapshot: WorksheetExport.Snapshot) {
        self.snapshot = snapshot
    }

    var fileName: String { WorksheetExport.fileName(for: snapshot.title, checked: snapshot.showsChecks) }

    func data() throws -> Data {
        if let hit = cache.data { return hit }
        guard let made = WorksheetExport.pdf(snapshot) else { throw CocoaError(.fileWriteUnknown) }
        cache.data = made
        return made
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { document in
            try await Task.detached(priority: .userInitiated) { try document.data() }.value
        }
        .suggestedFileName { $0.fileName }
    }

    private final class RenderCache: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Data?
        var data: Data? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }
}
