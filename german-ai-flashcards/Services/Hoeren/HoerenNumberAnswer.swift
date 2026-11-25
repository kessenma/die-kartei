//
//  HoerenNumberAnswer.swift
//  german-ai-flashcards
//
//  What a typed Zahlen-Diktat answer means. The learner types digits; the only thing graded is
//  whether they heard the number, so every harmless way of writing it is accepted: spaces or dots
//  as thousands separators, a comma or a point before the cents, a leading zero on a clock hour,
//  a trailing "Uhr" or "€". An answer that cannot be read as the kind asked for is `nil`, which
//  the screen shows as a format hint without using up the attempt: a format slip is not a
//  listening slip.
//

import Foundation

nonisolated enum HoerenNumberAnswer {

    /// Words and symbols a learner may type around the digits.
    private static let noiseWords: Set<String> = [
        "uhr", "euro", "eur", "cent", "ct", "am", "der", "den", "im", "jahr", "um", "h",
    ]

    private static let monthPrefixes: [(String, Int)] = [
        ("jan", 1), ("feb", 2), ("mär", 3), ("mar", 3), ("apr", 4), ("mai", 5), ("jun", 6),
        ("jul", 7), ("aug", 8), ("sep", 9), ("okt", 10), ("oct", 10), ("nov", 11), ("dez", 12),
        ("dec", 12),
    ]

    /// The typed text, lowercased, with no-break and thin spaces folded to plain ones and "€"
    /// split off its digits.
    static func cleaned(_ text: String) -> String {
        var s = text.lowercased()
        for space in ["\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}"] {
            s = s.replacingOccurrences(of: space, with: " ")
        }
        s = s.replacingOccurrences(of: "€", with: " € ")
        // "14uhr", "14h30" → keep the digits apart from the word.
        s = s.replacingOccurrences(of: "uhr", with: " uhr ")
        return s.split(separator: " ").map(String.init).joined(separator: " ")
    }

    static func parse(_ text: String, kind: HoerenNumberKind) -> HoerenNumberValue? {
        let s = cleaned(text)
        guard !s.isEmpty else { return nil }
        let mentionsCent = s.split(separator: " ").contains { $0 == "cent" || $0 == "ct" }
        let core = s.split(separator: " ")
            .filter { !noiseWords.contains(String($0)) && $0 != "€" }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return nil }

        switch kind {
        case .small, .large, .year:
            return integer(core).map(HoerenNumberValue.integer)
        case .price:
            return price(core, centsOnly: mentionsCent).map(HoerenNumberValue.cents)
        case .time, .timeColloquial:
            return time(core).map { HoerenNumberValue.time(hour: $0.0, minute: $0.1) }
        case .date:
            return date(core).map { HoerenNumberValue.date(day: $0.0, month: $0.1, year: $0.2) }
        case .phone:
            return phone(core).map(HoerenNumberValue.digits)
        }
    }

    /// Whether a typed value is the expected one. The everyday clock has no a.m./p.m., so 2:30
    /// and 14:30 both answer "halb drei". A date asked without a year ignores a typed one.
    static func matches(_ typed: HoerenNumberValue, expected: HoerenNumberValue, kind: HoerenNumberKind) -> Bool {
        switch (typed, expected) {
        case let (.time(th, tm), .time(eh, em)) where kind == .timeColloquial:
            return tm == em && th % 12 == eh % 12
        case let (.date(td, tmo, ty), .date(ed, emo, ey)):
            guard td == ed, tmo == emo else { return false }
            guard let ey else { return true }
            return ty == ey || ty.map { $0 % 100 == ey % 100 && $0 < 100 } == true
        default:
            return typed == expected
        }
    }

    // MARK: - Kinds

    /// "1250", "1 250", "1.250", "1'250". Thousands separators only in whole groups of three, so
    /// "12.5" is not read as 125.
    static func integer(_ s: String) -> Int? {
        if s.allSatisfy(\.isNumber) { return Int(s) }
        let grouped = s.range(of: #"^\d{1,3}([ .']\d{3})+$"#, options: .regularExpression) != nil
        guard grouped else { return nil }
        return Int(s.filter(\.isNumber))
    }

    /// Cents. "3,50", "3.50", "3,5" (= 3,50), "3", "0,99"; "99" with "Cent" typed is 99 cents.
    static func price(_ s: String, centsOnly: Bool) -> Int? {
        let compact = s.replacingOccurrences(of: " ", with: "")
        if compact.allSatisfy(\.isNumber), let n = Int(compact) {
            return centsOnly ? n : n * 100
        }
        // The last comma or point followed by one or two digits is the decimal mark; anything
        // before it may carry thousands dots.
        guard let match = compact.range(of: #"^(\d{1,3}(?:[.']\d{3})*|\d+)[,.](\d{1,2})$"#,
                                        options: .regularExpression), match == compact.startIndex..<compact.endIndex
        else { return nil }
        guard let sep = compact.lastIndex(where: { $0 == "," || $0 == "." }) else { return nil }
        let euroPart = compact[..<sep].filter(\.isNumber)
        var centPart = String(compact[compact.index(after: sep)...])
        if centPart.count == 1 { centPart += "0" }
        guard let e = Int(euroPart), let c = Int(centPart) else { return nil }
        return e * 100 + c
    }

    /// "14:30", "14.30", "14 30", "8:05", "08:05", "14" (= 14:00).
    static func time(_ s: String) -> (Int, Int)? {
        let parts = s.split(whereSeparator: { $0 == ":" || $0 == "." || $0 == " " }).map(String.init)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let h = Int(parts[0]), parts[0].count <= 2 else { return nil }
        let m: Int
        if parts.count == 2 {
            guard parts[1].count == 2, let mm = Int(parts[1]) else { return nil }
            m = mm
        } else {
            m = 0
        }
        guard (0...24).contains(h), (0..<60).contains(m) else { return nil }
        return (h % 24, m)
    }

    /// "3.5.", "3.5", "03.05.", "3.5.1987", "3. Mai", "3. Mai 1987".
    static func date(_ s: String) -> (Int, Int, Int?)? {
        let tokens = s.split(whereSeparator: { $0 == "." || $0 == " " || $0 == "/" }).map(String.init)
        guard (2...3).contains(tokens.count), let d = Int(tokens[0]), (1...31).contains(d) else { return nil }
        let month: Int?
        if let m = Int(tokens[1]) {
            month = m
        } else {
            month = monthPrefixes.first { tokens[1].hasPrefix($0.0) }?.1
        }
        guard let month, (1...12).contains(month) else { return nil }
        var year: Int? = nil
        if tokens.count == 3 {
            guard let y = Int(tokens[2]) else { return nil }
            year = y
        }
        return (d, month, year)
    }

    /// Digits only, leading zeros kept. Spaces, slashes, hyphens and brackets are dropped; "+49"
    /// is left as typed and compared as digits.
    static func phone(_ s: String) -> String? {
        let digits = s.filter { !" /-()+".contains($0) }
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return digits
    }
}

