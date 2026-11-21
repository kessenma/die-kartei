//
//  SchreibblattCribSheet.swift
//  german-ai-flashcards
//
//  Spickzettel · Crib sheet: the sheet's words in a small table that floats over the page, so the
//  German is never a scroll back to the Vorlage away. iPad only, like the canvas it floats on.
//
//   • It follows the pen: the row the newest pen stroke landed in (`PencilBoard.lastStroke` →
//     `SchreibblattLayout.cell(at:)`) is marked, in whichever table it is, and the list scrolls to
//     keep it in view. Dots (an umlaut, an i) are too small to move it, so a dot drifting into the
//     row above does not.
//   • Dragged by its title strip only, so a Pencil writing near it never moves it; it stays where
//     it is let go, as a place in the free space (`schreibblatt.cribX`/`cribY`, 0 to 1), so it
//     stays on screen through rotation and full screen.
//   • Folded, it is two rows: the one being written and the next, which is the one to look up
//     after finishing a word.
//   • Closed with its ×; the top bar's button, the full-screen bar's and the dock's gear bring it
//     back (`schreibblatt.crib`, on by default).
//
//  An overlay on the canvas, inside the dock's strip, floated with `.offset` rather than laid out:
//  a positioned child would make the container claim all the space.
//
//  See docs/SCHREIBBLATT.md ▸ Spickzettel.
//

import SwiftUI

extension View {
    /// The crib sheet over a Schreibblatt canvas. Apply it to the canvas, before `.pencilRail`, so
    /// it floats over the page and never over the dock's strip.
    func schreibblattCribSheet(layout: SchreibblattLayout, board: PencilBoard) -> some View {
        modifier(SchreibblattCribSheet(layout: layout, board: board))
    }
}

enum SchreibblattCrib {
    /// Shown or not. On until the learner closes it.
    static let shownKey = "schreibblatt.crib"
    static let foldedKey = "schreibblatt.cribFolded"
    static let xKey = "schreibblatt.cribX"
    static let yKey = "schreibblatt.cribY"

    /// A stroke smaller than this both ways is a dot, not a letter: it does not move the mark.
    static let dotSize: CGFloat = 7
}

private struct SchreibblattCribSheet: ViewModifier {
    let layout: SchreibblattLayout
    let board: PencilBoard

    @AppStorage(SchreibblattCrib.shownKey) private var shown = true
    @AppStorage(SchreibblattCrib.foldedKey) private var folded = false
    /// Where the panel sits in the space it can move in: 0 is the leading/top edge, 1 the other.
    @AppStorage(SchreibblattCrib.xKey) private var unitX = 1.0
    @AppStorage(SchreibblattCrib.yKey) private var unitY = 0.0

    @State private var area: CGSize = .zero
    @State private var panelSize: CGSize = .zero
    /// While the title strip is dragged: the panel's top-left, following the finger.
    @State private var dragOrigin: CGPoint?
    @State private var dragStart: CGPoint = .zero
    /// The row the pen is on; nil until it writes in a table.
    @State private var row: Int?

    private static let margin: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { area = $0 }
            .overlay(alignment: .topLeading) {
                // A finished sheet is not being written on, so nothing needs looking up.
                if shown, !board.isLocked, !layout.words.isEmpty {
                    CribPanel(words: layout.words, row: row, folded: $folded,
                              maxListHeight: max(120, area.height * 0.55),
                              onDrag: drag, onDragEnd: drop, onClose: close)
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { panelSize = $0 }
                        .offset(x: origin.x, y: origin.y)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: shown)
            .onChange(of: board.lastStroke) { _, stroke in follow(stroke) }
    }

    // MARK: Following the pen

    private func follow(_ stroke: CGRect?) {
        guard let stroke,
              stroke.width >= SchreibblattCrib.dotSize || stroke.height >= SchreibblattCrib.dotSize,
              let cell = layout.cell(at: CGPoint(x: stroke.midX, y: stroke.midY)),
              cell.row != row
        else { return }
        withAnimation(.easeOut(duration: 0.15)) { row = cell.row }
    }

    // MARK: Placing it

