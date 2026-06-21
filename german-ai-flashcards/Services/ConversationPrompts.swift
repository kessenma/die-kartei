import Foundation

/// Builds the prompts that steer the on-device model for conversation, correction,
/// translation, and the end-of-session coaching summary — and parses their output.
enum ConversationPrompts {

    // MARK: - Conversation system prompt

    static func systemPrompt(for config: ConversationConfig) -> String {
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

        // Learned phrases the user has heard in the wild and wants to get used to hearing.
        // These are things YOUR character would say to the learner — work them in naturally.
        if !config.learnedPhrases.isEmpty {
            let list = config.learnedPhrases
                .map { "«\($0.german)» (means: \($0.english))" }
                .joined(separator: ", ")
            parts.append("The learner has heard these German phrases in real life and wants to get used to hearing them. Naturally bring them into the conversation as things YOU (in your role) would say to the learner, and steer the scene so each one comes up. Say them in German exactly as written; do NOT translate or explain them in your replies: \(list).")
        }

        return parts.joined(separator: "\n\n")
    }

    /// The hidden seed turn that prompts the AI to open the conversation.
    static let openerSeed = "Beginne jetzt das Gespräch auf Deutsch mit einer kurzen, freundlichen Begrüßung und einer Frage an mich."

    // MARK: - Correction

