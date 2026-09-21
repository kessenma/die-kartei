import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// A German span the user picked from a conversation message to save into their phrase library.
/// Identifiable so it can drive an item-based `.sheet`.
struct PhraseDraft: Identifiable {
    let id = UUID()
    let german: String
}

/// The voice conversation screen. Tap-to-record, AI replies with playback &
/// translation, your corrections shown above your bubble, and an end-of-session report.
struct ConversationView: View {
    let conversation: ChatConversation
    let config: ConversationConfig
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var appTheme

    @State private var engine: ConversationEngine?
    @State private var summary: ConversationSummary?
    @State private var showSummary = false
    @State private var showEndConfirm = false
    @State private var showSayIt = false
    @State private var showSavedWords = false
    @State private var showHelp = false
    /// Interview chats: the posting the recruiter is working from, for re-reading mid-chat.
    @State private var showPosting = false
    /// App ▸ Voice, reachable from the chat menu so the German voice can be changed mid-session.
    @State private var showVoiceSettings = false
    /// A span the user selected from a correction and wants to save to their phrase library.
    @State private var phraseDraft: PhraseDraft?

    /// The typed turn in progress, its keyboard language, and a handle on the field.
    @State private var draft = ""
    @State private var composerLanguage: ComposerLanguage = .german
    @State private var composer = ChatComposerController()
    /// True only when the learner switched into typing mid-session — then the keyboard comes up
    /// on its own. Opening a chat that was already in typing mode leaves the reply visible.
    @State private var focusComposerOnAppear = false

