//
//  ArticleTableBoardView.swift
//  german-ai-flashcards
//
//  Die Tabelle's two halves: the chart as the drill shell's hero (the question), and the forms as
//  tiles in its panel (the answer). Drag a tile into a cell, or tap a tile and then a cell — both
//  paths call `place`, because a drag is no answer for VoiceOver, for a trackpad, or for a thumb
//  on a four-column grid.
//
//  The grid and the tray are two subtrees of the shell, so the drag that joins them works in
//  `.global` coordinates and shares one `ArticleTableDrag`, which the module holds — the module is
//  built once per round (`GrammarDrillShell`'s `@State module`), so a reference on it lives exactly
//  as long as the board does. The lifted tile is drawn in the tray's own space, offset by the
//  tray's global origin, so it can follow a finger up over the chart.
//
//  Colour follows the table everywhere else in the app (`CaseEndingsTable`): a form wears its
//  gender's colour, the row label and the cell's ring wear the case's. A miss is never red — the
//  cell keeps the right form and strikes the wrong pick under it, the way `KasusFeedback` greys a
//  miss so red stays owned by „die“.
//

import SwiftUI

// MARK: - The shared drag

/// What the grid and the tray both need to know: where the open cells are on screen, what is in
/// the air, and what a tap has armed. Global coordinates throughout.
@Observable
final class ArticleTableDrag {
    var cellFrames: [KasusTableCell: CGRect] = [:]
    /// The form being dragged, and where the finger is.
    var lifted: String?
    var point: CGPoint = .zero
    /// The open cell under the finger.
    var over: KasusTableCell?
    /// The tap-to-place path: a tile is armed, and the next tap on an open cell places it.
    var selected: String?

    func reset() {
        lifted = nil
        over = nil
        selected = nil
    }
}

// MARK: - The chart

