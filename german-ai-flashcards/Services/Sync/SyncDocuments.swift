import Foundation
import SwiftData

/// Synced records that don't live in SwiftData: progress kept in UserDefaults and the JSON files in
/// Application Support. SwiftData history can't see these, so the tracker compares them with their
/// last synced copy on every pass (a handful of small records, so that's cheap).
@MainActor
protocol SyncDocumentKind {
    var spec: SyncKindSpec { get }
    /// The records this kind has on this device, with their current fields.
    func localRecords() -> [(name: SyncRecordName, known: SyncPayload)]
    /// Write a server copy (flattened) into local storage.
    func apply(_ flat: SyncPayload, name: SyncRecordName)
    /// Records of this kind can disappear locally (files); a vanished one is deleted on the server.
    var tracksDeletions: Bool { get }
    func apply(_ flat: SyncPayload, name: SyncRecordName, file: URL?)
    /// The record is gone from the server. `payload` is the last copy this device had.
    func delete(_ name: SyncRecordName, payload: SyncPayload?)
    /// The asset that travels with a record, if any.
    func fileURL(for name: SyncRecordName, payload: SyncPayload) -> URL?
}

extension SyncDocumentKind {
    var tracksDeletions: Bool { false }
    func apply(_ flat: SyncPayload, name: SyncRecordName, file: URL?) { apply(flat, name: name) }
    func delete(_ name: SyncRecordName, payload: SyncPayload?) {}
    func fileURL(for name: SyncRecordName, payload: SyncPayload) -> URL? { nil }
}

@MainActor
enum SyncDocuments {
    static let kinds: [any SyncDocumentKind] = [
        ProgressSyncDocument(),
        JourneySyncDocument(),
        PlacementAttemptsSyncDocument(),
        FileSyncDocument(),
        DeviceSyncDocument(),
    ]

    static let byKind: [String: any SyncDocumentKind] =
        Dictionary(uniqueKeysWithValues: kinds.map { ($0.spec.kind, $0) })

    /// Local fields for one document record, or nil if this device doesn't have it.
    static func known(for name: SyncRecordName) -> SyncPayload? {
        byKind[name.kind]?.localRecords().first { $0.name == name }?.known
    }
}

// MARK: - Progress (UserDefaults)

/// The progress that lives in UserDefaults: the declared level, the placement result, badge dates,
/// onboarding and celebration flags, and the conversation record. Without it, a second device would
/// show a reset level, re-dated badges and re-fired celebrations.
struct ProgressSyncDocument: SyncDocumentKind {
    static let name = SyncRecordName(kind: "Progress", id: SyncNameUUID.make("progress"))

    let spec = SyncKindSpec(
        kind: "Progress",
        rules: [
            "placementSeen": .or,
            "placementHandoffAt": .max,
            "badges": .minMap,
            "badgesSeeded": .or,
            "onboardingV2": .or,
            "onboardingWizard": .or,
            "chatBestUnaidedStreak": .max,
            "maxLevelSeen": .max,
            "fired": .union,
        ],
        // The level and whether the learner declared it are one choice.
        groups: [SyncFieldGroup(fields: ["germanLevel", "germanLevelDeclared"], orderBy: [])]
    )

    private var defaults: UserDefaults { .standard }
    private static let celebrationPrefix = "celebration."

    func localRecords() -> [(name: SyncRecordName, known: SyncPayload)] {
        var f = SyncFields()
        f.set("germanLevel", defaults.string(forKey: "german.level"))
        f.set("germanLevelDeclared", defaults.bool(forKey: "german.level.declared"))
        f.set("placementResult", jsonData: defaults.data(forKey: "placement.result"))
        f.set("placementSeen", defaults.bool(forKey: "placement.seen"))
        f.set("placementHandoffAt", defaults.object(forKey: "placement.handoff.lastAttemptAt") as? Date)
        f.set("badges", json: badgeDates())
        f.set("badgesSeeded", defaults.bool(forKey: "achievements.seeded"))
        f.set("onboardingV2", defaults.bool(forKey: "hasSeenOnboardingV2"))
        f.set("onboardingWizard", defaults.bool(forKey: "hasSeenOnboardingWizard"))
        f.set("chatBestUnaidedStreak", defaults.integer(forKey: "chatBestUnaidedStreak"))
        f.set("maxLevelSeen", defaults.object(forKey: "celebration.maxLevelSeen") as? Int)
        f.set("fired", firedCelebrations())
        return [(Self.name, f.payload)]
    }

