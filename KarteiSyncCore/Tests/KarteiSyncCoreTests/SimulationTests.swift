import Foundation
import Testing
@testable import KarteiSyncCore

// Replicas drive SyncRecordLogic against FakeSyncServer the way the app drives it against
// CKSyncEngine: push dirty records (resolving conflicts), then pull changes. Random interleavings
// must always converge, and counters must be *conserved*: the final value equals exactly the sum of
// every increment any replica ever made. That one property rules out both lost reviews and doubled
// XP, including across zone resets and database switches.

private let spec = SyncKindSpec(
    kind: "Row",
    rules: [
        "count": .counter,
        "seconds": .counter,
        "best": .max,
        "tags": .set(idField: "id", item: .lww, sortBy: nil),
        "picks": .counterMap,
    ]
)

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private final class Replica {
    let slot: String
    var models: [String: SyncPayload] = [:]
    var copies: [String: SyncRecordCopies] = [:]
    var tags: [String: Int] = [:]
    var dirty: Set<String> = []
    var token = 0
    var clock: Double = 0

    init(slot: String) { self.slot = slot }

    func tick() -> Double { clock += 1; return clock }

    /// Seed a row that existed before sync, credited to a bootstrap slot.
    func seed(_ name: String, _ model: SyncPayload, bootstrap: String) {
        models[name] = model
        var c = SyncRecordCopies()
        SyncRecordLogic.noteLocal(&c, known: model, spec: spec, slot: bootstrap, now: tick())
        copies[name] = c
        dirty.insert(name)
    }

    func edit(_ name: String, _ change: (inout SyncPayload) -> Void) {
        var model = models[name] ?? [:]
        change(&model)
        models[name] = model
        var c = copies[name] ?? SyncRecordCopies()
        if SyncRecordLogic.noteLocal(&c, known: model, spec: spec, slot: slot, now: tick()) { dirty.insert(name) }
        copies[name] = c
    }

    func push(_ server: FakeSyncServer) {
        for name in dirty.sorted() {
            var attempts = 0
            while attempts < 10 {
                attempts += 1
                guard let payload = copies[name]?.pending else { dirty.remove(name); break }
                switch server.save(name, payload: payload, basedOn: tags[name]) {
                case .saved(let tag):
                    SyncRecordLogic.didSave(&copies[name, default: .init()], sent: payload)
                    tags[name] = tag
                    dirty.remove(name)
                case .conflict(let remote, let tag):
                    receive(name, remote: remote, tag: tag)
                    if copies[name]?.pending == nil { dirty.remove(name) }
                case .unknownItem:
                    tags[name] = nil
                    SyncRecordLogic.forgetServer(&copies[name, default: .init()])
                }
                if !dirty.contains(name) { break }
            }
        }
    }

    func pull(_ server: FakeSyncServer) {
        let changes = server.changes(since: token)
        for (name, stored) in changes.changed where tags[name] != stored.tag {
            receive(name, remote: stored.payload, tag: stored.tag)
            if copies[name]?.pending != nil { dirty.insert(name) }
        }
        token = changes.token
    }

    private func receive(_ name: String, remote: SyncPayload, tag: Int) {
        var c = copies[name] ?? SyncRecordCopies()
        let result = SyncRecordLogic.receive(&c, remote: remote, known: models[name], spec: spec, slot: slot, now: tick())
        if let apply = result.apply { models[name] = SyncMerge.flatten(apply, spec: spec) }
        copies[name] = c
        tags[name] = tag
    }

    /// Zone deleted, account round trip, or a different CloudKit database: forget the server.
    func forgetServer() {
        for name in copies.keys { SyncRecordLogic.forgetServer(&copies[name]!) }
        tags = [:]
        token = 0
        dirty = Set(copies.compactMap { $0.value.pending == nil ? nil : $0.key })
    }
}

private func settle(_ replicas: [Replica], _ server: FakeSyncServer) {
    for _ in 0..<30 {
        for r in replicas { r.push(server); r.pull(server) }
        if replicas.allSatisfy({ $0.dirty.isEmpty }) {
            for r in replicas { r.pull(server) }
            if replicas.allSatisfy({ $0.dirty.isEmpty }) { return }
        }
    }
}

private func count(_ model: SyncPayload?, _ key: String) -> Int64 { model?[key]?.int64Value ?? 0 }

@Suite struct SimulationTests {
    private let rows = ["day-1", "day-2", "card-1"]

