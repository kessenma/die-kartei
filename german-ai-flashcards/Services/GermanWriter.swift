import Foundation
import Combine
import FoundationModels
import NaturalLanguage

/// The two things the German writing helpers do to text, and the prompts behind them.
///
/// Shared by the iOS keyboard extension and the Mac's Services menu and Schreibhilfe panel. The file
/// lives in the app target; the keyboard compiles it through a membership exception in the project
/// (it can't link the app). Both run on Apple's on-device model through `FoundationModels`.
/// Measured on an iPhone 17 Pro inside the extension: 1.75s to first token, 3.74s for a full email,
/// and a 3.7 MB footprint delta — the weights live in a system process, so only the session and the
/// response are charged to the caller.
///
/// Everything here is `nonisolated`, and `perform` is `@concurrent`, on purpose: the Mac's Services
/// handler waits for the result on the main thread, so a hidden hop back to the main actor (which is
/// this project's default isolation) would hang until the request times out. Keep new helpers here
/// nonisolated too.
nonisolated enum GermanWriting {

    nonisolated enum Job: String, CaseIterable, Identifiable, Sendable {
        /// English draft in, German out.
        case translate
        /// German in, corrected German out. The learner wrote it; keep their voice.
        case correct

        var id: String { rawValue }

        var title: String {
            switch self {
            case .translate: return "Auf Deutsch"
            case .correct:   return "Korrigieren"
            }
        }

        var symbol: String {
            switch self {
            case .translate: return "character.book.closed"
            case .correct:   return "checkmark.bubble"
            }
        }
    }

    nonisolated enum Address: String, CaseIterable, Identifiable, Sendable {
        case sie = "Sie"
        case du = "du"
        var id: String { rawValue }

        var instruction: String {
            switch self {
            case .sie: return "Address the reader formally, with Sie and Ihr."
            case .du:  return "Address the reader informally, with du and dein."
            }
        }
    }

    nonisolated struct Outcome: Sendable, Equatable {
        let text: String
        /// The reply ran into the token cap and may stop mid-sentence. The model says nothing when
        /// that happens, so this is worked out from the token count.
        let possiblyTruncated: Bool
    }

    nonisolated enum Failure: Error, Sendable, Equatable {
        case unavailable(String)
        case empty
        /// Over `limit` characters, or (nil) too long for the model's context window.
        case tooLong(limit: Int?)
        case declined
        /// The reply wasn't German: usually the model explaining, in English, why it won't help.
        case notGerman(String)
        case busy
        case rateLimited
        case unsupportedLanguage
        case timedOut
        case cancelled
        case other(String)

        var message: String {
            switch self {
            case .unavailable(let reason):
                return reason
            case .empty:
                return "There's no text to work on."
            case .tooLong(let limit?):
                return "That's over \(limit.formatted()) characters. Try a shorter piece."
            case .tooLong(nil):
                return "That's too long for Apple's on-device model. Try a shorter piece."
            case .declined:
                return "Apple's model declined to rewrite this text."
            case .notGerman:
                return "The reply didn't come back in German, so nothing was changed."
            case .busy:
                return "Still working on the last one."
            case .rateLimited:
                return "Apple's model is busy. Try again in a moment."
            case .unsupportedLanguage:
                return "Apple's model can't work with this language."
            case .timedOut:
                return "That took too long, so nothing was changed."
            case .cancelled:
                return "Stopped."
            case .other(let description):
                return description
            }
        }
    }

    // MARK: - Limits

    /// The reply cap. Generous, because a long reply cut mid-sentence is worse than a slow one.
    static let maximumResponseTokens = 900

    /// Longest text replaced in place by a Services request. The requesting app freezes while it
    /// waits, so a request has to finish in seconds; anything longer goes to the panel instead.
    static let inPlaceLimit = 1_500

    /// Longest text taken at all. With the instructions and a 900-token reply it stays inside the
    /// model's 4,096-token context (German runs about three to four characters a token).
    static let panelLimit = 4_000

    // MARK: - Availability

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Why the model can't be used, or nil if it can. The same switch as the app's
    /// `AppleIntelligenceService`, which the keyboard extension can't reach.
    static var unavailableReason: String? {
        reason(for: SystemLanguageModel.default.availability)
    }

    static func reason(for availability: SystemLanguageModel.Availability) -> String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                #if os(macOS)
                return "This Mac doesn't support Apple Intelligence."
                #else
                return "This iPhone doesn't support Apple Intelligence."
                #endif
            case .appleIntelligenceNotEnabled:
                #if os(macOS)
                return "Turn on Apple Intelligence in System Settings to use the writing helper."
                #else
                return "Turn on Apple Intelligence in Settings to use this keyboard."
                #endif
            case .modelNotReady:
                return "Apple Intelligence is still preparing. Try again shortly."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    // MARK: - Running a job

    /// Runs `job` on `text`. Streaming reports each cumulative snapshot through `onPartial`; the
    /// Services path doesn't stream, because Apple advises the plain response for a caller that
    /// isn't the frontmost app (a streamed one is rate-limited there).
    ///
    /// `address` nil means: translate formally, and correct without touching the writer's own Sie
    /// or du.
    @concurrent
    static func perform(
        _ job: Job,
        on text: String,
        address: Address?,
        streaming: Bool,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async -> Result<Outcome, Failure> {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return .failure(.empty) }
        guard input.count <= panelLimit else { return .failure(.tooLong(limit: panelLimit)) }

        // Permissive guardrails: rewriting the user's own text is a content transformation, and
        // the default guardrails refuse ordinary emails often enough to matter. The model can still
        // decline in words, which the German check below catches.
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        if let reason = reason(for: model.availability) { return .failure(.unavailable(reason)) }

        let session = LanguageModelSession(model: model, instructions: instructions(for: job, address: address))
        // Low temperature: this is a faithful rewrite, not a creative one.
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: maximumResponseTokens)

        do {
            var raw = ""
            var outputTokens: Int?
            if streaming {
                for try await snapshot in session.streamResponse(to: input, options: options) {
                    try Task.checkCancellation()
                    raw = snapshot.content
                    onPartial?(raw)
                    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                        outputTokens = snapshot.usage.output.totalTokenCount
                    }
                }
            } else {
                let response = try await session.respond(to: input, options: options)
                raw = response.content
                if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
                    outputTokens = response.usage.output.totalTokenCount
                }
            }
            try Task.checkCancellation()

            let result = clean(raw)
            guard !result.isEmpty else { return .failure(.declined) }
            guard isGerman(result) else { return .failure(.notGerman(result)) }

            if outputTokens == nil, #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
                outputTokens = try? await model.tokenCount(for: raw)
            }
            return .success(Outcome(text: result, possiblyTruncated: isTruncated(outputTokens: outputTokens, raw: raw)))
        } catch {
            return .failure(failure(for: error))
        }
    }

    /// Whether the reply hit the cap. Without a count (before 26.4) it estimates three characters a
    /// token, which overcounts German and so errs toward flagging.
    static func isTruncated(outputTokens: Int?, raw: String) -> Bool {
        (outputTokens ?? raw.count / 3) >= maximumResponseTokens - 2
    }

    static func failure(for error: any Error) -> Failure {
        if error is CancellationError { return .cancelled }
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            if let error = error as? LanguageModelError {
                switch error {
                case .contextSizeExceeded: return .tooLong(limit: nil)
                case .rateLimited: return .rateLimited
                case .guardrailViolation, .refusal: return .declined
                case .unsupportedLanguageOrLocale: return .unsupportedLanguage
                case .timeout: return .timedOut
                default: return .other(error.localizedDescription)
                }
            }
            if let error = error as? LanguageModelSession.Error {
                switch error {
                case .concurrentRequests: return .busy
                default: return .other(error.localizedDescription)
                }
            }
            if error is SystemLanguageModel.Error {
                return .unavailable("Apple Intelligence is still preparing. Try again shortly.")
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return .tooLong(limit: nil)
            case .assetsUnavailable: return .unavailable("Apple Intelligence is still preparing. Try again shortly.")
            case .guardrailViolation, .refusal: return .declined
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            case .rateLimited: return .rateLimited
            case .concurrentRequests: return .busy
            default: return .other(error.localizedDescription)
            }
        }
        return .other(error.localizedDescription)
    }

    /// Whether a reply is German. Short replies pass: a greeting or a one-word fix carries too
    /// little for the recognizer, and a refusal is never that short.
    static func isGerman(_ text: String) -> Bool {
        guard text.count >= 20 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if recognizer.dominantLanguage == .german { return true }
        return (recognizer.languageHypotheses(withMaximum: 2)[.german] ?? 0) >= 0.5
    }

    /// The result, wrapped in the original's own leading and trailing whitespace. `clean` trims the
    /// reply, and a selection that ended in a line break would otherwise run into the next paragraph.
    static func replacement(for original: String, with result: String) -> String {
        let leading = original.prefix(while: \.isWhitespace)
        let trailing = original.reversed().prefix(while: \.isWhitespace).reversed()
        guard leading.count < original.count else { return original }
        return String(leading) + result + String(trailing)
    }

    // MARK: - Prompts

    /// The translate prompt's last three rules were tuned against the model on 2026-10-04 (macOS
    /// 27.2, five runs of five emails). Without the title rule, „Dear Mr. Schneider" came back as
    /// Frau every time, and „my order" as Ihre Bestellung in most runs. Phrasing it as "never add a
    /// greeting or sign-off" made it drop the real sign-off; quoting example greetings made it
    /// invent one for a one-line text. Rerun that comparison before changing the wording.
    static func instructions(for job: Job, address: Address?) -> String {
        switch job {
        case .translate:
            return """
            You rewrite the user's English text as natural German. Reply with the German only: no \
            preamble, no notes, no English, no quotation marks around the whole reply, and no \
            explanation of what you changed.

            \((address ?? .sie).instruction)

            Preserve the meaning, the tone, and every name, date, number and amount exactly as \
            given. Write numbers and dates the way German writes them. Keep the text's shape: if \
            it is one sentence, reply with one sentence; if it is an email with a greeting and a \
            sign-off, keep both. Translate every part, the greeting and the sign-off included, and \
            add none of your own. Keep each person's title: Mr. is always Herr, and Ms. and Mrs. \
            are always Frau. Keep whose things are whose: the writer's my stays mein. \(surnameRule)
            """
        case .correct:
            return """
            You correct German text. Reply with the corrected German only: no preamble, no notes, \
            no English, and no explanation of what you changed.

            \(address?.instruction ?? keepAddress)

            Fix grammar, case endings, word order, and spelling. Keep the writer's own words and \
            register wherever they are already correct — this is their sentence, not yours, so do \
            not rewrite it to sound more elegant. If a word is English because they did not know \
            the German, replace it with the German. If the text is already correct, reply with it \
            unchanged. \(surnameRule)
            """
        }
    }

    static let keepAddress = """
    Keep the writer's own form of address (Sie or du) exactly as they wrote it.
    """

    /// The model wrote „Sehr geehrter Herr Thomas" for a first name during the probe. German
    /// formal address takes a surname, and getting it wrong is the kind of mistake the reader
    /// notices immediately.
    static let surnameRule = """
    In a formal greeting use the recipient's surname; if only a first name is known, greet with \
    "Hallo <name>," rather than attaching Herr or Frau to a first name.
    """

    /// Models occasionally wrap a reply in quotes or fence it despite being told not to.
    static func clean(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("```") {
            out = out.drop(while: { $0 != "\n" }).trimmingCharacters(in: .whitespacesAndNewlines)
            if let fence = out.range(of: "```", options: .backwards) {
                out = String(out[..<fence.lowerBound])
            }
        }
        // Only when the whole reply is wrapped — a quotation inside the text must survive.
        for (open, close) in [("\"", "\""), ("“", "”"), ("„", "“")] {
            if out.hasPrefix(open), out.hasSuffix(close), out.count > open.count + close.count {
                out = String(out.dropFirst(open.count).dropLast(close.count))
                break
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The observable face of `GermanWriting` for SwiftUI: whether it's working, the German as it
/// streams in, and the last error. The keyboard's bar and the Mac's Schreibhilfe panel both hold one.
@MainActor
final class GermanWriter: ObservableObject {

    typealias Job = GermanWriting.Job
    typealias Address = GermanWriting.Address

    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?

    /// Cumulative output as it streams, so the bar can show the German arriving.
    @Published private(set) var partial = ""

    /// The last result may stop mid-sentence (it ran into the reply cap).
    @Published private(set) var lastWasTruncated = false

    private var runID = UUID()

    var isAvailable: Bool { GermanWriting.isAvailable }
    var unavailableReason: String? { GermanWriting.unavailableReason }

    func run(_ job: Job, on text: String, address: Address?) async -> String? {
        guard !isWorking else { return nil }
        isWorking = true
        partial = ""
        lastError = nil
        lastWasTruncated = false
        let id = UUID()
        runID = id
        defer { isWorking = false }

        let result = await GermanWriting.perform(job, on: text, address: address, streaming: true) { [weak self] snapshot in
            Task { @MainActor [weak self] in
                // A snapshot that lands after the run finished would overwrite the final text.
                guard let self, self.isWorking, self.runID == id else { return }
                self.partial = snapshot
            }
        }
        switch result {
        case .success(let outcome):
            partial = outcome.text
            lastWasTruncated = outcome.possiblyTruncated
            return outcome.text
        case .failure(let failure):
            lastError = failure.message
            return nil
        }
    }
}
