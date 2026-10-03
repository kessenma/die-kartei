//
//  german_ai_flashcardsApp.swift
//  german-ai-flashcards
//
//  Created by Kyle Essenmacher on 5/14/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Recreate the background download session on every launch: transfers that finished
        // or failed while the app was gone deliver their callbacks now and get settled into
        // their partial files, not only once a download screen happens to start one.
        BackgroundModelDownloadSession.shared.activate()
        // iOS's own account of crashes and memory-limit kills, filed into the memory log next to
        // the app's session-marker records (Settings ▸ Speicher).
        MetricKitSubscriber.shared.start()
        return true
    }

    /// Rarely called on iOS — a foreground quit, some background terminations — but when it is,
    /// the next launch must not report this session as a crash.
    func applicationWillTerminate(_ application: UIApplication) {
        MemoryDiagnostics.endSessionCleanly()
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundModelDownloadSession.shared.setBackgroundCompletionHandler(completionHandler)
        // Woken in the background because a file finished: keep the download moving (commit
        // the file, enqueue the next one) instead of waiting for the user to come back.
        if application.applicationState == .background {
            BackgroundDownloadResumer.kickIfNeeded()
        }
    }
}
#else
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // One window: no window tabs, and no View ▸ Show Tab Bar / Show All Tabs for them.
        NSWindow.allowsAutomaticWindowTabbing = false
        MacReadingTextSize.installEqualsKeyAlias()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BackgroundModelDownloadSession.shared.activate()
        MetricKitSubscriber.shared.start()
        // The Mac has no memory warnings; its memory-pressure events stand in for them.
        MacMemoryPressure.start()
    }

    /// One window, one app: closing it quits, the way a phone app's swipe-away does.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting is a normal exit on the Mac (and the scene never reaches `.background` first), so
    /// this is where the session ends cleanly and the last edits are queued for iCloud.
    func applicationWillTerminate(_ notification: Notification) {
        SyncManager.shared.appWillResignActive()
        MemoryDiagnostics.endSessionCleanly()
    }
}
#endif

