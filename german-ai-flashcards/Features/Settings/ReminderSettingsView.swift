import SwiftUI
import SwiftData
import UserNotifications

/// Opt-in "come back and practice" reminders. A master switch (off by default) plus an escalating
/// ladder of inactivity checkpoints — each enabled one fires a single local notification measured
/// from the learner's last practice, and practicing resets the whole ladder. The gaps grow, so the
/// reminders get less frequent the longer someone's been away rather than nagging every day.
struct ReminderSettingsView: View {
    @Bindable var modelManager: MLXModelManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    /// iOS-level permission was explicitly denied — scheduling silently no-ops, so we say so.
    @State private var systemNotificationsDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Practice reminders", isOn: $modelManager.practiceRemindersEnabled)
            } footer: {
                Text("A gentle nudge to keep your German going. Off by default, and every reminder resets the moment you practice.")
                    .font(.caption2)
            }

            if modelManager.practiceRemindersEnabled {
                if systemNotificationsDenied {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notifications are turned off for this app")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Reminders can't be delivered until you allow notifications in iOS Settings.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        } label: {
                            Label("Open Settings", systemImage: "arrow.up.right.square")
                        }
                    }
                }

                Section {
                    ForEach(ReminderCheckpoint.allCases) { checkpoint in
                        Toggle(checkpoint.title, isOn: checkpointBinding(checkpoint))
                    }
                } header: {
                    Text("Remind me if I haven't practiced in…")
                } footer: {
                    Text(checkpointsFooter)
                        .font(.caption2)
                }
            }
        }
        .navigationTitle("Practice Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAuthorizationState() }
        // Any change to the switch or the checkpoint set re-derives the scheduled ladder.
        .onChange(of: modelManager.practiceRemindersEnabled) { _, enabled in
            Task {
                if enabled { await LocalNotificationService.requestAuthorizationIfNeeded() }
                await refreshAuthorizationState()
                await PracticeReminderService.refresh(context: modelContext, modelManager: modelManager)
            }
        }
        .onChange(of: modelManager.practiceReminderCheckpointsRaw) { _, _ in
            Task { await PracticeReminderService.refresh(context: modelContext, modelManager: modelManager) }
        }
    }

    /// A per-checkpoint on/off binding backed by the manager's checkpoint set.
    private func checkpointBinding(_ checkpoint: ReminderCheckpoint) -> Binding<Bool> {
        Binding(
            get: { modelManager.practiceReminderCheckpoints.contains(checkpoint) },
            set: { isOn in
                var set = modelManager.practiceReminderCheckpoints
                if isOn { set.insert(checkpoint) } else { set.remove(checkpoint) }
                modelManager.practiceReminderCheckpoints = set
            }
        )
    }

    private var checkpointsFooter: String {
        guard !modelManager.practiceReminderCheckpoints.isEmpty else {
            return "Pick at least one interval so there's something to remind you about."
        }
        return "Each interval sends one reminder, timed from your last practice. Turn on several for a gentle escalating nudge that spaces out the longer you're away."
    }

    @MainActor
    private func refreshAuthorizationState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        systemNotificationsDenied = settings.authorizationStatus == .denied
    }
}
