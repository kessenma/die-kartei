import Foundation
import FoundationModels

/// Wraps Apple's on-device foundation model (the system language model behind Apple Intelligence)
/// behind the same small surface `MLXGenerationService` exposes, so the rest of the app can treat
/// the built-in model as just another `MLXModel` choice (`.appleIntelligence`).
///
/// This is the ONLY file in the project that imports `FoundationModels`. Everything else stays
/// MLX-typed and routes here via `MLXGenerationService` when the selected model is the built-in one.
///
/// The on-device model is whatever the current OS ships: it is upgraded with each major iOS release
/// (iOS 26 → 2nd-gen, iOS 27 → "AFM 3"), so simply targeting `SystemLanguageModel.default` means the
/// app automatically benefits from the newer, better model on each update — there is no model to pin.
@MainActor
final class AppleIntelligenceService {

    // MARK: - Availability

    var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    /// A user-facing explanation when the on-device model can't be used right now, or `nil` if it can.
    var unavailableReason: String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to use the built-in model."
            case .modelNotReady:
                return "Apple Intelligence is still preparing its model. Try again shortly."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    /// Synchronous availability check usable from `MLXModelManager.init` (to pick the first-run
    /// default) without that file having to import `FoundationModels`.
    nonisolated static func currentlyAvailable() -> Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // MARK: - Generation

    /// Low-level one-shot text generation. Mirrors `MLXGenerationService.generateText` minus `model:`.
    func generateText(system: String, user: String, maxTokens: Int = 512) async throws -> String {
        let session = LanguageModelSession { system }
        let options = GenerationOptions(maximumResponseTokens: maxTokens)
        let response = try await session.respond(to: user, options: options)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Card generation: returns the model's RAW text (typically JSON). The caller
    /// (`MLXGenerationService`) runs it through its existing tolerant `parseVocabCards` salvage
    /// pipeline — we deliberately do NOT parse here, to reuse that battle-tested code.
    ///
    /// TODO: upgrade to `@Generable` schema-guided generation — see
    /// `AppleIntelligence-CardGeneration-TODO.md`. That change is fully contained to this method.
    func generateCardsRaw(system: String, user: String, maxTokens: Int = 1500) async throws -> String {
        let session = LanguageModelSession { system }
        let options = GenerationOptions(maximumResponseTokens: maxTokens)
        let response = try await session.respond(to: user, options: options)
        return response.content
    }

    /// Streamed multi-turn chat reply. Mirrors `MLXGenerationService.streamChatReply` minus `model:`.
    /// Each streamed value is a CUMULATIVE snapshot of the reply so far, so `onPartial` is called by
    /// assignment (never by appending — appending would duplicate text).
    func streamChatReply(
        history: [(role: ChatRole, content: String)],
        system: String,
        maxTokens: Int = 256,
        temperature: Double = 0.7,
        onPartial: @escaping (String) -> Void
    ) async throws -> String {
        let session = LanguageModelSession { system }
        let prompt = Self.flatten(history)
        let options = GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens)

        var latest = ""
        for try await partial in session.streamResponse(to: prompt, options: options) {
            latest = partial.content
            onPartial(latest)
        }
        return latest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Flatten a multi-turn history into a single prompt, mirroring the MLX path's chat mapping.
    private static func flatten(_ history: [(role: ChatRole, content: String)]) -> String {
        let body = history.map { turn -> String in
            switch turn.role {
            case .user:      return "User: \(turn.content)"
            case .assistant: return "Assistant: \(turn.content)"
            case .system:    return turn.content
            }
        }.joined(separator: "\n\n")
        return body + "\n\nAssistant:"
    }
}
