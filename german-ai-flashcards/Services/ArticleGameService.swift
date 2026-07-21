//
//  ArticleGameService.swift
//  german-ai-flashcards
//
//  Question sourcing + persistence for the der/die/das game, mirroring
//  `MatchingStatsService`'s shape (stateless enum over the caller's `ModelContext`).
//
//  Sources: bundled Goethe lists, the on-device Wiktionary dictionary, the learner's saved
//  decks, words from the learner profile, and the tricky-word re-drill. `recordRound` folds a
//  finished round into per-noun stats + round history, counts it as grammar practice for the
//  streak, moves the profile's Artikel skill via `applyDrillResult`, and (optionally) feeds
//  repeat offenders to the coach so conversations start working them in.
//

import Foundation
import SwiftData

enum ArticleGameService {

    // Tuning
    /// A noun is "tricky" once it's been missed in this many rounds…
    static let troubleMinMisses = 2
    /// …and stays tricky until answered first-try this many rounds in a row.
    static let graduationStreak = 3
    /// At most this many trouble nouns flow into the learner profile per round.
    static let coachFeedCap = 5
    /// A round needs at least this many nouns to be worth playing.
    static let minQuestions = 4

    static func key(for noun: String) -> String {
        noun.lowercased(with: Locale(identifier: "de_DE")).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Question sources

    /// All article-bearing nouns in a Goethe level, deduped.
    static func goetheQuestions(level: GoetheLevel) -> [ArticleQuestion] {
        var seen = Set<String>()
        return GoetheVocabService.entries(for: level).compactMap { entry in
            guard let article = GermanArticle(text: entry.article),
                  let english = entry.translation, !english.isEmpty,
                  seen.insert(key(for: entry.word)).inserted
            else { return nil }
            return ArticleQuestion(noun: entry.word, article: article, english: english)
        }
    }

    /// Random dictionary nouns from the bundled Wiktionary database.
    static func wiktionaryQuestions(count: Int) -> [ArticleQuestion] {
        WiktionaryValidator.shared.randomNouns(count: count).map {
            ArticleQuestion(noun: $0.noun, article: $0.article, english: $0.english)
        }
    }

    /// The article-bearing nouns of one saved deck.
    static func deckQuestions(from deck: SavedDeck) -> [ArticleQuestion] {
        var seen = Set<String>()
        return deck.vocabCards.compactMap { card in
            guard let article = GermanArticle(text: card.article) else { return nil }
            // Strip a baked-in article ("die Gabel" stored as the word on older cards).
            let noun = bareNoun(card.germanWord)
            guard !noun.isEmpty, !card.englishTranslation.isEmpty,
                  seen.insert(key(for: noun)).inserted
            else { return nil }
            return ArticleQuestion(noun: noun, article: article, english: card.englishTranslation)
        }
    }

    /// Words the learner is building (from the coach's profile), resolved to nouns with an
    /// unambiguous gender via the on-device dictionary. This is how the game drills *your*
    /// words, not just lists.
    static func learnerWordQuestions(in context: ModelContext) -> [ArticleQuestion] {
        guard let profile = try? context.fetch(FetchDescriptor<LearnerProfile>()).first else { return [] }
        var seen = Set<String>()
        return profile.vocab.compactMap { touch in
            let noun = bareNoun(touch.german)
            guard !noun.isEmpty, seen.insert(key(for: noun)).inserted,
                  let hit = WiktionaryValidator.shared.nounArticle(for: noun)
            else { return nil }
            let english = touch.english.isEmpty ? (hit.english ?? "") : touch.english
            guard !english.isEmpty else { return nil }
            return ArticleQuestion(noun: noun, article: hit.article, english: english)
        }
    }

    /// Nouns currently worth re-drilling, most-missed (then most recently missed) first.
    static func trickyWords(in context: ModelContext) -> [ArticleWordStat] {
        let all = (try? context.fetch(FetchDescriptor<ArticleWordStat>())) ?? []
        return all
            .filter(\.isTricky)
            .sorted {
                if $0.timesMissed != $1.timesMissed { return $0.timesMissed > $1.timesMissed }
                return ($0.lastMissedAt ?? .distantPast) > ($1.lastMissedAt ?? .distantPast)
            }
    }

    /// A pure tricky-word round, straight from the stats rows.
    static func trickyQuestions(in context: ModelContext) -> [ArticleQuestion] {
        trickyWords(in: context).compactMap { stat in
            guard let article = stat.article else { return nil }
            return ArticleQuestion(noun: stat.noun, article: article, english: stat.english)
        }
    }

    // MARK: - Round assembly

    /// Sample a round from a question pool. With `trickyFirst` on, up to half the round is drawn
    /// from nouns the learner keeps missing — the rest stays random so a round never turns into
    /// a pure punishment drill. Returns nil below `minQuestions`.
    static func session(
        topic: String,
        pool rawPool: [ArticleQuestion],
        count: Int,
        trickyFirst: Bool,
        in context: ModelContext
    ) -> ArticleGameSession? {
        // Callers may concatenate sources (random + tricky) — dedupe by noun, first wins.
        var seen = Set<String>()
        let pool = rawPool.filter { seen.insert(key(for: $0.noun)).inserted }

        guard pool.count >= minQuestions else { return nil }
        guard trickyFirst else {
            return ArticleGameSession(questions: Array(pool.shuffled().prefix(count)), topic: topic)
        }
        let trickyKeys = Set(trickyWords(in: context).map(\.key))
        var tricky: [ArticleQuestion] = []
        var rest: [ArticleQuestion] = []
        for q in pool {
            if trickyKeys.contains(key(for: q.noun)) { tricky.append(q) } else { rest.append(q) }
        }
        let trickyTake = Array(tricky.shuffled().prefix(count / 2))
        let restTake = Array(rest.shuffled().prefix(count - trickyTake.count))
        return ArticleGameSession(questions: (trickyTake + restTake).shuffled(), topic: topic)
    }

    // MARK: - Write: fold one finished round in

    /// Persist a completed round and return the feedback for the summary. Also counts the round
    /// toward the streak (as grammar practice), nudges the profile's Artikel skill, and — with
    /// `feedCoach` on — hands repeatedly-missed nouns to the coach's vocabulary.
    @MainActor
    static func recordRound(
        _ result: ArticleRoundResult,
        topic: String,
        feedCoach: Bool,
        in context: ModelContext
    ) -> ArticleRoundFeedback {
        guard result.questionCount > 0 else { return .empty }
        let now = Date()

        // Personal best = fastest *perfect* round for this source at this size, judged against
        // history before this round is inserted.
        var isPersonalBest = false
        if result.firstTryCount == result.questionCount {
            let count = result.questionCount
            let descriptor = FetchDescriptor<ArticleRound>(
                predicate: #Predicate { $0.topic == topic && $0.questionCount == count }
            )
            let priorBest = ((try? context.fetch(descriptor)) ?? [])
                .filter(\.isPerfect)
                .map(\.durationSeconds)
                .min()
            isPersonalBest = priorBest.map { result.durationSeconds < $0 } ?? true
        }

        context.insert(ArticleRound(
            topic: topic,
            questionCount: result.questionCount,
            firstTryCount: result.firstTryCount,
            durationSeconds: result.durationSeconds
        ))

        // Fold each outcome into its lifetime stat row.
        var misses: [ArticleRoundFeedback.RepeatMiss] = []
        var troubleStats: [ArticleWordStat] = []
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
                // Only a *repeating* wrong article is worth calling out by name.
                let repeated = stat.topWrongPick.flatMap { top in
                    (stat.wrongPicks[top.rawValue] ?? 0) >= 2 ? top : nil
                }
                misses.append(.init(
                    noun: stat.noun,
                    article: outcome.article,
                    english: stat.english,
                    timesMissed: stat.timesMissed,
                    repeatedWrongArticle: repeated
                ))
                if stat.isTricky { troubleStats.append(stat) }
            }
        }

