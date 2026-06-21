import Foundation

// MARK: - Grammar Focus

/// A grammar structure the conversation should emphasize. Used to steer the AI's
/// questions and to focus the correction pass. Each case carries an English label
/// and explanation for the picker's subheader and info modal.
enum GrammarFocus: String, CaseIterable, Codable, Identifiable {
    case perfekt
    case praeteritum
    case futur
    case konjunktiv2
    case akkusativ
    case dativ
    case genitiv
    case modalverben
    case wechselpraepositionen
    case adjektivendungen

    var id: String { rawValue }

    /// The German name shown as the primary label.
    var germanLabel: String {
        switch self {
        case .perfekt:              "Perfekt"
        case .praeteritum:          "Präteritum"
        case .futur:                "Futur I"
        case .konjunktiv2:          "Konjunktiv II"
        case .akkusativ:            "Akkusativ"
        case .dativ:                "Dativ"
        case .genitiv:              "Genitiv"
        case .modalverben:          "Modalverben"
        case .wechselpraepositionen: "Wechselpräpositionen"
        case .adjektivendungen:     "Adjektivendungen"
        }
    }

    /// Short English gloss shown as a subheader under the German label.
    var englishLabel: String {
        switch self {
        case .perfekt:              "Conversational past tense"
        case .praeteritum:          "Simple / written past"
        case .futur:                "Future tense"
        case .konjunktiv2:          "Hypotheticals & politeness"
        case .akkusativ:            "Direct-object case"
        case .dativ:                "Indirect-object case"
        case .genitiv:              "Possessive case"
        case .modalverben:          "Modal verbs"
        case .wechselpraepositionen: "Two-way prepositions"
        case .adjektivendungen:     "Adjective endings"
        }
    }

    /// Longer English explanation shown in the info modal.
    var explanation: String {
        switch self {
        case .perfekt:
            "The everyday past tense used when speaking — “ich habe gegessen”, “ich bin gegangen”. Formed with haben or sein plus the past participle."
        case .praeteritum:
            "The simple past, common in writing and with verbs like sein, haben and modals — “ich war”, “ich hatte”, “ich ging”."
        case .futur:
            "Talking about the future using werden plus an infinitive — “ich werde morgen arbeiten”."
        case .konjunktiv2:
            "Used for hypotheticals, wishes, and politeness — “ich würde gehen”, “wenn ich Zeit hätte…”, “könnten Sie mir helfen?”."
        case .akkusativ:
            "The direct object — the thing receiving the action. It changes the article: der → den. “Ich sehe den Mann.”"
        case .dativ:
            "The indirect object — to or for whom something happens. der → dem, die → der. “Ich gebe dem Kind das Buch.”"
        case .genitiv:
            "Shows possession (“of”). Articles become des / der and masculine/neuter nouns often add -s. “das Auto des Mannes.”"
        case .modalverben:
            "können, müssen, wollen, sollen, dürfen, mögen — they push the main verb to the end of the sentence as an infinitive. “Ich muss heute arbeiten.”"
        case .wechselpraepositionen:
            "Prepositions like in, an, auf, über that take the Akkusativ for movement/direction and the Dativ for a fixed location. “Ich gehe in die Stadt” vs. “Ich bin in der Stadt”."
        case .adjektivendungen:
            "Adjectives placed before a noun take endings that change with case, gender, and the article in front — “ein guter Wein”, “mit dem guten Wein”."
        }
    }

    /// A German example/hint the AI can use to elicit this structure.
    var steeringHint: String {
        switch self {
        case .perfekt:               "frage nach Vergangenem, z. B. „Was hast du am Wochenende gemacht?“"
        case .praeteritum:           "erzähle und frage im Präteritum, z. B. „Wie war dein Tag?“"
        case .futur:                 "sprich über die Zukunft, z. B. „Was wirst du nächstes Jahr machen?“"
        case .konjunktiv2:           "stelle hypothetische Fragen, z. B. „Was würdest du tun, wenn du viel Geld hättest?“"
        case .akkusativ:             "nutze Sätze mit direktem Objekt, z. B. „Was kaufst du heute?“"
        case .dativ:                 "nutze Dativ-Verben und -Präpositionen, z. B. „Wem hilfst du?“, „Mit wem gehst du?“"
        case .genitiv:               "nutze den Genitiv, z. B. „Wessen Idee war das?“"
        case .modalverben:           "stelle Fragen mit Modalverben, z. B. „Was möchtest du machen?“, „Was musst du heute tun?“"
        case .wechselpraepositionen: "frage nach Ort und Richtung, z. B. „Wohin gehst du?“ und „Wo bist du?“"
        case .adjektivendungen:      "rege Beschreibungen mit Adjektiven an, z. B. „Was für ein Auto möchtest du?“"
        }
    }
}
