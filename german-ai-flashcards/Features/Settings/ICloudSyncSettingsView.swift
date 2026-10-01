import SwiftUI

/// Settings ▸ Account ▸ iCloud Sync. There's no sign-in here: sync uses the Apple Account the
/// device is signed into. This screen says whether it's working, lets the learner sync or repair
/// now, and turns it off or deletes the iCloud copy.
struct ICloudSyncSettingsView: View {
    #if os(macOS)
    private static let settingsPath = "System Settings ▸ your name ▸ iCloud"
    private static let manageStorage = "Manage"
    private static let openSettingsTitle = "Open System Settings"
    #else
    private static let settingsPath = "Settings ▸ your name ▸ iCloud"
    private static let manageStorage = "Manage Account Storage"
    private static let openSettingsTitle = "Open Settings"
    #endif

    private var sync: SyncManager { SyncManager.shared }
    @Environment(\.openURL) private var openURL
    @State private var confirmingDelete = false
    @State private var deleteError: String?
    @State private var working = false
    /// What's in iCloud, by kind. Refreshed when a sync finishes.
    @State private var storage: [SyncStorageLine] = []

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
                Text("Your cards, progress, streak and study history follow you to every iPhone, iPad and Mac signed in to the same Apple Account. It's stored in your own iCloud, not on a server of ours.")
            }
            .themedListRow()

            if sync.accountSwitchPending { accountSwitchSection }

            if sync.isRunning, let coordinator = sync.coordinator {
                devicesSection(coordinator)
            }

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
                    if !coordinator.disagreement.isEmpty {
                        Label("Your devices still disagree after a repair. Try Repair Sync on each.",
                              systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Repair checks every item against iCloud and fetches everything again. It's safe any time: nothing is counted twice.")
                }
                .themedListRow()
            }

            storageSection

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
                Text("• Sign in to the same Apple Account on each device.\n• In \(Self.settingsPath), make sure Die Kartei is allowed.\n• Open the app on the other device so it can send its changes.")
                    .font(.footnote)
                Button(Self.openSettingsTitle) {
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
        .task(id: sync.coordinator?.lastSession?.finishedAt) {
            storage = sync.coordinator?.storageSummary() ?? []
        }
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
        if let coordinator = sync.coordinator {
            progressRows(coordinator)
        }
        if let notice = sync.notice {
            Text(notice).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Progress

    /// While syncing: how far the upload is, and what has come down so far. CloudKit doesn't say how
    /// much a download will bring, so receiving counts up. Afterwards: what the last sync moved.
    @ViewBuilder
    private func progressRows(_ coordinator: SyncCoordinator) -> some View {
        let activity = coordinator.activity
        if activity.sending, activity.sendTotal > 0 {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(min(activity.sent, activity.sendTotal)), total: Double(activity.sendTotal))
                Text("Sending \(activity.sent) of \(activity.sendTotal) · \(bytes(activity.sentBytes))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        if activity.receiving || (activity.isActive && activity.received > 0) {
            HStack(spacing: 8) {
                if activity.receiving { ProgressView().controlSize(.small) }
                Text("Receiving \(activity.received) items · \(bytes(activity.receivedBytes))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        if !activity.isActive, let last = coordinator.lastSession {
            Text("Last sync: " + moved(sent: last.sent, sentBytes: last.sentBytes,
                                       received: last.received, receivedBytes: last.receivedBytes))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    /// "12 sent (40 KB) · 3 received (8 KB)", leaving out a direction that moved nothing.
    private func moved(sent: Int, sentBytes: Int64, received: Int, receivedBytes: Int64) -> String {
        var parts: [String] = []
        if sent > 0 { parts.append("\(sent) sent (\(bytes(sentBytes)))") }
        if received > 0 { parts.append("\(received) received (\(bytes(receivedBytes)))") }
        return parts.isEmpty ? "already up to date" : parts.joined(separator: " · ")
    }

    private func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }

    // MARK: Storage

    /// What's in iCloud, by kind. Before anything has synced, the same list says what will.
    private var storageSection: some View {
        Section {
            if storage.isEmpty {
                ForEach(SyncCoordinator.storageCategories) { line in
                    Label(line.title, systemImage: line.symbol)
                }
            } else {
                LabeledContent("Total", value: bytes(storage.reduce(0) { $0 + $1.bytes }))
                    .fontWeight(.semibold)
                ForEach(storage) { line in
                    LabeledContent {
                        Text("\(line.records) · \(bytes(line.bytes))").monospacedDigit()
                    } label: {
                        Label(line.title, systemImage: line.symbol)
                    }
                }
            }
        } header: {
            Text(storage.isEmpty ? "What syncs" : "In your iCloud").themedSectionHeader()
        } footer: {
            Text("This lives in Die Kartei's private iCloud database, not in iCloud Drive, so it doesn't show up in the Files app. To see its size or remove it: \(Self.settingsPath) ▸ \(Self.manageStorage) ▸ Die Kartei. Downloaded models, voices, settings and the crash log stay on each device.")
        }
        .themedListRow()
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

    // MARK: Devices

    /// Every device's heartbeat: the visible sign of a device that stopped syncing or runs an
    /// older app.
    @ViewBuilder
    private func devicesSection(_ coordinator: SyncCoordinator) -> some View {
        let peers = coordinator.peers()
        if !peers.isEmpty {
            let mine = peers.first { $0.isThisDevice }?.appVersion
            Section {
                ForEach(peers) { peer in
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.isThisDevice ? "\(peer.model) (this one)" : peer.model)
                                if let synced = peer.lastSyncAt {
                                    Text("Synced \(synced, style: .relative) ago · \(peer.appVersion)")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(peer.appVersion).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: symbol(for: peer.model))
                        }
                        Spacer()
                        if !peer.isThisDevice, let mine, peer.appVersion != mine {
                            Text("Different version").font(.caption).foregroundStyle(.orange)
                        } else if peer.stuck > 0 {
                            Text("\(peer.stuck) stuck").font(.caption).foregroundStyle(.orange)
                        } else if peer.hasPending {
                            Text("Sending…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Your devices").themedSectionHeader()
            } footer: {
                Text("A device that runs an older version holds back what it can't read yet and catches up after it updates.")
            }
            .themedListRow()
        }
    }

    private func symbol(for model: String) -> String {
        switch model {
        case let m where m.hasPrefix("iPad"): "ipad"
        case let m where m.hasPrefix("iPhone"): "iphone"
        case let m where m.contains("Mac"): "laptopcomputer"
        default: "desktopcomputer"
        }
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
