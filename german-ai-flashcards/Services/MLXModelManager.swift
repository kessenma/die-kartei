import Foundation

@Observable
class MLXModelManager {
    /// The active model provider.
    var activeProvider: ModelProvider {
        didSet {
            UserDefaults.standard.set(activeProvider.rawValue, forKey: "activeModelProvider")
        }
    }

    /// The currently selected MLX model.
    var selectedMLXModel: MLXModel {
        didSet {
            UserDefaults.standard.set(selectedMLXModel.rawValue, forKey: "selectedMLXModel")
        }
    }

    /// The preferred flashcard review style.
    var flashcardStyle: FlashcardStyle {
        didSet {
            UserDefaults.standard.set(flashcardStyle.rawValue, forKey: "flashcardStyle")
        }
    }

    /// Whether a newly created deck starts drawing AI pictures for its cards in the background.
    /// Off by default — pictures need a separate model download and real generation time. Lives
    /// here rather than in `@AppStorage` because two views share it (deck setup and Card Settings).
    var flashcardIllustrationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(flashcardIllustrationsEnabled, forKey: "flashcardIllustrationsEnabled")
        }
    }

    /// The identifier of the preferred German TTS voice (nil = system default de-DE).
    var selectedVoiceIdentifier: String? {
        didSet {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "selectedVoiceIdentifier")
        }
    }

    /// Per-role German voices used to give each speaker of a dialogue/e-mail story its own voice
    /// in listening mode. Each nil = fall back to `selectedVoiceIdentifier`, then the system de-DE.
    var voiceMaleIdentifier: String? {
        didSet { UserDefaults.standard.set(voiceMaleIdentifier, forKey: "voiceMaleIdentifier") }
    }
    var voiceFemaleIdentifier: String? {
        didSet { UserDefaults.standard.set(voiceFemaleIdentifier, forKey: "voiceFemaleIdentifier") }
    }
    var voiceBoyIdentifier: String? {
        didSet { UserDefaults.standard.set(voiceBoyIdentifier, forKey: "voiceBoyIdentifier") }
    }
    var voiceGirlIdentifier: String? {
        didSet { UserDefaults.standard.set(voiceGirlIdentifier, forKey: "voiceGirlIdentifier") }
    }

    /// The downloaded voice a speaker role maps to, falling back to the single selected voice.
    func voiceIdentifier(for role: StorySpeaker.Role) -> String? {
        let roleVoice: String?
        switch role {
        case .male:   roleVoice = voiceMaleIdentifier
        case .female: roleVoice = voiceFemaleIdentifier
        case .boy:    roleVoice = voiceBoyIdentifier
        case .girl:   roleVoice = voiceGirlIdentifier
        }
        return roleVoice ?? selectedVoiceIdentifier
    }

    /// When true, selecting a rating automatically advances to the next card (no Next button needed).
    var autoAdvance: Bool {
        didSet {
            UserDefaults.standard.set(autoAdvance, forKey: "autoAdvance")
        }
    }

    /// The most recently successfully loaded model — persists across app launches so the app can offer a quick resume.
    var lastLoadedModel: MLXModel? {
        didSet {
            if let model = lastLoadedModel {
                UserDefaults.standard.set(model.rawValue, forKey: "lastLoadedModel")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastLoadedModel")
            }
        }
    }

    // MARK: - Card Matching Settings

    /// Pairs per matching round (the board size). Clamped to the picker's 6/8/10/12 choices.
    var matchingPairCount: Int {
        didSet { UserDefaults.standard.set(matchingPairCount, forKey: "matchingPairCount") }
    }
    /// When on, rounds draw up to half their pairs from words the learner keeps missing,
    /// so recurring mistakes come back around until they're re-proven.
    var matchingTrickyFirst: Bool {
        didSet { UserDefaults.standard.set(matchingTrickyFirst, forKey: "matchingTrickyFirst") }
    }
    /// When on, repeatedly-missed matching words flow into the learner profile, so the
    /// conversation coach works them in and they're drillable from Coach's Notes.
    var matchingFeedsCoach: Bool {
        didSet { UserDefaults.standard.set(matchingFeedsCoach, forKey: "matchingFeedsCoach") }
    }
    /// Same hand-off for the der/die/das game: nouns whose article keeps being missed
    /// flow into the learner profile as words being built.
    var articleFeedsCoach: Bool {
        didSet { UserDefaults.standard.set(articleFeedsCoach, forKey: "articleFeedsCoach") }
    }
    /// Same hand-off for the preposition Kasus drill: prepositions whose case keeps being
    /// missed flow into the learner profile as words being built.
    var prepositionsFeedCoach: Bool {
        didSet { UserDefaults.standard.set(prepositionsFeedCoach, forKey: "prepositionsFeedCoach") }
    }
    /// How much of the preposition 3D scene is shown, and when. See `PrepositionPictureMode` —
    /// `teaching` is the one mode whose answers are discounted for mastery.
    var prepositionPictureMode: PrepositionPictureMode {
        didSet {
            UserDefaults.standard.set(prepositionPictureMode.rawValue,
                                      forKey: PrepositionPictureMode.defaultsKey)
        }
    }
    /// How much the games vibrate (matching + der/die/das): all feedback, mistakes only, or off.
    var hapticFeedbackMode: HapticFeedbackMode {
        didSet { UserDefaults.standard.set(hapticFeedbackMode.rawValue, forKey: "hapticFeedbackMode") }
    }

    // MARK: - Conversation (Voice Chat) Settings

    /// The model used for the AI conversation feature (independent of card generation).
    var selectedChatModel: MLXModel {
        didSet {
            UserDefaults.standard.set(selectedChatModel.rawValue, forKey: "selectedChatModel")
        }
    }

    /// Whether the AI's spoken replies auto-play when they arrive.
    var autoPlayReplies: Bool {
        didSet {
            UserDefaults.standard.set(autoPlayReplies, forKey: "autoPlayReplies")
        }
    }

    /// Remembered conversation-setup defaults (so a new chat reuses the last choices).
    var chatLevelRaw: String {
        didSet { UserDefaults.standard.set(chatLevelRaw, forKey: "chatLevelRaw") }
    }
    var chatFormalityRaw: String {
        didSet { UserDefaults.standard.set(chatFormalityRaw, forKey: "chatFormalityRaw") }
    }
    var chatStrictnessRaw: String {
        didSet { UserDefaults.standard.set(chatStrictnessRaw, forKey: "chatStrictnessRaw") }
    }
    /// Raw `FeedbackStyle` — whether corrections are handed over ("Tell me") or elicited via a
    /// question first ("Nudge me"). New conversations start from this default.
    var chatFeedbackStyleRaw: String {
        didSet { UserDefaults.standard.set(chatFeedbackStyleRaw, forKey: "chatFeedbackStyleRaw") }
    }
    var chatCorrectionsEnabled: Bool {
        didSet { UserDefaults.standard.set(chatCorrectionsEnabled, forKey: "chatCorrectionsEnabled") }
    }
    /// When a correction is shown, also surface the English meaning of the corrected sentence.
    var chatShowCorrectionTranslation: Bool {
        didSet { UserDefaults.standard.set(chatShowCorrectionTranslation, forKey: "chatShowCorrectionTranslation") }
    }
    /// Pre-compute translations & hints in the background (learning aid; uses more compute/battery).
    var chatEagerAssist: Bool {
        didSet { UserDefaults.standard.set(chatEagerAssist, forKey: "chatEagerAssist") }
    }
    /// When eager assist is on, auto-show the translation (vs. just pre-load it for instant reveal).
    var chatAutoShowTranslation: Bool {
        didSet { UserDefaults.standard.set(chatAutoShowTranslation, forKey: "chatAutoShowTranslation") }
    }
    /// Number of hint suggestions to generate (1–3).
    var chatHintCount: Int {
        didSet { UserDefaults.standard.set(chatHintCount, forKey: "chatHintCount") }
    }
    /// When on, the coach keeps a persistent on-device learner profile and uses it to
    /// personalize each session (steer toward weak spots, reuse the learner's words, sharpen
    /// corrections). See `LearnerMemoryService`.
    var chatPersonalizedCoaching: Bool {
        didSet { UserDefaults.standard.set(chatPersonalizedCoaching, forKey: "chatPersonalizedCoaching") }
    }
    /// When on, conversations resurface SRS-due flashcards ("spaced re-encounter") and advance a
    /// card's real review schedule when the learner uses the word correctly. See `ConversationReviewTracker`.
    var chatSpacedReview: Bool {
        didSet { UserDefaults.standard.set(chatSpacedReview, forKey: "chatSpacedReview") }
    }
    /// Which conversations spaced review applies to (raw `SpacedReviewScope`).
    var chatSpacedReviewScopeRaw: String {
        didSet { UserDefaults.standard.set(chatSpacedReviewScopeRaw, forKey: "chatSpacedReviewScopeRaw") }
    }
    /// Typed accessor for the spaced-review scope.
    var spacedReviewScope: SpacedReviewScope {
        get { SpacedReviewScope(rawValue: chatSpacedReviewScopeRaw) ?? .everywhere }
        set { chatSpacedReviewScopeRaw = newValue.rawValue }
    }
    /// The model used to generate study materials from papers/links (and to discuss them).
    var selectedPaperModel: MLXModel {
        didSet { UserDefaults.standard.set(selectedPaperModel.rawValue, forKey: "selectedPaperModel") }
    }

    // MARK: - Short Stories Settings

    /// Remembered story-setup defaults. The level starts from the conversation level and then
    /// tracks the learner's own story choice.
    var storyLevelRaw: String {
        didSet { UserDefaults.standard.set(storyLevelRaw, forKey: "storyLevelRaw") }
    }
    var storyGenreRaw: String {
        didSet { UserDefaults.standard.set(storyGenreRaw, forKey: "storyGenreRaw") }
    }
    /// Comma-joined `StoryQuestion.Kind` raw values the learner wants generated.
    var storyQuestionTypesRaw: String {
        didSet { UserDefaults.standard.set(storyQuestionTypesRaw, forKey: "storyQuestionTypesRaw") }
    }
    var storyQuestionCount: Int {
        didSet { UserDefaults.standard.set(storyQuestionCount, forKey: "storyQuestionCount") }
    }
    /// Default for "Illustrate this story" in the setup form. Off by default — images are a
    /// separate model download and add generation time.
    var storyIllustrationsEnabled: Bool {
        didSet { UserDefaults.standard.set(storyIllustrationsEnabled, forKey: "storyIllustrationsEnabled") }
    }
    /// Images per illustrated story (1–4; the first is always the header image).
    var storyImageCount: Int {
        didSet { UserDefaults.standard.set(storyImageCount, forKey: "storyImageCount") }
    }
    /// Default for "Translate after writing" in the setup form. Off by default — the translation
    /// is always available on demand from the story screen, and pre-writing it costs another run.
    var storyTranslationEnabled: Bool {
        didSet { UserDefaults.standard.set(storyTranslationEnabled, forKey: "storyTranslationEnabled") }
    }
    /// When on, time spent reading or listening to a story keeps the streak alive on its own —
    /// no questions required (a minute minimum, see `StudyDay.storyStreakSeconds`).
    var storyTimeCountsTowardStreak: Bool {
        didSet { UserDefaults.standard.set(storyTimeCountsTowardStreak, forKey: "storyTimeCountsTowardStreak") }
    }
    /// When on, words saved while reading and single-word fixes from graded written answers flow
    /// into the learner profile — the same hand-off the matching game and article game make.
    var storyFeedsCoach: Bool {
        didSet { UserDefaults.standard.set(storyFeedsCoach, forKey: "storyFeedsCoach") }
    }

    var storyLevel: CEFRLevel {
        get { CEFRLevel(rawValue: storyLevelRaw) ?? .a2 }
        set { storyLevelRaw = newValue.rawValue }
    }
    var storyGenre: StoryGenre {
        get { StoryGenre(rawValue: storyGenreRaw) ?? .alltag }
        set { storyGenreRaw = newValue.rawValue }
    }
    /// Selected question kinds in canonical order; never empty (falls back to multiple choice).
    var storyQuestionKinds: [StoryQuestion.Kind] {
        get {
            let kinds = storyQuestionTypesRaw.split(separator: ",").compactMap { StoryQuestion.Kind(rawValue: String($0)) }
            return kinds.isEmpty ? [.multipleChoice] : kinds
        }
        set {
            let ordered = StoryQuestion.Kind.allCases.filter { newValue.contains($0) }
            storyQuestionTypesRaw = (ordered.isEmpty ? [.multipleChoice] : ordered).map(\.rawValue).joined(separator: ",")
        }
    }

    // MARK: - Gamification Settings

    /// Master switch for the game layer (level card, goal ring, badges, pyramid). On by default;
    /// turning it off hides every gamified surface but nothing stops accruing — XP, streaks and
    /// stats are all derived from the study log, so switching back on restores the full picture.
    var gamificationEnabled: Bool {
        didSet { UserDefaults.standard.set(gamificationEnabled, forKey: "gamificationEnabled") }
    }
    /// The daily study goal in minutes behind the Tagesziel ring. One of
    /// `ExperienceService.dailyGoalOptions`.
    var dailyGoalMinutes: Int {
        didSet { UserDefaults.standard.set(dailyGoalMinutes, forKey: "dailyGoalMinutes") }
    }
    /// Confetti + level-up sheets. Off keeps the badges and numbers, loses the spectacle.
    var gamificationCelebrationsEnabled: Bool {
        didSet { UserDefaults.standard.set(gamificationCelebrationsEnabled, forKey: "gamificationCelebrationsEnabled") }
    }
    /// The Abzeichen (badge) grid on the Fortschritt screen.
    var gamificationBadgesEnabled: Bool {
        didSet { UserDefaults.standard.set(gamificationBadgesEnabled, forKey: "gamificationBadgesEnabled") }
    }
    /// The Lernpyramide — the 3D learning path — on Home and Fortschritt.
    var gamificationPyramidEnabled: Bool {
        didSet { UserDefaults.standard.set(gamificationPyramidEnabled, forKey: "gamificationPyramidEnabled") }
    }

    // MARK: - Practice Reminder Settings

    /// Master switch for the "come back and practice" local notifications. Off by default — the app
    /// never nags unless the learner opts in. See `PracticeReminderService`.
    var practiceRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(practiceRemindersEnabled, forKey: "practiceRemindersEnabled") }
    }
    /// Which inactivity checkpoints are on, stored as comma-joined `ReminderCheckpoint` raw values.
    /// Each enabled checkpoint fires once, measured from the last practice — turning several on
    /// builds an escalating ladder whose gaps grow, so reminders thin out the longer someone's away.
    var practiceReminderCheckpointsRaw: String {
        didSet { UserDefaults.standard.set(practiceReminderCheckpointsRaw, forKey: "practiceReminderCheckpointsRaw") }
    }
    /// Typed accessor for the enabled reminder checkpoints.
    var practiceReminderCheckpoints: Set<ReminderCheckpoint> {
        get { Set(practiceReminderCheckpointsRaw.split(separator: ",").compactMap { ReminderCheckpoint(rawValue: String($0)) }) }
        set { practiceReminderCheckpointsRaw = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    // MARK: - Generation Speed Tracking

    /// Record a completed generation for speed stats.
    func recordGenerationTime(_ seconds: TimeInterval, cardCount: Int, for model: MLXModel) {
        UserDefaults.standard.set(seconds, forKey: "lastGenSeconds_\(model.rawValue)")
        UserDefaults.standard.set(cardCount, forKey: "lastGenCards_\(model.rawValue)")
    }

    /// Returns (seconds, cardCount) for the last generation with this model, or nil if never used.
    func lastGenerationStats(for model: MLXModel) -> (seconds: Double, cardCount: Int)? {
        let seconds = UserDefaults.standard.double(forKey: "lastGenSeconds_\(model.rawValue)")
        let cardCount = UserDefaults.standard.integer(forKey: "lastGenCards_\(model.rawValue)")
        guard seconds > 0, cardCount > 0 else { return nil }
        return (seconds, cardCount)
    }

    init() {
        let providerRaw = UserDefaults.standard.string(forKey: "activeModelProvider") ?? ""
        self.activeProvider = ModelProvider(rawValue: providerRaw) ?? .mlx

        // On first run (no stored choice), default to Apple's built-in model when the device
        // supports it — zero download, instant start. The user can switch to any other model and
        // that choice persists as their new default.
        let firstRunDefault: MLXModel = AppleIntelligenceService.currentlyAvailable() ? .appleIntelligence : .qwen3_0_6B

        let modelRaw = UserDefaults.standard.string(forKey: "selectedMLXModel") ?? ""
        self.selectedMLXModel = MLXModel(rawValue: modelRaw) ?? firstRunDefault

        let styleRaw = UserDefaults.standard.string(forKey: "flashcardStyle") ?? ""
        self.flashcardStyle = FlashcardStyle(rawValue: styleRaw) ?? .default
        self.flashcardIllustrationsEnabled = UserDefaults.standard.bool(forKey: "flashcardIllustrationsEnabled")

        self.selectedVoiceIdentifier = UserDefaults.standard.string(forKey: "selectedVoiceIdentifier")
        self.autoAdvance = UserDefaults.standard.bool(forKey: "autoAdvance")

        let lastRaw = UserDefaults.standard.string(forKey: "lastLoadedModel") ?? ""
        self.lastLoadedModel = MLXModel(rawValue: lastRaw)

        // Matching settings.
        let storedPairCount = UserDefaults.standard.integer(forKey: "matchingPairCount")
        self.matchingPairCount = [6, 8, 10, 12].contains(storedPairCount) ? storedPairCount : 8
        self.matchingTrickyFirst = (UserDefaults.standard.object(forKey: "matchingTrickyFirst") as? Bool) ?? true
        self.matchingFeedsCoach = (UserDefaults.standard.object(forKey: "matchingFeedsCoach") as? Bool) ?? true
        self.articleFeedsCoach = (UserDefaults.standard.object(forKey: "articleFeedsCoach") as? Bool) ?? true
        self.prepositionsFeedCoach = (UserDefaults.standard.object(forKey: "prepositionsFeedCoach") as? Bool) ?? true
        self.prepositionPictureMode = PrepositionPictureMode(
            rawValue: UserDefaults.standard.string(forKey: PrepositionPictureMode.defaultsKey) ?? ""
        ) ?? .on
        self.hapticFeedbackMode = HapticFeedbackMode(rawValue: UserDefaults.standard.string(forKey: "hapticFeedbackMode") ?? "") ?? .all

        // Conversation settings — default the chat model to the selected card model.
        let chatModelRaw = UserDefaults.standard.string(forKey: "selectedChatModel") ?? ""
        self.selectedChatModel = MLXModel(rawValue: chatModelRaw)
            ?? MLXModel(rawValue: modelRaw)
            ?? firstRunDefault
        self.autoPlayReplies = (UserDefaults.standard.object(forKey: "autoPlayReplies") as? Bool) ?? true
        self.chatLevelRaw = UserDefaults.standard.string(forKey: "chatLevelRaw") ?? CEFRLevel.a2.rawValue
        self.chatFormalityRaw = UserDefaults.standard.string(forKey: "chatFormalityRaw") ?? Formality.du.rawValue
        self.chatStrictnessRaw = UserDefaults.standard.string(forKey: "chatStrictnessRaw") ?? CorrectionStrictness.balanced.rawValue
        self.chatFeedbackStyleRaw = UserDefaults.standard.string(forKey: "chatFeedbackStyleRaw") ?? FeedbackStyle.tellMe.rawValue
        self.chatCorrectionsEnabled = (UserDefaults.standard.object(forKey: "chatCorrectionsEnabled") as? Bool) ?? true
        self.chatShowCorrectionTranslation = (UserDefaults.standard.object(forKey: "chatShowCorrectionTranslation") as? Bool) ?? false
        self.chatEagerAssist = (UserDefaults.standard.object(forKey: "chatEagerAssist") as? Bool) ?? false
        self.chatAutoShowTranslation = (UserDefaults.standard.object(forKey: "chatAutoShowTranslation") as? Bool) ?? true
        let storedHintCount = UserDefaults.standard.integer(forKey: "chatHintCount")
        self.chatHintCount = (1...3).contains(storedHintCount) ? storedHintCount : 1
        self.chatPersonalizedCoaching = (UserDefaults.standard.object(forKey: "chatPersonalizedCoaching") as? Bool) ?? true
        self.chatSpacedReview = (UserDefaults.standard.object(forKey: "chatSpacedReview") as? Bool) ?? true
        self.chatSpacedReviewScopeRaw = UserDefaults.standard.string(forKey: "chatSpacedReviewScopeRaw") ?? SpacedReviewScope.everywhere.rawValue
        let paperModelRaw = UserDefaults.standard.string(forKey: "selectedPaperModel") ?? ""
        self.selectedPaperModel = MLXModel(rawValue: paperModelRaw) ?? PaperStudyService.requiredModel

        // Story settings — the level follows the conversation level until changed.
        self.storyLevelRaw = UserDefaults.standard.string(forKey: "storyLevelRaw")
            ?? UserDefaults.standard.string(forKey: "chatLevelRaw")
            ?? CEFRLevel.a2.rawValue
        self.storyGenreRaw = UserDefaults.standard.string(forKey: "storyGenreRaw") ?? StoryGenre.alltag.rawValue
        self.storyQuestionTypesRaw = UserDefaults.standard.string(forKey: "storyQuestionTypesRaw")
            ?? StoryQuestion.Kind.multipleChoice.rawValue
        let storedStoryQuestionCount = UserDefaults.standard.integer(forKey: "storyQuestionCount")
        self.storyQuestionCount = [4, 6, 8, 10].contains(storedStoryQuestionCount) ? storedStoryQuestionCount : 6
        self.storyIllustrationsEnabled = (UserDefaults.standard.object(forKey: "storyIllustrationsEnabled") as? Bool) ?? false
        let storedStoryImageCount = UserDefaults.standard.integer(forKey: "storyImageCount")
        self.storyImageCount = (1...4).contains(storedStoryImageCount) ? storedStoryImageCount : 2
        self.storyTranslationEnabled = (UserDefaults.standard.object(forKey: "storyTranslationEnabled") as? Bool) ?? false
        self.storyTimeCountsTowardStreak = (UserDefaults.standard.object(forKey: "storyTimeCountsTowardStreak") as? Bool) ?? true
        self.storyFeedsCoach = (UserDefaults.standard.object(forKey: "storyFeedsCoach") as? Bool) ?? true

        // Gamification — on by default; the study log it's derived from exists either way.
        self.gamificationEnabled = (UserDefaults.standard.object(forKey: "gamificationEnabled") as? Bool) ?? true
        let storedGoal = UserDefaults.standard.integer(forKey: "dailyGoalMinutes")
        self.dailyGoalMinutes = ExperienceService.dailyGoalOptions.contains(storedGoal)
            ? storedGoal : ExperienceService.defaultDailyGoalMinutes
        self.gamificationCelebrationsEnabled = (UserDefaults.standard.object(forKey: "gamificationCelebrationsEnabled") as? Bool) ?? true
        self.gamificationBadgesEnabled = (UserDefaults.standard.object(forKey: "gamificationBadgesEnabled") as? Bool) ?? true
        self.gamificationPyramidEnabled = (UserDefaults.standard.object(forKey: "gamificationPyramidEnabled") as? Bool) ?? true

        // Practice reminders — opt-in, so the master switch defaults off (nothing is scheduled while
        // it's off). The checkpoint set is pre-seeded with a gentle escalating ladder so flipping the
        // switch on is immediately useful.
        self.practiceRemindersEnabled = UserDefaults.standard.bool(forKey: "practiceRemindersEnabled")
        self.practiceReminderCheckpointsRaw = UserDefaults.standard.string(forKey: "practiceReminderCheckpointsRaw")
            ?? [ReminderCheckpoint.threeDays, .week, .month].map(\.rawValue).joined(separator: ",")
    }
}
