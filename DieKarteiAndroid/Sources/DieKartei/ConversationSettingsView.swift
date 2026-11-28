@testable import DieKarteiCore
import SwiftUI

/// Settings ▸ Conversation (iOS `ConversationSettingsView`): where every new chat starts. Same
/// keys and defaults as iOS (`ChatPrefs`), so a chat starts the same on both.
struct ConversationSettingsView: View {
    @AppStorage(ChatPrefs.learnerNameKey) var learnerName = ""
    @AppStorage(ChatPrefs.correctionsEnabledKey) var correctionsEnabled = ChatPrefs.correctionsEnabledDefault
    @AppStorage(ChatPrefs.showCorrectionTranslationKey) var showCorrectionTranslation = ChatPrefs.showCorrectionTranslationDefault
    @AppStorage(ChatPrefs.strictnessKey) var strictnessRaw = CorrectionStrictness.balanced.rawValue
    @AppStorage(ChatPrefs.feedbackStyleKey) var feedbackStyleRaw = FeedbackStyle.tellMe.rawValue
    @AppStorage(ChatPrefs.inputModeKey) var inputModeRaw = ChatInputMode.speak.rawValue
    @AppStorage(ChatPrefs.autoPlayRepliesKey) var autoPlayReplies = ChatPrefs.autoPlayRepliesDefault
    @AppStorage(ChatPrefs.hintCountKey) var hintCount = ChatPrefs.hintCountDefault
    @AppStorage(ChatPrefs.autoHintsKey) var autoHints = ChatPrefs.autoHintsDefault
    @AppStorage(ChatPrefs.eagerAssistKey) var eagerAssist = ChatPrefs.eagerAssistDefault
    @AppStorage(ChatPrefs.autoShowTranslationKey) var autoShowTranslation = ChatPrefs.autoShowTranslationDefault
    @AppStorage(LearnerMemory.personalizedCoachingKey) var personalizedCoaching = true

    var strictness: CorrectionStrictness { CorrectionStrictness(rawValue: strictnessRaw) ?? .balanced }
    var feedbackStyle: FeedbackStyle { FeedbackStyle(rawValue: feedbackStyleRaw) ?? .tellMe }
    var inputMode: ChatInputMode { ChatInputMode(rawValue: inputModeRaw) ?? .speak }

    var body: some View {
        List {
            Section {
                TextField("Your name", text: $learnerName)
            } header: {
                Text("You")
            } footer: {
                Text("How your conversation partner addresses you. Write it the way you want to hear it: „Kyle“, or „Herr Essenmacher“ for formal chats. Leave it blank and the AI makes a name up.")
            }

            Section {
                Toggle("Show suggested corrections", isOn: $correctionsEnabled)
                if correctionsEnabled {
                    Toggle("Show English meaning", isOn: $showCorrectionTranslation)
                    Picker("Strictness", selection: $strictnessRaw) {
                        ForEach(CorrectionStrictness.allCases) { s in Text(s.rawValue).tag(s.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text(strictness.subtitle).font(.caption).foregroundStyle(.secondary)
                    Picker("Feedback", selection: $feedbackStyleRaw) {
                        ForEach(FeedbackStyle.allCases) { s in Text(s.rawValue).tag(s.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text(feedbackStyle.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Corrections")
            } footer: {
                Text(correctionsFooter)
            }

            Section {
                Picker("Your turns", selection: $inputModeRaw) {
                    ForEach(ChatInputMode.allCases) { m in Text(m.rawValue).tag(m.rawValue) }
                }
                .pickerStyle(.segmented)
                Text(inputMode.subtitle).font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Speak or type")
            } footer: {
                Text("Where new conversations start. Typing keeps a session silent — for a plane, a train, or a quiet office — and either way you can switch mid-conversation.")
            }

            Section {
                Toggle("Auto-play AI replies", isOn: $autoPlayReplies)
            } header: {
                Text("Voice")
            } footer: {
                Text("Replies are spoken aloud automatically, except while you're typing your turns. You can always replay them.")
            }

            Section {
                Picker("Hints per request", selection: $hintCount) {
                    ForEach(Array(ChatPrefs.hintCountRange), id: \.self) { n in Text("\(n)").tag(n) }
                }
                .pickerStyle(.segmented)
                Toggle("Hint every turn", isOn: $autoHints)
                Toggle("Auto-translate & pre-load hints", isOn: $eagerAssist)
                if eagerAssist {
                    Toggle("Auto-show translations", isOn: $autoShowTranslation)
                }
            } header: {
                Text("Learning aids")
            } footer: {
                Text(learningAidsFooter)
            }

            Section {
                Toggle("Personalized coaching", isOn: $personalizedCoaching)
                NavigationLink { CoachNotesView() } label: {
                    Label("Coach's Notes", systemImage: "brain.head.profile")
                }
            } header: {
                Text("Coaching")
            } footer: {
                Text("The coach quietly remembers what you struggle with and the words you're learning, and uses that to steer and sharpen future conversations. Everything stays on your device.")
            }

            Section {
                NavigationLink { PhraseLibraryView() } label: {
                    Text("Phrase library")
                }
            } header: {
                Text("Phrases")
            } footer: {
                Text("Save German phrases you hear in the wild but don't understand. The AI weaves the active ones into matching scenario chats.")
            }
        }
        .navigationTitle("Conversation")
    }

    /// iOS's footer, word for word.
    var correctionsFooter: String {
        guard correctionsEnabled else {
            return "Corrections are off — the AI won't suggest fixes to what you say. New conversations start with this default."
        }
        let base = showCorrectionTranslation
            ? "When something needs fixing, the corrected German appears above your message with its English meaning below it."
            : "When something needs fixing, the corrected German appears above your message. Turn on English meaning to also show what the correction means."
        let feedback = feedbackStyle == .nudgeMe
            ? " With Nudge me, the coach asks a question first and lets you say the fixed sentence back — you only see the answer after a miss or when you ask. Repairing it yourself makes it stick."
            : ""
        return base + feedback
    }

    var learningAidsFooter: String {
        let extra = autoHints
            ? " A \u{201C}you could say\u{201D} suggestion appears under every reply, so you always have something to say."
            : ""
        if !eagerAssist {
            return "Pick how many hint suggestions to generate. Turn on auto-translate to prepare translations and hints in the background so they're instant." + extra
        }
        if autoShowTranslation {
            return "Translations appear automatically under each reply, and hints are pre-loaded so they show instantly. Great for early learners — uses a bit more battery." + extra
        }
        return "Translations and hints are prepared in the background but stay hidden until you tap, so taps are instant. Uses a bit more battery." + extra
    }
}
