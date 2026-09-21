import Foundation

// MARK: - Conversation Mode

enum ConversationMode: String, CaseIterable, Codable, Identifiable {
    case freestyle = "Freestyle"
    case decks     = "From Decks"
    case scenario  = "Scenario"
    case interview = "Interview"
    case paper     = "Paper"

    var id: String { rawValue }

    /// Modes selectable in the normal setup picker (paper chats start from a paper instead).
    static var setupCases: [ConversationMode] { [.freestyle, .decks, .scenario, .interview] }

    var systemImage: String {
        switch self {
        case .freestyle: "bubble.left.and.bubble.right"
        case .decks:     "rectangle.stack"
        case .scenario:  "theatermasks"
        case .interview: "briefcase.fill"
        case .paper:     "doc.text"
        }
    }

    var subtitle: String {
        switch self {
        case .freestyle: "Open-ended chat about anything"
        case .decks:     "Practice words from your decks"
        case .scenario:  "Role-play a real-life situation"
        case .interview: "Interview for a real job posting"
        case .paper:     "Discuss a paper you uploaded"
        }
    }
}

// MARK: - CEFR Level

enum CEFRLevel: String, CaseIterable, Codable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"

    var id: String { rawValue }

    var englishLabel: String {
        switch self {
        case .a1: "Beginner"
        case .a2: "Elementary"
        case .b1: "Intermediate"
        case .b2: "Upper-intermediate"
        case .c1: "Advanced"
        }
    }

    /// A first-person can-do statement, for the screen where a learner picks their own level.
    /// CEFR self-assessment framing: the question is "which of these sounds like me?", which
    /// `englishLabel` alone can't answer — "Elementary" and "Intermediate" don't tell anyone which
    /// one they are.
    var selfAssessment: String {
        switch self {
        case .a1: "I know everyday expressions and very basic phrases."
        case .a2: "I can handle simple, routine exchanges about familiar things."
        case .b1: "I can get by while travelling and explain my opinions."
        case .b2: "I can hold a real discussion on a range of topics."
        case .c1: "I use German fluently and flexibly, for work or study."
        }
    }

    /// Instruction injected into the system prompt to control the AI's complexity.
    var promptInstruction: String {
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

enum Formality: String, CaseIterable, Codable, Identifiable {
    case du  = "du"
    case sie = "Sie"

    var id: String { rawValue }

    var englishLabel: String {
        switch self {
        case .du:  "Informal (du)"
        case .sie: "Formal (Sie)"
        }
    }

    var promptInstruction: String {
        switch self {
        case .du:  "Address the learner informally using the \"du\" form."
        case .sie: "Address the learner formally using the \"Sie\" form."
        }
    }
}

// MARK: - Input mode

/// How the learner takes their turn. Speaking is the default, but a conversation is just as
/// useful typed — on a plane, in an office, or anywhere talking to your phone isn't an option.
/// Typing also silences auto-play, so a session can be run start to finish without a sound.
enum ChatInputMode: String, CaseIterable, Codable, Identifiable {
    case speak = "Speak"
    case type  = "Type"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .speak: "mic.fill"
        case .type:  "keyboard.fill"
        }
    }

    /// The other mode — the one the in-chat switch flips to.
    var toggled: ChatInputMode { self == .speak ? .type : .speak }

    var subtitle: String {
        switch self {
        case .speak: "Tap the mic and say your turn out loud"
        case .type:  "Write your turn instead — replies stay silent"
        }
    }

    /// True when this mode keeps the session soundless unless the learner asks to hear something.
    var isSilent: Bool { self == .type }
}

// MARK: - Correction Strictness

enum CorrectionStrictness: String, CaseIterable, Codable, Identifiable {
    case gentle   = "Gentle"
    case balanced = "Balanced"
    case strict   = "Strict"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .gentle:   "Only flags mistakes that obscure meaning"
        case .balanced: "Flags grammar, case & clear word-choice errors"
        case .strict:   "Flags every mistake, even small ones"
        }
    }

    var promptInstruction: String {
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

// MARK: - Feedback style

/// How a correction is delivered. `tellMe` hands the learner the fix (today's behavior);
/// `nudgeMe` first asks a targeted question so they can repair their own error, revealing the
/// fix only after a miss or on request. Repairing your own mistake sticks far better than being
/// handed the answer, so this is a pedagogically stronger mode for learners who want to work.
enum FeedbackStyle: String, CaseIterable, Codable, Identifiable {
    case tellMe  = "Tell me"
    case nudgeMe = "Nudge me"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .tellMe:  "Shows the corrected sentence right away"
        case .nudgeMe: "Asks a question first so you can fix it yourself"
        }
    }

    var systemImage: String {
        switch self {
        case .tellMe:  "text.bubble.fill"
        case .nudgeMe: "questionmark.bubble.fill"
        }
    }
}

