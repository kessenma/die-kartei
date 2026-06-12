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

    /// The identifier of the preferred German TTS voice (nil = system default de-DE).
    var selectedVoiceIdentifier: String? {
        didSet {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "selectedVoiceIdentifier")
        }
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
    var chatCorrectionsEnabled: Bool {
        didSet { UserDefaults.standard.set(chatCorrectionsEnabled, forKey: "chatCorrectionsEnabled") }
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
    /// The model used to generate study materials from papers/links (and to discuss them).
    var selectedPaperModel: MLXModel {
        didSet { UserDefaults.standard.set(selectedPaperModel.rawValue, forKey: "selectedPaperModel") }
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

        let modelRaw = UserDefaults.standard.string(forKey: "selectedMLXModel") ?? ""
        self.selectedMLXModel = MLXModel(rawValue: modelRaw) ?? .qwen3_0_6B

        let styleRaw = UserDefaults.standard.string(forKey: "flashcardStyle") ?? ""
        self.flashcardStyle = FlashcardStyle(rawValue: styleRaw) ?? .default

        self.selectedVoiceIdentifier = UserDefaults.standard.string(forKey: "selectedVoiceIdentifier")
        self.autoAdvance = UserDefaults.standard.bool(forKey: "autoAdvance")

        let lastRaw = UserDefaults.standard.string(forKey: "lastLoadedModel") ?? ""
        self.lastLoadedModel = MLXModel(rawValue: lastRaw)

        // Conversation settings — default the chat model to the selected card model.
        let chatModelRaw = UserDefaults.standard.string(forKey: "selectedChatModel") ?? ""
        self.selectedChatModel = MLXModel(rawValue: chatModelRaw)
            ?? MLXModel(rawValue: modelRaw)
            ?? .qwen3_0_6B
        self.autoPlayReplies = (UserDefaults.standard.object(forKey: "autoPlayReplies") as? Bool) ?? true
        self.chatLevelRaw = UserDefaults.standard.string(forKey: "chatLevelRaw") ?? CEFRLevel.a2.rawValue
        self.chatFormalityRaw = UserDefaults.standard.string(forKey: "chatFormalityRaw") ?? Formality.du.rawValue
        self.chatStrictnessRaw = UserDefaults.standard.string(forKey: "chatStrictnessRaw") ?? CorrectionStrictness.balanced.rawValue
        self.chatCorrectionsEnabled = (UserDefaults.standard.object(forKey: "chatCorrectionsEnabled") as? Bool) ?? true
        self.chatEagerAssist = (UserDefaults.standard.object(forKey: "chatEagerAssist") as? Bool) ?? false
        self.chatAutoShowTranslation = (UserDefaults.standard.object(forKey: "chatAutoShowTranslation") as? Bool) ?? true
        let storedHintCount = UserDefaults.standard.integer(forKey: "chatHintCount")
        self.chatHintCount = (1...3).contains(storedHintCount) ? storedHintCount : 1
        let paperModelRaw = UserDefaults.standard.string(forKey: "selectedPaperModel") ?? ""
        self.selectedPaperModel = MLXModel(rawValue: paperModelRaw) ?? .gemma4_E4B
    }
}
