import SwiftUI

/// The tab bar, the same four tabs as the iOS app's NavBar (Home, Grammar, Library, Settings).
/// Everything under them runs on files shared with the iOS app (DieKarteiCore): the Goethe lists,
/// the SM-2 scheduler, the grammar content, the Hören number engine and the games.
///
/// The icons are the nearest ones Android has: SF Symbols can't ship on Android, and SkipUI maps
/// only some of them to Material icons (house, checkmark.circle, bookmark and gearshape are
/// among them; iOS's checklist and brain.head.profile aren't).
enum MenuTab: String, Hashable {
    case home, grammar, library, settings
}

struct ContentView: View {
    /// A new key: the old five-tab bar stored "karten", "spiele", … under "tab".
    @AppStorage("menuTab") var tab = MenuTab.home
    /// Settings ▸ Appearance: "", "light" or "dark".
    @AppStorage("appearance") var appearance = ""

    var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: MenuTab.home) {
                NavigationStack { HomeView(openGrammar: { tab = .grammar }) }
            }
            Tab("Grammar", systemImage: "checkmark.circle", value: MenuTab.grammar) {
                NavigationStack { GrammatikView() }
            }
            Tab("Library", systemImage: "bookmark", value: MenuTab.library) {
                NavigationStack { LibraryView() }
            }
            Tab("Settings", systemImage: "gearshape", value: MenuTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .preferredColorScheme(colorScheme)
    }
}
