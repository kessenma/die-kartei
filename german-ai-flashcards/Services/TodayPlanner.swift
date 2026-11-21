import SwiftUI

/// What a Today recommendation does when tapped. The view resolves each into a concrete
/// action (a `router` launch, a tab switch, a pushed screen, or a lesson sheet) so this stays
/// UI-framework-light and easy to reason about / test.
enum TodayIntent: Equatable {
    /// Review the SRS cards that have come due, across every deck.
    case reviewDueCards
    /// Practice one shaky grammar structure (a multiple-choice drill when one exists for it,
    /// otherwise a 30-second mini-lesson from `GrammarFocus.explanation`).
    case grammar(GrammarFocus)
    /// A short conversation — the streak-keeper.
    case chat
    /// Turn the coach's remembered words / slip-ups into a drill deck.
    case buildDrillDeck
    /// Generate a fresh vocabulary deck.
    case generateDeck
    /// Pick up a flashcard session the learner paused mid-deck.
    case resumePausedDeck
    /// The Goethe word box: today's due reviews plus the new-word budget, in one session.
    case wortschatz
    /// The verb-pair review box (Verben mit Präpositionen), studied on its own verb cards.
    case verbReview
    /// A few lines in the Tagebuch, with today's prompt from the bank when there is one.
    case write(prompt: String?)
    /// A quick round of cards the learner already knows well (roadmap item 6, FSI lesson 7: vary
    /// the pace, give some tasks that are easy). Never touches the SRS schedule.
    case easyRound(count: Int)
    /// The course deck's due cards: this fortnight's class words (docs/CLASS_NOTES.md ▸ Today).
    case classWords(count: Int)
    /// Her review plan: a sent worksheet again, answers hidden (docs/WORKSHEETS.md ▸ Wiederholen).
    case worksheetRedo(materialID: UUID)
    /// The loop around a session (roadmap items 12, 13): prepare the day before, review the same day.
    case beforeClass(courseID: UUID)
    case afterClass(courseID: UUID)
}

/// One ordered item in the Today plan.
struct TodayRecommendation: Identifiable {
    let intent: TodayIntent
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color

    var id: String {
        switch intent {
        case .reviewDueCards:   return "review"
        case .grammar(let f):   return "grammar-\(f.rawValue)"
        case .chat:             return "chat"
        case .buildDrillDeck:   return "drill"
        case .generateDeck:     return "generate"
        case .resumePausedDeck: return "resume"
        case .wortschatz:       return "wortschatz"
        case .verbReview:       return "verbs"
        case .write:            return "write"
        case .easyRound:        return "easy"
        case .classWords:       return "class-words"
        case .worksheetRedo(let id): return "redo-\(id.uuidString)"
        case .beforeClass(let id): return "before-\(id.uuidString)"
        case .afterClass(let id): return "after-\(id.uuidString)"
        }
    }
}

/// The live facts the plan is built from — gathered by the view from its `@Query`s so the
/// planner itself is a pure function (same snapshot → same plan).
struct TodaySnapshot {
    var dueCardCount: Int
    /// Shaky grammar structures, worst-first (already thresholded).
    var weaknesses: [GrammarFocus]
    /// The coach has remembered words or slip-ups that could become a drill deck.
    var hasCoachContent: Bool
    var streak: Int
    var studiedToday: Bool
    /// Has the learner ever done anything (studied, chatted, or made a deck)? Drives cold-start.
    var hasStartedLearning: Bool
    /// A day-of-year index used to rotate/interleave which weak spot is surfaced, so the plan
    /// isn't the identical three items every day.
    var dayIndex: Int
    /// An in-progress (paused) flashcard session to offer resuming, if any.
    var resume: ResumeInfo? = nil
    /// What the Goethe box has waiting today, once the learner has opened it at all.
    var wortschatz: WortschatzInfo? = nil
    /// Verb pairs that have come due in their review box. Only scheduled ones: the plan never
    /// offers the 42 new pairs to someone who hasn't opened the box.
    var verbDue: Int = 0
    /// The Schreiben room's state. Nil when the view did not look.
    var writing: WritingInfo? = nil
    /// Cards known well (a high Leitner box or a long interval) and not due: an easy round's pool.
    var knownCardCount: Int = 0
    /// Today's last scored session went badly (under 60% right first time).
    var hardSessionToday: Bool = false

