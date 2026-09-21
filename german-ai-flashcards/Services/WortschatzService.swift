//
//  WortschatzService.swift
//  german-ai-flashcards
//
//  The pure half of the Wortschatz screen: what the learner has chosen to study (`WortschatzScope`)
//  and what one Goethe card's SRS state means in words (`WortschatzService`). Nothing here touches
//  SwiftData; the hub, the browse list, the word sheet, and Today all read status through this one
//  place so "fällig", "bekannt" and the Karteikasten buckets can never disagree.
//

import SwiftUI

// MARK: - Scope

/// Which levels and word classes feed reviews and new words. Progress outside the scope is kept,
/// not lost — a deselected level's cards simply wait until it is switched back on.
struct WortschatzScope: Equatable {
    var levels: Set<GoetheLevel>
    var wordTypes: Set<GoetheWordType>

    static let all = WortschatzScope(levels: Set(GoetheLevel.allCases), wordTypes: Set(GoetheWordType.allCases))

    static let levelsKey = "wortschatz.levels"
    static let wordTypesKey = "wortschatz.wordTypes"

    func contains(_ word: GoetheWord) -> Bool {
        !levels.isDisjoint(with: word.levels) && wordTypes.contains(word.wordType)
    }

    var orderedLevels: [GoetheLevel] { GoetheLevel.allCases.filter { levels.contains($0) } }
    var orderedTypes: [GoetheWordType] { GoetheWordType.allCases.filter { wordTypes.contains($0) } }

    /// The session topic: a single level keeps the per-level label the deck history and the
    /// Goethe badge have always used; a mix gets the merged deck's own name.
    var topic: String {
        orderedLevels.count == 1 ? "\(orderedLevels[0].rawValue) Vocabulary" : DeckStore.wortschatzTopic
    }

    /// "A1 · A2 · Nomen, Verben" — the one-line recap the hero and the options row show.
    var summary: String {
        let levelPart = levels.count == GoetheLevel.allCases.count
            ? "A1–B1" : orderedLevels.map(\.rawValue).joined(separator: " · ")
        let typePart = wordTypes.count == GoetheWordType.allCases.count
            ? "all word types" : orderedTypes.map(\.label).joined(separator: ", ")
        return "\(levelPart) · \(typePart)"
    }

    // MARK: Persistence (comma-joined raw values, the `home.selectedTenses` pattern)

    var levelsRaw: String { orderedLevels.map(\.rawValue).joined(separator: ",") }
    var wordTypesRaw: String { orderedTypes.map(\.rawValue).joined(separator: ",") }

    /// Decode the two stored strings; anything empty or unreadable falls back to everything, so a
    /// fresh install and a corrupted key both study the whole box.
    static func decode(levelsRaw: String, wordTypesRaw: String) -> WortschatzScope {
        let levels = Set(levelsRaw.split(separator: ",").compactMap { GoetheLevel(rawValue: String($0)) })
        let types = Set(wordTypesRaw.split(separator: ",").compactMap { GoetheWordType(rawValue: String($0)) })
        return WortschatzScope(
            levels: levels.isEmpty ? all.levels : levels,
            wordTypes: types.isEmpty ? all.wordTypes : types
        )
    }

    static func load(_ defaults: UserDefaults = .standard) -> WortschatzScope {
        decode(levelsRaw: defaults.string(forKey: levelsKey) ?? "",
               wordTypesRaw: defaults.string(forKey: wordTypesKey) ?? "")
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(levelsRaw, forKey: Self.levelsKey)
        defaults.set(wordTypesRaw, forKey: Self.wordTypesKey)
    }

    /// Flip one level; the last remaining level stays on (an empty scope studies nothing).
    mutating func toggle(_ level: GoetheLevel) {
        if levels.contains(level) {
            guard levels.count > 1 else { return }
            levels.remove(level)
        } else {
            levels.insert(level)
        }
    }

