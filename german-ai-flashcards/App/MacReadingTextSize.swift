#if os(macOS)
import SwiftUI

/// View ▸ Bigger Text / Smaller Text (⌘+ / ⌘−): the size of the German you read (chat messages,
/// stories, class notes, job postings), the way Mail and Books size their text on the Mac. Menus,
/// buttons and the rest of the window keep their size.
///
/// It scales the shared German text views (`SelectableGermanText`, `WrappedText`) through
/// `\.macReadingScale`. Whole-window zoom was tried and dropped: macOS ignores Dynamic Type, and
/// scaling the window's content broke its layout.
enum MacReadingTextSize {
    static let defaultsKey = "mac.readingTextSize"
    static let steps: [CGFloat] = [0.85, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]
    /// 1.3: the Mac's text styles run about a quarter smaller than the iPhone's (body 13 pt against
    /// 17 pt), and reading German at the Mac's size is a strain. This lands near the phone's size;
    /// Smaller Text still goes down to the Mac's own.
    static let defaultStep = 3

    static func clamped(_ step: Int) -> Int { min(max(step, 0), steps.count - 1) }

    /// ⌘= (the unshifted + key) makes text bigger too, as in Safari. A menu item carries only one
    /// key equivalent, so this catches the other one.
    @MainActor static func installEqualsKeyAlias() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers == "=" else { return event }
            let defaults = UserDefaults.standard
            let current = defaults.object(forKey: defaultsKey) as? Int ?? defaultStep
            defaults.set(clamped(current + 1), forKey: defaultsKey)
            return nil
        }
    }
}

/// Publishes the chosen reading size to a window's content.
struct MacReadingTextSizeModifier: ViewModifier {
    @AppStorage(MacReadingTextSize.defaultsKey) private var step = MacReadingTextSize.defaultStep

    func body(content: Content) -> some View {
        content.environment(\.macReadingScale, MacReadingTextSize.steps[MacReadingTextSize.clamped(step)])
    }
}

extension EnvironmentValues {
    /// How much larger than its text style the German reading text is drawn. 1 by default.
    @Entry var macReadingScale: CGFloat = 1
}
#endif