/// Why a wrong number was wrong, when the reason is a known listening trap. Stats count these,
/// so a learner sees "you swap tens and units" rather than a bare miss count.
nonisolated enum HoerenConfusion: String, Codable, Hashable, Sendable, CaseIterable {
    /// 24 typed as 42: German says the units first.
    case tensUnitsSwap
    /// 13 vs 30, 17 vs 70.
    case teenTy
    /// "halb drei" typed as 3:30: the hour is the coming one.
    case halbHour
    /// zwei and drei sound alike on a bad line; that is why the phone says "zwo".
    case zweiDrei
    case other

    var label: String {
        switch self {
        case .tensUnitsSwap: "Tens and units swapped (24 ↔ 42)"
        case .teenTy:        "-zehn vs -zig (13 ↔ 30)"
        case .halbHour:      "halb: the coming hour (halb drei = 2:30)"
        case .zweiDrei:      "zwei vs drei"
        case .other:         "Other"
        }
    }

    static func classify(typed: HoerenNumberValue, expected: HoerenNumberValue, kind: HoerenNumberKind) -> HoerenConfusion {
        if case let .time(th, tm) = typed, case let .time(eh, em) = expected, tm == em {
            let diff = ((th - eh) % 12 + 12) % 12
            if diff == 1 || diff == 11 { return .halbHour }
        }
        if case let .integer(t) = typed, case let .integer(e) = expected, isTeenTy(t, e) || isTeenTy(e, t) {
            return .teenTy
        }
        let t = Array(typed.digitString), e = Array(expected.digitString)
        if t.count == e.count, t != e {
            let differing = t.indices.filter { t[$0] != e[$0] }
            if differing.count == 2, differing[1] == differing[0] + 1,
               t[differing[0]] == e[differing[1]], t[differing[1]] == e[differing[0]] {
                return .tensUnitsSwap
            }
            if differing.count == 1, Set([t[differing[0]], e[differing[0]]]) == Set(["2", "3"]) {
                return .zweiDrei
            }
        }
        return .other
    }

    /// 13–19 heard as the matching -zig, or the reverse, anywhere in the last two digits.
    private static func isTeenTy(_ teen: Int, _ ty: Int) -> Bool {
        let a = teen % 100, b = ty % 100
        guard teen / 100 == ty / 100, (13...19).contains(a) else { return false }
        return b == (a - 10) * 10
    }
}