    /// Due cards on the deck of a course with a class in the last fortnight.
    var classWordsDue: Int = 0
    var classCourseName: String? = nil
    /// Grammar the class pointed at: checked worksheet mistakes first, then what an entry covered.
    var classFocus: ClassFocusInfo? = nil
    /// A sent worksheet her review plan brings back today.
    var worksheetRedo: WorksheetRedoInfo? = nil
    /// A class today to review, or tomorrow to prepare for.
    var classSession: ClassSessionInfo? = nil

    struct ClassSessionInfo: Equatable {
        enum Moment: Equatable { case before, after }
        var courseID: UUID
        var courseName: String
        var moment: Moment
        /// "No entry yet", "3 questions for her", …
        var detail: String
    }

    struct ClassFocusInfo: Equatable {
        var focus: GrammarFocus
        var reason: String
    }

    struct WorksheetRedoInfo: Equatable {
        var materialID: UUID
        var title: String
        /// 0 = the next day, 1 = a week later.
        var step: Int
    }

    /// The minimum pool for an easy round.
    static let easyRoundMinimum = 8

    struct WritingInfo {
        var wroteToday: Bool
        /// Days since the newest entry; nil when the learner has never written.
        var daysSinceLastEntry: Int?
        /// Today's Tagebuch prompt from the bank, at the learner's level.
        var prompt: String?
    }

    struct ResumeInfo: Equatable {
        var topic: String
        var cardIndex: Int
        var cardCount: Int
    }

    struct WortschatzInfo: Equatable {
        var due: Int
        var new: Int
        var todo: Int { due + new }
    }
}

/// Builds the short, ordered "here's the one next thing" plan from a snapshot of the learner's
/// state. Deliberately opinionated and capped — the whole point is to *remove* the decision.
enum TodayPlanner {

    static func plan(_ s: TodaySnapshot) -> [TodayRecommendation] {
        // Cold start: don't invent SRS/grammar work the learner hasn't generated yet.
        guard s.hasStartedLearning else {
            return [generate(cold: true), chat(streak: s.streak, studiedToday: s.studiedToday)]
        }

        var recs: [TodayRecommendation] = []

        // 0. Resume an unfinished session first — the learner was literally mid-deck.
        if let resume = s.resume {
            recs.append(resumeRec(resume))
        }

        // 0a. The loop around a class: review today's, or prepare tomorrow's.
        if let session = s.classSession {
            recs.append(classSession(session))
        }

        // 0b. Her review plan: a sent worksheet again, on the day it's due.
        if let redo = s.worksheetRedo {
            recs.append(worksheetRedo(redo))
        }

        // 1. Clear the spaced-repetition backlog first — it's time-sensitive by design. The
        //    Goethe box keeps its own step: its due words are not in `dueCardCount`.
        if let w = s.wortschatz, w.todo > 0 {
            recs.append(wortschatz(w))
        }
        // The verb pairs keep their own step too: they review on their own cards (the generic
        // review would show the answer on the card's face), so they are not in `dueCardCount`.
        if s.verbDue > 0 {
            recs.append(verbReview(count: s.verbDue))
        }
        // This fortnight's class words, apart from the general review so the class reads as its own.
        if s.classWordsDue > 0 {
            recs.append(classWords(count: s.classWordsDue, course: s.classCourseName))
        }
        if s.dueCardCount > 0 {
            recs.append(review(count: s.dueCardCount))
        } else if s.hasCoachContent, s.wortschatz?.todo ?? 0 == 0 {
            // Nothing due, but there's remembered material worth turning into review.
            recs.append(drill())
        }

        // 2. Target a weak spot, rotating through the shaky ones for interleaving.
        //    The class's grammar comes first: what she just taught, or what her worksheet caught.
        if let fromClass = s.classFocus {
            recs.append(classGrammar(fromClass))
        } else if !s.weaknesses.isEmpty {
            let focus = s.weaknesses[s.dayIndex % s.weaknesses.count]
            recs.append(grammar(focus))
        }

        // 2a. An easy round after a hard session, or when the plan would be all weak spots: some
        //     tasks should be easy (FSI lesson 7). Only with enough well-known cards to fill one.
        if s.knownCardCount >= TodaySnapshot.easyRoundMinimum, s.hardSessionToday || s.weaknesses.count >= 2 {
            recs.append(easyRound(count: min(10, s.knownCardCount), afterHard: s.hardSessionToday))
        }

        // 2b. A few lines in the journal: every day once the habit has lapsed three days, else
        //     every third day as a nudge. Never when today's page already exists.
        if let w = s.writing, !w.wroteToday, (w.daysSinceLastEntry ?? 99) >= 3 || s.dayIndex % 3 == 0 {
            recs.append(write(w))
        }

        // 3. Keep (or kindle) the streak with a short chat — always on the plan.
        recs.append(chat(streak: s.streak, studiedToday: s.studiedToday))

        // Never leave a returning learner with a single lonely item.
        if recs.count < 2 {
            recs.append(generate(cold: false))
        }

        return Array(recs.prefix(3))
    }

