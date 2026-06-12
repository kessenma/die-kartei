import Foundation

enum GrammarExerciseService {
    private static var cache: [GrammarCategory]?

    static func loadCategories() -> [GrammarCategory] {
        if let cached = cache { return cached }
        guard let url = Bundle.main.url(forResource: "grammar_exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(GrammarExercisesFile.self, from: data)
        else { return [] }
        cache = file.categories
        return file.categories
    }

    static func toVocabCards(category: GrammarCategory) -> [VocabCard] {
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
