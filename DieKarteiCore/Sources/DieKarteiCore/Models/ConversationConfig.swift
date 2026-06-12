import Foundation

// MARK: - Conversation Mode

public enum ConversationMode: String, CaseIterable, Codable, Identifiable {
    case freestyle = "Freestyle"
    case decks     = "From Decks"
    case scenario  = "Scenario"
    case paper     = "Paper"

    public var id: String { rawValue }

    /// Modes selectable in the normal setup picker (paper chats start from a paper instead).
    public static var setupCases: [ConversationMode] { [.freestyle, .decks, .scenario] }

    public var systemImage: String {
        switch self {
        case .freestyle: "bubble.left.and.bubble.right"
        case .decks:     "rectangle.stack"
        case .scenario:  "theatermasks"
        case .paper:     "doc.text"
        }
    }

    public var subtitle: String {
        switch self {
        case .freestyle: "Open-ended chat about anything"
        case .decks:     "Practice words from your decks"
        case .scenario:  "Role-play a real-life situation"
        case .paper:     "Discuss a paper you uploaded"
        }
    }
}

// MARK: - CEFR Level

public enum CEFRLevel: String, CaseIterable, Codable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"

    public var id: String { rawValue }

    public var englishLabel: String {
        switch self {
        case .a1: "Beginner"
        case .a2: "Elementary"
        case .b1: "Intermediate"
        case .b2: "Upper-intermediate"
        case .c1: "Advanced"
        }
    }

    /// Instruction injected into the system prompt to control the AI's complexity.
    public var promptInstruction: String {
        switch self {
        case .a1:
            "The learner is a beginner (A1). Use only the most common words and short, simple sentences in the present tense. Keep each reply to one or two short sentences."
        case .a2:
            "The learner is at A2 (elementary). Use simple everyday vocabulary and mostly short sentences. You may use basic past tense (Perfekt) occasionally."
        case .b1:
            "The learner is at B1 (intermediate). Use everyday vocabulary and a natural mix of tenses, but keep sentences reasonably clear."
        case .b2:
            "The learner is at B2 (upper-intermediate). Use natural German with varied sentence structures and richer vocabulary."
        case .c1:
            "The learner is at C1 (advanced). Use fluent, idiomatic German with complex structures and nuanced vocabulary."
        }
    }
}

// MARK: - Formality

public enum Formality: String, CaseIterable, Codable, Identifiable {
    case du  = "du"
    case sie = "Sie"

    public var id: String { rawValue }

    public var englishLabel: String {
        switch self {
        case .du:  "Informal (du)"
        case .sie: "Formal (Sie)"
        }
    }

    public var promptInstruction: String {
        switch self {
        case .du:  "Address the learner informally using the \"du\" form."
        case .sie: "Address the learner formally using the \"Sie\" form."
        }
    }
}

// MARK: - Correction Strictness

public enum CorrectionStrictness: String, CaseIterable, Codable, Identifiable {
    case gentle   = "Gentle"
    case balanced = "Balanced"
    case strict   = "Strict"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .gentle:   "Only flags mistakes that obscure meaning"
        case .balanced: "Flags grammar, case & clear word-choice errors"
        case .strict:   "Flags every mistake, even small ones"
        }
    }

    public var promptInstruction: String {
        switch self {
        case .gentle:
            "Only point out mistakes that genuinely obscure meaning or are clear grammatical errors. Ignore minor style or punctuation issues."
        case .balanced:
            "Point out grammar, case, word-order, and clear vocabulary mistakes. Ignore tiny stylistic issues."
        case .strict:
            "Point out every grammatical, case, word-order, spelling, and word-choice mistake, even small ones."
        }
    }
}

// MARK: - Grammar Focus

/// A grammar structure the conversation should emphasize. Used to steer the AI's
/// questions and to focus the correction pass. Each case carries an English label
/// and explanation for the picker's subheader and info modal.
public enum GrammarFocus: String, CaseIterable, Codable, Identifiable {
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

    public var id: String { rawValue }