    var body: some View {
        Group {
            if let engine {
                chat(engine)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if engine == nil {
                let e = ConversationEngine(
                    conversation: conversation, config: config,
                    mlxService: mlxService, modelManager: modelManager,
                    modelContext: modelContext
                )
                engine = e
                e.onAppear()
            }
        }
        .onDisappear { engine?.tearDown() }
        .memoryContext("Chat")
        .sheet(isPresented: $showSummary) {
            if let summary {
                ConversationSummaryView(
                    conversation: conversation,
                    summary: summary,
                    mlxService: mlxService,
                    modelManager: modelManager,
                    onDone: { showSummary = false; dismiss() }
                )
            }
        }
    }

    // MARK: - Layout

    /// The brand theme of the model powering this conversation.
    private var theme: ModelTheme { config.model.theme }

    @ViewBuilder
    private func chat(_ engine: ConversationEngine) -> some View {
        VStack(spacing: 0) {
            topBar(engine)
            brandDivider
            messageList(engine)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputArea(engine)
        }
        .overlay {
            // An interview opens on a "call connecting" screen while the tutor loads and writes
            // its first line; the chat underneath would otherwise sit empty with a status caption.
            if showsRecruiterWarmup(engine) {
                RecruiterWarmupView(
                    config: config,
                    isLoadingModel: engine.isLoadingModel,
                    loadProgress: mlxService.downloadProgress,
                    loadInfo: mlxService.downloadInfo,
                    onCancel: { mlxService.cancelLoad() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showsRecruiterWarmup(engine))
        .background {
            let userTurns = engine.conversation.messages.lazy.filter(\.isUser).count
            // The wash warms one turn at a time — a long conversation literally heats up.
            let restingOpacity = min(0.28 + Double(userTurns) * 0.006, 0.40)
            ZStack(alignment: .top) {
                if appTheme == .klar {
                    Color(.systemBackground)
                } else {
                    ThemedBackground()
                }
                // An animated brand wash at the top, echoing the model sheet styling. It gently
                // intensifies while the model is generating a reply.
                ModelBrandWash(palette: theme.palette, animated: !reduceMotion)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .mask(
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    )
                    .opacity(engine.phase == .thinking ? 0.5 : restingOpacity)
                    .animation(.easeInOut(duration: 0.6), value: engine.phase)
                    .animation(.easeInOut(duration: 1.5), value: userTurns)
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: engine.isRecording) { _, _ in
            // A cue, not an error — silent in "Mistakes only".
            modelManager.hapticFeedbackMode == .all
        }
        .sensoryFeedback(.success, trigger: engine.successTurnCount) { old, new in
            new > old && modelManager.hapticFeedbackMode.playsSuccess
        }
        .sheet(isPresented: Binding(
            get: { engine.inspectedWord != nil },
            set: { if !$0 { engine.dismissInspector() } }
        )) {
            WordInspectorSheet(
                source: engine,
                footer: "Saved words become flashcards: they appear in your end-of-session report, where you can add them to a deck."
            )
        }
        .sheet(isPresented: $showSavedWords) {
            SavedWordsSheet(engine: engine)
        }
        .sheet(isPresented: $showPosting) {
            JobPostingSheet(config: config)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showVoiceSettings) {
            NavigationStack {
                VoiceSettingsView(modelManager: modelManager)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showVoiceSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showHelp) {
            GestureHelpSheet(
                intro: "Two quick gestures help you learn while you chat.",
                accent: theme.accent
            )
        }
        .sheet(item: $phraseDraft) { draft in
            AddEditPhraseSheet(
                modelManager: modelManager,
                mlxService: mlxService,
                anchorScenario: config.scenario,
                phrase: nil,
                initialGerman: draft.german
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.resume() } else { engine.pause() }
        }
        .confirmationDialog("End this conversation?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End & get my report") { endSession(engine) }
            Button("Keep talking", role: .cancel) {}
        } message: {
            Text("You'll get a short coaching report on how you did.")
        }
        .alert("Load \(config.model.rawValue)?", isPresented: Binding(
            get: { engine.showModelLoadPrompt },
            set: { if !$0 { engine.cancelModelLoad() } }
        )) {
            Button("Load model") { engine.confirmModelLoad() }
            Button("Not now", role: .cancel) { engine.cancelModelLoad() }
        } message: {
            Text("This conversation runs on \(config.model.rawValue). It needs to be loaded into memory before you can speak, translate, or get hints.")
        }
    }

    /// A thin model-colored separator under the header.
    private var brandDivider: some View {
        LinearGradient(colors: theme.palette, startPoint: .leading, endPoint: .trailing)
            .frame(height: 1.5)
            .opacity(0.55)
    }

    private func topBar(_ engine: ConversationEngine) -> some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.body.weight(.medium))
            }
            .fixedSize()

            Spacer(minLength: 4)

            VStack(spacing: 1) {
                Text(engine.conversation.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(timeLabel(engine.elapsedSeconds()))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if config.mode == .interview {
                Button {
                    showPosting = true
                } label: {
                    Image(systemName: "briefcase.fill").font(.title3)
                }
                .accessibilityLabel("Show the job posting")
            }

            Button {
                showHelp = true
            } label: {
                Image(systemName: "info.circle").font(.title3)
            }
            .accessibilityLabel("How to translate words and save phrases")

            Menu {
                if engine.isModelReady {
                    Label("\(config.model.rawValue) loaded", systemImage: "checkmark.circle.fill")
                } else if engine.isLoadingModel {
                    Label("Loading \(config.model.rawValue)…", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Button {
                        engine.loadModel()
                    } label: {
                        Label("Load \(config.model.rawValue)", systemImage: "arrow.down.circle")
                    }
                }

                Divider()

                Picker("Input", selection: Binding(
                    get: { engine.inputMode },
                    set: { switchInput(to: $0, engine: engine) }
                )) {
                    ForEach(ChatInputMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                    }
                }

                if engine.isSilent {
                    // The auto-play toggle would read as broken here: typing is silent by design.
                    Label("Replies stay silent while you type", systemImage: "speaker.slash.fill")
                } else {
                    Toggle("Auto-play replies", isOn: $modelManager.autoPlayReplies)
                }
                Button {
                    showVoiceSettings = true
                } label: {
                    Label("Voice settings", systemImage: "waveform")
                }
                Button {
                    showEndConfirm = true
                } label: {
                    Label("End & summarize", systemImage: "flag.checkered")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    // A small badge hints that the model still needs loading.
                    .overlay(alignment: .topTrailing) {
                        if !engine.isModelReady && !engine.isLoadingModel {
                            Circle().fill(.orange).frame(width: 7, height: 7).offset(x: 1, y: -1)
                        }
                    }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func messageList(_ engine: ConversationEngine) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(engine.conversation.sortedMessages) { message in
                        if message.isUser {
                            UserMessageView(
                                message: message,
                                engine: engine,
                                onSavePhrase: { phraseDraft = PhraseDraft(german: $0) }
                            )
                        } else {
                            AssistantMessageView(
                                message: message,
                                engine: engine,
                                onSavePhrase: { phraseDraft = PhraseDraft(german: $0) }
                            )
                        }
                    }

                    if engine.phase == .thinking {
                        if engine.streamingReply.isEmpty {
                            TypingIndicator(model: config.model)
                        } else {
                            AssistantStreamingView(text: engine.streamingReply, model: config.model)
                        }
                    }

                    if let error = engine.errorMessage {
                        ErrorBanner(
                            text: error,
                            onRetry: engine.canRetryReply ? { engine.retryReply() } : nil
                        )
                    } else if let notice = engine.strandedTurnNotice {
                        // Not an error — a turn the AI still owes from a session that ended badly.
                        // Without this the only apparent way forward is to send again, which is
                        // what stacks two learner turns and breaks the chat template.
                        StrandedTurnBanner(
                            text: notice,
                            onContinue: { engine.continueStrandedTurn() },
                            onDismiss: { engine.dismissStrandedTurnNotice() }
                        )
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: engine.conversation.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: engine.streamingReply) { _, _ in scrollToBottom(proxy) }
            .onChange(of: engine.phase) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func inputArea(_ engine: ConversationEngine) -> some View {
        VStack(spacing: 8) {
            if engine.phase == .loadingModel {
                ModelLoadingBanner(service: mlxService, model: config.model)
            }

            if !engine.hints.isEmpty || engine.hintLoading {
                HintCard(
                    hints: engine.hints,
                    history: engine.hintHistory,
                    loading: engine.hintLoading,
                    onClose: { engine.clearHints() },
                    onRegenerate: { engine.regenerateHints() },
                    onTapWord: { engine.inspectWord($0) },
                    onSavePhrase: { phraseDraft = PhraseDraft(german: $0) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let prompt = engine.sayItPrompt {
                SayItPromptCard(
                    prompt: prompt,
                    accent: theme.accent,
                    isTyping: engine.inputMode == .type,
                    onHear: { SpeechService.shared.speak(prompt.german) },
                    onHearSlow: { SpeechService.shared.speak(prompt.german, slow: true) },
                    onUseAnyway: { engine.useSayItPromptAnyway() },
                    onClose: { engine.clearSayItPrompt() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let repair = engine.repairPrompt {
                NudgePromptCard(
                    prompt: repair,
                    accent: theme.accent,
                    isTyping: engine.inputMode == .type,
                    onHear: { SpeechService.shared.speak(repair.target) },
                    onHearSlow: { SpeechService.shared.speak(repair.target, slow: true) },
                    onReveal: { engine.revealRepair() },
                    onSkip: { engine.skipRepair() },
                    onClose: { engine.skipRepair() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Assist actions — hidden while a nudge is active so the mic stays focused on the retry.
            if engine.repairPrompt == nil {
                HStack(spacing: 10) {
                    AssistPill(icon: "lightbulb.fill", title: "Hint", tint: .yellow,
                               disabled: engine.isBusy || engine.isRecording) {
                        engine.requestHints()
                    }
                    AssistPill(icon: "character.bubble.fill", title: "Say it in German", tint: theme.accent,
                               disabled: engine.isBusy || engine.isRecording) {
                        // Needs the model to translate — load it first, then open the sheet.
                        if engine.requireModelReady(orRun: { showSayIt = true }) { showSayIt = true }
                    }
                }
            }

            let status = statusText(engine)
            if !status.isEmpty {
                Text(status)
                    .font(engine.isRecording ? .callout : .footnote)
                    .foregroundStyle(engine.isRecording ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 18)
                    .animation(.default, value: engine.isRecording)
            }

            if engine.inputMode == .type {
                typingInput(engine)
            } else {
                speakingInput(engine)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
        .background(alignment: .top) {
            // A soft scrim in the theme's own ground color instead of a hard bar: messages fade
            // out as they scroll beneath the mic, echoing the model sheet's masked-gradient look.
            Rectangle()
                .fill(appTheme == .klar ? AnyShapeStyle(Color(.systemBackground)) : appTheme.screenBackground)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.9), location: 0.3),
                            .init(color: .black, location: 0.55)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .padding(.top, -44)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: engine.isRecording)
        .animation(.easeInOut(duration: 0.25), value: engine.isModelReady)
        .animation(.easeInOut(duration: 0.2), value: engine.sayItPrompt)
        .animation(.easeInOut(duration: 0.2), value: engine.repairPrompt)
        .sheet(isPresented: $showSayIt) {
            SayItView(engine: engine)
        }
    }

    /// Tap-to-record: the mic, its waveform, and the punctuation controls that go with it.
    @ViewBuilder
    private func speakingInput(_ engine: ConversationEngine) -> some View {
        if engine.isRecording {
            RecordingControls(
                onPeriod:   { engine.addPunctuation(".") },
                onQuestion: { engine.addPunctuation("?") },
                onComma:    { engine.addPunctuation(",") },
                onRestart:  { engine.restartRecording() }
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }

        ZStack {
            if engine.isRecording {
                MicWaveform(level: engine.micLevel)
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }

            MicButton(
                isRecording: engine.isRecording,
                level: engine.micLevel,
                disabled: engine.isBusy,
                dimmed: !engine.isModelReady && !engine.isRecording,
                tint: theme.accent
            ) {
                engine.toggleRecording()
            }

            sessionControls(engine)
        }
    }

    /// The silent alternative: write the turn instead of speaking it. The session controls sit
    /// above the field here, so the composer stays right on top of the keyboard.
    @ViewBuilder
    private func typingInput(_ engine: ConversationEngine) -> some View {
        sessionControls(engine)

        ChatComposer(
            text: $draft,
            language: $composerLanguage,
            controller: composer,
            placeholder: composerPlaceholder(engine),
            accent: theme.accent,
            canTakeTurn: engine.canSubmitTyped,
            focusOnAppear: focusComposerOnAppear,
            onSend: { sendDraft(engine) },
            onSwitchToSpeaking: { switchInput(to: .speak, engine: engine) }
        )
    }

    /// The controls that flank the input whichever way the learner is taking their turn: load the
    /// model, switch input, review saved words, end the session.
    private func sessionControls(_ engine: ConversationEngine) -> some View {
        HStack(spacing: 12) {
            // An obvious one-tap loader, shown beside the mic only until the model is in memory.
            if !engine.isModelReady && !engine.isLoadingModel {
                LoadModelButton(model: config.model) { engine.loadModel() }
                    .transition(.scale.combined(with: .opacity))
            }
            if engine.inputMode == .speak {
                CircleIconButton(system: "keyboard.fill", tint: .secondary, disabled: engine.isBusy) {
                    switchInput(to: .type, engine: engine)
                }
                .accessibilityLabel("Type instead of speaking")
            }
            Spacer()
            if engine.savedWordCount > 0 {
                SavedWordsButton(count: engine.savedWordCount) {
                    showSavedWords = true
                }
            }
            if engine.conversation.messages.contains(where: { $0.isUser }) {
                CircleIconButton(system: "flag.checkered", tint: .secondary, disabled: engine.isBusy) {
                    showEndConfirm = true
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    /// Send the typed turn. The draft is only cleared once the engine takes it, so a turn typed
    /// before the model is loaded survives the load prompt.
    private func sendDraft(_ engine: ConversationEngine) {
        if engine.submitTyped(draft) { draft = "" }
    }

    /// Flip between mic and keyboard, keeping the keyboard out of the way of the mic.
    private func switchInput(to mode: ChatInputMode, engine: ConversationEngine) {
        guard mode != engine.inputMode else { return }
        focusComposerOnAppear = (mode == .type)
        if mode == .speak { composer.dismissKeyboard() }
        withAnimation(.snappy(duration: 0.25)) { engine.setInputMode(mode) }
    }

    /// What the empty composer asks for, which changes with what the chat is waiting on.
    private func composerPlaceholder(_ engine: ConversationEngine) -> String {
        if engine.repairPrompt != nil { return "Write the correction…" }
        if engine.sayItPrompt != nil { return "Write it in German…" }
        return "Write in German…"
    }

    /// The warm-up overlay covers a fresh interview until its opening line exists: through the
    /// model load and the recruiter's first turn. A resumed chat already has messages.
    private func showsRecruiterWarmup(_ engine: ConversationEngine) -> Bool {
        config.mode == .interview
            && engine.conversation.messages.isEmpty
            && (engine.phase == .loadingModel || engine.phase == .thinking)
    }

    private func statusText(_ engine: ConversationEngine) -> String {
        switch engine.phase {
        case .loadingModel: return mlxService.downloadInfo ?? "Loading model…"
        case .summarizing:  return "Preparing your report…"
        case .thinking:     return "…"
        case .listening:
            let t = engine.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Listening… tap to stop" : t
        case .idle:
            let typing = engine.inputMode == .type
            if !engine.isModelReady {
                return typing
                    ? "Send your line to load \(config.model.rawValue) and pick up where you left off"
                    : "Tap the mic to load \(config.model.rawValue) and pick up where you left off"
            }
            if engine.repairPrompt != nil {
                return typing ? "Write the corrected sentence" : "Tap the mic and say the corrected sentence"
            }
            if engine.conversation.messages.isEmpty { return "Getting ready…" }
            // The composer's own placeholder already says what to do; a caption above it would
            // only push the field further up the screen.
            return typing ? "" : "Tap to speak"
        }
    }

    private func endSession(_ engine: ConversationEngine) {
        Task {
            let result = await engine.endAndSummarize()
            summary = result ?? conversation.summary
            if summary != nil { showSummary = true }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func timeLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Assistant message

private struct AssistantMessageView: View {
    let message: ChatMessage
    let engine: ConversationEngine
    /// Called with German text the user selected from the reply to save as a phrase.
    let onSavePhrase: (String) -> Void

    private var isSpeaking: Bool { engine.speakingMessageID == message.id }
    private var theme: ModelTheme { engine.config.model.theme }

    /// The word range to highlight while this message is being read aloud.
    private var highlightRange: NSRange? {
        guard isSpeaking, engine.spokenText == message.text else { return nil }
        return engine.spokenRange
    }

    /// Dictionary-confirmed noun genders in this reply, for der/die/das tinting.
    private var genderTints: [(range: NSRange, gender: Gender)] {
        guard engine.config.genderColors else { return [] }
        return NounGenderTinter.tints(for: message.text, messageID: message.id)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ModelAvatar(model: engine.config.model)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    #if canImport(UIKit)
                    SelectableGermanText(
                        text: message.text,
                        textStyle: .title3,
                        highlightRange: highlightRange,
                        savedWords: engine.conversation.savedVocabWords,
                        nounTints: genderTints.map { ($0.range, UIColor($0.gender.color)) },
                        onTapWord: { engine.inspectWord($0) },
                        onTranslateSelection: { engine.inspectWord($0) },
                        onSavePhrase: { onSavePhrase($0) }
                    )
                    #else
                    TappableText(
                        text: message.text,
                        highlightRange: highlightRange,
                        savedWords: engine.conversation.savedVocabWords,
                        nounTints: genderTints.map { ($0.range, $0.gender.color) },
                        font: .title3,
                        onTapWord: { engine.inspectWord($0) }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    #endif

                    if engine.shouldShowTranslation(message) {
                        if let translation = message.translationText {
                            Text(translation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 10)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(theme.accent.opacity(0.6)).frame(width: 3)
                                }
                        } else {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("Translating…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .modelBubble(theme)

                HStack(spacing: 18) {
                    ActionIcon(system: isSpeaking ? "stop.fill" : "play.fill", tint: theme.accent) {
                        if isSpeaking { engine.stopPlayback() } else { engine.play(message, slow: false) }
                    }
                    ActionIcon(system: "tortoise.fill", tint: theme.accent) {
                        engine.play(message, slow: true)
                    }
                    if !engine.shouldShowTranslation(message) {
                        ActionIcon(system: "character.book.closed", tint: theme.accent) {
                            engine.revealTranslation(message)
                        }
                    }
                    ActionIcon(system: "doc.on.doc", tint: theme.accent) {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = message.text
                        #endif
                    }
                }
                .padding(.top, 2)
                .padding(.leading, 4)
            }

            Spacer(minLength: 20)
        }
    }
}

private struct AssistantStreamingView: View {
    let text: String
    let model: MLXModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ModelAvatar(model: model, glowing: true)
            Text(text.isEmpty ? " " : text)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
                .modelBubble(model.theme)
            Spacer(minLength: 20)
        }
    }
}

// MARK: - User message + correction

private struct UserMessageView: View {
    let message: ChatMessage
    let engine: ConversationEngine
    /// Called with German text the user selected from the correction to save as a phrase.
    let onSavePhrase: (String) -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // The corrected sentence stays hidden while an elicitation nudge is active for this turn
            // (the learner is being asked to fix it themselves); it appears once the nudge resolves.
            if message.hasCorrection, engine.activeRepairMessageID != message.id {
                CorrectionCard(message: message, engine: engine, onSavePhrase: onSavePhrase)
            }

            HStack {
                Spacer(minLength: 40)
                Group {
                    #if canImport(UIKit)
                    // No "Save phrase" here — your own words aren't "heard in the wild" phrases.
                    SelectableGermanText(
                        text: message.text,
                        textStyle: .title3,
                        savedWords: engine.conversation.savedVocabWords,
                        onTapWord: { engine.inspectWord($0) },
                        onTranslateSelection: { engine.inspectWord($0) }
                    )
                    #else
                    TappableText(
                        text: message.text,
                        savedWords: engine.conversation.savedVocabWords,
                        font: .title3,
                        onTapWord: { engine.inspectWord($0) }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    #endif
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(18), style: .continuous))
            }

            HStack(spacing: 8) {
                if message.confirmedClean {
                    Label("clean", systemImage: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Sentence confirmed correct")
                }
                if message.usedHint {
                    Label("used a hint", systemImage: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                if !message.targetWordsUsed.isEmpty {
                    Text("✓ used: \(message.targetWordsUsed.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if !message.reviewedWords.isEmpty {
                    Label("reviewed: \(message.reviewedWords.joined(separator: ", "))",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

private struct CorrectionCard: View {
    let message: ChatMessage
    let engine: ConversationEngine
    /// Called with selected German text to save it to the phrase library.
    let onSavePhrase: (String) -> Void

    @Environment(\.appTheme) private var appTheme

    private var corrected: String { message.correctedText ?? "" }
    private var note: String? { message.correctionNote }
    private var selfCorrected: Bool { message.selfCorrected }
    /// Understandable with minor slips — lead with the win before the fix.
    private var closeEnough: Bool {
        ConversationEngine.closeEnough(original: message.text, corrected: corrected)
    }
    /// Green when the learner repaired it themselves (elicitation), teal for a near-miss,
    /// orange for a handed-over fix.
    private var tint: Color { selfCorrected ? .green : (closeEnough ? .teal : .orange) }

    private var headerIcon: String {
        if selfCorrected { return "checkmark.seal.fill" }
        return closeEnough ? "checkmark.bubble.fill" : "pencil.and.outline"
    }

    private var headerText: String {
        if selfCorrected { return "You fixed this yourself" }
        return closeEnough ? "Fast richtig! One small fix" : "Suggested correction"
    }

    var body: some View {
        HStack {
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: headerIcon)
                    Text(headerText)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(tint)

                correctedGermanView

                if engine.shouldShowCorrectionTranslation(message) {
                    correctionMeaningView
                }

                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 14) {
                    Button {
                        SpeechService.shared.speak(corrected)
                    } label: {
                        Label("Hear it", systemImage: "speaker.wave.2.fill").font(.caption2)
                    }
                    Button {
                        SpeechService.shared.speak(corrected, slow: true)
                    } label: {
                        Label("Slow", systemImage: "tortoise.fill").font(.caption2)
                    }
                }
                .buttonStyle(.borderless)
                .padding(.top, 1)
            }
            .padding(12)
            .background(tint.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: appTheme.innerRadius(14), style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(14), style: .continuous))
        }
        // Fill in the English meaning lazily for reopened chats once the model is ready.
        .task(id: meaningTaskID) { engine.ensureCorrectionTranslation(message) }
    }

    /// The corrected German — tap a word to inspect it, or select a span to translate / save it.
    @ViewBuilder
    private var correctedGermanView: some View {
        #if canImport(UIKit)
        SelectableGermanText(
            text: corrected,
            textStyle: .callout,
            weight: .medium,
            onTapWord: { engine.inspectWord($0) },
            onTranslateSelection: { engine.inspectWord($0) },
            onSavePhrase: onSavePhrase
        )
        #else
        Text(corrected)
            .font(.callout.weight(.medium))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    /// The English meaning shown under the corrected sentence (or a spinner while it loads).
    @ViewBuilder
    private var correctionMeaningView: some View {
        if let meaning = message.correctionTranslationText, !meaning.isEmpty {
            Text(meaning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Rectangle().fill(tint.opacity(0.5)).frame(width: 2)
                }
                .fixedSize(horizontal: false, vertical: true)
        } else if engine.isTranslatingCorrection(message) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Translating…").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Changes when the model becomes ready, the turn settles, or the meaning arrives — so the
    /// lazy ensure re-fires for reopened chats once it's safe to run.
    private var meaningTaskID: String {
        "\(engine.isModelReady)-\(engine.phase)-\(message.correctionTranslationText == nil)"
    }
}

// MARK: - Mic + small controls

private struct MicButton: View {
    let isRecording: Bool
    let level: Double
    let disabled: Bool
    /// Greyed-out but still tappable — used when the model isn't loaded yet, so a tap can prompt
    /// the user to load it rather than recording.
    var dimmed: Bool = false
    var tint: Color = .accentColor
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    // A soft glow that swells with the voice, in place of the old flat halo.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.red.opacity(0.35), Color.red.opacity(0.02)],
                                center: .center, startRadius: 18, endRadius: 58
                            )
                        )
                        .frame(width: 116, height: 116)
                        .scaleEffect(0.72 + CGFloat(level) * 0.45)
                        .animation(.easeOut(duration: 0.12), value: level)

                    if !reduceMotion {
                        SonarRipples()
                    }
                }
                Circle()
                    .fill(isRecording ? Color.red : tint)
                    .frame(width: 64, height: 64)
                    .shadow(color: (isRecording ? Color.red : tint).opacity(0.35),
                            radius: isRecording ? 10 : 6, y: 3)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isRecording)
        }
        .buttonStyle(SpringPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : (dimmed ? 0.55 : 1))
        .frame(width: 96, height: 76)
    }
}

/// Two slow, expanding rings that fade as they grow — a quiet "the mic is live" pulse behind the
/// record button. Skipped entirely under Reduce Motion.
private struct SonarRipples: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ripple(delay: 0)
            ripple(delay: 1.1)
        }
        .allowsHitTesting(false)
        .onAppear { animate = true }
    }

    private func ripple(delay: Double) -> some View {
        Circle()
            .stroke(Color.red.opacity(animate ? 0 : 0.3), lineWidth: 1.5)
            .frame(width: 68, height: 68)
            .scaleEffect(animate ? 1.85 : 1)
            .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(delay), value: animate)
    }
}

/// A gentle press-down spring shared by the round controls, so taps feel tactile without any
/// added chrome.
private struct SpringPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// A live, mirrored level history radiating out from behind the mic while recording — the newest
/// sample lands beside the button and older ones drift toward the edges, Voice-Memos style.
private struct MicWaveform: View {
    let level: Double

    @State private var samples: [CGFloat] = []
    @State private var lastAppend = Date.distantPast

    /// Bars kept per side; at 5pt spacing this comfortably fills a phone width.
    private let maxBars = 30

    var body: some View {
        Canvas { context, size in
            let barWidth: CGFloat = 3
            let step: CGFloat = 5
            let midX = size.width / 2
            let midY = size.height / 2
            for (i, sample) in samples.enumerated() {
                let height = max(3, sample * size.height)
                let age = CGFloat(i) / CGFloat(max(samples.count, 1))
                let opacity = 0.4 * (1 - age)
                // Start clear of the 64pt button: first bar ~40pt from center.
                let offset = CGFloat(i + 8) * step
                for x in [midX + offset, midX - offset] {
                    let rect = CGRect(x: x - barWidth / 2, y: midY - height / 2,
                                      width: barWidth, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                                 with: .color(.red.opacity(opacity)))
                }
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82), .init(color: .clear, location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .allowsHitTesting(false)
        .onChange(of: level) { _, newValue in
            let clamped = CGFloat(min(max(newValue, 0), 1))
            let now = Date()
            // Throttle to ~20 bars/s so the scroll speed stays steady regardless of update rate;
            // between appends keep the loudest peak so transients still register.
            guard now.timeIntervalSince(lastAppend) > 0.045 else {
                if let first = samples.first, clamped > first { samples[0] = clamped }
                return
            }
            lastAppend = now
            samples.insert(clamped, at: 0)
            if samples.count > maxBars { samples.removeLast() }
        }
    }
}

/// A prominent, icon-only loader shown next to the mic when this conversation's model isn't in
/// memory yet. It carries the model's own logo plus a download badge so it's obvious what a tap
/// will load, and pulses gently to invite the tap. Tapping loads the model directly.
private struct LoadModelButton: View {
    let model: MLXModel
    let action: () -> Void

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var theme: ModelTheme { model.theme }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.18))
                    .overlay(Circle().strokeBorder(theme.accent.opacity(0.5), lineWidth: 1.5))
                    .frame(width: 56, height: 56)

                model.logoImage
                    .resizable().scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(theme.accent)
                            .background(Circle().fill(Color(.systemBackground)))
                            .offset(x: 5, y: 5)
                    }
            }
            .scaleEffect(pulse ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .frame(width: 64, height: 64)
        .accessibilityLabel("Load \(model.rawValue)")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Controls shown while recording: insert end punctuation, or scrap the turn and retry.
struct RecordingControls: View {
    let onPeriod: () -> Void
    let onQuestion: () -> Void
    let onComma: () -> Void
    let onRestart: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 12) {
            PunctuationButton(symbol: ",", action: onComma)
                .staggeredIn(0)
            PunctuationButton(symbol: ".", action: onPeriod)
                .staggeredIn(1)
            PunctuationButton(symbol: "?", action: onQuestion)
                .staggeredIn(2)
            Button(action: onRestart) {
                Label("Restart", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Color(.secondarySystemBackground), in: appTheme.pillShape)
            }
            .buttonStyle(SpringPressStyle())
            .staggeredIn(3)
        }
    }
}

/// Pops a control in with a small springy scale, delayed by its position — used so the recording
/// controls ripple into place left-to-right instead of appearing as one block. Under Reduce
/// Motion the content just shows immediately.
private struct StaggeredIn: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.7)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.65).delay(Double(index) * 0.05)) {
                    shown = true
                }
            }
            .onDisappear { shown = false }
    }
}

private extension View {
    func staggeredIn(_ index: Int) -> some View { modifier(StaggeredIn(index: index)) }
}

struct PunctuationButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
        .buttonStyle(SpringPressStyle())
        .accessibilityLabel(accessibilityName)
    }

    private var accessibilityName: String {
        switch symbol {
        case "?": "Add question mark"
        case ",": "Add comma"
        default:  "Add period"
        }
    }
}

private struct CircleIconButton: View {
    let system: String
    var tint: Color = .accentColor
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3)
                .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                .frame(width: 48, height: 48)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
        }
        .buttonStyle(SpringPressStyle())
        .disabled(disabled)
    }
}

private struct ActionIcon: View {
    let system: String
    var tint: Color = .accentColor
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.callout)
                .foregroundStyle(tint)
                .frame(width: 34, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Misc subviews

private struct TypingIndicator: View {
    let model: MLXModel
    @State private var phase = 0.0

    private var theme: ModelTheme { model.theme }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ModelAvatar(model: model, glowing: true)
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 7, height: 7)
                        .opacity(opacity(for: i))
                }
            }
            .modelBubble(theme)
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { phase = 1 }
        }
    }

    private func opacity(for i: Int) -> Double {
        let base = (phase + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
        return 0.3 + 0.7 * abs(sin(base * .pi))
    }
}

private struct ModelLoadingBanner: View {
    var service: MLXGenerationService
    let model: MLXModel

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(service.downloadInfo ?? "Loading \(model.rawValue)…")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let bytes = service.downloadBytesInfo {
                    Text(bytes).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if let progress = service.downloadProgress, progress > 0 {
                ProgressView(value: progress)
            }
        }
        .tint(model.theme.accent)
        .padding(.horizontal, 24)
    }
}

/// Bookmark button with a count badge, shown near the mic when words have been saved.
private struct SavedWordsButton: View {
    let count: Int
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "bookmark.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
                .overlay(alignment: .topTrailing) {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(appTheme.pillShape.fill(.red))
                        .offset(x: 6, y: -4)
                }
        }
        .buttonStyle(SpringPressStyle())
    }
}

/// The list of words saved during this conversation, with swipe-to-remove.
private struct SavedWordsSheet: View {
    let engine: ConversationEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if engine.conversation.savedVocab.isEmpty {
                    ContentUnavailableView(
                        "No saved words yet",
                        systemImage: "bookmark",
                        description: Text("Tap a word in the chat to save it.")
                    )
                } else {
                    Section {
                        ForEach(engine.conversation.savedVocab) { item in
                            HStack {
                                Text(item.german)
                                Spacer()
                                Text(item.english).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            let items = engine.conversation.savedVocab
                            for index in offsets { engine.removeSavedWord(items[index].german) }
                        }
                    } footer: {
                        Text("These appear in your end-of-session report, where you can add them to a deck. Swipe to remove.")
                    }
                }
            }
            .navigationTitle("Saved words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct ErrorBanner: View {
    let text: String
    /// When set, a "Try again" button is shown to re-trigger the AI response.
    var onRetry: (() -> Void)? = nil

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onRetry {
                Button(action: onRetry) {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(.orange)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(10)))
    }
}

/// A turn the AI still owes, from a session that ended before its reply landed — a termination, a
/// memory eviction, a failed generation. Styled as information rather than as a warning, because
/// nothing is wrong: the conversation is simply waiting on a tap.
private struct StrandedTurnBanner: View {
    let text: String
    let onContinue: () -> Void
    let onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "arrow.trianglehead.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Button(action: onContinue) {
                    Label("Get a reply", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                Button("Not now", action: onDismiss)
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .tint(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(10)))
    }
}

