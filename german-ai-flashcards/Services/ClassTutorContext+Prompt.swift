import Foundation

// The prompt text of `ClassTutorContext`, apart from its SwiftData fetches so the conversation
// prompts build for Android too (DieKarteiCore declares the empty namespace there).
extension ClassTutorContext {
    /// The system-prompt section around the text.
    nonisolated static func promptSection(_ text: String) -> String {
        """
        The learner is taking a German class. This is what it covered recently:
        \"\"\"
        \(text)
        \"\"\"
        Where it fits naturally, use words and topics from the class and give the learner chances to \
        use its grammar. Do not quiz them on it, and do not mention the class unless they do.
        """
    }
}
