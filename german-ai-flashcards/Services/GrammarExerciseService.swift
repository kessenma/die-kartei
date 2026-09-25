import Foundation

/// The bundled fill-in-the-blank sets (`grammar_exercises.json`): today only the preposition ones,
/// which the preposition hub lists. A grammar focus finds its practice through `GrammarRoute`.
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
}
