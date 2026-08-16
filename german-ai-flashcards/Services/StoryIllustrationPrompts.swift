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

// MARK: - Recurring characters

/// A character that shows up in more than one of a story's pictures, with the one fixed
/// wording used to describe it every time.
///
/// Stable Diffusion has no memory between images: two prompts that both say "a pigeon" are
/// free to draw a white dove and a gray city bird. The only lever we have is *saying the same
/// words*, so the LLM commits to one appearance up front and `positivePrompt` splices it into
/// every scene that mentions the character.
struct StoryCastMember: Hashable {
    /// The bare noun the scene descriptions use ("pigeon").
    let tag: String
    /// The full descriptive phrase that replaces it ("plump gray pigeon with a white belly,
    /// iridescent green neck and a coral-orange beak").
    let look: String
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
    ///
    /// With `wantsCast` the same call also opens with a cast sheet — the fixed look of the
    /// characters that recur across the pictures (see `StoryCastMember`). It rides along on
    /// this call rather than a second one because the model is already holding the story.
    /// If the model skips or mangles the block we simply get today's behaviour back.
    static func sceneRequest(
        title: String,
        storyText: String,
        paragraphs: [String],
        anchors: [Int?],
        wantsCast: Bool = false
    ) -> (system: String, user: String) {
        let n = anchors.count
        var lines: [String] = []

        if wantsCast {
            lines.append("STEP 1 — CAST. Name at most 2 characters that appear in more than one picture. Skip this if no character recurs.")
            lines.append("Give each a single fixed appearance: species or age and build, colours, clothing. Appearance only — no names, no story, no actions. Max 12 words.")
            lines.append("Write the bare noun first, then '=', then the description repeating that noun, like:")
            lines.append("CAST 1: pigeon = plump gray pigeon with a white belly and a coral-orange beak")
            lines.append("")
            lines.append("STEP 2 — SCENES.")
        }

        lines.append("Write \(n) one-sentence scene description\(n == 1 ? "" : "s") IN ENGLISH for illustrating this German story.")
        // The cast phrase is spliced into the scene later and CLIP only reads ~77 tokens, so
        // scenes have to leave room for it.
        lines.append("Each description is purely visual: concrete subjects, a setting, a mood. Max \(wantsCast ? 18 : 25) words each. No text, letters, signs, or speech in the scene.")
        if wantsCast {
            lines.append("Refer to a cast character by its bare noun exactly as written above, every time it appears.")
        }
        lines.append("SCENE 1 shows the story as a whole.")
        for (slot, anchor) in anchors.enumerated() where slot > 0 {
            if let anchor, paragraphs.indices.contains(anchor) {
                lines.append("SCENE \(slot + 1) shows this part: \"\(String(paragraphs[anchor].prefix(300)))\"")
            }
        }
        lines.append("Answer EXACTLY in this format, nothing else:")
        if wantsCast {
            lines.append("CAST 1: <noun> = <appearance>")
        }
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

    /// Parse the "CAST n: noun = appearance" lines. Anything malformed, empty, or over-long is
    /// dropped rather than repaired — a missing cast just means the pictures fall back to
    /// whatever the scene descriptions say on their own. At most 2 survive, so the spliced
    /// phrases can't crowd the style suffix out of CLIP's window.
    static func parseCast(_ raw: String) -> [StoryCastMember] {
        let cleaned = ConversationPrompts.stripThinkBlocks(raw)
        var members: [StoryCastMember] = []
        var seenTags = Set<String>()
        for line in cleaned.components(separatedBy: .newlines) {
            guard members.count < 2,
                  let match = line.firstMatch(of: #/(?i)^\s*CAST\s*\d*\s*[:\-–.]\s*(.+?)\s*=\s*(.+)$/#)
            else { continue }
            let tag = String(match.1)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'*`<>"))
                .lowercased()
            let look = String(match.2)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'*`<>."))
            // The tag has to be a bare noun we can find in a sentence, and the look has to
            // actually contain it — otherwise the splice would read as a non sequitur.
            guard (3...24).contains(tag.count),
                  (12...110).contains(look.count),
                  !tag.contains(" ") || tag.split(separator: " ").count <= 2,
                  look.range(of: tag, options: .caseInsensitive) != nil,
                  seenTags.insert(tag).inserted
            else { continue }
            members.append(StoryCastMember(tag: tag, look: look))
        }
        return members
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
    ///
    /// Each cast member's fixed look replaces the *first* mention of its noun in the scene, so
    /// every picture in the story describes the character with byte-identical wording. Only the
    /// first mention: repeating the phrase would spend the token budget twice over for nothing.
    static func positivePrompt(scene: String, genre: StoryGenre, cast: [StoryCastMember] = []) -> String {
        var scene = scene
        var didSplice = false
        for member in cast {
            guard let range = firstWordRange(of: member.tag, in: scene) else { continue }
            scene.replaceSubrange(range, with: member.look)
            didSplice = true
        }
        // CLIP reads only ~77 tokens and truncates the tail, so once a look phrase is in the
        // prompt the generic quality words are dropped ahead of the style suffix — the suffix
        // is what keeps a story's pictures looking like one set.
        return didSplice
            ? "\(scene), \(genre.sdStyleSuffix)"
            : "\(scene), \(genre.sdStyleSuffix), highly detailed, soft lighting"
    }

    /// Range of the first whole-word, case-insensitive occurrence of `word` in `text`.
    /// Whole-word so a "cat" tag doesn't rewrite the middle of "catch".
    private static func firstWordRange(of word: String, in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while let range = text.range(of: word, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            let beforeOK = range.lowerBound == text.startIndex
                || !text[text.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == text.endIndex
                || !text[range.upperBound].isLetter
            if beforeOK && afterOK { return range }
            guard range.upperBound < text.endIndex else { return nil }
            searchStart = text.index(after: range.lowerBound)
        }
        return nil
    }
}
