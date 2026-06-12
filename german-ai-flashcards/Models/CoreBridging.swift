import Foundation
import MLXLLM
import MLXLMCommon
import DieKarteiCore

// Bridges the platform-neutral DieKarteiCore types to this app's
// iOS-specific frameworks (MLX, SwiftData models).

// MARK: - MLXModel → MLX registry

extension MLXModel {
    /// The MLX registry configuration for this model.
    var configuration: ModelConfiguration {
        switch self {
        case .gemma4_E4B:   LLMRegistry.gemma4_e4b_it_4bit
        case .mistral7B:    LLMRegistry.mistral7B4bit
        case .qwen3_8B:     LLMRegistry.qwen3_8b_4bit
        case .gemma3n_E4B:  LLMRegistry.gemma3n_E4B_it_lm_4bit
        case .qwen3_4B:     LLMRegistry.qwen3_4b_4bit
        case .phi4Mini:     ModelConfiguration(id: "mlx-community/Phi-4-mini-instruct-4bit")
        case .llama3_2_1B:  LLMRegistry.llama3_2_1B_4bit
        case .gemma3_1B:    LLMRegistry.gemma3_1B_qat_4bit
        case .qwen3_0_6B:   LLMRegistry.qwen3_0_6b_4bit
        }
    }

    var huggingFaceRepoURL: URL {
        URL(string: "https://huggingface.co/\(configuration.name)")!
    }
}

// MARK: - SwiftData models → SRS protocol

extension SavedCard: SRSCardState {}

extension SpacedRepetitionService {
    /// Returns cards from the deck that are due for review.
    static func dueCards(in deck: SavedDeck) -> [SavedCard] {
        dueCards(in: deck.cards)
    }
}

// MARK: - ChatMessage → transcript lines

extension ConversationPrompts {
    static func transcript(from messages: [ChatMessage]) -> String {
        transcript(from: messages.map {
            TranscriptLine(isUser: $0.isUser, text: $0.text, sortOrder: $0.sortOrder)
        })
    }
}
