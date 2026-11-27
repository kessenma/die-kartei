import Foundation

// MARK: - MLXModel catalog (shared with Android)

/// One tutor as a GGUF file for llama.cpp, the Android runtime. Same weights as the model's MLX
/// repo, published by training/scripts/publish_gguf.py (which prints these sizes and hashes into
/// training/releases/gguf_release.json). Scores per format: training/ANDROID_GGUF.md.
struct GGUFRelease: Sendable, Hashable {
    let repoID: String
    let fileName: String
    let quant: String
    let bytes: Int64
    /// Checked after a download, so a truncated or swapped file never reaches llama.cpp.
    let sha256: String

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(fileName)")!
    }
}

extension MLXModel {
    /// The tutors that ship as GGUF, largest first (the order Android lists them).
    static let ggufTutors: [MLXModel] = [.gemma4_E4B_german, .gemma4_E2B_german, .granite41_3B_german, .granite2B_german]

    /// The GGUF file the app uses for this tutor, or nil (Apple Intelligence has none).
    ///
    /// E4B as Q4_0, the others as Q4_K_M. Q4_0 is what llama.cpp repacks best for ARM's int8
    /// dot-product instructions (~40% faster to read a prompt, ~20% faster to answer on the
    /// emulator) and costs E4B nothing (184 vs 185 of 203). On the three smaller tutors it scored
    /// 4–5 items lower each time (not significant per model, but every time), and with the prompt
    /// cache most of a turn's prompt is never re-read, so they keep Q4_K_M. Both quants are in
    /// each repo.
    var gguf: GGUFRelease? {
        switch self {
        case .appleIntelligence:
            nil
        case .gemma4_E4B_german:
            GGUFRelease(repoID: "kessenma/gemma4-e4b-german-tutor-v4-gguf",
                        fileName: "gemma4-e4b-german-tutor-v4-Q4_0.gguf", quant: "Q4_0", bytes: 5_185_915_104,
                        sha256: "b01a6ffa3e1a8b57cb45bb794cf243d1ed28b18416dabe4a6114b4d54b68f121")
        case .gemma4_E2B_german:
            GGUFRelease(repoID: "kessenma/gemma4-e2b-german-tutor-gguf",
                        fileName: "gemma4-e2b-german-tutor-Q4_K_M.gguf", quant: "Q4_K_M", bytes: 3_416_104_256,
                        sha256: "87a5dc28693e910d0a1b57f6c9d200c3b25e4a4da864736ed1e4a61c6dbf54df")
        case .granite41_3B_german:
            GGUFRelease(repoID: "kessenma/granite41-3b-german-tutor-v4-gguf",
                        fileName: "granite41-3b-german-tutor-v4-Q4_K_M.gguf", quant: "Q4_K_M", bytes: 2_099_502_208,
                        sha256: "f98fef3fc9754c1eba605d7c36c68511f9453066e15884d42bda043c6180308d")
        case .granite2B_german:
            GGUFRelease(repoID: "kessenma/granite33-2b-german-tutor-v4-gguf",
                        fileName: "granite33-2b-german-tutor-v4-Q4_K_M.gguf", quant: "Q4_K_M", bytes: 1_545_303_488,
                        sha256: "d841cb15552c5a8ba3e8d675aa4549cf2d75cb1c58f26c98bf9b96307577f9af")
        }
    }

    /// Minimum device RAM (in GB) needed to run this model.
    ///
    /// Sized against what iOS actually hands an app, not against physical RAM: the jetsam limit is
    /// roughly half of RAM even with the increased-memory-limit entitlement, so a 6 GB iPhone has
    /// about 3.4 GB to work with and cannot hold a 4 GB set of weights plus a KV cache. Anything
    /// whose weights are over ~3 GB therefore lands in the 8 GB tier.
    ///
    /// This drives the *interface*: which model gets recommended, and when the memory check sheet
    /// appears. It's deliberately a fixed tier rather than a live reading, so rows don't appear and
    /// vanish as the app allocates. Runtime safety is ``MemoryBudget``'s job, which measures the
    /// real budget on the device in hand.
    var minimumRAMGB: Int {
        switch self {
        case .appleIntelligence: 0   // gated by Apple Intelligence eligibility, not by RAM
        case .granite2B_german, .granite41_3B_german: 4
        case .gemma4_E2B_german: 6
        case .gemma4_E4B_german: 8
        }
    }
}
