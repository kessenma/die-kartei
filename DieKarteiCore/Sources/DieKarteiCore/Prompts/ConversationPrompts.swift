import Foundation

/// One line of a conversation transcript, decoupled from any persistence model.
/// The iOS app maps SwiftData `ChatMessage` objects into these; an Android host
/// maps its own message records the same way.
public struct TranscriptLine {
    public var isUser: Bool
    public var text: String
    public var sortOrder: Int

    public init(isUser: Bool, text: String, sortOrder: Int) {
        self.isUser = isUser
        self.text = text
        self.sortOrder = sortOrder
    }
}

/// Builds the prompts that steer the on-device model for conversation, correction,
/// translation, and the end-of-session coaching summary — and parses their output.
public enum ConversationPrompts {

    // MARK: - Conversation system prompt

    public static func systemPrompt(for config: ConversationConfig) -> String {
        var parts: [String] = []

        // Role / persona
        if config.mode == .paper {
            let context = (config.paperContext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append("""
            You are a German academic examiner and discussion partner — a friendly but probing thesis-committee member. \
            The learner has studied a German paper titled "\(config.paperTitle ?? "das Papier")" and wants to discuss it with you and be quizzed on it, in German. \
            Use the following material as your knowledge of the paper, and base your questions and comments on it:

            \"\"\"
            \(context)
            \"\"\"

            Ask thoughtful questions about the paper's content, probe the learner's understanding, gently correct mistaken claims about the paper, and keep the whole discussion in German.
            """)
        } else if config.mode == .scenario {
            if config.scenario == .custom {
                let custom = config.customScenario.trimmingCharacters(in: .whitespacesAndNewlines)
                parts.append("You are role-playing the following situation with a German learner: \(custom). Stay fully in character and set the scene.")
            } else if let role = config.scenario?.roleInstruction {
                parts.append(role)
            }
        } else {
            parts.append("You are Lena, a warm and patient German conversation partner helping someone practice spoken German.")
        }

        // Core conversational rules
        parts.append("Speak ONLY in German. " + config.level.promptInstruction + " " + config.formality.promptInstruction)
        parts.append("Keep your replies short — usually one to three sentences — and end most replies with a question so the conversation keeps flowing.")
        parts.append("The learner is speaking out loud, so their words may contain small transcription glitches and they may mix in an English word when they don't know the German one. Understand them charitably and simply continue the conversation in natural German.")
        parts.append("Do NOT correct the learner, and do NOT add translations, explanations, or any English in your replies. Just have a natural conversation.")

        // Grammar focus steering
        if !config.focusAreas.isEmpty {
            let names = config.focusAreas.map { $0.germanLabel }.joined(separator: ", ")
            let hints = config.focusAreas.map { "- \($0.steeringHint)" }.joined(separator: "\n")
            parts.append("Gently steer the conversation so the learner naturally practices these structures: \(names). To do that, \(config.focusAreas.count == 1 ? "" : "for example ")ask questions like:\n\(hints)")
        }

        // Deck vocabulary
        if config.mode == .decks, !config.deckWords.isEmpty {
            let sample = config.deckWords.prefix(24).joined(separator: ", ")
            parts.append("The learner is studying these German words; weave a few of them naturally into your questions and replies, and encourage the learner to use them: \(sample).")
        }

        return parts.joined(separator: "\n\n")
    }

    /// The hidden seed turn that prompts the AI to open the conversation.
    public static let openerSeed = "Beginne jetzt das Gespräch auf Deutsch mit einer kurzen, freundlichen Begrüßung und einer Frage an mich."

    // MARK: - Correction

    public static func correctionSystemPrompt(for config: ConversationConfig) -> String {
        var s = "You are a meticulous German teacher reviewing one line a student said during a spoken conversation. "
        s += "The student's level is \(config.level.rawValue). "
        s += config.strictness.promptInstruction + " "
        if !config.focusAreas.isEmpty {
            let names = config.focusAreas.map { "\($0.germanLabel) (\($0.englishLabel))" }.joined(separator: ", ")
            s += "Pay particular attention to: \(names). "
        }
        s += "The student uses the \(config.formality.rawValue) form. "
        s += "They may have mixed in an English word they didn't know — in your correction, replace it with the correct German word.\n\n"
        s += "If the sentence is already correct and natural German, reply with exactly:\nOK\n\n"
        s += "Otherwise reply in EXACTLY this format and nothing else:\n"
        s += "FIX: <the full corrected sentence in natural German>\n"
        s += "WHY: <one short explanation in English, at most 18 words>"
        return s
    }

    public static func correctionUserPrompt(partnerLine: String?, studentLine: String) -> String {
        if let partnerLine, !partnerLine.isEmpty {
            return "The conversation partner just said: \"\(partnerLine)\"\nThe student replied: \"\(studentLine)\"\n\nEvaluate only the student's reply."
        }
        return "The student said: \"\(studentLine)\"\n\nEvaluate the student's sentence."
    }

    public struct CorrectionResult {
        public var correctedText: String?
        public var note: String?
        public var isClean: Bool { correctedText == nil }

        public init(correctedText: String? = nil, note: String? = nil) {
            self.correctedText = correctedText
            self.note = note
        }
    }

    /// Parse the correction model output into a structured result.
    public static func parseCorrection(_ raw: String, original: String) -> CorrectionResult {
        let cleaned = stripThinkBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines)

        // Treat a bare "OK" (the model's "no issues" signal) as clean.
        let upper = cleaned.uppercased()
        if cleaned.isEmpty || upper == "OK" || upper.hasPrefix("OK\n") || upper == "OK." {
            return CorrectionResult(correctedText: nil, note: nil)
        }

        var fix: String?
        var why: String?
        for rawLine in cleaned.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let r = matchPrefix(line, prefixes: ["FIX:", "FIX -", "Fix:", "Korrektur:"]) {
                fix = r
            } else if let r = matchPrefix(line, prefixes: ["WHY:", "WHY -", "Why:", "Grund:", "Erklärung:"]) {
                why = r
            }
        }

