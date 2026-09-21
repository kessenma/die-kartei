//
//  MemoryDiagnostics.swift
//  german-ai-flashcards
//
//  The one place that answers "what is using memory, where, and what happened last time".
//
//  Three jobs:
//
//  1. **Readings and the breakdown.** `MemoryReading.now()` is the kernel's view (`phys_footprint`,
//     what's left) plus MLX's (weights + KV cache, reuse cache). The breakdown is a registry: every
//     heavy owner — the tutor, the drawing model, the story picture cache — registers a closure
//     that reports its bytes, and "everything else" is whatever the footprint doesn't account for.
//  2. **The context.** Screens that hold heavy things call `.memoryContext("Story reader · Ganz")`
//     so every log line, and above all a termination record, says *where* it happened.
//  3. **Recording.** `record(...)` tees off the existing `os.Logger` lines into the on-disk log
//     (`MemoryEventStore`), keeps the session marker current so an unclean exit is noticed at the
//     next launch, and runs the opt-in heartbeat.
//
//  Why a session marker and MetricKit both: the marker is immediate (the very next launch says
//  "closed while in use, footprint was 4.8 GB, story reader") but can't tell jetsam from a crash;
//  MetricKit is authoritative about the cause but arrives a day later. Together they cover it.
//

import Foundation
import MLX
import os
import SwiftUI
import UIKit

extension MemoryReading {
    /// What the process holds right now. The MLX figures are zero until a model has loaded in
    /// this process (and always in the simulator): asking MLX earlier would construct its Metal
    /// device just to be told nothing is allocated — and abort where there is no Metal.
    static func now() -> MemoryReading {
        let mlx = MemorySaver.mlxRuntimeReady
        return MemoryReading(
            footprintMB: MemoryBudget.footprintMB,
            availableMB: MemoryBudget.availableMB,
            totalMB: MemoryBudget.totalMB,
            mlxActiveMB: mlx ? Memory.activeMemory / 1_048_576 : 0,
            mlxCacheMB: mlx ? Memory.cacheMemory / 1_048_576 : 0,
            mlxPeakMB: mlx ? Memory.peakMemory / 1_048_576 : 0
        )
    }
}