    func apply(_ flat: SyncPayload, name: SyncRecordName) {
        let manager = SyncManager.shared.modelManager
        if let level = flat.string("germanLevel") {
            defaults.set(level, forKey: "german.level")
            if manager?.germanLevelRaw != level { manager?.germanLevelRaw = level }
        }
        if let declared = flat.bool("germanLevelDeclared") {
            defaults.set(declared, forKey: "german.level.declared")
            if manager?.germanLevelIsDeclared != declared { manager?.germanLevelIsDeclared = declared }
        }
        if let result = flat.jsonData("placementResult") { defaults.set(result, forKey: "placement.result") }
        if flat.bool("placementSeen") == true { defaults.set(true, forKey: "placement.seen") }
        if let at = flat.date("placementHandoffAt") { defaults.set(at, forKey: "placement.handoff.lastAttemptAt") }
        if let badges = flat["badges"]?.objectValue {
            let dates = badges.compactMapValues { $0.doubleValue.map(Date.init(timeIntervalSinceReferenceDate:)) }
            defaults.set(try? JSONEncoder().encode(dates), forKey: "achievements.earnedAt")
        }
        if flat.bool("badgesSeeded") == true { defaults.set(true, forKey: "achievements.seeded") }
        if flat.bool("onboardingV2") == true { defaults.set(true, forKey: "hasSeenOnboardingV2") }
        if flat.bool("onboardingWizard") == true { defaults.set(true, forKey: "hasSeenOnboardingWizard") }
        if let best = flat.int("chatBestUnaidedStreak") {
            defaults.set(best, forKey: "chatBestUnaidedStreak")
            if let manager, manager.chatBestUnaidedStreak != best { manager.chatBestUnaidedStreak = best }
        }
        if let level = flat.int("maxLevelSeen") { defaults.set(level, forKey: "celebration.maxLevelSeen") }
        // Celebrations already shown on another device are marked shown here, so they don't fire twice.
        for key in flat.strings("fired") ?? [] { defaults.set(true, forKey: Self.celebrationPrefix + key) }
    }

    /// `achievements.earnedAt` is `[badgeID: Date]` written by a default `JSONEncoder` (dates as
    /// seconds since the reference date), which is already the payload's date form.
    private func badgeDates() -> SyncJSON? {
        guard let data = defaults.data(forKey: "achievements.earnedAt") else { return nil }
        return try? SyncJSON(data: data)
    }

    private func firedCelebrations() -> [String] {
        defaults.dictionaryRepresentation()
            .filter { $0.key.hasPrefix(Self.celebrationPrefix) && ($0.value as? Bool) == true }
            .map { String($0.key.dropFirst(Self.celebrationPrefix.count)) }
            .sorted()
    }
}

// MARK: - Journey (Progress/journey.json)

/// "Dein Weg": weekly snapshots, recorded milestones, and the sets that stop a milestone from being
/// announced twice. Each device takes its own weekly snapshot, so the merge keeps one per ISO week
/// (the later). The same milestone seen on both devices is kept once (the earlier).
struct JourneySyncDocument: SyncDocumentKind {
    static let name = SyncRecordName(kind: "Journey", id: SyncNameUUID.make("journey"))

    let spec = SyncKindSpec(
        kind: "Journey",
        rules: [
            "snapshots": .set(idField: "takenAt", item: .lww, sortBy: "takenAt"),
            "milestones": .set(idField: "id", item: .lww, sortBy: "date"),
            "seenComebackWords": .union,
            "seenCompletedLayers": .union,
            "probeLastAskedAt": .max,
        ],
        normalize: JourneySyncDocument.normalize
    )

