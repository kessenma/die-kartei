//
//  ScreenshotDataSeeder.swift
//  german-ai-flashcards
//
//  The developer screenshot door: fills a device with a plausible ten months of German study so
//  the streak calendar, the Lernpyramide and „Dein Weg" can be photographed on hardware nobody
//  has ever learned on. Reached from Settings ▸ Developer, which only exists in DEBUG and
//  TestFlight builds (see `ScreenshotSeeding.isAvailable`) — an App Store build has no door.
//
//  Two rules shape everything here:
//
//  * **Nothing is faked past the front door.** The seeder writes the same records real study
//    writes — `StudyDay` rows, `SavedCard` intervals, `PrepositionStat` streaks, quiz attempts,
//    chat summaries — and then lets `PyramidService`, `ExperienceService`, `JourneyService` and
//    `AchievementService` derive the screens from them exactly as they always do. A screenshot
//    taken after seeding shows numbers that agree with each other, because nothing computed one
//    of them by hand.
//  * **It is reversible.** Everything the seeder is about to destroy (the study log, `journey.json`,
//    the placement history, badge dates, the coaching profile) is written to
//    `Application Support/Developer/screenshot-backup.json` first, and every row it *creates* is
//    recorded there by id. `restore(in:)` deletes what was created and puts the originals back.
//
//  Output is deterministic (`SeededGenerator`, one fixed seed), so re-seeding a second device
//  produces the same calendar and the same pyramid — which is the point when a screenshot set has
//  to match across an iPhone and an iPad.
//
//  The one invariant it deliberately steps over: `docs/GAMIFICATION.md`'s "placement never writes
//  `LearnerProfile.grammar`, and never automatically". This is not placement and not automatic —
//  it is an explicit, confirmed, reversible developer action, and Grammatik-Kern cannot be filled
//  any other way. `restore(in:)` puts the real `grammar` blob back byte for byte.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Availability

enum ScreenshotSeeding {

    /// DEBUG builds always; TestFlight betas carry a `sandboxReceipt` where the App Store build
    /// carries a `receipt`. The seeder destroys progress, so it must not exist for anyone who
    /// installed the app to actually learn German with it.
    static var isAvailable: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}

// MARK: - Backup

/// Everything `fill(in:)` overwrites, plus the ids of everything it creates. One file, written
/// before the first row changes.
nonisolated struct ScreenshotSeedBackup: Codable {
    var createdAt: Date = Date()

    // Replaced wholesale
    var studyDays: [StudyDayRecord] = []
    /// Optional only because `JourneyDocument`'s init is MainActor-isolated and this struct is
    /// not — `captureBackup` always sets it.
    var journey: JourneyDocument?
    var placementAttempts: [PlacementAttempt] = []
    var placementResult: PlacementResult?
    var placementSeen: Bool = false
    var achievementsEarned: [String: Date] = [:]
    var achievementsSeeded: Bool = false

    // The coaching profile's four encoded buckets, exactly as they were.
    var hadLearnerProfile: Bool = false
    var profileGrammar: Data?
    var profileVocab: Data?
    var profileSlips: Data?
    var profileSessionCount: Int = 0
    var profileLastSessionAt: Date?

    // Created by the fill, deleted by the restore
    var seededDeckIDs: [UUID] = []
    var seededStoryAttemptIDs: [UUID] = []
    var seededConversationIDs: [UUID] = []
    var seededArchivedIDs: [UUID] = []
    /// Only prepositions the fill *introduced* — a key that already had a real row was left alone.
    var seededPrepositionKeys: [String] = []
    var seededMatchingRoundDates: [Date] = []
    var seededArticleRoundDates: [Date] = []
    var seededPrepositionRoundDates: [Date] = []
}

/// `StudyDay` flattened for the backup file — the model is a `@Model`, which is not `Codable`.
nonisolated struct StudyDayRecord: Codable {
    var dayStart: Date
    var cardsReviewed: Int
    var grammarExercises: Int
    var conversations: Int
    var storySeconds: Int
    var storyQuestions: Int
    var lastActivityAt: Date
    var cardSeconds: Int
    var grammarSeconds: Int
    var conversationSeconds: Int
    var storyQuizSeconds: Int
    /// Optional so backups written before the Wortschatz budget existed still decode.
    var newWordsIntroduced: Int? = 0
    var newWordsBonus: Int? = 0
}

/// `Application Support/Developer/screenshot-backup.json`. Same storage rationale as
/// `PlacementAttemptStore`: not SwiftData (the store resets itself on migration failure and this
/// has to survive that), not UserDefaults (it is far too big for the launch path).
enum ScreenshotSeedBackupStore {

    private static var fileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Developer")
            .appendingPathComponent("screenshot-backup.json")
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    static func load() -> ScreenshotSeedBackup? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(ScreenshotSeedBackup.self, from: data)
    }

    static func save(_ backup: ScreenshotSeedBackup) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(backup) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

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
}

// MARK: - Seeder

enum ScreenshotDataSeeder {

    // MARK: Shape of the fake learner
    //
    // These are the only numbers worth tuning. Everything downstream — XP, level, badges, the
    // pyramid's percentages, the journey's milestones — falls out of them.

    /// How far back the study log runs. Long enough for the Year heatmap to have a story.
    static let historyDays = 300
    /// The unbroken run ending today. Past 30 and short of 100, so the streak grid shows a long
    /// live run and the badge wall shows both earned and unearned states.
    static let currentStreakDays = 62

    /// A1 words proven (of the 585-word Goethe list) and A2 words proven (of the 200-word goal).
    static let learnedA1Count = 350
    static let learnedA2Count = 120
    /// Cards in the library that are *not* yet proven, so Wortschatz isn't suspiciously full.
    static let unlearnedCount = 110

