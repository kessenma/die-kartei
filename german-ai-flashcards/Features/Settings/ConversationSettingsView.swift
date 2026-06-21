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
            }
        } header: {
            Text("Corrections")
        } footer: {
            Text(modelManager.chatCorrectionsEnabled
                 ? (modelManager.chatShowCorrectionTranslation
                    ? "When something needs fixing, the corrected German appears above your message with its English meaning below it. Tap a word — or select a phrase — to translate it or save it to your library."
                    : "When something needs fixing, the corrected German appears above your message. Turn on English meaning to also show what the correction means. Tap a word — or select a phrase — to translate it or save it.")
                 : "Corrections are off — the AI won't suggest fixes to what you say. New conversations start with this default; you can still change it per chat in setup.")
                .font(.caption2)
        }

        Section {
            Toggle("Auto-play AI replies", isOn: $modelManager.autoPlayReplies)
        } header: {
            Text("Voice")
        } footer: {
            Text("Replies are spoken aloud automatically. You can always replay them with the play / slow buttons.")
                .font(.caption2)
        }

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
            Text("Learning aids")
        } footer: {
            Text(learningAidsFooter)
                .font(.caption2)
        }

        Section {
            NavigationLink {
                PhraseLibraryView(modelManager: modelManager, mlxService: mlxService)
            } label: {
                Label("Phrase library", systemImage: "ear.badge.waveform")
            }
        } header: {
            Text("Phrases")
        } footer: {
            Text("Save German phrases you hear in the wild but don't understand. The AI weaves the active ones into matching scenario chats.")
                .font(.caption2)
        }
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