    static func correctionSystemPrompt(for config: ConversationConfig) -> String {
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

    static func correctionUserPrompt(partnerLine: String?, studentLine: String) -> String {
        if let partnerLine, !partnerLine.isEmpty {
            return "The conversation partner just said: \"\(partnerLine)\"\nThe student replied: \"\(studentLine)\"\n\nEvaluate only the student's reply."
        }
        return "The student said: \"\(studentLine)\"\n\nEvaluate the student's sentence."
    }

    struct CorrectionResult {
        var correctedText: String?
        var note: String?
        var isClean: Bool { correctedText == nil }
    }

    /// Parse the correction model output into a structured result.
    static func parseCorrection(_ raw: String, original: String) -> CorrectionResult {
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

    static let translationSystemPrompt =
        "You are a professional German-to-English translator. You ONLY translate. You never answer, continue, react to, or have a conversation about the text — you just render it in English."

    /// Framed user prompt — small models follow an instruction in the user turn (ending with
    /// "English:") far more reliably than a system-only instruction, which they tend to ignore
    /// and instead *reply* to the German in German.
    static func translationUserPrompt(german: String) -> String {
        """
        Translate the German text below into natural English. \
        Output ONLY the English translation — no German, no quotation marks, no notes, and do not answer or continue the text.

        German: \(german)
        English:
        """
    }

    static func cleanTranslation(_ raw: String) -> String {
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

    // MARK: - Phrase check (library validation)

    struct PhraseCheckResult {
        /// The natural German phrase the model confirmed or produced.
        var german: String
        /// A natural English translation.
        var english: String
        /// True when the model adjusted the learner's German (vs. confirming it was already fine).
        var fixed: Bool
        /// A short note on what was off, if any.
        var note: String?
        /// Scenarios the model suggested for this phrase (only when `suggestScenarios` was requested).
        var scenarios: [ConversationScenario] = []
        /// Grammar structures the model tagged (only when `suggestGrammar` was requested).
        var focusAreas: [GrammarFocus] = []
    }

    /// The allowed scenario keys (rawValue) and their short English label, for the suggest prompt.
    private static var phraseScenarioKeyList: String {
        ConversationScenario.allCases
            .filter { $0 != .custom }
            .map { "- \($0.rawValue): \($0.englishTitle)" }
            .joined(separator: "\n")
    }

    /// The allowed grammar keys (rawValue) and their short English label, for the suggest prompt.
    private static var phraseGrammarKeyList: String {
        GrammarFocus.allCases
            .map { "- \($0.rawValue): \($0.englishLabel)" }
            .joined(separator: "\n")
    }

    static func phraseCheckSystemPrompt(
        inputIsGerman: Bool,
        suggestScenarios: Bool = false,
        suggestGrammar: Bool = false
    ) -> String {
        var s = "You are a meticulous German teacher helping a learner save a phrase they heard in real life so they can practice it. "
        if inputIsGerman {
            s += "The learner typed what they think they heard, in German. Confirm it, or fix it into the natural German a real speaker would actually say. "
        } else {
            s += "The learner typed what they want in English. Render it as the natural German a real speaker would actually say. "
        }
        s += "Reply in EXACTLY this format and nothing else — each line starting with its label:\n"
        s += "GERMAN: <the natural German phrase>\n"
        s += "ENGLISH: <a natural English translation>\n"
        s += "STATUS: <OK if the German needed no change, or FIXED if you changed or produced it>\n"
        s += "NOTE: <at most 15 words on what was off, or leave blank>\n"
        if suggestScenarios {
            s += "SCENARIOS: <1 to 3 keys from the scenario list, comma-separated — where a learner is most likely to hear this>\n"
        }
        if suggestGrammar {
            s += "GRAMMAR: <0 to 2 keys from the grammar list, comma-separated — the main structure(s) this phrase shows, or leave blank if none stands out>\n"
        }
        s += "\n"
        if suggestScenarios {
            s += "Scenario keys (use the key exactly as written):\n\(phraseScenarioKeyList)\n\n"
        }
        if suggestGrammar {
            s += "Grammar keys (use the key exactly as written):\n\(phraseGrammarKeyList)\n\n"
        }
        s += "Example:\n"
        s += "GERMAN: Sonst noch etwas?\n"
        s += "ENGLISH: Anything else?\n"
        s += "STATUS: OK\n"
        s += "NOTE:"
        if suggestScenarios { s += "\nSCENARIOS: bakery, cafe" }
        if suggestGrammar { s += "\nGRAMMAR:" }
        return s
    }

    static func phraseCheckUserPrompt(_ input: String) -> String {
        "Phrase: \"\(input.trimmingCharacters(in: .whitespacesAndNewlines))\""
    }

    /// Parse the phrase-check output. Returns nil if no usable German line was produced.
    static func parsePhraseCheck(_ raw: String) -> PhraseCheckResult? {
        let cleaned = stripThinkBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        var german: String?
        var english: String?
        var status: String?
        var note: String?
        var scenarioKeys: String?
        var grammarKeys: String?

        for rawLine in cleaned.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let r = matchPrefix(line, prefixes: ["GERMAN:", "German:", "Deutsch:", "DE:"]) {
                german = stripWrappingQuotes(r)
            } else if let r = matchPrefix(line, prefixes: ["ENGLISH:", "English:", "Englisch:", "EN:"]) {
                english = stripWrappingQuotes(r)
            } else if let r = matchPrefix(line, prefixes: ["STATUS:", "Status:"]) {
                status = r.uppercased()
            } else if let r = matchPrefix(line, prefixes: ["NOTE:", "Note:", "Notiz:"]) {
                note = r.trimmingCharacters(in: .whitespaces)
            } else if let r = matchPrefix(line, prefixes: ["SCENARIOS:", "Scenarios:", "SCENARIO:", "Scenario:", "Szenarien:"]) {
                scenarioKeys = r
            } else if let r = matchPrefix(line, prefixes: ["GRAMMAR:", "Grammar:", "Grammatik:"]) {
                grammarKeys = r
            }
        }

        // Lenient fallback: a small model sometimes drops the labels and just echoes the German
        // phrase. If there's no GERMAN line but the whole reply is a single short line, treat that
        // as the German so the user still gets a usable result.
        if german == nil {
            let lines = cleaned.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if lines.count == 1, lines[0].count <= 120 {
                german = stripWrappingQuotes(lines[0])
            }
        }

        guard let germanText = german?.trimmingCharacters(in: .whitespacesAndNewlines), !germanText.isEmpty else {
            return nil
        }
        let fixed = status?.contains("FIX") ?? false
        let cleanedNote = (note?.isEmpty == false) ? note : nil
        return PhraseCheckResult(
            german: germanText,
            english: english?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            fixed: fixed,
            note: cleanedNote,
            scenarios: parseScenarioKeys(scenarioKeys),
            focusAreas: parseGrammarKeys(grammarKeys)
        )
    }

    /// Map a comma/semicolon/slash-separated key list onto known scenarios (matched leniently by
    /// rawValue, German title, or English title). Unknown tokens are dropped.
    private static func parseScenarioKeys(_ raw: String?) -> [ConversationScenario] {
        let matched = keyTokens(raw).compactMap { token in
            ConversationScenario.allCases.first {
                $0 != .custom && (
                    $0.rawValue.lowercased() == token
                    || $0.germanTitle.lowercased() == token
                    || $0.englishTitle.lowercased() == token
                )
            }
        }
        return deduped(matched)
    }

    /// Map a key list onto known grammar structures. Unknown tokens (e.g. "none") are dropped.
    private static func parseGrammarKeys(_ raw: String?) -> [GrammarFocus] {
        let matched = keyTokens(raw).compactMap { token in
            GrammarFocus.allCases.first {
                $0.rawValue.lowercased() == token
                || $0.germanLabel.lowercased() == token
                || $0.englishLabel.lowercased() == token
            }
        }
        return deduped(matched)
    }

    /// Split a model-produced key list into normalized, lowercased tokens.
    private static func keyTokens(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw
            .components(separatedBy: CharacterSet(charactersIn: ",;/\n"))
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Order-preserving dedupe.
    private static func deduped<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }

    // MARK: - Summary

    static func summarySystemPrompt(for config: ConversationConfig) -> String {
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

    static func transcript(from messages: [ChatMessage]) -> String {
        messages
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { msg in
                let speaker = msg.isUser ? "STUDENT" : "PARTNER"
                return "\(speaker): \(msg.text)"
            }
            .joined(separator: "\n")
    }

    /// Parse the coaching report into structured arrays. Falls back to raw text.
    static func parseSummary(_ raw: String) -> (strengths: [String], improvements: [String], pattern: String) {
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
    static func matchedWords(in text: String, targetWords: [String]) -> [String] {
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
    static func stripThinkBlocks(_ text: String) -> String {
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
