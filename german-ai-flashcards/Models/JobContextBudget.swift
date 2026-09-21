import Foundation

/// How much of a job posting reaches the recruiter prompt, in characters.
///
/// The posting shares the tutor's reading window with the conversation itself, and that window
/// is not the same on every phone: under Memory Saver the KV cache rotates past
/// `MemorySaver.maxKVSize` tokens, so anything longer than that is evicted mid-interview anyway.
/// German runs at roughly three characters per token, which is what these numbers assume.
///
/// The setup screen, the clipper's meter, and the injected prompt all read the same function, so
/// the number the learner sees is the number the model gets.
@MainActor
enum JobContextBudget {
    /// Characters of posting text injected for `model` on this device, right now.
    static func characters(for model: MLXModel) -> Int {
        let base = baseCharacters(for: model)
        return MemorySaver.isActive(for: model) ? min(base, saverCharacters) : base
    }

    /// The cap while Memory Saver governs generation: about 500 tokens, leaving the rest of the
    /// 1,024-token rotating cache for the interview.
    static let saverCharacters = 1_500

    /// The cap by tutor alone, before the device has a say.
    static func baseCharacters(for model: MLXModel) -> Int {
        switch model {
        case .gemma4_E4B_german: 6_000
        case .gemma4_E2B_german: 4_500
        case .granite41_3B_german, .granite2B_german: 3_000
        case .appleIntelligence: 3_000   // a 4,096-token window shared with the whole chat
        }
    }

    /// "2,340 / 5,000"
    static func label(used: Int, cap: Int) -> String {
        "\(used.formatted()) / \(cap.formatted())"
    }

    /// Why this tutor gets the cap it does on this phone, for the info sheet.
    static func reason(for model: MLXModel) -> String {
        if MemorySaver.isActive(for: model) {
            return "Memory Saver is on for \(model.rawValue) on this phone. It keeps the tutor's memory of the conversation to about a thousand words, so the posting is trimmed to leave room for the interview itself."
        }
        switch model {
        case .appleIntelligence:
            return "Apple Intelligence reads about 4,000 tokens in total, shared between the posting, the recruiter's instructions, and the conversation."
        case .gemma4_E4B_german:
            return "The largest tutor reads the most. A whole posting usually fits, so bring the sections you want the recruiter to ask about."
        case .gemma4_E2B_german:
            return "A mid-sized tutor. Room for the tasks and the profile in full; benefits and the application process are best left out."
        case .granite41_3B_german, .granite2B_german:
            return "The small tutors keep a shorter window so the interview stays quick on 4 GB phones. Bring the tasks and the profile and leave the rest."
        }
    }
}
