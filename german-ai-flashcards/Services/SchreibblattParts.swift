//
//  SchreibblattParts.swift
//  german-ai-flashcards
//
//  A big selection written in parts: fifty words become five sheets of ten, made together and
//  written one after another (`SchreibblattSheet.seriesID`). Each part finished is a checkpoint
//  that offers its words as flashcards, or the last two parts, or everything written so far.
//
//  Pure values, so the splitting and the offers are tested without a store
//  (`SchreibblattPartsTests`). See docs/SCHREIBBLATT.md ▸ Parts.
//

import Foundation

nonisolated enum SchreibblattParts {

    /// The smallest part the setup screen offers. Below this a "part" is a word or two, and the
    /// drill is a page of tables.
    static let minPartSize = 3

    // MARK: - Splitting

    /// How many words each part gets: as many parts as `partSize` needs, with the words shared
    /// out evenly (sizes differ by at most one, bigger first). 52 words at 10 make six parts of
    /// 9, 9, 9, 9, 8, 8 rather than five of 10 and a stub of 2.
    static func sizes(count: Int, partSize: Int) -> [Int] {
        guard count > 0 else { return [] }
        let size = max(1, partSize)
        let parts = (count + size - 1) / size
        let base = count / parts
        let extra = count % parts
        return (0..<parts).map { $0 < extra ? base + 1 : base }
    }

    /// `items` cut into the parts `sizes` describes, in order.
    static func split<T>(_ items: [T], partSize: Int) -> [[T]] {
        var start = 0
        return sizes(count: items.count, partSize: partSize).map { size in
            defer { start += size }
            return Array(items[start..<(start + size)])
        }
    }

    /// "10" when every part is the same size, "8–9" when they differ.
    static func sizeLabel(_ sizes: [Int]) -> String {
        guard let low = sizes.min(), let high = sizes.max() else { return "0" }
        return low == high ? "\(low)" : "\(low)–\(high)"
    }

    // MARK: - Checkpoints

    /// One part as the offers see it: its place, the words on it that still have a flashcard,
    /// and whether it is done.
    struct Part: Equatable, Sendable {
        var index: Int
        var wordIDs: [UUID]
        var isFinished: Bool
    }

    /// One way to practise: a name, what it covers, and the cards.
    struct PracticeOption: Identifiable, Equatable, Sendable {
        enum Kind: String, Sendable { case thisPart, lastTwo, soFar, whole }
        var kind: Kind
        var title: String
        var detail: String
        var wordIDs: [UUID]
        var id: String { kind.rawValue }
    }

    /// The practice offers at part `current` (0-based): that part's words, the last two parts
    /// written, and everything written so far (the whole set once every part is done). Only
    /// finished parts count as written, apart from `current` itself, so a part skipped never
    /// sneaks in. Offers covering the same words collapse into the first; offers with no cards
    /// (every word deleted since) are left out.
    static func practiceOptions(parts: [Part], current: Int) -> [PracticeOption] {
        let sorted = parts.sorted { $0.index < $1.index }
        guard let here = sorted.first(where: { $0.index == current }) else { return [] }
        let written = sorted.filter { $0.isFinished || $0.index == current }
        let upToHere = written.filter { $0.index <= current }

        var options: [PracticeOption] = []
        options.append(PracticeOption(
            kind: .thisPart,
            title: sorted.count > 1 ? "Teil \(here.index + 1)" : "Diese Wörter",
            detail: sorted.count > 1 ? "\(words(here.wordIDs.count)), just this part" : words(here.wordIDs.count),
            wordIDs: here.wordIDs))

        let lastTwo = Array(upToHere.suffix(2))
        if lastTwo.count == 2 {
            options.append(PracticeOption(
                kind: .lastTwo, title: "Die letzten zwei Teile",
                detail: "\(words(lastTwo.flatMap(\.wordIDs).count)) · parts \(partList(lastTwo))",
                wordIDs: lastTwo.flatMap(\.wordIDs)))
        }

        let isWhole = written.count == sorted.count && sorted.count > 1
        options.append(PracticeOption(
            kind: isWhole ? .whole : .soFar,
            title: isWhole ? "Alle Teile" : "Alles bisher",
            detail: isWhole
                ? "all \(words(written.flatMap(\.wordIDs).count))"
                : "\(words(written.flatMap(\.wordIDs).count)) · parts \(partList(written))",
            wordIDs: written.flatMap(\.wordIDs)))

        var seen: [Set<UUID>] = []
        return options.filter { option in
            let set = Set(option.wordIDs)
            guard !set.isEmpty, !seen.contains(set) else { return false }
            seen.append(set)
            return true
        }
    }

    /// The part to write next after `current`: the first unfinished one after it, else the first
    /// unfinished one before it, else nil (every part is done).
    static func nextPart(parts: [Part], after current: Int) -> Int? {
        let open = parts.filter { !$0.isFinished && $0.index != current }.map(\.index).sorted()
        return open.first { $0 > current } ?? open.first
    }

    // MARK: - Labels

    static func words(_ count: Int) -> String { count == 1 ? "1 word" : "\(count) words" }

    /// "2–3" for neighbours in a run, "1, 3, 4" otherwise, numbered from 1.
    static func partList(_ parts: [Part]) -> String {
        let numbers = parts.map { $0.index + 1 }.sorted()
        guard let first = numbers.first, let last = numbers.last else { return "" }
        if numbers.count > 1, last - first == numbers.count - 1 { return "\(first)–\(last)" }
        return numbers.map(String.init).joined(separator: ", ")
    }
}
