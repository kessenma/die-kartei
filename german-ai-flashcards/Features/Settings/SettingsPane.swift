import SwiftUI

/// One screen under Settings: its group, title, icon, one-line summary and destination.
///
/// Listed once so the iPhone's Settings list and the Mac's Settings window can't drift apart: a new
/// setting is a new case here, and both show it.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    // There's no sign-in: sync rides on the device's Apple Account. The row says whether it's on;
    // the screen behind it says why not and what to do.
    case sync
    case appearance, reminders, voice
    // Setup only: iOS gives an app no way to enable its own keyboard, so this screen explains where
    // the switch lives and reports whether it's been flipped. The Mac has no keyboard extension.
    case keyboard
    case gamification
    // First in Learning, because the three screens under it all inherit their level from here.
    case level, flashcards, conversation, stories
    // Model status lives on the model row: while a model downloads or loads, it carries the same
    // badge as the Settings tab. Speicher is what the app holds, plus the log of crashes and memory
    // warnings: the place to look (and copy from) when the app closed by itself.
    case model, memory
    case whatsNew, sources, feedback
    // DEBUG and TestFlight only; an App Store build has no Developer section at all.
    case developer

    enum Group: String, CaseIterable, Identifiable {
        case account = "Account", app = "App", learning = "Learning", model = "Model"
        case about = "About", developer = "Developer"
        var id: String { rawValue }
    }

    var id: String { rawValue }

    var group: Group {
        switch self {
        case .sync: .account
        case .appearance, .reminders, .voice, .keyboard, .gamification: .app
        case .level, .flashcards, .conversation, .stories: .learning
        case .model, .memory: .model
        case .whatsNew, .sources, .feedback: .about
        case .developer: .developer
        }
    }

    var title: String {
        switch self {
        case .sync: "iCloud Sync"
        case .appearance: "Appearance"
        case .reminders: "Reminders"
        case .voice: "Voice"
        case .keyboard: "Tastatur · Keyboard"
        case .gamification: "Gamification"
        case .level: "Your Level"
        case .flashcards: "Flashcards"
        case .conversation: "Conversation"
        case .stories: "Stories"
        case .model: "Model & Downloads"
        case .memory: "Speicher · Memory"
        case .whatsNew: "What's New"
        case .sources: "Sources & Credits"
        case .feedback: "Send Feedback"
        case .developer: "Screenshot Data"
        }
    }

    var systemImage: String {
        switch self {
        case .sync: "icloud"
        case .appearance: "paintpalette"
        case .reminders: "bell.badge"
        case .voice: "waveform"
        case .keyboard: "keyboard"
        case .gamification: "gamecontroller"
        case .level: "figure.stairs"
        case .flashcards: "rectangle.stack"
        case .conversation: "bubble.left.and.bubble.right"
        case .stories: "book.pages"
        case .model: "cpu"
        case .memory: "memorychip"
        case .whatsNew: "sparkles"
        case .sources: "doc.text.magnifyingglass"
        case .feedback: "envelope"
        case .developer: "hammer"
        }
    }

    /// Whether this pane exists on this platform and in this build.
    var isAvailable: Bool {
        switch self {
        case .keyboard: !ThisDevice.isMac
        case .developer: ScreenshotSeeding.isAvailable
        default: true
        }
    }

    static func panes(in group: Group) -> [SettingsPane] {
        allCases.filter { $0.group == group && $0.isAvailable }
    }

    /// The pane a deep link asks for.
    init(route: SettingsRoute) {
        switch route {
        case .model: self = .model
        case .cards: self = .flashcards
        case .memory: self = .memory
        case .sync: self = .sync
        }
    }

    // MARK: - Summaries

    /// The short grey text at the end of the row, or nil for none.
    @MainActor
    func summary(modelManager: MLXModelManager, appTheme: AppTheme) -> String? {
        switch self {
        case .sync:
            let sync = SyncManager.shared
            guard sync.isEnabled, sync.refusalReason == nil else { return "Off" }
            if sync.account == .noAccount { return "Not signed in" }
            return sync.engineBusy ? "Syncing…" : "On"
        case .appearance:
            return appTheme.label
        case .reminders:
            // "Off", or the enabled checkpoints shortest-first.
            guard modelManager.practiceRemindersEnabled else { return "Off" }
            let checkpoints = modelManager.practiceReminderCheckpoints
            guard !checkpoints.isEmpty else { return "On" }
            return checkpoints.sorted().map(\.title).joined(separator: " · ")
        case .keyboard:
            return GermanKeyboard.summary
        case .gamification:
            return modelManager.gamificationEnabled ? "\(modelManager.dailyGoalMinutes) min/day" : "Off"
        case .level:
            // The anchor every level picker opens at.
            return "\(modelManager.germanLevel.rawValue) · \(modelManager.germanLevel.englishLabel)"
        case .memory:
            // How many crashes stand in the log, or the event count.
            let events = MemoryDiagnostics.events
            guard !events.isEmpty else { return nil }
            let crashes = events.filter { $0.kind == .unexpectedTermination || $0.kind == .crashReport }.count
            if crashes > 0 { return crashes == 1 ? "1 crash" : "\(crashes) crashes" }
            return events.count == 1 ? "1 event" : "\(events.count) events"
        case .whatsNew:
            return WhatsNew.current.map { $0.isUnreleased ? "In progress" : "v\($0.version)" }
        case .developer:
            return ScreenshotDataSeeder.seededAt == nil ? nil : "Seeded"
        case .voice, .flashcards, .conversation, .stories, .model, .sources, .feedback:
            return nil
        }
    }

    // MARK: - Destinations

    @MainActor @ViewBuilder
    func destination(modelManager: MLXModelManager, mlxService: MLXGenerationService) -> some View {
        switch self {
        case .sync: ICloudSyncSettingsView()
        case .appearance: ThemePickerView()
        case .reminders: ReminderSettingsView(modelManager: modelManager)
        case .voice: VoiceSettingsView(modelManager: modelManager)
        case .keyboard:
            #if os(iOS)
            KeyboardSettingsView()
            #else
            EmptyView()
            #endif
        case .gamification: GamificationSettingsView(modelManager: modelManager)
        case .level: LevelSettingsView(modelManager: modelManager)
        case .flashcards: FlashcardsSettingsScreen(modelManager: modelManager)
        case .conversation: ConversationSettingsScreen(modelManager: modelManager, mlxService: mlxService)
        case .stories: StoriesSettingsScreen(modelManager: modelManager)
        case .model: ModelSettingsScreen(modelManager: modelManager, mlxService: mlxService)
        case .memory: MemorySettingsView()
        case .whatsNew: WhatsNewView(current: WhatsNew.current)
        case .sources: SourcesView()
        case .feedback: FeedbackScreen(loadedModelName: mlxService.currentModel?.rawValue)
        case .developer: DeveloperSettingsView(modelManager: modelManager, mlxService: mlxService)
        }
    }
}

/// A settings row: the pane's icon and title, its summary trailing in grey, and on the model row
/// the download badge while a model downloads or loads.
struct SettingsPaneRow: View {
    let pane: SettingsPane
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Read here rather than passed in, so the Appearance row follows a theme change at once.
    @AppStorage(AppTheme.defaultsKey) private var appTheme: AppTheme = .klar

    var body: some View {
        HStack {
            Label(pane.title, systemImage: pane.systemImage)
            Spacer(minLength: 8)
            if pane == .model, mlxService.isLoading {
                DownloadBadge(progress: mlxService.downloadProgress)
            } else if let summary = pane.summary(modelManager: modelManager, appTheme: appTheme) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
