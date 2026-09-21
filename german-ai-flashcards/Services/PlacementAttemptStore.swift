//
//  PlacementAttemptStore.swift
//  german-ai-flashcards
//
//  Where finished placement runs are kept: `Application Support/Placement/attempts.json`,
//  newest first.
//
//  Why a file and not the two places the app already stores things:
//
//  * **Not SwiftData.** Same reason as `PlacementResult` — the store deletes and recreates itself
//    on migration failure, so gamification data stays out of the schema (docs/GAMIFICATION.md).
//  * **Not UserDefaults.** `placement.result` is ~400 bytes and belongs there. An attempt is ~6 KB
//    (29 questions with their options), and `UserDefaults.standard`'s plist is parsed on the launch
//    path and held resident for the process. Putting a few hundred KB that exactly one screen ever
//    reads into the launch path is the wrong trade.
//
//  Application Support rather than Caches for the same reason `StoryImageStore` uses it: this is
//  user content — the record of what they answered — and must survive cache eviction.
//
//  A decode failure yields an empty history rather than a crash or a repair attempt. Nothing else
//  in the app depends on this data, which is precisely why it can live outside the schema.
//

import Foundation

enum PlacementAttemptStore {

    /// Roughly 6 KB per attempt, so the cap is ~240 KB on disk. This is a runaway backstop, not a
    /// product limit: a learner retaking monthly for three years lands at 36.
    static let cap = 40

    private static let directoryName = "Placement"
    private static let fileName = "attempts.json"

    private static var fileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent(directoryName)
            .appendingPathComponent(fileName)
    }

    /// Decoded history, cached after the first read — mirroring `PlacementGrammarBank.cache`, since
    /// this is likewise read-mostly and rewritten only by an explicit action.
    private static var cache: [PlacementAttempt]?

    // MARK: - Reading

    /// Every recorded attempt, newest first.
    static func attempts() -> [PlacementAttempt] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([PlacementAttempt].self, from: data)
        else {
            cache = []
            return []
        }
        let sorted = decoded.sorted { $0.takenAt > $1.takenAt }
        cache = sorted
        return sorted
    }

    static func attempt(id: UUID) -> PlacementAttempt? {
        attempts().first { $0.id == id }
    }

    static var isEmpty: Bool { attempts().isEmpty }

    // MARK: - Writing

    static func append(_ attempt: PlacementAttempt) {
        // Re-sort rather than just inserting at the front: a real run is always "now", but the
        // debug seeder backdates, and the cache is handed straight back by `attempts()` without a
        // second sort — so an out-of-order insert would survive for the rest of the launch and
        // quietly break the newest-first contract every caller relies on.
        let all = (attempts() + [attempt]).sorted { $0.takenAt > $1.takenAt }
        write(Array(all.prefix(cap)))
    }

    static func delete(id: UUID) {
        write(attempts().filter { $0.id != id })
    }

    static func deleteAll() {
        write([])
    }

    /// Records a finished run.
    ///
    /// `answers` empty (and `cloze` nil) is the "I'm starting from zero" door. That still gets a
    /// row: it's a real, dated decision, and skipping it is the one case that would make the
    /// timeline lie — "placed at B1 in March, placed at A2 in June" with the declaration between
    /// them silently missing.
    static func record(
        result: PlacementResult,
        answers: [PlacementAnswer],
        cloze: PlacementClozePrompt?
    ) {
        var records: [PlacementRecord] = []
        records.reserveCapacity(answers.count)
        for answer in answers {
            var context: String?
            if case .cloze(_, _, let gap) = answer.item.kind, let cloze {
                context = clozeContext(cloze, gap: gap)
            }
            records.append(PlacementRecord(answer, context: context))
        }
        append(PlacementAttempt(
            result: result,
            records: records,
            bankVersion: PlacementGrammarBank.version
        ))
    }

    /// The finale paragraph as one gap saw it: *this* gap blanked, the others filled with their
    /// answers. The recorded item's own prompt is only the paragraph title, so without this a
    /// cloze row reads as a title plus three orphaned options.
    static func clozeContext(_ cloze: PlacementClozePrompt, gap: Int) -> String {
        var out = ""
        for (index, segment) in cloze.segments.enumerated() {
            out += segment
            guard index < cloze.gaps.count else { continue }
            let filled = cloze.gaps[index]
            out += index == gap
                ? ClozeCard.blank
                : (filled.choices.indices.contains(filled.correctIndex) ? filled.choices[filled.correctIndex] : "")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Disk

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func write(_ attempts: [PlacementAttempt]) {
        cache = attempts
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(attempts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
