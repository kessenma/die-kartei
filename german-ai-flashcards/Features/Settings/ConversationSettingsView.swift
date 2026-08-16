import SwiftUI

/// The "Conversation" tab of the Settings screen. Home for conversation-practice defaults —
/// corrections, voice, learning aids, and the phrase library. These set the starting point for
/// every new conversation.
struct ConversationSettingsView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    /// Bridges the enum picker to the raw-string default stored on the model manager.
    private var strictnessBinding: Binding<CorrectionStrictness> {
        Binding(
            get: { CorrectionStrictness(rawValue: modelManager.chatStrictnessRaw) ?? .balanced },
            set: { modelManager.chatStrictnessRaw = $0.rawValue }
        )
    }

    /// Bridges the spaced-review scope picker to its raw-string default.
    private var spacedReviewScopeBinding: Binding<SpacedReviewScope> {
        Binding(
            get: { modelManager.spacedReviewScope },
            set: { modelManager.spacedReviewScope = $0 }
        )
    }

    /// Bridges the feedback-style picker to its raw-string default.
    private var feedbackStyleBinding: Binding<FeedbackStyle> {
        Binding(
            get: { FeedbackStyle(rawValue: modelManager.chatFeedbackStyleRaw) ?? .tellMe },
            set: { modelManager.chatFeedbackStyleRaw = $0.rawValue }
        )
    }

    var body: some View {
        Section {
            Toggle("Show suggested corrections", isOn: $modelManager.chatCorrectionsEnabled)
            if modelManager.chatCorrectionsEnabled {
                Toggle("Show English meaning", isOn: $modelManager.chatShowCorrectionTranslation)

                Picker("Strictness", selection: strictnessBinding) {
                    ForEach(CorrectionStrictness.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                Text(strictnessBinding.wrappedValue.subtitle)
                    .font(.caption).foregroundStyle(.secondary)

                Picker("Feedback", selection: feedbackStyleBinding) {
                    ForEach(FeedbackStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text(feedbackStyleBinding.wrappedValue.subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Corrections").themedSectionHeader()
        } footer: {
            Text(correctionsFooter)
                .font(.caption2)
        }
        .themedListRow()

        Section {
            Toggle("Auto-play AI replies", isOn: $modelManager.autoPlayReplies)
        } header: {
            Text("Voice").themedSectionHeader()
        } footer: {
            Text("Replies are spoken aloud automatically. You can always replay them with the play / slow buttons.")
                .font(.caption2)
        }
        .themedListRow()

        Section {
            Picker("Hints per request", selection: $modelManager.chatHintCount) {
                Text("1").tag(1)
                Text("2").tag(2)
                Text("3").tag(3)
            }
            .pickerStyle(.segmented)

            Toggle("Auto-translate & pre-load hints", isOn: $modelManager.chatEagerAssist)

            if modelManager.chatEagerAssist {
                Toggle("Auto-show translations", isOn: $modelManager.chatAutoShowTranslation)
            }
        } header: {
            Text("Learning aids").themedSectionHeader()
        } footer: {
            Text(learningAidsFooter)
                .font(.caption2)
        }
        .themedListRow()

        Section {
            Toggle("Personalized coaching", isOn: $modelManager.chatPersonalizedCoaching)
            NavigationLink {
                CoachNotesView()
            } label: {
                Label("Coach's Notes", systemImage: "brain.head.profile")
            }
        } header: {
            Text("Coaching").themedSectionHeader()
        } footer: {
            Text("The coach quietly remembers what you struggle with and the words you're learning, and uses that to steer and sharpen future conversations. Everything it remembers stays on your device.")
                .font(.caption2)
        }
        .themedListRow()

        Section {
            Toggle("Spaced review in conversation", isOn: $modelManager.chatSpacedReview)
            if modelManager.chatSpacedReview {
                Picker("Where", selection: spacedReviewScopeBinding) {
                    ForEach(SpacedReviewScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
            }
        } header: {
            Text("Spaced review").themedSectionHeader()
        } footer: {
            Text(modelManager.chatSpacedReview
                 ? "When a flashcard is due, the coach steers the chat so its word comes up. Use it correctly and that counts as a review — the card's schedule advances, no flip needed. " + modelManager.spacedReviewScope.footer
                 : "Off — conversations won't resurface due flashcards or advance their schedule.")
                .font(.caption2)
        }
        .themedListRow()

        Section {
            NavigationLink {
                PhraseLibraryView(modelManager: modelManager, mlxService: mlxService)
            } label: {
                Label("Phrase library", systemImage: "ear.badge.waveform")
            }
        } header: {
            Text("Phrases").themedSectionHeader()
        } footer: {
            Text("Save German phrases you hear in the wild but don't understand. The AI weaves the active ones into matching scenario chats.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var correctionsFooter: String {
        guard modelManager.chatCorrectionsEnabled else {
            return "Corrections are off — the AI won't suggest fixes to what you say. New conversations start with this default; you can still change it per chat in setup."
        }
        let base = modelManager.chatShowCorrectionTranslation
            ? "When something needs fixing, the corrected German appears above your message with its English meaning below it. Tap a word — or select a phrase — to translate it or save it to your library."
            : "When something needs fixing, the corrected German appears above your message. Turn on English meaning to also show what the correction means. Tap a word — or select a phrase — to translate it or save it."
        let feedback = (feedbackStyleBinding.wrappedValue == .nudgeMe)
            ? " With Nudge me, the coach asks a question first and lets you say the fixed sentence back — you only see the answer after a miss or when you ask. Repairing it yourself makes it stick."
            : ""
        return base + feedback
    }

    private var learningAidsFooter: String {
        if !modelManager.chatEagerAssist {
            return "Pick how many hint suggestions to generate. Turn on auto-translate to prepare translations and hints in the background so they’re instant."
        }
        if modelManager.chatAutoShowTranslation {
            return "Translations appear automatically under each reply, and hints are pre-loaded so they show instantly. Great for early learners — uses a bit more battery."
        }
        return "Translations and hints are prepared in the background but stay hidden until you tap, so taps are instant. Uses a bit more battery."
    }
}
