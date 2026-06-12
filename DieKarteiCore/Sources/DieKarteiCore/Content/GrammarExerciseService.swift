import Foundation

public enum GrammarExerciseService {
    private static var cache: [GrammarCategory]?

    public static func loadCategories() -> [GrammarCategory] {
        if let cached = cache { return cached }
        guard let file = CoreResources.decode(GrammarExercisesFile.self, resource: "grammar_exercises")
        else { return [] }
        cache = file.categories
        return file.categories
    }

    public static func toVocabCards(category: GrammarCategory) -> [VocabCard] {
        category.exercises.map { exercise in
            let filled = exercise.sentence.replacingOccurrences(of: "______", with: exercise.correctAnswer)
            return VocabCard(
                germanWord: exercise.sentence,
                englishTranslation: "\(exercise.correctAnswer) · \(exercise.noun) (\(exercise.gender))",
                wordType: "grammar",
                article: exercise.correctAnswer,
                exampleSentence: filled
            )
        }
    }
}