    mutating func toggle(_ type: GoetheWordType) {
        if wordTypes.contains(type) {
            guard wordTypes.count > 1 else { return }
            wordTypes.remove(type)
        } else {
            wordTypes.insert(type)
        }
    }
}

// MARK: - Status

/// One card's place in the box, in the order the badge decides it: never seen, due now, known,
/// or scheduled for later.
enum WortschatzStatus: Equatable {
    case new
    case due
    case known
    case scheduled(daysUntil: Int)
}

enum WortschatzService {

    /// "Bekannt" is the pyramid's own learned rule, so the hub and the Lernpyramide agree.
    static let knownIntervalDays = PyramidService.matureIntervalDays
    static let knownRepetitions = PyramidService.provenRepetitions

    static func isNew(_ card: SavedCard) -> Bool { card.totalReviews == 0 }

    static func isKnown(_ card: SavedCard) -> Bool {
        card.interval >= knownIntervalDays || card.repetitions >= knownRepetitions
    }

    /// Due under the scheduler the learner studies with. Never-reviewed cards are new, not due.
    /// A card reviewed only under the other scheduler has no schedule here and counts as due, so
    /// switching styles never strands a word.
    static func isDue(_ card: SavedCard, style: FlashcardStyle, leitnerSession: Int, now: Date = .now) -> Bool {
        guard !isNew(card) else { return false }
        switch style {
        case .leitner:
            return LeitnerService.isDue(box: card.leitnerBox, sessionNumber: leitnerSession)
        default:
            guard let next = card.nextReviewDate else { return true }
            return next <= now
        }
    }

