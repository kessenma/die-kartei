import Foundation

// The one definition of every synced kind: its merge rules and how its record name is derived.
// The iOS codecs (`Services/Sync/Codecs`) read their `spec` from here, and so does the Android
// record store, so a record written on either platform merges the same way on the other.
// Change a rule here and both apps change with it. The rules themselves are explained next to
// each codec and in docs/ICLOUD_SYNC.md ▸ Merge rules.

// MARK: - Canonical ids

/// Decks whose id both devices derive from (generatorRaw, topic) rather than make up at random:
/// the Wortschatz deck and the per-topic stats and SRS decks, which each device fetch-or-creates.
nonisolated enum SyncSingletonDecks {
    /// `VerbPrepositionService.deckGenerator` is "verb-prep-srs"; an iOS test checks they agree.
    static let generators: Set<String> = ["goethe", "goethe-srs", "past-tense", "past-tense-srs", "grammar",
                                          "verb-prep-srs"]

    /// The one Wortschatz deck (every Goethe word, A1–B1): `DeckStore.wortschatzTopic` on iOS.
    static let wortschatzGenerator = "goethe-srs"
    static let wortschatzTopic = "Goethe Vocabulary"
    static var wortschatzDeckID: UUID { deckID(generatorRaw: wortschatzGenerator, topic: wortschatzTopic) }

    static func isSingleton(generatorRaw: String) -> Bool { generators.contains(generatorRaw) }

    /// Canonical deck id: the same on every device for the same generator and topic.
    static func deckID(generatorRaw: String, topic: String) -> UUID {
        SyncNameUUID.make("deck", generatorRaw, topic)
    }

    /// The id for a story's, job posting's or course's own deck when it has to be created here.
    /// If the parent already links a deck that simply hasn't arrived from the other device yet,
    /// reuse that id so the two become one record when it lands. Otherwise derive it from the
    /// parent, so two devices creating it offline create the same deck.
    static func linkedDeckID(existing: UUID?, kind: String, parentID: UUID) -> UUID {
        existing ?? SyncNameUUID.make("linked-deck", kind, parentID.uuidString)
    }

    /// Canonical card id inside a singleton deck: one card per German word.
    /// The exact word, never lowercased: the Goethe lists hold 34 pairs that differ only by
    /// case (sie/Sie, essen/Essen), and each is its own card.
    static func cardID(deckID: UUID, germanWord: String) -> UUID {
        SyncNameUUID.make("card", deckID.uuidString, germanWord)
    }
}

/// The calendar date a `StudyDay` belongs to, as `yyyy-MM-dd`.
///
/// `dayStart` is an absolute instant: local midnight wherever the row was written. Formatting it
/// directly would put a Berlin row on the previous date when read in New York. Formatting
/// `dayStart + 12 h` lands mid-day, which reads as the same date in any time zone less than 12 hours
/// away.
nonisolated enum SyncDayKey {
    static func key(for dayStart: Date, calendar: Calendar = .current) -> String {
        formatter(calendar).string(from: dayStart.addingTimeInterval(12 * 3600))
    }

    /// Local midnight of the date a key names, in this device's calendar.
    static func dayStart(for key: String, calendar: Calendar = .current) -> Date? {
        guard let noon = formatter(calendar).date(from: key)?.addingTimeInterval(12 * 3600) else { return nil }
        return calendar.startOfDay(for: noon)
    }

    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}

/// Natural keys for rows that have no id of their own.
nonisolated enum SyncNaturalKeys {
    /// A round row has no id, so its record is named after its content. Rounds are never edited,
    /// and two rounds can't finish at the same instant on the same topic.
    static func roundKey(date: Date, topic: String, counts: [Int]) -> String {
        (["\(date.timeIntervalSinceReferenceDate)", topic] + counts.map { String($0) }).joined(separator: "|")
    }

    /// A Kasus round: its own `roundKey`, or, for rows from before it existed, its content.
    static func kasusRoundKey(roundKey: String, date: Date, storyID: String, unitRaw: String, stepRaw: String) -> String {
        roundKey.isEmpty
            ? "\(date.timeIntervalSinceReferenceDate)|\(storyID)|\(unitRaw)|\(stepRaw)"
            : roundKey
    }
}

// MARK: - Merge rules

