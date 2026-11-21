//
//  GermanNumberSpeller.swift
//  german-ai-flashcards
//
//  German numbers as the words a speaker says, for Zahlen-Diktat (docs/HOEREN.md). The speech
//  voice is handed this text rather than digits, so what the learner hears is exactly what the
//  app means: years, prices, clock times and phone numbers each have a spoken form that digits
//  alone do not pin down.
//
//  Written by hand on purpose. `NumberFormatter` with `.spellOut` for de_DE puts soft hyphens
//  (U+00AD) inside the words and says 1987 as "eintausendneunhundert…", where a German says
//  "neunzehnhundert…". Nothing here ever emits U+00AD; a test pins that.
//

import Foundation

nonisolated enum GermanNumberSpeller {

    private static let units = ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben",
                                "acht", "neun"]
    private static let teens = ["zehn", "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn",
                                "sechzehn", "siebzehn", "achtzehn", "neunzehn"]
    private static let tens = ["", "", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig",
                               "siebzig", "achtzig", "neunzig"]

    static let months = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August",
                         "September", "Oktober", "November", "Dezember"]

    // MARK: - Cardinals

    /// 0 … 999 999 as one word. `standalone` decides a final 1: "eins" when the number stands
    /// alone ("Seite eins", "hunderteins"), "ein" before a noun or "Uhr" ("ein Uhr", "ein Euro").
    static func cardinal(_ n: Int, standalone: Bool = true) -> String {
        precondition(n >= 0 && n < 1_000_000, "cardinal out of range: \(n)")
        if n == 0 { return "null" }
        var out = ""
        let thousands = n / 1000, rest = n % 1000
        if thousands > 0 {
            // "tausend", not "eintausend", at the front; "einundzwanzigtausend" inside.
            out += thousands == 1 ? "tausend" : below1000(thousands, finalOne: "ein", leadingHundred: true) + "tausend"
        }
        if rest > 0 {
            out += below1000(rest, finalOne: standalone ? "eins" : "ein", leadingHundred: thousands == 0)
        }
        return out
    }

    /// 1 … 999. `leadingHundred` drops the "ein" of a hundred at the very front ("hundert",
    /// "hundertzwei"); inside a larger number it stays ("tausendeinhundert").
    private static func below1000(_ n: Int, finalOne: String, leadingHundred: Bool) -> String {
        let h = n / 100, r = n % 100
        var out = ""
        if h > 0 {
            out += h == 1 ? (leadingHundred ? "hundert" : "einhundert") : units[h] + "hundert"
        }
        if r > 0 { out += below100(r, finalOne: finalOne) }
        return out
    }

    /// 1 … 99. Units before tens, joined by "und": vierundzwanzig.
    private static func below100(_ n: Int, finalOne: String) -> String {
        if n == 1 { return finalOne }
        if n < 10 { return units[n] }
        if n < 20 { return teens[n - 10] }
        let t = n / 10, u = n % 10
        if u == 0 { return tens[t] }
        return (u == 1 ? "ein" : units[u]) + "und" + tens[t]
    }

    // MARK: - Years

    /// 1100–1999 in hundreds (neunzehnhundertsiebenundachtzig); every other year as a cardinal
    /// (zweitausendvierundzwanzig).
    static func year(_ y: Int) -> String {
        if (1100...1999).contains(y) {
            let r = y % 100
            return cardinal(y / 100) + "hundert" + (r == 0 ? "" : cardinal(r))
        }
        return cardinal(y)
    }

    // MARK: - Prices

    /// A price in cents as said at a till: "drei Euro fünfzig", "ein Euro", "neunundneunzig Cent".
    static func price(cents: Int) -> String {
        let euros = cents / 100, c = cents % 100
        if euros == 0 { return cardinal(c, standalone: false) + " Cent" }
        let e = cardinal(euros, standalone: false) + " Euro"
        return c == 0 ? e : e + " " + cardinal(c)
    }

    // MARK: - Clock times

    /// The official 24-hour form used for timetables and appointments: "vierzehn Uhr dreißig",
    /// "ein Uhr", "null Uhr fünfzehn".
    static func time(hour: Int, minute: Int) -> String {
        let h = cardinal(hour, standalone: false) + " Uhr"
        return minute == 0 ? h : h + " " + cardinal(minute)
    }

    /// The everyday 12-hour form: "Viertel nach drei", "halb drei" (2:30, the trap), "fünf vor
    /// halb drei". Minutes are multiples of five; any other minute falls back to the official form.
    static func colloquialTime(hour: Int, minute: Int) -> String {
        guard minute % 5 == 0 else { return time(hour: hour, minute: minute) }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let next = h12 % 12 + 1
        let this = cardinal(h12), coming = cardinal(next)
        switch minute {
        case 0:  return cardinal(h12, standalone: false) + " Uhr"
        case 15: return "Viertel nach " + this
        case 30: return "halb " + coming
        case 45: return "Viertel vor " + coming
        case 25: return "fünf vor halb " + coming
        case 35: return "fünf nach halb " + coming
        case 5, 10, 20: return cardinal(minute) + " nach " + this
        default: return cardinal(60 - minute) + " vor " + coming   // 40, 50, 55
        }
    }

    // MARK: - Dates

    enum DateForm: Hashable, Sendable {
        /// "der dritte Mai": the date standing alone.
        case nominative
        /// "am dritten Mai": inside a sentence.
        case dative
    }

    /// The ordinal stem before its ending: erst, zweit, dritt, siebt, acht, zwanzigst.
    static func ordinalStem(_ n: Int) -> String {
        switch n {
        case 1: return "erst"
        case 3: return "dritt"
        case 7: return "siebt"
        case 8: return "acht"
        case ..<20: return cardinal(n) + "t"
        default: return cardinal(n) + "st"
        }
    }

    static func date(day: Int, month: Int, year: Int? = nil, form: DateForm) -> String {
        let ordinal = ordinalStem(day) + (form == .nominative ? "e" : "en")
        var out = (form == .nominative ? "der " : "am ") + ordinal + " " + months[month - 1]
        if let year { out += " " + self.year(year) }
        return out
    }

    // MARK: - Phone numbers

    /// Single digits as read on the phone: "zwo" for 2, so it is not heard as "drei".
    static func phoneDigit(_ d: Character) -> String {
        guard let v = d.wholeNumberValue else { return String(d) }
        return v == 2 ? "zwo" : units[v]
    }

    /// A number in groups, separated by ", " so the voice pauses. The first group (the area code)
    /// is always read digit by digit. With `pairs`, the rest is read two digits at a time
    /// ("vierunddreißig", "null fünf"); an odd digit at the end is read alone.
    static func phone(_ groups: [String], pairs: Bool) -> String {
        var spoken: [String] = []
        for (index, group) in groups.enumerated() {
            let digits = Array(group.filter(\.isNumber))
            guard !digits.isEmpty else { continue }
            if index == 0 || !pairs {
                spoken.append(digits.map(phoneDigit).joined(separator: " "))
                continue
            }
            var parts: [String] = []
            var i = 0
            while i < digits.count {
                if i + 1 < digits.count {
                    parts.append(pairWord(digits[i], digits[i + 1]))
                    i += 2
                } else {
                    parts.append(phoneDigit(digits[i]))
                    i += 1
                }
            }
            spoken.append(parts.joined(separator: " "))
        }
        return spoken.joined(separator: ", ")
    }

    private static func pairWord(_ a: Character, _ b: Character) -> String {
        guard let x = a.wholeNumberValue, let y = b.wholeNumberValue else { return String([a, b]) }
        if x == 0 { return "null " + phoneDigit(b) }
        return cardinal(x * 10 + y)
    }
}