    private func run(seed: UInt64, replicaCount: Int, steps: Int, disruptions: Bool) {
        var rng = SplitMix64(state: seed)
        let server = FakeSyncServer()
        let replicas = (0..<replicaCount).map { Replica(slot: "r\($0)") }
        var expected: [String: [String: Int64]] = [:]  // row → counter → total

        // Independent pre-sync histories on two devices for the same natural key: must sum.
        replicas[0].seed("day-1", ["count": .int(5)], bootstrap: "store-0")
        replicas[1 % replicaCount].seed("day-1", ["count": .int(7)], bootstrap: "store-1")
        expected["day-1", default: [:]]["count", default: 0] += 5 + 7

        for _ in 0..<steps {
            let r = replicas[Int(rng.next() % UInt64(replicaCount))]
            let row = rows[Int(rng.next() % UInt64(rows.count))]
            switch rng.next() % 9 {
            case 0, 1, 2:
                let by = Int64(rng.next() % 5) + 1
                r.edit(row) { $0["count"] = .int(count($0, "count") + by) }
                expected[row, default: [:]]["count", default: 0] += by
            case 3:
                let by = Int64(rng.next() % 90) + 10
                r.edit(row) { $0["seconds"] = .int(count($0, "seconds") + by) }
                expected[row, default: [:]]["seconds", default: 0] += by
            case 4:
                let pick = ["der", "die", "das"][Int(rng.next() % 3)]
                r.edit(row) {
                    var picks = $0["picks"]?.objectValue ?? [:]
                    picks[pick] = .int((picks[pick]?.int64Value ?? 0) + 1)
                    $0["picks"] = .object(picks)
                }
                expected[row, default: [:]]["picks." + pick, default: 0] += 1
            case 5:
                let v = Int64(rng.next() % 100)
                r.edit(row) { $0["best"] = .int(Swift.max(count($0, "best"), v)) }
            case 6:
                let tag = "t\(rng.next() % 4)"
                r.edit(row) {
                    var tags = $0["tags"]?.arrayValue ?? []
                    if let i = tags.firstIndex(where: { $0["id"]?.stringValue == tag }) { tags.remove(at: i) }
                    else { tags.append(.object(["id": .string(tag)])) }
                    $0["tags"] = .array(tags)
                }
            case 7:
                r.push(server)
            default:
                r.pull(server)
            }

            if disruptions, rng.next() % 40 == 0 {
                // Delete iCloud Data: the zone vanishes and every device forgets the server.
                server.wipe()
                for rep in replicas { rep.forgetServer() }
            }
        }

        settle(replicas, server)

        // Convergence: every replica holds identical models.
        let first = replicas[0].models
        for r in replicas.dropFirst() {
            #expect(r.models == first, "replica \(r.slot) diverged (seed \(seed))")
        }
        // Conservation: no lost and no doubled increments.
        for (row, counters) in expected {
            for (field, total) in counters {
                let actual: Int64
                if field.hasPrefix("picks.") {
                    actual = first[row]?["picks"]?[String(field.dropFirst(6))]?.int64Value ?? 0
                } else {
                    actual = count(first[row], field)
                }
                #expect(actual == total, "\(row).\(field): \(actual) ≠ \(total) (seed \(seed))")
            }
        }
    }

    @Test(arguments: 1...60)
    func randomInterleavingsConvergeAndConserve(seed: Int) {
        run(seed: UInt64(seed), replicaCount: 2 + seed % 2, steps: 250, disruptions: false)
    }

    @Test(arguments: 1...60)
    func zoneResetsNeverDoubleCounters(seed: Int) {
        run(seed: UInt64(seed) &* 7919, replicaCount: 2 + seed % 2, steps: 300, disruptions: true)
    }

    @Test func debugToTestFlightDatabaseSwitchDoesNotDouble() {
        let production = FakeSyncServer(), development = FakeSyncServer()
        let phone = Replica(slot: "phone"), pad = Replica(slot: "pad")
        phone.edit("day") { $0["count"] = .int(10) }
        pad.edit("day") { $0["count"] = .int(4) }
        settle([phone, pad], production)
        #expect(count(phone.models["day"], "count") == 14)

        // The phone installs a Debug build: a different database with the same store.
        phone.forgetServer()
        phone.edit("day") { $0["count"] = .int(count($0, "count") + 3) }
        settle([phone], development)
        // Back to TestFlight.
        phone.forgetServer()
        phone.edit("day") { $0["count"] = .int(count($0, "count") + 1) }
        settle([phone, pad], production)
        #expect(count(phone.models["day"], "count") == 18)
        #expect(pad.models == phone.models)
    }

    @Test func offlineForAWeekThenReconnect() {
        let server = FakeSyncServer()
        let phone = Replica(slot: "phone"), pad = Replica(slot: "pad")
        settle([phone, pad], server)
        for _ in 0..<50 { pad.edit("day") { $0["count"] = .int(count($0, "count") + 1) } }   // offline
        for _ in 0..<30 {
            phone.edit("day") { $0["count"] = .int(count($0, "count") + 2) }
            phone.push(server); phone.pull(server)
        }
        settle([phone, pad], server)
        #expect(count(pad.models["day"], "count") == 110)
        #expect(pad.models == phone.models)
    }

    @Test func digestsAgreeOnceSettled() {
        let server = FakeSyncServer()
        let a = Replica(slot: "a"), b = Replica(slot: "b")
        a.edit("x") { $0["count"] = .int(3) }
        b.edit("y") { $0["best"] = .int(9) }
        settle([a, b], server)
        func digest(_ r: Replica) -> SyncDigest {
            SyncDigest(entries: r.copies.compactMap { name, c in c.server.map { (name, $0.syncHash) } })
        }
        #expect(digest(a) == digest(b))
    }
}
