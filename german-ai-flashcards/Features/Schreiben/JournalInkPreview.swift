//
//  JournalInkPreview.swift
//  german-ai-flashcards
//
//  A journal page's handwriting, rendered read-only: what the iPhone and the Mac show of a page
//  written on the iPad, and what the iPad shows above the keyboard once the ink has been read.
//  `PKDrawing` renders on every platform; only the canvas is iPad-only.
//

import SwiftUI
#if canImport(PencilKit)
import PencilKit
#endif

struct JournalInkPreview: View {
    let entryID: UUID
    let pageHeight: Int
    /// Bumped by the owner when the ink changed, so the picture is drawn again.
    var version: Int = 0
    var maxHeight: CGFloat = 220

    @State private var image: CGImage?

    var body: some View {
        // A real (zero-height) view while there is no picture yet: `.task` never fires on an
        // empty conditional, so the first render would never start.
        ZStack {
            if let image {
                ScrollView(.vertical) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: maxHeight)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25))
                }
                .accessibilityLabel("Your handwriting")
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: version) { await render() }
    }

    private func render() async {
        #if canImport(PencilKit)
        guard let data = JournalInkStore.read(entryID) else { image = nil; return }
        let height = CGFloat(max(pageHeight, JournalInkStore.initialHeight))
        let width = JournalInkStore.pageWidth
        image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
            // Only the part of the page that has ink on it, at half size.
            let bounds = drawing.bounds
            let area = CGRect(x: 0, y: max(0, bounds.minY - 16), width: width,
                              height: min(height, bounds.maxY + 16) - max(0, bounds.minY - 16))
            return WorksheetInkReader.inkOnWhite(drawing, area: area, scale: 0.5)
        }.value
        #else
        image = nil
        #endif
    }
}
