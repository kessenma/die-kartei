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

    /// Bridges the input-mode picker to its raw-string default.
    private var inputModeBinding: Binding<ChatInputMode> {
        Binding(
            get: { modelManager.chatInputMode },
            set: { modelManager.chatInputMode = $0 }
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
            TextField("Your name", text: $modelManager.learnerName)
                .textContentType(.name)
                .autocorrectionDisabled()
        } header: {
            Text("You").themedSectionHeader()
        } footer: {
            Text("How your conversation partner addresses you. Write it the way you want to hear it: „Kyle“, or „Herr Essenmacher“ for formal chats. Leave it blank and the AI makes a name up.")
                .font(.caption2)
        }
        .themedListRow()

        Section {
            // The chat level was never editable from Settings — it only existed as whatever the
            // last conversation happened to be set to. It's the app-wide anchor now, so this points
            // at the screen that owns it.
            NavigationLink {
                LevelSettingsView(modelManager: modelManager)
            } label: {
                HStack {
                    Text("Level")
                    Spacer()
                    Text("\(modelManager.germanLevel.rawValue) · \(modelManager.germanLevel.englishLabel)")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Level").themedSectionHeader()
        } footer: {
            Text("Where every new conversation starts, shared with stories. You can still pick a different level for a single chat in its setup screen — that leaves this one alone.")
                .font(.caption2)
        }
        .themedListRow()

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
            Picker("Your turns", selection: inputModeBinding) {
                ForEach(ChatInputMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(inputModeBinding.wrappedValue.subtitle)
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Speak or type").themedSectionHeader()
        } footer: {
            Text("Where new conversations start. Typing keeps a session silent — for a plane, a train, or a quiet office — and either way you can switch mid-conversation from the chat's menu.")
                .font(.caption2)
        }
        .themedListRow()

        Section {
            Toggle("Auto-play AI replies", isOn: $modelManager.autoPlayReplies)
        } header: {
            Text("Voice").themedSectionHeader()
        } footer: {
            Text("Replies are spoken aloud automatically, except while you're typing your turns. You can always replay them with the play / slow buttons.")
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

            Toggle("Hint every turn", isOn: $modelManager.chatAutoHints)

            Toggle("Color noun genders", isOn: $modelManager.chatGenderColors)

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
                CoachNotesView(modelManager: modelManager)
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
        var extras: [String] = []
        if modelManager.chatAutoHints {
            extras.append("A \u{201C}you could say\u{201D} suggestion appears under every reply, so you always have something to say.")
        }
        if modelManager.chatGenderColors {
            extras.append("Nouns in AI replies take their der/die/das color. Tap one to see why.")
        }
        let extraText = extras.isEmpty ? "" : " " + extras.joined(separator: " ")
        if !modelManager.chatEagerAssist {
            return "Pick how many hint suggestions to generate. Turn on auto-translate to prepare translations and hints in the background so they’re instant." + extraText
        }
        if modelManager.chatAutoShowTranslation {
            return "Translations appear automatically under each reply, and hints are pre-loaded so they show instantly. Great for early learners — uses a bit more battery." + extraText
        }
        return "Translations and hints are prepared in the background but stay hidden until you tap, so taps are instant. Uses a bit more battery." + extraText
    }
}
