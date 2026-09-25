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

    /// Wrap AI-generated exercises in an on-the-fly category so they run in the existing
    /// multiple-choice player. `grammaticalCase` carries the focus raw value — that's how a
    /// finished drill finds its way back into the learner profile (see ContentView).
    static func aiCategory(focus: GrammarFocus, topic: String, exercises: [GrammarExercise]) -> GrammarCategory {
        GrammarCategory(
            id: "ai-\(focus.rawValue)-\(UUID().uuidString)",
            title: "\(focus.germanLabel): \(topic)",
            subtitle: "AI exercises · \(topic)",
            grammaticalCase: focus.rawValue,
            articleType: "ai",
            ruleNote: focus.compactRule,
            options: focus.exerciseSeed.fallbackOptions,
            exercises: exercises
        )
    }
}
