import DieKarteiCore
import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

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

    @State private var engine: ConversationEngine?
    @State private var summary: ConversationSummary?
    @State private var showSummary = false
    @State private var showEndConfirm = false
    @State private var showSayIt = false
    @State private var showSavedWords = false

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

    @ViewBuilder
    private func chat(_ engine: ConversationEngine) -> some View {
        VStack(spacing: 0) {
            topBar(engine)
            Divider()
            messageList(engine)
            inputArea(engine)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: Binding(
            get: { engine.inspectedWord != nil },
            set: { if !$0 { engine.dismissInspector() } }
        )) {
            WordInspectorSheet(engine: engine)
        }
        .sheet(isPresented: $showSavedWords) {
            SavedWordsSheet(engine: engine)
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

            Menu {
                Toggle("Auto-play replies", isOn: $modelManager.autoPlayReplies)
                Button {
                    showEndConfirm = true
                } label: {
                    Label("End & summarize", systemImage: "flag.checkered")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
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
                            UserMessageView(message: message, engine: engine)
                        } else {
                            AssistantMessageView(message: message, engine: engine)
                        }
                    }

                    if engine.phase == .thinking {
                        if engine.streamingReply.isEmpty {
                            TypingIndicator(logo: config.model.logoName)
                        } else {
                            AssistantStreamingView(text: engine.streamingReply, logo: config.model.logoName)
                        }
                    }

                    if let error = engine.errorMessage {
                        ErrorBanner(text: error)
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
                    onClose: { engine.clearHints() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Assist actions
            HStack(spacing: 10) {
                AssistPill(icon: "lightbulb.fill", title: "Hint", tint: .yellow,
                           disabled: engine.isBusy || engine.isRecording) {
                    engine.requestHints()
                }
                AssistPill(icon: "character.bubble.fill", title: "Say it in German", tint: .accentColor,
                           disabled: engine.isBusy || engine.isRecording) {
                    showSayIt = true
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

            ZStack {
                MicButton(
                    isRecording: engine.isRecording,
                    level: engine.micLevel,
                    disabled: engine.isBusy
                ) {
                    engine.toggleRecording()
                }

                HStack(spacing: 12) {
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
                .padding(.trailing, 24)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
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

    private var isSpeaking: Bool { engine.speakingMessageID == message.id }

    /// The word range to highlight while this message is being read aloud.
    private var highlightRange: NSRange? {
        guard isSpeaking, engine.spokenText == message.text else { return nil }
        return engine.spokenRange
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(engine.config.model.logoName)
                .resizable().scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 8) {
                TappableText(
                    text: message.text,
                    highlightRange: highlightRange,
                    savedWords: engine.conversation.savedVocabWords,
                    font: .title3,
                    onTapWord: { engine.inspectWord($0) }
                )
                .fixedSize(horizontal: false, vertical: true)

                if engine.shouldShowTranslation(message) {
                    if let translation = message.translationText {
                        Text(translation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 10)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color.accentColor.opacity(0.4)).frame(width: 3)
                            }
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Translating…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 18) {
                    ActionIcon(system: isSpeaking ? "stop.fill" : "play.fill") {
                        if isSpeaking { engine.stopPlayback() } else { engine.play(message, slow: false) }
                    }
                    ActionIcon(system: "tortoise.fill") {
                        engine.play(message, slow: true)
                    }
                    if !engine.shouldShowTranslation(message) {
                        ActionIcon(system: "character.book.closed") {
                            engine.revealTranslation(message)
                        }
                    }
                    ActionIcon(system: "doc.on.doc") {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = message.text
                        #endif
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 20)
        }
    }
}

private struct AssistantStreamingView: View {
    let text: String
    let logo: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(logo)
                .resizable().scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
            Text(text.isEmpty ? " " : text)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 20)
        }
    }
}

// MARK: - User message + correction

private struct UserMessageView: View {
    let message: ChatMessage
    let engine: ConversationEngine

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if message.hasCorrection {
                CorrectionCard(
                    corrected: message.correctedText ?? "",
                    note: message.correctionNote
                )
            }

            HStack {
                Spacer(minLength: 40)
                TappableText(
                    text: message.text,
                    savedWords: engine.conversation.savedVocabWords,
                    font: .title3,
                    onTapWord: { engine.inspectWord($0) }
                )
                .fixedSize(horizontal: false, vertical: true)
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
            }
        }
    }
}

private struct CorrectionCard: View {
    let corrected: String
    let note: String?

    var body: some View {
        HStack {
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.outline")
                    Text("Suggested correction").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.orange)

                Text(corrected)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

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
            .background(Color.orange.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Mic + small controls

private struct MicButton: View {
    let isRecording: Bool
    let level: Double
    let disabled: Bool
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
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 76, height: 76)
                    .shadow(radius: isRecording ? 6 : 2)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .frame(width: 120, height: 120)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.callout)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 30)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Misc subviews

private struct TypingIndicator: View {
    let logo: String
    @State private var phase = 0.0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(logo)
                .resizable().scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(opacity(for: i))
                }
            }
            .padding(.top, 10)
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
        .padding(.horizontal, 24)
    }
}

/// Shown when the user taps a word — its translation, hear-it, and a save-to-library action.
private struct WordInspectorSheet: View {
    let engine: ConversationEngine

    var body: some View {
        NavigationStack {
            Group {
                if let inspected = engine.inspectedWord {
                    content(inspected)
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { engine.dismissInspector() }
                }
            }
            .presentationDetents([.height(300)])
        }
    }

    @ViewBuilder
    private func content(_ inspected: InspectedWord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(inspected.word)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if inspected.loading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Translating…").foregroundStyle(.secondary)
                }
            } else if let translation = inspected.translation, !translation.isEmpty {
                Text(translation).font(.title3).foregroundStyle(.secondary)
            } else {
                Text("No translation found.").font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button { SpeechService.shared.speak(inspected.word) } label: {
                    Label("Hear it", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)

                if inspected.saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button { engine.saveInspectedWord() } label: {
                        Label("Save to library", systemImage: "tray.and.arrow.down.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inspected.loading)
                }
            }

            Text("Saved words appear in your end-of-session report, where you can add them to a deck.")
                .font(.caption2).foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
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
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                            Text(h.german)
                                .font(.callout.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
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