    // MARK: - Builders

    private static func review(count: Int) -> TodayRecommendation {
        let minutes = max(1, Int((Double(count) * 7.0 / 60.0).rounded()))
        return TodayRecommendation(
            intent: .reviewDueCards,
            title: "Review \(count) due card\(count == 1 ? "" : "s")",
            subtitle: "Spaced repetition · ~\(minutes) min",
            systemImage: "rectangle.stack.badge.play.fill",
            accent: .blue
        )
    }

    private static func classSession(_ c: TodaySnapshot.ClassSessionInfo) -> TodayRecommendation {
        switch c.moment {
        case .before:
            return TodayRecommendation(intent: .beforeClass(courseID: c.courseID),
                                       title: "Vor der Stunde · \(c.courseName) tomorrow",
                                       subtitle: c.detail, systemImage: "sunrise.fill", accent: .brown)
        case .after:
            return TodayRecommendation(intent: .afterClass(courseID: c.courseID),
                                       title: "Nach der Stunde · \(c.courseName)",
                                       subtitle: c.detail, systemImage: "moon.stars.fill", accent: .brown)
        }
    }

    private static func worksheetRedo(_ r: TodaySnapshot.WorksheetRedoInfo) -> TodayRecommendation {
        TodayRecommendation(
            intent: .worksheetRedo(materialID: r.materialID),
            title: "Wiederholen · \(r.title)",
            subtitle: r.step == 0 ? "Her review plan: again the next day, answers hidden" : "Her review plan: again a week later, answers hidden",
            systemImage: "arrow.counterclockwise.circle.fill",
            accent: .brown
        )
    }

    private static func classWords(count: Int, course: String?) -> TodayRecommendation {
        TodayRecommendation(
            intent: .classWords(count: count),
            title: "Kurs · \(count) class word\(count == 1 ? "" : "s") due",
            subtitle: (course.map { "\($0) · " } ?? "") + "Spaced repetition",
            systemImage: "graduationcap.fill",
            accent: .brown
        )
    }

    private static func classGrammar(_ c: TodaySnapshot.ClassFocusInfo) -> TodayRecommendation {
        TodayRecommendation(
            intent: .grammar(c.focus),
            title: "\(c.focus.germanLabel) practice",
            subtitle: c.reason,
            systemImage: "graduationcap",
            accent: .brown
        )
    }

