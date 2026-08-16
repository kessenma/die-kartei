//
//  PyramidService.swift
//  german-ai-flashcards
//
//  Computes how built the Lernpyramide is — each layer's fill is a pure function of mastery
//  signals the app already records:
//
//    Fundament      prepositions mastered in the Kasus drill        (PrepositionStat)
//    Wortschatz A1  A1 words learned (see `isLearned`)              (SavedCard + game stats)
//    Geschichten A1 distinct A1 stories passed at ≥ 80 %            (StoryQuizAttempt)
//    Grammatik-Kern Akkusativ/Dativ/Artikel/Präpositionen Solid     (LearnerProfile.grammar)
//    Vertiefung A2  A2 words learned + A2 stories passed            (half each)
//    Spitze         conversations finished                          (StudyDay.conversations)
//
//  Nothing is stored: the pyramid is rebuilt from live data every time it appears, so it can
//  never drift from the truth.
//
//  Two channels, one pyramid. Every layer reports what the learner has **proven here** (earned)
//  separately from what the placement estimate says they **already knew** (provisional). Without
//  that split the pyramid measures time-in-app rather than German: a B2 speaker who knows all 585
//  A1 words would still need three weeks of spacing before the layer moved. Earned draws solid,
//  provisional draws ghost, and only earned counts as complete.
//

import Foundation

// MARK: - Snapshot

/// The gathered inputs, one fetch per kind. Kept separate from the fill math so the rules stay
/// pure and testable.
///
/// Each countable comes in pairs: the `…` count is proven in-app, the `estimated…` count is what
/// placement credits on top and is always net of what's already proven (so the two can be summed
/// without double-counting an item). Stories and conversations have no estimate — no quiz can
/// stand in for having read and spoken.
struct PyramidSnapshot {
    // Fundament
    var masteredPrepositions: Int = 0
    var estimatedPrepositions: Int = 0
    var corePrepositions: Int = 1
    // Wortschatz A1
    var learnedA1Words: Int = 0
    var estimatedA1Words: Int = 0
    var a1WordGoal: Int = 1
    // Geschichten A1 — earned only
    var a1StoriesPassed: Int = 0
    // Grammatik-Kern. The estimate is fractional on purpose: crediting whole structures would need
    // a "counts as solid" cutoff, and there's no measurement to justify one — partial credit for
    // partial evidence is the honest reading.
    var solidCoreGrammar: Int = 0
    var estimatedCoreGrammar: Double = 0
    var coreGrammarCount: Int = 4
    // Vertiefung A2
    var learnedA2Words: Int = 0
    var estimatedA2Words: Int = 0
    var a2WordGoal: Int = 200
    var a2StoriesPassed: Int = 0
    // Spitze — earned only. Counts conversations *held well*, not conversations started.
    var conversations: Int = 0
    var conversationGoal: Int = 20
    /// True once there is conversation history to judge. Before that the layer falls back to the
    /// plain count, so a learner mid-way through the old rule doesn't watch their peak empty out.
    var hasConversationQuality: Bool = false
}

// MARK: - Service

enum PyramidService {

    /// A story quiz at or above this score counts the story as "understood".
    static let storyPassScore = 80
    /// Stories per level the pyramid asks for.
    static let storyGoalPerLevel = 3
    /// A2 words matured toward the Vertiefung layer (the A2 list is ~1 200 — the goal is a
    /// working core, not the dictionary).
    static let a2WordGoal = 200
    /// Finished conversations that crown the Spitze.
    static let conversationGoal = 20
    /// The grammar structures the Kern layer is built from.
    static let coreGrammar: [GrammarFocus] = [.akkusativ, .dativ, .artikel, .praepositionen]
    /// Anki's classic maturity bar — three weeks of spacing means a word survived real forgetting.
    static let matureIntervalDays = 21
    /// The fast path to the same conclusion: consecutive correct reviews. `SavedCard.repetitions`
    /// resets on a lapse, so this already means "right three times running, right now" — no extra
    /// `lapses == 0` test, which would wrongly exclude a word forgotten once and then relearned.
    static let provenRepetitions = 3

    // MARK: Gather

