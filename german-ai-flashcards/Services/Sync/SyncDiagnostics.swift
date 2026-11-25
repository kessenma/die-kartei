import Foundation
import SwiftData

/// Why sync isn't finishing — in words the learner can act on, plus the detail worth sending in.
///
/// Every record already remembers the last thing CloudKit said about it (`SyncRecordState.lastError`).
/// Until this report existed that text was written and never read: the screen could say
/// "Waiting to upload 1,143" and "Can't sync 1,172" and nothing whatsoever about why.
struct SyncReport: Equatable {
    /// Records owed to iCloud, including the ones that have given up.
    var waiting = 0
    /// Of those, records that failed often enough to be skipped until a repair.
    var stuck = 0
    /// Deletes still owed.
    var waitingToDelete = 0
    /// Server copies this build can't read yet (written by a newer version of the app).
    var heldForNewerVersion = 0
    /// Owed, but with nothing to actually send. A stall with no error behind it: a bug if it's
    /// anything but zero, and the only way to see it was a debugger.
    var nothingToSend = 0
    /// What's waiting, by kind, biggest first.
    var byKind: [SyncReportCount] = []
    /// What iCloud said, grouped.
    var problems: [SyncProblem] = []

    var hasProblems: Bool { stuck > 0 || nothingToSend > 0 || !problems.isEmpty }
}

struct SyncReportCount: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let count: Int
}

/// One reason, and everything it's holding up.
struct SyncProblem: Identifiable, Equatable {
    var id: String { reason }
    /// What CloudKit said, as it said it: "serverRecordChanged: …".
    let reason: String
    /// Plain English, from the error's code.
    let explanation: String
    /// These records won't be tried again until a repair.
    let givenUp: Bool
    let records: Int
    /// The kinds it's holding up, biggest first.
    let kinds: [SyncReportCount]
}

enum SyncDiagnostics {
    /// The code CloudKit reports is the useful half of the message, so the transport keeps it as a
    /// prefix ("quotaExceeded: …"). Anything else is shown as-is.
    static func code(of reason: String) -> String {
        guard let colon = reason.firstIndex(of: ":") else { return "" }
        return String(reason[reason.startIndex..<colon])
    }

    /// What to do about it, in the app's voice. The default is honest about not knowing rather
    /// than inventing advice.
    static func explain(_ reason: String) -> String {
        switch code(of: reason) {
        case "schemaNotDeployed":
            "iCloud isn't set up for Die Kartei yet, so it can't take anything. That's the app's fault, not yours. Nothing is lost: it all goes up once that's fixed."
        case "quotaExceeded":
            "Your iCloud storage is full. Free some space, then repair."
        case "limitExceeded":
            "Too big for one upload. It'll keep being skipped; the rest still syncs."
        case "serverRecordChanged":
            "Another device changed this at the same time. It merges and goes up again by itself."
        case "batchRequestFailed":
            "Another item in the same upload failed, so this one came back too. It goes up as soon as that one is out of the way."
        case "networkFailure", "networkUnavailable":
            "No connection to iCloud. It carries on when there is one."
        case "requestRateLimited", "zoneBusy", "serviceUnavailable", "serverResponseLost":
            "iCloud asked for a pause. It carries on by itself."
        case "notAuthenticated", "accountTemporarilyUnavailable":
            "Not signed in to iCloud right now."
        case "permissionFailure", "managedAccountRestricted":
            "This Apple Account doesn't allow Die Kartei to use iCloud. Check Settings ▸ your name ▸ iCloud."
        case "changeTokenExpired":
            "iCloud forgot where this device had got to. Repair Sync fetches everything again."
        case "assetFileNotFound", "assetFileModified", "assetNotAvailable":
            "A picture or PDF changed while it was going up. It goes again with the next change."
        case "invalidArguments", "serverRejectedRequest", "internalError", "constraintViolation":
            "iCloud refused this item. That's a bug here, not something you did — please send the report."
        default:
            "iCloud couldn't take this item."
        }
    }
}

extension SyncCoordinator {

    /// Read the whole picture out of the store. A settings screen's worth of work: one fetch of the
    /// records that are owed or have something to say, and no network.
    func report() -> SyncReport {
        var report = SyncReport()
        let states = (try? context.fetch(FetchDescriptor<SyncRecordState>(
            predicate: #Predicate { $0.needsUpload || $0.pendingDelete || $0.lastError != nil || $0.heldReason != nil }
        ))) ?? []

        var kinds: [String: Int] = [:]
        // reason → (givenUp, total, kinds)
        var problems: [String: (givenUp: Bool, count: Int, kinds: [String: Int])] = [:]
        let held = "generation"

        for state in states {
            if state.heldReason == held { report.heldForNewerVersion += 1 }
            if state.pendingDelete { report.waitingToDelete += 1 }
            if state.needsUpload {
                report.waiting += 1
                kinds[state.kind, default: 0] += 1
                if state.isStuck { report.stuck += 1 }
                if state.pendingPayload == nil { report.nothingToSend += 1 }
            }
            // A reason on a record that has nothing owed any more is history: it got through since.
            guard let reason = state.lastError, state.needsUpload || state.pendingDelete else { continue }
            var entry = problems[reason] ?? (state.isStuck, 0, [:])
            entry.givenUp = entry.givenUp || state.isStuck
            entry.count += 1
            entry.kinds[state.kind, default: 0] += 1
            problems[reason] = entry
        }

        report.byKind = kinds.map { SyncReportCount(name: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        report.problems = problems.map { reason, entry in
            SyncProblem(
                reason: reason,
                explanation: SyncDiagnostics.explain(reason),
                givenUp: entry.givenUp,
                records: entry.count,
                kinds: entry.kinds.map { SyncReportCount(name: $0.key, count: $0.value) }
                    .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            )
        }
        .sorted { ($0.records, $1.reason) > ($1.records, $0.reason) }
        return report
    }

    /// The whole report as text, for Copy and Share. What someone would need to tell a bug apart
    /// from a full iCloud account.
    func reportText(_ report: SyncReport) -> String {
        var lines: [String] = ["Die Kartei — sync report", Date.now.formatted()]
        let info = Bundle.main.infoDictionary
        lines.append("app \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")) · \(SyncManager.environmentName)")
        lines.append("last sync: \(lastSyncedAt?.formatted() ?? "never this launch")")
        if let lastError { lines.append("last sync error: \(lastError)") }
        lines.append("waiting \(report.waiting) · given up \(report.stuck) · deletes \(report.waitingToDelete) · nothing to send \(report.nothingToSend) · held for a newer version \(report.heldForNewerVersion)")
        if !report.byKind.isEmpty {
            lines.append("")
            lines.append("waiting by kind:")
            lines += report.byKind.map { "  \($0.name) \($0.count)" }
        }
        if !report.problems.isEmpty {
            lines.append("")
            lines.append("reasons:")
            for problem in report.problems {
                lines.append("  \(problem.reason) — \(problem.records) record(s)\(problem.givenUp ? ", given up" : "")")
                lines.append("    " + problem.kinds.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
            }
        }
        for peer in peers() {
            lines.append("")
            lines.append("device \(peer.model)\(peer.isThisDevice ? " (this one)" : "") \(peer.appVersion) · synced \(peer.lastSyncAt?.formatted() ?? "—") · pending \(peer.hasPending) · stuck \(peer.stuck)")
        }
        if !events.isEmpty {
            lines.append("")
            lines.append("recent:")
            lines += events.prefix(40).map { "  " + $0 }
        }
        return lines.joined(separator: "\n")
    }
}