/// Every synced SwiftData kind's `SyncKindSpec`. `all` lists them in `SyncRegistry` order
/// (parents before children); an iOS test checks the registry against it.
nonisolated enum SyncKinds {

    // Decks, cards and quiz results.

    static let savedDeck = SyncKindSpec(kind: "SavedDeck")

    /// A card's SRS schedule travels as one group, taken whole from the later review.
    static let cardScheduleFields = [
        "easeFactor", "interval", "repetitions", "nextReviewDate", "leitnerBox",
        "lastReviewedAt", "lastReviewWasCorrect",
    ]

    static let savedCard = SyncKindSpec(
        kind: "SavedCard",
        rules: [
            "totalReviews": .counter,
            "lapses": .counter,
            "firstReviewedAt": .min,
        ],
        groups: [
            SyncFieldGroup(fields: cardScheduleFields,
                           orderBy: ["lastReviewedAt", "repetitions", "interval", "easeFactor"])
        ]
    )

    static let quizResult = SyncKindSpec(kind: "QuizResult")

    // Study log and per-word stats.

    static let studyDayCounterFields = [
        "cardsReviewed", "grammarExercises", "conversations", "storySeconds", "storyQuestions",
        "cardSeconds", "grammarSeconds", "conversationSeconds", "storyQuizSeconds",
        "newWordsIntroduced", "newWordsBonus",
        "gameSeconds", "gameWordsSolved",
        "wordsDrawn", "drawingSeconds",
        "wordsWritten", "writingSeconds",
        "sheetWordsWritten",
        "hoerenItems", "hoerenSeconds",
    ]

    static let studyDay: SyncKindSpec = {
        var rules = Dictionary(uniqueKeysWithValues: studyDayCounterFields.map { ($0, SyncFieldRule.counter) })
        rules["lastActivityAt"] = .max
        return SyncKindSpec(kind: "StudyDay", rules: rules)
    }()

    /// A per-word game stat row (matching pairs, der/die/das nouns, prepositions). Seen and missed
    /// are per-device counters and the wrong-pick tally is one counter per wrong answer, so play on
    /// two devices adds up. The first-try streak and `lastSeenAt` are taken together from the
    /// device that saw the word last: a streak is an unbroken run of rounds, and two devices' runs
    /// can't be added. `lastSeenAt` sits in the group, as `lastReviewedAt` does in a card's
    /// schedule: a miss that leaves the streak at 0 doesn't change it, and a streak-only group
    /// would then take the other device's older streak. `lastSeenAt` still comes out as the later
    /// time. `lastMissedAt` takes the later time.
    static func gameStat(kind: String, tally: String) -> SyncKindSpec {
        SyncKindSpec(
            kind: kind,
            rules: [
                "timesSeen": .counter,
                "timesMissed": .counter,
                tally: .counterMap,
                "lastMissedAt": .max,
            ],
            groups: [SyncFieldGroup(fields: ["firstTryStreak", "lastSeenAt"], orderBy: ["lastSeenAt"])]
        )
    }

    static let matchingPairStat = gameStat(kind: "MatchingPairStat", tally: "confusions")
    static let matchingRound = SyncKindSpec(kind: "MatchingRound")
    static let articleWordStat = gameStat(kind: "ArticleWordStat", tally: "wrongPicks")
    static let articleRound = SyncKindSpec(kind: "ArticleRound")
    static let prepositionStat = gameStat(kind: "PrepositionStat", tally: "wrongPicks")
    static let prepositionRound = SyncKindSpec(kind: "PrepositionRound")

    // Grammatik path.

    static let generatedKasusStory = SyncKindSpec(kind: "GeneratedKasusStory")
    static let kasusRound = SyncKindSpec(kind: "KasusRound", rules: ["revealedAnswers": .or])

    // Coaching memory.

    /// The fixed record name of the learner profile on every device.
    static let learnerProfileName = SyncRecordName(kind: "LearnerProfile", id: SyncNameUUID.make("learner-profile"))

    static let learnerProfile = SyncKindSpec(
        kind: "LearnerProfile",
        rules: [
            "sessionCount": .counter,
            "lastSessionAt": .max,
            "grammar": .keyed(item: .lwwBy("lastSeen")),
            "vocab": .set(idField: "german", lowercasedID: true, item: .lwwBy("lastSeen"), sortBy: "lastSeen"),
            "slips": .set(idField: "id", item: .lwwBy("lastSeen"), sortBy: "lastSeen"),
            // What the learner said they find hard (the journal hand-off). Matched on the
            // computed `SelfReportNote.id`, written in like a slip's. A payload from a build
            // without the field merges as an empty set, so the notes on the other side survive.
            "selfReports": .set(idField: "id", item: .lwwBy("notedAt"), sortBy: "notedAt"),
        ],
        normalize: SyncKinds.normalizeLearnerProfile
    )

    /// No sessions left after the merge means no last session: a reset on either device wins over
    /// the other device's older date. Deterministic, so both devices normalize to the same bytes.
    static func normalizeLearnerProfile(_ payload: SyncPayload) -> SyncPayload {
        guard payload["lastSessionAt"] != nil, SyncCounter(json: payload["sessionCount"]).value <= 0 else {
            return payload
        }
        var out = payload
        out["lastSessionAt"] = nil
        return out
    }

    static let archivedMemoryItem = SyncKindSpec(kind: "ArchivedMemoryItem", rules: ["archivedAt": .min])

    // Stories and papers.

    static let studyStory = SyncKindSpec(
        kind: "StudyStory",
        rules: [
            "bestScore": .max,
            "generationComplete": .or,
            "lookups": .set(idField: "german", lowercasedID: true),
        ]
    )
    static let storyReadingSession = SyncKindSpec(kind: "StoryReadingSession")
    static let storyQuizAttempt = SyncKindSpec(kind: "StoryQuizAttempt")
    static let studyPaper = SyncKindSpec(kind: "StudyPaper", rules: ["generationComplete": .or])

    // Conversations, job postings, phrases.

    static let chatConversation = SyncKindSpec(
        kind: "ChatConversation",
        rules: [
            "durationSeconds": .counter,
            "updatedAt": .max,
            "savedVocab": .set(idField: "german", lowercasedID: true),
        ]
    )

    static let chatMessage = SyncKindSpec(
        kind: "ChatMessage",
        rules: [
            "selfCorrected": .or,
            "usedHint": .or,
            "usedPhraseHelper": .or,
            "confirmedClean": .or,
            "translationViewed": .or,
        ]
    )

    static let jobPosting = SyncKindSpec(
        kind: "JobPosting",
        rules: [
            "readingSeconds": .counter,
            "updatedAt": .max,
            "lastOpenedAt": .max,
            "lookups": .set(idField: "german", lowercasedID: true),
        ]
    )

    static let learnedPhrase = SyncKindSpec(
        kind: "LearnedPhrase",
        rules: ["lastSurfacedAt": .max, "surfacedCount": .max]
    )

    // Deutschkurs.

    static let classCourse = SyncKindSpec(kind: "ClassCourse", rules: [
        "updatedAt": .max,
        "questions": .keyed(item: .lwwBy("at")),
    ])

    static let classEntry = SyncKindSpec(
        kind: "ClassEntry",
        rules: [
            "updatedAt": .max,
            "words": .set(idField: "id"),
            "teacherCorrections": .set(idField: "id"),
        ]
    )

    static let classMaterial = SyncKindSpec(
        kind: "ClassMaterial",
        rules: [
            "lookups": .set(idField: "german", lowercasedID: true),
            "worksheetAnswers": .keyed(item: .lwwBy("at")),
        ],
        groups: [SyncFieldGroup(fields: ["translation", "translationModelRaw"], orderBy: [])]
    )

    // Zeichnen.

    static let wordArtwork = SyncKindSpec(kind: "WordArtwork")

    static let wordDrawingCounterFields = ["quickCount", "studioCount", "paintedCount", "recallRight", "recallMissed"]

    static let wordDrawingStat: SyncKindSpec = {
        var rules = Dictionary(uniqueKeysWithValues: wordDrawingCounterFields.map { ($0, SyncFieldRule.counter) })
        rules["lastQuickAt"] = .max
        rules["lastStudioAt"] = .max
        rules["lastPaintedAt"] = .max
        return SyncKindSpec(kind: "WordDrawingStat", rules: rules)
    }()

    static let quickDrawSet = SyncKindSpec(kind: "QuickDrawSet")

    // Writing and listening.

    static let journalEntry = SyncKindSpec(
        kind: "JournalEntry",
        rules: [
            "updatedAt": .max,
            "sharedWithCoachAt": .max,
            "creditedWords": .max,
            "lookups": .set(idField: "german", lowercasedID: true, item: .lwwBy("at")),
        ],
        groups: [SyncFieldGroup(fields: ["check", "checkedAt", "checkedModelID", "checkedTextHash"], orderBy: [])]
    )

    static let hoerenRound = SyncKindSpec(kind: "HoerenRound")

    /// In `SyncRegistry` order: parents before children.
    static let all: [SyncKindSpec] = [
        savedDeck, savedCard, quizResult,
        studyDay, matchingPairStat, matchingRound, articleWordStat, articleRound, prepositionStat, prepositionRound,
        generatedKasusStory, kasusRound,
        learnerProfile, archivedMemoryItem,
        studyStory, storyReadingSession, storyQuizAttempt, studyPaper,
        chatConversation, chatMessage, jobPosting, learnedPhrase,
        classCourse, classEntry, classMaterial,
        wordArtwork, wordDrawingStat, quickDrawSet,
        journalEntry, hoerenRound,
    ]

    static let byKind: [String: SyncKindSpec] = Dictionary(uniqueKeysWithValues: all.map { ($0.kind, $0) })

    /// The kinds that hang off a parent record, and the payload field naming it. A delete of the
    /// parent cascades to them (the SwiftData relationships with `.cascade`).
    static let parentField: [String: (field: String, parentKind: String)] = [
        "SavedCard": ("deck", "SavedDeck"),
        "QuizResult": ("deck", "SavedDeck"),
        "ChatMessage": ("conversation", "ChatConversation"),
        "ClassEntry": ("course", "ClassCourse"),
        "ClassMaterial": ("entry", "ClassEntry"),
    ]
}
