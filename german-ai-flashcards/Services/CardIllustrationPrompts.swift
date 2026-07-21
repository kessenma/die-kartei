import Foundation

/// Builds the Stable Diffusion prompts for one flashcard picture.
///
/// Unlike story illustrations — where an LLM has to read the German prose and pick scenes — a
/// flashcard already carries its own English gloss, so the prompt is built deterministically from
/// `englishTranslation` and `wordType`. No model call, which is what makes illustrating an existing
/// deck cheap: the language model never has to load at all.
///
/// The look isn't fixed: `CardImageStyle` and `CardImageDetail` are the learner's two knobs, and
/// both contribute to the positive *and* negative prompt. The negative half does most of the work
/// on a small model, so it's built here rather than left to `ImageGenConstants`.
enum CardIllustrationPrompts {

    /// True of every card picture whatever the style: a flashcard is glanced at for a second, so
    /// one clear subject beats an atmospheric scene.
    static let baseSuffix = "illustration for a vocabulary flashcard"

    /// Card-specific negatives on top of `ImageGenConstants.negativePrompt`. Small models love to
    /// answer an abstract noun with a poster or an infographic, both of which are unreadable at
    /// flashcard size.
    static let baseNegative = "caption, label, title, typography, handwriting, poster, infographic, diagram, chart, logo"

    /// Shape the English gloss into something drawable, by word type. Verbs and adjectives are the
    /// two that fail as bare nouns — "to run" or "beautiful" alone give the model nothing to
    /// center on.
    static func subject(
        englishTranslation: String,
        wordType: String?,
        detail: CardImageDetail = .current
    ) -> String {
        let word = englishTranslation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,;:"))

        switch (wordType ?? "").lowercased() {
        case "verb":
            // "to run" → "a person performing the action: run"
            let bare = word.hasPrefix("to ") ? String(word.dropFirst(3)) : word
            return "a person performing the action: \(bare)"
        case "adjective", "adverb":
            return detail == .justTheWord
                ? "something that looks very \(word)"
                : "a scene that looks very \(word), expressive mood"
        case "noun":
            let bare = stripArticle(word)
            return detail == .justTheWord ? "a single \(bare)" : bare
        default:
            return detail == .justTheWord ? "a simple picture of \(word)" : "a simple scene depicting \(word)"
        }
    }

    /// The full positive prompt for one card.
    static func positivePrompt(
        englishTranslation: String,
        wordType: String?,
        style: CardImageStyle = .current,
        detail: CardImageDetail = .current
    ) -> String {
        [
            subject(englishTranslation: englishTranslation, wordType: wordType, detail: detail),
            style.promptFragment,
            detail.promptFragment,
            baseSuffix,
        ].joined(separator: ", ")
    }

    /// The full negative prompt for one card: the shared list, plus what a flashcard never wants,
    /// plus what this particular style and detail level must avoid.
    static func negativePrompt(
        style: CardImageStyle = .current,
        detail: CardImageDetail = .current
    ) -> String {
        [
            ImageGenConstants.negativePrompt,
            baseNegative,
            style.negativeFragment,
            detail.negativeFragment,
        ].joined(separator: ", ")
    }

    /// Drop a leading English article — the picture is of the thing, not of "a thing".
    private static func stripArticle(_ word: String) -> String {
        for article in ["the ", "a ", "an "] where word.lowercased().hasPrefix(article) {
            return String(word.dropFirst(article.count))
        }
        return word
    }
}
