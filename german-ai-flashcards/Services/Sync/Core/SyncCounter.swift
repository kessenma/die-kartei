import Foundation

/// A counter that merges exactly, however many times the same states meet: a PN-counter CRDT.
///
/// Each replica (an install of the app, or a bootstrap slot for data that existed before sync)
/// owns one slot. It only ever raises its own `p` (increments) and `n` (decrements). Merging takes
/// the pointwise max. The value is `Σp − Σn`.
///
/// Why not "last synced value + my delta": that needs a stored ancestor, and anything that clears
/// the ancestor (Delete iCloud Data, an account round trip, Debug↔TestFlight switching databases)
/// makes the next merge sum two copies of the same history. That doubles XP and reviews with no way
/// back. Pointwise max is idempotent: re-uploading everything is always safe.
nonisolated struct SyncCounter: Hashable, Sendable, Codable {
    var p: [String: Int64] = [:]
    var n: [String: Int64] = [:]

    init() {}

    init(p: [String: Int64], n: [String: Int64] = [:]) {
        self.p = p
        self.n = n
    }

    /// Reads a counter out of a payload field. A bare number (from before the field became a
    /// counter) is taken as one `legacy` slot, so it merges by max against other legacy copies.
    init(json: SyncJSON?) {
        switch json {
        case .object(let o):
            p = Self.slots(o["p"])
            n = Self.slots(o["n"])
        case .some(let v):
            if let i = v.int64Value { p = ["legacy": i] }
        case .none:
            break
        }
    }

    var json: SyncJSON {
        .object([
            "p": .object(p.mapValues { .int($0) }),
            "n": .object(n.mapValues { .int($0) }),
        ])
    }

    var value: Int64 { p.values.reduce(0, +) - n.values.reduce(0, +) }

    /// Pointwise max: commutative, associative, idempotent.
    func merged(with other: SyncCounter) -> SyncCounter {
        SyncCounter(
            p: p.merging(other.p, uniquingKeysWith: Swift.max),
            n: n.merging(other.n, uniquingKeysWith: Swift.max)
        )
    }

    /// Credit a change to one slot. Positive raises `p`, negative raises `n`.
    mutating func credit(_ delta: Int64, to slot: String) {
        if delta > 0 {
            p[slot, default: 0] += delta
        } else if delta < 0 {
            n[slot, default: 0] += -delta
        }
    }

    /// Bring the counter up to the model's current value, crediting the difference to `slot`.
    /// The model is the truth for this replica; the counter remembers who contributed what.
    mutating func absorb(localValue: Int64, slot: String) {
        credit(localValue - value, to: slot)
    }

    private static func slots(_ json: SyncJSON?) -> [String: Int64] {
        guard let o = json?.objectValue else { return [:] }
        var out: [String: Int64] = [:]
        for (k, v) in o { if let i = v.int64Value { out[k] = i } }
        return out
    }
}
