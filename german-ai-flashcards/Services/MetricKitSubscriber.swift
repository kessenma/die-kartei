//
//  MetricKitSubscriber.swift
//  german-ai-flashcards
//
//  iOS's own account of how the app has been ending. MetricKit delivers, at most once a day, the
//  cumulative exit counts (foreground memory-limit kills are the one that matters here) and a
//  crash diagnostic per crash. Both are filed into the memory log so they sit next to the app's
//  own "closed while in use" records — the marker says *when and where*, this says *why*.
//
//  Payloads never arrive in the simulator on their own; Xcode ▸ Debug ▸ Simulate MetricKit Payload
//  delivers a sample one to a DEBUG build, which is how the rows are checked.
//

import Foundation
import MetricKit

nonisolated final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitSubscriber()

    private override init() { super.init() }

    /// Subscribe once, at launch. MetricKit hands over anything that accumulated while the app
    /// was away as soon as a subscriber exists.
    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            guard let exits = payload.applicationExitMetrics else { continue }
            let fg = exits.foregroundExitData
            let bg = exits.backgroundExitData
            let summary = "In use: \(fg.cumulativeMemoryResourceLimitExitCount) out of memory, "
                + "\(fg.cumulativeAbnormalExitCount) abnormal, \(fg.cumulativeBadAccessExitCount) bad access, "
                + "\(fg.cumulativeAppWatchdogExitCount) watchdog. "
                + "Background: \(bg.cumulativeMemoryResourceLimitExitCount) out of memory, "
                + "\(bg.cumulativeMemoryPressureExitCount) memory pressure, "
                + "\(bg.cumulativeAbnormalExitCount) abnormal."
            let window = "\(Self.short(payload.timeStampBegin)) – \(Self.short(payload.timeStampEnd))"
            Task { @MainActor in
                MemoryDiagnostics.record(
                    .systemExitCounts,
                    title: "iOS exit report · \(window)",
                    detail: summary
                )
            }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                var pieces: [String] = []
                if let reason = crash.terminationReason { pieces.append("Reason: \(reason)") }
                if let type = crash.exceptionType { pieces.append("Exception type \(type)") }
                if let code = crash.exceptionCode { pieces.append("code \(code)") }
                if let signal = crash.signal { pieces.append("signal \(signal)") }
                if let region = crash.virtualMemoryRegionInfo { pieces.append("Region: \(region)") }
                pieces.append("Build \(crash.metaData.applicationBuildVersion) · iOS \(crash.metaData.osVersion) · \(crash.metaData.deviceType)")
                let frames = Self.frames(from: crash.callStackTree)
                if !frames.isEmpty { pieces.append("Frames:\n" + frames) }
                let detail = pieces.joined(separator: "\n")
                let when = Self.short(payload.timeStampEnd)
                Task { @MainActor in
                    MemoryDiagnostics.record(
                        .crashReport,
                        title: "Crash report from iOS · \(when)",
                        detail: String(detail.prefix(8_000))
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private static func short(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm"
        return f.string(from: date)
    }

    /// The first ~40 frame lines of the crashed thread, from the tree's JSON. Symbolication is
    /// not attempted — a binary name plus offset is enough to match against a crash log later,
    /// and it keeps the row small.
    private static func frames(from tree: MXCallStackTree) -> String {
        let data = tree.jsonRepresentation()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]]
        else { return "" }
        let crashed = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
        guard let crashed, let frames = crashed["callStackRootFrames"] as? [[String: Any]] else { return "" }

        var lines: [String] = []
        func walk(_ frame: [String: Any], depth: Int) {
            guard lines.count < 40 else { return }
            let binary = frame["binaryName"] as? String ?? "?"
            let offset = frame["offsetIntoBinaryTextSegment"] as? Int ?? 0
            lines.append("  \(String(repeating: " ", count: min(depth, 8)))\(binary) +\(offset)")
            for sub in frame["subFrames"] as? [[String: Any]] ?? [] {
                walk(sub, depth: depth + 1)
            }
        }
        for frame in frames { walk(frame, depth: 0) }
        return lines.joined(separator: "\n")
    }
}