/// Inline hint(s) shown just above the mic, so the user can read them and record at the same time.
/// Older batches stay reachable: the chevrons (or a side swipe) page back through this session's
/// earlier hints, so a regenerate or a new turn never loses a line the learner wanted.
private struct HintCard: View {
    let hints: [HintSuggestion]
    /// Earlier batches from this session, newest first (see `ConversationEngine.hintHistory`).
    var history: [[HintSuggestion]] = []
    let loading: Bool
    let onClose: () -> Void
    /// Ask for a fresh batch of suggestions when the first ones don't fit.
    var onRegenerate: () -> Void = {}
    /// Double-tap a word in a hint to inspect it.
    var onTapWord: (String) -> Void = { _ in }
    /// Select a span in a hint to save it as a phrase.
    var onSavePhrase: (String) -> Void = { _ in }

    @Environment(\.appTheme) private var appTheme

    /// 0 = the current batch, 1… = history batches (newest first).
    @State private var page = 0

    /// Current batch first, then history — skipping an empty current batch while loading.
    private var pages: [[HintSuggestion]] {
        (hints.isEmpty ? history : [hints] + history).filter { !$0.isEmpty }
    }

    private var shownHints: [HintSuggestion] {
        pages.indices.contains(page) ? pages[page] : (pages.first ?? hints)
    }

