#if os(macOS)
import SwiftUI

/// How the Mac window navigates: a sidebar (the default), or the iPhone's bottom tab bar.
enum MacNavigationStyle: String {
    case sidebar, tabBar

    static let defaultsKey = "mac.navigationStyle"
}

/// One place the Mac sidebar goes. Home's six activity categories and its two goal cards sit in the
/// sidebar directly, so everything is one click away and Home itself is just For You.
enum MacDestination: String, CaseIterable, Identifiable, Hashable {
    case home
    case vocabulary, grammar, reading, speaking, listening, batch
    case deutschkurs, jobPrep
    case library

    enum Section: CaseIterable {
        case start, practice, goals, collection

        var title: String? {
            switch self {
            case .start, .collection: nil
            case .practice: "Üben · Practice"
            case .goals: "Ziele · Goals"
            }
        }

        var destinations: [MacDestination] { MacDestination.allCases.filter { $0.section == self } }
    }

    var id: String { rawValue }

    var section: Section {
        switch self {
        case .home: .start
        case .vocabulary, .grammar, .reading, .speaking, .listening, .batch: .practice
        case .deutschkurs, .jobPrep: .goals
        case .library: .collection
        }
    }

    /// The Home category this destination shows, for the six practice items.
    var category: ActivityCategory? {
        switch self {
        case .vocabulary: .vocabulary
        case .grammar: .grammar
        case .reading: .reading
        case .speaking: .speaking
        case .listening: .listening
        case .batch: .batch
        case .home, .deutschkurs, .jobPrep, .library: nil
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .deutschkurs: "Deutschkurs"
        case .jobPrep: "Job Prep"
        case .library: "Library"
        default: category?.title ?? rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .deutschkurs: "graduationcap"
        case .jobPrep: "briefcase"
        case .library: "brain.head.profile"
        default: category?.systemImage ?? "circle"
        }
    }

    /// ⌘1 … ⌘9, then ⌘0, in sidebar order.
    var shortcut: KeyEquivalent {
        let index = MacDestination.allCases.firstIndex(of: self) ?? 0
        return KeyEquivalent(Character(index < 9 ? "\(index + 1)" : "0"))
    }
}

/// The Mac window's navigation state, owned by the App so the menu bar can drive it too.
@MainActor @Observable
final class MacNavigator {
    var selection: MacDestination = .home
    /// Bumped when the current destination is chosen again: its stack pops back to its root.
    private(set) var resetTokens: [MacDestination: Int] = [:]
    /// File ▸ Import Deck… (⌘O).
    var showsDeckImporter = false

    func go(to destination: MacDestination) {
        if selection == destination {
            resetTokens[destination, default: 0] += 1
        } else {
            selection = destination
        }
    }

    func resetToken(for destination: MacDestination) -> Int { resetTokens[destination, default: 0] }
}
#endif
