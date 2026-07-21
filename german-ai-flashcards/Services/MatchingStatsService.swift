//
//  MatchingStatsService.swift
//  german-ai-flashcards
//
//  Persistence + progress logic for the card-matching game, mirroring `LearnerMemoryService`'s
//  shape (stateless enum over the caller's `ModelContext`).
//
//  - `recordRound` folds a finished round into per-pair stats + round history and returns the
//    history-aware feedback the summary shows ("3rd time you've missed this", personal best).
//  - Repeatedly-missed words optionally flow into the learner profile (`noteMatchingTrouble`),
//    so the conversation coach starts working them in and they become drillable from Coach's Notes.
//  - `trickyPairs` backs the picker's tricky-pair list and `DeckStore`'s biased sampling.
//

import Foundation
import SwiftData

enum MatchingStatsService {

    // Tuning
    /// A pair is "tricky" once it's been missed in this many rounds…
    static let troubleMinMisses = 2
    /// …and stays tricky until matched first-try this many rounds in a row.
    static let graduationStreak = 3
    /// At most this many trouble words flow into the learner profile per round.
    static let coachFeedCap = 5

    /// Stable identity for a pair — same word with a different translation is a different pair.
    static func pairKey(german: String, english: String) -> String {
        let de = Locale(identifier: "de_DE")
        return german.lowercased(with: de).trimmingCharacters(in: .whitespaces)
            + "|" + english.lowercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Write: fold one finished round in

    /// Persist a completed round and return the feedback for the round summary.
    /// `feedCoach` gates the learner-profile hand-off (Settings → Cards → Card Matching).
    static func recordRound(
        _ result: MatchingRoundResult,
        topic: String,
        feedCoach: Bool,
        in context: ModelContext
    ) -> MatchingRoundFeedback {
        guard result.pairCount > 0 else { return .empty }
        let now = Date()

        // Personal best = fastest *perfect* round for this deck at this board size, judged
        // against history before this round is inserted.
        var isPersonalBest = false
        if result.firstTryCount == result.pairCount {
            let pairCount = result.pairCount
            let descriptor = FetchDescriptor<MatchingRound>(
                predicate: #Predicate { $0.topic == topic && $0.pairCount == pairCount }
            )
            let priorPerfectBest = ((try? context.fetch(descriptor)) ?? [])
                .filter(\.isPerfect)
                .map(\.durationSeconds)
                .min()
            isPersonalBest = priorPerfectBest.map { result.durationSeconds < $0 } ?? true
        }

        context.insert(MatchingRound(
            topic: topic,
            pairCount: result.pairCount,
            firstTryCount: result.firstTryCount,
            durationSeconds: result.durationSeconds
        ))

        // Fold each pair's outcome into its lifetime stat row.
        var misses: [MatchingRoundFeedback.RepeatMiss] = []
        var troubleStats: [MatchingPairStat] = []
        for outcome in result.outcomes {
            let stat = fetchOrCreateStat(for: outcome, in: context)
            stat.timesSeen += 1
            stat.lastSeenAt = now

            if outcome.firstTry {
                stat.firstTryStreak += 1
            } else {
                stat.timesMissed += 1
                stat.firstTryStreak = 0
                stat.lastMissedAt = now
                if !outcome.wrongEnglishPicks.isEmpty {
                    var confusions = stat.confusions
                    for pick in outcome.wrongEnglishPicks {
                        confusions[pick, default: 0] += 1
                    }
                    stat.confusions = confusions
                }
                // Only a *repeating* wrong meaning is worth calling out by name.
                let repeated = stat.confusions.first { $0.value >= 2 && $0.key == stat.topConfusion }?.key
                misses.append(.init(
                    displayGerman: stat.displayGerman,
                    english: stat.english,
                    timesMissed: stat.timesMissed,
                    repeatedConfusion: repeated
                ))
                if stat.isTricky { troubleStats.append(stat) }
            }
        }

        if feedCoach, !troubleStats.isEmpty {
            let words = troubleStats
                .sorted { $0.timesMissed > $1.timesMissed }
                .prefix(coachFeedCap)
                .map { (german: $0.displayGerman, english: $0.english) }
            LearnerMemoryService.noteMatchingTrouble(Array(words), in: context)
        }

        try? context.save()

        // Most-missed first, so the summary leads with the biggest offender.
        misses.sort { $0.timesMissed > $1.timesMissed }
        return MatchingRoundFeedback(isPersonalBest: isPersonalBest, misses: misses)
    }

    private static func fetchOrCreateStat(
        for outcome: MatchingPairOutcome,
        in context: ModelContext
    ) -> MatchingPairStat {
        let key = pairKey(german: outcome.german, english: outcome.english)
        let descriptor = FetchDescriptor<MatchingPairStat>(predicate: #Predicate { $0.key == key })
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = MatchingPairStat(
            key: key,
            german: outcome.german,
            article: outcome.article,
            english: outcome.english
        )
        context.insert(created)
        return created
    }

    // MARK: - Read

    /// Pairs currently worth re-drilling, most-missed (then most recently missed) first.
    static func trickyPairs(in context: ModelContext) -> [MatchingPairStat] {
        let all = (try? context.fetch(FetchDescriptor<MatchingPairStat>())) ?? []
        return all
            .filter(\.isTricky)
            .sorted {
                if $0.timesMissed != $1.timesMissed { return $0.timesMissed > $1.timesMissed }
                return ($0.lastMissedAt ?? .distantPast) > ($1.lastMissedAt ?? .distantPast)
            }
    }

    /// The pair keys `DeckStore` uses to bias round sampling toward tricky pairs.
    static func trickyPairKeys(in context: ModelContext) -> Set<String> {
        Set(trickyPairs(in: context).map(\.key))
    }

    // MARK: - Manage

    /// Drop one pair's history (swipe-to-remove on the tricky list).
    static func forgetPair(_ stat: MatchingPairStat, in context: ModelContext) {
        context.delete(stat)
        try? context.save()
    }

    /// Wipe all matching history — pair stats and round records.
    static func reset(in context: ModelContext) {
        for stat in (try? context.fetch(FetchDescriptor<MatchingPairStat>())) ?? [] {
            context.delete(stat)
        }
        for round in (try? context.fetch(FetchDescriptor<MatchingRound>())) ?? [] {
            context.delete(round)
        }
        try? context.save()
    }
}