    private static func easyRound(count: Int, afterHard: Bool) -> TodayRecommendation {
        TodayRecommendation(
            intent: .easyRound(count: count),
            title: "Leichte Runde · \(count) cards you know",
            subtitle: afterHard ? "After a hard session · ~2 min, nothing rescheduled" : "A quick, easy round · ~2 min",
            systemImage: "leaf.fill",
            accent: .green
        )
    }

    private static func verbReview(count: Int) -> TodayRecommendation {
        let minutes = max(1, Int((Double(count) * 10.0 / 60.0).rounded()))
        return TodayRecommendation(
            intent: .verbReview,
            title: "Verben · \(count) due",
            subtitle: "Verbs with prepositions · ~\(minutes) min",
            systemImage: "link",
            // Blue like the generic review: teal is the Dativ's color, and this row is not Dativ.
            accent: .blue
        )
    }

    private static func wortschatz(_ w: TodaySnapshot.WortschatzInfo) -> TodayRecommendation {
        let minutes = max(1, Int((Double(w.todo) * 7.0 / 60.0).rounded()))
        let title = w.due > 0
            ? "Wortschatz · \(w.due) due" + (w.new > 0 ? " + \(w.new) new" : "")
            : "Wortschatz · \(w.new) new word\(w.new == 1 ? "" : "s")"
        return TodayRecommendation(
            intent: .wortschatz,
            title: title,
            subtitle: "Goethe A1–B1 · ~\(minutes) min",
            systemImage: "archivebox.fill",
            accent: .indigo
        )
    }

    private static func write(_ w: TodaySnapshot.WritingInfo) -> TodayRecommendation {
        TodayRecommendation(
            intent: .write(prompt: w.prompt),
            title: (w.daysSinceLastEntry ?? 0) >= 3 ? "Schreib wieder ein paar Zeilen" : "Schreib ein paar Zeilen",
            subtitle: w.prompt ?? "Tagebuch · ~5 min, German, English or both",
            systemImage: SchreibenTile.systemImage,
            accent: SchreibenTile.tint
        )
    }

    private static func grammar(_ focus: GrammarFocus) -> TodayRecommendation {
        TodayRecommendation(
            intent: .grammar(focus),
            title: "\(focus.germanLabel) practice",
            subtitle: "\(focus.englishLabel) · a recurring weak spot",
            systemImage: "checklist",
            accent: .orange
        )
    }

    private static func chat(streak: Int, studiedToday: Bool) -> TodayRecommendation {
        let title: String
        let subtitle: String
        if streak <= 0 {
            title = "Start a streak today"
            subtitle = "A short chat gets you going"
        } else if studiedToday {
            title = "Keep the momentum going"
            subtitle = "A 5-min chat · 🔥 \(streak)-day streak"
        } else {
            title = "Keep your \(streak)-day streak"
            subtitle = "A 5-min chat keeps 🔥 \(streak) alive"
        }
        return TodayRecommendation(
            intent: .chat,
            title: title,
            subtitle: subtitle,
            systemImage: "bubble.left.and.bubble.right.fill",
            accent: .green
        )
    }

    private static func drill() -> TodayRecommendation {
        TodayRecommendation(
            intent: .buildDrillDeck,
            title: "Build a drill deck",
            subtitle: "Your words & slip-ups → flashcards",
            systemImage: "rectangle.stack.badge.plus",
            accent: .purple
        )
    }

    private static func generate(cold: Bool) -> TodayRecommendation {
        TodayRecommendation(
            intent: .generateDeck,
            title: cold ? "Create your first deck" : "Generate flashcards",
            subtitle: "AI vocabulary on any topic",
            systemImage: "sparkles",
            accent: .pink
        )
    }

    private static func resumeRec(_ r: TodaySnapshot.ResumeInfo) -> TodayRecommendation {
        TodayRecommendation(
            intent: .resumePausedDeck,
            title: "Resume \(r.topic)",
            subtitle: "Card \(r.cardIndex + 1) of \(r.cardCount) · pick up where you left off",
            systemImage: "play.circle.fill",
            accent: .teal
        )
    }
}
