import Foundation

// MARK: - Rules

/// How to settle one item of a set or keyed field that both sides changed.
nonisolated enum SyncItemRule: Sendable {
    /// Take the payload-level winner's copy (later `_t`, then canonical bytes).
    case lww
    /// Take the copy with the larger number or date in this field, then the payload-level winner's.
    case lwwBy(String)
}

/// How one payload field merges when both devices changed the row.
nonisolated enum SyncFieldRule: Sendable {
    /// Three-way against the last server copy: a side that didn't change the field takes the
    /// other side's value. If both changed it, the payload-level winner's value is kept.
    case lww
    /// A PN counter (`SyncCounter`). The model holds a plain integer; the payload holds the slots.
    case counter
    /// An object whose values are each a PN counter (e.g. wrong-pick tallies per answer).
    case counterMap
    /// The larger number or date.
    case max
    /// The smaller number or date.
    case min
    /// True if either side is true.
    case or
    /// An array of strings that only grows (fired celebrations): the sorted union.
    case union
    /// An object of numbers or dates where each key keeps its smallest value (badge earned dates).
    case minMap
    /// An array of objects identified by `idField`. Adds from either side are kept. A removal
    /// (the item is in the ancestor but gone from one side) wins, unless the other side edited the
    /// item since the ancestor: then the edit wins. Output is sorted by `sortBy`, then id, so both
    /// devices produce identical bytes.
    case set(idField: String, lowercasedID: Bool = false, item: SyncItemRule = .lww, sortBy: String? = nil)
    /// An object whose keys are the ids. Same semantics as `set`.
    case keyed(item: SyncItemRule = .lww)
}

/// Fields that must travel together, taken whole from one side: an SRS schedule must never be
/// half one review and half another. Conflicting copies are ordered by `orderBy` (numbers or
/// dates, missing = lowest, larger wins), then by the payload-level winner.
nonisolated struct SyncFieldGroup: Sendable {
    let fields: [String]
    let orderBy: [String]
}

/// Everything the merge engine needs to know about one kind of record.
nonisolated struct SyncKindSpec: Sendable {
    let kind: String
    /// Bump only if a field's *meaning* changes (see `SyncPayloadKey.generation`).
    var generation: Int64 = 1
    var rules: [String: SyncFieldRule] = [:]
    var groups: [SyncFieldGroup] = []
    /// A deterministic clean-up run on every merge result (e.g. drop entries older than a reset).
    var normalize: (@Sendable (SyncPayload) -> SyncPayload)? = nil

    init(
        kind: String,
        generation: Int64 = 1,
        rules: [String: SyncFieldRule] = [:],
        groups: [SyncFieldGroup] = [],
        normalize: (@Sendable (SyncPayload) -> SyncPayload)? = nil
    ) {
        self.kind = kind
        self.generation = generation
        self.rules = rules
        self.groups = groups
        self.normalize = normalize
    }

    func rule(for key: String) -> SyncFieldRule {
        if groups.contains(where: { $0.fields.contains(key) }) { return .lww }
        return rules[key] ?? .lww
    }

    /// A payload from a newer breaking generation is held back, not applied.
    func canRead(_ payload: SyncPayload) -> Bool {
        (payload[SyncPayloadKey.generation]?.int64Value ?? 1) <= generation
    }
}

// MARK: - Engine