        guard var corrected = fix?.trimmingCharacters(in: .whitespacesAndNewlines), !corrected.isEmpty else {
            // No parseable FIX line — assume nothing actionable.
            return CorrectionResult(correctedText: nil, note: nil)
        }
        corrected = stripWrappingQuotes(corrected)

        // If the "correction" is identical to what the student said, treat as clean.
        if corrected.compare(original.trimmingCharacters(in: .whitespacesAndNewlines),
                             options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return CorrectionResult(correctedText: nil, note: nil)
        }

        let note = why?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CorrectionResult(correctedText: corrected, note: (note?.isEmpty == false) ? note : nil)
    }

    // MARK: - Translation

    public static let translationSystemPrompt =
        "You are a professional German-to-English translator. You ONLY translate. You never answer, continue, react to, or have a conversation about the text — you just render it in English."

    /// Framed user prompt — small models follow an instruction in the user turn (ending with
    /// "English:") far more reliably than a system-only instruction, which they tend to ignore
    /// and instead *reply* to the German in German.
    public static func translationUserPrompt(german: String) -> String {
        """
        Translate the German text below into natural English. \
        Output ONLY the English translation — no German, no quotation marks, no notes, and do not answer or continue the text.

        German: \(german)
        English:
        """
    }

    public static func cleanTranslation(_ raw: String) -> String {
        var s = stripThinkBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip a leading label the model sometimes echoes back.
        for label in ["English:", "English translation:", "Translation:", "EN:", "Englisch:"] {
            if s.lowercased().hasPrefix(label.lowercased()) {
                s = String(s.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        // Keep only the first paragraph if the model rambled past the translation.
        if let firstBlank = s.range(of: "\n\n") {
            s = String(s[..<firstBlank.lowerBound])
        }
        return stripWrappingQuotes(s)
    }

    // MARK: - Summary

    public static func summarySystemPrompt(for config: ConversationConfig) -> String {
        var s = "You are a supportive German language coach. Below is a transcript of a conversation-practice session between a STUDENT (the learner, level \(config.level.rawValue)) and a PARTNER (the AI). "
        s += "Analyze the STUDENT's German across the whole conversation and write a short, encouraging coaching report in ENGLISH.\n\n"
        if !config.focusAreas.isEmpty {
            let names = config.focusAreas.map { $0.germanLabel }.joined(separator: ", ")
            s += "The student was focusing on: \(names). Comment on how they handled these.\n\n"
        }
        s += "Reply in EXACTLY this format:\n"
        s += "STRENGTHS:\n- <something the student did well>\n- <something else they did well>\n"
        s += "IMPROVE:\n- <a specific, actionable area to work on>\n- <another specific area>\n"
        s += "PATTERN: <one sentence naming a recurring habit you noticed, good or bad>\n\n"
        s += "Base everything only on the student's lines. Be specific about grammar, vocabulary, and structures. If the student barely spoke, say so kindly."
        return s
    }

    public static func transcript(from lines: [TranscriptLine]) -> String {
        lines
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { line in
                let speaker = line.isUser ? "STUDENT" : "PARTNER"
                return "\(speaker): \(line.text)"
            }
            .joined(separator: "\n")
    }

    /// Parse the coaching report into structured arrays. Falls back to raw text.
    public static func parseSummary(_ raw: String) -> (strengths: [String], improvements: [String], pattern: String) {
        let cleaned = stripThinkBlocks(raw)
        var strengths: [String] = []
        var improvements: [String] = []
        var pattern = ""

        enum Section { case none, strengths, improve }
        var section: Section = .none

        for rawLine in cleaned.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let upper = line.uppercased()
            if upper.hasPrefix("STRENGTH") { section = .strengths; continue }
            if upper.hasPrefix("IMPROVE") || upper.hasPrefix("AREAS") || upper.hasPrefix("TO IMPROVE") { section = .improve; continue }
            if upper.hasPrefix("PATTERN") {
                section = .none
                if let r = matchPrefix(line, prefixes: ["PATTERN:", "Pattern:", "PATTERN -"]) {
                    pattern = r.trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            let item = stripBullet(line)
            guard !item.isEmpty else { continue }
            switch section {
            case .strengths: strengths.append(item)
            case .improve:   improvements.append(item)
            case .none:      break
            }
        }

        return (strengths, improvements, pattern)
    }

    // MARK: - Vocabulary matching

    /// Returns which of `targetWords` appear in `text` (case/diacritic-insensitive, whole-word-ish).
    public static func matchedWords(in text: String, targetWords: [String]) -> [String] {
        guard !targetWords.isEmpty else { return [] }
        let haystack = " " + normalize(text) + " "
        var found: [String] = []
        for word in targetWords {
            // Strip a leading article ("der Tisch" -> "tisch") so spoken forms match.
            let core = word.split(separator: " ").last.map(String.init) ?? word
            let needle = normalize(core)
            guard needle.count >= 3 else { continue }
            if haystack.contains(" " + needle + " ")
                || haystack.contains(" " + needle)
                || haystack.contains(needle + " ") {
                found.append(word)
            }
        }
        return found
    }

    // MARK: - Helpers

    private static func normalize(_ s: String) -> String {
        let lowered = s.lowercased(with: Locale(identifier: "de_DE"))
        // Keep letters/spaces only; collapse punctuation to spaces.
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.letters.contains(scalar) || scalar == " " { return Character(scalar) }
            return " "
        }
        return String(scalars).replacingOccurrences(of: "  ", with: " ")
    }

    private static func matchPrefix(_ line: String, prefixes: [String]) -> String? {
        for p in prefixes where line.hasPrefix(p) {
            return String(line.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func stripBullet(_ line: String) -> String {
        var s = line
        for prefix in ["- ", "• ", "* ", "– ", "—  "] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func stripWrappingQuotes(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("„", "“"), ("'", "'")]
        for (open, close) in pairs where t.first == open && t.last == close && t.count >= 2 {
            t = String(t.dropFirst().dropLast())
            break
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove <think>…</think> reasoning blocks some models emit.
    public static func stripThinkBlocks(_ text: String) -> String {
        var cleaned = text
        while let range = cleaned.range(of: #"<think>[\s\S]*?</think>"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        // Drop a dangling unterminated <think> (truncated reasoning).
        if let open = cleaned.range(of: "<think>") {
            cleaned = String(cleaned[..<open.lowerBound])
        }
        return cleaned
    }
}
