import Foundation
import UIKit

/// One bullet on the What's New screen.
struct WhatsNewHighlight: Decodable, Identifiable {
    let title: String
    let detail: String?
    let symbol: String?

    /// Titles are unique within a release; `scripts/whats_new.py check` enforces it.
    var id: String { title }

    /// The SF Symbol to draw: the named one when this OS has it, `sparkles` otherwise, so a typo in
    /// the JSON costs an icon rather than a blank slot.
    var resolvedSymbol: String {
        if let symbol, UIImage(systemName: symbol) != nil { return symbol }
        return "sparkles"
    }
}

/// One shipped version (or the in-progress bucket) and its bullets.
struct WhatsNewRelease: Decodable, Identifiable {
    static let unreleasedVersion = "unreleased"

    let version: String
    /// `YYYY-MM-DD`, stamped by deploy. Absent on the `unreleased` entry.
    let date: String?
    let highlights: [WhatsNewHighlight]

    var id: String { version }
    var isUnreleased: Bool { version == Self.unreleasedVersion }

    var displayTitle: String {
        isUnreleased ? "In Arbeit · In progress" : "Version \(version)"
    }

    /// "5 Sep 2026" from the stamped date, or nil.
    var displayDate: String? {
        guard let date, let parsed = Self.parser.date(from: date) else { return nil }
        return parsed.formatted(date: .abbreviated, time: .omitted)
    }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct WhatsNewFile: Decodable {
    let releases: [WhatsNewRelease]
}

/// THE STANDARD FOR RELEASE NOTES, any change, any time (the long form is in `/CLAUDE.md`):
/// 1. Add ONE highlight per learner-visible change to the top `"unreleased"` entry of
///    `Resources/whats_new.json`, creating that entry if it's missing.
/// 2. Never write a version or a date. `scripts/deploy.py` renames `unreleased` to the shipping
///    marketing version, merges later bullets into it across TestFlight builds of that version,
///    and sends the same text to TestFlight and to the App Store's What's New field.
/// Nothing in the app writes the file; this type only reads it and remembers what was shown.
enum WhatsNew {
    /// Newest first. In Release builds the `unreleased` entry is dropped even if an archive made
    /// outside `deploy.py` shipped it; in Debug it stays as a preview of what the next version will
    /// say.
    static let releases: [WhatsNewRelease] = {
        guard let url = Bundle.main.url(forResource: "whats_new", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        guard let file = try? JSONDecoder().decode(WhatsNewFile.self, from: data) else {
            assertionFailure("whats_new.json is present but undecodable — run scripts/whats_new.py check")
            return []
        }
        #if DEBUG
        return file.releases
        #else
        return file.releases.filter { !$0.isUnreleased }
        #endif
    }()

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// The release to show expanded.
    ///
    /// Debug ignores the bundle version on purpose: the Debug configuration's marketing version
    /// lags Release (it says 1.2, a real past release), and syncing the pbxproj for a preview isn't
    /// worth the churn. The top entry is what a developer wants to see anyway.
    static var current: WhatsNewRelease? {
        #if DEBUG
        return releases.first
        #else
        return releases.first { $0.version == currentVersion }
        #endif
    }

    // MARK: - Launch-sheet memory

    private static let lastSeenKey = "whatsNew.lastSeenVersion"

    static func markSeen() {
        UserDefaults.standard.set(currentVersion, forKey: lastSeenKey)
    }

    /// The release worth raising at launch, or nil.
    ///
    /// Non-nil only for an *existing* install seeing a *new* marketing version that has notes in
    /// the bundle. Every nil path stamps the current version as seen, so the question is asked once
    /// per version and never again. The caller stamps on the non-nil path before presenting, the
    /// same discipline as `ModelSupersession.markUpdateSheetSeen()`.
    ///
    /// - `isFreshInstall`: the onboarding wizard is about to run. A brand-new user has nothing to
    ///   compare against, so they get the version stamped silently and no sheet.
    /// - A stored key of nil on an existing install means "updated to the first build that has this
    ///   feature", which is exactly an update, so it shows.
    static func launchPrompt(isFreshInstall: Bool) -> WhatsNewRelease? {
        #if DEBUG
        if debugForced { return current }
        #endif
        if isFreshInstall {
            markSeen()
            return nil
        }
        let stored = UserDefaults.standard.string(forKey: lastSeenKey)
        if stored == currentVersion { return nil }
        guard let current else {
            markSeen()  // a build with no entry for its own version: stay quiet, don't nag later
            return nil
        }
        return current
    }

    #if DEBUG
    /// `-whatsNew.debugForce 1` clears the seen key and raises the sheet on launch, even on a fresh
    /// simulator where the wizard would otherwise win:
    ///
    ///     xcrun simctl launch <udid> kyle-essenmacher.german-ai-flashcards -whatsNew.debugForce 1
    ///
    /// The real path needs an app update to detect, which a simulator install never is. One
    /// presenting arg per launch: combined with `-review.debugForce`, `-placement.debugOpenReview`
    /// or `-level.debugOpenLevel` the second presentation is dropped. DEBUG builds only.
    private static var debugForced = false

    static func applyDebugLaunchArgumentIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "whatsNew.debugForce") else { return }
        UserDefaults.standard.removeObject(forKey: lastSeenKey)
        debugForced = true
    }
    #endif
}