    static func status(_ card: SavedCard, style: FlashcardStyle, leitnerSession: Int, now: Date = .now) -> WortschatzStatus {
        if isNew(card) { return .new }
        if isDue(card, style: style, leitnerSession: leitnerSession, now: now) { return .due }
        if isKnown(card) { return .known }
        if style != .leitner, let next = card.nextReviewDate {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now),
                                                       to: Calendar.current.startOfDay(for: next)).day ?? 0
            return .scheduled(daysUntil: max(0, days))
        }
        return .scheduled(daysUntil: 0)
    }

    /// Worth a second look: a word with a lapse that hasn't been proven since, or one the games
    /// keep catching.
    static func isDifficult(_ card: SavedCard, articleTricky: Bool, matchingTricky: Bool) -> Bool {
        !isKnown(card) && (card.lapses > 0 || articleTricky || matchingTricky)
    }

    /// The trailing badge on a browse row.
    static func badgeText(_ card: SavedCard, style: FlashcardStyle, leitnerSession: Int, now: Date = .now) -> String {
        switch status(card, style: style, leitnerSession: leitnerSession, now: now) {
        case .new: return "new"
        case .due: return "due"
        case .known: return "known"
        case .scheduled(let days):
            if style == .leitner { return "Box \(max(1, card.leitnerBox))" }
            if days <= 0 { return "today" }
            if days == 1 { return "tomorrow" }
            return "in \(days) days"
        }
    }

    static func badgeColor(_ card: SavedCard, style: FlashcardStyle, leitnerSession: Int, now: Date = .now) -> Color {
        switch status(card, style: style, leitnerSession: leitnerSession, now: now) {
        case .new: return .gray
        case .due: return .orange
        case .known: return .green
        case .scheduled: return bucketColor(bucketIndex(card, style: style))
        }
    }

    // MARK: Der Karteikasten

    struct Bucket: Identifiable {
        let id: Int
        let label: String
        let count: Int
        let color: Color
    }

    static let bucketCount = 7

    /// Seven compartments, zeros included, so the chart always shows the whole box. Under Anki the
    /// middle five are the next-review spacing; under Leitner they are the boxes themselves.
    static func karteikasten(_ cards: [SavedCard], style: FlashcardStyle) -> [Bucket] {
        var counts = Array(repeating: 0, count: bucketCount)
        for card in cards {
            counts[bucketIndex(card, style: style)] += 1
        }
        let labels = style == .leitner
            ? ["New", "Box 1", "Box 2", "Box 3", "Box 4", "Box 5", "Known"]
            : ["New", "1 day", "3 days", "7 days", "14 days", "20 days", "Known"]
        return (0..<bucketCount).map { i in
            Bucket(id: i, label: labels[i], count: counts[i], color: bucketColor(i))
        }
    }

    static func bucketIndex(_ card: SavedCard, style: FlashcardStyle) -> Int {
        if isNew(card) { return 0 }
        if isKnown(card) { return 6 }
        if style == .leitner { return min(max(card.leitnerBox, 1), 5) }
        switch card.interval {
        case ..<2: return 1
        case ..<4: return 2
        case ..<8: return 3
        case ..<15: return 4
        default: return 5
        }
    }

    static func bucketColor(_ index: Int) -> Color {
        switch index {
        case 0: .gray
        case 1: .red
        case 2: .orange
        case 3: .yellow
        case 4: .mint
        case 5: .blue
        default: .green
        }
    }

    // MARK: Today

    static func reviewedToday(_ card: SavedCard, now: Date = .now) -> Bool {
        guard let at = card.lastReviewedAt else { return false }
        return at >= Calendar.current.startOfDay(for: now)
    }

    static func metToday(_ card: SavedCard, now: Date = .now) -> Bool {
        guard let at = card.firstReviewedAt else { return false }
        return at >= Calendar.current.startOfDay(for: now)
    }

    struct TodaySummary: Equatable {
        var reviewed: Int
        var right: Int
        var met: Int
        var missed: Int { reviewed - right }
    }

    /// What happened in the box today, counted per distinct word (a re-queued card counts once,
    /// with the result of its last pass).
    static func today(_ cards: [SavedCard], now: Date = .now) -> TodaySummary {
        var reviewed = 0, right = 0, met = 0
        for card in cards where reviewedToday(card, now: now) {
            reviewed += 1
            if card.lastReviewWasCorrect == true { right += 1 }
            if metToday(card, now: now) { met += 1 }
        }
        return TodaySummary(reviewed: reviewed, right: right, met: met)
    }

    /// Today's words, missed ones first, then most recent.
    static func todaysCards(_ cards: [SavedCard], now: Date = .now) -> [SavedCard] {
        cards.filter { reviewedToday($0, now: now) }.sorted {
            let a = $0.lastReviewWasCorrect ?? true, b = $1.lastReviewWasCorrect ?? true
            if a != b { return !a }
            return ($0.lastReviewedAt ?? .distantPast) > ($1.lastReviewedAt ?? .distantPast)
        }
    }

    // MARK: Counts

    static func inScope(_ card: SavedCard, _ scope: WortschatzScope) -> Bool {
        GoetheVocabService.index[card.germanWord].map { scope.contains($0) } ?? false
    }

    struct Summary: Equatable {
        /// Reviews waiting now.
        var due: Int
        /// New words today's budget still allows.
        var new: Int
        /// Words in scope never seen at all, budget or not.
        var unseen: Int
        var known: Int
        var total: Int

        var todo: Int { due + new }
    }

    static func summary(
        cards: [SavedCard], scope: WortschatzScope, style: FlashcardStyle,
        leitnerSession: Int, budgetRemaining: Int, now: Date = .now
    ) -> Summary {
        var due = 0, unseen = 0, known = 0, total = 0
        for card in cards where inScope(card, scope) {
            total += 1
            if isNew(card) { unseen += 1; continue }
            if isDue(card, style: style, leitnerSession: leitnerSession, now: now) { due += 1 }
            if isKnown(card) { known += 1 }
        }
        return Summary(due: due, new: min(unseen, max(0, budgetRemaining)), unseen: unseen, known: known, total: total)
    }
}