    /// The room the panel's top-left can move in, inside the margins.
    private var room: CGSize {
        CGSize(width: max(0, area.width - panelSize.width - Self.margin * 2),
               height: max(0, area.height - panelSize.height - Self.margin * 2))
    }

    private var origin: CGPoint {
        if let dragOrigin { return clamped(dragOrigin) }
        return CGPoint(x: Self.margin + room.width * unitX, y: Self.margin + room.height * unitY)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, Self.margin), Self.margin + room.width),
                y: min(max(point.y, Self.margin), Self.margin + room.height))
    }

    private func drag(_ value: DragGesture.Value) {
        if dragOrigin == nil { dragStart = origin }
        dragOrigin = CGPoint(x: dragStart.x + value.translation.width, y: dragStart.y + value.translation.height)
    }

    private func drop(_ value: DragGesture.Value) {
        let landed = clamped(CGPoint(x: dragStart.x + value.translation.width,
                                     y: dragStart.y + value.translation.height))
        unitX = room.width > 0 ? Double((landed.x - Self.margin) / room.width) : 0
        unitY = room.height > 0 ? Double((landed.y - Self.margin) / room.height) : 0
        dragOrigin = nil
    }

    private func close() {
        shown = false
        board.announce("Spickzettel aus · Crib sheet off. The list button brings it back.",
                       symbol: "list.bullet.rectangle")
    }
}

// MARK: - The panel

private struct CribPanel: View {
    let words: [SchreibblattWord]
    let row: Int?
    @Binding var folded: Bool
    let maxListHeight: CGFloat
    let onDrag: (DragGesture.Value) -> Void
    let onDragEnd: (DragGesture.Value) -> Void
    let onClose: () -> Void

    @State private var listHeight: CGFloat = 0

    private static let width: CGFloat = 310
    private var accent: Color { SchreibblattTile.tint }

    var body: some View {
        VStack(spacing: 0) {
            titleStrip
            Divider()
            if folded {
                VStack(spacing: 0) {
                    ForEach(foldedRows, id: \.self) { index in
                        wordRow(index)
                        if index != foldedRows.last { rule }
                    }
                }
            } else {
                list
            }
        }
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spickzettel, crib sheet")
    }

    /// The row being written and the next one: after a word, the next is the one to look up.
    private var foldedRows: [Int] {
        let current = min(row ?? 0, words.count - 1)
        return current + 1 < words.count ? [current, current + 1] : [current]
    }

    // MARK: Title strip (the handle)

    private var titleStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 0) {
                Text("Spickzettel")
                    .font(.subheadline.weight(.semibold))
                Text(row.map { "Crib sheet · \($0 + 1) of \(words.count)" } ?? "Crib sheet · drag to move")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { folded.toggle() }
            } label: {
                Image(systemName: folded ? "chevron.down" : "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(folded ? "Show every word" : "Fold to the word being written")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close the crib sheet")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        // Global space: the panel moves under the finger, so its own space would move too.
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged(onDrag)
            .onEnded(onDragEnd))
    }

    // MARK: The words

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(words.indices, id: \.self) { index in
                        wordRow(index)
                            .id(index)
                        if index < words.count - 1 { rule }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(listHeight, 1), maxListHeight))
            .onChange(of: row) { _, row in
                guard let row, listHeight > maxListHeight else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(row, anchor: .center) }
            }
        }
    }

    /// Plain colours, not `.secondary` or `Divider`: hierarchical styles over the material are drawn
    /// vibrant, and inside the scroll view that vibrancy has nothing to blend with and vanishes.
    private static let secondaryInk = Color.primary.opacity(0.6)

    private var rule: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 0.5)
            .padding(.leading, 10)
    }

    private func wordRow(_ index: Int) -> some View {
        let word = words[index]
        let isCurrent = index == row
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(word.english)
                .font(.caption)
                .foregroundStyle(Self.secondaryInk)
                .lineLimit(2)
                .frame(width: 96, alignment: .leading)
            Text(word.german)
                .font(.callout.weight(isCurrent ? .semibold : .medium))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isCurrent ? accent.opacity(0.18) : .clear)
        .overlay(alignment: .leading) {
            if isCurrent {
                accent.frame(width: 3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
