//
//  EndingBlocksFlat.swift
//  german-ai-flashcards
//
//  The ending blocks without RealityKit, for Stills Only and Reduce Motion: the same word, the
//  same three colors (ink stem, case-colored ending, gender plate), drawn as text. A new ending
//  drops in from above and the old one leaves to the right; under Reduce Motion they only fade.
//  A wrong pick shows grey for a moment and shakes, the Kasus way of saying no without red.
//

import SwiftUI

struct EndingBlocksFlat: View {
    let state: EndingBlocksState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wrong: String?
    @State private var shakes: CGFloat = 0

    private static let font = Font.custom("Futura-Bold", size: 64, relativeTo: .largeTitle)

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(state.stem)
                    .foregroundStyle(EndingBlocksInk.stem)
                ZStack {
                    endingBlock(state.ending, color: EndingBlocksInk.ending(state.kasus), open: state.isOpen)
                        .id("\(state.ending)|\(state.kasus?.rawValue ?? "open")")
                        .transition(endingTransition)
                    if let wrong {
                        endingBlock(wrong, color: EndingBlocksInk.neutral, open: true)
                            .modifier(KasusShake(shakes: shakes))
                            .offset(y: -18)
                            .transition(.opacity)
                    }
                }
            }
            .font(Self.font)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            Capsule()
                .fill(GenderPalette.color(state.genus))
                .frame(height: 6)
                .padding(.horizontal, -10)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.62),
                   value: state)
        .onChange(of: state.rejected) { _, rejected in showWrong(rejected) }
    }

    @ViewBuilder
    private func endingBlock(_ ending: String, color: Color, open: Bool) -> some View {
        if ending.isEmpty {
            // The empty slot, a letter wide: dashed, so it reads as a place rather than a thing.
            Text("e")
                .hidden()
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(color, style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(color.opacity(open ? 0.08 : 0.16)))
                        .padding(.vertical, 6)
                }
        } else {
            Text(ending)
                .foregroundStyle(color)
        }
    }

    private var endingTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .offset(x: 30, y: -30).combined(with: .opacity)
        )
    }

    private func showWrong(_ rejected: String?) {
        guard let rejected, !reduceMotion else { wrong = nil; return }
        wrong = rejected
        shakes = 0
        withAnimation(.linear(duration: 0.4)) { shakes = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.55))
            withAnimation(.easeOut(duration: 0.2)) { wrong = nil }
        }
    }
}

#Preview("Flat blocks") {
    VStack(spacing: 24) {
        EndingBlocksFlat(state: .built(KasusFormParts(stem: "d", ending: "em"), kasus: .dativ, genus: .der))
        EndingBlocksFlat(state: .built(KasusFormParts(stem: "mein", ending: "en"), kasus: .akkusativ, genus: .der))
        EndingBlocksFlat(state: .built(KasusFormParts(stem: "kein", ending: ""), kasus: .nominativ, genus: .das))
        EndingBlocksFlat(state: .open(stem: "dies", genus: .die))
    }
    .frame(height: 500)
}