    func localRecords() -> [(name: SyncRecordName, known: SyncPayload)] {
        let doc = ProgressSnapshotStore.document()
        var f = SyncFields()
        f.set("snapshots", json: try? SyncJSON(encoding: doc.snapshots))
        f.set("milestones", json: try? SyncJSON(encoding: doc.milestones))
        f.set("seenComebackWords", doc.seenComebackWords.sorted())
        f.set("seenCompletedLayers", doc.seenCompletedLayers.sorted())
        f.set("probeLastAskedAt", doc.probe?.lastAskedAt)
        return [(Self.name, f.payload)]
    }

    func apply(_ flat: SyncPayload, name: SyncRecordName) {
        var doc = ProgressSnapshotStore.document()
        if let s = try? flat["snapshots"]?.decoded(as: [ProgressSnapshot].self) { doc.snapshots = s }
        if let m = try? flat["milestones"]?.decoded(as: [RecordedMilestone].self) { doc.milestones = m }
        doc.seenComebackWords = flat.strings("seenComebackWords") ?? doc.seenComebackWords
        doc.seenCompletedLayers = flat.strings("seenCompletedLayers") ?? doc.seenCompletedLayers
        if let asked = flat.date("probeLastAskedAt") { doc.probe = ProbeState(lastAskedAt: asked) }
        ProgressSnapshotStore.save(doc)
    }

    /// One snapshot per ISO week (the latest), one milestone per (kind, title) (the earliest), then
    /// the store's caps. Deterministic, so both devices normalize to the same bytes.
    nonisolated static func normalize(_ payload: SyncPayload) -> SyncPayload {
        var out = payload
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        if let snapshots = payload["snapshots"]?.arrayValue {
            var byWeek: [String: SyncJSON] = [:]
            for s in snapshots {
                guard let t = s["takenAt"]?.doubleValue else { continue }
                let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date(timeIntervalSinceReferenceDate: t))
                let week = "\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
                if let kept = byWeek[week], (kept["takenAt"]?.doubleValue ?? 0) >= t { continue }
                byWeek[week] = s
            }
            let sorted = byWeek.values.sorted { ($0["takenAt"]?.doubleValue ?? 0) < ($1["takenAt"]?.doubleValue ?? 0) }
            out["snapshots"] = .array(Array(sorted.suffix(ProgressSnapshotStore.snapshotCap)))
        }
        if let milestones = payload["milestones"]?.arrayValue {
            var byKey: [String: SyncJSON] = [:]
            for m in milestones {
                let key = "\(m["kindRaw"]?.stringValue ?? "")\u{1F}\(m["title"]?.stringValue ?? "")"
                let t = m["date"]?.doubleValue ?? 0
                if let kept = byKey[key] {
                    let keptT = kept["date"]?.doubleValue ?? 0
                    if keptT < t || (keptT == t && (kept["id"]?.stringValue ?? "") <= (m["id"]?.stringValue ?? "")) { continue }
                }
                byKey[key] = m
            }
            let sorted = byKey.values.sorted {
                let a = $0["date"]?.doubleValue ?? 0, b = $1["date"]?.doubleValue ?? 0
                return a != b ? a < b : ($0["id"]?.stringValue ?? "") < ($1["id"]?.stringValue ?? "")
            }
            out["milestones"] = .array(Array(sorted.suffix(ProgressSnapshotStore.milestoneCap)))
        }
        return out
    }
}

// MARK: - Placement attempts (Placement/attempts.json)

/// Every finished placement check with its answers, merged by attempt id, newest 40 kept.
struct PlacementAttemptsSyncDocument: SyncDocumentKind {
    static let name = SyncRecordName(kind: "PlacementAttempts", id: SyncNameUUID.make("placement-attempts"))

    let spec = SyncKindSpec(
        kind: "PlacementAttempts",
        rules: ["attempts": .set(idField: "id", item: .lww, sortBy: nil)],
        normalize: PlacementAttemptsSyncDocument.normalize
    )

    func localRecords() -> [(name: SyncRecordName, known: SyncPayload)] {
        var f = SyncFields()
        f.set("attempts", json: try? SyncJSON(encoding: PlacementAttemptStore.attempts()))
        return [(Self.name, f.payload)]
    }

