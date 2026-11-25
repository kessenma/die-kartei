//
//  AnswerTimeLog.swift
//  german-ai-flashcards
//
//  How long answers take (roadmap item 5, FSI lesson 7: automaticity). Measure first: this log
//  feeds a spread view in Settings ▸ Developer, and nothing is judged "fast" until those numbers
//  have been looked at. No threshold lives here.
//
//  Per device, not synced, last 3 000 answers in Application Support/Progress/answer_times.json.
//  Grammar drill answers also keep their time on the synced `KasusRoundItem.answerMs`; this log
//  is the one place card flips are timed.
//

import Foundation

nonisolated struct AnswerTime: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// Card shown → flipped: the time to recall.
        case cardFlip
        /// A grammar drill step: shown → first graded pick.
        case drill
    }

    var date: Date
    var kind: Kind
    var ms: Int
    /// For drills: right on the first pick. For card flips: nil (the grade comes later).
    var correct: Bool?
    /// The drill kind or the card style, for the breakdown.
    var detail: String
}

@MainActor
enum AnswerTimeLog {
    static let cap = 3000
    /// Longer than this is a learner who looked away, not an answer.
    static let ceilingMs = 120_000

    private static var cache: [AnswerTime]?

    private static var url: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Progress", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("answer_times.json")
    }

    static var all: [AnswerTime] {
        if let cache { return cache }
        let loaded = url.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([AnswerTime].self, from: $0) } ?? []
        cache = loaded
        return loaded
    }

    static func record(_ kind: AnswerTime.Kind, ms: Int, correct: Bool? = nil, detail: String) {
        guard ms > 0, ms <= ceilingMs else { return }
        var list = all
        list.append(AnswerTime(date: .now, kind: kind, ms: ms, correct: correct, detail: detail))
        if list.count > cap { list.removeFirst(list.count - cap) }
        cache = list
        if let url, let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
    }

    /// Percentiles of a set of times, for the spread view.
    nonisolated static func percentiles(_ ms: [Int], _ ps: [Double] = [0.1, 0.25, 0.5, 0.75, 0.9]) -> [Int] {
        let sorted = ms.sorted()
        guard !sorted.isEmpty else { return ps.map { _ in 0 } }
        return ps.map { p in sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))] }
    }

    #if DEBUG
    static func clear() {
        cache = []
        if let url { try? FileManager.default.removeItem(at: url) }
    }
    #endif
}