        // Streak + coach memory: a round is grammar practice, and its score moves the
        // profile's Artikel skill exactly like a finished multiple-choice drill.
        StudyLogService.record(.grammar(result.questionCount), in: context)
        LearnerMemoryService.applyDrillResult(
            focus: .artikel,
            correct: result.firstTryCount,
            total: result.questionCount,
            in: context
        )

        if feedCoach, !troubleStats.isEmpty {
            let words = troubleStats
                .sorted { $0.timesMissed > $1.timesMissed }
                .prefix(coachFeedCap)
                .map { (german: $0.displayGerman, english: $0.english) }
            LearnerMemoryService.noteVocabEncounters(Array(words), in: context)
        }

        try? context.save()

        misses.sort { $0.timesMissed > $1.timesMissed }
        return ArticleRoundFeedback(isPersonalBest: isPersonalBest, misses: misses)
    }

    private static func fetchOrCreateStat(
        for outcome: ArticleAnswerOutcome,
        in context: ModelContext
    ) -> ArticleWordStat {
        let statKey = key(for: outcome.noun)
        let descriptor = FetchDescriptor<ArticleWordStat>(predicate: #Predicate { $0.key == statKey })
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = ArticleWordStat(
            key: statKey,
            noun: outcome.noun,
            articleRaw: outcome.article.rawValue,
            english: outcome.english
        )
        context.insert(created)
        return created
    }

    // MARK: - Manage

    /// Drop one noun's history (swipe-to-remove on the tricky list).
    static func forgetWord(_ stat: ArticleWordStat, in context: ModelContext) {
        context.delete(stat)
        try? context.save()
    }

    // MARK: - Helpers

    /// "die Gabel" → "Gabel"; leaves bare nouns untouched.
    static func bareNoun(_ word: String) -> String {
        var trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        for article in GermanArticle.allCases {
            let prefix = article.rawValue + " "
            if trimmed.lowercased().hasPrefix(prefix) {
                trimmed = String(trimmed.dropFirst(prefix.count))
                break
            }
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }
}
