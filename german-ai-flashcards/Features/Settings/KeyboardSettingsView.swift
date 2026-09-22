import SwiftUI
import UIKit   // UIApplication.openSettingsURLString

/// App ▸ Tastatur. How to turn on the German writing keyboard, which lives in iOS Settings rather
/// than in this app: an extension can be installed by the app but only *enabled* by the user.
///
/// This screen is pure instruction plus a status read. There is no switch to flip here, because iOS
/// gives an app no way to enable its own keyboard — the closest thing to a control is the deep link
/// at the bottom, and even that only reaches this app's own Settings page.
struct KeyboardSettingsView: View {
    @Environment(\.openURL) private var openURL

    /// Re-read whenever the screen appears and whenever the app comes back from the foreground, so
    /// walking to Settings, switching the keyboard on, and walking back shows the change.
    @State private var status: GermanKeyboard.Status = .unknown

    var body: some View {
        Form {
            SettingsHeader(icon: "keyboard", title: "Tastatur · Keyboard")

            Section {
                Text("Write an email in English, and the keyboard turns it into natural German without leaving the app you're in. It runs on Apple Intelligence, on your phone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .themedListRow()

            statusSection

            Section {
                SettingsStepRow(1, "Open the Settings app, then tap General.",
                                image: "keyboard-guide-general")
                SettingsStepRow(2, "Tap Keyboard, then Keyboards at the top.",
                                image: "keyboard-guide-keyboards")
                SettingsStepRow(3, "Tap Add New Keyboard…",
                                image: "keyboard-guide-add-new")
                SettingsStepRow(4, "Under Third-Party Keyboards, tap Die Kartei.",
                                image: "keyboard-guide-pick-die-kartei")
            } header: {
                Text("Turn it on").themedSectionHeader()
            } footer: {
                Text("The keyboard only appears in this list after the app is installed. If it isn't there, reopen the app once and look again.")
            }
            .themedListRow()

            Section {
                SettingsStepRow(1, "Open any app you write in, such as Mail or Gmail, and tap into a message.",
                                image: "keyboard-guide-globe")
                SettingsStepRow(2, "Press and hold the globe key, then choose Die Kartei.")
            } header: {
                Text("Use it").themedSectionHeader()
            }
            .themedListRow()

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("It never asks for Full Access")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Most third-party keyboards ask you to switch on Allow Full Access, which lets them send what you type off the phone. This one does not request it, so iOS will not even offer the switch. It has no network access and cannot share anything with the rest of the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.green)
                }
            }
            .themedListRow()

            Section {
                Label {
                    Text("Password and other secure fields always use the built-in keyboard, and a few apps turn third-party keyboards off entirely. That's iOS protecting those fields, not a problem with the setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                }
            }
            .themedListRow()

            Section {
                Button {
                    // openSettingsURLString is the only Apple-sanctioned deep link: it opens this
                    // app's own page in Settings. There is no public way to open General ▸ Keyboard.
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("Opens this app's page in Settings. Tap back to reach the main list, then General ▸ Keyboard ▸ Keyboards.")
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { status = GermanKeyboard.status }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
        )) { _ in
            status = GermanKeyboard.status
        }
    }

    /// Shown only when iOS actually answered. `.unknown` says nothing rather than guessing wrong:
    /// claiming "not enabled" to someone who just enabled it would send them round the loop again.
    @ViewBuilder
    private var statusSection: some View {
        switch status {
        case .enabled:
            Section {
                Label {
                    Text("The keyboard is switched on. Tap the globe key in any app to reach it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            }
            .themedListRow()
        case .notEnabled:
            Section {
                Label {
                    Text("Not switched on yet. The steps below take about thirty seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }
            .themedListRow()
        case .unknown:
            EmptyView()
        }
    }
}

// MARK: - Status

/// The keyboard extension, as seen from the containing app.
enum GermanKeyboard {

    enum Status {
        case enabled
        case notEnabled
        /// iOS didn't answer. Treated as "say nothing", never as "not enabled".
        case unknown
    }

    /// Derived, not hardcoded, so it follows the app if the bundle ID ever changes. Must stay in
    /// lockstep with the extension target's `PRODUCT_BUNDLE_IDENTIFIER`.
    static var bundleIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "kyle-essenmacher.german-ai-flashcards") + ".keyboard"
    }

    /// Whether the user has added this keyboard in iOS Settings.
    ///
    /// `AppleKeyboards` is an undocumented defaults key holding the enabled keyboards' bundle IDs.
    /// It is a plain `UserDefaults` read, not a private API call, but it is not contractual: iOS may
    /// return nothing at all. Every failure path lands on `.unknown`, so the screen falls back to
    /// simply showing the steps rather than asserting something false.
    static var status: Status {
        guard let enabled = UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String],
              !enabled.isEmpty else {
            return .unknown
        }
        return enabled.contains(bundleIdentifier) ? .enabled : .notEnabled
    }

    /// Trailing summary for the Settings row, or `nil` when there is nothing trustworthy to say.
    static var summary: String? {
        switch status {
        case .enabled:    return "On"
        case .notEnabled: return "Not set up"
        case .unknown:    return nil
        }
    }
}
