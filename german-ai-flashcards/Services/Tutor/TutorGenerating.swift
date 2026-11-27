import Foundation

/// What the tutor features need from a language model, and nothing else. iOS answers it with
/// `MLXGenerationService` (MLX, plus the Apple Intelligence path); Android with `TutorStore`
/// (llama.cpp). The conversation session and every shared feature talk to this, never to a
/// runtime, so a feature written once runs on both.
///
/// The two calls are the two shapes the app has always used: one prompt in, one answer out
/// (corrections, translations, hints, summaries; low temperature), and a chat reply streamed as
/// it's written. Turn-shape rules (``ChatTurnNormalizer``) are the implementation's job, so a
/// history that drifted out of strict alternation never reaches a template.
@MainActor
protocol TutorGenerating: AnyObject {
    /// The model in memory and ready to answer, if any.
    var readyModel: MLXModel? { get }
    /// Why the last load failed, worded for the learner. `nil` after a successful load.
    var loadFailure: String? { get }
    /// True when `model` was dropped to free memory (iOS sheds it in the background) and the
    /// screen using it should bring it back.
    func wasEvicted(_ model: MLXModel) -> Bool
    /// Load `model`. On return it's `readyModel`, or `loadFailure` says why not.
    func loadTutor(_ model: MLXModel) async
    /// One prompt, one answer, at the low temperature checks need.
    func complete(system: String, user: String, model: MLXModel, maxTokens: Int) async throws -> String
    /// A chat reply, streamed into `onPartial` (think blocks already stripped).
    func streamReply(
        history: [(role: ChatRole, content: String)],
        system: String,
        model: MLXModel,
        maxTokens: Int,
        temperature: Float,
        onPartial: @escaping (String) -> Void
    ) async throws -> String
    /// A learner-readable message for an error this runtime threw, when it has a better one than
    /// `localizedDescription`.
    func friendlyMessage(for error: Error) -> String?
}

extension TutorGenerating {
    func isReady(_ model: MLXModel) -> Bool { readyModel == model }
    func friendlyMessage(for error: Error) -> String? { nil }
}

/// Token budgets and temperatures for each kind of tutor call, in one place so both runtimes
/// answer alike. The values are the ones the iOS app shipped with.
enum TutorBudget {
    /// The correction pass on one learner line (FIX/WHY/HINT).
    static let correction = 120
    /// A tutor reply's English translation.
    static let translation = 220
    /// A correction's English meaning.
    static let correctionTranslation = 160
    /// "Say it in German": the learner's English as one German sentence.
    static let phrase = 120
    /// The end-of-session coaching summary.
    static let summary = 360
    /// A tapped word's translation.
    static let word = 48
    /// "What could I say?": `count` suggestions, one line each.
    static func hints(_ count: Int) -> Int { 80 + count * 60 }

    /// The tutor's opening line.
    static let opener = 200
    /// A tutor reply in the conversation.
    static let reply = 220
    /// Chat replies' sampling temperature (checks run at the runtime's low default).
    static let replyTemperature: Float = 0.7
}