    /// Paging back through history is only offered when there is somewhere to go.
    private var canPage: Bool { pages.count > 1 }
    private var viewingEarlier: Bool { canPage && page > 0 && !hints.isEmpty }

    private var title: String {
        if viewingEarlier { return "Earlier hints" }
        return shownHints.count > 1 ? "Hints — you could say" : "Hint — you could say"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: viewingEarlier ? "clock.arrow.circlepath" : "lightbulb.fill")
                    .foregroundStyle(viewingEarlier ? Color.secondary : .yellow)
                Text(title)
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if canPage, !loading {
                    HStack(spacing: 2) {
                        Button { page = min(page + 1, pages.count - 1) } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(page < pages.count - 1 ? Color.secondary : Color(.tertiaryLabel))
                        }
                        .buttonStyle(.plain)
                        .disabled(page >= pages.count - 1)
                        .accessibilityLabel("Earlier hints")

                        Text("\(pages.count - page)/\(pages.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)

                        Button { page = max(page - 1, 0) } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(page > 0 ? Color.secondary : Color(.tertiaryLabel))
                        }
                        .buttonStyle(.plain)
                        .disabled(page == 0)
                        .accessibilityLabel("Newer hints")
                    }
                    .padding(.trailing, 4)
                }
                if !loading, page == 0 {
                    Button { onRegenerate() } label: {
                        Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New suggestions")
                }
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking of suggestions…").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(shownHints.enumerated()), id: \.element.id) { index, h in
                    if index > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            #if canImport(UIKit)
                            SelectableGermanText(
                                text: h.german,
                                textStyle: .callout,
                                weight: .medium,
                                onTapWord: { onTapWord($0) },
                                onTranslateSelection: { onTapWord($0) },
                                onSavePhrase: { onSavePhrase($0) }
                            )
                            #else
                            Text(h.german)
                                .font(.callout.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                            #endif
                            Spacer()
                            Button { SpeechService.shared.speak(h.german) } label: {
                                Image(systemName: "speaker.wave.2.fill").font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        if let en = h.english, !en.isEmpty {
                            Text(en).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.yellow.opacity(viewingEarlier ? 0.06 : 0.10))
        .overlay(
            RoundedRectangle(cornerRadius: appTheme.innerRadius(14), style: .continuous)
                .strokeBorder(Color.yellow.opacity(viewingEarlier ? 0.2 : 0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(14), style: .continuous))
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.15), value: page)
        // A fresh batch always lands the card back on the newest page.
        .onChange(of: hints.first?.id) { _, _ in page = 0 }
        // Side-swipe pages through history: left = older, right = newer.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 {
                        page = min(page + 1, max(pages.count - 1, 0))
                    } else {
                        page = max(page - 1, 0)
                    }
                }
        )
    }
}