    static func snapshot(
        prepositionStats: [PrepositionStat],
        cards: [SavedCard],
        storyAttempts: [StoryQuizAttempt],
        profile: LearnerProfile?,
        studyDays: [StudyDay],
        articleStats: [ArticleWordStat] = [],
        matchingStats: [MatchingPairStat] = [],
        placement: PlacementResult? = nil,
        conversations: [ChatConversation] = []
    ) -> PyramidSnapshot {
        var s = PyramidSnapshot()

        // Fundament — mastered = re-proven after trouble, or clean from the start.
        let core = PrepositionService.prepositions(includeAdvanced: false)
        s.corePrepositions = max(1, core.count)
        let coreKeys = Set(core.map { PrepositionService.key(for: $0.word) })
        s.masteredPrepositions = prepositionStats
            .filter { coreKeys.contains($0.key) }
            .filter { $0.firstTryStreak >= PrepositionService.graduationStreak
                      || ($0.timesSeen >= 3 && $0.timesMissed == 0) }
            .count

        // Wortschatz — every word the learner has actually proven, matched against the Goethe list
        // on the bare lowercased word (the card's article lives in its own field).
        let learned = learnedWords(cards: cards, articleStats: articleStats, matchingStats: matchingStats)
        let a1Set = Set(GoetheVocabService.entries(for: .a1).map { $0.word.lowercased() })
        let a2Set = Set(GoetheVocabService.entries(for: .a2).map { $0.word.lowercased() })
        s.a1WordGoal = max(1, a1Set.count)
        s.learnedA1Words = learned.intersection(a1Set).count
        s.a2WordGoal = a2WordGoal
        s.learnedA2Words = learned.intersection(a2Set).count

        // Geschichten — distinct stories passed (best attempt ≥ pass score), per level.
        s.a1StoriesPassed = passedStories(storyAttempts, level: .a1)
        s.a2StoriesPassed = passedStories(storyAttempts, level: .a2)

        // Grammatik-Kern — a structure counts once it exists in the profile and sits below the
        // shaky threshold (the same cutoff Coach's Notes uses).
        let grammar = profile?.grammar ?? [:]
        s.coreGrammarCount = coreGrammar.count
        s.solidCoreGrammar = coreGrammar.filter { focus in
            guard let skill = grammar[focus.rawValue] else { return false }
            return skill.struggle < GrammarSkill.shakyThreshold
        }.count

        // Spitze — production, and the one layer no quiz can shortcut. Counting finished chats
        // rewarded showing up: twenty abandoned two-turn sessions would crown the pyramid. When
        // there are summaries to read, the peak asks instead for conversations actually held well.
        let judged = conversations.filter { ConversationQualityService.density($0) != nil }
        if judged.isEmpty {
            s.conversations = studyDays.reduce(0) { $0 + $1.conversations }
            s.conversationGoal = conversationGoal
            s.hasConversationQuality = false
        } else {
            s.conversations = ConversationQualityService.wellHeldCount(judged)
            s.conversationGoal = ConversationQualityService.qualityGoal
            s.hasConversationQuality = true
        }

        // ── Provisional credit ────────────────────────────────────────────────────────────────
        // Everything above is proof. Everything below is the placement estimate, and it is always
        // net of what's already proven and of what the app has since seen the learner get wrong.
        guard let placement, !placement.declaredBeginner else { return s }

        let refuted = refutedWords(
            cards: cards,
            articleStats: articleStats,
            matchingStats: matchingStats,
            learned: learned
        )

        s.estimatedA1Words = provisional(
            fraction: placement.vocabKnown(.a1),
            goal: s.a1WordGoal,
            earned: s.learnedA1Words,
            refuted: refuted.intersection(a1Set).count
        )
        s.estimatedA2Words = provisional(
            fraction: placement.vocabKnown(.a2),
            goal: s.a2WordGoal,
            earned: s.learnedA2Words,
            refuted: refuted.intersection(a2Set).count
        )

        // Fundament — the probe's case block *is* preposition knowledge, so it credits directly.
        let prepositionKnown = PlacementService.knowledge(
            fromAccuracy: placement.prepositionAccuracy,
            items: PlacementService.prepositionItems,
            choices: PrepositionCase.allCases.count
        )
        let refutedPrepositions = prepositionStats
            .filter { coreKeys.contains($0.key) && $0.timesMissed > 0 }
            .filter { $0.firstTryStreak < PrepositionService.graduationStreak }
            .count
        s.estimatedPrepositions = provisional(
            fraction: prepositionKnown,
            goal: s.corePrepositions,
            earned: s.masteredPrepositions,
            refuted: refutedPrepositions
        )

        // Grammatik-Kern — credited per structure, and only where the profile has nothing to say.
        // A structure the coach has actually measured is settled: measured beats estimated, in
        // both directions, so a learner who drills badly can't hide behind a good quiz.
        let articleKnown = PlacementService.knowledge(
            fromAccuracy: placement.articleAccuracy,
            items: PlacementService.genderItems,
            choices: PlacementService.genderChoiceCount
        )
        s.estimatedCoreGrammar = coreGrammar.reduce(0.0) { total, focus in
            guard grammar[focus.rawValue] == nil else { return total }
            switch focus {
            case .artikel:                          return total + articleKnown
            // Naming the case a preposition governs is exactly Akkusativ/Dativ knowledge.
            case .praepositionen, .akkusativ, .dativ: return total + prepositionKnown
            default:                                return total
            }
        }

        return s
    }

