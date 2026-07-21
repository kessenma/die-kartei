import Foundation
import SwiftData

/// The flashcard deck attached to a story — words the learner double-taps while reading are saved
/// here (the deck is created on first save). Shared by the reading view and the read-aloud player
/// so both offer the same tap-to-translate-and-save gesture.
enum StoryDeckStore {
    static func deck(for story: StudyStory, context: ModelContext) -> SavedDeck? {
        guard let deckID = story.deckID else { return nil }
        let descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == deckID })
        return try? context.fetch(descriptor).first
    }

    /// Lowercased German words already saved to this story's deck — highlighted in the text.
    static func savedWords(for story: StudyStory, context: ModelContext) -> Set<String> {
        guard let deck = deck(for: story, context: context) else { return [] }
        return Set(deck.cards.map { $0.germanWord.lowercased() })
    }

    static func isWordSaved(_ word: String, story: StudyStory, context: ModelContext) -> Bool {
        guard let deck = deck(for: story, context: context) else { return false }
        let key = word.lowercased()
        return deck.cards.contains { $0.germanWord.lowercased() == key }
    }

    /// Save a tapped word into the story's flashcard deck (created on first save) and, unless the
    /// learner turned the hand-off off, fold it into the learner profile's vocabulary.
    static func saveWord(
        german: String,
        english: String?,
        story: StudyStory,
        feedsCoach: Bool = true,
        context: ModelContext
    ) {
        let target: SavedDeck
        if let existing = deck(for: story, context: context) {
            target = existing
        } else {
            let created = SavedDeck(topic: "Story: \(story.title)", wordCount: 0, includeExamples: false, includeGender: true)
            created.generatorRaw = "story"
            context.insert(created)
            story.deckID = created.id
            target = created
        }

        let (word, article) = splitArticle(german)
        target.cards.append(SavedCard(
            germanWord: word,
            englishTranslation: english ?? "",
            wordType: article != nil ? "noun" : nil,
            article: article,
            exampleSentence: nil,
            conjugations: nil,
            sortOrder: target.cards.count
        ))
        target.wordCount = target.cards.count
        try? context.save()

        if feedsCoach {
            LearnerMemoryService.noteVocabEncounters([(german: word, english: english ?? "")], in: context)
        }
    }

    private static func splitArticle(_ word: String) -> (String, String?) {
        for article in ["der ", "die ", "das "] where word.lowercased().hasPrefix(article) {
            return (String(word.dropFirst(article.count)).trimmingCharacters(in: .whitespaces), String(article.dropLast()))
        }
        return (word, nil)
    }
}
