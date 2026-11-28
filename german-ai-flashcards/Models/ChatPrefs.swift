//
//  ChatPrefs.swift
//  german-ai-flashcards
//
//  Settings ▸ Conversation: the keys, the defaults, and what a chat reads from them. Shared with
//  the Android app (DieKarteiCore): iOS's `MLXModelManager` stores its chat settings under these
//  keys, iOS's setup screen and `makeConfig` and Android's chat screens fill a config through
//  `applyDefaults` and `applyDeviceSettings`, so both apps start and reopen a chat the same way.
//

import Foundation

enum ChatPrefs {
    // MARK: Keys (iOS's UserDefaults names; never rename)

    static let learnerNameKey = "learnerName"
    static let levelKey = "german.level"
    static let formalityKey = "chatFormalityRaw"
    static let correctionsEnabledKey = "chatCorrectionsEnabled"
    static let showCorrectionTranslationKey = "chatShowCorrectionTranslation"
    static let strictnessKey = "chatStrictnessRaw"
    static let feedbackStyleKey = "chatFeedbackStyleRaw"
    static let inputModeKey = "chatInputModeRaw"
    static let autoPlayRepliesKey = "autoPlayReplies"
    static let hintCountKey = "chatHintCount"
    static let autoHintsKey = "chatAutoHints"
    static let genderColorsKey = "chatGenderColors"
    static let eagerAssistKey = "chatEagerAssist"
    static let autoShowTranslationKey = "chatAutoShowTranslation"
    static let spacedReviewKey = "chatSpacedReview"
    static let spacedReviewScopeKey = "chatSpacedReviewScopeRaw"
    static let classFeedsCoachKey = "classFeedsCoach"
    static let bestUnaidedStreakKey = "chatBestUnaidedStreak"

    // MARK: Defaults

    static let correctionsEnabledDefault = true
    static let showCorrectionTranslationDefault = false
    static let autoPlayRepliesDefault = true
    static let hintCountDefault = 1
    static let hintCountRange = 1...3
    static let autoHintsDefault = false
    static let genderColorsDefault = true
    static let eagerAssistDefault = false
    static let autoShowTranslationDefault = true
    static let spacedReviewDefault = true
    static let classFeedsCoachDefault = true

    // MARK: Reading

    static func bool(_ key: String, _ fallback: Bool, in d: UserDefaults = SharedDefaults.store) -> Bool {
        d.object(forKey: key) as? Bool ?? fallback
    }

    static func learnerName(in d: UserDefaults = SharedDefaults.store) -> String { d.string(forKey: learnerNameKey) ?? "" }

    static func level(in d: UserDefaults = SharedDefaults.store) -> CEFRLevel {
        d.string(forKey: levelKey).flatMap(CEFRLevel.init(rawValue:)) ?? .a2
    }

    static func formality(in d: UserDefaults = SharedDefaults.store) -> Formality {
        d.string(forKey: formalityKey).flatMap(Formality.init(rawValue:)) ?? .du
    }

    static func strictness(in d: UserDefaults = SharedDefaults.store) -> CorrectionStrictness {
        d.string(forKey: strictnessKey).flatMap(CorrectionStrictness.init(rawValue:)) ?? .balanced
    }

    static func feedbackStyle(in d: UserDefaults = SharedDefaults.store) -> FeedbackStyle {
        d.string(forKey: feedbackStyleKey).flatMap(FeedbackStyle.init(rawValue:)) ?? .tellMe
    }

    static func inputMode(in d: UserDefaults = SharedDefaults.store) -> ChatInputMode {
        d.string(forKey: inputModeKey).flatMap(ChatInputMode.init(rawValue:)) ?? .speak
    }

    /// 1–3; anything else stored reads as the default.
    static func hintCount(in d: UserDefaults = SharedDefaults.store) -> Int {
        let stored = d.integer(forKey: hintCountKey)
        return hintCountRange.contains(stored) ? stored : hintCountDefault
    }

    // MARK: Into a chat

    /// This device's chat settings, which every chat reads fresh: new ones and reopened ones
    /// (iOS `makeConfig`).
    static func applyDeviceSettings(to c: inout ConversationConfig, in d: UserDefaults = SharedDefaults.store) {
        c.learnerName = ConversationConfig.learnerName(from: learnerName(in: d))
        c.correctionTranslationEnabled = bool(showCorrectionTranslationKey, showCorrectionTranslationDefault, in: d)
        c.eagerAssist = bool(eagerAssistKey, eagerAssistDefault, in: d)
        c.autoShowTranslation = bool(autoShowTranslationKey, autoShowTranslationDefault, in: d)
        c.hintCount = hintCount(in: d)
        c.autoHints = bool(autoHintsKey, autoHintsDefault, in: d)
        c.genderColors = bool(genderColorsKey, genderColorsDefault, in: d)
    }

    /// A new chat's starting point: the device settings plus the defaults a chat then keeps
    /// (iOS's setup screen, before the learner's choices for this one chat).
    static func applyDefaults(to c: inout ConversationConfig, in d: UserDefaults = SharedDefaults.store) {
        applyDeviceSettings(to: &c, in: d)
        c.level = level(in: d)
        c.formality = formality(in: d)
        c.correctionsEnabled = bool(correctionsEnabledKey, correctionsEnabledDefault, in: d)
        c.strictness = strictness(in: d)
        c.feedbackStyle = feedbackStyle(in: d)
        c.autoPlay = bool(autoPlayRepliesKey, autoPlayRepliesDefault, in: d)
        c.inputMode = inputMode(in: d)
    }
}
