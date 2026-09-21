import Foundation
import SwiftData

/// The flashcard deck attached to a job posting — words the learner double-taps while reading the
/// ad are saved here (the deck is created on first save). The job twin of `StoryDeckStore`, kept
/// separate so the two document types can grow their own card shapes without stepping on each
/// other.
enum JobDeckStore {
    static let generatorRaw = "job"

    static func deck(for posting: JobPosting, context: ModelContext) -> SavedDeck? {
        guard let deckID = posting.deckID else { return nil }
        let descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == deckID })
        return try? context.fetch(descriptor).first
    }

    /// Lowercased German words already saved to this posting's deck — marked in the text.
    static func savedWords(for posting: JobPosting, context: ModelContext) -> Set<String> {
        guard let deck = deck(for: posting, context: context) else { return [] }
        return Set(deck.cards.map { $0.germanWord.lowercased() })
    }

    static func isWordSaved(_ word: String, posting: JobPosting, context: ModelContext) -> Bool {
        guard let deck = deck(for: posting, context: context) else { return false }
        let key = splitArticle(word).0.lowercased()
        return deck.cards.contains { $0.germanWord.lowercased() == key }
    }

    /// Save a tapped word (or phrase) into the posting's deck, created on first save, and unless
    /// the learner turned the hand-off off, fold it into the learner profile's vocabulary.
    /// Returns false when the word was already there.
    @discardableResult
    static func saveWord(
        german: String,
        english: String?,
        posting: JobPosting,
        feedsCoach: Bool = true,
        context: ModelContext
    ) -> Bool {
        guard !isWordSaved(german, posting: posting, context: context) else { return false }
        let target: SavedDeck
        if let existing = deck(for: posting, context: context) {
            target = existing
        } else {
            let created = SavedDeck(topic: "Job: \(posting.title)", wordCount: 0, includeExamples: false, includeGender: true)
            created.generatorRaw = generatorRaw
            context.insert(created)
            posting.deckID = created.id
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
        posting.updatedAt = .now
        try? context.save()

        if feedsCoach {
            LearnerMemoryService.noteVocabEncounters([(german: word, english: english ?? "")], source: "job", in: context)
        }
        return true
    }

    /// Save every looked-up word that isn't in the deck yet. Returns how many were added.
    @discardableResult
    static func saveAllLookups(for posting: JobPosting, feedsCoach: Bool = true, context: ModelContext) -> Int {
        var added = 0
        for entry in posting.lookups.reversed() where !entry.english.isEmpty {
            if saveWord(german: entry.german, english: entry.english, posting: posting, feedsCoach: feedsCoach, context: context) {
                added += 1
            }
        }
        return added
    }

    private static func splitArticle(_ word: String) -> (String, String?) {
        for article in ["der ", "die ", "das "] where word.lowercased().hasPrefix(article) {
            return (String(word.dropFirst(article.count)).trimmingCharacters(in: .whitespaces), String(article.dropLast()))
        }
        return (word, nil)
    }
}