@main
struct german_ai_flashcardsApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    let container: ModelContainer
    @State private var modelManager: MLXModelManager
    @State private var coordinator: GenerationCoordinator
    @Environment(\.scenePhase) private var scenePhase

    /// The app-wide visual identity. `klar` (the untouched baseline) by default, so shipping the
    /// theme system is a no-op until the learner opts into another theme in Settings.
    @AppStorage(AppTheme.defaultsKey) private var appTheme: AppTheme = .klar

    /// A `.kartei` file handed over by AirDrop / Files / Messages, decoded and waiting for the
    /// learner to confirm. Held here rather than in the Library because a deck can arrive while
    /// any tab is open, and the file is gone from the inbox by the time this is set.
    @State private var pendingDeckImport: DeckImportRequest?
    @State private var deckImportError: String?
    #if os(macOS)
    /// The Mac window's sidebar selection and menu-driven flags, shared with the menu bar.
    @State private var navigator = MacNavigator()
    #endif

    init() {
        // The Klassisch/Geschichte scene-style toggle was removed 2026-08-12 (the sets merged
        // into one curated scene per word); the key was user-visible in the preposition hub,
        // so stale devices exist.
        UserDefaults.standard.removeObject(forKey: "prepositions.sceneStyle")

        let schema = Schema(AppSchema.models)
        // `.none` is load-bearing. The parameter defaults to `.automatic`, which turns on SwiftData's
        // own CloudKit mirroring the moment the app gains an iCloud container entitlement. This
        // schema doesn't meet mirroring's rules, so the store would fail to open. iCloud Sync runs
        // on CKSyncEngine instead (docs/ICLOUD_SYNC.md), and this store stays local.
        let config = SwiftData.ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // The store can't be opened (a migration SwiftData couldn't do). Move it aside rather
            // than delete it, so the old file can still be rescued, and start fresh.
            StoreRecovery.moveAside(storeURL: config.url, reason: error)

            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }

        let mm = MLXModelManager()
        _modelManager = State(initialValue: mm)
        _coordinator = State(initialValue: GenerationCoordinator(modelManager: mm))

        // iCloud Sync starts here rather than in a view, so a silent push that wakes the app in
        // the background finds the engine running. When another device's study lands, the
        // practice reminders re-plan, so this device doesn't nag about a day already studied.
        let syncContainer = container
        SyncManager.shared.onRemoteChanges = { kinds in
            guard kinds.contains(StudyDayCodec.spec.kind) else { return }
            Task { @MainActor in
                await PracticeReminderService.refresh(context: syncContainer.mainContext, modelManager: mm)
            }
        }
        SyncManager.shared.modelManager = mm
        SyncManager.shared.configure(container: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: coordinator)
                .environment(coordinator.mlxService)
                .environment(\.appTheme, appTheme)
                #if os(macOS)
                .environment(navigator)
                #endif
                .onChange(of: scenePhase) { _, phase in
                    // The session marker's app state is what decides whether an unclean exit is
                    // reported as "closed while in use" or "closed in the background".
                    MemoryDiagnostics.sceneDidChange()
                    // A model download cut off while the user was in another app resumes
                    // from its saved partial files as soon as they come back — even when
                    // the cutoff was iOS terminating the app. The background wake driver
                    // stops first: two drivers would race one repo's partials.
                    if phase == .active {
                        Task { @MainActor in
                            await BackgroundDownloadResumer.stop()
                            coordinator.mlxService.resumeInterruptedDownloadIfNeeded()
                        }
                    }
                    // Leaving the foreground with multi-GB weights resident is the single fastest
                    // way to get the app terminated: iOS ranks suspended apps for jetsam largely
                    // by footprint, so a trip to Settings (adding a German keyboard, say) is
                    // enough to lose the open conversation's in-flight turn. Shed the model on the
                    // devices that have no room to spare for it; the screen that was using it
                    // reloads it on return (see `MLXGenerationService.releaseMemory(reason:)`).
                    if phase == .background {
                        coordinator.mlxService.releaseMemory(reason: .background)
                    }
                    // iCloud Sync: queue the latest edits before suspension; on return, send and
                    // fetch (CloudKit pushes can be late or dropped). A Mac app is rarely
                    // `.background`; switching to another app makes it `.inactive`.
                    if phase == .background { SyncManager.shared.appWillResignActive() }
                    #if os(macOS)
                    if phase == .inactive { SyncManager.shared.appWillResignActive() }
                    #endif
                    if phase == .active { Task { await SyncManager.shared.appBecameActive() } }
                    // Keep practice reminders anchored to the real last-practice date: re-derive the
                    // ladder whenever the app enters or leaves the foreground. Leaving captures any
                    // practice done this session; entering picks up permission or settings changes.
                    if phase == .active || phase == .background {
                        Task { @MainActor in
                            await PracticeReminderService.refresh(
                                context: container.mainContext,
                                modelManager: modelManager
                            )
                        }
                    }
                }
                .onOpenURL { url in importDeck(from: url) }
                #if os(macOS)
                // File ▸ Import Deck… (⌘O): the same path as a .kartei opened from Finder.
                .fileImporter(isPresented: $navigator.showsDeckImporter,
                              allowedContentTypes: [.karteiDeck]) { result in
                    switch result {
                    case .success(let url): importDeck(from: url)
                    case .failure(let error): deckImportError = error.localizedDescription
                    }
                }
                #endif
                .sheet(item: $pendingDeckImport) { request in
                    DeckImportSheet(request: request)
                }
                .alert(
                    "Import failed",
                    isPresented: Binding(
                        get: { deckImportError != nil },
                        set: { if !$0 { deckImportError = nil } }
                    ),
                    presenting: deckImportError
                ) { _ in
                    Button("OK", role: .cancel) {}
                } message: { message in
                    Text(message)
                }
                #if os(macOS)
                // Phone-shaped screens and their sheets need a window at least this tall.
                .frame(minWidth: 760, minHeight: 820)
                // Settings-style forms as on iOS; the Mac default is a two-column layout.
                .formStyle(.grouped)
                // View ▸ Bigger / Smaller Text (⌘+ / ⌘−) for the German you read.
                .modifier(MacReadingTextSizeModifier())
                #endif
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1100, height: 900)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { MacCommands(navigator: navigator) }
        #endif

        #if os(macOS)
        // The iPhone's full-screen covers (an activity, a chat, the onboarding wizard) each open
        // in a window of their own, so their toolbars show (App/MacCoverWindow.swift).
        WindowGroup(id: MacCoverRegistry.sceneID, for: UUID.self) { $id in
            MacCoverWindowRoot(id: id)
                .modifier(MacReadingTextSizeModifier())
                .environment(coordinator.mlxService)
                .environment(\.appTheme, appTheme)
                .environment(navigator)
                .modelContainer(container)
        }
        .defaultSize(width: 1000, height: 840)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        // ⌘, — the panes of the iPhone's Settings list, as a Mac settings window.
        Settings {
            MacSettingsView(modelManager: modelManager, mlxService: coordinator.mlxService)
                .environment(coordinator.mlxService)
                .environment(\.appTheme, appTheme)
                .environment(\.modelTheme, coordinator.mlxService.loadedModel?.theme)
                .formStyle(.grouped)
                .modelContainer(container)
        }
        #endif
    }

    /// A `.kartei` deck handed to the app, decoded and waiting for the learner to confirm.
    private func importDeck(from url: URL) {
        do {
            pendingDeckImport = DeckImportRequest(envelope: try DeckImporter.read(from: url))
        } catch {
            deckImportError = error.localizedDescription
        }
    }
}
