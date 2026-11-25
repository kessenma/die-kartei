//
//  SchreibblattStats.swift
//  german-ai-flashcards
//
//  The writing numbers the checkpoint and the finish screen show, one at a time: words in the
//  last hour, today, this week and in all; how many times words were written by hand (words ×
//  passes); the run of days; the word written most; strokes of the pen. Each appearance shows the
//  next one in turn (`next(after:)`), so finishing a sheet keeps turning up something new.
//
//  Pure values over facts read from the store (`SchreibblattStats.load`), so the counting and the
//  turn are tested without one (`SchreibblattStatsTests`).
//
//  Two sources, on purpose: `StudyDay.sheetWordsWritten` syncs, so today / week / total include
//  another device's sheets; the sheets themselves are local (docs/SCHREIBBLATT.md ▸ Invariants),
//  so the last hour, passes by hand, strokes and the top word are this device's.
//

import Foundation

nonisolated struct SchreibblattStats: Equatable, Sendable {

    /// One finished sheet, as the numbers see it.
    struct Sheet: Equatable, Sendable {
        /// Its first Fertig (`SchreibblattSheet.loggedAt`).
        var loggedAt: Date
        /// The words on the page: card id and German.
        var words: [Word]
        var repetitions: Int
        var strokes: Int

        struct Word: Equatable, Sendable {
            var id: UUID
            var german: String
        }
    }

    /// One day of the synced log.
    struct Day: Equatable, Sendable {
        var start: Date
        var words: Int
    }

    struct Stat: Identifiable, Equatable, Sendable {
        enum Kind: String, CaseIterable, Sendable {
            case lastHour, byHand, streak, total, topWord, week, distinct, sheets, strokes, today
        }
        var kind: Kind
        /// The number, or the word for `topWord`.
        var value: String
        /// German, the app's heading voice.
        var title: String
        /// The English under it.
        var caption: String
        var symbol: String
        var id: String { kind.rawValue }
    }

    /// Every number worth showing now, in turn order. A zero (or a streak of one day, a word
    /// written once) is left out: "0 words in the last hour" is not a cheer.
    let stats: [Stat]

    init(sheets: [Sheet], days: [Day], now: Date = Date(), calendar: Calendar = .current) {
        var found: [Stat.Kind: Stat] = [:]
        func add(_ kind: Stat.Kind, _ value: String, _ title: String, _ caption: String, _ symbol: String) {
            found[kind] = Stat(kind: kind, value: value, title: title, caption: caption, symbol: symbol)
        }

        let hourAgo = now.addingTimeInterval(-3600)
        let lastHour = sheets.filter { $0.loggedAt >= hourAgo && $0.loggedAt <= now }
            .reduce(0) { $0 + $1.words.count }
        if lastHour > 0 {
            add(.lastHour, Self.number(lastHour), lastHour == 1 ? "Wort in der letzten Stunde" : "Wörter in der letzten Stunde",
                lastHour == 1 ? "word in the last hour" : "words in the last hour", "clock")
        }

        let byHand = sheets.reduce(0) { $0 + $1.words.count * max(1, $1.repetitions) }
        if byHand > 0 {
            add(.byHand, Self.number(byHand), "Mal von Hand geschrieben", "times a word was written by hand", "hand.draw")
        }

        let today = calendar.startOfDay(for: now)
        let perDay = Dictionary(days.map { (calendar.startOfDay(for: $0.start), $0.words) }, uniquingKeysWith: +)
        let streak = Self.streak(perDay: perDay, today: today, calendar: calendar)
        if streak >= 2 {
            add(.streak, Self.number(streak), "Tage in Folge geschrieben", "days in a row with a sheet", "flame")
        }

        let total = perDay.values.reduce(0, +)
        if total > 0 {
            add(.total, Self.number(total), "Wörter insgesamt", "words written on sheets, all time", "books.vertical")
        }

        var counts: [UUID: (german: String, count: Int)] = [:]
        for sheet in sheets {
            for word in Set(sheet.words.map(\.id)) {
                let german = sheet.words.first { $0.id == word }?.german ?? ""
                counts[word, default: (german, 0)].count += 1
            }
        }
        if let top = counts.values.max(by: { ($0.count, $1.german) < ($1.count, $0.german) }), top.count >= 2 {
            add(.topWord, top.german, "Am häufigsten geschrieben",
                "your most-written word, on \(top.count) sheets", "star")
        }

        if let weekStart = calendar.date(byAdding: .day, value: -6, to: today) {
            let week = perDay.filter { $0.key >= weekStart && $0.key <= today }.values.reduce(0, +)
            if week > 0 {
                add(.week, Self.number(week), "Wörter in den letzten 7 Tagen", "words in the last seven days", "calendar")
            }
        }

        if counts.count > 0 {
            add(.distinct, Self.number(counts.count), counts.count == 1 ? "verschiedenes Wort" : "verschiedene Wörter",
                "different words written at least once", "textformat.abc")
        }

        if sheets.count > 0 {
            add(.sheets, Self.number(sheets.count), sheets.count == 1 ? "Blatt fertig" : "Blätter fertig",
                "sheets finished", "doc.text")
        }

        let strokes = sheets.reduce(0) { $0 + $1.strokes }
        if strokes > 0 {
            add(.strokes, Self.number(strokes), "Striche mit dem Stift", "pen strokes on your sheets", "pencil.and.scribble")
        }

        if let todayWords = perDay[today], todayWords > 0 {
            add(.today, Self.number(todayWords), todayWords == 1 ? "Wort heute" : "Wörter heute",
                "words written today", "sun.max")
        }

        stats = Stat.Kind.allCases.compactMap { found[$0] }
    }

    /// The stat to show after `lastID` (the one shown last time): the next in turn, wrapping
    /// round, or the first when there was none or it has no number now.
    func next(after lastID: String?) -> Stat? {
        guard !stats.isEmpty else { return nil }
        guard let lastID, let kind = Stat.Kind(rawValue: lastID) else { return stats.first }
        let order = Stat.Kind.allCases
        guard let start = order.firstIndex(of: kind) else { return stats.first }
        for step in 1...order.count {
            let candidate = order[(start + step) % order.count]
            if let stat = stats.first(where: { $0.kind == candidate }) { return stat }
        }
        return stats.first
    }

    /// Days in a row with sheet words, counting back from today, or from yesterday when today has
    /// none yet (the run is not broken until the day is over).
    static func streak(perDay: [Date: Int], today: Date, calendar: Calendar) -> Int {
        var day = today
        if (perDay[day] ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            day = yesterday
        }
        var run = 0
        while (perDay[day] ?? 0) > 0 {
            run += 1
            guard let before = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = before
        }
        return run
    }

    static func number(_ n: Int) -> String {
        n.formatted(.number.locale(Locale(identifier: "de_DE")))
    }
}
