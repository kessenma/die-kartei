//
//  GrammarRoute.swift
//  german-ai-flashcards
//
//  Where practising a grammar focus goes, decided in one place. Today's weak-spot row, Coach's
//  Notes' "Practice this", the pyramid's "Wo du stehst" rows and a class entry's story row all ask
//  the same question; each used to answer it on its own, and the pyramid sent every case focus to
//  the preposition hub.
//
//    akkusativ · dativ · genitiv     Einsetzen in the unit's least-recently-played story, or the
//                                    unit's Schnellrunde while the unit has no story yet
//    artikel                         a der/die/das round at the learner's level
//    praepositionen · wechsel…       the preposition hub
//    everything else                 the quick lesson (`GrammarLessonSheet`)
//
//  A route is cheap and pure, so a row can decide while it renders whether it is a button or a
//  NavigationLink. What a tap opens (which story, which nouns) is resolved at the tap, since it
//  reads round history and samples a noun pool. Each surface presents the result its own way:
//  the router for an activity, a push for the hub, a sheet (or an inline lesson) for the rest.
//

import Foundation
import SwiftData

enum GrammarRoute: Hashable {
    /// A Kasus unit: its least-recently-played story at Einsetzen, else its Schnellrunde.
    case kasus(KasusUnit)
    /// A der/die/das round.
    case articleGame
    /// `PrepositionHubView`, pushed.
    case prepositionHub
    /// `GrammarLessonSheet`, the 30-second explanation. Structures with no exercise of their own.
    case lesson(GrammarFocus)

    init(_ focus: GrammarFocus) {
        if let unit = KasusUnit.allCases.first(where: { $0.focus == focus }) {
            self = .kasus(unit)
            return
        }
        switch focus {
        case .artikel:
            self = .articleGame
        case .praepositionen, .wechselpraepositionen:
            self = .prepositionHub
        default:
            self = .lesson(focus)
        }
    }

    // MARK: Presentation

    /// How a surface shows the route: a full-screen activity, a pushed screen, or a sheet.
    enum Presentation {
        case launch, push, sheet
    }

    var presentation: Presentation {
        switch self {
        case .kasus, .articleGame: .launch
        case .prepositionHub:      .push
        case .lesson:              .sheet
        }
    }

    /// Everything but the quick lesson has an exercise of its own.
    var hasExercise: Bool { presentation != .sheet }

    // MARK: Resolving a tap

    /// What a tap opens, resolved now.
    enum Destination {
        /// Hand to `ActivityRouter.launch`.
        case launch(Activity)
        /// Push `PrepositionHubView`.
        case prepositionHub
        /// Present `GrammarLessonSheet`.
        case lesson(GrammarFocus)
    }

    /// Reads the unit's round history for a story pick and samples the article pool, so call it
    /// from the tap, not from a view's body. `level` is the learner's anchor, read only.
    func resolve(in context: ModelContext, level: CEFRLevel) -> Destination {
        switch self {
        case .kasus(let unit):
            return .launch(Self.kasusActivity(for: unit, rounds: Self.rounds(for: unit, in: context)))
        case .articleGame:
            // The Goethe lists always hold enough nouns; the lesson is only a safety net.
            guard let activity = Self.articleActivity(level: level, in: context) else { return .lesson(.artikel) }
            return .launch(activity)
        case .prepositionHub:
            return .prepositionHub
        case .lesson(let focus):
            return .lesson(focus)
        }
    }

    // MARK: Kasus

    /// The unit's story at Einsetzen, the step that moves the case skill, or its Schnellrunde
    /// while the unit has no story. The step bar still reaches Lesen and Finden.
    static func kasusActivity(for unit: KasusUnit, rounds: [KasusRound],
                              bank: KasusStoryBank = .bundled) -> Activity {
        if let story = practiceStory(for: unit, rounds: rounds, bank: bank) {
            return .kasusStory(KasusSession(storyID: story.id, unit: unit, startStep: .einsetzen))
        }
        return .caseEndings(CaseEndingsSession(unit: unit))
    }

    /// The unit's least-recently-played story: an unplayed one first, in the bank's order.
    /// Nil while the unit has no story.
    static func practiceStory(for unit: KasusUnit, rounds: [KasusRound],
                              bank: KasusStoryBank = .bundled) -> KasusStory? {
        let progress = KasusProgress(rounds: rounds)
        return bank.stories(for: unit).min {
            (progress.lastPlayed($0) ?? .distantPast) < (progress.lastPlayed($1) ?? .distantPast)
        }
    }

    /// True once the unit has a story, so a row can say "story" or "Schnellrunde" before the tap.
    static func hasStory(_ unit: KasusUnit, bank: KasusStoryBank = .bundled) -> Bool {
        !bank.stories(for: unit).isEmpty
    }