/// The pure merge engine. Everything here is deterministic and symmetric:
/// `merge(a, L, R) == merge(a, R, L)`, and `merge(a, X, X) == X`. Two devices that saw the same
/// server copies compute identical bytes.
nonisolated enum SyncMerge {

    // MARK: Three-way merge

    /// Merge a local and a remote payload against the last server copy both descend from.
    /// `ancestor == nil` means no common copy is known (first sync, or after a zone reset): every
    /// difference is then a conflict, settled by the rules (counters still merge exactly).
    static func merge(
        ancestor a: SyncPayload?,
        local l: SyncPayload,
        remote r: SyncPayload,
        spec: SyncKindSpec
    ) -> SyncPayload {
        if l == r { return l }
        let localWins = payloadWinnerIsLocal(l, r)
        var out: SyncPayload = [:]
        var handled = Set<String>()

        for group in spec.groups {
            handled.formUnion(group.fields)
            let fromLocal = pickGroupFromLocal(group, a, l, r, localWins: localWins)
            for field in group.fields {
                if let v = (fromLocal ? l : r)[field], v != .null { out[field] = v }
            }
        }

        let keys = Set(l.keys).union(r.keys).subtracting(handled).subtracting(SyncPayloadKey.reserved)
        for key in keys {
            let merged = mergeField(
                spec.rule(for: key),
                ancestor: a.map { $0[key] ?? .null },
                local: l[key] ?? .null,
                remote: r[key] ?? .null,
                localWins: localWins
            )
            if merged != .null { out[key] = merged }
        }

        let times = [l, r].compactMap { $0[SyncPayloadKey.modifiedAt]?.doubleValue }
        if let t = times.max() { out[SyncPayloadKey.modifiedAt] = .number(t) }
        let generations = [l, r].map { $0[SyncPayloadKey.generation]?.int64Value ?? 1 }
        out[SyncPayloadKey.generation] = .int(generations.max() ?? 1)

        if let normalize = spec.normalize { out = normalize(out) }
        return out
    }

    // MARK: Compose (local → payload)

    /// Build the payload that describes the local model, starting from `base` (the pending or
    /// server copy) so unknown fields from newer builds and every counter slot survive.
    ///
    /// - `known`: the fields this build knows, as the model holds them (counters as plain ints).
    ///   `.null` means "this field is empty".
    /// - `slot`: who gets credit for counter changes (this install's replica id, or a bootstrap slot
    ///   for data that existed before sync was switched on).
    /// - `now`: stamped into `_t` when a non-counter field changed.
    static func compose(
        base: SyncPayload?,
        known: SyncPayload,
        spec: SyncKindSpec,
        slot: String,
        now: Double
    ) -> SyncPayload {
        var out = base ?? [:]
        var changed = base == nil
        for (key, value) in known where !SyncPayloadKey.reserved.contains(key) {
            switch spec.rule(for: key) {
            case .counter:
                var counter = SyncCounter(json: out[key])
                counter.absorb(localValue: value.int64Value ?? 0, slot: slot)
                out[key] = counter.p.isEmpty && counter.n.isEmpty ? nil : counter.json
            case .counterMap:
                let local = value.objectValue ?? [:]
                var existing = out[key]?.objectValue ?? [:]
                for k in Set(local.keys).union(existing.keys) {
                    var counter = SyncCounter(json: existing[k])
                    counter.absorb(localValue: local[k]?.int64Value ?? 0, slot: slot)
                    existing[k] = counter.json
                }
                out[key] = existing.isEmpty ? nil : .object(existing)
            default:
                let newValue: SyncJSON? = value == .null ? nil : value
                if out[key] != newValue {
                    out[key] = newValue
                    changed = true
                }
            }
        }
        if changed { out[SyncPayloadKey.modifiedAt] = .number(now) }
        let baseGeneration = base?[SyncPayloadKey.generation]?.int64Value ?? 1
        out[SyncPayloadKey.generation] = .int(Swift.max(baseGeneration, spec.generation))
        return out
    }

    // MARK: Flatten (payload → model)

    /// The payload as the model sees it: counters collapsed to their value, reserved keys dropped.
    /// Decode a DTO from `.object(flatten(...))`; keys the DTO doesn't know are ignored.
    static func flatten(_ payload: SyncPayload, spec: SyncKindSpec) -> SyncPayload {
        var out: SyncPayload = [:]
        for (key, value) in payload where !SyncPayloadKey.reserved.contains(key) {
            switch spec.rule(for: key) {
            case .counter:
                out[key] = .int(SyncCounter(json: value).value)
            case .counterMap:
                let map = value.objectValue ?? [:]
                out[key] = .object(map.mapValues { .int(SyncCounter(json: $0).value) })
            default:
                out[key] = value
            }
        }
        return out
    }

    // MARK: Field rules

    static func mergeField(
        _ rule: SyncFieldRule,
        ancestor a: SyncJSON?,
        local l: SyncJSON,
        remote r: SyncJSON,
        localWins: Bool
    ) -> SyncJSON {
        switch rule {
        case .lww:
            return threeWay(a, l, r, localWins: localWins)
        case .counter:
            if l == .null && r == .null { return .null }
            return SyncCounter(json: l).merged(with: SyncCounter(json: r)).json
        case .counterMap:
            let lm = l.objectValue ?? [:], rm = r.objectValue ?? [:]
            var out: [String: SyncJSON] = [:]
            for k in Set(lm.keys).union(rm.keys) {
                out[k] = SyncCounter(json: lm[k]).merged(with: SyncCounter(json: rm[k])).json
            }
            return out.isEmpty ? .null : .object(out)
        case .max, .min:
            guard let ln = l.doubleValue else { return r }
            guard let rn = r.doubleValue else { return l }
            if ln == rn { return localWins ? l : r }
            return (ln > rn) == (rule.isMax) ? l : r
        case .or:
            return .bool((l.boolValue ?? false) || (r.boolValue ?? false))
        case .union:
            let all = Set((l.arrayValue ?? []).compactMap(\.stringValue) + (r.arrayValue ?? []).compactMap(\.stringValue))
            if all.isEmpty && l == .null && r == .null { return .null }
            return .array(all.sorted().map(SyncJSON.string))
        case .minMap:
            let lm = l.objectValue ?? [:], rm = r.objectValue ?? [:]
            var out: [String: SyncJSON] = [:]
            for k in Set(lm.keys).union(rm.keys) {
                switch (lm[k]?.doubleValue, rm[k]?.doubleValue) {
                case let (a?, b?): out[k] = a <= b ? lm[k] : rm[k]
                case (_?, nil): out[k] = lm[k]
                case (nil, _?): out[k] = rm[k]
                case (nil, nil): break
                }
            }
            return out.isEmpty && l == .null && r == .null ? .null : .object(out)
        case let .set(idField, lowercasedID, item, sortBy):
            // Changed on one side only: take that side as it is, order included (lookups are
            // newest first; re-sorting would scramble them for nothing).
            if let a, a == l { return r }
            if let a, a == r { return l }
            let id: (SyncJSON) -> String = { element in
                if let s = element[idField]?.stringValue { return lowercasedID ? s.lowercased() : s }
                if let n = element[idField]?.doubleValue { return String(n) }
                return element.hashHex
            }
            func index(_ v: SyncJSON?) -> [String: SyncJSON]? {
                guard let v else { return nil }
                var out: [String: SyncJSON] = [:]
                for element in v.arrayValue ?? [] { out[id(element)] = element }
                return out
            }
            let merged = mergeKeyed(
                ancestor: a.map { index($0) ?? [:] },
                local: index(l) ?? [:],
                remote: index(r) ?? [:],
                item: item,
                localWins: localWins
            )
            guard !merged.isEmpty else { return l == .null && r == .null ? .null : .array([]) }
            let sorted = merged.sorted { x, y in
                if let sortBy {
                    let xs = x.value[sortBy]?.doubleValue ?? -.infinity
                    let ys = y.value[sortBy]?.doubleValue ?? -.infinity
                    if xs != ys { return xs < ys }
                }
                return x.key < y.key
            }
            return .array(sorted.map(\.value))
        case let .keyed(item):
            if let a, a == l { return r }
            if let a, a == r { return l }
            let merged = mergeKeyed(
                ancestor: a.map { $0.objectValue ?? [:] },
                local: l.objectValue ?? [:],
                remote: r.objectValue ?? [:],
                item: item,
                localWins: localWins
            )
            return merged.isEmpty && l == .null && r == .null ? .null : .object(merged)
        }
    }

    /// Set/keyed semantics: adds kept, removals honoured, edits beat a concurrent removal.
    /// `ancestor == nil` means no common copy: nothing can be told apart as removed, so union.
    static func mergeKeyed(
        ancestor a: [String: SyncJSON]?,
        local l: [String: SyncJSON],
        remote r: [String: SyncJSON],
        item: SyncItemRule,
        localWins: Bool
    ) -> [String: SyncJSON] {
        var out: [String: SyncJSON] = [:]
        for key in Set(l.keys).union(r.keys) {
            let ancestorItem = a?[key]
            switch (l[key], r[key]) {
            case let (lv?, rv?):
                out[key] = mergeItem(item, ancestor: ancestorItem, local: lv, remote: rv, localWins: localWins)
            case let (lv?, nil):
                // Remote doesn't have it: remote removed it (it was in the ancestor), or local added it.
                if let ancestorItem {
                    if lv != ancestorItem { out[key] = lv }  // local edited it: the edit wins
                } else {
                    out[key] = lv
                }
            case let (nil, rv?):
                if let ancestorItem {
                    if rv != ancestorItem { out[key] = rv }
                } else {
                    out[key] = rv
                }
            case (nil, nil):
                break
            }
        }
        return out
    }

    static func mergeItem(
        _ rule: SyncItemRule,
        ancestor a: SyncJSON?,
        local l: SyncJSON,
        remote r: SyncJSON,
        localWins: Bool
    ) -> SyncJSON {
        if l == r { return l }
        if let a {
            if a == l { return r }
            if a == r { return l }
        }
        switch rule {
        case .lww:
            return localWins ? l : r
        case .lwwBy(let field):
            let ln = l[field]?.doubleValue ?? -.infinity
            let rn = r[field]?.doubleValue ?? -.infinity
            if ln != rn { return ln > rn ? l : r }
            return localWins ? l : r
        }
    }

    // MARK: Helpers

    static func threeWay(_ a: SyncJSON?, _ l: SyncJSON, _ r: SyncJSON, localWins: Bool) -> SyncJSON {
        if l == r { return l }
        if let a {
            if a == l { return r }
            if a == r { return l }
        }
        return localWins ? l : r
    }

    /// The payload that wins true conflicts: later `_t`, then the larger canonical bytes. Total and
    /// symmetric, so both devices pick the same side.
    static func payloadWinnerIsLocal(_ l: SyncPayload, _ r: SyncPayload) -> Bool {
        let lt = l[SyncPayloadKey.modifiedAt]?.doubleValue ?? -.infinity
        let rt = r[SyncPayloadKey.modifiedAt]?.doubleValue ?? -.infinity
        if lt != rt { return lt > rt }
        return syncBytesLess(r.syncCanonicalData, l.syncCanonicalData)
    }

    private static func pickGroupFromLocal(
        _ group: SyncFieldGroup,
        _ a: SyncPayload?,
        _ l: SyncPayload,
        _ r: SyncPayload,
        localWins: Bool
    ) -> Bool {
        func project(_ p: SyncPayload) -> [String: SyncJSON] {
            var out: [String: SyncJSON] = [:]
            for f in group.fields { if let v = p[f], v != .null { out[f] = v } }
            return out
        }
        let lg = project(l), rg = project(r)
        if lg == rg { return true }
        if let a {
            let ag = project(a)
            if ag == lg { return false }
            if ag == rg { return true }
        }
        for field in group.orderBy {
            let ln = l[field]?.doubleValue ?? -.infinity
            let rn = r[field]?.doubleValue ?? -.infinity
            if ln != rn { return ln > rn }
        }
        return localWins
    }
}

private extension SyncFieldRule {
    nonisolated var isMax: Bool {
        if case .max = self { return true }
        return false
    }
}

extension SyncJSON {
    /// A number in its canonical representation: integral values as `.int`, so a synthesized
    /// number compares equal to the same number read back from JSON text.
    nonisolated static func number(_ d: Double) -> SyncJSON {
        if d.rounded() == d, abs(d) < 9.0e15 { return .int(Int64(d)) }
        return .double(d)
    }
}
