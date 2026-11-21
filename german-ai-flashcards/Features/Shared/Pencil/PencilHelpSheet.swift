//
//  PencilHelpSheet.swift
//  german-ai-flashcards
//
//  The "?" on the Pencil rail: every Pencil gesture the writing surfaces understand, with the two
//  eraser gestures played as small loops. Built like `GestureHelpSheet`, whose demo card it
//  borrows; Reduce Motion shows each demo's end state instead of looping.
//

import SwiftUI

struct PencilHelpSheet<ScreenTips: View>: View {
    var accent: Color = .accentColor
    /// The screen's own rows: its paper, its settings.
    @ViewBuilder var screenTips: ScreenTips
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("These work wherever you write or draw with the Pencil.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    GestureDemoCard(
                        icon: "lasso",
                        title: "Circle a word to erase it",
                        caption: "With the eraser, draw a loop around a word. Everything inside the loop goes at once.",
                        accent: accent
                    ) {
                        CircleEraseDemo(accent: accent, reduceMotion: reduceMotion)
                    }

                    GestureDemoCard(
                        icon: "eraser",
                        title: "Rub out part of a word",
                        caption: "With the eraser, rub over the ink. Only what you touch goes, the rest of the word stays.",
                        accent: accent
                    ) {
                        RubOutDemo(accent: accent, reduceMotion: reduceMotion)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        PencilTipRow(symbol: "gearshape", title: "Einstellungen · Settings",
                                     detail: "The gear on the dock: what a squeeze does, the wrist guard's scrolling and pause, the finger taps, which edge the dock sits on, and the page's paper or notes margin.",
                                     accent: accent)
                        PencilTipRow(symbol: "applepencil.squeeze", title: "Drücken · Squeeze for the eraser",
                                     detail: "On Apple Pencil Pro, a squeeze switches between pen and eraser. In the gear it can instead undo, redo, change the colour or thickness, open the pen picker, or do nothing.",
                                     accent: accent)
                        PencilTipRow(symbol: "hand.tap", title: "Tap with two fingers to undo",
                                     detail: "Three fingers redo. The arrows on the dock do the same.",
                                     accent: accent)
                        PencilTipRow(symbol: "hand.raised.fill", title: "Handballen-Schutz · Wrist guard",
                                     detail: "The hand button on the dock. On: only the Pencil writes, and a hand resting on the glass can't write, scroll or tap. Off: a finger writes too. It turns on by itself the first time you use the Pencil.",
                                     accent: accent)
                        PencilTipRow(symbol: "arrow.up.and.down.and.arrow.left.and.right",
                                     title: "Moving around the page",
                                     detail: "Drag with two fingers to scroll, and pinch to zoom. With the wrist guard on, one finger does nothing, which is what keeps your hand from moving the page (the gear can make it one finger). A two-finger tap still undoes: a tap is two fingers that lift without moving.",
                                     accent: accent)
                        PencilTipRow(symbol: "pencil.tip", title: "Stifte · Pens, colours and thickness",
                                     detail: "Tap the pen on the dock again: Kugelschreiber (ballpoint), Füller (fountain pen), Bleistift (pencil) or Fineliner, in black, blue or red, fine to thick. On dark paper the black pen writes white, and there is yellow too.",
                                     accent: accent)
                        PencilTipRow(symbol: "eraser", title: "Radierer · Eraser size",
                                     detail: "Tap the eraser on the dock again for small, medium, large or huge.",
                                     accent: accent)
                        PencilTipRow(symbol: "highlighter", title: "Textmarker · Highlighter",
                                     detail: "Next to the pen: see-through marking in yellow, green, pink or blue. Tap it again for its colours and thickness. The check reads your handwriting, never the highlighting.",
                                     accent: accent)
                        screenTips
                        PencilTipRow(symbol: "hand.pinch", title: "Zoom in to write small",
                                     detail: "A long phrase in a short row: pinch in, write, then pinch back out to see the whole page.",
                                     accent: accent)
                        PencilTipRow(symbol: "arrow.up.and.down.and.arrow.left.and.right", title: "Die Leiste · Move the dock",
                                     detail: "Drag the dock by its handle to any edge: upright on the left or right, lying flat along the top or bottom.",
                                     accent: accent)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16), style: .continuous))
                }
                .padding()
            }
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .navigationTitle("Der Stift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDetents([.large])
        }
    }
}

/// One row of the tips: a symbol, a title (German · English) and a line of English.
struct PencilTipRow: View {
    let symbol: String
    let title: String
    let detail: String
    var accent: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Demo: circle to erase

private struct CircleEraseDemo: View {
    let accent: Color
    let reduceMotion: Bool

    @State private var drawn: CGFloat = 0
    @State private var erased = false

    var body: some View {
        HStack(spacing: 8) {
            Text("mit")
            Text("einem")
            Text("Brot")
                .opacity(erased ? 0 : 1)
                .overlay {
                    Ellipse()
                        .trim(from: 0, to: drawn)
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                        .padding(.horizontal, -12)
                        .padding(.vertical, -8)
                        .opacity(erased ? 0 : 1)
                }
        }
        .font(.title3.weight(.medium).italic())
        .task {
            if reduceMotion {
                drawn = 1
            } else {
                await loop()
            }
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            drawn = 0
            erased = false
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.easeInOut(duration: 1.0)) { drawn = 1 }
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation(.easeOut(duration: 0.35)) { erased = true }
            try? await Task.sleep(for: .seconds(1.4))
        }
    }
}

// MARK: - Demo: rub out part of a word

private struct RubOutDemo: View {
    let accent: Color
    let reduceMotion: Bool

    @State private var rubbed = false
    @State private var rubbing = false
    @State private var wiggle = false

    var body: some View {
        HStack(spacing: 0) {
            Text("Sal")
            Text("at")
                .opacity(rubbed ? 0.06 : 1)
                .overlay {
                    Image(systemName: "eraser.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                        .rotationEffect(.degrees(-30))
                        .offset(x: wiggle ? 9 : -9, y: -4)
                        .opacity(rubbing ? 1 : 0)
                }
        }
        .font(.title3.weight(.medium).italic())
        .task {
            if reduceMotion {
                rubbed = true
            } else {
                await loop()
            }
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            rubbed = false
            wiggle = false
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.easeOut(duration: 0.2)) { rubbing = true }
            withAnimation(.easeInOut(duration: 0.18).repeatCount(6, autoreverses: true)) { wiggle = true }
            withAnimation(.easeIn(duration: 1.0)) { rubbed = true }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.2)) { rubbing = false }
            try? await Task.sleep(for: .seconds(1.4))
        }
    }
}

extension PencilHelpSheet where ScreenTips == EmptyView {
    init(accent: Color = .accentColor) {
        self.init(accent: accent) { EmptyView() }
    }
}
