#if os(macOS)
import SwiftUI

/// The iPhone's full-screen covers (an activity, a chat, the web clipper, the onboarding wizard)
/// open in a window of their own on the Mac.
///
/// A sheet was the first stand-in, but a Mac sheet draws no toolbar, so a cover lost its own close
/// button, its title and its trailing buttons (a story's step bar, the Kasus-Check). In a window
/// all of them show as they do on the phone, and the window's close button, ⌘W and a screen's own
/// `dismiss()` all end the cover the same way.
///
/// How it fits together: `fullScreenCover` (MacCompat) registers the cover's view here and opens a
/// window of the `sceneID` group with its id; `MacCoverWindowRoot` shows that view. The view keeps
/// the environment of the screen that opened it (the model context, theme, routers, tutor
/// service), which a new scene would not otherwise have.
@MainActor @Observable
final class MacCoverRegistry {
    static let shared = MacCoverRegistry()
    static let sceneID = "cover"

    struct Entry {
        let content: AnyView
        /// The window went away (its close button, ⌘W, `dismiss()`): tell the opener.
        let onClose: () -> Void
    }

    private(set) var entries: [UUID: Entry] = [:]

    func register(_ content: AnyView, onClose: @escaping () -> Void) -> UUID {
        let id = UUID()
        entries[id] = Entry(content: content, onClose: onClose)
        return id
    }

    /// The opener closed the cover itself; the window closing after this reports nothing.
    func remove(_ id: UUID) {
        entries[id] = nil
    }

    /// The window closed. If the opener didn't close it, tell the opener now.
    func windowClosed(_ id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.onClose()
    }
}

/// The root of a cover window: the registered view, or nothing for a window whose cover is gone
/// (one the system tried to bring back, for instance), which closes itself.
struct MacCoverWindowRoot: View {
    let id: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let id, let entry = MacCoverRegistry.shared.entries[id] {
            entry.content
                .frame(minWidth: MacCompat.coverSize.width, minHeight: MacCompat.coverSize.height)
                .onDisappear { MacCoverRegistry.shared.windowClosed(id) }
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }
}

/// Shown over the screen that opened a cover window, while the window is open: the cover is
/// still in progress elsewhere, and the button brings it back to the front.
struct MacCoverPlaceholder: View {
    var bringToFront: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.background.opacity(0.85))
            VStack(spacing: 12) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Open in its own window")
                    .font(.headline)
                Button("Show Window", action: bringToFront)
                    .buttonStyle(.borderedProminent)
            }
        }
        .transition(.opacity)
    }
}
#endif
