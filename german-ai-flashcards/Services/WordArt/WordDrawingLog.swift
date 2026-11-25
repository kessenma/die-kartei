import Foundation
import SwiftData

/// Writes `WordDrawingStat` rows: every word drawn counts, saved or not. This is the record the
/// learner's drawing history, the coach and future features read.
@MainActor
enum WordDrawingLog {
    struct QuickEntry {
        let germanWord: String
        let english: String
        /// Recall runs: whether the learner knew the word. Nil in copy runs.
        let recalled: Bool?
    }

    static func recordQuick(_ entries: [QuickEntry], at date: Date = Date(), in context: ModelContext) {
        for entry in entries {
            let stat = fetchOrCreate(germanWord: entry.germanWord, english: entry.english, in: context)
            stat.quickCount += 1
            stat.lastQuickAt = max(stat.lastQuickAt ?? .distantPast, date)
            switch entry.recalled {
            case true?:  stat.recallRight += 1
            case false?: stat.recallMissed += 1
            case nil:    break
            }
        }
        try? context.save()
    }

    static func recordStudio(germanWord: String, english: String, at date: Date = Date(), in context: ModelContext) {
        let stat = fetchOrCreate(germanWord: germanWord, english: english, in: context)
        stat.studioCount += 1
        stat.lastStudioAt = max(stat.lastStudioAt ?? .distantPast, date)
        try? context.save()
    }

    static func recordPainted(germanWord: String, english: String, at date: Date = Date(), in context: ModelContext) {
        let stat = fetchOrCreate(germanWord: germanWord, english: english, in: context)
        stat.paintedCount += 1
        stat.lastPaintedAt = max(stat.lastPaintedAt ?? .distantPast, date)
        try? context.save()
    }

    static func stat(forKey key: String, in context: ModelContext) -> WordDrawingStat? {
        var d = FetchDescriptor<WordDrawingStat>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    private static func fetchOrCreate(germanWord: String, english: String, in context: ModelContext) -> WordDrawingStat {
        let key = WordArtKey.make(germanWord)
        if let existing = stat(forKey: key, in: context) { return existing }
        let stat = WordDrawingStat(key: key, germanWord: germanWord, english: english)
        context.insert(stat)
        return stat
    }
}
