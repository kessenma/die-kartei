@testable import DieKarteiCore
import SwiftUI

/// The Android app's tabs. Each one runs on files shared with the iOS app (DieKarteiCore):
/// the Goethe word lists, `Gender` and `GrammarCase`.
enum ContentTab: String, Hashable {
    case wortschatz, karten, faelle
}

struct ContentView: View {
    @AppStorage("tab") var tab = ContentTab.wortschatz

    var body: some View {
        TabView(selection: $tab) {
            Tab("Wortschatz", systemImage: "list.bullet", value: ContentTab.wortschatz) {
                NavigationStack {
                    WortschatzView()
                }
            }
            Tab("Karten", systemImage: "bookmark", value: ContentTab.karten) {
                NavigationStack {
                    KartenView()
                }
            }
            Tab("Fälle", systemImage: "info.circle", value: ContentTab.faelle) {
                NavigationStack {
                    FaelleView()
                }
            }
        }
    }
}
