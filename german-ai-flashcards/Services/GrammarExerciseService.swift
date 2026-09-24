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

    /// The multiple-choice drill category matching a grammar focus, if one ships in the bundle.
    /// Akkusativ, Dativ and the two preposition focuses have exercises today; every other
    /// structure returns `nil` (its just-in-time lesson falls back to the explanation + a
    /// conversation nudge). `rotation` (e.g. a day index) picks among the categories for that
    /// key so repeated practice varies.
    static func category(for focus: GrammarFocus, rotation: Int = 0) -> GrammarCategory? {
        let caseKey: String
        switch focus {
        case .akkusativ:             caseKey = "akkusativ"
        case .dativ:                 caseKey = "dativ"
        case .praepositionen:        caseKey = "praepositionen"
        case .wechselpraepositionen: caseKey = "wechselpraepositionen"
        default:                     return nil
        }
        let categories = loadCategories().filter { $0.grammaticalCase == caseKey }
        guard !categories.isEmpty else { return nil }
        // Wrap defensively so any (even negative) rotation lands on a valid index.
        return categories[((rotation % categories.count) + categories.count) % categories.count]
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
