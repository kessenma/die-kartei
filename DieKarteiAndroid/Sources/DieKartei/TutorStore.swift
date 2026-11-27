@testable import DieKarteiCore
import Foundation
import Observation
import SwiftUI

/// The tutor models as Android has them: GGUF files run by llama.cpp (`TutorEngine`). Same four
/// tutors as the iOS catalog (`MLXModel`), converted from the same weights; scores and speeds in
/// training/ANDROID_GGUF.md.
struct TutorModelFile: Identifiable, Hashable {
    let model: MLXModel
    /// File name in the models folder, and in the (not yet published) Hugging Face repo.
    let fileName: String
    let sizeGB: Double
    /// The iOS app's RAM floor for the model, kept the same on Android to start.
    let minimumRAMGB: Int

    var id: String { model.rawValue }

    /// E4B as Q4_0, the others as Q4_K_M. Q4_0 is what llama.cpp repacks best for ARM's int8
    /// dot-product instructions (~40% faster to read a prompt, ~20% faster to answer on the
    /// emulator) and costs E4B nothing (184 vs 185 of 203). On the three smaller tutors it scored
    /// 4–5 items lower each time (not significant per model, but every time), and with the prompt
    /// cache most of a turn's prompt is never re-read, so they keep Q4_K_M. training/ANDROID_GGUF.md.
    static let all: [TutorModelFile] = [
        TutorModelFile(model: .gemma4_E4B_german, fileName: "gemma4-e4b-german-tutor-v4-Q4_0.gguf", sizeGB: 5.2, minimumRAMGB: 8),
        TutorModelFile(model: .gemma4_E2B_german, fileName: "gemma4-e2b-german-tutor-Q4_K_M.gguf", sizeGB: 3.4, minimumRAMGB: 6),
        TutorModelFile(model: .granite41_3B_german, fileName: "granite41-3b-german-tutor-v4-Q4_K_M.gguf", sizeGB: 2.1, minimumRAMGB: 4),
        TutorModelFile(model: .granite2B_german, fileName: "granite33-2b-german-tutor-v4-Q4_K_M.gguf", sizeGB: 1.5, minimumRAMGB: 4),
    ]
}

@Observable
@MainActor
final class TutorStore {
    static let shared = TutorStore()

    enum LoadState: Equatable {
        case idle, loading, ready, failed(String)
    }

    var selectedID: String? = UserDefaults.standard.string(forKey: "tutor.model") {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: "tutor.model")
            unload()
        }
    }
    private(set) var state: LoadState = .idle
    /// From the last answer: shown under it, and on the model screen.
    private(set) var lastStats: TutorEngine.Stats?
    private(set) var threads: Int = 0
    private(set) var cpuFeatures: String = ""
    /// Bumped when the models folder may have changed, so views re-check which files exist.
    private(set) var filesVersion = 0

    private var engine: TutorEngine?
    private var loadedID: String?

    /// `files/models` in the app's private storage. During development, put GGUFs there with
    /// `adb push` + `run-as` (see DieKarteiAndroid/README.md); later the app downloads them.
    nonisolated static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("models", isDirectory: true)
    }

    func url(for file: TutorModelFile) -> URL {
        Self.modelsDirectory.appendingPathComponent(file.fileName)
    }

    func isOnDevice(_ file: TutorModelFile) -> Bool {
        _ = filesVersion
        return FileManager.default.fileExists(atPath: url(for: file).path)
    }

    func refreshFiles() {
        try? FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
        filesVersion += 1
        if selectedID == nil, let first = TutorModelFile.all.first(where: isOnDevice) {
            selectedID = first.id
        }
    }

    var selected: TutorModelFile? {
        TutorModelFile.all.first { $0.id == selectedID }
    }

    /// The selected model when its file is on the phone.
    var available: TutorModelFile? {
        guard let selected, isOnDevice(selected) else { return nil }
        return selected
    }

    /// Loads the selected model if it isn't loaded yet. False when there's none or it fails.
    func ensureLoaded() async -> Bool {
        #if canImport(CLlama)
        guard let file = available else {
            state = .failed("No tutor model on this phone yet.")
            return false
        }
        if engine != nil, loadedID == file.id { return true }
        unload()
        state = .loading
        let path = url(for: file).path
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try TutorEngine.load(path: path)
            }.value
            engine = loaded
            loadedID = file.id
            threads = loaded.threads
            cpuFeatures = loaded.systemInfo
            state = .ready
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
        #else
        state = .failed("The tutor runs on Android only in this build.")
        return false
        #endif
    }

    func unload() {
        engine = nil
        loadedID = nil
        if state != .loading { state = .idle }
    }

    /// One answer to one prompt: corrections, sentence checks. Low temperature, like iOS's
    /// `generateText`.
    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        try await generate([(role: "system", content: system), (role: "user", content: user)],
                           slot: .check, maxTokens: maxTokens, temperature: 0.1, onText: nil)
    }

    func startNewConversation() {
        #if canImport(CLlama)
        engine?.reset(.chat)
        #endif
    }

    func cancel() {
        #if canImport(CLlama)
        engine?.cancel()
        #endif
    }

    private func generate(_ messages: [(role: String, content: String)], slot: TutorSlot, maxTokens: Int,
                          temperature: Float, onText: (@MainActor (String) -> Void)?) async throws -> String {
        #if canImport(CLlama)
        guard await ensureLoaded(), let engine else { throw TutorUnavailable() }
        var callback: (@Sendable (String) -> Void)? = nil
        if let onText {
            callback = { @Sendable (text: String) in
                Task { @MainActor in onText(text) }
            }
        }
        let engineSlot: TutorEngine.Slot = slot == .chat ? .chat : .check
        let (text, stats) = try await engine.generate(messages: messages, slot: engineSlot, maxTokens: maxTokens,
                                                      temperature: temperature, onText: callback)
        lastStats = stats
        return text
        #else
        throw TutorUnavailable()
        #endif
    }
}

