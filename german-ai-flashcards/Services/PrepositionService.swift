//
//  PrepositionService.swift
//  german-ai-flashcards
//
//  Content loading + persistence for the preposition exercises, mirroring `ArticleGameService`'s
//  shape (stateless enum over the caller's `ModelContext`).
//
//  The bundled `prepositions.json` is the single source of truth every preposition exercise reads:
//  the Kasus drill, the flip-card reference deck, the rules sheet, and the matching round. On the
//  way back, `recordRound` folds a finished Kasus round into per-preposition stats + round history,
//  counts it as grammar practice for the streak, moves the profile's Präpositionen skill via
//  `applyDrillResult`, and (optionally) feeds repeat offenders to the coach.
//

import Foundation
import SwiftData
import SwiftUI

enum PrepositionService {

    // Tuning — same thresholds as the article game, so "tricky" means the same thing app-wide.
    /// A preposition is "tricky" once it's been missed in this many rounds…
    static let troubleMinMisses = 2
    /// …and stays tricky until answered first-try this many rounds in a row.
    static let graduationStreak = 3
    /// At most this many trouble prepositions flow into the learner profile per round.
    static let coachFeedCap = 5
    /// A round needs at least this many questions to be worth playing.
    static let minQuestions = 4

    static func key(for word: String) -> String {
        word.lowercased(with: Locale(identifier: "de_DE")).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Bundled content

    private static var cache: [Preposition]?

    /// Every preposition in the bundle, in authored order (Akkusativ → Dativ → Wechsel → Genitiv).
    static func all() -> [Preposition] {
        if let cache { return cache }
        guard let url = Bundle.main.url(forResource: "prepositions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PrepositionsFile.self, from: data)
        else { return [] }
        cache = file.prepositions
        return file.prepositions
    }

    static func prepositions(governing group: PrepositionCase) -> [Preposition] {
        all().filter { $0.governs == group }
    }

    /// The set a round or a card deck draws from. `advanced` adds the formal Genitiv prepositions
    /// (innerhalb, jenseits, …) and the entries with awkward real-world usage.
    static func prepositions(
        groups: Set<PrepositionCase> = Set(PrepositionCase.allCases),
        includeAdvanced: Bool
    ) -> [Preposition] {
        all().filter { groups.contains($0.governs) && (includeAdvanced || $0.tier == .core) }
    }

    static func preposition(_ word: String) -> Preposition? {
        let wanted = key(for: word)
        return all().first { key(for: $0.word) == wanted }
    }

    /// Every contraction in the bundle, grouped for the rules sheet ("in + das = ins").
    static func allContractions() -> [(preposition: Preposition, contraction: PrepositionContraction)] {
        all().flatMap { prep in prep.contractions.map { (prep, $0) } }
    }

    // MARK: - Round assembly (Kasus drill)

    /// Sample a Kasus round from a pool. With `trickyFirst` on, up to half the round is drawn from
    /// prepositions the learner keeps missing — the rest stays random so a round never turns into
    /// a pure punishment drill. Returns nil below `minQuestions`.
    /// `answerCases` is what the board will offer as buttons — pass the groups the *source*
    /// covers, so a two-group round doesn't show four cases (and a sampled round that happens to
    /// miss a group doesn't leak that by hiding its button).
    static func session(
        topic: String,
        pool rawPool: [Preposition],
        count: Int,
        trickyFirst: Bool,
        answerCases: Set<PrepositionCase> = Set(PrepositionCase.allCases),
        in context: ModelContext
    ) -> PrepositionCaseSession? {
        var seen = Set<String>()
        let pool = rawPool.filter { seen.insert(key(for: $0.word)).inserted }
        guard pool.count >= minQuestions else { return nil }
        let buttons = PrepositionCase.allCases.filter { answerCases.contains($0) }

        guard trickyFirst else {
            let picked = Array(pool.shuffled().prefix(count)).map(PrepositionQuestion.init)
            return PrepositionCaseSession(questions: picked, topic: topic, answerCases: buttons)
        }

        let trickyKeys = Set(trickyStats(in: context).map(\.key))
        var tricky: [Preposition] = []
        var rest: [Preposition] = []
        for prep in pool {
            if trickyKeys.contains(key(for: prep.word)) { tricky.append(prep) } else { rest.append(prep) }
        }
        let trickyTake = Array(tricky.shuffled().prefix(count / 2))
        let restTake = Array(rest.shuffled().prefix(count - trickyTake.count))
        let questions = (trickyTake + restTake).shuffled().map(PrepositionQuestion.init)
        return PrepositionCaseSession(questions: questions, topic: topic, answerCases: buttons)
    }

    /// Prepositions currently worth re-drilling, most-missed (then most recently missed) first.
    static func trickyStats(in context: ModelContext) -> [PrepositionStat] {
        let all = (try? context.fetch(FetchDescriptor<PrepositionStat>())) ?? []
        return all
            .filter(\.isTricky)
            .sorted {
                if $0.timesMissed != $1.timesMissed { return $0.timesMissed > $1.timesMissed }
                return ($0.lastMissedAt ?? .distantPast) > ($1.lastMissedAt ?? .distantPast)
            }
    }

    /// A pure tricky-preposition round, resolved back to bundled content.
    static func trickyPrepositions(in context: ModelContext) -> [Preposition] {
        trickyStats(in: context).compactMap { preposition($0.word) }
    }

    // MARK: - Matching round (preposition ↔ meaning)

    /// Preposition pairs as `VocabCard`s, so the existing matching game can run a meaning-recall
    /// round with no game code of its own. `article` stays nil: these aren't nouns, so the board
    /// never implies a gender.
    static func vocabCards(
        groups: Set<PrepositionCase> = Set(PrepositionCase.allCases),
        includeAdvanced: Bool,
        limit: Int
    ) -> [VocabCard] {
        prepositions(groups: groups, includeAdvanced: includeAdvanced)
            .shuffled()
            .prefix(limit)
            .map { prep in
                VocabCard(
                    germanWord: prep.word,
                    englishTranslation: prep.meaningLine,
                    wordType: "preposition",
                    article: nil,
                    exampleSentence: prep.examples.first?.german
                )
            }
    }

    /// A ready-to-launch meaning-matching round, with the German column tinted by case so the
    /// color link built in the Kasus drill keeps paying off here. Returns nil below four pairs.
    @MainActor
    static func matchingSession(
        topic: String,
        groups: Set<PrepositionCase> = Set(PrepositionCase.allCases),
        includeAdvanced: Bool,
        limit: Int,
        colorCoded: Bool
    ) -> MatchingSession? {
        let cards = vocabCards(groups: groups, includeAdvanced: includeAdvanced, limit: limit)
        guard cards.count >= 4 else { return nil }

        var tints: [String: Color] = [:]
        var legend: [MatchingTintLegendItem] = []
        if colorCoded {
            let byWord = Dictionary(
                prepositions(groups: groups, includeAdvanced: includeAdvanced)
                    .map { (key(for: $0.word), $0.governs) },
                uniquingKeysWith: { first, _ in first }
            )
            for card in cards {
                if let group = byWord[key(for: card.germanWord)] {
                    tints[card.germanWord.lowercased()] = group.color
                }
            }
            // Only legend the groups actually on this board.
            let present = Set(cards.compactMap { byWord[key(for: $0.germanWord)] })
            legend = PrepositionCase.allCases
                .filter { present.contains($0) }
                .map { MatchingTintLegendItem(label: $0.germanLabel, color: $0.color) }
        }

        return MatchingSession(
            cards: cards,
            topic: topic,
            deckID: nil,
            subDeckLabel: "Matching · \(cards.count) pairs",
            germanTileTints: tints,
            tintLegend: legend
        )
    }

    // MARK: - Write: fold one finished round in

    /// Persist a completed Kasus round and return the feedback for the summary. Also counts the
    /// round toward the streak (as grammar practice), nudges the profile's Präpositionen skill,
    /// and — with `feedCoach` on — hands repeatedly-missed prepositions to the coach.
    @MainActor
    static func recordRound(
        _ result: PrepositionRoundResult,
        topic: String,
        feedCoach: Bool,
        in context: ModelContext
    ) -> PrepositionRoundFeedback {
        guard result.questionCount > 0 else { return .empty }
        let now = Date()

        // Personal best = fastest *perfect* round for this source at this size, judged against
        // history before this round is inserted.
        var isPersonalBest = false
        if result.firstTryCount == result.questionCount {
            let count = result.questionCount
            let descriptor = FetchDescriptor<PrepositionRound>(
                predicate: #Predicate { $0.topic == topic && $0.questionCount == count }
            )
            let priorBest = ((try? context.fetch(descriptor)) ?? [])
                .filter(\.isPerfect)
                .map(\.durationSeconds)
                .min()
            isPersonalBest = priorBest.map { result.durationSeconds < $0 } ?? true
        }

        context.insert(PrepositionRound(
            topic: topic,
            questionCount: result.questionCount,
            firstTryCount: result.firstTryCount,
            durationSeconds: result.durationSeconds
        ))

        // Fold each outcome into its lifetime stat row.
        var misses: [PrepositionRoundFeedback.RepeatMiss] = []
        var troubleStats: [PrepositionStat] = []
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
                if let wrong = outcome.wrongPick {
                    var picks = stat.wrongPicks
                    picks[wrong.rawValue, default: 0] += 1
                    stat.wrongPicks = picks
                }
                // Only a *repeating* wrong case is worth calling out by name.
                let repeated = stat.topWrongPick.flatMap { top in
                    (stat.wrongPicks[top.rawValue] ?? 0) >= 2 ? top : nil
                }
                misses.append(.init(
                    word: stat.word,
                    governs: outcome.governs,
                    meaning: stat.meaning,
                    timesMissed: stat.timesMissed,
                    repeatedWrongCase: repeated
                ))
                if stat.isTricky { troubleStats.append(stat) }
            }
        }

        // Streak: the whole round is practice regardless of how much help was on screen. The
        // streak measures showing up, not mastery.
        StudyLogService.record(
            .grammar(result.questionCount), seconds: result.durationSeconds, in: context
        )

        // Skill: only the answers given *without* the answer on screen. In teaching mode the
        // scene carries the case color, so counting those would tell the coach a beginner
        // reading answers off a picture has mastered Präpositionen — and every downstream
        // surface (Coach's Picks, the "Needs work" flame, the Today plan, conversation
        // steering) would inherit that.
        let earned = result.unscaffolded
        if !earned.isEmpty {
            LearnerMemoryService.applyDrillResult(
                focus: .praepositionen,
                correct: earned.filter(\.firstTry).count,
                total: earned.count,
                in: context
            )
        }

        if feedCoach, !troubleStats.isEmpty {
            let words = troubleStats
                .sorted { $0.timesMissed > $1.timesMissed }
                .prefix(coachFeedCap)
                .map { (german: $0.word, english: $0.meaning) }
            LearnerMemoryService.noteVocabEncounters(Array(words), in: context)
        }

        try? context.save()

        misses.sort { $0.timesMissed > $1.timesMissed }
        return PrepositionRoundFeedback(isPersonalBest: isPersonalBest, misses: misses)
    }

    private static func fetchOrCreateStat(
        for outcome: PrepositionAnswerOutcome,
        in context: ModelContext
    ) -> PrepositionStat {
        let statKey = key(for: outcome.word)
        let descriptor = FetchDescriptor<PrepositionStat>(predicate: #Predicate { $0.key == statKey })
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = PrepositionStat(
            key: statKey,
            word: outcome.word,
            caseRaw: outcome.governs.rawValue,
            meaning: outcome.meaning
        )
        context.insert(created)
        return created
    }

    // MARK: - Manage

    /// Drop one preposition's history.
    static func forget(_ stat: PrepositionStat, in context: ModelContext) {
        context.delete(stat)
        try? context.save()
    }
}
