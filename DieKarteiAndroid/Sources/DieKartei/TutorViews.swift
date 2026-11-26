@testable import DieKarteiCore
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

/// A conversation with the tutor, as on iOS: every learner line gets the correction pass, then
/// the tutor replies in character. Kept in memory for now (no history yet).
struct GespraechView: View {
    struct Line: Identifiable {
        let id = UUID()
        let isUser: Bool
        var text: String
        var correction: ConversationPrompts.CorrectionResult?
    }

    @State var store = TutorStore.shared
    @State var lines: [Line] = []
    @State var draft = ""
    @State var busy = false
    @State var streaming = ""
    @State var errorText: String?
    @State var scenario: ConversationScenario? = nil

    var config: ConversationConfig {
        var c = ConversationConfig(model: store.available?.model ?? .gemma4_E2B_german)
        c.scenario = scenario
        return c
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Picker("Szenario", selection: $scenario) {
                        Text("Freies Gespräch").tag(ConversationScenario?.none)
                        ForEach(ConversationScenario.allCases.filter { $0 != .custom }) { s in
                            Text(s.germanTitle).tag(ConversationScenario?.some(s))
                        }
                    }
                    .disabled(!lines.isEmpty || busy)
                }
                ForEach(lines) { line in
                    lineView(line)
                }
                if busy {
                    Text(streaming.isEmpty ? "…" : streaming)
                        .foregroundStyle(.secondary)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(Color.red)
                }
                if let stats = store.lastStats, !busy, !lines.isEmpty {
                    Text(stats.caption).font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField("Deine Antwort", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("Senden") { Task { await send() } }
                    .disabled(busy || draft.trimmingCharacters(in: .whitespaces).isEmpty || lines.isEmpty)
            }
            .padding()
        }
        .navigationTitle("Gespräch")
        .toolbar {
            Button("Neu") { restart() }
                .disabled(busy)
        }
        .task {
            store.refreshFiles()
            if lines.isEmpty { await opener() }
        }
    }

    @ViewBuilder
    func lineView(_ line: Line) -> some View {
        VStack(alignment: line.isUser ? .trailing : .leading, spacing: 4) {
            Text(line.text)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(line.isUser ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15)))
            if let correction = line.correction {
                if let fixed = correction.correctedText {
                    Text("✎ \(fixed)").font(.subheadline).foregroundStyle(Color.orange)
                    if let note = correction.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("✓").font(.caption).foregroundStyle(Color.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: line.isUser ? .trailing : .leading)
    }

    func restart() {
        lines = []
        errorText = nil
        store.startNewConversation()
        Task { await opener() }
    }

    /// The tutor speaks first, from the iOS opener seed (sent as a user turn, never shown).
    func opener() async {
        await runReply(history: [(role: "user", content: ConversationPrompts.openerSeed(for: config))])
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        let partner = lines.last(where: { !$0.isUser })?.text
        lines.append(Line(isUser: true, text: text))
        let index = lines.count - 1
        busy = true
        // 1. Correction pass (its own slot, so the conversation's cache stays warm).
        do {
            let raw = try await store.complete(
                system: ConversationPrompts.correctionSystemPrompt(for: config),
                user: ConversationPrompts.correctionUserPrompt(partnerLine: partner, studentLine: text),
                maxTokens: 120)
            lines[index].correction = ConversationPrompts.parseCorrection(raw, original: text)
        } catch {
            errorText = error.localizedDescription
        }
        // 2. Reply pass.
        var history: [(role: String, content: String)] = [(role: "user", content: ConversationPrompts.openerSeed(for: config))]
        for line in lines {
            history.append((role: line.isUser ? "user" : "assistant", content: line.text))
        }
        await runReply(history: history)
    }

    func runReply(history: [(role: String, content: String)]) async {
        busy = true
        streaming = ""
        errorText = nil
        defer { busy = false }
        do {
            let reply = try await store.reply(
                system: ConversationPrompts.systemPrompt(for: config), history: history, maxTokens: 200
            ) { partial in streaming = partial }
            lines.append(Line(isUser: false, text: reply))
        } catch {
            errorText = error.localizedDescription
        }
        streaming = ""
    }
}
