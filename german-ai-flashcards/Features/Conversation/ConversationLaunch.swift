import Foundation
import SwiftData

/// Rebuilding a saved chat's `ConversationConfig` so it can be resumed. Lived inside
/// `ConversationListView` until the Job prep hub needed the same thing for its interview list.
extension ChatConversation {
    /// The per-chat choices come from the chat; the learner-wide aids (translations, hints, eager
    /// assist, gender colors) come from the current settings, as they always have.
    @MainActor
    func makeConfig(modelManager: MLXModelManager, decks: [SavedDeck]) -> ConversationConfig {
        let model = self.model ?? modelManager.selectedChatModel
        var c = ConversationConfig(model: model)
        c.learnerName = ConversationConfig.learnerName(from: modelManager.learnerName)
        c.mode = mode
        c.deckIDs = deckIDsRaw.compactMap { UUID(uuidString: $0) }
        c.deckLabel = deckLabel
        let ids = Set(c.deckIDs)
        c.deckWords = decks.filter { ids.contains($0.id) }.flatMap { $0.cards.map(\.germanWord) }
        c.scenario = scenario
        c.customScenario = customScenario ?? ""
        c.focusAreas = focusAreas
        c.level = level
        c.formality = formality
        c.correctionsEnabled = correctionsEnabled
        c.correctionTranslationEnabled = modelManager.chatShowCorrectionTranslation
        c.strictness = strictness
        c.feedbackStyle = feedbackStyle
        c.autoPlay = autoPlay
        c.inputMode = inputMode
        c.eagerAssist = modelManager.chatEagerAssist
        c.autoShowTranslation = modelManager.chatAutoShowTranslation
        c.hintCount = modelManager.chatHintCount
        c.autoHints = modelManager.chatAutoHints
        c.genderColors = modelManager.chatGenderColors
        c.paperTitle = paperTitle
        c.paperContext = paperContext
        c.jobTitle = jobTitle
        c.jobContext = jobContext
        c.jobCompany = jobCompany
        c.jobLocation = jobLocation
        c.jobURL = jobURL
        c.interviewRound = interviewRound
        c.interviewFormat = interviewFormat
        c.jobSnapshotFile = jobSnapshotFile
        c.jobPostingID = jobPostingID
        return c
    }

    /// `ConversationMode.interview.rawValue`, spelled out because `#Predicate` can only take a
    /// literal. Keep in step with `Models/ConversationConfig.swift`.
    static let interviewModeRaw = "Interview"
}