    /// Placement credit for one content set, net of proof and of contradiction.
    ///
    /// Subtracting `earned` is what stops an item being counted in both channels; subtracting
    /// `refuted` is what makes the estimate shrink as the app learns better. The estimate never
    /// grows on its own — only a retake can raise it.
    private static func provisional(fraction: Double, goal: Int, earned: Int, refuted: Int) -> Int {
        guard fraction > 0, goal > 0 else { return 0 }
        let target = Int((fraction * Double(goal)).rounded())
        return max(0, target - earned - refuted)
    }

    /// Words the app has watched the learner get wrong and not yet re-prove. These are subtracted
    /// from placement credit, so an estimate decays against evidence instead of standing forever.
    static func refutedWords(
        cards: [SavedCard],
        articleStats: [ArticleWordStat],
        matchingStats: [MatchingPairStat],
        learned: Set<String>
    ) -> Set<String> {
        var refuted = Set<String>()
        for card in cards where card.lapses > 0 {
            refuted.insert(card.germanWord.lowercased())
        }
        for stat in articleStats where stat.timesMissed > 0 {
            refuted.insert(stat.noun.lowercased())
        }
        for stat in matchingStats where stat.timesMissed > 0 {
            refuted.insert(stat.german.lowercased())
        }
        // A word that has since been re-proven isn't evidence against anything.
        return refuted.subtracting(learned)
    }

    /// Every word the learner has demonstrably learned, lowercased and bare.
    ///
    /// Three independent proofs, because SRS maturity alone measures *how long you've been here*
    /// rather than *what you know*: a returning learner who already knows a word would otherwise
    /// wait three weeks for the pyramid to admit it. Any one of these is enough:
    ///   - the card survived real spacing (`interval ≥ 21d`),
    ///   - it's been answered right three times running (`repetitions`, which resets on a lapse),
    ///   - or a game graduated it — the same `firstTryStreak` bar the article and matching games
    ///     already use to retire a word from their tricky lists.
    static func learnedWords(
        cards: [SavedCard],
        articleStats: [ArticleWordStat],
        matchingStats: [MatchingPairStat]
    ) -> Set<String> {
        var learned = Set<String>()
        for card in cards where card.interval >= matureIntervalDays || card.repetitions >= provenRepetitions {
            learned.insert(card.germanWord.lowercased())
        }
        for stat in articleStats where stat.firstTryStreak >= ArticleGameService.graduationStreak {
            learned.insert(stat.noun.lowercased())
        }
        for stat in matchingStats where stat.firstTryStreak >= MatchingStatsService.graduationStreak {
            learned.insert(stat.german.lowercased())
        }
        return learned
    }

    private static func passedStories(_ attempts: [StoryQuizAttempt], level: CEFRLevel) -> Int {
        var passed: Set<UUID> = []
        for attempt in attempts where attempt.level == level && attempt.scorePercentage >= storyPassScore {
            passed.insert(attempt.storyID)
        }
        return passed.count
    }

