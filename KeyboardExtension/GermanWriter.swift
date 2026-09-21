import Foundation
import FoundationModels

/// The two things this keyboard does to text, and the prompts behind them.
///
/// Both run on Apple's on-device model through `FoundationModels`. Measured on an iPhone 17 Pro
/// inside the extension: 1.75s to first token, 3.74s for a full email, and a 3.7 MB footprint
/// delta — the weights live in a system process, so only the session and the streamed response are
/// charged here.
@MainActor
final class GermanWriter: ObservableObject {

    enum Job: String, CaseIterable, Identifiable {
        /// English draft in, German email out.
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

    enum Address: String, CaseIterable, Identifiable {
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

    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?

    /// Cumulative output as it streams, so the bar can show the German arriving.
    @Published private(set) var partial = ""

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Why the model can't be used, or nil if it can. Copy lifted from the app's
    /// `AppleIntelligenceService`, which is the only other place this switch exists.
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This iPhone doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to use this keyboard."
            case .modelNotReady:
                return "Apple Intelligence is still preparing. Try again shortly."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    func run(_ job: Job, on text: String, address: Address) async -> String? {
        guard !isWorking else { return nil }
        isWorking = true
        partial = ""
        lastError = nil
        defer { isWorking = false }

        do {
            let session = LanguageModelSession { Self.instructions(for: job, address: address) }
            // Low temperature: this is a faithful rewrite, not a creative one. The cap is generous
            // because a long reply being cut mid-sentence is worse than a slow one.
            let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 900)
            var latest = ""
            for try await chunk in session.streamResponse(to: text, options: options) {
                latest = chunk.content
                partial = latest
            }
            let result = Self.clean(latest)
            return result.isEmpty ? nil : result
        } catch {
            lastError = "\(error)"
            return nil
        }
    }

    // MARK: - Prompts

    private static func instructions(for job: Job, address: Address) -> String {
        switch job {
        case .translate:
            return """
            You rewrite the user's English text as natural German. Reply with the German only: no \
            preamble, no notes, no English, no quotation marks around the whole reply, and no \
            explanation of what you changed.

            \(address.instruction)

            Preserve the meaning, the tone, and every name, date, number and amount exactly as \
            given. Write numbers and dates the way German writes them. Keep the text's shape: if \
            it is one sentence, reply with one sentence; if it is an email with a greeting and a \
            sign-off, keep both. \(surnameRule)
            """
        case .correct:
            return """
            You correct German text. Reply with the corrected German only: no preamble, no notes, \
            no English, and no explanation of what you changed.

            \(address.instruction)

            Fix grammar, case endings, word order, and spelling. Keep the writer's own words and \
            register wherever they are already correct — this is their sentence, not yours, so do \
            not rewrite it to sound more elegant. If a word is English because they did not know \
            the German, replace it with the German. If the text is already correct, reply with it \
            unchanged. \(surnameRule)
            """
        }
    }

    /// The model wrote „Sehr geehrter Herr Thomas" for a first name during the probe. German
    /// formal address takes a surname, and getting it wrong is the kind of mistake the reader
    /// notices immediately.
    private static let surnameRule = """
    In a formal greeting use the recipient's surname; if only a first name is known, greet with \
    "Hallo <name>," rather than attaching Herr or Frau to a first name.
    """

    /// Models occasionally wrap a reply in quotes or fence it despite being told not to.
    private static func clean(_ text: String) -> String {
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