enum MemoryDiagnostics {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "de.germanflashcards",
        category: "Memory"
    )

    // MARK: - The logging toggle

    /// UserDefaults key behind "Log when memory runs short" — shared with the Settings toggle's
    /// `@AppStorage`.
    static let verboseDefaultsKey = "memoryLog.verbose"

    /// On by default where the people running the build are testing it (DEBUG and TestFlight),
    /// off for the App Store: a learner never asked for a heartbeat in their Application Support.
    static var verboseDefault: Bool { ScreenshotSeeding.isAvailable }

    /// Whether the opt-in kinds (pressure samples, model moves, heartbeats) are recorded.
    static var isVerbose: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: verboseDefaultsKey) != nil else { return verboseDefault }
            return defaults.bool(forKey: verboseDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: verboseDefaultsKey)
            verboseDidChange()
        }
    }

    /// Call after the toggle flips (the Settings screen binds `@AppStorage` directly, so it
    /// bypasses the setter above) to start or stop the heartbeat.
    static func verboseDidChange() {
        if isVerbose, UIApplication.shared.applicationState == .active {
            startHeartbeat()
        } else {
            stopHeartbeat()
        }
    }

    // MARK: - Context

    /// The screen in force — set by `.memoryContext(_:)`. Read at every record so the log says
    /// where the app was, which is the question a termination row exists to answer.
    private(set) static var context: String?

    static func setContext(_ value: String) {
        context = value
        touchSessionMarker()
    }

    /// Clears only if `value` is still the context: two screens can overlap on the way out
    /// (a cover dismissing over a pushed reader), and the one leaving must not erase the other.
    static func clearContext(_ value: String) {
        guard context == value else { return }
        context = nil
        touchSessionMarker()
    }

    // MARK: - Breakdown registry

    private struct Contributor {
        let key: String
        let name: () -> String
        let bytes: () -> Int
    }

    private static var contributors: [Contributor] = []

    /// Register a heavy owner under a stable `key`. `bytes` is read whenever a breakdown is built
    /// (return 0 when holding nothing); `name` is the row label, a closure so it can carry state
    /// ("Tutor · gemma4_E4B"). Registering an existing key replaces it. First registration sets
    /// display order.
    static func register(_ key: String, name: @escaping () -> String, bytes: @escaping () -> Int) {
        let contributor = Contributor(key: key, name: name, bytes: bytes)
        if let index = contributors.firstIndex(where: { $0.key == key }) {
            contributors[index] = contributor
        } else {
            contributors.append(contributor)
        }
    }

    static func register(_ key: String, name: String, bytes: @escaping () -> Int) {
        register(key, name: { name }, bytes: bytes)
    }

    static func unregister(_ key: String) {
        contributors.removeAll { $0.key == key }
    }

    /// Named owners with a non-zero share, plus "Everything else" for what the footprint holds
    /// that nobody claimed. MLX's reuse cache is listed from the reading, not the registry — it
    /// belongs to no feature.
    static func breakdown(for reading: MemoryReading) -> [MemoryEvent.Contributor] {
        var rows: [MemoryEvent.Contributor] = []
        var claimed = 0
        for contributor in contributors {
            let mb = contributor.bytes() / 1_048_576
            guard mb > 0 else { continue }
            rows.append(.init(name: contributor.name(), mb: mb))
            claimed += mb
        }
        if reading.mlxCacheMB > 0 {
            rows.append(.init(name: "MLX reuse cache", mb: reading.mlxCacheMB))
            claimed += reading.mlxCacheMB
        }
        if reading.footprintMB > 0 {
            rows.append(.init(name: "Everything else", mb: max(0, reading.footprintMB - claimed)))
        }
        return rows
    }

    // MARK: - Recording

    /// Record one event. Opt-in kinds are dropped unless the toggle is on; the rest always land.
    /// Every record also refreshes the session marker, so the last line before a termination is
    /// what the next launch reports.
    static func record(_ kind: MemoryEvent.Kind, title: String, detail: String? = nil) {
        guard !kind.isOptIn || isVerbose else { return }
        let reading = MemoryReading.now()
        let event = MemoryEvent(
            kind: kind,
            title: title,
            detail: detail,
            reading: reading,
            breakdown: breakdown(for: reading),
            context: context,
            appState: appStateLabel,
            appVersion: DeviceInfo.appVersion
        )
        MemoryEventStore.append(event)
        logger.info("[\(kind.rawValue, privacy: .public)] \(title, privacy: .public) — footprint \(reading.footprintMB, privacy: .public) MB, available \(reading.availableMB, privacy: .public) MB, context \(context ?? "—", privacy: .public)")
        touchSessionMarker(reading: reading, breakdown: event.breakdown)
    }

    /// Newest first.
    static var events: [MemoryEvent] { MemoryEventStore.events() }

    static func clearLog() { MemoryEventStore.deleteAll() }

    private static var appStateLabel: String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    // MARK: - Session marker

    /// What the previous session left behind. Written at launch, refreshed on every event and
    /// scene change, closed by `applicationWillTerminate`. Still open at the next launch means the
    /// app was killed — by jetsam, a crash, or the app switcher.
    private struct SessionMarker: Codable {
        var launchedAt: Date
        var lastSeenAt: Date
        var appState: String
        var lastReading: MemoryReading?
        var lastBreakdown: [MemoryEvent.Contributor]
        var lastContext: String?
        var appVersion: String
        var osVersion: String
        var endedCleanly: Bool
    }

    private static var markerURL: URL {
        MemoryEventStore.fileURL.deletingLastPathComponent().appendingPathComponent("session.json")
    }

    private static var marker: SessionMarker?

    /// At launch: turn a still-open marker from last time into a log line, then open this
    /// session's. The launch slot in `ContentView` calls this once, beside `takeInterruptedLoad`.
    static func beginSession() {
        if let previous = readMarker(), !previous.endedCleanly {
            reportUncleanExit(previous)
        }
        marker = SessionMarker(
            launchedAt: Date(),
            lastSeenAt: Date(),
            appState: appStateLabel,
            lastReading: MemoryReading.now(),
            lastBreakdown: [],
            lastContext: nil,
            appVersion: DeviceInfo.appVersion,
            osVersion: DeviceInfo.osVersionNumber,
            endedCleanly: false
        )
        writeMarker()
        verboseDidChange()
    }

    private static func reportUncleanExit(_ previous: SessionMarker) {
        let versionChanged = previous.appVersion != DeviceInfo.appVersion
            || previous.osVersion != DeviceInfo.osVersionNumber
        let reading = previous.lastReading ?? MemoryReading.now()
        let last = previous.lastReading.map { "Last seen with \($0.footprintMB) MB used and \($0.availableMB) MB free" }

        let event: MemoryEvent
        if versionChanged {
            event = MemoryEvent(
                date: previous.lastSeenAt,
                kind: .appUpdated,
                title: "App or iOS was updated",
                detail: "\(previous.appVersion) on iOS \(previous.osVersion) → \(DeviceInfo.appVersion) on iOS \(DeviceInfo.osVersionNumber). The previous session ended with the update, not a crash.",
                reading: reading,
                breakdown: previous.lastBreakdown,
                context: previous.lastContext,
                appState: previous.appState,
                appVersion: previous.appVersion
            )
        } else if previous.appState == "active" {
            event = MemoryEvent(
                date: previous.lastSeenAt,
                kind: .unexpectedTermination,
                title: "Closed while in use",
                detail: [
                    "The app stopped without closing normally — it ran out of memory, or crashed.",
                    last
                ].compactMap { $0 }.joined(separator: " "),
                reading: reading,
                breakdown: previous.lastBreakdown,
                context: previous.lastContext,
                appState: previous.appState,
                appVersion: previous.appVersion
            )
        } else {
            event = MemoryEvent(
                date: previous.lastSeenAt,
                kind: .unexpectedTermination,
                title: "Closed in the background",
                detail: [
                    "iOS reclaimed the app's memory while it was suspended, or it was closed from the app switcher. Normal for an app holding a tutor; the screen it was on reloads what it needs.",
                    last
                ].compactMap { $0 }.joined(separator: " "),
                reading: reading,
                breakdown: previous.lastBreakdown,
                context: previous.lastContext,
                appState: previous.appState,
                appVersion: previous.appVersion
            )
        }
        MemoryEventStore.append(event)
        logger.notice("Previous session ended uncleanly: \(event.title, privacy: .public) (\(previous.appState, privacy: .public), context \(previous.lastContext ?? "—", privacy: .public))")
    }

    /// Scene changes: the marker's `appState` is what decides how an unclean exit is labelled.
    static func sceneDidChange() {
        touchSessionMarker(reading: MemoryReading.now())
        verboseDidChange()
    }

    /// `applicationWillTerminate`. iOS calls it rarely — a foreground quit, some background
    /// terminations — but when it does, the next launch must not call that a crash.
    static func endSessionCleanly() {
        marker?.endedCleanly = true
        marker?.lastSeenAt = Date()
        writeMarker()
    }

    private static func touchSessionMarker(reading: MemoryReading? = nil,
                                           breakdown: [MemoryEvent.Contributor]? = nil) {
        guard marker != nil else { return }
        marker?.lastSeenAt = Date()
        marker?.appState = appStateLabel
        marker?.lastContext = context
        if let reading {
            marker?.lastReading = reading
            marker?.lastBreakdown = breakdown ?? self.breakdown(for: reading)
        }
        writeMarker()
    }

    private static func readMarker() -> SessionMarker? {
        guard let data = try? Data(contentsOf: markerURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionMarker.self, from: data)
    }

    private static func writeMarker() {
        guard let marker else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(marker) else { return }
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: markerURL, options: .atomic)
    }

    // MARK: - Heartbeat

    /// How often a routine reading lands while the opt-in logging is on and the app is in front.
    /// A minute is enough to see a leak's slope across a study session without the log being all
    /// heartbeats (the store trims those first anyway).
    static let heartbeatSeconds: Double = 60

    private static var heartbeat: Task<Void, Never>?

    private static func startHeartbeat() {
        guard heartbeat == nil else { return }
        heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(heartbeatSeconds))
                guard !Task.isCancelled else { break }
                record(.heartbeat, title: "Routine reading")
            }
        }
    }

    private static func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    // MARK: - Export

    /// The whole log as text, newest first, with a device header — what Copy puts on the
    /// pasteboard. One line per event; the breakdown is inlined so a pasted log stands alone.
    static func exportText(events: [MemoryEvent]? = nil) -> String {
        let events = events ?? self.events
        let reading = MemoryReading.now()
        var lines: [String] = []
        lines.append("Die Kartei memory log")
        lines.append("App \(DeviceInfo.appVersion) · \(DeviceInfo.deviceModel) · \(DeviceInfo.osVersion) · \(DeviceCapability.ramGB) GB RAM")
        lines.append("Budget \(reading.totalMB) MB · now \(reading.footprintMB) MB used, \(reading.availableMB) MB free · MLX \(reading.mlxActiveMB) MB active, \(reading.mlxCacheMB) MB cache, \(reading.mlxPeakMB) MB peak")
        lines.append("Logging when memory runs short: \(isVerbose ? "on" : "off") · \(events.count) events")
        lines.append("")
        for event in events {
            lines.append(line(for: event))
            if let detail = event.detail, !detail.isEmpty {
                lines.append("    \(detail)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func line(for event: MemoryEvent) -> String {
        var parts: [String] = []
        parts.append("\(stamp.string(from: event.date))  \(event.kind.textMarker) \(event.title)")
        parts.append("\(event.reading.footprintMB) MB used")
        parts.append("\(event.reading.availableMB) MB free")
        for contributor in event.breakdown where contributor.name != "Everything else" {
            parts.append("\(contributor.name.lowercased()) \(contributor.mb)")
        }
        if let other = event.breakdown.first(where: { $0.name == "Everything else" }) {
            parts.append("other \(other.mb)")
        }
        if let context = event.context { parts.append(context) }
        if event.appState != "active" { parts.append(event.appState) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - View modifier

private struct MemoryContextModifier: ViewModifier {
    let value: String

    func body(content: Content) -> some View {
        content
            .onAppear { MemoryDiagnostics.setContext(value) }
            .onDisappear { MemoryDiagnostics.clearContext(value) }
            // A screen whose context carries state (the reader's layout) re-labels in place.
            .onChange(of: value) { old, new in
                MemoryDiagnostics.clearContext(old)
                MemoryDiagnostics.setContext(new)
            }
    }
}

extension View {
    /// Name this screen in the memory log for as long as it's on screen: "Story reader · Ganz",
    /// "Chat", "Creating cards". Put it on the screens that hold heavy things, so a termination
    /// record says where the app was.
    func memoryContext(_ value: String) -> some View {
        modifier(MemoryContextModifier(value: value))
    }
}
