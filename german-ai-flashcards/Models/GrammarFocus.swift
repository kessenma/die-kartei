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
    case artikel
    case akkusativ
    case dativ
    case genitiv
    case modalverben
    case praepositionen
    case wechselpraepositionen
    case adjektivendungen

    var id: String { rawValue }

    /// The CEFR level at which this structure is normally introduced.
    ///
    /// Two jobs: picking placement items that actually discriminate between levels, and keeping an
    /// A1 learner from being handed a B1 drill. Which level owns a structure is a fact about the
    /// Goethe curriculum, so it's recorded here rather than guessed at runtime.
    ///
    /// Two deliberate judgment calls: `konjunktiv2` shows up at A2 for politeness ("könnten Sie…")
    /// but is filed at B1, where hypotheticals make it a real structure; `adjektivendungen` starts
    /// after definite articles at A2 but is filed at B1, because the full table is what a drill
    /// actually tests. Both err upward on purpose — over-levelling only delays a structure, while
    /// under-levelling hands a beginner an exercise they cannot do.
    var introducedAt: CEFRLevel {
        switch self {
        case .artikel, .akkusativ, .modalverben, .perfekt, .praepositionen: .a1
        case .dativ, .praeteritum, .futur, .wechselpraepositionen:          .a2
        case .genitiv, .konjunktiv2, .adjektivendungen:                     .b1
        }
    }

    /// The German name shown as the primary label.
    var germanLabel: String {
        switch self {
        case .perfekt:              "Perfekt"
        case .praeteritum:          "Präteritum"
        case .futur:                "Futur I"
        case .konjunktiv2:          "Konjunktiv II"
        case .artikel:              "Artikel"
        case .akkusativ:            "Akkusativ"
        case .dativ:                "Dativ"
        case .genitiv:              "Genitiv"
        case .modalverben:          "Modalverben"
        case .praepositionen:       "Präpositionen"
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
        case .artikel:              "Noun gender (der/die/das)"
        case .akkusativ:            "Direct-object case"
        case .dativ:                "Indirect-object case"
        case .genitiv:              "Possessive case"
        case .modalverben:          "Modal verbs"
        case .praepositionen:       "Prepositions & the case they take"
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
        case .artikel:
            "Every German noun has a grammatical gender shown by its article: der (masculine), die (feminine), das (neuter). Endings often give it away — “-ung”, “-heit” and “-keit” are feminine, “-chen” and “-lein” are neuter — but many just have to be learned with the noun."
        case .akkusativ:
            "The direct object — the thing receiving the action. It changes the article: der → den. “Ich sehe den Mann.”"
        case .dativ:
            "The indirect object — to or for whom something happens. der → dem, die → der. “Ich gebe dem Kind das Buch.”"
        case .genitiv:
            "Shows possession (“of”). Articles become des / der and masculine/neuter nouns often add -s. “das Auto des Mannes.”"
        case .modalverben:
            "können, müssen, wollen, sollen, dürfen, mögen — they push the main verb to the end of the sentence as an infinitive. “Ich muss heute arbeiten.”"
        case .praepositionen:
            "Every German preposition fixes the case of the noun after it. Some always take the Akkusativ (durch, für, ohne, um…), some always the Dativ (aus, bei, mit, nach, von, zu…), some the Genitiv (trotz, während, wegen…), and the two-way ones switch between Akkusativ and Dativ. Learning the preposition means learning its case."
        case .wechselpraepositionen:
            "Prepositions like in, an, auf, über that take the Akkusativ for movement/direction and the Dativ for a fixed location. “Ich gehe in die Stadt” vs. “Ich bin in der Stadt”."
        case .adjektivendungen:
            "Adjectives placed before a noun take endings that change with case, gender, and the article in front — “ein guter Wein”, “mit dem guten Wein”."
        }
    }

    /// One-line rule reminder shown above drill exercises (mirrors the bundled
    /// categories' `ruleNote`, which the multiple-choice header displays).
    var compactRule: String {
        switch self {
        case .perfekt:              "Perfekt: haben/sein + Partizip II — „ich habe gegessen“, „ich bin gegangen“"
        case .praeteritum:          "Präteritum: simple past — „ich war“, „ich hatte“, „ich ging“"
        case .futur:                "Futur I: werden + Infinitiv — „ich werde arbeiten“"
        case .konjunktiv2:          "Konjunktiv II: würde / hätte / wäre / könnte — hypotheticals & politeness"
        case .artikel:              "der (m) · die (f) · das (n) — Endungen helfen: -ung → die, -chen → das"
        case .akkusativ:            "Akkusativ: den (m) · die (f) · das (n) · die (Pl.)"
        case .dativ:                "Dativ: dem (m) · der (f) · dem (n) · den (Pl.)"
        case .genitiv:              "Genitiv: des …s (m/n) · der (f/Pl.)"
        case .modalverben:          "Modalverb konjugiert, Hauptverb als Infinitiv ans Satzende"
        case .praepositionen:       "Die Präposition bestimmt den Fall — durch/für/ohne/um → Akk. · aus/bei/mit/nach/von/zu → Dat."
        case .wechselpraepositionen: "Wohin? (movement) → Akkusativ · Wo? (location) → Dativ"
        case .adjektivendungen:     "Endings follow case, gender & article — „ein guter Wein“"
        }
    }

    /// A German example/hint the AI can use to elicit this structure.
    var steeringHint: String {
        switch self {
        case .perfekt:               "frage nach Vergangenem, z. B. „Was hast du am Wochenende gemacht?“"
        case .praeteritum:           "erzähle und frage im Präteritum, z. B. „Wie war dein Tag?“"
        case .futur:                 "sprich über die Zukunft, z. B. „Was wirst du nächstes Jahr machen?“"
        case .konjunktiv2:           "stelle hypothetische Fragen, z. B. „Was würdest du tun, wenn du viel Geld hättest?“"
        case .artikel:               "frage nach konkreten Dingen und Gegenständen, z. B. „Was ist in deiner Küche?“, damit Substantive mit Artikeln vorkommen"
        case .akkusativ:             "nutze Sätze mit direktem Objekt, z. B. „Was kaufst du heute?“"
        case .dativ:                 "nutze Dativ-Verben und -Präpositionen, z. B. „Wem hilfst du?“, „Mit wem gehst du?“"
        case .genitiv:               "nutze den Genitiv, z. B. „Wessen Idee war das?“"
        case .modalverben:           "stelle Fragen mit Modalverben, z. B. „Was möchtest du machen?“, „Was musst du heute tun?“"
        case .praepositionen:        "stelle Fragen, die Präpositionen erzwingen, z. B. „Mit wem fährst du?“, „Für wen ist das?“, „Seit wann lernst du Deutsch?“"
        case .wechselpraepositionen: "frage nach Ort und Richtung, z. B. „Wohin gehst du?“ und „Wo bist du?“"
        case .adjektivendungen:      "rege Beschreibungen mit Adjektiven an, z. B. „Was für ein Auto möchtest du?“"
        }
    }
}