struct ArticleTableGridView: View {
    let board: ArticleTableBoard
    /// The cells this board has already had answered, from the round's picks.
    let placed: [KasusTableCell: ArticleTablePlaced]
    let drag: ArticleTableDrag
    let onPlace: (ArticleTablePlacement) -> Void

    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 5, verticalSpacing: 5) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(Gender.allCases) { gender in
                    HStack(spacing: 3) {
                        Image(systemName: gender.symbol)
                            .font(.caption2)
                        Text(gender.columnLabel)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(gender.color, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous))
                    .accessibilityLabel(gender.genderName)
                }
            }
            ForEach(GrammarCase.allCases) { kasus in
                GridRow {
                    rowLabel(kasus)
                    ForEach(Gender.allCases) { gender in
                        cell(KasusTableCell(kasus: kasus, genus: gender))
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.18), value: drag.over)
    }

    private func rowLabel(_ kasus: GrammarCase) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                Image(systemName: kasus.symbol)
                Text(kasus.short)
            }
            Text(kasus.short)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(kasus.color)
        .frame(width: 46, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kasus.name)
    }

    @ViewBuilder
    private func cell(_ cell: KasusTableCell) -> some View {
        let shape = RoundedRectangle(cornerRadius: appTheme.innerRadius(7), style: .continuous)
        let isOpen = board.isOpen(cell, placed: placed)
        let isOver = drag.over == cell
        Group {
            if let done = placed[cell] {
                answered(done, cell: cell)
            } else if isOpen {
                Text(" ")
                    .font(.title3)
            } else {
                // Context: a form the board gives, a notch back so the open cells lead the eye.
                Text(board.form(cell))
                    .font(.title3)
                    .foregroundStyle(cell.genus.color.opacity(colorScheme == .dark ? 0.62 : 0.55))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(background(cell, isOpen: isOpen, isOver: isOver), in: shape)
        .overlay {
            if isOpen {
                shape.strokeBorder(cell.kasus.color.opacity(isOver ? 1 : 0.45),
                                   style: StrokeStyle(lineWidth: isOver ? 2 : 1.5,
                                                      dash: isOver ? [] : [4, 3]))
            }
        }
        .scaleEffect(isOver ? 1.06 : 1)
        .contentShape(shape)
        .onTapGesture {
            guard let form = drag.selected, isOpen else { return }
            drag.selected = nil
            onPlace(ArticleTablePlacement(cell: cell, form: form))
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { drag.cellFrames[cell] = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(for: cell, isOpen: isOpen))
        .accessibilityHint(isOpen && drag.selected != nil ? "Places \(drag.selected ?? "")" : "")
        .accessibilityAddTraits(isOpen && drag.selected != nil ? .isButton : [])
    }

    /// A filled cell: the right form in its gender colour on the case's wash, with a wrong pick
    /// struck through beneath it.
    private func answered(_ done: ArticleTablePlaced, cell: KasusTableCell) -> some View {
        VStack(spacing: 0) {
            Text(done.answer)
                .font(.title3.weight(.semibold))
                .foregroundStyle(cell.genus.color)
            if !done.isRight {
                Text(done.pick)
                    .font(.caption2)
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func background(_ cell: KasusTableCell, isOpen: Bool, isOver: Bool) -> Color {
        if isOver { return cell.kasus.color.opacity(0.22) }
        if let done = placed[cell] { return done.isRight ? cell.kasus.color.opacity(0.14) : .primary.opacity(0.06) }
        return isOpen ? cell.kasus.color.opacity(0.05) : .clear
    }

    private func label(for cell: KasusTableCell, isOpen: Bool) -> String {
        let place = "\(cell.kasus.name), \(cell.genus.genderName)"
        if let done = placed[cell] {
            return done.isRight ? "\(place): \(done.answer)" : "\(place): \(done.answer). You placed \(done.pick)"
        }
        return isOpen ? "\(place): empty" : "\(place): \(board.form(cell))"
    }
}

// MARK: - The tray

struct ArticleTableTrayView: View {
    let board: ArticleTableBoard
    let placed: [KasusTableCell: ArticleTablePlaced]
    let drag: ArticleTableDrag
    let onPlace: (ArticleTablePlacement) -> Void

    @Environment(\.appTheme) private var appTheme

    /// The tray's own origin on screen, so the lifted tile can be placed from a global point.
    @State private var origin: CGPoint = .zero

    var body: some View {
        let stacks = board.tray
        // The lifted tile is an *overlay*, never a ZStack child: `position` takes every point its
        // parent offers, so a positioned child makes the tray greedy and the chart above it gets
        // squeezed off the screen mid-drag. An overlay is sized to the grid and draws outside it.
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6),
                                        count: stacks.count > 4 ? 3 : max(2, stacks.count)),
                         spacing: 6) {
            ForEach(stacks) { stack in
                let left = remaining(stack)
                // A stack that ever held more than one keeps its number all the way to 0:
                // „you have used all four der“ is part of what the table teaches.
                tile(form: stack.form, count: stack.count > 1 ? left : nil, lifted: false)
                    .opacity(left == 0 ? 0.3 : 1)
                    .scaleEffect(drag.lifted == stack.form ? 0.96 : 1)
                    .gesture(left == 0 ? nil : gesture(for: stack.form))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stack.form), \(left) left")
                    .accessibilityHint(left == 0 ? "" : "Taps to pick it up, then tap its cell")
                    .accessibilityAddTraits(drag.selected == stack.form ? [.isButton, .isSelected] : .isButton)
            }
        }
        .overlay(alignment: .topLeading) {
            if let form = drag.lifted {
                tile(form: form, count: nil, lifted: true)
                    .fixedSize()
                    .position(x: drag.point.x - origin.x, y: drag.point.y - origin.y)
                    .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
        .animation(.snappy(duration: 0.2), value: drag.selected)
        #if DEBUG
        .task { await applyDebugLift() }
        #endif
    }

    #if DEBUG
    /// `-kasus.debugTabelleLift der`: parks that tile in the air over the first open cell. This
    /// simulator cannot drag, and the drag is the one thing about this screen a screenshot of the
    /// resting state proves nothing about — a lifted tile once made the tray greedy and pushed
    /// the chart off the screen.
    private func applyDebugLift() async {
        guard let form = UserDefaults.standard.string(forKey: "kasus.debugTabelleLift"),
              board.tray.contains(where: { $0.form == form }) else { return }
        // The frames land with the first layout pass, which this task runs ahead of.
        try? await Task.sleep(for: .milliseconds(200))
        guard let cell = board.blanks.first(where: { board.isOpen($0, placed: placed) }),
              let frame = drag.cellFrames[cell] else { return }
        drag.lifted = form
        drag.point = CGPoint(x: frame.midX, y: frame.midY)
        drag.over = cell
    }
    #endif

    /// A form as a tile: no gender's colour on it, because the colour is the answer.
    private func tile(form: String, count: Int?, lifted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous)
        let isArmed = drag.selected == form
        return HStack(spacing: 5) {
            Text(form)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let count {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(maxWidth: lifted ? nil : .infinity, minHeight: 46)
        .background(.thinMaterial, in: shape)
        .overlay {
            shape.strokeBorder(isArmed ? Color.accentColor : .primary.opacity(0.18),
                               lineWidth: isArmed ? 2 : 1)
        }
        .shadow(color: .black.opacity(lifted ? 0.22 : 0), radius: lifted ? 8 : 0, y: lifted ? 4 : 0)
        .scaleEffect(lifted ? 1.1 : 1)
    }

    // MARK: Placing

    /// One gesture for both paths: a drag carries the tile and drops it, and a press that never
    /// moved is a tap that arms it.
    private func gesture(for form: String) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard moved(value) else { return }
                drag.lifted = form
                drag.point = value.location
                drag.over = cell(at: value.location)
                drag.selected = nil
            }
            .onEnded { value in
                let over = moved(value) ? cell(at: value.location) : nil
                let wasDrag = moved(value)
                drag.lifted = nil
                drag.over = nil
                if wasDrag {
                    if let over { place(form, on: over) }
                } else {
                    drag.selected = drag.selected == form ? nil : form
                }
            }
    }

    private func moved(_ value: DragGesture.Value) -> Bool {
        hypot(value.translation.width, value.translation.height) > 4
    }

    private func place(_ form: String, on cell: KasusTableCell) {
        guard board.isOpen(cell, placed: placed) else { return }
        drag.selected = nil
        onPlace(ArticleTablePlacement(cell: cell, form: form))
    }

    private func cell(at point: CGPoint) -> KasusTableCell? {
        drag.cellFrames.first { board.isOpen($0.key, placed: placed) && $0.value.contains(point) }?.key
    }

    /// What is left of a stack: every answered cell consumes one copy of its own form, right or
    /// wrong, so a count can never drift from the cells still open.
    private func remaining(_ stack: ArticleTile) -> Int {
        stack.count - placed.values.filter { $0.answer == stack.form }.count
    }
}

// MARK: - Previews

#Preview("Die Tabelle · board · 4 themes") {
    let board = ArticleTableBoard(chart: .definite, shape: .whole,
                                  blanks: ArticleChart.allCells, index: 0)
    let placed: [KasusTableCell: ArticleTablePlaced] = [
        KasusTableCell(kasus: .nominativ, genus: .der): .init(answer: "der", pick: "der"),
        KasusTableCell(kasus: .dativ, genus: .die): .init(answer: "der", pick: "dem"),
    ]
    let drag = ArticleTableDrag()
    return TabView {
        ForEach(AppTheme.allCases) { theme in
            VStack(spacing: 16) {
                ArticleTableGridView(board: board, placed: placed, drag: drag, onPlace: { _ in })
                Spacer()
                ArticleTableTrayView(board: board, placed: placed, drag: drag, onPlace: { _ in })
            }
            .padding()
            .background(ThemedBackground().ignoresSafeArea())
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
}