    // MARK: Fills

    static func layers(from s: PyramidSnapshot) -> [PyramidLayerState] {
        // Detail lines are English-primary: the numbers are what matter, and a beginner can't
        // parse "gefestigt" yet. The German lives in the layer titles.
        [
            PyramidLayerState(
                id: .fundament,
                earnedFill: ratio(s.masteredPrepositions, s.corePrepositions),
                provisionalFill: ratio(s.estimatedPrepositions, s.corePrepositions),
                detail: estimated(
                    "\(s.masteredPrepositions) of \(s.corePrepositions) prepositions mastered",
                    s.estimatedPrepositions
                )
            ),
            PyramidLayerState(
                id: .wortschatzA1,
                earnedFill: ratio(s.learnedA1Words, s.a1WordGoal),
                provisionalFill: ratio(s.estimatedA1Words, s.a1WordGoal),
                detail: estimated(
                    "\(s.learnedA1Words) of \(s.a1WordGoal) A1 words learned",
                    s.estimatedA1Words
                )
            ),
            PyramidLayerState(
                id: .geschichtenA1,
                earnedFill: ratio(s.a1StoriesPassed, storyGoalPerLevel),
                detail: "\(min(s.a1StoriesPassed, storyGoalPerLevel)) of \(storyGoalPerLevel) A1 stories understood"
            ),
            PyramidLayerState(
                id: .grammatikKern,
                earnedFill: ratio(s.solidCoreGrammar, s.coreGrammarCount),
                provisionalFill: ratio(s.estimatedCoreGrammar, s.coreGrammarCount),
                detail: estimated(
                    "\(s.solidCoreGrammar) of \(s.coreGrammarCount) core structures solid",
                    Int(s.estimatedCoreGrammar.rounded())
                )
            ),
            // The only compound layer: words and stories, half each. Stories carry no estimate,
            // so the provisional channel is the vocabulary half alone.
            PyramidLayerState(
                id: .vertiefungA2,
                earnedFill: (ratio(s.learnedA2Words, s.a2WordGoal)
                             + ratio(s.a2StoriesPassed, storyGoalPerLevel)) / 2,
                provisionalFill: ratio(s.estimatedA2Words, s.a2WordGoal) / 2,
                detail: estimated(
                    "\(s.learnedA2Words) A2 words · \(min(s.a2StoriesPassed, storyGoalPerLevel)) of \(storyGoalPerLevel) A2 stories",
                    s.estimatedA2Words
                )
            ),
            PyramidLayerState(
                id: .spitze,
                earnedFill: ratio(s.conversations, s.conversationGoal),
                detail: s.hasConversationQuality
                    ? "\(min(s.conversations, s.conversationGoal)) of \(s.conversationGoal) conversations held well"
                    : "\(min(s.conversations, s.conversationGoal)) of \(s.conversationGoal) conversations held"
            ),
        ]
    }

    /// Appends the estimated count to a detail line, so a ghost-filled layer says where its fill
    /// came from rather than looking like unexplained progress.
    private static func estimated(_ base: String, _ count: Int) -> String {
        count > 0 ? "\(base) · \(count) estimated" : base
    }

    /// Whole-pyramid completion including the placement estimate — the number the teasers show.
    static func overallFill(_ layers: [PyramidLayerState]) -> Double {
        guard !layers.isEmpty else { return 0 }
        return layers.reduce(0) { $0 + $1.fill } / Double(layers.count)
    }

    /// The proven half of the same number. Anything that gates a reward reads this, never
    /// `overallFill` — an estimate is a starting point, not an achievement.
    static func overallEarnedFill(_ layers: [PyramidLayerState]) -> Double {
        guard !layers.isEmpty else { return 0 }
        return layers.reduce(0) { $0 + $1.earnedFill } / Double(layers.count)
    }

    private static func ratio(_ n: Int, _ of: Int) -> Double {
        ratio(Double(n), of)
    }

    private static func ratio(_ n: Double, _ of: Int) -> Double {
        guard of > 0 else { return 0 }
        return min(1, max(0, n / Double(of)))
    }
}
