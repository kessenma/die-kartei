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
    /// Our Gemma 4 E4B fine-tuned for German grammar across 15 phenomena (v4 corpus: verbs with
    /// prepositions, separable/reflexive verbs, da-/wo-compounds, haben/sein, relative pronouns,
    /// Konjunktiv II, and more) and correction reliability. v4 supersedes v1: same grammar accuracy
    /// (paired p = 1.0), half the false corrections, conversational register.
    /// See training/training-v3.md §9.1.
    case gemma4_E4B_german = "Gemma 4 E4B German Tutor"
    /// The same German fine-tune on Gemma 4 E2B — ~1.7 GB lighter than the E4B tutor, for devices
    /// that can't afford the flagship's memory budget. Scored on the app's own correction behaviour
    /// it lands at 83% on the core grammar suite vs the E4B tutor's 90% — both guarded, both on the
    /// same suite. See training/GEMMA_E2B_FINETUNING.md.
    case gemma4_E2B_german = "Gemma 4 E2B German Tutor"
    /// IBM's Granite 3.3 2B, fine-tuned on the same German corpus as the Gemma tutors. The answer
    /// for 4 GB devices, which can't hold either Gemma tutor: it roughly doubles what those phones
    /// could run before. Its tokenizer costs ~1.9× the tokens per German word, so it generates
    /// noticeably slower than its size suggests. See training/training-v2.md §3.
    case granite2B_german = "Granite 2B German Tutor"
    /// IBM's Granite 4.1 3B on the same v4 German corpus. The stronger of the two Granite tutors
    /// (81% vs 75% across the full grammar suite, and it misses far fewer real errors: 25% vs 43%),
    /// for ~0.5 GB more download. Its ~100k-token vocabulary splits German into roughly half the
    /// tokens of the 2B Granite, which largely cancels the larger model's per-token cost. Which of
    /// the two ships long-term is decided by on-device peak-RAM measurement; both are listed while
    /// that test runs. See training/training-v3.md §9.4.
    case granite41_3B_german = "Granite 3B German Tutor"

    var id: String { rawValue }

    /// The MLX registry configuration for this model.
    ///
    /// For `.appleIntelligence` this returns a harmless sentinel that is NEVER loaded by MLX — it
    /// only keeps the cache-path helpers (which derive from `configuration.name`) total and
    /// non-crashing. The service short-circuits the Apple case before any real load happens.
    var configuration: ModelConfiguration {
        switch self {
        case .appleIntelligence: ModelConfiguration(id: "apple-intelligence")
        case .gemma4_E4B_german: ModelConfiguration(id: "kessenma/gemma4-e4b-german-tutor-v4-4bit")
        case .gemma4_E2B_german: ModelConfiguration(id: "kessenma/gemma4-e2b-german-tutor-4bit")
        case .granite2B_german: ModelConfiguration(id: "kessenma/granite33-2b-german-tutor-v4-4bit")
        case .granite41_3B_german: ModelConfiguration(id: "kessenma/granite41-3b-german-tutor-v4-4bit")
        }
    }

    var displayName: String { rawValue }

    var logoName: String {
        switch self {
        // Never rendered — `usesSFSymbolLogo` routes the Apple model to an SF Symbol before
        // anything reads this, and there is no "logo-apple" asset in the catalog.
        case .appleIntelligence: "logo-apple"
        case .gemma4_E4B_german, .gemma4_E2B_german: "logo-gemma"
        case .granite2B_german, .granite41_3B_german: "logo-ibm"
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
    /// Only the built-in Apple model lands here — it has no logo asset at all.
    var usesSFSymbolLogo: Bool {
        self == .appleIntelligence
    }

    /// SF Symbol used when `usesSFSymbolLogo` is true. `apple.intelligence` ships on iOS 26+;
    /// swap to `"sparkles"` if it ever renders blank on a given OS.
    var sfSymbolLogo: String {
        isAppleIntelligence ? "apple.intelligence" : "circle.hexagongrid.fill"
    }

    /// True for models that run via Apple's on-device FoundationModels rather than MLX.
    var isAppleIntelligence: Bool { self == .appleIntelligence }
}
