import SwiftUI
import SwiftData

/// Settings ▸ Developer. Exists only in DEBUG and TestFlight builds (`ScreenshotSeeding.isAvailable`
/// gates both this screen and the row that pushes it), and holds exactly one tool: the App Store
/// screenshot seeder.
///
/// The problem it solves: a fresh iPad has no `StudyDay` history, so the streak calendar, the
/// Lernpyramide and „Dein Weg" all correctly render as empty — there is nothing to photograph.
/// Filling replaces this device's progress with ten months of plausible study; the real data is
/// backed up first and Restore puts it back.
struct DeveloperSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var confirmingFill = false
    @State private var confirmingRestore = false
    @State private var isWorking = false
    @State private var status: String?
    @State private var seededAt: Date? = ScreenshotDataSeeder.seededAt

    var body: some View {
        List {
            SettingsHeader(icon: "hammer", title: "Developer")

            Section {
                Button {
                    confirmingFill = true
                } label: {
                    Label("Fill in screenshot data", systemImage: "wand.and.stars")
                }
                .disabled(isWorking)

                if seededAt != nil {
                    Button(role: .destructive) {
                        confirmingRestore = true
                    } label: {
                        Label("Restore my real data", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(isWorking)
                }
            } header: {
                Text("App Store screenshots").themedSectionHeader()
            } footer: {
                Text(footerText).font(.caption2)
            }
            .themedListRow()

            Section {
                Button {
                    run { WortschatzDebugSeeder.seed(in: modelContext) }
                } label: {
                    Label("Seed the Wortschatz box", systemImage: "archivebox")
                }
                .disabled(isWorking)

                if WortschatzDebugSeeder.hasBackup {
                    Button(role: .destructive) {
                        run { WortschatzDebugSeeder.restore(in: modelContext) ? "Wortschatz progress restored." : "Nothing to restore." }
                    } label: {
                        Label("Restore Wortschatz progress", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(isWorking)
                }

                Button {
                    run { WortschatzDebugSeeder.createLegacyDecks(in: modelContext) }
                } label: {
                    Label("Create the old per-level Goethe decks", systemImage: "square.stack.3d.up")
                }
                .disabled(isWorking)

                Button {
                    run { WortschatzDebugSeeder.rerunMerge(in: modelContext) }
                } label: {
                    Label("Re-run the Wortschatz merge", systemImage: "arrow.triangle.merge")
                }
                .disabled(isWorking)
            } header: {
                Text("Wortschatz").themedSectionHeader()
            } footer: {
                Text("Seed spreads the Goethe box over new, due, known and lapsed words (reversible). The old decks plus a re-run exercise the one-time merge.")
                    .font(.caption2)
            }
            .themedListRow()

            if isWorking || status != nil {
                Section {
                    if isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Working…").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else if let status {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .themedListRow()
            }

            Section {
                Text("""
                Filling writes the same records real study writes — study days, card intervals, \
                preposition streaks, quiz attempts, chat summaries — and lets the app derive the \
                streak, the pyramid, the badges and the journey from them the usual way. Nothing \
                on screen is drawn by hand, so the numbers agree with each other.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .themedListRow()
        }
        .navigationBarTitleDisplayMode(.inline)
        .themedListScreen()
        .confirmationDialog(
            "Fill in developer data for App Store screenshots?",
            isPresented: $confirmingFill,
            titleVisibility: .visible
        ) {
            Button("Fill in", role: .destructive) { fill() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
            This replaces your streak, your learner pyramid, your journey, your badges and your \
            coach profile with ten months of fake study, and adds three demo decks.

            Your real data is backed up on this device first, and "Restore my real data" puts it \
            back. Don't leave the app seeded — a real study session written on top of fake history \
            can't be separated out again.
            """)
        }
        .confirmationDialog(
            "Restore your real data?",
            isPresented: $confirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) { restore() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The demo decks, chats and study days go away, and everything from before the fill comes back. Anything you studied while the app was seeded is lost.")
        }
    }

    private var footerText: String {
        guard let seededAt else {
            return "A fresh device has no study history, so these three screens are empty. Fill them in, take the shots, then restore."
        }
        return "Seeded \(seededAt.formatted(date: .abbreviated, time: .shortened)). Restore before you study on this device again."
    }

    private func fill() {
        isWorking = true
        status = nil
        // A hop through the run loop so the spinner paints before the seeding blocks the main
        // actor — every write here is SwiftData on the main context, so it cannot move off it.
        DispatchQueue.main.async {
            let summary = ScreenshotDataSeeder.fill(in: modelContext)
            seededAt = ScreenshotDataSeeder.seededAt
            status = summary
            isWorking = false
        }
    }

    private func restore() {
        isWorking = true
        status = nil
        DispatchQueue.main.async {
            let restored = ScreenshotDataSeeder.restore(in: modelContext)
            seededAt = ScreenshotDataSeeder.seededAt
            status = restored ? "Your real data is back. Nothing seeded remains." : "Nothing to restore."
            isWorking = false
        }
    }

    /// One Wortschatz tool: spinner, run on the next turn of the run loop, report.
    private func run(_ work: @escaping () -> String) {
        isWorking = true
        status = nil
        DispatchQueue.main.async {
            status = work()
            isWorking = false
        }
    }
}
