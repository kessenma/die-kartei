import SwiftUI

/// A destination inside the Settings tab that another screen can ask for.
///
/// One case today. It's an enum rather than a `Bool` because the follow-up work — making the ten
/// scattered "go to Settings → Model" hints tappable — will want `.level`, `.reminders` and friends,
/// and widening an enum is cheaper than replacing a flag.
enum SettingsRoute: Hashable {
    /// Settings ▸ Model & Downloads.
    case model
    /// Settings ▸ Cards — the flashcard and Wortschatz settings.
    case cards
    /// Settings ▸ Speicher — memory readings and the crash/memory log.
    case memory
}

/// Lets any screen ask to be taken to a Settings destination.
///
/// Lives in the environment next to `ActivityRouter` so a nudge buried in a sheet can point
/// somewhere real without threading a closure through every view between it and `ContentView`.
/// Until this existed there was no way to reach Model & Downloads programmatically at all: the row
/// is a plain `NavigationLink`, and the only handle on the Settings stack was `settingsResetToken`,
/// which pops to root — the opposite of a deep link.
@Observable
final class SettingsRouter {
    /// Set to push; `SettingsView` clears it when the destination pops, so setting the same route
    /// twice in a row pushes twice.
    var route: SettingsRoute?
}
