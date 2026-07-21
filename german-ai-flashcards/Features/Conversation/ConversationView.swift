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

    @State private var engine: ConversationEngine?
    @State private var summary: ConversationSummary?
    @State private var showSummary = false
    @State private var showEndConfirm = false
    @State private var showSayIt = false
    @State private var showSavedWords = false
    @State private var showHelp = false
    /// A span the user selected from a correction and wants to save to their phrase library.
    @State private var phraseDraft: PhraseDraft?

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
            inputArea(engine)
        }
        .background {
            ZStack(alignment: .top) {
                Color(.systemBackground)
                // An animated brand wash at the top, echoing the model sheet styling. It gently
                // intensifies while the model is generating a reply.
                ModelBrandWash(palette: theme.palette, animated: !reduceMotion)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .mask(
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    )
                    .opacity(engine.phase == .thinking ? 0.5 : 0.28)
                    .animation(.easeInOut(duration: 0.6), value: engine.phase)
            }
            .ignoresSafeArea()
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

                Toggle("Auto-play replies", isOn: $modelManager.autoPlayReplies)
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
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: engine.conversation.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: engine.streamingReply) { _, _ in scrollToBottom(proxy) }
            .onChange(of: engine.phase) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func inputArea(_ engine: ConversationEngine) -> some View {
        VStack(spacing: 12) {
            if engine.phase == .loadingModel {
                ModelLoadingBanner(service: mlxService, model: config.model)
            }

            if !engine.hints.isEmpty || engine.hintLoading {
                HintCard(
                    hints: engine.hints,
                    loading: engine.hintLoading,
                    onClose: { engine.clearHints() },
                    onTapWord: { engine.inspectWord($0) },
                    onSavePhrase: { phraseDraft = PhraseDraft(german: $0) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let prompt = engine.sayItPrompt {
                SayItPromptCard(
                    prompt: prompt,
                    accent: theme.accent,
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

            Text(statusText(engine))
                .font(.callout)
                .foregroundStyle(engine.isRecording ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 24)
                .animation(.default, value: engine.isRecording)

            if engine.isRecording {
                RecordingControls(
                    onPeriod:   { engine.addPunctuation(".") },
                    onQuestion: { engine.addPunctuation("?") },
                    onRestart:  { engine.restartRecording() }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            ZStack {
                MicButton(
                    isRecording: engine.isRecording,
                    level: engine.micLevel,
                    disabled: engine.isBusy,
                    dimmed: !engine.isModelReady && !engine.isRecording,
                    tint: theme.accent
                ) {
                    engine.toggleRecording()
                }

                HStack(spacing: 12) {
                    // An obvious one-tap loader, shown beside the mic only until the model is in memory.
                    if !engine.isModelReady && !engine.isLoadingModel {
                        LoadModelButton(model: config.model) { engine.loadModel() }
                            .transition(.scale.combined(with: .opacity))
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
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: engine.isRecording)
        .animation(.easeInOut(duration: 0.25), value: engine.isModelReady)
        .animation(.easeInOut(duration: 0.2), value: engine.sayItPrompt)
        .animation(.easeInOut(duration: 0.2), value: engine.repairPrompt)
        .sheet(isPresented: $showSayIt) {
            SayItView(engine: engine)
        }
    }

    // MARK: - Helpers

    private func statusText(_ engine: ConversationEngine) -> String {
        switch engine.phase {
        case .loadingModel: return mlxService.downloadInfo ?? "Loading model…"
        case .summarizing:  return "Preparing your report…"
        case .thinking:     return "…"
        case .listening:
            let t = engine.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Listening… tap to stop" : t
        case .idle:
            if !engine.isModelReady {
                return "Tap the mic to load \(config.model.rawValue) and pick up where you left off"
            }
            if engine.repairPrompt != nil {
                return "Tap the mic and say the corrected sentence"
            }
            return engine.conversation.messages.isEmpty ? "Getting ready…" : "Tap to speak"
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
                        onTapWord: { engine.inspectWord($0) },
                        onTranslateSelection: { engine.inspectWord($0) },
                        onSavePhrase: { onSavePhrase($0) }
                    )
                    #else
                    TappableText(
                        text: message.text,
                        highlightRange: highlightRange,
                        savedWords: engine.conversation.savedVocabWords,
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
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 8) {
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

    private var corrected: String { message.correctedText ?? "" }
    private var note: String? { message.correctionNote }
    private var selfCorrected: Bool { message.selfCorrected }
    /// Green when the learner repaired it themselves (elicitation), orange for a handed-over fix.
    private var tint: Color { selfCorrected ? .green : .orange }

    var body: some View {
        HStack {
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: selfCorrected ? "checkmark.seal.fill" : "pencil.and.outline")
                    Text(selfCorrected ? "You fixed this yourself" : "Suggested correction")
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

                Button {
                    SpeechService.shared.speak(corrected)
                } label: {
                    Label("Hear it", systemImage: "speaker.wave.2.fill").font(.caption2)
                }
                .buttonStyle(.borderless)
                .padding(.top, 1)
            }
            .padding(12)
            .background(tint.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: 84 + CGFloat(level) * 36, height: 84 + CGFloat(level) * 36)
                        .animation(.easeOut(duration: 0.12), value: level)
                }
                Circle()
                    .fill(isRecording ? Color.red : tint)
                    .frame(width: 76, height: 76)
                    .shadow(radius: isRecording ? 6 : 2)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : (dimmed ? 0.55 : 1))
        .frame(width: 120, height: 120)
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
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PunctuationButton(symbol: ".", action: onPeriod)
            PunctuationButton(symbol: "?", action: onQuestion)
            Button(action: onRestart) {
                Label("Restart", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Color(.secondarySystemBackground), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
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
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "?" ? "Add question mark" : "Add period")
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
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct ActionIcon: View {
    let system: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.callout)
                .foregroundStyle(tint)
                .frame(width: 34, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                        .background(Capsule().fill(.red))
                        .offset(x: 6, y: -4)
                }
        }
        .buttonStyle(.plain)
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Inline hint(s) shown just above the mic, so the user can read them and record at the same time.
private struct HintCard: View {
    let hints: [HintSuggestion]
    let loading: Bool
    let onClose: () -> Void
    /// Double-tap a word in a hint to inspect it.
    var onTapWord: (String) -> Void = { _ in }
    /// Select a span in a hint to save it as a phrase.
    var onSavePhrase: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                Text(hints.count > 1 ? "Hints — you could say" : "Hint — you could say")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
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
                ForEach(Array(hints.enumerated()), id: \.element.id) { index, h in
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
        .background(Color.yellow.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}

/// Shows a "Say it in German" phrase above the mic so the learner can say it themselves — echoing
/// the hint card. After a spoken attempt that misses, it flips to a gentle coaching state that
/// spells out the target (with slow playback) and shows what was heard, so they can try again.
private struct SayItPromptCard: View {
    let prompt: SayItPrompt
    let accent: Color
    let onHear: () -> Void
    let onHearSlow: () -> Void
    let onUseAnyway: () -> Void
    let onClose: () -> Void

    private var missed: Bool { prompt.matched == false }
    private var tint: Color { missed ? .orange : accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: missed ? "exclamationmark.bubble.fill" : "character.bubble.fill")
                    .foregroundStyle(tint)
                Text(missed ? "Almost — here's how to say it" : "Say it out loud")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if missed, let heard = prompt.heardText, !heard.isEmpty {
                Text("You said: \(heard)")
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
                Label(missed ? "Tap the mic to try again" : "Tap the mic and say it",
                      systemImage: "mic.fill")
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}

/// The elicitation ("Nudge me") card: a targeted question that lets the learner repair their own
/// mistake by saying the corrected sentence back. Mirrors `SayItPromptCard`'s try-again loop, but
/// the answer stays hidden until they miss or ask to see it.
private struct NudgePromptCard: View {
    let prompt: RepairPrompt
    let accent: Color
    let onHear: () -> Void
    let onHearSlow: () -> Void
    let onReveal: () -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    private var missed: Bool { prompt.matched == false }
    private var revealed: Bool { prompt.revealed }
    private var tint: Color { missed ? .orange : accent }

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
                Text("You said: \(heard)")
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
                Label(missed ? "Tap the mic to try again" : "Tap the mic and say it correctly",
                      systemImage: "mic.fill")
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
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

private extension View {
    /// Wraps content in a soft, model-colored chat bubble.
    func modelBubble(_ theme: ModelTheme) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(theme.accent.opacity(0.20), lineWidth: 1)
            )
    }
}
