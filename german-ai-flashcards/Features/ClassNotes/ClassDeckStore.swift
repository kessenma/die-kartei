import Foundation
import SwiftData

/// The flashcard deck of a course. One deck per course, not per entry: the words from a semester
/// belong together, and a deck of six cards per class would never be worth a review session. The
/// class twin of `JobDeckStore`. The deck is created on the first word saved and linked through
/// `ClassCourse.deckID`.
enum ClassDeckStore {
    static let generatorRaw = "class"

    static func deck(for course: ClassCourse, context: ModelContext) -> SavedDeck? {
        guard let deckID = course.deckID else { return nil }
        let descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == deckID })
        return try? context.fetch(descriptor).first
    }

    /// The course's deck, created now if it has none yet.
    static func orCreateDeck(for course: ClassCourse, context: ModelContext) -> SavedDeck {
        if let existing = deck(for: course, context: context) { return existing }
        let created = SavedDeck(topic: "Class: \(course.name)", wordCount: 0, includeExamples: false, includeGender: true)
        created.generatorRaw = generatorRaw
        created.courseID = course.id
        context.insert(created)
        course.deckID = created.id
        return created
    }

    /// Lowercased German words already in the course's deck, article stripped.
    static func savedWords(for course: ClassCourse, context: ModelContext) -> Set<String> {
        guard let deck = deck(for: course, context: context) else { return [] }
        return Set(deck.cards.map { $0.germanWord.lowercased() })
    }

    static func isWordSaved(_ word: String, course: ClassCourse, context: ModelContext) -> Bool {
        guard let deck = deck(for: course, context: context) else { return false }
        let key = ClassWord.key(word)
        return deck.cards.contains { $0.germanWord.lowercased() == key }
    }

    /// Save a word (or phrase) into the course's deck, and unless the learner turned the hand-off
    /// off, fold it into the learner profile's vocabulary. Returns false when it was already there.
    @discardableResult
    static func saveWord(
        german: String,
        english: String?,
        course: ClassCourse,
        feedsCoach: Bool = true,
        context: ModelContext
    ) -> Bool {
        guard !isWordSaved(german, course: course, context: context) else { return false }
        let target = orCreateDeck(for: course, context: context)
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
        course.updatedAt = .now
        try? context.save()

        if feedsCoach {
            LearnerMemoryService.noteVocabEncounters([(german: word, english: english ?? "")], source: "class", in: context)
        }
        return true
    }

    /// Save every complete word of an entry that isn't in the deck yet, and mark them on the
    /// entry. Returns how many were added.
    @discardableResult
    static func saveWords(of entry: ClassEntry, feedsCoach: Bool = true, context: ModelContext) -> Int {
        guard let course = entry.course else { return 0 }
        var words = entry.words
        var added = 0
        for index in words.indices where words[index].isComplete {
            if saveWord(german: words[index].trimmedGerman, english: words[index].trimmedEnglish,
                        course: course, feedsCoach: feedsCoach, context: context) {
                added += 1
            }
            words[index].addedToDeck = true
        }
        entry.setWords(words)
        try? context.save()
        return added
    }

    /// Save every looked-up word of a handout that isn't in the deck yet. Returns how many were added.
    @discardableResult
    static func saveAllLookups(for material: ClassMaterial, feedsCoach: Bool = true, context: ModelContext) -> Int {
        guard let course = material.entry?.course else { return 0 }
        var added = 0
        for entry in material.lookups.reversed() where !entry.english.isEmpty {
            if saveWord(german: entry.german, english: entry.english, course: course, feedsCoach: feedsCoach, context: context) {
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