enum TutorSlot { case chat, check }

/// llama.cpp behind the shared tutor protocol, so the shared conversation session
/// (`ConversationSession`) runs on Android exactly as on iOS.
extension TutorStore: TutorGenerating {
    var readyModel: MLXModel? {
        guard state == .ready, let loadedID else { return nil }
        return TutorModelFile.all.first { $0.id == loadedID }?.model
    }

    var loadFailure: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// Android doesn't shed the model in the background (yet).
    func wasEvicted(_ model: MLXModel) -> Bool { false }

    func loadTutor(_ model: MLXModel) async {
        if let file = TutorModelFile.all.first(where: { $0.model == model }), selectedID != file.id {
            selectedID = file.id
        }
        _ = await ensureLoaded()
    }

    func complete(system: String, user: String, model: MLXModel, maxTokens: Int) async throws -> String {
        try await complete(system: system, user: user, maxTokens: maxTokens)
    }

    /// Same turn shape as iOS: normalized to strict user/assistant alternation (Gemma's template
    /// demands it), think blocks stripped from what the learner sees.
    func streamReply(
        history: [(role: ChatRole, content: String)],
        system: String,
        model: MLXModel,
        maxTokens: Int,
        temperature: Float,
        onPartial: @escaping (String) -> Void
    ) async throws -> String {
        let turns = ChatTurnNormalizer.normalized(history, openerSeed: ConversationPrompts.openerSeed)
        let messages = [(role: "system", content: system)] + turns.map { (role: $0.role.rawValue, content: $0.content) }
        let raw = try await generate(messages, slot: .chat, maxTokens: maxTokens, temperature: temperature) { partial in
            onPartial(ConversationPrompts.stripThinkBlocks(partial))
        }
        return ConversationPrompts.stripThinkBlocks(raw)
    }
}

struct TutorUnavailable: LocalizedError {
    var errorDescription: String? { "No tutor model is loaded. Pick one in Settings ▸ Tutor Model." }
}

#if !canImport(CLlama)
/// Stand-in so the store compiles where llama.cpp isn't linked (the Darwin build of this package).
enum TutorEngine {
    struct Stats: Sendable {
        var promptTokens = 0, reusedTokens = 0, generatedTokens = 0
        var prefillSeconds = 0.0, generateSeconds = 0.0
        var tokensPerSecond: Double { 0 }
    }
}
#endif

extension TutorEngine.Stats {
    /// "212 prompt tokens (180 cached) in 0.4 s · 31 tokens at 18.2/s", under an answer.
    var caption: String {
        let reused = reusedTokens > 0 ? " (\(reusedTokens) cached)" : ""
        let read = String(format: "%.1f", prefillSeconds)
        let speed = String(format: "%.1f", tokensPerSecond)
        return "\(promptTokens) prompt tokens\(reused) in \(read) s · \(generatedTokens) tokens at \(speed)/s"
    }
}
