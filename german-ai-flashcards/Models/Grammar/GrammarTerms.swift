//
//  GrammarTerms.swift
//  german-ai-flashcards
//
//  Gender and case as plain values, with no UI: their colors live in GrammarPalette.swift.
//  Kept Foundation-only so DieKarteiCore (the Android build) can share them.
//

import Foundation

// MARK: - Gender

/// German grammatical gender. The signature pedagogy-as-identity move of the theme system:
/// color-code der/die/das everywhere it appears (article text, card corners, the article game,
/// the picker) so the classic learner mnemonic is always on screen.
///
/// Independent of `AppTheme` — the gender colors are the same in every theme, so the aid never
/// changes meaning. In **Grundform** these colors double as the Bauhaus primaries, so identity and
/// pedagogy share one palette (see `AppTheme.previewColors` / `accent`).
nonisolated enum Gender: String, CaseIterable, Identifiable {
    case der, die, das, plural

    var id: String { rawValue }

    /// The nominative singular article (or "die" for the plural), lowercased.
    var article: String {
        switch self {
        case .der:    "der"
        case .die:    "die"
        case .das:    "das"
        case .plural: "die"   // plural takes "die" regardless of singular gender
        }
    }

    /// Human label for pickers and legends.
    var label: String {
        switch self {
        case .der:    "der"
        case .die:    "die"
        case .das:    "das"
        case .plural: "Plural"
        }
    }

    /// The figure glyph used on cards, pickers and badges.
    var symbol: String {
        switch self {
        case .der:    "figure.stand"
        case .die:    "figure.stand.dress"
        case .das:    "figure.stand.dress.line.vertical.figure"
        case .plural: "person.2.fill"
        }
    }

    /// Column header, as a teacher's table writes it.
    var columnLabel: String {
        switch self {
        case .der:    "m"
        case .die:    "f"
        case .das:    "n"
        case .plural: "pl"
        }
    }

    var genderName: String {
        switch self {
        case .der:    "masculine"
        case .die:    "feminine"
        case .das:    "neuter"
        case .plural: "plural"
        }
    }

    /// Best-effort parse from an article string (`"der"` / `"die"` / `"das"`, any case, with or
    /// without surrounding whitespace). Returns `nil` when the string isn't a bare article, so
    /// callers can fall back to an uncolored treatment. Deliberately does not guess plural — a bare
    /// "die" is read as feminine; plurals are tagged explicitly by the caller that knows the count.
    init?(article raw: String) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "der": self = .der
        case "die": self = .die
        case "das": self = .das
        default:    return nil
        }
    }

    /// Parse from a teacher's column label (`"m"` / `"f"` / `"n"` / `"pl"`, any case), the
    /// inverse of `columnLabel`. The Kasus stories store genus this way.
    init?(columnLabel raw: String) {
        guard let match = Self.allCases.first(where: {
            $0.columnLabel == raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }) else { return nil }
        self = match
    }
}

// MARK: - Case


/// The four German cases, with the table forms every case lesson teaches from. Each case owns a
/// color and a symbol that says what it does in the sentence:
///
///   Nominativ  bolt    the one doing the verb
///   Akkusativ  target  the thing the verb hits
///   Dativ      gift    the one receiving: to whom
///   Genitiv    key     whose it is
///
/// „Der Mann gibt dem Kind einen Ball“ reads bolt, gift, target.
nonisolated enum GrammarCase: String, CaseIterable, Identifiable {
    case nominativ, akkusativ, dativ, genitiv

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    var short: String {
        switch self {
        case .nominativ: "Nom"
        case .akkusativ: "Akk"
        case .dativ:     "Dat"
        case .genitiv:   "Gen"
        }
    }

    var role: String {
        switch self {
        case .nominativ: "Subject"
        case .akkusativ: "Direct object"
        case .dativ:     "Indirect object"
        case .genitiv:   "Possession"
        }
    }

    var question: String {
        switch self {
        case .nominativ: "Who or what is doing the verb?"
        case .akkusativ: "Who or what is being “verbed”?"
        case .dativ:     "To whom is the verb being done? The receiver."
        case .genitiv:   "Whose is it?"
        }
    }

    var symbol: String {
        switch self {
        case .nominativ: "bolt.fill"
        case .akkusativ: "target"
        case .dativ:     "gift.fill"
        case .genitiv:   "key.fill"
        }
    }

    /// The coach's skill for this case, where it tracks one.
    var focus: GrammarFocus? {
        switch self {
        case .nominativ: nil
        case .akkusativ: .akkusativ
        case .dativ:     .dativ
        case .genitiv:   .genitiv
        }
    }

    init?(focus: GrammarFocus) {
        guard let match = Self.allCases.first(where: { $0.focus == focus }) else { return nil }
        self = match
    }

    /// The definite article; its last letter is this case's code letter for the gender.
    func article(_ gender: Gender) -> String {
        switch (self, gender) {
        case (.nominativ, .der):    "der"
        case (.nominativ, .die):    "die"
        case (.nominativ, .das):    "das"
        case (.nominativ, .plural): "die"
        case (.akkusativ, .der):    "den"
        case (.akkusativ, .die):    "die"
        case (.akkusativ, .das):    "das"
        case (.akkusativ, .plural): "die"
        case (.dativ, .der):        "dem"
        case (.dativ, .die):        "der"
        case (.dativ, .das):        "dem"
        case (.dativ, .plural):     "den"
        case (.genitiv, .der):      "des"
        case (.genitiv, .die):      "der"
        case (.genitiv, .das):      "des"
        case (.genitiv, .plural):   "der"
        }
    }

    /// The ending on ein / mein / kein. Empty in the three spots where ein-words carry none.
    func einEnding(_ gender: Gender) -> String {
        switch (self, gender) {
        case (.nominativ, .der), (.nominativ, .das), (.akkusativ, .das): ""
        case (.nominativ, .die), (.akkusativ, .die),
             (.nominativ, .plural), (.akkusativ, .plural):                "e"
        case (.akkusativ, .der), (.dativ, .plural):                       "en"
        case (.dativ, .der), (.dativ, .das):                              "em"
        case (.dativ, .die), (.genitiv, .die), (.genitiv, .plural):       "er"
        case (.genitiv, .der), (.genitiv, .das):                          "es"
        }
    }

    /// „rese“, „nese“, „mrmn“, „srsr“: the articles' last letters in m-f-n-pl order.
    var code: String {
        String(Gender.allCases.compactMap { article($0).last })
    }
}
