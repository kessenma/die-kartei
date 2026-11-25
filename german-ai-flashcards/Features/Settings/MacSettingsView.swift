#if os(macOS)
import SwiftUI

/// Which pane the Settings window shows. Shared, so a deep link from the main window (a nudge's
/// "open Model settings", Help ▸ Send Feedback) can pick the pane before the window opens.
@MainActor @Observable
final class MacSettingsSelection {
    static let shared = MacSettingsSelection()
    var pane: SettingsPane? = .sync
}

/// The Mac's Settings window (⌘,): the panes listed down the left, grouped as on the iPhone, and
/// the chosen pane's form on the right. The panes are the iPhone's own screens (`SettingsPane`).
struct MacSettingsView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    @Bindable private var selection = MacSettingsSelection.shared
    /// A settings screen that links to another one (an upgrade nudge's "open Model settings")
    /// asks through this; here it selects that pane.
    @State private var settingsRouter = SettingsRouter()
    /// Some settings screens can start an activity. The Settings window has nowhere to show one, so
    /// this router only keeps those screens working.
    @State private var activityRouter = ActivityRouter()

    var body: some View {
        // A plain split rather than NavigationSplitView: the Settings window restores its own
        // sidebar width and ignores the column width, which left the pane names truncated.
        HStack(spacing: 0) {
            List(selection: $selection.pane) {
                ForEach(SettingsPane.Group.allCases) { group in
                    let panes = SettingsPane.panes(in: group)
                    if !panes.isEmpty {
                        Section(group.rawValue) {
                            ForEach(panes) { pane in
                                // Title and icon only, like System Settings: the summaries crowd
                                // the names in a sidebar, and each pane shows its own state.
                                HStack {
                                    Label(pane.title, systemImage: pane.systemImage)
                                    if pane == .model, mlxService.isLoading {
                                        Spacer(minLength: 4)
                                        DownloadBadge(progress: mlxService.downloadProgress)
                                    }
                                }
                                .tag(pane)
                            }
                        }
                    }
                }
                Section {
                    Link(destination: ReviewPromptService.writeReviewURL) {
                        Label("Rate on the App Store", systemImage: "star")
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 230)

            Divider()

            NavigationStack {
                if let pane = selection.pane {
                    pane.destination(modelManager: modelManager, mlxService: mlxService)
                        .navigationTitle(pane.title)
                } else {
                    ContentUnavailableView("Settings", systemImage: "gearshape",
                                           description: Text("Choose a section on the left."))
                }
            }
            // A new pane starts at its own root rather than inside whatever the last one pushed.
            .id(selection.pane)
            // The window is already form-width; a readable column inside it would only narrow the
            // toolbar's background to a band under the title bar.
            .environment(\.macReadableWidth, .greatestFiniteMagnitude)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 540)
        .environment(settingsRouter)
        .environment(activityRouter)
        .onChange(of: settingsRouter.route) { _, route in
            guard let route else { return }
            selection.pane = SettingsPane(route: route)
            settingsRouter.route = nil
        }
        // Keep last-loaded in sync, as the in-window Settings does.
        .onChange(of: mlxService.currentModel) { _, newModel in
            if let newModel { modelManager.lastLoadedModel = newModel }
        }
    }
}
#endif
