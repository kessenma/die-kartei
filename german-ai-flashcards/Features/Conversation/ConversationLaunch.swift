import Foundation
import SwiftData

/// Rebuilding a saved chat's `ConversationConfig` so it can be resumed. Lived inside
/// `ConversationListView` until the Job prep hub needed the same thing for its interview list.
extension ChatConversation {
    /// The per-chat choices come from the chat; the learner-wide aids (translations, hints, eager
    /// assist, gender colors) come from the current settings, as they always have.
    ///
    /// The model is this device's answer (`ModelHandoff`), not necessarily the one the chat was
    /// started with: a chat synced from another device continues on a tutor that is here. The
    /// chat's own `modelRaw` is left alone, and `ConversationView` compares the two to say so.
    @MainActor
    func makeConfig(modelManager: MLXModelManager, decks: [SavedDeck]) -> ConversationConfig {
        let model = ModelHandoff.current(original: self.model, pick: modelManager.selectedChatModel).model
        var c = ConversationConfig(model: model)
        // The stored setup and this device's chat settings (both shared with Android), then the deck's words.
        setup.apply(to: &c)
        let ids = Set(c.deckIDs)
        c.deckWords = decks.filter { ids.contains($0.id) }.flatMap { $0.cards.map(\.germanWord) }
        ChatPrefs.applyDeviceSettings(to: &c)
        // The résumé stays on the device: re-read it here, capped to this tutor's slice.
        if usesResume, let context = modelContext, let resume = ResumeStore.current(in: context), !resume.kurzprofil.isEmpty {
            c.resumeProfile = String(resume.kurzprofil.prefix(ResumePrompts.kurzprofilSlice(saver: MemorySaver.isActive(for: model))))
            c.resumeFacts = resume.facts.map(\.text)
        }
        return c
    }

    /// `ConversationMode.interview.rawValue`, spelled out because `#Predicate` can only take a
    /// literal. Keep in step with `Models/ConversationConfig.swift`.
    static let interviewModeRaw = "Interview"
}
