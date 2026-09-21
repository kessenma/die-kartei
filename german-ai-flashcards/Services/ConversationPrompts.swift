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
        } else if config.mode == .interview {
            let posting = (config.jobContext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let position = config.jobTitle.map { " for the position \"\($0)\"" } ?? ""
            // "at Company in City" when the setup captured them; nothing when it didn't, so older
            // chats keep the exact persona they were started with.
            let employer = [config.jobCompany, config.jobLocation]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " in ")
            let workplace = employer.isEmpty ? "" : " at \(employer)"
            let persona = config.interviewRound?.persona ?? "an experienced recruiter"
            let opener = config.interviewFormat?.openerClause ?? "welcome the candidate in one sentence"
            parts.append("""
            You are \(persona)\(workplace) conducting a job interview\(position), and the learner is the candidate. \
            The job posting below is your knowledge of the role. It may be written in German or English, but you conduct the entire interview in German:

            \"\"\"
            \(posting)
            \"\"\"

            How to run the interview:
            - Your first message: greet the candidate, \(opener), and in the SAME message ask them to introduce themselves briefly with regard to this role. Do not wait for a reply before asking that.
            - After the greeting, never ask about scheduling, timing, whether they have time for the call, or any other logistics. Every question is about the candidate's experience, skills, motivation, or a point from the interview plan below.
            - Work through the interview plan in order, one point per turn. Name the point in your question the way the posting phrases it, for example: „In der Ausschreibung steht ‚Kenntnisse in Webservice-Technologien‘. Wo haben Sie damit gearbeitet?"
            - React to each answer in one short sentence, then ask the next question. When an answer is vague or interesting, ask one follow-up about it before moving on.
            - When the plan is done, ask about their motivation for this role and company, then how they would handle a typical situation from the posting, then invite their own questions.
            - If the candidate asks about the job, answer from the posting. Stay in character as the interviewer for the whole session.
            """)
            let plan = interviewPlan(from: posting)
            if !plan.isEmpty {
                let numbered = plan.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                parts.append("Interview plan, taken from the posting:\n\(numbered)")
            }
            // Round and channel refine the script above; older chats have neither.
            let steering = [config.interviewRound?.promptInstruction, config.interviewFormat?.promptInstruction]
                .compactMap { $0 }
            if !steering.isEmpty {
                parts.append(steering.joined(separator: "\n"))
            }
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
        if let name = config.learnerName {
            parts.append("The learner's name is „\(name)“. When you address them by name, use exactly that, as written, and never invent a different name, title, or surname for them.")
        }
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

        // Spaced re-encounter: words the learner is due to review right now (SRS-timed). Steering
        // only — using one correctly is counted as a review in a separate pass, so never announce it.
        if !config.dueReviewWords.isEmpty {
            let list = config.dueReviewWords.prefix(8).joined(separator: ", ")
            parts.append("These specific words are due for the learner's spaced review right now: \(list). Make a natural, unforced effort to steer toward topics where the learner would want to say each one, and gently invite them to use it — but only where it fits the conversation. Never list these words, translate them, or mention that they're being reviewed.")
        }

        // Persistent coach memory (steering-only — correction happens in a separate pass).
        if !config.learnerBriefing.isEmpty {
            parts.append(config.learnerBriefing)
        }

        return parts.joined(separator: "\n\n")
    }

    /// The hidden seed turn that prompts the AI to open the conversation.
    static let openerSeed = "Beginne jetzt das Gespräch auf Deutsch mit einer kurzen, freundlichen Begrüßung und einer Frage an mich."

    /// The seed for this conversation. An interview's opener carries the whole greeting in one
    /// turn (greeting, the format's one-line check, and the request to introduce oneself) so the
    /// model doesn't spend its first exchanges on logistics.
    static func openerSeed(for config: ConversationConfig) -> String {
        let naming = config.learnerName.map { " Sprich mich mit „\($0)“ an." } ?? ""
        guard config.mode == .interview else { return openerSeed + naming }
        let check = config.interviewFormat?.openerSeedClause ?? "begrüße mich in einem Satz"
        return "Beginne jetzt das Vorstellungsgespräch auf Deutsch: begrüße mich kurz, \(check), und bitte mich im selben Beitrag, mich kurz vorzustellen und meinen bisherigen Werdegang in Bezug auf diese Stelle zu beschreiben." + naming
    }

    // MARK: - Interview plan

    /// The points an interviewer would work through, pulled from the posting: bullet items and
    /// short list lines under the tasks and profile headings first, other sections after, and
    /// nothing from benefits, the application process, or the company blurb. Small models follow
    /// a numbered list far better than "draw your questions from the posting".
    static func interviewPlan(from posting: String, limit: Int = 8) -> [String] {
        enum Section { case core, other, skip }
        let coreHeading = try! NSRegularExpression(pattern: #"aufgaben|erwartet|tätigkeit|taetigkeit|responsibil|what you|your role|about the role|profil|anforderung|qualifikation|voraussetzung|bringst du|bringen sie|requirement|qualification|skills|what you bring|who you are"#, options: [.caseInsensitive])
        let skipHeading = try! NSRegularExpression(pattern: #"wir bieten|bieten wir|benefit|vorteile|what we offer|why us|perks|bewerbung|dein weg|so geht|how to apply|application|kontakt|contact|über uns|ueber uns|das sind wir|unternehmen|about us|who we are|company"#, options: [.caseInsensitive])
        let bulletPrefix = try! NSRegularExpression(pattern: #"^\s*(?:[✓✔•●▪◦∙·\-–—*]+|\d{1,2}[.)])\s*"#)
        // The job title itself ("Senior iOS Developer (m/w/d)") is a short line, not a question.
        let titleMarker = try! NSRegularExpression(pattern: #"\(?\b[mwdx]\s*/\s*[mwdx](?:\s*/\s*[mwdx])?\b\)?"#, options: [.caseInsensitive])

        func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        func stripBullet(_ text: String) -> String? {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = bulletPrefix.firstMatch(in: text, range: range), match.range.length > 0,
                  let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        var section: Section = .other
        var core: [String] = []
        var other: [String] = []
        var seen: Set<String> = []

        for rawLine in posting.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let words = line.split(whereSeparator: \.isWhitespace).count

            // A short line that names a section switches the bucket for what follows.
            if line.count <= 60, words <= 8, stripBullet(line) == nil {
                if matches(skipHeading, line) { section = .skip; continue }
                if matches(coreHeading, line) { section = .core; continue }
            }
            guard section != .skip else { continue }

            var item: String?
            if let stripped = stripBullet(line), stripped.count >= 12 {
                item = stripped
            } else if words >= 4, words <= 14, line.count <= 110, !line.hasSuffix(":"),
                      !line.hasSuffix("."), !line.hasSuffix("!"), !line.hasSuffix("?") {
                item = line
            }
            guard var text = item, !matches(titleMarker, text) else { continue }
            if text.count > 120 { text = String(text.prefix(117)) + "…" }
            let key = text.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            if section == .core { core.append(text) } else { other.append(text) }
        }

        return Array((core + other).prefix(limit))
    }

    /// One line appended to the reply prompt each turn so the interviewer keeps moving through
    /// the plan instead of circling. `candidateTurns` counts the candidate's answers so far,
    /// including the one just given; the first answer is the self-introduction.
    static func interviewProgressNote(for config: ConversationConfig, candidateTurns: Int) -> String? {
        guard config.mode == .interview else { return nil }
        let plan = interviewPlan(from: config.jobContext ?? "")
        let next = candidateTurns - 1
        if plan.isEmpty {
            return "Progress: the candidate has answered \(candidateTurns) question(s). Ask about a concrete requirement or responsibility from the posting they have not covered yet, naming it as the posting phrases it."
        }
        if next < 0 {
            return "Progress: the candidate has not answered anything yet. Ask them to introduce themselves with regard to the role."
        }
        if next < plan.count {
            return "Progress: the candidate has answered \(candidateTurns) question(s). Plan point \(next + 1) is next: „\(plan[next])“. Ask about it now, unless their last answer needs one short follow-up first."
        }
        return "Progress: every plan point has been covered. Ask about their motivation for this role and company, then a typical situation from the posting, then invite their own questions."
    }

    // MARK: - Correction

    static func correctionSystemPrompt(for config: ConversationConfig) -> String {
        var s = "You are a meticulous German teacher reviewing one line a student said during a spoken conversation. "
        s += "The student's level is \(config.level.rawValue). "
        s += config.strictness.promptInstruction + " "
        if !config.focusAreas.isEmpty {
            let names = config.focusAreas.map { "\($0.germanLabel) (\($0.englishLabel))" }.joined(separator: ", ")
            s += "Pay particular attention to: \(names). "
        }
        if !config.correctionMemoryHint.isEmpty {
            s += config.correctionMemoryHint + " "
        }
        s += "The student uses the \(config.formality.rawValue) form. "
        s += "They may have mixed in an English word they didn't know — in your correction, replace it with the correct German word. "
        s += "Their line is a speech-recognition transcript, so punctuation is unreliable: NEVER correct punctuation. A missing or misplaced comma, period, or question mark is not a mistake — judge only the words.\n\n"
        s += "If the sentence is already correct and natural German, reply with exactly:\nOK\n\n"
        if config.feedbackStyle == .nudgeMe {
            // Elicitation: still give the fix (used to check the learner's retry and to reveal on
            // request), but also a German question that points at the mistake without giving away
            // the answer, so the learner can repair it themselves.
            s += "Otherwise reply in EXACTLY this format and nothing else:\n"
            s += "FIX: <the full corrected sentence in natural German>\n"
            s += "WHY: <one short explanation in English, at most 18 words>\n"
            s += "HINT: <a SHORT German question that points the student at their single main mistake so they can fix it themselves — e.g. \"Welcher Fall kommt nach 'mit'?\" or \"Wo steht das Verb in einem Nebensatz?\". Name the grammar category, but do NOT reveal the corrected word or sentence.>"
        } else {
            s += "Otherwise reply in EXACTLY this format and nothing else:\n"
            s += "FIX: <the full corrected sentence in natural German>\n"
            s += "WHY: <one short explanation in English, at most 18 words>"
        }
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
        /// The German elicitation question, when the model was asked for one ("Nudge me" mode).
        var hint: String?
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
        var hint: String?
        for rawLine in cleaned.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let r = matchPrefix(line, prefixes: ["FIX:", "FIX -", "Fix:", "Korrektur:"]) {
                fix = r
            } else if let r = matchPrefix(line, prefixes: ["WHY:", "WHY -", "Why:", "Grund:", "Erklärung:"]) {
                why = r
            } else if let r = matchPrefix(line, prefixes: ["HINT:", "HINT -", "Hint:", "Tipp:", "Frage:"]) {
                hint = r
            }
        }

        guard var corrected = fix?.trimmingCharacters(in: .whitespacesAndNewlines), !corrected.isEmpty else {
            // No parseable FIX line — assume nothing actionable.
            return CorrectionResult(correctedText: nil, note: nil)
        }
        corrected = stripWrappingQuotes(corrected)

        // If the "correction" is identical to what the student said, treat as clean. Small models
        // echo the input under a FIX: header and confabulate a reason for it — the single biggest
        // source of spurious corrections (18 of tuned E2B's 19 in the eval). Note this is
        // deliberately diacritic-SENSITIVE: "Madchen" → "Mädchen" is a real correction, not an echo.
        if echoNormalized(corrected) == echoNormalized(original) {
            return CorrectionResult(correctedText: nil, note: nil)
        }

        let note = why?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hintText = stripWrappingQuotes(hint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        return CorrectionResult(
            correctedText: corrected,
            note: (note?.isEmpty == false) ? note : nil,
            hint: hintText.isEmpty ? nil : hintText
        )
    }

    /// Folds the differences that don't amount to a correction — surrounding quotes, whitespace,
    /// case, and ALL punctuation — so a fix that only inserts a comma or a period is recognised as
    /// an echo. The student's line is a speech transcript, so punctuation is never their mistake.
    /// Umlauts and ß are preserved: fixing those *is* the lesson.
    private static func echoNormalized(_ s: String) -> String {
        let unquoted = stripWrappingQuotes(s.trimmingCharacters(in: .whitespacesAndNewlines))
        let letters = unquoted.unicodeScalars.map { scalar -> Character in
            CharacterSet.punctuationCharacters.contains(scalar) ? " " : Character(scalar)
        }
        return String(letters)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
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
        s += "PATTERN: <one sentence naming a recurring habit you noticed, good or bad>\n"
        s += "WEAK: <comma-separated keys from the list below for structures the student clearly struggled with this session, or leave blank>\n"
        s += "STRONG: <comma-separated keys from the list below for structures the student handled well, or leave blank>\n\n"
        s += "Grammar keys (use each key exactly as written, and only when the transcript clearly shows it):\n\(phraseGrammarKeyList)\n\n"
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

    /// Parse the machine-readable WEAK/STRONG grammar tags appended to the coaching report.
    /// Reuses the same lenient key matching as the phrase-library grammar suggestions.
    static func parseProfileSignals(_ raw: String) -> (weak: [GrammarFocus], strong: [GrammarFocus]) {
        let cleaned = stripThinkBlocks(raw)
        var weakKeys: String?
        var strongKeys: String?
        for rawLine in cleaned.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let r = matchPrefix(line, prefixes: ["WEAK:", "Weak:", "WEAK -"]) {
                weakKeys = r
            } else if let r = matchPrefix(line, prefixes: ["STRONG:", "Strong:", "STRONG -"]) {
                strongKeys = r
            }
        }
        return (parseGrammarKeys(weakKeys), parseGrammarKeys(strongKeys))
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
