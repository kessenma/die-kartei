//
//  HoerenNumberKind.swift
//  german-ai-flashcards
//
//  What Zahlen-Diktat can ask for, and the value a typed answer becomes. DLI's objective is
//  "transcribe (single pass) numbers", bare and in context (docs/FSI_DLI_ROADMAP.md item 1), so a
//  kind is the sort of number and `HoerenNumberMode` is bare or in a sentence.
//

import Foundation

nonisolated enum HoerenNumberKind: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    /// 0–100.
    case small
    /// Hundreds and thousands.
    case large
    /// Euro and cent.
    case price
    /// The official 24-hour form: 14:30 is "vierzehn Uhr dreißig".
    case time
    /// The everyday form: 2:30 is "halb drei".
    case timeColloquial
    case date
    case year
    case phone

    var id: String { rawValue }

    var germanLabel: String {
        switch self {
        case .small:          "Zahlen bis 100"
        case .large:          "Große Zahlen"
        case .price:          "Preise"
        case .time:           "Uhrzeit"
        case .timeColloquial: "Uhrzeit, Alltag"
        case .date:           "Datum"
        case .year:           "Jahreszahlen"
        case .phone:          "Telefonnummern"
        }
    }

    var englishLabel: String {
        switch self {
        case .small:          "Numbers to 100"
        case .large:          "Hundreds and thousands"
        case .price:          "Prices"
        case .time:           "Clock times, official"
        case .timeColloquial: "Clock times, everyday (halb drei)"
        case .date:           "Dates"
        case .year:           "Years"
        case .phone:          "Phone numbers"
        }
    }

    var systemImage: String {
        switch self {
        case .small:          "number"
        case .large:          "textformat.123"
        case .price:          "eurosign"
        case .time:           "clock"
        case .timeColloquial: "clock.arrow.circlepath"
        case .date:           "calendar"
        case .year:           "calendar.badge.clock"
        case .phone:          "phone"
        }
    }

    /// How to type it, shown under the field.
    var answerHint: String {
        switch self {
        case .small, .large:  "Digits, e.g. 24 or 1 250"
        case .price:          "Euro and cent, e.g. 3,50"
        case .time:           "Hours and minutes, e.g. 14:30"
        case .timeColloquial: "Hours and minutes, e.g. 2:30"
        case .date:           "Day and month, e.g. 3.5."
        case .year:           "The year, e.g. 1987"
        case .phone:          "The digits, e.g. 030 4567 89"
        }
    }

    /// The level at which a kind first appears.
    var introducedAt: CEFRLevel {
        switch self {
        case .small, .price, .time, .phone: .a1
        case .large, .timeColloquial, .date: .a2
        case .year: .b1
        }
    }

    static func kinds(for level: CEFRLevel) -> [HoerenNumberKind] {
        let rank = level.hoerenRank
        return allCases.filter { $0.introducedAt.hoerenRank <= rank }
    }
}

/// Bare number, or the number inside a carrier sentence. DLI lists both as separate objectives.
nonisolated enum HoerenNumberMode: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case bare
    case carrier

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bare:    "Number alone"
        case .carrier: "In a sentence"
        }
    }
}

/// What a typed answer means, after `HoerenNumberAnswer.parse`. The expected answer is held in
/// the same form, so grading is a comparison of values, never of strings.
nonisolated enum HoerenNumberValue: Codable, Hashable, Sendable {
    case integer(Int)
    case cents(Int)
    case time(hour: Int, minute: Int)
    case date(day: Int, month: Int, year: Int?)
    /// Phone numbers: digits as a string, because leading zeros matter.
    case digits(String)

    /// The canonical written form, shown as "the answer was".
    var display: String {
        switch self {
        case .integer(let n):
            return n >= 10_000 ? Self.grouped(n) : String(n)
        case .cents(let c):
            return String(format: "%ld,%02ld €", c / 100, c % 100)
        case .time(let h, let m):
            return String(format: "%ld:%02ld", h, m)
        case .date(let d, let m, let y):
            return y.map { "\(d).\(m).\($0)" } ?? "\(d).\(m)."
        case .digits(let s):
            return s
        }
    }

    /// Digits only, in reading order, for the confusion classes (24 ↔ 42 is a swap of "24").
    var digitString: String {
        switch self {
        case .integer(let n):          String(n)
        case .cents(let c):            String(c)
        case .time(let h, let m):      String(format: "%ld%02ld", h, m)
        case .date(let d, let m, let y): "\(d)\(m)" + (y.map(String.init) ?? "")
        case .digits(let s):           s
        }
    }

    private static func grouped(_ n: Int) -> String {
        let s = String(n)
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, (s.count - i) % 3 == 0 { out.append(" ") }
            out.append(ch)
        }
        return out
    }
}

extension CEFRLevel {
    /// 0 for A1, upwards. Hören keeps its own ordering so it never depends on case order.
    nonisolated var hoerenRank: Int {
        switch self {
        case .a1: 0
        case .a2: 1
        case .b1: 2
        case .b2: 3
        case .c1: 4
        }
    }
}
