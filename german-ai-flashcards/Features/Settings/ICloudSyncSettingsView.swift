import SwiftUI

/// Settings ▸ Account ▸ iCloud Sync. There's no sign-in here: sync uses the Apple Account the
/// device is signed into. This screen says whether it's working, lets the learner sync or repair
/// now, and turns it off or deletes the iCloud copy.
struct ICloudSyncSettingsView: View {
    private var sync: SyncManager { SyncManager.shared }
    @Environment(\.openURL) private var openURL
    @State private var confirmingDelete = false
    @State private var deleteError: String?
    @State private var working = false

    var body: some View {
        Form {
            SettingsHeader(icon: "icloud", title: "iCloud Sync")

            Section {
                Toggle("Sync with iCloud", isOn: Binding(
                    get: { sync.isEnabled && sync.refusalReason == nil },
                    set: { sync.setEnabled($0) }
                ))
                .disabled(sync.refusalReason != nil)
                statusRow
                #if DEBUG
                LabeledContent("Database", value: SyncManager.environmentName)
                    .font(.caption)
                #endif
            } footer: {
                Text("Your cards, progress, streak and study history follow you to every iPhone and iPad signed in to the same Apple Account. It's stored in your own iCloud, not on a server of ours.")
            }
            .themedListRow()

            if sync.accountSwitchPending { accountSwitchSection }

            if sync.isRunning, let coordinator = sync.coordinator {
                Section {
                    Button {
                        run { await sync.syncNow() }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(working)
                    Button {
                        run { await sync.repair() }
                    } label: {
                        Label("Repair Sync", systemImage: "wrench.and.screwdriver")
                    }
                    .disabled(working)
                    if coordinator.pendingCount > 0 {
                        LabeledContent("Waiting to upload", value: "\(coordinator.pendingCount)")
                    }
                    if coordinator.stuckCount > 0 {
                        LabeledContent("Can't sync", value: "\(coordinator.stuckCount)")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Repair checks every item against iCloud and fetches everything again. It's safe any time: nothing is counted twice.")
                }
                .themedListRow()
            }

            Section {
                Label("Flashcards and their review schedule", systemImage: "rectangle.stack")
                Label("Study days, streak and XP", systemImage: "flame")
                Label("Phrases you saved", systemImage: "text.quote")
            } header: {
                Text("What syncs").themedSectionHeader()
            } footer: {
                Text("Downloaded models, voices and the crash log stay on each device.")
            }
            .themedListRow()

            Section {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete iCloud Data", systemImage: "trash")
                }
                .disabled(working || !sync.isEnabled)
            } footer: {
                Text("Removes Die Kartei's data from iCloud for all your devices. What's on this device stays.")
            }
            .themedListRow()

            Section {
                Text("• Sign in to the same Apple Account on each device.\n• In Settings ▸ your name ▸ iCloud, make sure Die Kartei is allowed.\n• Open the app on the other device so it can send its changes.")
                    .font(.footnote)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } header: {
                Text("Not syncing?").themedSectionHeader()
            }
            .themedListRow()

            #if DEBUG
            if let coordinator = sync.coordinator, !coordinator.events.isEmpty {
                Section {
                    ForEach(coordinator.events, id: \.self) { Text($0).font(.caption.monospaced()) }
                } header: {
                    Text("Events").themedSectionHeader()
                }
                .themedListRow()
            }
            #endif
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task { await sync.refreshAccount() }
        .alert("Delete your iCloud data?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                run {
                    do { try await sync.deleteICloudData() } catch { deleteError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Die Kartei's copy in iCloud is removed for every device, and sync turns off. This device keeps everything it has.")
        }
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusRow: some View {
        let (symbol, text, tint) = status
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                if sync.isRunning, let last = sync.coordinator?.lastSyncedAt, !isBusy {
                    Text("Last synced \(last, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        if let notice = sync.notice {
            Text(notice).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var isBusy: Bool { sync.engineBusy || (sync.coordinator?.isSyncing ?? false) }

    private var status: (String, String, Color) {
        if let reason = sync.refusalReason { return ("exclamationmark.icloud", "Off. " + reason, .orange) }
        if !sync.isEnabled { return ("icloud.slash", "Off. This device's data stays here.", .secondary) }
        switch sync.account {
        case .noAccount: return ("person.crop.circle.badge.exclamationmark", "Sign in to iCloud in Settings to sync.", .orange)
        case .restricted: return ("lock.icloud", "iCloud is restricted on this device.", .orange)
        case .temporarilyUnavailable: return ("icloud.slash", "iCloud is unavailable for now. Changes wait here.", .orange)
        default: break
        }
        if sync.storageFull { return ("externaldrive.badge.exclamationmark", "iCloud storage is full. Free some space in Settings.", .orange) }
        if isBusy { return ("arrow.triangle.2.circlepath.icloud", "Syncing…", .accentColor) }
        return ("checkmark.icloud", "On", .green)
    }

    private var accountSwitchSection: some View {
        Section {
            Text("A different Apple Account is signed in on this device. Sync is paused so this device's progress doesn't mix into someone else's.")
                .font(.footnote)
            Button("Add this device's data to this account") {
                sync.resolveAccountSwitch(mergeIntoNewAccount: true)
            }
            Button("Keep this device separate (sync off)") {
                sync.resolveAccountSwitch(mergeIntoNewAccount: false)
            }
        } header: {
            Text("Different Apple Account").themedSectionHeader()
        }
        .themedListRow()
    }

    private func run(_ action: @escaping () async -> Void) {
        working = true
        Task {
            await action()
            working = false
        }
    }
}
