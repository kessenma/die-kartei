import SwiftUI

/// The Settings screen — a grouped list (App / Learning / Model / About) whose rows push to detail
/// screens. Replaces the old four-tab segmented switcher: the theme-upgrade IA gives app-level
/// settings a home and lands the theme picker at App ▸ Appearance. Every screen (root + each pushed
/// section) wears the same morphing `SettingsHeader`, so the header look Kyle likes is preserved —
/// now driven by navigation instead of segments.
struct SettingsView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Bumped by the tab bar when Settings is re-tapped while already active. Changing it
    /// re-identifies the NavigationStack below, popping any pushed sub-screen back to root.
    var resetToken: Int = 0

    /// A destination another screen asked for — the Home tutor card, an upgrade nudge. Cleared when
    /// the pushed screen pops, so asking for the same route twice pushes twice.
    ///
    /// Deliberately separate from `resetToken`: that one *rebuilds* this stack and would throw a
    /// pushed destination away, so a deep link must never touch it.
    @Binding var route: SettingsRoute?

    /// Trailing summary on the Appearance row — the current theme's name.
    @AppStorage(AppTheme.defaultsKey) private var appTheme: AppTheme = .klar

    var body: some View {
        NavigationStack {
            List {
                SettingsHeader(icon: "gearshape", title: "Settings")

                Section("App") {
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        row("Appearance", systemImage: "paintpalette", detail: appTheme.label)
                    }
                    NavigationLink {
                        ReminderSettingsView(modelManager: modelManager)
                    } label: {
                        row("Reminders", systemImage: "bell.badge", detail: reminderSummary)
                    }
                    NavigationLink {
                        VoiceSettingsView(modelManager: modelManager)
                    } label: {
                        row("Voice", systemImage: "waveform")
                    }
                    // Setup only: iOS gives an app no way to enable its own keyboard, so this
                    // screen explains where the switch lives and reports whether it's been flipped.
                    NavigationLink {
                        KeyboardSettingsView()
                    } label: {
                        row("Tastatur · Keyboard", systemImage: "keyboard",
                            detail: GermanKeyboard.summary)
                    }
                    NavigationLink {
                        GamificationSettingsView(modelManager: modelManager)
                    } label: {
                        row("Gamification", systemImage: "gamecontroller", detail: gamificationSummary)
                    }
                }
                .themedListRow()

                Section("Learning") {
                    // First, because the three screens under it all inherit their level from here.
                    NavigationLink {
                        LevelSettingsView(modelManager: modelManager)
                    } label: {
                        row("Your Level", systemImage: "figure.stairs", detail: levelSummary)
                    }
                    NavigationLink {
                        FlashcardsSettingsScreen(modelManager: modelManager)
                    } label: {
                        row("Flashcards", systemImage: "rectangle.stack")
                    }
                    NavigationLink {
                        ConversationSettingsScreen(modelManager: modelManager, mlxService: mlxService)
                    } label: {
                        row("Conversation", systemImage: "bubble.left.and.bubble.right")
                    }
                    NavigationLink {
                        StoriesSettingsScreen(modelManager: modelManager)
                    } label: {
                        row("Stories", systemImage: "book.pages")
                    }
                }
                .themedListRow()

                Section("Model") {
                    NavigationLink {
                        ModelSettingsScreen(modelManager: modelManager, mlxService: mlxService)
                    } label: {
                        HStack {
                            Label("Model & Downloads", systemImage: "cpu")
                            Spacer()
                            // Model status lives on this row: while a model downloads/loads, badge it
                            // — the same badge that appears on the Settings tab item.
                            if mlxService.isLoading {
                                DownloadBadge(progress: mlxService.downloadProgress)
                            }
                        }
                    }
                    // What the app holds and who holds it, plus the log of crashes and memory
                    // warnings — the place to look (and copy from) when the app closed by itself.
                    NavigationLink {
                        MemorySettingsView()
                    } label: {
                        row("Speicher · Memory", systemImage: "memorychip", detail: memorySummary)
                    }
                }
                .themedListRow()

                Section("About") {
                    // The same notes the launch sheet shows after an update, reachable any time.
                    NavigationLink {
                        WhatsNewView(current: WhatsNew.current)
                    } label: {
                        row("What's New", systemImage: "sparkles",
                            detail: WhatsNew.current.map { $0.isUnreleased ? "In progress" : "v\($0.version)" })
                    }
                    NavigationLink {
                        SourcesView()
                    } label: {
                        row("Sources & Credits", systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink {
                        FeedbackScreen(loadedModelName: mlxService.currentModel?.rawValue)
                    } label: {
                        row("Send Feedback", systemImage: "envelope")
                    }
                    // Straight to the App Store's write-review sheet. An explicit tap, so it skips
                    // every gate in `ReviewPromptService` — those throttle the *system* prompt.
                    Link(destination: ReviewPromptService.writeReviewURL) {
                        row("Rate on the App Store", systemImage: "star")
                    }
                }
                .themedListRow()

                // DEBUG and TestFlight only — an App Store build has no Developer section at all.
                if ScreenshotSeeding.isAvailable {
                    Section("Developer") {
                        NavigationLink {
                            DeveloperSettingsView()
                        } label: {
                            row("Screenshot Data", systemImage: "hammer",
                                detail: ScreenshotDataSeeder.seededAt == nil ? nil : "Seeded")
                        }
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.bottom, 120)
            // Keep last-loaded in sync regardless of which screen is showing.
            .onChange(of: mlxService.currentModel) { _, newModel in
                if let model = newModel {
                    modelManager.lastLoadedModel = model
                }
            }
            // The same destinations the rows above push, reachable by route. The rows stay: a deep
            // link is an extra door, not a replacement for the one people find by looking.
            .navigationDestination(item: $route) { destination in
                switch destination {
                case .model:
                    ModelSettingsScreen(modelManager: modelManager, mlxService: mlxService)
                case .cards:
                    FlashcardsSettingsScreen(modelManager: modelManager)
                case .memory:
                    MemorySettingsView()
                }
            }
        }
        // Re-tapping the Settings tab bumps `resetToken`, giving the stack a fresh identity and
        // tearing down any pushed sub-screen — returning to root Settings.
        .id(resetToken)
    }

    /// A plain settings row: leading icon + title, optional trailing grey summary.
    @ViewBuilder
    private func row(_ title: String, systemImage: String, detail: String? = nil) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if let detail {
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Trailing summary on the Your Level row — the anchor every level picker opens at.
    private var levelSummary: String {
        "\(modelManager.germanLevel.rawValue) · \(modelManager.germanLevel.englishLabel)"
    }

    /// Trailing summary on the Reminders row: "Off", or the enabled checkpoints shortest-first.
    private var reminderSummary: String {
        guard modelManager.practiceRemindersEnabled else { return "Off" }
        let checkpoints = modelManager.practiceReminderCheckpoints
        guard !checkpoints.isEmpty else { return "On" }
        return checkpoints.sorted().map(\.title).joined(separator: " · ")
    }

    /// Trailing summary on the Gamification row: "Off", or the daily goal.
    private var gamificationSummary: String {
        modelManager.gamificationEnabled ? "\(modelManager.dailyGoalMinutes) min/day" : "Off"
    }

    /// Trailing summary on the Speicher row: how many crashes stand in the log, or the event count.
    private var memorySummary: String? {
        let events = MemoryDiagnostics.events
        guard !events.isEmpty else { return nil }
        let crashes = events.filter { $0.kind == .unexpectedTermination || $0.kind == .crashReport }.count
        if crashes > 0 { return crashes == 1 ? "1 crash" : "\(crashes) crashes" }
        return events.count == 1 ? "1 event" : "\(events.count) events"
    }
}

// MARK: - Detail screens
//
// The Learning/Model settings bodies emit bare `Section`s — they were composed into one shared
// `Form` in the old segmented shell. Each detail screen now wraps them in its own `Form` behind a
// morphing `SettingsHeader`. (Reminders, Voice, Appearance, Sources bring their own containers.)

private struct FlashcardsSettingsScreen: View {
    @Bindable var modelManager: MLXModelManager
    var body: some View {
        Form {
            SettingsHeader(icon: "rectangle.stack", title: "Flashcards")
            CardSettingsView(modelManager: modelManager)
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConversationSettingsScreen: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    var body: some View {
        Form {
            SettingsHeader(icon: "bubble.left.and.bubble.right", title: "Conversation")
            ConversationSettingsView(modelManager: modelManager, mlxService: mlxService)
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StoriesSettingsScreen: View {
    @Bindable var modelManager: MLXModelManager
    var body: some View {
        Form {
            SettingsHeader(icon: "book.pages", title: "Stories")
            StorySettingsView(modelManager: modelManager)
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ModelSettingsScreen: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    var body: some View {
        Form {
            SettingsHeader(icon: "cpu", title: "Model")
            ModelSettingsView(modelManager: modelManager, mlxService: mlxService)
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FeedbackScreen: View {
    let loadedModelName: String?
    var body: some View {
        Form {
            SettingsHeader(icon: "envelope", title: "Feedback")
            FeedbackSection(loadedModelName: loadedModelName)
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}
