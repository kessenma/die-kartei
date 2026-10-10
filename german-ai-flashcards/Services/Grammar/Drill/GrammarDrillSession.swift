//
//  GrammarDrillSession.swift
//  german-ai-flashcards
//
//  What `Activity.grammarDrill` launches: an exercise kind in a topic, with the module's own
//  configuration for the round (`DrillVariant`). One case on `Activity` and one seam in
//  `ContentView` serve every kind; the kind picks its module (`KasusDrillKind+Shell.swift`).
//

import Foundation

struct GrammarDrillSession: Identifiable {
    let id = UUID()
    let kind: KasusDrillKind
    let topic: GrammarTopic
    /// The module's configuration for this round. A mode switch replaces it and rebuilds the
    /// round over the same items.
    var variant: DrillVariant
    /// Set only by the DEBUG launch arguments; nil in every real session. With it the shell
    /// reads its state from the launch arguments and never records the round.
    var prefill: KasusPrefill? = nil
    /// Blitzrunde: the best score so far, read from the round history by whoever launches it.
    var personalBest: Int? = nil

    /// „Schnellrunde · Dativ“, „Rollen · Dativ“: the title on the drill screen.
    var title: String { "\(kind.meta.germanTitle) · \(topic.germanTitle)" }

    init(kind: KasusDrillKind, topic: GrammarTopic, variant: DrillVariant? = nil, prefill: KasusPrefill? = nil) {
        self.kind = kind
        self.topic = topic
        self.variant = variant ?? DrillVariant.standard(for: kind, in: topic)
        self.prefill = prefill
    }
}

/// A module's typed configuration for one round. Each module reads its own case and ignores the
/// rest; a kind whose module isn't built yet gets the endings default and shows nothing to play.
enum DrillVariant: Hashable {
    case endings(EndingsConfig)
    case concept(ConceptConfig)
    case gap(GapConfig)

    /// The configuration a kind plays with when nothing else is asked: the topic's cases, the
    /// kind's round size, the remembered Rollen mode.
    static func standard(for kind: KasusDrillKind, in topic: GrammarTopic) -> DrillVariant {
        switch kind {
        case .roles, .wer, .probe:
            let exercise = KasusConceptExercise(step: kind.step) ?? .roles
            let stored = UserDefaults.standard.string(forKey: KasusRolesMode.storageKey) ?? ""
            return .concept(ConceptConfig(exercise: exercise, rolesMode: KasusRolesMode.resolve(stored: stored)))
        case .build:
            return .endings(EndingsConfig(style: .ending, cases: topic.casesInPlay, emphasis: topic.emphasis,
                                          count: kind.meta.roundSize))
        case .dativVerbs:
            // The family holds Dativ and Akkusativ frames only, so the round spans those two.
            return .endings(EndingsConfig(style: .article, cases: topic.casesInPlay, emphasis: .dativ,
                                          count: kind.meta.roundSize, family: .dativVerb))
        case .blitz:
            return .endings(EndingsConfig(style: .article, cases: topic.casesInPlay, emphasis: topic.emphasis,
                                          count: EndingsConfig.blitzQuestions, deferredFeedback: true,
                                          timeLimit: EndingsConfig.blitzSeconds))
        case .reflexCase:
            return .gap(GapConfig(focus: .case, count: kind.meta.roundSize))
        case .reflexPerson:
            return .gap(GapConfig(focus: .person, count: kind.meta.roundSize))
        case .quick, .pair, .fehler, .bridge:
            return .endings(EndingsConfig(style: .article, cases: topic.casesInPlay, emphasis: topic.emphasis,
                                          count: max(1, kind.meta.roundSize)))
        }
    }
}

/// The endings drills: the Schnellrunde, Bau das Wort, and the variants on the same engine.
struct EndingsConfig: Hashable {
    enum Style: Hashable {
        /// Whole articles as buttons (the Schnellrunde).
        case article
        /// Ending labels as buttons, the word built in 3D (Bau das Wort).
        case ending
    }

    var style: Style = .article
    var cases: [GrammarCase]
    var emphasis: GrammarCase? = nil
    var count: Int = 10
    /// Only this family's frames (Dativ-Verben). Nil: every frame.
    var family: EndingsFrame.Family? = nil
    /// Only these forms as buttons (a confusion pair: dem vs den). Nil: the family's row.
    var options: [String]? = nil
    /// Only nouns of these genders. Nil: every noun.
    var genders: Set<Gender>? = nil
    /// Only these article families (a confusion pair of definite forms). Nil: every family.
    var determiners: [EndingsDeterminer]? = nil
    /// No feedback card mid-round; the misses wait for the summary (Blitzrunde).
    var deferredFeedback = false
    /// Seconds on the clock (Blitzrunde). Nil: untimed.
    var timeLimit: Int? = nil

    /// The Blitzrunde: a minute on the clock, and more questions than anyone answers in it.
    static let blitzSeconds = 60
    static let blitzQuestions = 60
}

/// The gap-choice drills on the bundled items (`GapChoiceBank`).
struct GapConfig: Hashable {
    var focus: GapChoiceFocus
    var count: Int = 10
}

/// The Verstehen exercises on the concept bank.
struct ConceptConfig: Hashable {
    var exercise: KasusConceptExercise
    /// Rollen: Schritt für Schritt or Direkt. Ignored by the other exercises.
    var rolesMode: KasusRolesMode = .direkt
}
