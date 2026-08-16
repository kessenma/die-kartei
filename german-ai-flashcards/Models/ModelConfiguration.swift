import Foundation
import MLXLLM
import MLXLMCommon

// MARK: - Model Provider

enum ModelProvider: String, CaseIterable, Codable {
    case mlx = "MLX"
}

// MARK: - MLX Model Definitions

/// Specific models the user can select and run.
///
/// Despite the name, this also includes one non-MLX entry — `.appleIntelligence`, Apple's built-in
/// on-device model — so the option flows through every picker, all persistence, and all feature
/// callers (which are uniformly typed on `MLXModel`) with no plumbing changes. That case carries no
/// MLX configuration and is routed to `AppleIntelligenceService` inside `MLXGenerationService`.
///
/// Per-model human-facing copy (size, description, parameter count, quality, RAM, device notes,
/// links) lives in `MLXModel+Descriptors.swift`.
enum MLXModel: String, CaseIterable, Codable, Identifiable {
    /// Apple's built-in on-device model (Apple Intelligence). No download; runtime-gated by device
    /// eligibility. Listed first so it leads any unsorted picker.
    case appleIntelligence = "Apple Intelligence"
    /// Our Gemma 4 E4B fine-tuned for German grammar (verbs+prepositions, separable verbs,
    /// reflexives, da-/wo-compounds, haben/sein) and correction reliability. See training/PLAN.md.
    case gemma4_E4B_german = "Gemma 4 E4B German Tutor"
    /// The same German fine-tune on Gemma 4 E2B — ~1.7 GB lighter than the E4B tutor, for devices
    /// that can't afford the flagship's memory budget. Scored on the app's own correction behaviour
    /// it lands at 83% on the core grammar suite vs the E4B tutor's 90% — both guarded, both on the
    /// same suite. See training/GEMMA_E2B_FINETUNING.md.
    case gemma4_E2B_german = "Gemma 4 E2B German Tutor"
    case mistral7B    = "Mistral 7B"
    case qwen3_8B     = "Qwen3 8B"
    case qwen3_4B     = "Qwen3 4B"
    case phi4Mini     = "Phi-4 Mini"
    case llama3_2_1B  = "LLaMA 3.2 1B"
    case gemma3_1B    = "Gemma 3 1B"
    case qwen3_0_6B   = "Qwen3 0.6B"
    /// IBM's Granite 3.3 2B, fine-tuned on the same German corpus as the Gemma tutors. The answer
    /// for 4 GB devices, which can't hold either Gemma tutor: it roughly doubles what those phones
    /// could run before. Its tokenizer costs ~1.9× the tokens per German word, so it generates
    /// noticeably slower than its size suggests. See training/training-v2.md §3.
    case granite2B_german = "Granite 2B German Tutor"

    var id: String { rawValue }

    /// The MLX registry configuration for this model.
    ///
    /// For `.appleIntelligence` this returns a harmless sentinel that is NEVER loaded by MLX — it
    /// only keeps the cache-path helpers (which derive from `configuration.name`) total and
    /// non-crashing. The service short-circuits the Apple case before any real load happens.
    var configuration: ModelConfiguration {
        switch self {
        case .appleIntelligence: ModelConfiguration(id: "apple-intelligence")
        case .gemma4_E4B_german: ModelConfiguration(id: "kessenma/gemma4-e4b-german-tutor-4bit")
        case .gemma4_E2B_german: ModelConfiguration(id: "kessenma/gemma4-e2b-german-tutor-4bit")
        case .mistral7B:    LLMRegistry.mistral7B4bit
        case .qwen3_8B:     LLMRegistry.qwen3_8b_4bit
        case .qwen3_4B:     LLMRegistry.qwen3_4b_4bit
        case .phi4Mini:     ModelConfiguration(id: "mlx-community/Phi-4-mini-instruct-4bit")
        case .llama3_2_1B:  LLMRegistry.llama3_2_1B_4bit
        case .gemma3_1B:    LLMRegistry.gemma3_1B_qat_4bit
        case .qwen3_0_6B:   LLMRegistry.qwen3_0_6b_4bit
        case .granite2B_german: ModelConfiguration(id: "kessenma/granite33-2b-german-tutor-4bit")
        }
    }

    var displayName: String { rawValue }

    var logoName: String {
        switch self {
        case .appleIntelligence: "logo-apple"   // placeholder — never used; see `usesSFSymbolLogo`/`logoImage`
        case .qwen3_0_6B, .qwen3_4B, .qwen3_8B: "logo-qwen"
        case .llama3_2_1B: "logo-meta"
        case .gemma3_1B, .gemma4_E4B_german, .gemma4_E2B_german: "logo-gemma"
        case .mistral7B: "logo-mistral"
        case .phi4Mini: "logo-microsoft"
        case .granite2B_german: "logo-ibm"   // no asset yet; `usesSFSymbolLogo` covers it meanwhile
        }
    }

    /// The HuggingFace repo page, or `nil` for the built-in Apple model (no repo).
    var huggingFaceRepoURL: URL? {
        if self == .appleIntelligence { return nil }
        return URL(string: "https://huggingface.co/\(configuration.name)")
    }

    // MARK: - Built-in model helpers

    /// Whether the UI should render an SF Symbol instead of a brand asset. Drives `logoImage` and
    /// the no-download/eligibility UI branches.
    ///
    /// Two reasons a model lands here: the built-in Apple model has no logo asset at all, and the
    /// Granite tutor doesn't have one *yet*. A missing `Image("logo-ibm")` renders as blank space
    /// rather than failing, which reads as a broken row, so it takes a symbol until an IBM asset is
    /// added to `Assets.xcassets`. **To finish that: add `logo-ibm.imageset` and drop
    /// `.granite2B_german` from this list.** Nothing else needs to change.
    var usesSFSymbolLogo: Bool { self == .appleIntelligence || self == .granite2B_german }

    /// SF Symbol used when `usesSFSymbolLogo` is true. `apple.intelligence` ships on iOS 26+;
    /// swap to `"sparkles"` if it ever renders blank on a given OS.
    var sfSymbolLogo: String {
        self == .granite2B_german ? "circle.hexagongrid.fill" : "apple.intelligence"
    }

    /// True for models that run via Apple's on-device FoundationModels rather than MLX.
    var isAppleIntelligence: Bool { self == .appleIntelligence }
}
