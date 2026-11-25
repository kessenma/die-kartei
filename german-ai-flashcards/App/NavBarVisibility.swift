//
//  NavBarVisibility.swift
//  german-ai-flashcards
//
//  Drawing mode: a screen that wants the whole height (a Pencil page) asks the shell to take the
//  bottom NavBar away while it is up. The shell slides the bar off, stops it taking touches and
//  lets the tabs run to the screen's bottom edge; leaving the screen brings it back.
//
//  A screen holds the bar down with `.hidesNavBar()`: a hold is taken on appear and given back on
//  disappear. Holds are kept per tab, because a tab that is not selected stays mounted (at opacity
//  0) with its screens still on its stack: a hold only counts on the tab it was taken on, so a
//  deep link that switches tabs never leaves the bar missing from the wrong one.
//
//  See docs/SCHREIBBLATT.md ▸ Pencil surface.
//

import Observation
import SwiftUI

@MainActor
@Observable
final class NavBarVisibility {
    private var holds: [UUID: MenuTab] = [:]

    /// The bar is held down on `tab`.
    func isHidden(on tab: MenuTab) -> Bool {
        holds.values.contains(tab)
    }

    func hold(_ id: UUID, on tab: MenuTab) {
        holds[id] = tab
    }

    func release(_ id: UUID) {
        holds[id] = nil
    }
}

extension EnvironmentValues {
    /// The shell's visibility object; nil outside the tab shell (a cover, a sheet, a preview,
    /// the Mac's sidebar), where there is no bar to hide.
    @Entry var navBarVisibility: NavBarVisibility?
    /// The tab a view lives on, set by the shell on each tab's root.
    @Entry var shellTab: MenuTab?
}

extension View {
    /// Take the bottom NavBar away while this view is on screen.
    func hidesNavBar() -> some View {
        modifier(HidesNavBar())
    }
}

private struct HidesNavBar: ViewModifier {
    @Environment(\.navBarVisibility) private var visibility
    @Environment(\.shellTab) private var tab
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard let visibility, let tab else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { visibility.hold(id, on: tab) }
            }
            .onDisappear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { visibility?.release(id) }
            }
    }
}
