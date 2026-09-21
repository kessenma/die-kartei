//
//  MemoryEventStore.swift
//  german-ai-flashcards
//
//  The memory log: every crash, system memory warning, and (when the learner has turned the
//  finer logging on) every moment the app got close to its limit or moved a multi-gigabyte model
//  in or out of memory. Shown under Settings ▸ Speicher, copied out as text when something goes
//  wrong.
//
//  Same shape as `PlacementAttemptStore`: one JSON array in Application Support, rewritten
//  atomically, a decode failure yields an empty log rather than a crash. Not SwiftData, because a
//  log that has to survive the store deleting itself on migration failure cannot live inside it —
//  and because the log is most valuable right after the app died, which is the worst moment to
//  depend on anything else being healthy.
//
//  The cap trims the chatty kinds first (heartbeats, then the other opt-in kinds), so a crash
//  record is never pushed out by an hour of routine samples.
//

import Foundation

/// One line of the memory log.
struct MemoryEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        // Always recorded.
        /// The previous session did not end cleanly (session marker still open at launch).
        case unexpectedTermination
        /// A crash diagnostic delivered by MetricKit.
        case crashReport
        /// MetricKit's daily exit counts — the authoritative "was it jetsam?" answer.
        case systemExitCounts
        /// `UIApplication.didReceiveMemoryWarningNotification`.
        case memoryWarning
        /// A model load was still marked in flight when the app last stopped.
        case interruptedLoad
        /// The app or OS version changed between sessions, which explains an unclean exit.
        case appUpdated

        // Recorded only while "Log when memory runs short" is on.
        case pressureElevated
        case pressureCritical
        case modelLoadStart
        case modelLoaded
        case modelLoadFailed
        case modelUnloaded
        case modelEvicted
        case pipelineLoaded
        case pipelineUnloaded
        case heartbeat

        /// Whether the learner's logging toggle gates this kind.
        var isOptIn: Bool {
            switch self {
            case .unexpectedTermination, .crashReport, .systemExitCounts, .memoryWarning,
                 .interruptedLoad, .appUpdated:
                false
            case .pressureElevated, .pressureCritical, .modelLoadStart, .modelLoaded,
                 .modelLoadFailed, .modelUnloaded, .modelEvicted, .pipelineLoaded,
                 .pipelineUnloaded, .heartbeat:
                true
            }
        }

        /// The row's icon, and the colour it's drawn in.
        var symbol: String {
            switch self {
            case .unexpectedTermination, .crashReport: "exclamationmark.octagon.fill"
            case .systemExitCounts:                    "chart.bar.doc.horizontal"
            case .memoryWarning, .pressureCritical:    "exclamationmark.triangle.fill"
            case .pressureElevated:                    "exclamationmark.triangle"
            case .interruptedLoad:                     "bolt.slash"
            case .appUpdated:                          "arrow.up.app"
            case .modelLoadStart, .modelLoaded, .modelLoadFailed, .modelUnloaded, .modelEvicted: "cpu"
            case .pipelineLoaded, .pipelineUnloaded:   "paintbrush"
            case .heartbeat:                           "waveform.path.ecg"
            }
        }

        /// A one-character marker for the plain-text export, so a pasted log scans by eye.
        var textMarker: String {
            switch self {
            case .unexpectedTermination, .crashReport: "✖︎"
            case .memoryWarning, .pressureCritical, .pressureElevated, .interruptedLoad: "⚠︎"
            case .systemExitCounts, .appUpdated: "ℹ︎"
            case .modelLoadStart, .modelLoaded, .modelLoadFailed, .modelUnloaded, .modelEvicted,
                 .pipelineLoaded, .pipelineUnloaded: "•"
            case .heartbeat: "·"
            }
        }
    }

    /// One named owner of memory, in MB. "Everything else" is footprint minus the named ones.
    struct Contributor: Codable, Equatable {
        var name: String
        var mb: Int
    }

    var id: UUID = UUID()
    var date: Date = Date()
    var kind: Kind
    var title: String
    var detail: String?
    var reading: MemoryReading
    var breakdown: [Contributor]
    /// The screen in force when this happened — "Story reader · Ganz", "Chat", … — see
    /// `MemoryDiagnostics.context`.
    var context: String?
    /// "active" / "inactive" / "background" at the moment of the event.
    var appState: String
    var appVersion: String
}

/// A snapshot of what the process holds and what it has left, from the kernel and from MLX.
struct MemoryReading: Codable, Equatable {
    /// `phys_footprint` — the number jetsam watches. −1 if the kernel wouldn't say.
    var footprintMB: Int
    /// What the process can still allocate before iOS kills it. 0 when the OS won't report.
    var availableMB: Int
    /// `availableMB + footprintMB`: the app's whole budget on this device.
    var totalMB: Int
    /// MLX buffers in use — the loaded weights plus any live KV cache.
    var mlxActiveMB: Int
    /// MLX buffers kept for reuse, not currently in use.
    var mlxCacheMB: Int
    /// The high-water mark of `mlxActiveMB` since launch.
    var mlxPeakMB: Int
}

enum MemoryEventStore {

    /// A log line is a few hundred bytes, so this is ~200 KB on disk. See `trim(_:)` for what
    /// goes first when it fills.
    static let cap = 600

    private static let directoryName = "Diagnostics"
    private static let fileName = "memory-events.json"

    static var fileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent(directoryName)
            .appendingPathComponent(fileName)
    }

    private static var cache: [MemoryEvent]?

    // MARK: - Reading

    /// Every recorded event, newest first.
    static func events() -> [MemoryEvent] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([MemoryEvent].self, from: data)
        else {
            cache = []
            return []
        }
        let sorted = decoded.sorted { $0.date > $1.date }
        cache = sorted
        return sorted
    }

    static var count: Int { events().count }

    // MARK: - Writing

    static func append(_ event: MemoryEvent) {
        let all = (events() + [event]).sorted { $0.date > $1.date }
        write(trim(all))
    }

    static func deleteAll() {
        write([])
    }

    /// Drop the least valuable lines first: heartbeats, then the other opt-in kinds, then — only
    /// if the log is somehow still over the cap — the oldest of everything.
    private static func trim(_ events: [MemoryEvent]) -> [MemoryEvent] {
        guard events.count > cap else { return events }
        var kept = events   // newest first
        for stage in 0..<3 {
            let dropped: (MemoryEvent) -> Bool = { event in
                switch stage {
                case 0: event.kind == .heartbeat
                case 1: event.kind.isOptIn
                default: true
                }
            }
            // Walk from the oldest end, removing matches until we fit.
            var index = kept.count - 1
            while kept.count > cap, index >= 0 {
                if dropped(kept[index]) { kept.remove(at: index) }
                index -= 1
            }
            if kept.count <= cap { break }
        }
        return kept
    }

    // MARK: - Disk

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func write(_ events: [MemoryEvent]) {
        cache = events
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