    /// Core prepositions graduated out of the tricky list, and how many are left visibly shaky.
    static let masteredPrepositionCount = 20
    static let trickyPrepositionCount = 4

    /// Weekly rows behind „Damals & heute" and the trend line.
    static let snapshotWeeks = 16

    private static let rngSeed: UInt64 = 20_260_913

    // MARK: - Fill

    /// Replaces this device's progress with the screenshot set. Safe to call twice: a second fill
    /// restores the first one before it starts, so demo decks and demo chats never stack up.
    @discardableResult
    static func fill(in context: ModelContext) -> String {
        guard ScreenshotSeeding.isAvailable else { return "Not available in this build." }

        // A second fill undoes the first, so the real data underneath is still the thing backed up.
        if ScreenshotSeedBackupStore.exists { _ = restore(in: context) }

        var backup = captureBackup(in: context)
        ScreenshotSeedBackupStore.save(backup)

        var rng = SeededGenerator(seed: rngSeed)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 1. The study log — the spine. Streak, calendar, XP, level and every replayed journey
        //    milestone are read back off these rows.
        try? context.delete(model: StudyDay.self)
        let plan = studyPlan(&rng, today: today, calendar: calendar)
        for day in plan { context.insert(day.makeStudyDay()) }

        // 2. The vocabulary the pyramid counts.
        let decks = seedVocabulary(&rng, today: today, calendar: calendar, in: context)
        backup.seededDeckIDs = decks.map(\.id)

        // 3. The rest of the pyramid's inputs.
        backup.seededPrepositionKeys = seedPrepositions(&rng, today: today, calendar: calendar, in: context)
        backup.seededStoryAttemptIDs = seedStories(today: today, calendar: calendar, in: context)
        backup.seededConversationIDs = seedConversations(&rng, today: today, calendar: calendar, in: context)
        backup.seededArchivedIDs = seedMasteredSlips(today: today, calendar: calendar, in: context)
        seedGrammarProfile(today: today, calendar: calendar, in: context)

        // 4. Game rounds — the three "perfect round" badges, and something for the progress strips.
        let rounds = seedGameRounds(today: today, calendar: calendar, in: context)
        backup.seededMatchingRoundDates = rounds.matching
        backup.seededArticleRoundDates = rounds.article
        backup.seededPrepositionRoundDates = rounds.preposition

        // 5. Day-detail rows for the days a screenshot is most likely to tap into.
        seedQuizResults(&rng, plan: plan, deck: decks.first, in: context)

        try? context.save()

        // 6. Derived history, written only once the SwiftData side is settled — the journey
        //    snapshots read the *live* pyramid so the header's "% built" can never disagree with
        //    the pyramid screen.
        seedPlacementHistory(today: today, calendar: calendar)
        seedJourney(plan: plan, today: today, calendar: calendar, in: context)
        seedBadges(plan: plan, in: context)

        ScreenshotSeedBackupStore.save(backup)

        let activeDays = plan.count
        return "Filled: \(activeDays) study days, \(learnedA1Count + learnedA2Count + unlearnedCount) cards, "
            + "a \(currentStreakDays)-day streak. Your real data is backed up."
    }

    // MARK: - Restore

    /// Puts the real device back. Returns false when there is nothing to restore.
    @discardableResult
    static func restore(in context: ModelContext) -> Bool {
        guard let backup = ScreenshotSeedBackupStore.load() else { return false }

        // Everything the fill created.
        let deckIDs = Set(backup.seededDeckIDs)
        for deck in fetchAll(SavedDeck.self, in: context) where deckIDs.contains(deck.id) {
            context.delete(deck)   // cascades to its cards and quiz results
        }
        let storyIDs = Set(backup.seededStoryAttemptIDs)
        for attempt in fetchAll(StoryQuizAttempt.self, in: context) where storyIDs.contains(attempt.id) {
            context.delete(attempt)
        }
        let chatIDs = Set(backup.seededConversationIDs)
        for chat in fetchAll(ChatConversation.self, in: context) where chatIDs.contains(chat.id) {
            context.delete(chat)
        }
        let archivedIDs = Set(backup.seededArchivedIDs)
        for item in fetchAll(ArchivedMemoryItem.self, in: context) where archivedIDs.contains(item.id) {
            context.delete(item)
        }
        let prepositionKeys = Set(backup.seededPrepositionKeys)
        for stat in fetchAll(PrepositionStat.self, in: context) where prepositionKeys.contains(stat.key) {
            context.delete(stat)
        }
        let matchingDates = Set(backup.seededMatchingRoundDates)
        for round in fetchAll(MatchingRound.self, in: context) where matchingDates.contains(round.date) {
            context.delete(round)
        }
        let articleDates = Set(backup.seededArticleRoundDates)
        for round in fetchAll(ArticleRound.self, in: context) where articleDates.contains(round.date) {
            context.delete(round)
        }
        let prepositionDates = Set(backup.seededPrepositionRoundDates)
        for round in fetchAll(PrepositionRound.self, in: context) where prepositionDates.contains(round.date) {
            context.delete(round)
        }

        // The study log, as it was.
        try? context.delete(model: StudyDay.self)
        for record in backup.studyDays {
            let day = StudyDay(dayStart: record.dayStart)
            day.cardsReviewed = record.cardsReviewed
            day.grammarExercises = record.grammarExercises
            day.conversations = record.conversations
            day.storySeconds = record.storySeconds
            day.storyQuestions = record.storyQuestions
            day.lastActivityAt = record.lastActivityAt
            day.cardSeconds = record.cardSeconds
            day.grammarSeconds = record.grammarSeconds
            day.conversationSeconds = record.conversationSeconds
            day.storyQuizSeconds = record.storyQuizSeconds
            day.newWordsIntroduced = record.newWordsIntroduced ?? 0
            day.newWordsBonus = record.newWordsBonus ?? 0
            context.insert(day)
        }

        // The coaching profile's buckets, byte for byte.
        let profiles = fetchAll(LearnerProfile.self, in: context)
        if backup.hadLearnerProfile {
            let profile = profiles.first ?? {
                let created = LearnerProfile()
                context.insert(created)
                return created
            }()
            profile.grammarData = backup.profileGrammar
            profile.vocabData = backup.profileVocab
            profile.slipsData = backup.profileSlips
            profile.sessionCount = backup.profileSessionCount
            profile.lastSessionAt = backup.profileLastSessionAt
        } else {
            // There was no profile before the fill — the fill made one.
            for profile in profiles { context.delete(profile) }
        }

        try? context.save()

        // The three file/defaults-backed stores.
        ProgressSnapshotStore.save(backup.journey ?? JourneyDocument())

        PlacementAttemptStore.deleteAll()
        for attempt in backup.placementAttempts.sorted(by: { $0.takenAt < $1.takenAt }) {
            PlacementAttemptStore.append(attempt)
        }
        if let result = backup.placementResult {
            PlacementService.save(result)
        } else {
            PlacementService.clear()
        }
        UserDefaults.standard.set(backup.placementSeen, forKey: PlacementService.seenKey)

        AchievementService.replaceEarnedDates(backup.achievementsEarned, seeded: backup.achievementsSeeded)

        ScreenshotSeedBackupStore.clear()
        return true
    }

