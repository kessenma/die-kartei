#if os(macOS)
import SwiftUI

/// App ▸ Schreibhilfe, on the Mac. How to use the German writing helper: the Services menu items
/// that replace a selection in any app, and the floating panel for everything else. The Mac's
/// stand-in for the iPhone's Tastatur screen; there is nothing to switch on, only to learn.
struct MacWritingHelperSettingsView: View {
    @Environment(\.openURL) private var openURL

    @State private var unavailableReason = GermanWriting.unavailableReason

    var body: some View {
        Form {
            SettingsHeader(icon: "text.badge.checkmark", title: "Schreibhilfe · Writing helper")

            Section {
                Text("Select text in any app and turn it into German, or correct your own German, without leaving the app you're writing in. It runs on Apple Intelligence, on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .themedListRow()

            statusSection

            Section {
                SettingsStepRow(1, "Select the text in Mail, Notes, Safari or any app you write in.")
                SettingsStepRow(2, "Control-click it and choose Services, then Auf Deutsch (Sie), Auf Deutsch (du) or Deutsch korrigieren. The app's own menu has Services too.")
                SettingsStepRow(3, "The German replaces your selection. ⌘Z puts your text back.")
            } header: {
                Text("Use it").themedSectionHeader()
            } footer: {
                Text("Up to \(GermanWriting.inPlaceLimit.formatted()) characters are replaced in place. Longer text, and anything that can't finish cleanly, opens in the Schreibhilfe window instead, so your text is never lost.")
            }
            .themedListRow()

            Section {
                Text("A small window that stays on top of the app you're in: paste your text, watch the German arrive, then copy it. Open it from Edit ▸ Schreibhilfe… (⌥⌘D) or Services ▸ In der Schreibhilfe öffnen.")
                    .font(.callout)
                Button {
                    MacWritingHelper.shared.show()
                } label: {
                    Label("Open the Schreibhilfe", systemImage: "macwindow")
                }
            } header: {
                Text("The Schreibhilfe window").themedSectionHeader()
            }
            .themedListRow()

            Section {
                SettingsStepRow(1, "Open System Settings ▸ Keyboard, then Keyboard Shortcuts…")
                SettingsStepRow(2, "Choose Services, open Text, and give Auf Deutsch (Sie) a shortcut, such as ⌃⌥D.")
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        openURL(url)
                    }
                } label: {
                    Label("Open Keyboard Settings", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Add a shortcut").themedSectionHeader()
            }
            .themedListRow()

            Section {
                note("person.text.rectangle",
                     "Korrigieren keeps your own words and your Sie or du, and fixes only what's wrong: grammar, case endings, word order and spelling.")
                note("textformat",
                     "Plain text only: bold, links or pictures inside the selection come back as plain text.")
                note("lock.shield",
                     "Nothing leaves this Mac, and Die Kartei never reads your clipboard.")
                note("questionmark.circle",
                     "If the items aren't in the Services menu, open Die Kartei once, or log out and back in.")
            }
            .themedListRow()
        }
        .themedListScreen()
        .onAppear { unavailableReason = GermanWriting.unavailableReason }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            if let unavailableReason {
                Label {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(unavailableReason)
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                                openURL(url)
                            }
                        }
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } else {
                Label("Ready. Apple Intelligence is on.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .themedListRow()
    }

    private func note(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
