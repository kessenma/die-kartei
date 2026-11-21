//
//  HoerenNumberGenerator.swift
//  german-ai-flashcards
//
//  Zahlen-Diktat items by kind and level, bare or inside a carrier sentence (docs/HOEREN.md).
//  Pure and seedable: a test can pin a round, and the debug screens can show the same items twice.
//

import Foundation

/// One number to hear and type.
nonisolated struct HoerenNumberItem: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var kind: HoerenNumberKind
    var mode: HoerenNumberMode
    /// What the answer must be.
    var value: HoerenNumberValue
    /// The number in words, as the speaker says it ("halb drei").
    var spelled: String
    /// The whole thing the voice reads: the spelled number, or the carrier sentence around it.
    var spoken: String
    /// The same with the number in digits, shown after answering.
    var written: String
}

nonisolated enum HoerenNumberGenerator {

    static func round<R: RandomNumberGenerator>(
        kinds: [HoerenNumberKind], level: CEFRLevel, mode: HoerenNumberMode, count: Int,
        rng: inout R
    ) -> [HoerenNumberItem] {
        let pool = kinds.isEmpty ? HoerenNumberKind.kinds(for: level) : kinds
        var items: [HoerenNumberItem] = []
        var seen = Set<HoerenNumberValue>()
        var guardCount = 0
        while items.count < count, guardCount < count * 20 {
            guardCount += 1
            let kind = pool.randomElement(using: &rng) ?? .small
            let item = make(kind: kind, level: level, mode: mode, id: items.count, rng: &rng)
            guard seen.insert(item.value).inserted else { continue }
            items.append(item)
        }
        return items
    }

    static func make<R: RandomNumberGenerator>(
        kind: HoerenNumberKind, level: CEFRLevel, mode: HoerenNumberMode, id: Int, rng: inout R
    ) -> HoerenNumberItem {
        let rank = level.hoerenRank
        let carrier = mode == .carrier
        switch kind {
        case .small:
            // Most items in 21–99 with a non-zero unit, where the units-first order can trip.
            let n: Int
            if Int.random(in: 0..<10, using: &rng) < 7 {
                n = Int.random(in: 2...9, using: &rng) * 10 + Int.random(in: 1...9, using: &rng)
            } else {
                n = Int.random(in: 0...100, using: &rng)
            }
            return item(id, kind, mode, .integer(n), GermanNumberSpeller.cardinal(n), String(n),
                        carrier ? smallTemplates : nil, avoidOne: n == 1, rng: &rng)

        case .large:
            let upper = rank >= 2 ? 999_999 : 9_999
            var n = Int.random(in: 101...upper, using: &rng)
            // A final 1 reads "hunderteins" alone but "hundertein Kilometer" in a sentence: keep
            // carrier items off it rather than teach a rare form.
            if carrier, n % 100 == 1 { n += 1 }
            return item(id, kind, mode, .integer(n), GermanNumberSpeller.cardinal(n),
                        HoerenNumberValue.integer(n).display, carrier ? largeTemplates : nil, rng: &rng)

        case .price:
            let maxEuro = rank == 0 ? 19 : rank == 1 ? 99 : 999
            let euros = Int.random(in: 0...maxEuro, using: &rng)
            // Cents a till actually shows; never 01–04, which nobody says aloud.
            let centChoices = [0, 0, 5, 10, 20, 25, 30, 40, 45, 49, 50, 50, 60, 70, 75, 80, 85, 90, 95, 99]
            var cents = centChoices.randomElement(using: &rng) ?? 50
            if euros == 0, cents == 0 { cents = 99 }
            let total = euros * 100 + cents
            return item(id, kind, mode, .cents(total), GermanNumberSpeller.price(cents: total),
                        HoerenNumberValue.cents(total).display, carrier ? priceTemplates : nil, rng: &rng)

        case .time:
            let h = Int.random(in: 0...23, using: &rng)
            let m: Int = rank == 0 ? [0, 30].randomElement(using: &rng)! : Int.random(in: 0...59, using: &rng)
            let value = HoerenNumberValue.time(hour: h, minute: m)
            return item(id, kind, mode, value, GermanNumberSpeller.time(hour: h, minute: m), value.display,
                        carrier ? timeTemplates : nil, rng: &rng)

        case .timeColloquial:
            let h = Int.random(in: 1...12, using: &rng)
            // The half hour is the trap worth hearing most often.
            let minutes = [0, 5, 10, 15, 20, 25, 30, 30, 30, 35, 40, 45, 50, 55]
            let m = minutes.randomElement(using: &rng) ?? 30
            let value = HoerenNumberValue.time(hour: h, minute: m)
            return item(id, kind, mode, value, GermanNumberSpeller.colloquialTime(hour: h, minute: m),
                        value.display, carrier ? colloquialTemplates : nil, rng: &rng)

        case .date:
            let month = Int.random(in: 1...12, using: &rng)
            let day = Int.random(in: 1...28, using: &rng)
            let year: Int? = rank >= 2 && Bool.random(using: &rng) ? Int.random(in: 1950...2030, using: &rng) : nil
            let value = HoerenNumberValue.date(day: day, month: month, year: year)
            let form: GermanNumberSpeller.DateForm = carrier ? .dative : .nominative
            let spelled = GermanNumberSpeller.date(day: day, month: month, year: year, form: form)
            let written = (carrier ? "am " : "") + "\(day). \(GermanNumberSpeller.months[month - 1])"
                + (year.map { " \($0)" } ?? "")
            return item(id, kind, mode, value, spelled, written, carrier ? dateTemplates : nil, rng: &rng)

        case .year:
            let y = Bool.random(using: &rng) ? Int.random(in: 1900...1999, using: &rng)
                                             : Int.random(in: 2000...2030, using: &rng)
            return item(id, kind, mode, .integer(y), GermanNumberSpeller.year(y), String(y),
                        carrier ? yearTemplates : nil, rng: &rng)

        case .phone:
            let areaCodes = ["030", "040", "089", "069", "0221", "0711", "0341", "0351", "0176", "0151"]
            let area = areaCodes.randomElement(using: &rng) ?? "030"
            let length = Int.random(in: 6...7, using: &rng)
            let local = String((0..<length).map { i in
                Character(String(i == 0 ? Int.random(in: 1...9, using: &rng) : Int.random(in: 0...9, using: &rng)))
            })
            let spelled = GermanNumberSpeller.phone([area, local], pairs: rank >= 1)
            return item(id, kind, mode, .digits(area + local), spelled, area + " " + local,
                        carrier ? phoneTemplates : nil, rng: &rng)
        }
    }

    // MARK: - Assembly

    /// A template has one "#", where the number goes.
    private static func item<R: RandomNumberGenerator>(
        _ id: Int, _ kind: HoerenNumberKind, _ mode: HoerenNumberMode, _ value: HoerenNumberValue,
        _ spelled: String, _ written: String, _ templates: [String]?, avoidOne: Bool = false, rng: inout R
    ) -> HoerenNumberItem {
        guard let templates, !avoidOne, let template = templates.randomElement(using: &rng) else {
            return HoerenNumberItem(id: id, kind: kind, mode: .bare, value: value,
                                    spelled: spelled, spoken: spelled, written: written)
        }
        return HoerenNumberItem(
            id: id, kind: kind, mode: mode, value: value, spelled: spelled,
            spoken: template.replacingOccurrences(of: "#", with: spelled),
            written: template.replacingOccurrences(of: "#", with: written)
        )
    }

    // Carrier sentences. Each keeps the number where it stands alone or before a fixed word, so
    // the spelled form never needs an inflected "eine".
    static let smallTemplates = [
        "Bitte öffnen Sie das Buch auf Seite #.", "Der Bus Nummer # kommt gleich.",
        "Mein Zimmer hat die Nummer #.", "Wir warten schon # Minuten.",
        "Im Kurs sind # Leute.", "Sie wohnt in der Hausnummer #.",
    ]
    static let largeTemplates = [
        "Das Dorf hat # Einwohner.", "Bis Hamburg sind es noch # Kilometer.",
        "Das Stadion hat Platz für # Leute.", "Das Auto hat schon # Kilometer.",
    ]
    static let priceTemplates = [
        "Das macht zusammen #.", "Der Kaffee kostet #.", "Die Fahrkarte kostet #.",
        "Das Buch kostet heute nur #.",
    ]
    static let timeTemplates = [
        "Der Zug fährt um #.", "Ihr Termin ist um #.", "Das Geschäft öffnet um #.",
        "Der Film beginnt um #.",
    ]
    static let colloquialTemplates = [
        "Wir treffen uns um #.", "Ich komme um # nach Hause.", "Treffen wir uns um #?",
        "Das Essen ist um # fertig.",
    ]
    static let dateTemplates = [
        "Mein Geburtstag ist #.", "Der Kurs beginnt #.", "Wir fliegen # nach Spanien.",
        "Die Prüfung ist #.",
    ]
    static let yearTemplates = [
        "Das Foto ist von #.", "Das Haus wurde # gebaut.", "Wir sind # nach Berlin gezogen.",
    ]
    static let phoneTemplates = [
        "Meine Nummer ist #.", "Rufen Sie bitte unter # an.", "Die Telefonnummer lautet #.",
    ]
}