/// Shows a "Say it in German" phrase above the mic so the learner can say it themselves — echoing
/// the hint card. After a spoken attempt that misses, it flips to a gentle coaching state that
/// spells out the target (with slow playback) and shows what was heard, so they can try again.
private struct SayItPromptCard: View {
    let prompt: SayItPrompt
    let accent: Color
    /// The learner is writing their attempt, not speaking it — the instructions have to match.
    let isTyping: Bool
    let onHear: () -> Void
    let onHearSlow: () -> Void
    let onUseAnyway: () -> Void
    let onClose: () -> Void

    @Environment(\.appTheme) private var appTheme

    private var missed: Bool { prompt.matched == false }
    private var tint: Color { missed ? .orange : accent }

    private var headline: String {
        if missed { return isTyping ? "Almost — here's how it goes" : "Almost — here's how to say it" }
        return isTyping ? "Write it yourself" : "Say it out loud"
    }

    private var instruction: String {
        if isTyping { return missed ? "Write it again below" : "Write it below" }
        return missed ? "Tap the mic to try again" : "Tap the mic and say it"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: missed ? "exclamationmark.bubble.fill" : "character.bubble.fill")
                    .foregroundStyle(tint)
                Text(headline)
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if missed, let heard = prompt.heardText, !heard.isEmpty {
                Text("\(isTyping ? "You wrote" : "You said"): \(heard)")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(prompt.german)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { onHear() } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.caption)
                }
                .buttonStyle(.borderless)
                if missed {
                    Button { onHearSlow() } label: {
                        Image(systemName: "tortoise.fill").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let en = prompt.english, !en.isEmpty, !missed {
                Text(en).font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Label(instruction, systemImage: isTyping ? "keyboard.fill" : "mic.fill")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button { onUseAnyway() } label: {
                    Text("Use it anyway").font(.caption2.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: appTheme.innerRadius(14), style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(14), style: .continuous))
        .padding(.horizontal, 16)
    }
}

/// The elicitation ("Nudge me") card: a targeted question that lets the learner repair their own
/// mistake by saying the corrected sentence back. Mirrors `SayItPromptCard`'s try-again loop, but
/// the answer stays hidden until they miss or ask to see it.
private struct NudgePromptCard: View {
    let prompt: RepairPrompt
    let accent: Color
    /// The learner is writing their repair, not speaking it.
    let isTyping: Bool
    let onHear: () -> Void
    let onHearSlow: () -> Void
    let onReveal: () -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    @Environment(\.appTheme) private var appTheme

    private var missed: Bool { prompt.matched == false }
    private var revealed: Bool { prompt.revealed }
    private var tint: Color { missed ? .orange : accent }

    private var instruction: String {
        if isTyping { return missed ? "Write the fix below" : "Write the corrected sentence" }
        return missed ? "Tap the mic to try again" : "Tap the mic and say it correctly"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: missed ? "exclamationmark.bubble.fill" : "questionmark.bubble.fill")
                    .foregroundStyle(tint)
                Text(missed ? "Almost — try the fix" : "Your turn — fix it yourself")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // The German nudge question — always shown; it's the whole point of this mode.
            Text(prompt.hint)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            if missed, let heard = prompt.heardText, !heard.isEmpty {
                Text("\(isTyping ? "You wrote" : "You said"): \(heard)")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The answer — revealed only after a miss or an explicit "Show me".
            if revealed {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(prompt.target)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { onHear() } label: {
                        Image(systemName: "speaker.wave.2.fill").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    Button { onHearSlow() } label: {
                        Image(systemName: "tortoise.fill").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                if let note = prompt.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Label(instruction, systemImage: isTyping ? "keyboard.fill" : "mic.fill")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if !revealed {
                    Button { onReveal() } label: {
                        Text("Show me").font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
                Button { onSkip() } label: {
                    Text(revealed ? "Continue" : "Skip").font(.caption2.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: appTheme.innerRadius(14), style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(14), style: .continuous))
        .padding(.horizontal, 16)
    }
}

/// A pill-style assist action button (Hint, Say it in German).
private struct AssistPill: View {
    let icon: String
    let title: String
    var tint: Color = .accentColor
    let disabled: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(appTheme.pillShape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Brand styling

/// The model's logo in a brand-ringed circle. When `glowing` it pulses with the model's accent —
/// used while the model is generating a reply.
private struct ModelAvatar: View {
    let model: MLXModel
    var size: CGFloat = 30
    var glowing: Bool = false

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ModelTheme { model.theme }

    var body: some View {
        model.logoImage
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(theme.accent.opacity(0.55), lineWidth: 1.5))
            .background(
                Circle()
                    .fill(theme.accent)
                    .opacity(glowing ? (pulse ? 0.35 : 0.12) : 0)
                    .blur(radius: 9)
                    .scaleEffect(glowing ? (pulse ? 1.55 : 1.1) : 1)
            )
            .onAppear {
                guard glowing, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

/// Wraps content in a soft, model-colored chat bubble. A `ViewModifier` (not a plain method) so it
/// can read `\.appTheme` and reshape the bubble's corners per theme while keeping the model-brand fill.
private struct ModelBubble: ViewModifier {
    let theme: ModelTheme
    @Environment(\.appTheme) private var appTheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(18), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: appTheme.innerRadius(18), style: .continuous)
                    .strokeBorder(theme.accent.opacity(0.20), lineWidth: 1)
            )
    }
}

private extension View {
    /// Wraps content in a soft, model-colored chat bubble.
    func modelBubble(_ theme: ModelTheme) -> some View {
        modifier(ModelBubble(theme: theme))
    }
}