// MARK: - Scenario category

enum ScenarioCategory: String, CaseIterable, Identifiable {
    case dining
    case services
    case social
    case work
    case travel

    var id: String { rawValue }

    var germanTitle: String {
        switch self {
        case .dining:   "Essen & Trinken"
        case .services: "Unterwegs & Erledigungen"
        case .social:   "Soziales"
        case .work:     "Arbeit & Formelles"
        case .travel:   "Reisen"
        }
    }

    var englishTitle: String {
        switch self {
        case .dining:   "Food & Drink"
        case .services: "Out & About"
        case .social:   "Social"
        case .work:     "Work & Formal"
        case .travel:   "Travel"
        }
    }

    var systemImage: String {
        switch self {
        case .dining:   "fork.knife"
        case .services: "bag.fill"
        case .social:   "person.2.fill"
        case .work:     "briefcase.fill"
        case .travel:   "airplane"
        }
    }

    /// The scenarios in this category (excludes `custom`).
    var scenarios: [ConversationScenario] {
        ConversationScenario.allCases.filter { $0.category == self }
    }
}

// MARK: - Scenario

enum ConversationScenario: String, CaseIterable, Codable, Identifiable {
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

    var id: String { rawValue }

    /// The category this scenario belongs to (`custom` has none).
    var category: ScenarioCategory? {
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

    var germanTitle: String {
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

    /// A short English label for the German title — shown alongside it in pickers.
    var englishTitle: String {
        switch self {
        case .restaurant:       "Restaurant"
        case .fastCasual:       "Food counter"
        case .cafe:             "Café"
        case .bar:              "Bar"
        case .bakery:           "Bakery"
        case .directions:       "Asking directions"
        case .haircut:          "Hairdresser"
        case .doctor:           "Doctor's office"
        case .pharmacy:         "Pharmacy"
        case .transport:        "Train station"
        case .shopping:         "Clothes shopping"
        case .apartmentViewing: "Flat viewing"
        case .smallTalk:        "Small talk"
        case .date:             "A date"
        case .bouncer:          "Club door"
        case .party:            "At a party"
        case .makePlans:        "Making plans"
        case .jobInterview:     "Job interview"
        case .boss:             "Talking to your boss"
        case .bank:             "At the bank"
        case .phoneCall:        "Formal phone call"
        case .hotel:            "Hotel check-in"
        case .airport:          "Airport"
        case .custom:           "Custom scenario"
        }
    }

    var englishDescription: String {
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

    var systemImage: String {
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
    static func random() -> ConversationScenario {
        allCases.filter { $0 != .custom }.randomElement() ?? .smallTalk
    }

    /// The role the AI plays and how it should open the scene.
    /// `custom` returns nil so the caller can substitute the user's own text.
    var roleInstruction: String? {
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

// MARK: - Spaced review scope

/// Where SRS "spaced re-encounter" applies — which conversations may resurface due flashcards and
/// advance their schedule when the learner uses the word correctly. Backed by a raw string setting.
enum SpacedReviewScope: String, CaseIterable, Codable, Identifiable {
    /// Every conversation. Deck chats favor their own decks first, then top up library-wide.
    case everywhere
    /// Only "From Decks" conversations, using that chat's chosen decks.
    case decksOnly
    /// Freestyle and deck chats only — scenario role-plays, interviews, and paper discussions
    /// are left alone.
    case exceptScripted

    var id: String { rawValue }

    /// Short label for the settings picker.
    var label: String {
        switch self {
        case .everywhere:    "Everywhere"
        case .decksOnly:     "Deck chats"
        case .exceptScripted: "Skip role-plays"
        }
    }

    /// One-line explanation shown under the picker.
    var footer: String {
        switch self {
        case .everywhere:
            "Every conversation can resurface your most-overdue cards — deck chats favor their own decks first."
        case .decksOnly:
            "Only “From Decks” conversations, using that chat's decks."
        case .exceptScripted:
            "Freestyle and deck chats only — role-plays, interviews, and paper discussions are left alone."
        }
    }

    /// Whether spaced review runs at all for a conversation of this mode.
    func applies(to mode: ConversationMode) -> Bool {
        switch self {
        case .everywhere:     return true
        case .decksOnly:      return mode == .decks
        case .exceptScripted: return mode == .freestyle || mode == .decks
        }
    }

    /// Whether, for this mode, due cards may be pulled from the whole library (vs. the chat's decks
    /// only). Deck chats always prioritize their own decks first regardless.
    func allowsLibraryWide(for mode: ConversationMode) -> Bool {
        switch self {
        case .everywhere:     return true
        case .decksOnly:      return false
        case .exceptScripted: return true
        }
    }
}

// MARK: - Learned phrase (session payload)

/// A single phrase from the user's library, carried into a session so the AI can weave it in.
/// Mirrors `SavedVocabItem` — a lightweight value type, not the SwiftData model.
struct LearnedPhraseItem: Identifiable, Hashable {
    var german: String
    var english: String
    var id: String { german.lowercased() }
}

// MARK: - Conversation Configuration

/// The full configuration captured in the setup screen and used to drive a session.
struct ConversationConfig {
    var mode: ConversationMode = .freestyle
    var deckIDs: [UUID] = []
    var deckLabel: String = ""
    var deckWords: [String] = []
    var scenario: ConversationScenario? = nil
    var customScenario: String = ""
    var focusAreas: [GrammarFocus] = []
    /// Phrases from the user's library that are surfaced this session — the AI weaves these
    /// into the scenario as things its character says, so the learner gets used to hearing them.
    var learnedPhrases: [LearnedPhraseItem] = []
    /// Steering-only coach memory injected into the conversation prompt (built from the
    /// persistent `LearnerProfile` at session start). Empty when personalized coaching is off.
    var learnerBriefing: String = ""
    /// Watch-for coach memory injected into the separate correction pass.
    var correctionMemoryHint: String = ""
    /// German words that are SRS-due right now (article-prefixed display forms), injected into the
    /// conversation prompt so the coach steers the learner toward re-using them. Empty when spaced
    /// review is off or nothing is currently due. Advancement is handled by `ConversationReviewTracker`.
    var dueReviewWords: [String] = []
    var level: CEFRLevel = .a2
    var formality: Formality = .du
    var correctionsEnabled: Bool = true
    /// When a correction is shown, also display the English meaning of the corrected sentence.
    var correctionTranslationEnabled: Bool = false
    var strictness: CorrectionStrictness = .balanced
    /// How corrections are delivered — hand over the fix, or nudge the learner to self-correct first.
    var feedbackStyle: FeedbackStyle = .tellMe
    var model: MLXModel
    /// Speak the turn or type it. Typing also suppresses auto-play so nothing makes a sound.
    var inputMode: ChatInputMode = .speak
    var autoPlay: Bool = true
    /// Pre-compute the translation and a next-turn hint in the background after each reply.
    var eagerAssist: Bool = false
    /// When eager assist is on, also display the translation automatically (vs. pre-load only).
    var autoShowTranslation: Bool = true
    /// How many suggestions the hint feature generates (1–3).
    var hintCount: Int = 1
    /// Surface a "you could say" hint automatically after every AI reply.
    var autoHints: Bool = false
    /// Tint nouns in AI replies with their der/die/das color.
    var genderColors: Bool = true
    /// For `.paper` mode: the paper's title and the reference text injected into the chat.
    var paperTitle: String? = nil
    var paperContext: String? = nil
    /// For `.interview` mode: the job title and the posting text the recruiter interviews from
    /// (German or English — the interview itself is always in German).
    var jobTitle: String? = nil
    var jobContext: String? = nil
    /// Where the interview is for: the employer and the job's location as captured from the posting
    /// (or typed by the learner), plus the posting's URL so it can be reopened. All optional; chats
    /// saved before these existed simply have none.
    var jobCompany: String? = nil
    var jobLocation: String? = nil
    var jobURL: String? = nil
    /// Which stage of the hiring process, and over which channel, the interview rehearses. Nil on
    /// chats from before these existed; the recruiter then behaves as it always did.
    var interviewRound: InterviewRound? = nil
    var interviewFormat: InterviewFormat? = nil
    /// File name of the saved PDF copy of the posting in `JobPostingSnapshotStore`, if one exists.
    var jobSnapshotFile: String? = nil
    /// The studied `JobPosting` this interview rehearses for, when it was started from one.
    var jobPostingID: UUID? = nil
    /// What the conversation partner calls the learner, exactly as the learner typed it in
    /// Settings. Nil when they left it blank.
    var learnerName: String? = nil

    /// The stored name as the prompt wants it: trimmed, nil when blank.
    static func learnerName(from stored: String) -> String? {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(60))
    }

    /// Longest job title stored as the chat name.
    static let jobTitleCap = 90
    /// Longest company / location string stored with an interview chat.
    static let jobDetailCap = 80

    /// A human-readable title for the saved-chats list.
    var displayTitle: String {
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
        case .interview:
            return jobTitle ?? "Vorstellungsgespräch"
        case .paper:
            return paperTitle ?? "Paper-Gespräch"
        }
    }
}

// MARK: - Interview round & format

/// Which stage of the hiring process an interview chat rehearses. Steers who the interviewer is
/// and what they dig into.
enum InterviewRound: String, CaseIterable, Codable, Identifiable {
    case screening
    case technical
    case final

    var id: String { rawValue }

    var label: String {
        switch self {
        case .screening: "HR screening"
        case .technical: "Technical round"
        case .final:     "Final round"
        }
    }

    var systemImage: String {
        switch self {
        case .screening: "person.text.rectangle"
        case .technical: "wrench.and.screwdriver"
        case .final:     "person.2.badge.gearshape"
        }
    }

    /// One line under the picker saying what this round is about.
    var blurb: String {
        switch self {
        case .screening: "A recruiter on your background, motivation, and how you work with people."
        case .technical: "Someone from the team on the skills and tools the posting names."
        case .final:     "The hiring manager on expectations, your first months, and your own questions."
        }
    }

    /// Who sits across the table, for the persona line of the prompt.
    var persona: String {
        switch self {
        case .screening: "an experienced recruiter"
        case .technical: "a senior member of the team, conducting the technical round"
        case .final:     "the hiring manager"
        }
    }

    /// Steering for the recruiter prompt.
    var promptInstruction: String {
        switch self {
        case .screening:
            "This is the first-round HR screening. You are the recruiter. Focus on the candidate's background and career path, their motivation for this role and company, strengths and weaknesses, how they work with colleagues, and practical points such as availability and expectations. Keep technical questions light; you are checking fit and communication."
        case .technical:
            "This is the technical round. You are a senior member of the team the role reports to. Draw your questions from the concrete skills, tools, systems, and responsibilities named in the posting: ask how the candidate has used each one, pose short practical scenarios from the role's daily work, ask them to walk through how they would solve a problem, and follow up on the details of their answers. If the candidate asks what a term means, explain it briefly in simple German and continue."
        case .final:
            "This is the final round. You are the hiring manager. Focus on what the role expects, how the candidate would approach their first months, their working style and priorities, how they handle pressure and conflict, and team fit. Leave room for the candidate's own questions about the team and the company, and answer them from the posting."
        }
    }
}

/// The channel the interview happens over. Sets the opening and the tone.
enum InterviewFormat: String, CaseIterable, Codable, Identifiable {
    case phone
    case video
    case inPerson

    var id: String { rawValue }

    var label: String {
        switch self {
        case .phone:    "Phone call"
        case .video:    "Video call"
        case .inPerson: "In person"
        }
    }

    var systemImage: String {
        switch self {
        case .phone:    "phone.fill"
        case .video:    "video.fill"
        case .inPerson: "person.2.fill"
        }
    }

    var blurb: String {
        switch self {
        case .phone:    "Voice only: crisp questions, no visual cues."
        case .video:    "A short audio check, then straight in."
        case .inPerson: "Welcomed at the office, a little small talk first."
        }
    }

    /// What the interviewer does in the greeting, as a clause for the prompt's first-message rule.
    var openerClause: String {
        switch self {
        case .phone:    "check in one sentence that it is a good moment to talk"
        case .video:    "check in one sentence that the candidate can hear you well"
        case .inPerson: "welcome the candidate to the office and offer them a seat"
        }
    }

    /// The same clause in German, for the hidden seed turn that makes the model open.
    var openerSeedClause: String {
        switch self {
        case .phone:    "frag in einem Satz, ob es gerade passt"
        case .video:    "frag in einem Satz, ob ich Sie gut höre"
        case .inPerson: "heiß mich im Büro willkommen und biete mir einen Platz an"
        }
    }

    /// Tone rules for the rest of the interview. Nothing here invites small talk: the earlier
    /// "occasionally check the candidate is still with you" produced filler questions about
    /// scheduling instead of questions about the job.
    var promptInstruction: String {
        switch self {
        case .phone:
            "The interview is a phone call. There is no visual channel, so never refer to anything visual, and keep each question short and clear."
        case .video:
            "The interview is a video call. Keep small talk to the greeting; after that, every turn is about the role."
        case .inPerson:
            "The interview is in person at the company's office. A sentence of small talk about the candidate's journey belongs in the greeting only; after that, every turn is about the role."
        }
    }
}
