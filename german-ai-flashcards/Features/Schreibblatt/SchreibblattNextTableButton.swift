//
//  SchreibblattNextTableButton.swift
//  german-ai-flashcards
//
//  "Nächste Tabelle": with the wrist guard on, a hand rests on the glass and a finger no longer
//  scrolls by itself, so moving on to the next writing table meant turning the guard off,
//  scrolling, and turning it back on. This pill at the bottom of the page does it in one tap: it
//  scrolls the next pass into view at the zoom the learner chose. On the last pass it turns into
//  "Fertig" where the page can finish the sheet (inline), and steps aside where it cannot (full
//  screen, whose bar has only Done).
//
//  Which table is next is `SchreibblattLayout.tableAfter` (Services/SchreibblattTableNav.swift);
//  the scrolling is `PencilBoard.reveal(sheetRect:)`.
//

import SwiftUI

extension View {
    /// The "Nächste Tabelle" pill over a sheet's canvas, shown while the wrist guard is on.
    func schreibblattNextTable(layout: SchreibblattLayout, board: PencilBoard,
                               onFinish: (() -> Void)? = nil) -> some View {
        modifier(SchreibblattNextTable(layout: layout, board: board, onFinish: onFinish))
    }
}

private struct SchreibblattNextTable: ViewModifier {
    let layout: SchreibblattLayout
    let board: PencilBoard
    let onFinish: (() -> Void)?

    /// The pass the button last brought into view, until the pen writes again: the stroke that
    /// was the current table's may still show as a sliver above the one just revealed.
    @State private var revealed: Int?
    /// On the last pass: the button finishes instead (or steps aside).
    @State private var atEnd = false

    private var shown: Bool {
        board.wristGuard && !board.isLocked && layout.writingTables.count > 1 && (!atEnd || onFinish != nil)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if shown {
                    pill
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: shown)
            .animation(.snappy(duration: 0.25), value: atEnd)
            .onChange(of: board.lastStroke) {
                revealed = nil
                refresh()
            }
            #if DEBUG
            // `-schreibblatt.debugNextTable <n>`: taps the pill n times, a second apart, since the
            // simulator can be driven by launch arguments but not by taps.
            .task {
                let taps = UserDefaults.standard.integer(forKey: "schreibblatt.debugNextTable")
                guard taps > 0 else { return }
                for _ in 0..<taps {
                    try? await Task.sleep(for: .seconds(1.5))
                    tap()
                    print("[schreibblatt] next table → \(revealed.map(String.init) ?? "none"), atEnd \(atEnd)")
                }
            }
            #endif
    }

    private var pill: some View {
        Button(action: tap) {
            Label(atEnd ? "Fertig" : "Nächste Tabelle",
                  systemImage: atEnd ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(SchreibblattTile.tint.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .foregroundStyle(SchreibblattTile.tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityHint(atEnd ? "Marks this sheet done" : "Scrolls the next table into view")
    }

    private func tap() {
        guard let visible = board.visibleSheetRect else { return }
        let writing = layout.writingTables
        let revealedTable = revealed.flatMap { pass in writing.first { $0.repetition == pass } }
            .flatMap { layout.revealRect(for: $0).intersects(visible) ? $0 : nil }
        // Still on the last pass (scrolled back since? then go on from there instead).
        if atEnd {
            let onLast = revealedTable.map { $0.repetition == writing.last?.repetition }
                ?? layout.isOnLastTable(visible: visible, lastStroke: board.lastStroke)
            if onLast {
                onFinish?()
                return
            }
            atEnd = false
        }
        let next: SchreibblattLayout.Table?
        if let revealedTable, let pass = revealedTable.repetition {
            next = writing.first { ($0.repetition ?? 0) > pass }
        } else {
            next = layout.tableAfter(visible: visible, lastStroke: board.lastStroke)
        }
        guard let next, let pass = next.repetition else {
            atEnd = true
            return
        }
        board.reveal(sheetRect: layout.revealRect(for: next))
        revealed = pass
        atEnd = pass == writing.last?.repetition
    }

    /// The pen wrote: on the last pass the button becomes Fertig, anywhere else it goes on.
    private func refresh() {
        guard let visible = board.visibleSheetRect else { return }
        atEnd = layout.isOnLastTable(visible: visible, lastStroke: board.lastStroke)
    }
}