    /// When the last fill happened, or nil if this device holds no seeded data.
    static var seededAt: Date? { ScreenshotSeedBackupStore.load()?.createdAt }

    // MARK: - Capture

    private static func captureBackup(in context: ModelContext) -> ScreenshotSeedBackup {
        var backup = ScreenshotSeedBackup()
        backup.studyDays = fetchAll(StudyDay.self, in: context).map { day in
            StudyDayRecord(
                dayStart: day.dayStart,
                cardsReviewed: day.cardsReviewed,
                grammarExercises: day.grammarExercises,
                conversations: day.conversations,
                storySeconds: day.storySeconds,
                storyQuestions: day.storyQuestions,
                lastActivityAt: day.lastActivityAt,
                cardSeconds: day.cardSeconds,
                grammarSeconds: day.grammarSeconds,
                conversationSeconds: day.conversationSeconds,
                storyQuizSeconds: day.storyQuizSeconds,
                newWordsIntroduced: day.newWordsIntroduced,
                newWordsBonus: day.newWordsBonus
            )
        }
        backup.journey = ProgressSnapshotStore.document()
        backup.placementAttempts = PlacementAttemptStore.attempts()
        backup.placementResult = PlacementService.current
        backup.placementSeen = PlacementService.hasBeenOffered
        backup.achievementsEarned = AchievementService.earnedDatesForBackup()
        backup.achievementsSeeded = AchievementService.hasSeededBadges

        if let profile = fetchAll(LearnerProfile.self, in: context).first {
            backup.hadLearnerProfile = true
            backup.profileGrammar = profile.grammarData
            backup.profileVocab = profile.vocabData
            backup.profileSlips = profile.slipsData
            backup.profileSessionCount = profile.sessionCount
            backup.profileLastSessionAt = profile.lastSessionAt
        }
        return backup
    }

    // MARK: - The study log

    /// One day the fake learner studied, before it becomes a `StudyDay`.
    private struct PlannedDay {
        var dayStart: Date
        var lastActivityAt: Date
        var cards: Int
        var grammar: Int
        var conversations: Int
        var storyQuestions: Int
        var cardSeconds: Int
        var grammarSeconds: Int
        var conversationSeconds: Int
        var storySeconds: Int
        var storyQuizSeconds: Int

        func makeStudyDay() -> StudyDay {
            let day = StudyDay(dayStart: dayStart)
            day.cardsReviewed = cards
            day.grammarExercises = grammar
            day.conversations = conversations
            day.storyQuestions = storyQuestions
            day.cardSeconds = cardSeconds
            day.grammarSeconds = grammarSeconds
            day.conversationSeconds = conversationSeconds
            day.storySeconds = storySeconds
            day.storyQuizSeconds = storyQuizSeconds
            day.lastActivityAt = lastActivityAt
            return day
        }
    }

