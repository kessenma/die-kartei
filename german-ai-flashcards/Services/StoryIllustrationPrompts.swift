import Foundation

// MARK: - Genre → visual style

extension StoryGenre {
    /// Style suffix appended to every Stable Diffusion prompt so the pictures match the
    /// story's flavor. English on purpose — SD 2.1 was trained on English captions.
    var sdStyleSuffix: String {
        switch self {
        case .alltag:    "warm storybook illustration of everyday life, soft colors"
        case .dialog:    "warm storybook illustration, two people talking, cozy scene"
        case .brief:     "cozy illustration, warm interior light, letter-writing mood"
        case .krimi:     "atmospheric mystery illustration, film noir mood, dramatic shadows"
        case .maerchen:  "classic fairy tale storybook illustration, whimsical, enchanted"
        case .abenteuer: "adventure storybook illustration, sweeping landscape, golden hour light"
        case .romanze:   "romantic illustration, warm pastel tones, soft focus"
        case .scifi:     "retro-futuristic science fiction illustration, starfield, neon accents"
        case .comedy:    "playful cartoon illustration, bright cheerful colors, exaggerated expressions"
        case .tagebuch:  "hand-drawn journal sketch, soft watercolor wash, personal"
        case .fabel:     "children's picture-book illustration of animals, gentle watercolor"
        }
    }
}

// MARK: - Prompt building

/// Builds and parses the prompts behind story illustrations: where images anchor in the
/// story, the LLM request that turns the German story into English scene descriptions,
/// and the final Stable Diffusion prompt for each scene. Only used by the (MainActor)
/// StoryStudyService, so it stays on the default isolation.
enum StoryIllustrationPrompts {

    /// Which paragraph each image follows. Slot 0 is always the header/hero image (nil);
    /// inline slots spread evenly across the paragraph gaps and collapse on collision, so
    /// short stories simply get fewer inline images.
    static func anchors(imageCount: Int, paragraphCount: Int) -> [Int?] {
        guard imageCount > 0, paragraphCount > 0 else { return [] }
        var result: [Int?] = [nil]
        var seen = Set<Int>()
        for k in 1..<imageCount {
            let anchor = min(paragraphCount - 1, k * paragraphCount / imageCount)
            if seen.insert(anchor).inserted { result.append(anchor) }
        }
        return result
    }

    /// The LLM request for one English scene description per image slot. The story is
    /// German; SD wants English, so the still-loaded story model does the translation
    /// and scene selection in a single call.
    static func sceneRequest(
        title: String,
        storyText: String,
        paragraphs: [String],
        anchors: [Int?]
    ) -> (system: String, user: String) {
        let n = anchors.count
        var lines: [String] = []
        lines.append("Write \(n) one-sentence scene description\(n == 1 ? "" : "s") IN ENGLISH for illustrating this German story.")
        lines.append("Each description is purely visual: concrete subjects, a setting, a mood. Max 25 words each. No text, letters, signs, or speech in the scene.")
        lines.append("SCENE 1 shows the story as a whole.")
        for (slot, anchor) in anchors.enumerated() where slot > 0 {
            if let anchor, paragraphs.indices.contains(anchor) {
                lines.append("SCENE \(slot + 1) shows this part: \"\(String(paragraphs[anchor].prefix(300)))\"")
            }
        }
        lines.append("Answer EXACTLY in this format, nothing else:")
        for i in 1...n {
            lines.append("SCENE \(i): <description>")
        }
        lines.append("")
        lines.append("STORY (Titel: \(title)):")
        lines.append(storyText)
        return (
            system: "You are helping illustrate a German short story for language learners. Respond ONLY in the exact format requested, in ENGLISH.",
            user: lines.joined(separator: "\n")
        )
    }

    /// Parse "SCENE n: …" lines into index-matched slots; nil where the model's output
    /// was missing or unusable (each nil slot falls back to `fallbackScene`).
    static func parseScenes(_ raw: String, count: Int) -> [String?] {
        var scenes = [String?](repeating: nil, count: count)
        let cleaned = ConversationPrompts.stripThinkBlocks(raw)
        for line in cleaned.components(separatedBy: .newlines) {
            guard let match = line.firstMatch(of: #/(?i)^\s*SCENE\s*(\d+)\s*[:\-–.]\s*(.+)$/#),
                  let index = Int(match.1), (1...count).contains(index)
            else { continue }
            let text = String(match.2)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'*`"))
            if (8...300).contains(text.count) {
                scenes[index - 1] = text
            }
        }
        return scenes
    }

    /// Deterministic scene when the LLM's description is unusable. Topics are entered in
    /// English (the setup placeholder and all bundled starters), so this reads fine to SD.
    static func fallbackScene(topic: String, slot: Int) -> String {
        slot == 0
            ? "\(topic), the key moment of a short story"
            : "\(topic), scene \(slot + 1) of a short story"
    }

    /// The final positive prompt for one image.
    static func positivePrompt(scene: String, genre: StoryGenre) -> String {
        "\(scene), \(genre.sdStyleSuffix), highly detailed, soft lighting"
    }
}
