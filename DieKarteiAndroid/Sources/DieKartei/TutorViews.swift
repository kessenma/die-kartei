@testable import DieKarteiCore
import GermanVoice
import SwiftUI

// The tutor screens on Android, on the iOS app's own prompts and parsers (ConversationPrompts):
// the same system prompts, the same FIX/WHY format, the same echo guard. Only the runtime differs.

// MARK: - Settings ▸ Tutor Model

struct TutorModelView: View {
    @State var store = TutorStore.shared

    var body: some View {
        List {
            Section {
                ForEach(TutorModelFile.all) { file in
                    Button {
                        store.selectedID = file.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.model.displayName)
                                    .foregroundStyle(Color.primary)
                                Text(detail(file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.selectedID == file.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } footer: {
                Text("Downloads come once the models are on Hugging Face. Until then, copy the files in with adb (see DieKarteiAndroid/README.md).")
            }
            Section("Engine") {
                Button("Load the model") {
                    Task { _ = await store.ensureLoaded() }
                }
                .disabled(store.available == nil || store.state == .loading)
                Text(stateText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if store.threads > 0 {
                    Text("\(store.threads) threads, on the fast cores")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let stats = store.lastStats {
                    Text("Last answer: \(stats.caption)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Tutor Model")
        .onAppear { store.refreshFiles() }
    }

    func detail(_ file: TutorModelFile) -> String {
        let where_ = store.isOnDevice(file) ? "on this phone" : "not on this phone yet"
        return String(format: "%.1f GB", file.sizeGB) + " · \(file.minimumRAMGB) GB RAM or more · \(where_)"
    }

    var stateText: String {
        switch store.state {
        case .idle: store.available == nil ? "No model file on this phone yet." : "Not loaded."
        case .loading: "Loading…"
        case .ready: "Loaded and ready."
        case .failed(let message): message
        }
    }
}

// MARK: - Satz prüfen

/// One sentence, one correction: the conversation's correction pass on its own.
struct SatzPruefenView: View {
    @State var store = TutorStore.shared
    @State var sentence = ""
    @State var result: ConversationPrompts.CorrectionResult?
    @State var checking = false
    @State var errorText: String?

    var body: some View {
        List {
            Section {
                TextField("Ein Satz auf Deutsch", text: $sentence, axis: .vertical)
                Button(checking ? "Prüfe…" : "Prüfen") { Task { await check() } }
                    .disabled(checking || sentence.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("Model: \(store.available?.model.displayName ?? "none — pick one in Settings ▸ Tutor Model")")
            }
            if let result {
                Section {
                    if let corrected = result.correctedText {
                        Text(corrected).font(.headline)
                        if let note = result.note {
                            Text(note).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Richtig! Nothing to correct.").font(.headline)
                    }
                } footer: {
                    if let stats = store.lastStats { Text(stats.caption) }
                }
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(Color.red) }
            }
        }
        .navigationTitle("Satz prüfen")
        .onAppear { store.refreshFiles() }
    }

    func check() async {
        checking = true
        errorText = nil
        defer { checking = false }
        let line = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = ConversationConfig(model: store.available?.model ?? .gemma4_E2B_german)
        do {
            let raw = try await store.complete(
                system: ConversationPrompts.correctionSystemPrompt(for: config),
                user: ConversationPrompts.correctionUserPrompt(partnerLine: nil, studentLine: line),
                maxTokens: 120)
            result = ConversationPrompts.parseCorrection(raw, original: line)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Gespräch

/// The voice host for Android chats: the system TTS voice. It reports no word ranges, so there's
/// no read-along highlight; `onFinish` fires right away.
final class AndroidSpeechOutput: SpeechOutput {
    func speak(_ text: String, slow: Bool, onWord: @escaping (NSRange) -> Void, onFinish: @escaping () -> Void) {
        GermanVoice.shared.speak(text, slow: slow)
        onFinish()
    }
    func stop() { GermanVoice.shared.stop() }
    func startBackgroundNoise() {}
    func stopBackgroundNoise() {}
}

typealias AndroidConversation = ConversationSession<MemoryConversationHost>

/// A conversation with the tutor: the iOS app's own session (`ConversationSession`, shared
/// through DieKarteiCore), so the flow is the same: the tutor opens, every learner line gets the
/// correction pass (or a nudge), then the reply; hints, translations and the summary on request.
/// Typed only for now, and kept in memory (no saved history yet).
struct GespraechView: View {
    @State var store = TutorStore.shared
    @State var scenario: ConversationScenario? = nil
    @State var session: AndroidConversation?

    var body: some View {
        Group {
            if let session {
                GespraechChat(session: session) { restart() }
            } else {
                setup
            }
        }
        .navigationTitle("Gespräch")
        .onAppear { store.refreshFiles() }
        .onDisappear { session?.tearDown() }
    }

    var setup: some View {
        List {
            Section {
                Picker("Szenario", selection: $scenario) {
                    Text("Freies Gespräch").tag(ConversationScenario?.none)
                    ForEach(ConversationScenario.allCases.filter { $0 != .custom }) { s in
                        Text(s.germanTitle).tag(ConversationScenario?.some(s))
                    }
                }
                Button("Gespräch beginnen") { start() }
                    .disabled(store.available == nil)
            } footer: {
                Text(store.available.map { "Tutor: \($0.model.displayName)" }
                     ?? "No tutor model on this phone yet. Settings ▸ Tutor Model.")
            }
        }
    }

    func start() {
        guard let model = store.available?.model else { return }
        var config = ConversationConfig(model: model)
        config.inputMode = .type
        if let scenario {
            config.mode = .scenario
            config.scenario = scenario
        }
        let new = AndroidConversation(
            host: MemoryConversationHost(),
            config: config,
            tutor: store,
            speechInput: NoSpeechInput(reason: "Speaking to the tutor isn't on Android yet; type instead."),
            speechOutput: AndroidSpeechOutput()
        )
        session = new
        new.onAppear()
    }

    func restart() {
        session?.tearDown()
        session = nil
    }
}

struct GespraechChat: View {
    let session: AndroidConversation
    let onRestart: () -> Void
    @State var draft = ""
    @State var summary: ConversationSummary?
    @State var summarizing = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(session.conversation.sortedMessages) { message in
                    bubble(message)
                }
                if session.phase == .thinking {
                    Text(session.streamingReply.isEmpty ? "…" : session.streamingReply)
                        .foregroundStyle(.secondary)
                }
                if session.phase == .loadingModel {
                    Text("Loading the tutor…").foregroundStyle(.secondary)
                }
                if session.showModelLoadPrompt {
                    Section {
                        Button("Load \(session.config.model.displayName)") { session.confirmModelLoad() }
                        Button("Not now") { session.cancelModelLoad() }
                    }
                }
                if let repair = session.repairPrompt {
                    repairCard(repair)
                }
                if !session.hints.isEmpty || session.hintLoading {
                    hintCard
                }
                if let error = session.errorMessage {
                    Section {
                        Text(error).foregroundStyle(Color.red)
                        if session.canRetryReply {
                            Button("Try again") { session.retryReply() }
                        }
                    }
                }
                if let summary {
                    summaryCard(summary)
                }
            }
            composer
        }
        .toolbar {
            Button("Ende") { Task { await end() } }
                .disabled(session.isBusy || summarizing || session.conversation.messages.count < 2)
            Button("Neu") { onRestart() }
                .disabled(session.isBusy)
        }
    }

    var composer: some View {
        HStack {
            Button("Tipp") { session.requestHints() }
                .disabled(session.isBusy || session.hintLoading)
            TextField(session.repairPrompt != nil ? "Versuch es noch einmal" : "Deine Antwort", text: $draft)
                .textFieldStyle(.roundedBorder)
            Button("Senden") {
                if session.submitTyped(draft) { draft = "" }
            }
            .disabled(!session.canSubmitTyped || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    @ViewBuilder
    func bubble(_ message: MemoryChatMessage) -> some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
            Text(message.text)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(message.isUser ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15)))
            if message.isUser {
                correction(message)
            } else {
                if session.shouldShowTranslation(message), let english = message.translationText {
                    Text(english).font(.caption).foregroundStyle(.secondary)
                } else if session.isTranslating(message) {
                    Text("Übersetze…").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 16) {
                        Button("Übersetzen") { session.revealTranslation(message) }
                        Button("Vorlesen") { session.play(message, slow: false) }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    @ViewBuilder
    func correction(_ message: MemoryChatMessage) -> some View {
        if session.activeRepairMessageID == message.id {
            EmptyView()   // the nudge card below asks first; the fix stays hidden
        } else if let fixed = message.correctedText {
            Text("✎ \(fixed)").font(.subheadline).foregroundStyle(Color.orange)
            if let note = message.correctionNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if message.selfCorrected {
                Text("Selbst korrigiert ✓").font(.caption).foregroundStyle(Color.green)
            }
        } else if message.confirmedClean {
            Text("✓").font(.caption).foregroundStyle(Color.green)
        }
    }

    func repairCard(_ repair: RepairPrompt) -> some View {
        Section("Fast!") {
            Text(repair.hint)
            if repair.revealed {
                Text(repair.target).font(.headline)
                if let note = repair.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            if let heard = repair.heardText, repair.matched == false {
                Text("Du hast geschrieben: \(heard)").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                if !repair.revealed { Button("Lösung zeigen") { session.revealRepair() } }
                Button("Weiter") { session.skipRepair() }
            }
            .buttonStyle(.borderless)
        }
    }

    var hintCard: some View {
        Section("Was könntest du sagen?") {
            if session.hintLoading {
                Text("…").foregroundStyle(.secondary)
            }
            ForEach(session.hints) { hint in
                Button {
                    draft = hint.german
                    session.clearHints()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hint.german).foregroundStyle(Color.primary)
                        if let english = hint.english {
                            Text(english).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    func summaryCard(_ summary: ConversationSummary) -> some View {
        Section("Zusammenfassung") {
            ForEach(summary.strengths, id: \.self) { Text("👍 \($0)") }
            ForEach(summary.improvements, id: \.self) { Text("→ \($0)") }
            if !summary.patternNote.isEmpty {
                Text(summary.patternNote).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(summary.turnCount) turns · \(summary.correctionCount) corrections")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    func end() async {
        summarizing = true
        summary = await session.endAndSummarize()
        summarizing = false
    }
}
