import SwiftUI

/// Settings ▸ Account ▸ iCloud Sync ▸ Sync-Bericht. What's waiting, and what iCloud said about it.
///
/// The screen above this one could only ever count: "Waiting to upload 1,143", "Can't sync 1,172".
/// The reason was in the store the whole time, one field per record, with nothing reading it. This
/// screen reads it, in every build — a sync that won't finish is exactly the thing you can't
/// reproduce on a Debug build.
struct SyncReportView: View {
    private var sync: SyncManager { SyncManager.shared }

    @State private var report = SyncReport()
    @State private var working = false
    @State private var didCopy = false

    var body: some View {
        Form {
            SettingsHeader(icon: "stethoscope", title: "Sync-Bericht")

            queueSection
            if !report.problems.isEmpty { problemsSection }
            if report.nothingToSend > 0 { nothingToSendSection }
            if !report.byKind.isEmpty { kindsSection }
            actionsSection
            if let coordinator = sync.coordinator, !coordinator.events.isEmpty { activitySection(coordinator) }
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copy()
                } label: {
                    Label(didCopy ? "Copied!" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(didCopy ? "Copied" : "Copy the report")
            }
        }
        .animation(.spring(duration: 0.3), value: didCopy)
        // Refreshed while the screen is up: a repair started here should visibly empty it.
        .task {
            while !Task.isCancelled {
                report = sync.coordinator?.report() ?? SyncReport()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Sections

    private var queueSection: some View {
        Section {
            LabeledContent("Waiting to upload", value: "\(report.waiting)")
            if report.waitingToDelete > 0 {
                LabeledContent("Waiting to delete", value: "\(report.waitingToDelete)")
            }
            if report.stuck > 0 {
                LabeledContent("Given up for now", value: "\(report.stuck)")
                    .foregroundStyle(.orange)
            }
            if report.heldForNewerVersion > 0 {
                LabeledContent("From a newer version", value: "\(report.heldForNewerVersion)")
            }
            if let error = sync.coordinator?.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("What's waiting").themedSectionHeader()
        } footer: {
            if report.waiting == 0 && report.waitingToDelete == 0 {
                Text("Nothing is owed to iCloud. This device is up to date.")
            } else if report.heldForNewerVersion > 0 {
                Text("Items from a newer version wait here until this device updates. They're safe meanwhile.")
            }
        }
        .themedListRow()
    }

    private var problemsSection: some View {
        Section {
            ForEach(report.problems) { problem in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(problem.explanation)
                        Spacer(minLength: 12)
                        Text("\(problem.records)")
                            .monospacedDigit()
                            .foregroundStyle(problem.givenUp ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                    Text(problem.kinds.prefix(4).map { "\($0.name) \($0.count)" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(problem.reason)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Why").themedSectionHeader()
        } footer: {
            Text("What iCloud said, grouped. An orange count has given up and waits for a repair; the rest are tried again by themselves.")
        }
        .themedListRow()
    }

    private var nothingToSendSection: some View {
        Section {
            Label("\(report.nothingToSend) items are marked as owed but have nothing to send.",
                  systemImage: "questionmark.circle")
                .font(.footnote)
                .foregroundStyle(.orange)
        } footer: {
            Text("Repair Sync works these out again. If it keeps happening, send the report.")
        }
        .themedListRow()
    }

    private var kindsSection: some View {
        Section {
            ForEach(report.byKind.prefix(12)) { line in
                LabeledContent(line.name, value: "\(line.count)").monospacedDigit()
            }
        } header: {
            Text("What's in the queue").themedSectionHeader()
        }
        .themedListRow()
    }

    private var actionsSection: some View {
        Section {
            Button {
                run { await sync.repair() }
            } label: {
                Label("Repair Sync", systemImage: "wrench.and.screwdriver")
            }
            .disabled(working || !sync.isRunning)
            if report.stuck > 0 {
                Button {
                    run {
                        sync.coordinator?.clearSendFailures()
                        await sync.syncNow()
                    }
                } label: {
                    Label("Try the given-up items again", systemImage: "arrow.clockwise")
                }
                .disabled(working)
            }
        } footer: {
            Text("A repair gives every item another try and checks the whole of iCloud again. Nothing is counted twice.")
        }
        .themedListRow()
    }

    private func activitySection(_ coordinator: SyncCoordinator) -> some View {
        Section {
            ForEach(coordinator.events.prefix(30), id: \.self) {
                Text($0).font(.caption.monospaced())
            }
        } header: {
            Text("Recent activity").themedSectionHeader()
        } footer: {
            Text("Since this launch, newest first.")
        }
        .themedListRow()
    }

    // MARK: Actions

    private func copy() {
        UIPasteboard.general.string = sync.coordinator?.reportText(report) ?? "Sync is off."
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        working = true
        Task {
            await action()
            report = sync.coordinator?.report() ?? SyncReport()
            working = false
        }
    }
}
