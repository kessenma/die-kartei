//
//  PencilFullScreen.swift
//  german-ai-flashcards
//
//  A Pencil page over the whole screen, and the hand-off that gets it there safely. Two canvases
//  must never hold one page's ink at once (each would save over the other), so:
//   1. `open()` first takes the inline canvas down (`inlineShown` turns false), which flushes its
//      ink to disk on the way out;
//   2. a beat later the cover opens, and its canvas reads that ink;
//   3. when the cover closes, a beat later `onReturn` runs (re-read anything held in `@State`) and
//      the inline canvas is built again (`token` changes its `.id`).
//
//      @State private var fullScreen = PencilHandOff()
//      …
//      if fullScreen.inlineShown { canvas.id(fullScreen.token) } else { placeholder }
//      Button("Full screen") { $fullScreen.open() }
//      .pencilFullScreen($fullScreen, onReturn: { ink = sheet.ink }) { MyCover() }
//
//  `PencilFullScreenPage` is the cover's frame: a bar with Done, the page's title, and whatever the
//  screen adds, over the canvas; no status bar.
//

import SwiftUI

struct PencilHandOff: Equatable {
    fileprivate(set) var isPresented = false
    fileprivate(set) var handingOff = false
    /// Bumped when the cover closes: the inline canvas's `.id`, so it is built again.
    fileprivate(set) var token = 0

    /// The inline canvas may be up: not while the cover is, or about to be.
    var inlineShown: Bool { !isPresented && !handingOff }
}

extension Binding where Value == PencilHandOff {
    /// Take the inline canvas down, then open the cover.
    @MainActor
    func open() {
        wrappedValue.handingOff = true
        DispatchQueue.main.async { wrappedValue.isPresented = true }
    }
}

extension View {
    /// The full-screen cover for a Pencil page, with the hand-off described above. On the Mac
    /// (where there is no canvas) it shows nothing.
    func pencilFullScreen<Cover: View>(_ handOff: Binding<PencilHandOff>,
                                       onReturn: @escaping () -> Void = {},
                                       @ViewBuilder cover: @escaping () -> Cover) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: Binding(get: { handOff.wrappedValue.isPresented },
                                             set: { handOff.wrappedValue.isPresented = $0 }),
                        onDismiss: {
                            // The cover's canvas saves as it goes down; read what it wrote, then rebuild.
                            DispatchQueue.main.async {
                                onReturn()
                                handOff.wrappedValue.token += 1
                                handOff.wrappedValue.handingOff = false
                            }
                        },
                        content: cover)
        #else
        self
        #endif
    }
}

/// The frame of a full-screen Pencil page: a bar (Done, the middle, the end) over the canvas.
struct PencilFullScreenPage<Middle: View, End: View, Canvas: View>: View {
    @ViewBuilder var middle: Middle
    @ViewBuilder var end: End
    @ViewBuilder var canvas: Canvas

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 8)
                middle
                Spacer(minLength: 8)
                end
            }
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)

            canvas
                .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
        #if os(iOS)
        .statusBarHidden()
        #endif
    }
}
