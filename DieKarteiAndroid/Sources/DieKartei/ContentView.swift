import SwiftUI

/// The Android app's tabs. Everything in them runs on files shared with the iOS app
/// (DieKarteiCore): the Goethe lists, the SM-2 scheduler, the grammar content and the games.
enum ContentTab: String, Hashable {
    case karten, wortschatz, grammatik, spiele
}

struct ContentView: View {
    @AppStorage("tab") var tab = ContentTab.karten

    var body: some View {
        TabView(selection: $tab) {
            Tab("Karten", systemImage: "bookmark", value: ContentTab.karten) {
                NavigationStack { KartenView() }
            }
            Tab("Wortschatz", systemImage: "list.bullet", value: ContentTab.wortschatz) {
                NavigationStack { WortschatzView() }
            }
            Tab("Grammatik", systemImage: "pencil", value: ContentTab.grammatik) {
                NavigationStack { GrammatikView() }
            }
            Tab("Spiele", systemImage: "star.fill", value: ContentTab.spiele) {
                NavigationStack { SpieleView() }
            }
        }
    }
}
