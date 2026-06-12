import Foundation

// MARK: - Model Provider

public enum ModelProvider: String, CaseIterable, Codable {
    case mlx = "MLX"
}

// MARK: - Model Definitions

/// Specific on-device model variants the user can select and run.
///
/// This catalog is platform-neutral metadata. The mapping to an actual
/// inference engine lives outside the core: on iOS,
/// `MLXModel+MLX.swift` in the app target maps each case to an MLX
/// registry configuration; an Android host maps cases to its own engine
/// (e.g. GGUF checkpoints for llama.cpp).
public enum MLXModel: String, CaseIterable, Codable, Identifiable {
    case gemma4_E4B   = "Gemma 4 E4B"
    case mistral7B    = "Mistral 7B"
    case qwen3_8B     = "Qwen3 8B"
    case gemma3n_E4B  = "Gemma 3n E4B"
    case qwen3_4B     = "Qwen3 4B"
    case phi4Mini     = "Phi-4 Mini"
    case llama3_2_1B  = "LLaMA 3.2 1B"
    case gemma3_1B    = "Gemma 3 1B"
    case qwen3_0_6B   = "Qwen3 0.6B"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var approximateSizeMB: Int {
        switch self {
        case .gemma4_E4B:   5500
        case .mistral7B:    4000
        case .qwen3_8B:     4900
        case .gemma3n_E4B:  3900
        case .qwen3_4B:     2200
        case .phi4Mini:     2300
        case .llama3_2_1B:   800
        case .gemma3_1B:     800
        case .qwen3_0_6B:    500
        }
    }

    // MARK: Model Info

    public var description: String {
        switch self {
        case .gemma4_E4B:
            "Google's latest Gemma 4 with effective 4B parameters, 4-bit quantized. Best quality but larger download (~5 GB)."
        case .mistral7B:
            "Mistral AI's 7B Instruct v0.3 model, 4-bit quantized. Built by a European team with strong multilingual training — excellent German quality at a size that runs comfortably on device."
        case .qwen3_8B:
            "Alibaba's Qwen3 8B model, 4-bit quantized. The strongest Qwen3 variant that fits comfortably on device — excellent German vocabulary, grammar, and instruction following."
        case .gemma3n_E4B:
            "Google's Gemma 3n with effective 4B parameters, 4-bit quantized, text-only. Strong quality without the vision overhead of Gemma 4."
        case .qwen3_4B:
            "Alibaba's Qwen3 4B model, 4-bit quantized. Qwen's 18-trillion-token multilingual corpus gives it strong German vocabulary and grammar at this size. A solid mid-range option that fits on more devices than the 4B Gemma models."
        case .phi4Mini:
            "Microsoft's Phi-4 Mini 3.8B Instruct, 4-bit quantized. Compact but capable, with solid German instruction following from curated multilingual training data."
        case .llama3_2_1B:
            "Meta's LLaMA 3.2 1B Instruct model, 4-bit quantized. Good balance of speed and quality."
        case .gemma3_1B:
            "Google's Gemma 3 1B Instruct with QAT 4-bit quantization. Compact model with strong instruction following."
        case .qwen3_0_6B:
            "A compact 0.6B parameter model from Alibaba's Qwen3 family, 4-bit quantized. Fast but limited quality."
        }
    }

    public var parameterCount: String {
        switch self {
        case .gemma4_E4B:   "~4B"
        case .mistral7B:    "7B"
        case .qwen3_8B:     "8B"
        case .gemma3n_E4B:  "~4B"
        case .qwen3_4B:     "4B"
        case .phi4Mini:     "3.8B"
        case .llama3_2_1B:  "1B"
        case .gemma3_1B:    "1B"
        case .qwen3_0_6B:   "0.6B"
        }
    }

    /// Numeric parameter count for sorting the Parameters tab.
    public var parameterCountValue: Double {
        switch self {
        case .mistral7B:     7.0
        case .qwen3_8B:      8.0
        case .gemma4_E4B:    4.0
        case .gemma3n_E4B:   4.0
        case .qwen3_4B:      4.0
        case .phi4Mini:      3.8
        case .llama3_2_1B:   1.0
        case .gemma3_1B:     1.0
        case .qwen3_0_6B:    0.6
        }
    }

    /// Relative German quality score used by the Recommended sort (1 = lowest, 5 = highest).
    public var germanQualityScore: Int {
        switch self {
        case .mistral7B:    4
        case .qwen3_8B:     5
        case .gemma4_E4B:   4
        case .gemma3n_E4B:  4
        case .qwen3_4B:     3
        case .phi4Mini:     3
        case .gemma3_1B:    2
        case .llama3_2_1B:  2
        case .qwen3_0_6B:   1
        }
    }

    public var quantization: String { "4-bit" }

    /// Minimum device RAM (in GB) needed to run this model comfortably.
    public var minimumRAMGB: Int {
        switch self {
        case .qwen3_0_6B, .llama3_2_1B, .gemma3_1B: 4
        case .qwen3_4B, .gemma3n_E4B, .gemma4_E4B, .phi4Mini, .mistral7B: 6
        case .qwen3_8B: 8
        }
    }

    /// Short device compatibility hint shown in the model picker.
    public var deviceNote: String {
        switch self {
        case .qwen3_0_6B, .llama3_2_1B, .gemma3_1B:
            "iPhone 12 or newer"
        case .qwen3_4B:
            "iPhone 13 Pro / iPhone 14 or newer (6 GB RAM)"
        case .gemma3n_E4B, .gemma4_E4B:
            "iPhone 14 Pro / iPhone 15 or newer (6 GB+ RAM)"
        case .phi4Mini, .mistral7B:
            "iPhone 14 Pro / iPhone 15 or newer (6 GB RAM)"
        case .qwen3_8B:
            "iPhone 15 Pro or newer (8 GB RAM)"
        }
    }

    public var logoName: String {
        switch self {
        case .qwen3_0_6B, .qwen3_4B, .qwen3_8B: "logo-qwen"
        case .llama3_2_1B: "logo-meta"
        case .gemma3_1B, .gemma3n_E4B, .gemma4_E4B: "logo-gemma"
        case .mistral7B: "logo-mistral"
        case .phi4Mini: "logo-microsoft"
        }
    }

    public var promoPageURL: URL {
        switch self {
        case .qwen3_0_6B, .qwen3_4B, .qwen3_8B:
            URL(string: "https://qwen.ai/blog?id=qwen3")!
        case .llama3_2_1B:
            URL(string: "https://www.llama.com/models/llama-3/")!
        case .gemma3_1B, .gemma3n_E4B, .gemma4_E4B:
            URL(string: "https://deepmind.google/models/gemma/")!
        case .mistral7B:
            URL(string: "https://mistral.ai/models/")!
        case .phi4Mini:
            URL(string: "https://azure.microsoft.com/en-us/products/phi")!
        }
    }
}
