@testable import DieKarteiCore
import Foundation
import Observation
import SwiftUI

// The tutor models as Android has them: GGUF files run by llama.cpp (`TutorEngine`). The catalog
// (repo, file, size, SHA-256, RAM floor) is the shared one, `MLXModel.gguf`, next to the MLX repos
// in DieKarteiCore; scores and speeds in training/ANDROID_GGUF.md.

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

    /// Downloads in progress or failed, by model.
    enum Download: Equatable {
        case running(Int64), failed(String)
    }
    private(set) var downloads: [MLXModel: Download] = [:]
    private var downloadTasks: [MLXModel: Task<Void, Never>] = [:]

    private var engine: TutorEngine?
    private var loadedID: String?

    /// `files/models` in the app's private storage. During development, put GGUFs there with
    /// `adb push` + `run-as` (see DieKarteiAndroid/README.md); later the app downloads them.
    nonisolated static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("models", isDirectory: true)
    }

    nonisolated static func url(for release: GGUFRelease) -> URL {
        modelsDirectory.appendingPathComponent(release.fileName)
    }

    func isOnDevice(_ model: MLXModel) -> Bool {
        _ = filesVersion
        guard let release = model.gguf else { return false }
        return FileManager.default.fileExists(atPath: Self.url(for: release).path)
    }

    /// Bytes of an interrupted download still on the phone, so the button can say "Resume".
    func partialBytes(_ model: MLXModel) -> Int64 {
        _ = filesVersion
        guard let release = model.gguf else { return 0 }
        return GGUFDownloader.resumableBytes(for: Self.url(for: release))
    }

    /// Downloads the model from Hugging Face, continuing an interrupted download. The file is
    /// checked against its published SHA-256 before it can be loaded.
    func download(_ model: MLXModel) {
        guard let release = model.gguf, downloadTasks[model] == nil else { return }
        downloads[model] = .running(partialBytes(model))
        downloadTasks[model] = Task {
            do {
                try await GGUFDownloader().download(release, to: Self.url(for: release)) { [weak self] bytes in
                    self?.downloads[model] = .running(bytes)
                }
                downloads[model] = nil
                if selectedID == nil { selectedID = model.rawValue }
            } catch is CancellationError {
                downloads[model] = nil
            } catch {
                downloads[model] = .failed(error.localizedDescription)
            }
            downloadTasks[model] = nil
            filesVersion += 1
        }
    }

    /// Stops a download; what's on the phone stays for "Resume".
    func cancelDownload(_ model: MLXModel) {
        downloadTasks[model]?.cancel()
    }

    /// Deletes the model file (and any partial download) from the phone.
    func delete(_ model: MLXModel) {
        guard let release = model.gguf else { return }
        if loadedID == model.rawValue { unload() }
        let url = Self.url(for: release)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: GGUFDownloader.partURL(for: url))
        downloads[model] = nil
        filesVersion += 1
    }

    func refreshFiles() {
        try? FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
        filesVersion += 1
        if selectedID == nil, let first = MLXModel.ggufTutors.first(where: isOnDevice) {
            selectedID = first.rawValue
        }
    }

    var selected: MLXModel? {
        MLXModel.ggufTutors.first { $0.rawValue == selectedID }
    }

    /// The selected model when its file is on the phone.
    var available: MLXModel? {
        guard let selected, isOnDevice(selected) else { return nil }
        return selected
    }

    /// Loads the selected model if it isn't loaded yet. False when there's none or it fails.
    func ensureLoaded() async -> Bool {
        #if canImport(CLlama)
        guard let model = available, let release = model.gguf else {
            state = .failed("No tutor model on this phone yet.")
            return false
        }
        if engine != nil, loadedID == model.rawValue { return true }
        unload()
        state = .loading
        let path = Self.url(for: release).path
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try TutorEngine.load(path: path)
            }.value
            engine = loaded
            loadedID = model.rawValue
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
        return MLXModel.ggufTutors.first { $0.rawValue == loadedID }
    }

    var loadFailure: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// Android doesn't shed the model in the background (yet).
    func wasEvicted(_ model: MLXModel) -> Bool { false }

    func loadTutor(_ model: MLXModel) async {
        if model.gguf != nil, selectedID != model.rawValue {
            selectedID = model.rawValue
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