    func apply(_ flat: SyncPayload, name: SyncRecordName) {
        guard let attempts = try? flat["attempts"]?.decoded(as: [PlacementAttempt].self) else { return }
        PlacementAttemptStore.replaceAll(attempts)
    }

    /// Newest first by the result's `takenAt`, capped like the store.
    nonisolated static func normalize(_ payload: SyncPayload) -> SyncPayload {
        guard let attempts = payload["attempts"]?.arrayValue else { return payload }
        func takenAt(_ a: SyncJSON) -> Double { a["result"]?["takenAt"]?.doubleValue ?? 0 }
        let sorted = attempts.sorted {
            takenAt($0) != takenAt($1) ? takenAt($0) > takenAt($1)
                : ($0["id"]?.stringValue ?? "") < ($1["id"]?.stringValue ?? "")
        }
        var out = payload
        out["attempts"] = .array(Array(sorted.prefix(PlacementAttemptStore.cap)))
        return out
    }
}

// MARK: - Files (pictures and handouts)

/// Card pictures, story illustrations, class handouts and saved job-posting PDFs. The rows that
/// use them store bare file names resolved against Application Support, so a file only has to
/// arrive at the same relative path for the row on the other device to find it. Each file is one
/// record whose payload is its path, size and modification date; the bytes travel as a CKAsset.
///
/// A redraw writes a new file (or overwrites `00.png`), which changes the modification date and
/// sends it again. A deleted file is deleted everywhere. Card-picture drafts (`draft-*`) never
/// leave the device.
struct FileSyncDocument: SyncDocumentKind {
    static let roots = ["CardImages", "StoryImages", "ClassNotes", "JobPostings"]

    let spec = SyncKindSpec(kind: "File")
    var tracksDeletions: Bool { true }

    private var base: URL { URL.applicationSupportDirectory }

    func localRecords() -> [(name: SyncRecordName, known: SyncPayload)] {
        let fm = FileManager.default
        var out: [(SyncRecordName, SyncPayload)] = []
        for root in Self.roots {
            let dir = base.appendingPathComponent(root, isDirectory: true)
            // The enumerator can hand back /private/var paths for a /var root: compare resolved paths.
            let dirPath = dir.resolvingSymlinksInPath().path + "/"
            guard let files = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                                            options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in files {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true, !url.lastPathComponent.hasPrefix("draft-")
                else { continue }
                let filePath = url.resolvingSymlinksInPath().path
                guard filePath.hasPrefix(dirPath) else { continue }
                let path = root + "/" + filePath.dropFirst(dirPath.count)
                var f = SyncFields()
                f.set("path", path)
                f.set("size", values.fileSize)
                // Whole seconds: the date is written back after a download, and sub-second
                // precision doesn't survive every file system.
                f.set("modified", values.contentModificationDate.map { $0.timeIntervalSinceReferenceDate.rounded(.down) })
                out.append((SyncRecordName(kind: spec.kind, naturalKey: path), f.payload))
            }
        }
        return out
    }

    func apply(_ flat: SyncPayload, name: SyncRecordName) {}

    func apply(_ flat: SyncPayload, name: SyncRecordName, file: URL?) {
        guard let path = flat.string("path"), let file, let dest = destination(path) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: dest)
        guard (try? fm.copyItem(at: file, to: dest)) != nil else { return }
        // Match the sender's date so the next pass doesn't see a "changed" file and send it back.
        if let modified = flat.double("modified") {
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceReferenceDate: modified)], ofItemAtPath: dest.path)
        }
    }

    func delete(_ name: SyncRecordName, payload: SyncPayload?) {
        guard let path = payload?.string("path"), let dest = destination(path) else { return }
        try? FileManager.default.removeItem(at: dest)
    }

    func fileURL(for name: SyncRecordName, payload: SyncPayload) -> URL? {
        payload.string("path").flatMap(destination)
    }

    /// Only paths inside the four synced folders, never `..` escapes.
    private func destination(_ path: String) -> URL? {
        guard let root = path.split(separator: "/").first, Self.roots.contains(String(root)),
              !path.contains("..") else { return nil }
        return base.appendingPathComponent(path)
    }
}
