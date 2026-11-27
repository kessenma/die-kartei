import Foundation

// MLX (and Apple Intelligence) behind the shared tutor protocol. Pure forwarding: the memory
// governors, stall watchdogs and the Apple path all stay in MLXGenerationService.
extension MLXGenerationService: TutorGenerating {
    var readyModel: MLXModel? { loadedModel }
    var loadFailure: String? { loadError }

    func loadTutor(_ model: MLXModel) async { await loadModel(model) }

    func complete(system: String, user: String, model: MLXModel, maxTokens: Int) async throws -> String {
        try await generateText(system: system, user: user, model: model, maxTokens: maxTokens)
    }

    func streamReply(
        history: [(role: ChatRole, content: String)],
        system: String,
        model: MLXModel,
        maxTokens: Int,
        temperature: Float,
        onPartial: @escaping (String) -> Void
    ) async throws -> String {
        try await streamChatReply(history: history, system: system, model: model,
                                  maxTokens: maxTokens, temperature: temperature, onPartial: onPartial)
    }

    func friendlyMessage(for error: Error) -> String? {
        guard let mlxError = error as? MLXError else { return nil }
        return mlxError.errorDescription ?? "Something went wrong."
    }
}