    /// Which days were studied and how hard. Three eras, because a flat random log looks like
    /// noise rather than a learner: a thin start, a thickening middle with real gaps, and the
    /// unbroken run that owns the flame.
    private static func studyPlan(
        _ rng: inout SeededGenerator, today: Date, calendar: Calendar
    ) -> [PlannedDay] {
        var out: [PlannedDay] = []
        for offset in 0..<historyDays {
            guard isActive(offset: offset, &rng) else { continue }
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }

            // Effort bands. Light days are the majority — a heatmap where every cell is deep blue
            // reads as fake, and the shade ramp has five steps to show.
            let roll = Double.random(in: 0..<1, using: &rng)
            let cards: Int
            let grammar: Int
            if roll < 0.28 {
                cards = Int.random(in: 3...9, using: &rng)
                grammar = Int.random(in: 0...4, using: &rng)
            } else if roll < 0.75 {
                cards = Int.random(in: 10...23, using: &rng)
                grammar = Int.random(in: 4...13, using: &rng)
            } else {
                cards = Int.random(in: 24...46, using: &rng)
                grammar = Int.random(in: 10...25, using: &rng)
            }

            let conversations = Double.random(in: 0..<1, using: &rng) < 0.14 ? 1 : 0
            let storyQuestions = Double.random(in: 0..<1, using: &rng) < 0.22
                ? Int.random(in: 3...8, using: &rng) : 0
            let storySeconds = Double.random(in: 0..<1, using: &rng) < 0.28
                ? Int.random(in: 240...1_500, using: &rng) : 0

            // Seconds are derived from the counts rather than rolled independently, so the Items
            // and Time shadings of the calendar agree about which days were big.
            let hour = Int.random(in: 8...21, using: &rng)
            let minute = Int.random(in: 0...59, using: &rng)
            out.append(PlannedDay(
                dayStart: dayStart,
                lastActivityAt: calendar.date(byAdding: .minute, value: hour * 60 + minute, to: dayStart) ?? dayStart,
                cards: cards,
                grammar: grammar,
                conversations: conversations,
                storyQuestions: storyQuestions,
                cardSeconds: cards * Int.random(in: 6...12, using: &rng),
                grammarSeconds: grammar * Int.random(in: 9...18, using: &rng),
                conversationSeconds: conversations * Int.random(in: 200...620, using: &rng),
                storySeconds: storySeconds,
                storyQuizSeconds: storyQuestions * Int.random(in: 18...40, using: &rng)
            ))
        }
        return out.sorted { $0.dayStart < $1.dayStart }
    }

    private static func isActive(offset: Int, _ rng: inout SeededGenerator) -> Bool {
        // The live run, then the two-day gap that ends it, then a habit that thickens over time.
        if offset < currentStreakDays { return true }
        if offset < currentStreakDays + 2 { return false }
        let span = Double(historyDays - currentStreakDays - 2)
        let age = Double(offset - currentStreakDays - 2) / max(1, span)   // 0 = recent, 1 = oldest
        let probability = 0.74 - 0.42 * age
        return Double.random(in: 0..<1, using: &rng) < probability
    }

    // MARK: - Vocabulary

    /// Three decks off the Goethe lists: what's proven at A1, what's proven at A2, and a batch
    /// that is still being learned. Named by level rather than by topic, because the words come
    /// off the list in list order and a "Food and Drink" deck full of `arbeiten` reads as a lie
    /// in the very screenshot it was made for.
    private static func seedVocabulary(
        _ rng: inout SeededGenerator, today: Date, calendar: Calendar, in context: ModelContext
    ) -> [SavedDeck] {
        var used = Set<String>()
        func pick(_ level: GoetheLevel, _ count: Int) -> [A1Entry] {
            GoetheVocabService.entries(for: level)
                .filter { ($0.translation?.isEmpty == false) && used.insert($0.word.lowercased()).inserted }
                .shuffled(using: &rng)
                .prefix(count)
                .map { $0 }
        }

        let a1 = pick(.a1, learnedA1Count)
        let a2 = pick(.a2, learnedA2Count)
        let fresh = pick(.a1, unlearnedCount / 2) + pick(.a2, unlearnedCount - unlearnedCount / 2)

        var decks: [SavedDeck] = []
        decks.append(makeDeck("Goethe A1 · Grundwortschatz", entries: a1, learned: true,
                              createdAt: date(today, minusDays: historyDays - 6, calendar), &rng, in: context))
        decks.append(makeDeck("Goethe A2 · Aufbauwortschatz", entries: a2, learned: true,
                              createdAt: date(today, minusDays: 150, calendar), &rng, in: context))
        decks.append(makeDeck("Neu dazugelernt · Just added", entries: fresh, learned: false,
                              createdAt: date(today, minusDays: 26, calendar), &rng, in: context))
        return decks
    }

    private static func makeDeck(
        _ topic: String, entries: [A1Entry], learned: Bool, createdAt: Date,
        _ rng: inout SeededGenerator, in context: ModelContext
    ) -> SavedDeck {
        let deck = SavedDeck(
            topic: topic,
            wordCount: entries.count,
            includeExamples: true,
            createdAt: createdAt
        )
        deck.generatorRaw = MLXModel.hero.rawValue
        context.insert(deck)

        for (index, entry) in entries.enumerated() {
            let card = SavedCard(
                germanWord: entry.word,
                englishTranslation: entry.translation ?? "",
                wordType: entry.wordType,
                article: entry.article,
                exampleSentence: entry.example?.isEmpty == false ? entry.example : nil,
                sortOrder: index
            )
            if learned {
                // Proven: three-plus consecutive correct reviews, or an interval past Anki's
                // three-week maturity bar — the two rules `PyramidService.learnedWords` reads.
                card.repetitions = Int.random(in: 3...7, using: &rng)
                card.interval = Int.random(in: 21...120, using: &rng)
                card.easeFactor = Double.random(in: 2.1...2.8, using: &rng)
                card.totalReviews = card.repetitions + Int.random(in: 0...6, using: &rng)
                card.leitnerBox = Int.random(in: 4...5, using: &rng)
                // Every twelfth word was forgotten once and won back — the „Zurückgeholt" section
                // on „Dein Weg" is built from exactly this shape.
                card.lapses = index % 12 == 0 ? Int.random(in: 1...2, using: &rng) : 0
            } else {
                card.repetitions = Int.random(in: 0...2, using: &rng)
                card.interval = Int.random(in: 0...9, using: &rng)
                card.easeFactor = Double.random(in: 1.9...2.5, using: &rng)
                card.totalReviews = Int.random(in: 1...5, using: &rng)
                card.leitnerBox = Int.random(in: 1...3, using: &rng)
                // A miss the app has watched and not seen repaired — this is what makes the
                // placement blueprint shrink instead of standing forever.
                card.lapses = index % 5 == 0 ? 1 : 0
            }
            card.nextReviewDate = Date().addingTimeInterval(Double(card.interval - 2) * 86_400)
            card.deck = deck
            context.insert(card)
        }
        return deck
    }

    // MARK: - Prepositions

    /// Graduated core prepositions (Fundament), plus a few still visibly tricky so the layer isn't
    /// suspiciously complete and the drill's tricky list has something in it. Keys that already
    /// carry a real row are skipped — the restore only deletes what it introduced.
    private static func seedPrepositions(
        _ rng: inout SeededGenerator, today: Date, calendar: Calendar, in context: ModelContext
    ) -> [String] {
        let existing = Set(fetchAll(PrepositionStat.self, in: context).map(\.key))
        let core = PrepositionService.prepositions(includeAdvanced: false)
            .filter { !existing.contains(PrepositionService.key(for: $0.word)) }

        var created: [String] = []
        for (index, preposition) in core.prefix(masteredPrepositionCount + trickyPrepositionCount).enumerated() {
            let key = PrepositionService.key(for: preposition.word)
            let stat = PrepositionStat(
                key: key,
                word: preposition.word,
                caseRaw: preposition.governs.rawValue,
                meaning: preposition.meaningLine
            )
            let isTricky = index >= masteredPrepositionCount
            stat.timesSeen = Int.random(in: 4...11, using: &rng)
            stat.timesMissed = isTricky
                ? Int.random(in: 2...4, using: &rng)
                : Int.random(in: 0...2, using: &rng)
            stat.firstTryStreak = isTricky
                ? Int.random(in: 0...2, using: &rng)
                : Int.random(in: PrepositionService.graduationStreak...6, using: &rng)
            stat.lastSeenAt = date(today, minusDays: Int.random(in: 1...30, using: &rng), calendar)
            stat.lastMissedAt = stat.timesMissed > 0
                ? date(today, minusDays: Int.random(in: 31...120, using: &rng), calendar)
                : nil
            context.insert(stat)
            created.append(key)
        }
        return created
    }

    // MARK: - Stories

    /// Three A1 stories understood (the layer completes), two A2 (it doesn't), and one that was
    /// failed — a wall of passes reads as a demo, and the failed one is what makes the rest land.
    private static func seedStories(
        today: Date, calendar: Calendar, in context: ModelContext
    ) -> [UUID] {
        let seeds: [(title: String, level: CEFRLevel, questions: Int, correct: Int, seconds: Int, daysAgo: Int)] = [
            ("Der verlorene Schlüssel",   .a1, 8, 8, 214, 190),
            ("Ein Tag am Fluss",          .a1, 6, 5, 178, 151),
            ("Die Bäckerei um die Ecke",  .a1, 8, 7, 243,  96),
            ("Das Amt",                   .a2, 8, 5, 321,  74),
            ("Der Zug nach Hamburg",      .a2, 8, 7, 298,  61),
            ("Nachbarn",                  .a2, 6, 5, 262,  24),
        ]
        var ids: [UUID] = []
        for seed in seeds {
            let attempt = StoryQuizAttempt(
                storyID: UUID(),
                storyTitle: seed.title,
                levelRaw: seed.level.rawValue,
                questionCount: seed.questions,
                correctCount: seed.correct,
                durationSeconds: seed.seconds,
                wasListening: seed.daysAgo % 3 == 0,
                writtenCount: seed.questions / 4
            )
            attempt.date = date(today, minusDays: seed.daysAgo, calendar).addingTimeInterval(19 * 3_600)
            context.insert(attempt)
            ids.append(attempt.id)
        }
        return ids
    }

    // MARK: - Conversations

    /// Fourteen chats, of which seven are *held well* — the Spitze counts quality, not attendance,
    /// so the peak needs summaries with a real turn count and a low correction density.
    private static func seedConversations(
        _ rng: inout SeededGenerator, today: Date, calendar: Calendar, in context: ModelContext
    ) -> [UUID] {
        let scenarios: [ConversationScenario] = [
            .bakery, .doctor, .smallTalk, .transport, .shopping, .restaurant, .apartmentViewing,
            .haircut, .bank, .hotel, .party, .cafe, .pharmacy, .makePlans,
        ]
        // Well held / judged-but-corrected-heavily / too short to judge.
        let quality: [String] = [
            "good", "good", "dense", "good", "short", "good", "dense",
            "good", "good", "short", "dense", "good", "dense", "short",
        ]

        var ids: [UUID] = []
        for (index, scenario) in scenarios.enumerated() {
            var config = ConversationConfig(model: .hero)
            config.mode = .scenario
            config.scenario = scenario
            config.level = index < 6 ? .a2 : .b1
            let createdAt = date(today, minusDays: 196 - index * 14, calendar)
                .addingTimeInterval(Double(Int.random(in: 10...20, using: &rng)) * 3_600)

            let chat = ChatConversation(config: config, createdAt: createdAt)
            chat.updatedAt = createdAt
            let turns: Int
            let corrections: Int
            switch quality[index] {
            case "good":
                turns = Int.random(in: 8...16, using: &rng)
                corrections = Int(Double(turns) * Double.random(in: 0.05...0.30, using: &rng))
            case "dense":
                turns = Int.random(in: 6...11, using: &rng)
                corrections = Int(Double(turns) * Double.random(in: 0.55...0.95, using: &rng))
            default:
                turns = Int.random(in: 2...3, using: &rng)   // below `minimumTurns`: not judged
                corrections = 1
            }
            chat.durationSeconds = turns * Int.random(in: 40...80, using: &rng)
            chat.setSummary(ConversationSummary(
                strengths: ["Klare Sätze", "Gute Wortwahl"],
                improvements: corrections > 0 ? ["Achte auf den Dativ nach «mit»"] : [],
                patternNote: corrections > 2
                    ? "Der Akkusativ nach «für» rutscht noch."
                    : "Sitzt — die Fälle kamen von allein.",
                wordsPracticed: ["bestellen", "Termin", "Quittung"],
                correctionCount: corrections,
                turnCount: turns,
                generatedAt: createdAt
            ))
            context.insert(chat)
            ids.append(chat.id)
        }
        return ids
    }

    // MARK: - Mastered slips

    /// Retired coaching slips. These are what „Dein Weg" dates as «…» gemeistert, and what the
    /// „Weißt du es noch?" probe draws from — so every one is at least 30 days old and carries the
    /// sentence and blank index the probe needs to build a question.
    private static func seedMasteredSlips(
        today: Date, calendar: Calendar, in context: ModelContext
    ) -> [UUID] {
        let seeds: [(wrong: String, right: String, note: String, sentence: String, blank: Int, daysAgo: Int)] = [
            ("gefahrt",   "gefahren",   "Partizip II von fahren",        "Ich bin nach Berlin gefahren.",   4, 211),
            ("gegeht",    "gegangen",   "Partizip II von gehen",         "Sie ist zur Arbeit gegangen.",    4, 188),
            ("dem",       "den",        "Akkusativ Maskulinum",          "Ich sehe den Hund.",              2, 166),
            ("die",       "der",        "Dativ Femininum",               "Ich helfe der Frau.",             2, 143),
            ("ins",       "im",         "Ort, nicht Richtung",           "Wir sind im Kino.",               2, 128),
            ("gebringt",  "gebracht",   "Partizip II von bringen",       "Er hat den Kuchen gebracht.",     4, 111),
            ("kann",      "könnte",     "Konjunktiv II für Höflichkeit", "Könnte ich bitte zahlen?",        0,  97),
            ("Buch",      "Buches",     "Genitiv Neutrum",               "Der Titel des Buches ist lang.",  3,  82),
            ("esse",      "isst",       "3. Person Singular von essen",  "Er isst gern Kuchen.",            1,  63),
            ("arbeitet",  "gearbeitet", "Partizip II von arbeiten",      "Ich habe gestern gearbeitet.",    3,  46),
        ]
        var ids: [UUID] = []
        for seed in seeds {
            let archivedAt = date(today, minusDays: seed.daysAgo, calendar)
            let slip = LexicalSlip(
                wrong: seed.wrong,
                right: seed.right,
                note: seed.note,
                lastSeen: archivedAt,
                timesSeen: 3,
                sentence: seed.sentence,
                blankIndex: seed.blank
            )
            let item = ArchivedMemoryItem(
                kind: .slip,
                reason: .mastered,
                title: "\(seed.wrong) → \(seed.right)",
                subtitle: seed.note,
                payload: try? JSONEncoder().encode(slip)
            )
            item.archivedAt = archivedAt
            context.insert(item)
            ids.append(item.id)
        }
        return ids
    }

    // MARK: - Coaching profile

    /// Three of the four core structures Solid (Grammatik-Kern lands at 3/4 — a complete Kern with
    /// a half-empty Spitze above it looks wrong), six Solid overall so the Grammatik-Guru badge
    /// earns, plus the vocab and slips that give Coach's Notes something to show.
    ///
    /// This is the one write in the app that touches `LearnerProfile.grammar` outside real
    /// coaching. See the file header for why that's allowed here and nowhere else.
    private static func seedGrammarProfile(today: Date, calendar: Calendar, in context: ModelContext) {
        let profile = fetchAll(LearnerProfile.self, in: context).first ?? {
            let created = LearnerProfile()
            context.insert(created)
            return created
        }()

        let struggles: [(GrammarFocus, Double)] = [
            (.akkusativ, 0.06), (.dativ, 0.11), (.artikel, 0.09),
            (.perfekt, 0.12), (.modalverben, 0.08), (.praeteritum, 0.15),
            (.praepositionen, 0.44), (.genitiv, 0.38),
            (.konjunktiv2, 0.52), (.adjektivendungen, 0.61),
        ]
        var grammar: [String: GrammarSkill] = [:]
        for (offset, entry) in struggles.enumerated() {
            grammar[entry.0.rawValue] = GrammarSkill(
                struggle: entry.1,
                lastSeen: date(today, minusDays: offset * 3 + 1, calendar),
                samples: entry.1 >= GrammarSkill.shakyThreshold
                    ? ["Ich warte auf der Bus. → Ich warte auf den Bus."]
                    : []
            )
        }
        profile.grammar = grammar

        profile.vocab = [
            VocabTouch(german: "die Quittung", english: "receipt", lastSeen: date(today, minusDays: 2, calendar), timesUsed: 4),
            VocabTouch(german: "der Termin", english: "appointment", lastSeen: date(today, minusDays: 4, calendar), timesUsed: 6),
            VocabTouch(german: "kündigen", english: "to cancel, to give notice", lastSeen: date(today, minusDays: 6, calendar), timesUsed: 2),
            VocabTouch(german: "die Anmeldung", english: "registration", lastSeen: date(today, minusDays: 9, calendar), timesUsed: 3),
            VocabTouch(german: "beantragen", english: "to apply for", lastSeen: date(today, minusDays: 13, calendar), timesUsed: 2),
        ]
        profile.slips = [
            LexicalSlip(wrong: "auf der Bus", right: "auf den Bus", note: "warten auf + Akkusativ",
                        lastSeen: date(today, minusDays: 3, calendar), timesSeen: 4,
                        sentence: "Ich warte auf den Bus.", blankIndex: 3),
            LexicalSlip(wrong: "seit zwei Jahre", right: "seit zwei Jahren", note: "seit + Dativ Plural",
                        lastSeen: date(today, minusDays: 8, calendar), timesSeen: 2,
                        sentence: "Ich lerne seit zwei Jahren Deutsch.", blankIndex: 4),
        ]
        profile.sessionCount = 34
        profile.lastSessionAt = date(today, minusDays: 1, calendar)
    }

    // MARK: - Game rounds

    /// One perfect round of each game (the three "fehlerfrei" badges) plus a couple of imperfect
    /// ones so the progress strips have a shape.
    private static func seedGameRounds(
        today: Date, calendar: Calendar, in context: ModelContext
    ) -> (matching: [Date], article: [Date], preposition: [Date]) {
        var matching: [Date] = []
        var article: [Date] = []
        var preposition: [Date] = []

        for (daysAgo, pairs, firstTry) in [(58, 8, 6), (31, 8, 8), (9, 10, 9)] {
            let round = MatchingRound(topic: "Goethe A1", pairCount: pairs,
                                      firstTryCount: firstTry, durationSeconds: pairs * 9)
            round.date = date(today, minusDays: daysAgo, calendar).addingTimeInterval(18 * 3_600)
            context.insert(round)
            matching.append(round.date)
        }
        for (daysAgo, questions, firstTry) in [(72, 12, 9), (40, 12, 12), (5, 15, 13)] {
            let round = ArticleRound(topic: "Goethe A1", questionCount: questions,
                                     firstTryCount: firstTry, durationSeconds: questions * 6)
            round.date = date(today, minusDays: daysAgo, calendar).addingTimeInterval(20 * 3_600)
            context.insert(round)
            article.append(round.date)
        }
        for (daysAgo, questions, firstTry) in [(66, 10, 7), (22, 10, 10), (3, 12, 11)] {
            let round = PrepositionRound(topic: "Kasus", questionCount: questions,
                                         firstTryCount: firstTry, durationSeconds: questions * 8)
            round.date = date(today, minusDays: daysAgo, calendar).addingTimeInterval(17 * 3_600)
            context.insert(round)
            preposition.append(round.date)
        }
        return (matching, article, preposition)
    }

    // MARK: - Day detail

    /// The day sheet lists timestamped records and only falls back to the `StudyDay` totals when a
    /// day has none. Recent days are the ones a screenshot taps into, so give them real
    /// `QuizResult` rows; older days read fine off the fallback.
    private static func seedQuizResults(
        _ rng: inout SeededGenerator, plan: [PlannedDay], deck: SavedDeck?, in context: ModelContext
    ) {
        guard let deck else { return }
        let recent = plan.suffix(28)
        for day in recent where day.cards > 0 {
            let correct = max(1, Int(Double(day.cards) * Double.random(in: 0.72...1.0, using: &rng)))
            let result = QuizResult(
                totalCards: day.cards,
                correctCount: min(correct, day.cards),
                durationSeconds: day.cardSeconds,
                date: day.lastActivityAt,
                studyMode: .anki
            )
            result.deck = deck
            context.insert(result)
        }
    }

    // MARK: - Placement history

    /// Three real runs of the probe, backdated and answered at rising accuracy, so „Dein Weg"
    /// shows a blueprint being redrawn (A1 → A2 → B1) and the pyramid carries a ghost channel.
    ///
    /// Drives an actual `PlacementSession` rather than hand-writing a `PlacementResult`: the
    /// questions, the staircases and the scorer are then the real ones, and the answer-review
    /// screen has genuine records to show.
    private static func seedPlacementHistory(today: Date, calendar: Calendar) {
        PlacementAttemptStore.deleteAll()
        var rng = SeededGenerator(seed: rngSeed &+ 7)

        for (daysAgo, accuracy) in [(284, 0.34), (152, 0.55), (38, 0.74)] {
            let session = PlacementSession()
            while let item = session.current {
                let roll = Double.random(in: 0..<1, using: &rng)
                if roll < 0.04 {
                    session.answer(nil)
                } else if roll < 0.04 + accuracy {
                    session.answer(item.correctIndex)
                } else {
                    session.answer((0..<item.choices.count)
                        .filter { $0 != item.correctIndex }
                        .randomElement(using: &rng))
                }
            }
            if let cloze = session.currentCloze {
                session.answerCloze(cloze.gaps.map { gap in
                    Double.random(in: 0..<1, using: &rng) < accuracy
                        ? gap.correctIndex
                        : (0..<gap.choices.count).filter { $0 != gap.correctIndex }.randomElement(using: &rng)
                })
            }
            let takenAt = date(today, minusDays: daysAgo, calendar).addingTimeInterval(11 * 3_600)
            PlacementAttemptStore.record(
                result: session.result(at: takenAt),
                answers: session.answers,
                cloze: session.finishedCloze
            )
        }
        // The newest check is the one in use — that's how a real device always reads.
        if let newest = PlacementAttemptStore.attempts().first {
            PlacementService.save(newest.result)
        }
    }

    // MARK: - Journey

    /// The weekly trend rows and the dated milestones that no other record dates.
    ///
    /// The final snapshot's fills are read off the *live* pyramid rather than invented, so the
    /// „Damals & heute" header can never disagree with the Lernpyramide screen next to it. Earlier
    /// weeks scale that endpoint back, staggered bottom-up: the Fundament fills across the whole
    /// span, the Spitze only in the last stretch — which is what building actually looks like.
    private static func seedJourney(
        plan: [PlannedDay], today: Date, calendar: Calendar, in context: ModelContext
    ) {
        let layers = liveLayers(in: context)
        let blueprint = PyramidService.overallFill(layers) - PyramidService.overallEarnedFill(layers)
        let studyDays = fetchAll(StudyDay.self, in: context)

        var document = JourneyDocument()
        var completionDates: [String: Date] = [:]

        for week in 0..<snapshotWeeks {
            let t = Double(week) / Double(snapshotWeeks - 1)          // 0 = oldest, 1 = today
            let takenAt = date(today, minusDays: (snapshotWeeks - 1 - week) * 7, calendar)
                .addingTimeInterval(20 * 3_600)

            var fills: [String: Double] = [:]
            for layer in layers {
                let delay = Double(layer.id.indexFromBottom) * 0.10   // the Spitze starts last
                let eased = max(0, min(1, (t - delay) / max(0.05, 1 - delay)))
                let fill = layer.earnedFill * eased
                fills[layer.id.rawValue] = fill
                if fill >= 0.999 && completionDates[layer.id.rawValue] == nil {
                    completionDates[layer.id.rawValue] = takenAt
                }
            }

            // XP, level and streak are replayed off the log rather than scaled — they're free,
            // and a trend row that disagrees with the study log is the kind of thing a reader
            // notices in a screenshot.
            let upToNow = studyDays.filter { $0.dayStart <= takenAt }
            let level = ExperienceService.level(for: upToNow)
            document.snapshots.append(ProgressSnapshot(
                takenAt: takenAt,
                earnedFill: fills,
                blueprintFill: blueprint,
                learnedA1: Int(Double(learnedA1Count) * t),
                learnedA2: Int(Double(learnedA2Count) * t),
                solidCoreGrammar: Int((3.0 * t).rounded()),
                wellHeldConversations: Int((7.0 * t).rounded()),
                streak: StudyLogService.currentStreak(upToNow, asOf: takenAt),
                level: level.level,
                totalXP: level.totalXP
            ))
        }

        for layer in layers where layer.isComplete {
            document.seenCompletedLayers.append(layer.id.rawValue)
            document.milestones.append(RecordedMilestone(
                kind: .layerComplete,
                date: completionDates[layer.id.rawValue] ?? date(today, minusDays: 30, calendar),
                title: "\(layer.id.germanTitle) vollendet",
                subtitle: "A whole layer stands — built, not outlined."
            ))
        }

        // Comeback words: dated here, and pre-marked as seen so the weekly recorder doesn't
        // announce all thirty of them again on the next Home appear.
        let comeback = fetchAll(SavedCard.self, in: context)
            .filter { $0.lapses > 0 && $0.repetitions >= PyramidService.provenRepetitions }
        document.seenComebackWords = comeback.map { $0.germanWord.lowercased() }
        for (index, card) in comeback.prefix(4).enumerated() {
            document.milestones.append(RecordedMilestone(
                kind: .comebackWord,
                date: date(today, minusDays: 120 - index * 26, calendar),
                title: "«\(card.germanWord)» zurückgeholt",
                subtitle: "Forgotten once — yours again."
            ))
        }

        document.milestones.append(RecordedMilestone(
            kind: .stillSolid,
            date: date(today, minusDays: 17, calendar),
            title: "«gefahren» sitzt noch",
            subtitle: "Still solid, 7 months after the coach let it go"
        ))

        // `probe` stays nil on purpose: the „Weißt du es noch?" card should be on screen when the
        // journey is photographed, and the throttle is what would hide it.
        ProgressSnapshotStore.save(document)
    }

    // MARK: - Badges

    /// Runs the real badge rules over the seeded device, then backdates each earned badge onto a
    /// day the fake learner actually studied — a wall of badges all earned today reads as a demo,
    /// and „Dein Weg" would stack every Abzeichen row into one month.
    private static func seedBadges(plan: [PlannedDay], in context: ModelContext) {
        let studyDays = fetchAll(StudyDay.self, in: context)
        let cards = fetchAll(SavedCard.self, in: context)
        let snapshot = AchievementSnapshot(
            streak: StudyLogService.currentStreak(studyDays),
            savedCards: cards.count,
            cardsReviewed: studyDays.reduce(0) { $0 + $1.cardsReviewed },
            conversations: studyDays.reduce(0) { $0 + $1.conversations },
            perfectMatchingRound: fetchAll(MatchingRound.self, in: context).contains(where: \.isPerfect),
            perfectArticleRound: fetchAll(ArticleRound.self, in: context).contains(where: \.isPerfect),
            perfectPrepositionRound: fetchAll(PrepositionRound.self, in: context).contains(where: \.isPerfect),
            storyQuizzes: fetchAll(StoryQuizAttempt.self, in: context).count,
            perfectStoryQuiz: fetchAll(StoryQuizAttempt.self, in: context).contains(where: \.isPerfect),
            solidGrammarSkills: solidGrammarCount(in: context),
            completedPyramidLayers: liveLayers(in: context).filter(\.isComplete).count
        )

        let earned = AchievementService.catalog.filter { $0.rule(snapshot) }.map(\.achievement.id)
        let days = plan.map(\.lastActivityAt).sorted()
        guard !days.isEmpty else { return }

        var dates: [String: Date] = [:]
        let step = max(1, days.count / (earned.count + 1))
        for (index, id) in earned.enumerated() {
            dates[id] = days[min(days.count - 1, (index + 1) * step)]
        }
        // Seeded = true, so nothing throws confetti the next time Fortschritt appears.
        AchievementService.replaceEarnedDates(dates, seeded: true)
    }

    private static func solidGrammarCount(in context: ModelContext) -> Int {
        let grammar = fetchAll(LearnerProfile.self, in: context).first?.grammar ?? [:]
        return GrammarFocus.allCases.filter { focus in
            guard let skill = grammar[focus.rawValue] else { return false }
            return skill.struggle < GrammarSkill.shakyThreshold
        }.count
    }

    /// The pyramid as the app itself would compute it right now.
    private static func liveLayers(in context: ModelContext) -> [PyramidLayerState] {
        PyramidService.layers(from: PyramidService.snapshot(
            prepositionStats: fetchAll(PrepositionStat.self, in: context),
            cards: fetchAll(SavedCard.self, in: context),
            storyAttempts: fetchAll(StoryQuizAttempt.self, in: context),
            profile: fetchAll(LearnerProfile.self, in: context).first,
            studyDays: fetchAll(StudyDay.self, in: context),
            articleStats: fetchAll(ArticleWordStat.self, in: context),
            matchingStats: fetchAll(MatchingPairStat.self, in: context),
            placement: PlacementService.current,
            conversations: fetchAll(ChatConversation.self, in: context)
        ))
    }

    // MARK: - Helpers

    private static func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private static func date(_ from: Date, minusDays days: Int, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -days, to: from) ?? from
    }
}