    /// The German name shown as the primary label.
    public var germanLabel: String {
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
    public var englishLabel: String {
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
    public var explanation: String {
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
    public var steeringHint: String {
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

// MARK: - Scenario category

public enum ScenarioCategory: String, CaseIterable, Identifiable {
    case dining
    case services
    case social
    case work
    case travel

    public var id: String { rawValue }

    public var germanTitle: String {
        switch self {
        case .dining:   "Essen & Trinken"
        case .services: "Unterwegs & Erledigungen"
        case .social:   "Soziales"
        case .work:     "Arbeit & Formelles"
        case .travel:   "Reisen"
        }
    }

    public var englishTitle: String {
        switch self {
        case .dining:   "Food & Drink"
        case .services: "Out & About"
        case .social:   "Social"
        case .work:     "Work & Formal"
        case .travel:   "Travel"
        }
    }

    public var systemImage: String {
        switch self {
        case .dining:   "fork.knife"
        case .services: "bag.fill"
        case .social:   "person.2.fill"
        case .work:     "briefcase.fill"
        case .travel:   "airplane"
        }
    }

    /// The scenarios in this category (excludes `custom`).
    public var scenarios: [ConversationScenario] {
        ConversationScenario.allCases.filter { $0.category == self }
    }
}

// MARK: - Scenario

public enum ConversationScenario: String, CaseIterable, Codable, Identifiable {
    // Dining
    case restaurant          // sit-down, host seats you
    case fastCasual          // counter service (döner, build-a-bowl)
    case cafe
    case bar
    case bakery
    // Services / out & about
    case directions
    case haircut
    case doctor
    case pharmacy
    case transport
    case shopping
    case apartmentViewing
    // Social
    case smallTalk
    case date
    case bouncer
    case party
    case makePlans
    // Work & formal
    case jobInterview
    case boss
    case bank
    case phoneCall
    // Travel
    case hotel
    case airport
    // Special
    case custom

    public var id: String { rawValue }

    /// The category this scenario belongs to (`custom` has none).
    public var category: ScenarioCategory? {
        switch self {
        case .restaurant, .fastCasual, .cafe, .bar, .bakery:
            return .dining
        case .directions, .haircut, .doctor, .pharmacy, .transport, .shopping, .apartmentViewing:
            return .services
        case .smallTalk, .date, .bouncer, .party, .makePlans:
            return .social
        case .jobInterview, .boss, .bank, .phoneCall:
            return .work
        case .hotel, .airport:
            return .travel
        case .custom:
            return nil
        }
    }

    public var germanTitle: String {
        switch self {
        case .restaurant:       "Im Restaurant"
        case .fastCasual:       "Imbiss / Döner"
        case .cafe:             "Im Café"
        case .bar:              "An der Bar"
        case .bakery:           "In der Bäckerei"
        case .directions:       "Nach dem Weg fragen"
        case .haircut:          "Beim Friseur"
        case .doctor:           "Beim Arzt"
        case .pharmacy:         "In der Apotheke"
        case .transport:        "Am Bahnhof"
        case .shopping:         "Kleidung kaufen"
        case .apartmentViewing: "Wohnungsbesichtigung"
        case .smallTalk:        "Small Talk"
        case .date:             "Ein Date"
        case .bouncer:          "Am Türsteher"
        case .party:            "Auf einer Party"
        case .makePlans:        "Pläne machen"
        case .jobInterview:     "Vorstellungsgespräch"
        case .boss:             "Mit dem Chef sprechen"
        case .bank:             "Auf der Bank"
        case .phoneCall:        "Formelles Telefonat"
        case .hotel:            "Hotel-Check-in"
        case .airport:          "Am Flughafen"
        case .custom:           "Eigenes Szenario"
        }
    }

    public var englishDescription: String {
        switch self {
        case .restaurant:       "A sit-down restaurant — a host seats you and a waiter takes your order."
        case .fastCasual:       "Order at a counter (döner, build-your-own bowl) and customize it."
        case .cafe:             "Order a coffee and a pastry, maybe chat with the barista."
        case .bar:              "Order a drink at a bar."
        case .bakery:           "At the bakery — order bread, rolls and pastries."
        case .directions:       "Stop a local and ask for directions."
        case .haircut:          "Describe the haircut you want."
        case .doctor:           "Describe your symptoms and understand the doctor's advice."
        case .pharmacy:         "Ask the pharmacist for something for a cold."
        case .transport:        "Buy a train ticket and ask about platforms."
        case .shopping:         "Shop for clothes and ask about sizes and prices."
        case .apartmentViewing: "Viewing a flat — ask the landlord questions."
        case .smallTalk:        "Casual small talk about everyday topics."
        case .date:             "A relaxed first date — get to know each other (with some romantic vocabulary)."
        case .bouncer:          "Convince the bouncer to let you into the club."
        case .party:            "Meet new people at a party."
        case .makePlans:        "Make plans with a friend to meet up."
        case .jobInterview:     "A job interview — talk about your experience."
        case .boss:             "Talk to your boss — ask for time off or discuss a project."
        case .bank:             "Open an account or sort out a problem at the bank."
        case .phoneCall:        "Make a formal phone call to an office."
        case .hotel:            "Check in to a hotel and ask about amenities."
        case .airport:          "Check in for your flight at the airport."
        case .custom:           "Describe your own situation."
        }
    }

    public var systemImage: String {
        switch self {
        case .restaurant:       "fork.knife"
        case .fastCasual:       "takeoutbag.and.cup.and.straw.fill"
        case .cafe:             "cup.and.saucer.fill"
        case .bar:              "wineglass.fill"
        case .bakery:           "birthday.cake"
        case .directions:       "map.fill"
        case .haircut:          "scissors"
        case .doctor:           "stethoscope"
        case .pharmacy:         "cross.case.fill"
        case .transport:        "tram.fill"
        case .shopping:         "tshirt"
        case .apartmentViewing: "house"
        case .smallTalk:        "hand.wave"
        case .date:             "heart.fill"
        case .bouncer:          "person.fill.checkmark"
        case .party:            "party.popper.fill"
        case .makePlans:        "calendar"
        case .jobInterview:     "briefcase"
        case .boss:             "person.crop.rectangle.fill"
        case .bank:             "building.columns.fill"
        case .phoneCall:        "phone.fill"
        case .hotel:            "bed.double.fill"
        case .airport:          "airplane"
        case .custom:           "square.and.pencil"
        }
    }

    /// A random scenario for "surprise me" (never `custom`).
    public static func random() -> ConversationScenario {
        allCases.filter { $0 != .custom }.randomElement() ?? .smallTalk
    }

    /// The role the AI plays and how it should open the scene.
    /// `custom` returns nil so the caller can substitute the user's own text.
    public var roleInstruction: String? {
        switch self {
        case .restaurant:
            "You are a waiter at a sit-down restaurant. Welcome the guest, seat them, and offer the menu, then take their order."
        case .fastCasual:
            "You work the counter at a fast-casual spot (like a döner shop or a build-your-own bowl place). Greet the customer and guide them through choosing and customizing their order."
        case .cafe:
            "You are a barista at a café. Greet the customer and ask what they'd like to drink, plus anything to eat."
        case .bar:
            "You are a bartender. Greet the customer and ask what they'd like to drink."
        case .bakery:
            "You are a friendly salesperson at a German bakery. Greet the customer and ask what they would like to buy."
        case .directions:
            "You are a friendly local on the street. The learner stops you to ask for directions — respond helpfully and ask where they're trying to get to."
        case .haircut:
            "You are a hairdresser. Greet the client and ask how they'd like their hair cut today."
        case .doctor:
            "You are a doctor (Hausärztin/Hausarzt). Greet the patient and ask what brings them in today."
        case .pharmacy:
            "You are a pharmacist. Greet the customer and ask how you can help."
        case .transport:
            "You work at a train station ticket counter. Greet the traveler and ask where they want to go."
        case .shopping:
            "You are a shop assistant in a clothing store. Greet the customer and offer to help them find something."
        case .apartmentViewing:
            "You are a landlord showing an apartment. Greet the visitor and briefly describe the flat, then invite questions."
        case .smallTalk:
            "You are a friendly acquaintance making small talk. Greet the learner warmly and ask how they are doing."
        case .date:
            "You are on a friendly first date with the learner at a café. Be warm and curious, ask about their interests, and keep it light and kind."
        case .bouncer:
            "You are a bouncer at a club door. Be a little gruff but fair — ask the learner why you should let them in and gauge the vibe."
        case .party:
            "You are a guest at a house party meeting the learner for the first time. Be friendly and curious, and start some small talk."
        case .makePlans:
            "You are a friend of the learner. Suggest meeting up soon and work out the details together — when, where, and what to do."
        case .jobInterview:
            "You are a recruiter conducting a job interview. Welcome the candidate and ask them to introduce themselves."
        case .boss:
            "You are the learner's boss. Be professional but approachable, and ask what they wanted to talk about."
        case .bank:
            "You are a bank clerk. Greet the customer and ask how you can help them today."
        case .phoneCall:
            "You are an office receptionist answering a formal phone call. Greet the caller formally and ask how you can help."
        case .hotel:
            "You are a hotel receptionist. Welcome the guest and start the check-in."
        case .airport:
            "You are an airline check-in agent at the airport. Greet the passenger and ask for their booking details."
        case .custom:
            nil
        }
    }
}

// MARK: - Conversation Configuration

/// The full configuration captured in the setup screen and used to drive a session.
public struct ConversationConfig {
    public var mode: ConversationMode = .freestyle
    public var deckIDs: [UUID] = []
    public var deckLabel: String = ""
    public var deckWords: [String] = []
    public var scenario: ConversationScenario? = nil
    public var customScenario: String = ""
    public var focusAreas: [GrammarFocus] = []
    public var level: CEFRLevel = .a2
    public var formality: Formality = .du
    public var correctionsEnabled: Bool = true
    public var strictness: CorrectionStrictness = .balanced
    public var model: MLXModel
    public var autoPlay: Bool = true
    /// Pre-compute the translation and a next-turn hint in the background after each reply.
    public var eagerAssist: Bool = false
    /// When eager assist is on, also display the translation automatically (vs. pre-load only).
    public var autoShowTranslation: Bool = true
    /// How many suggestions the hint feature generates (1–3).
    public var hintCount: Int = 1
    /// For `.paper` mode: the paper's title and the reference text injected into the chat.
    public var paperTitle: String? = nil
    public var paperContext: String? = nil

    public init(mode: ConversationMode = .freestyle,
                deckIDs: [UUID] = [],
                deckLabel: String = "",
                deckWords: [String] = [],
                scenario: ConversationScenario? = nil,
                customScenario: String = "",
                focusAreas: [GrammarFocus] = [],
                level: CEFRLevel = .a2,
                formality: Formality = .du,
                correctionsEnabled: Bool = true,
                strictness: CorrectionStrictness = .balanced,
                model: MLXModel,
                autoPlay: Bool = true,
                eagerAssist: Bool = false,
                autoShowTranslation: Bool = true,
                hintCount: Int = 1,
                paperTitle: String? = nil,
                paperContext: String? = nil) {
        self.mode = mode
        self.deckIDs = deckIDs
        self.deckLabel = deckLabel
        self.deckWords = deckWords
        self.scenario = scenario
        self.customScenario = customScenario
        self.focusAreas = focusAreas
        self.level = level
        self.formality = formality
        self.correctionsEnabled = correctionsEnabled
        self.strictness = strictness
        self.model = model
        self.autoPlay = autoPlay
        self.eagerAssist = eagerAssist
        self.autoShowTranslation = autoShowTranslation
        self.hintCount = hintCount
        self.paperTitle = paperTitle
        self.paperContext = paperContext
    }

    /// A human-readable title for the saved-chats list.
    public var displayTitle: String {
        switch mode {
        case .scenario:
            if scenario == .custom, !customScenario.isEmpty {
                return String(customScenario.prefix(40))
            }
            return scenario?.germanTitle ?? "Szenario"
        case .decks:
            return deckLabel.isEmpty ? "Deck-Gespräch" : deckLabel
        case .freestyle:
            return "Freies Gespräch"
        case .paper:
            return paperTitle ?? "Paper-Gespräch"
        }
    }
}
