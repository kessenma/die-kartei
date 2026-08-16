//
//  GrammarExplanation.swift
//  german-ai-flashcards
//
//  The "because …" clause the fill-in-the-blank round shows after a wrong pick.
//
//  Bundled exercises carry an authored `why` written against the specific sentence, which beats
//  anything derivable — only the sentence knows that "Die Katze läuft unter das Bett" is Wohin?
//  and "schläft unter dem Bett" is Wo?. AI-generated exercises usually won't have one, so this
//  derives the next best thing from the fields they do carry (the category's case, the noun and
//  its gender), and falls back to the category's rule note when even that isn't available.
//

import Foundation

enum GrammarExplanation {
    /// The clause to print after "The answer is <answer> because". Always starts lowercase and
    /// ends with a period, so callers can concatenate without inspecting it.
    static func because(_ exercise: GrammarExercise, in category: GrammarCategory) -> String {
        let authored = exercise.why?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let authored, !authored.isEmpty { return authored }
        return derived(exercise, in: category) ?? ruleFallback(category)
    }

    // MARK: - Derived

    private static func derived(_ exercise: GrammarExercise, in category: GrammarCategory) -> String? {
        guard let caseName = caseName(category.grammaticalCase) else { return nil }

        let noun = exercise.noun.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noun.isEmpty, let gender = englishGender(exercise.gender) else {
            // No noun to hang it on — the case alone is still worth saying.
            return "this sentence needs the \(caseName), so the answer is \(exercise.correctAnswer)."
        }
        return "\(noun) is \(gender) and this sentence needs the \(caseName), "
            + "which makes it \(exercise.correctAnswer)."
    }

    /// The German case name for a category's `grammaticalCase`, which carries a `GrammarFocus`
    /// raw value. Nil for the focuses that aren't a case at all (tenses, modals), where a
    /// derived case sentence would be nonsense.
    private static func caseName(_ raw: String) -> String? {
        switch GrammarFocus(rawValue: raw) {
        case .akkusativ:                            "Akkusativ"
        case .dativ:                                "Dativ"
        case .genitiv:                              "Genitiv"
        // Which case is right is exactly what these two exercises ask, so naming one would
        // either give the answer away or state it wrongly. The rule note carries them.
        case .praepositionen, .wechselpraepositionen: nil
        default:                                    nil
        }
    }

    private static func englishGender(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "maskulin", "masculine", "der": "masculine"
        case "feminin", "feminine", "die":   "feminine"
        case "neutrum", "neuter", "das":     "neuter"
        case "plural", "pl":                 "plural"
        default:                             nil
        }
    }

    // MARK: - Last resort

    /// The category's own rule, lowercased into a clause. Not elegant, but it is always true and
    /// always present, and it beats printing nothing after "because".
    private static func ruleFallback(_ category: GrammarCategory) -> String {
        let note = category.ruleNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return "that's the form this sentence calls for." }
        return note.hasSuffix(".") ? note : note + "."
    }
}
