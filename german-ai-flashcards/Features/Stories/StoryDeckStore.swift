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
        return Set(deck.cards.map { CardKind.matchKey($0.germanWord) })
    }

    static func isWordSaved(_ word: String, story: StudyStory, context: ModelContext) -> Bool {
        guard let deck = deck(for: story, context: context) else { return false }
        let key = CardKind.matchKey(word)
        return deck.cards.contains { CardKind.matchKey($0.germanWord) == key }
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
        guard !isWordSaved(german, story: story, context: context) else { return }
        let target: SavedDeck
        if let existing = deck(for: story, context: context) {
            target = existing
        } else {
            let created = SavedDeck(topic: "Story: \(story.title)", wordCount: 0, includeExamples: false, includeGender: true)
            created.generatorRaw = "story"
            created.id = SyncSingletonDecks.linkedDeckID(existing: story.deckID, kind: "story", parentID: story.id)
            context.insert(created)
            story.deckID = created.id
            target = created
        }

        let split = CardKind.split(german)
        let word = split.word
        target.cards.append(SavedCard(
            germanWord: word,
            englishTranslation: english ?? "",
            wordType: split.wordType,
            article: split.article,
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
}
