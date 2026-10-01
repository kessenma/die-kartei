#if os(macOS)
import SwiftUI

/// The Mac menu bar: Go (⌘1–⌘0 to the sidebar's places), the navigation choices under View,
/// Import Deck… in File (it takes New Window's place: the app is one window), and What's New and
/// Send Feedback under Help.
struct MacCommands: Commands {
    var navigator: MacNavigator

    @AppStorage(MacNavigationStyle.defaultsKey) private var navigationStyle: MacNavigationStyle = .sidebar
    @AppStorage("mac.sidebarCompact") private var compactSidebar = false
    @AppStorage(MacReadingTextSize.defaultsKey) private var readingSize = MacReadingTextSize.defaultStep
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import Deck…") { navigator.showsDeckImporter = true }
                .keyboardShortcut("o")
        }

        CommandGroup(before: .toolbar) {
            // A submenu with a checkmark rather than "Show Tab Bar": that name belongs to the
            // system's window-tab command.
            Picker("Navigation", selection: $navigationStyle) {
                Text("Sidebar").tag(MacNavigationStyle.sidebar)
                Text("Tab Bar").tag(MacNavigationStyle.tabBar)
            }
            Button(compactSidebar ? "Expand Sidebar" : "Compact Sidebar") {
                withAnimation(.snappy) { compactSidebar.toggle() }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(navigationStyle != .sidebar)
            Divider()
            // The German you read: chat, stories, class notes, job postings.
            Button("Bigger Text") { readingSize = MacReadingTextSize.clamped(readingSize + 1) }
                .keyboardShortcut("+")
                .disabled(readingSize >= MacReadingTextSize.steps.count - 1)
            Button("Smaller Text") { readingSize = MacReadingTextSize.clamped(readingSize - 1) }
                .keyboardShortcut("-")
                .disabled(readingSize <= 0)
            // No ⌘0: that goes to Library in the Go menu.
            Button("Default Text Size") { readingSize = MacReadingTextSize.defaultStep }
                .disabled(readingSize == MacReadingTextSize.defaultStep)
            Divider()
        }

        CommandMenu("Go") {
            ForEach(MacDestination.Section.allCases, id: \.self) { section in
                ForEach(section.destinations) { destination in
                    Button(destination.title) {
                        navigationStyle = .sidebar
                        navigator.go(to: destination)
                    }
                    .keyboardShortcut(destination.shortcut)
                }
                if section != MacDestination.Section.allCases.last { Divider() }
            }
        }

        CommandGroup(replacing: .help) {
            Button("What's New in Die Kartei") { open(.whatsNew) }
            Button("Send Feedback…") { open(.feedback) }
        }
    }

    private func open(_ pane: SettingsPane) {
        MacSettingsSelection.shared.pane = pane
        openSettings()
    }
}

#endif