    private static func rounds(for unit: KasusUnit, in context: ModelContext) -> [KasusRound] {
        let raw = unit.rawValue
        let descriptor = FetchDescriptor<KasusRound>(predicate: #Predicate { $0.unitRaw == raw })
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Artikel

    /// A der/die/das round from the Goethe list at the learner's level, with the nouns they keep
    /// missing mixed back in. Uses the setup screen's own two settings (round size, "Bring back
    /// tricky nouns"), so a round from here plays like one started there.
    static func articleActivity(level: CEFRLevel, in context: ModelContext) -> Activity? {
        let goethe: GoetheLevel = switch level {
        case .a1:           .a1
        case .a2:           .a2
        case .b1, .b2, .c1: .b1
        }
        let defaults = UserDefaults.standard
        let count = defaults.object(forKey: "articleGame.questionCount") as? Int ?? 10
        let trickyFirst = defaults.object(forKey: "articleGame.trickyFirst") as? Bool ?? true
        // Tricky nouns go into the pool so ones from outside this list can come back too.
        let pool = (trickyFirst ? ArticleGameService.trickyQuestions(in: context) : [])
            + ArticleGameService.goetheQuestions(level: goethe)
        guard let session = ArticleGameService.session(
            topic: "Goethe \(goethe.rawValue)", pool: pool, count: count,
            trickyFirst: trickyFirst, in: context
        ) else { return nil }
        return .articleGame(session)
    }

    // MARK: DEBUG

    #if DEBUG
    /// `-kasus.debugRoute 1`: every focus, what a tap resolves to against the live store, and how
    /// each surface presents it; then whether a case, article or preposition focus fell back to
    /// the lesson sheet. Resolving only reads (round history, a sampled noun pool).
    static func debugReport(in context: ModelContext, level: CEFRLevel) -> [String] {
        let bank = KasusStoryBank.bundled
        var lines = ["level \(level.rawValue) · stories "
                     + KasusUnit.allCases.map { "\($0.germanTitle) \(bank.stories(for: $0).count)" }
                        .joined(separator: " · ")]
        // Listed by hand, not read from the route, so a mapping that slips shows up here.
        let mustPractise: Set<GrammarFocus> = [.akkusativ, .dativ, .genitiv, .artikel,
                                               .praepositionen, .wechselpraepositionen]
        var fallbacks: [GrammarFocus] = []

        for focus in GrammarFocus.allCases {
            let route = GrammarRoute(focus)
            let destination = route.resolve(in: context, level: level)
            if case .lesson = destination, mustPractise.contains(focus) {
                fallbacks.append(focus)
            }
            lines.append("\(focus.rawValue) → \(describe(destination))")

            let verb: String = switch destination {
            case .launch:         "launch"
            case .prepositionHub: "push"
            case .lesson:         "sheet"
            }
            let coach = route.hasExercise ? "Practice this, \(verb)" : "inline lesson, no button"
            let pyramid: String = switch PyramidCoachSection.area(for: focus) {
            case .artikel:    "Artikel row, pushes the der/die/das setup"
            case .faelle:     "Fälle row when the worst shaky case, \(verb)"
            case .strukturen: "Strukturen row when the worst shaky one, \(verb)"
            }
            let classEntry: String
            switch route {
            case .kasus(let unit):
                let row = hasStory(unit, bank: bank) ? "Mit einer Geschichte üben" : "Schnellrunde"
                classEntry = "„\(row)“ row, \(verb)"
            case .articleGame:
                classEntry = "„Der · Die · Das üben“ row, \(verb)"
            case .prepositionHub:
                classEntry = "„Präpositionen“ row, \(verb)"
            case .lesson:
                classEntry = "pill, quick lesson"
            }
            lines.append("  Today \(verb) · Coach \(coach) · Pyramid \(pyramid) · Class entry \(classEntry)")
        }

        lines.append(fallbacks.isEmpty
            ? "OK · no case, article or preposition focus falls back to the lesson sheet"
            : "FAIL · falls back to the lesson: \(fallbacks.map(\.rawValue).joined(separator: ", "))")
        return lines
    }

    private static func describe(_ destination: Destination) -> String {
        switch destination {
        case .launch(let activity):
            switch activity {
            case .kasusStory(let session):
                let title = session.story?.title ?? session.storyID
                return "\(session.startStep.germanLabel) · „\(title)“ (\(session.storyID), \(session.unit.germanTitle))"
            case .caseEndings(let session):
                let cases = session.cases.map(\.short).joined(separator: " + ")
                return "\(session.title) · \(cases) (no \(session.unit.germanTitle) story yet)"
            case .articleGame(let session):
                return "der/die/das round · \(session.topic) · \(session.questionCount) nouns"
            default:
                return "activity \(activity.id)"
            }
        case .prepositionHub:
            return "Präpositionen hub"
        case .lesson(let focus):
            return "quick lesson (\(focus.germanLabel))"
        }
    }
    #endif
}
