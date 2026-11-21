//
//  GrammarProgress.swift
//  german-ai-flashcards
//
//  One pass over every grammar round, for the Grammatik hub's Fortschritt pane: time and
//  accuracy per day, per exercise and per case. A pure value type — it takes the three round
//  arrays and returns numbers, so it is testable without a store and holds no view state.
//
//  Why the rounds and not `StudyDay.grammarSeconds`, which looks like the obvious source:
//    · `VerbPrepositionReviewView` logs its time as `.cards`, so verb-preposition review lands
//      in `cardSeconds` and would be missing here.
//    · `StudyTimeBackfillService` only ever backfilled `QuizResult` and `ArticleRound`, never
//      `KasusRound` or `PrepositionRound`, so every day before time tracking shipped reads zero
//      for exactly the exercises this pane is about — and it writes `max(existing, backfilled)`,
//      so it can never correct an over-count either.
//  `durationSeconds` is on all three round models and a read lesson persists a `KasusRound`
//  carrying its seconds, so the rounds are complete where the day log is not. The consequence,
//  stated on the pane itself: these totals can differ slightly from Home's grammar time.
//
//  Two keying rules the exercise id exists to enforce:
//    · Group on (step, topic), never the step alone — `unitRaw` holds a `GrammarTopic.key`, and
//      the step enum carries no topic, so `quick` files as `quick-nominativ`, `quick-dativ`, …
//      Keying on `stepRaw` would fold all five units' Schnellrunden into one row.
//    · Never on `storyID`: „Markieren · Dativ“ is one row across every Dativ story, and
//      `roundID(topicKey:)` returns "" for the two story steps, so it would collapse them all
//      into one empty bucket.
//

import Foundation

/// How an exercise is identified across rounds.
nonisolated enum GrammarExerciseID: Hashable {
    /// A `KasusRound` exercise: the step it recorded as, in the topic it was played in.
    case kasus(stepRaw: String, topicKey: String)
    /// A drill that keeps its own round model and no exercise identity, so the family is the row.
    case family(GrammarDrillFamily)
}

struct GrammarProgress {

    /// What one day holds. Days with nothing are absent, not zero.
    struct DayTotals {
        var seconds = 0
        var rounds = 0
        var answers = 0
    }

    /// One row of „Zeit pro Übung“.
    struct ExerciseTotals: Identifiable {
        let id: GrammarExerciseID
        var rounds = 0
        var answers = 0
        var firstTry = 0
        var seconds = 0
        var lastPlayed: Date

        /// Nil when nothing was asked — a read lesson — so no surface can print a fake „0 %“.
        var firstTryPercent: Int? {
            guard answers > 0 else { return nil }
            return Int((Double(firstTry) / Double(answers) * 100).rounded())
        }
    }

    /// Keyed on local midnight.
    let days: [Date: DayTotals]
    /// Most time first, then most recently played. Only exercises actually played appear.
    let exercises: [ExerciseTotals]
    /// The case path only: a reflexive pick (sich, uns, euch) can't demonstrate a case, which is
    /// the same rule Verlauf's all-time strip applies.
    let perCase: [GrammarCase: KasusRound.CaseTally]

    let rounds: Int
    let answers: Int
    let firstTry: Int
    let totalSeconds: Int

    /// `kasus` is filtered on `countsAsStudy` here, not by the caller: a read lesson counts as
    /// grammar time, the DEBUG verify rounds count as nothing.
    init(kasus: [KasusRound], articles: [ArticleRound], prepositions: [PrepositionRound],
         calendar: Calendar = .current) {
        var days: [Date: DayTotals] = [:]
        var exercises: [GrammarExerciseID: ExerciseTotals] = [:]
        var perCase: [GrammarCase: KasusRound.CaseTally] = [:]
        var rounds = 0, answers = 0, firstTry = 0, totalSeconds = 0

        func add(day date: Date, seconds: Int, answers: Int) {
            let key = calendar.startOfDay(for: date)
            var totals = days[key] ?? DayTotals()
            totals.seconds += seconds
            totals.rounds += 1
            totals.answers += answers
            days[key] = totals
        }

        func add(_ id: GrammarExerciseID, date: Date, asked: Int, right: Int, seconds: Int) {
            var totals = exercises[id] ?? ExerciseTotals(id: id, lastPlayed: date)
            totals.rounds += 1
            totals.answers += asked
            totals.firstTry += right
            totals.seconds += seconds
            totals.lastPlayed = max(totals.lastPlayed, date)
            exercises[id] = totals

            rounds += 1
            answers += asked
            firstTry += right
            totalSeconds += seconds
            add(day: date, seconds: seconds, answers: asked)
        }

        for round in kasus where round.countsAsStudy {
            add(.kasus(stepRaw: round.stepRaw, topicKey: round.unitRaw),
                date: round.date,
                asked: round.askedCount,
                // A Markieren round scores in class-sheet points, the way its row does.
                right: round.markScore?.points ?? round.firstTryCount,
                seconds: round.durationSeconds)

            // Reflexive rounds bank their time and answers above but never the case bars.
            guard round.unit != nil else { continue }
            for (kasus, tally) in round.perCase {
                perCase[kasus, default: .init()].asked += tally.asked
                perCase[kasus, default: .init()].firstTry += tally.firstTry
            }
        }

        for round in articles {
            add(.family(.article), date: round.date, asked: round.questionCount,
                right: round.firstTryCount, seconds: round.durationSeconds)
        }

        for round in prepositions {
            add(.family(.preposition), date: round.date, asked: round.questionCount,
                right: round.firstTryCount, seconds: round.durationSeconds)
        }

        self.days = days
        self.exercises = exercises.values.sorted {
            $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.lastPlayed > $1.lastPlayed
        }
        self.perCase = perCase
        self.rounds = rounds
        self.answers = answers
        self.firstTry = firstTry
        self.totalSeconds = totalSeconds
    }

    /// Days that hold anything at all.
    var activeDays: Int { days.count }

    /// Home's own measure type, shaded by time, so the grammar heat grid and the Home one read
    /// off one ramp (`StreakShade`) and can never drift apart.
    func dayMetrics() -> DayMetrics {
        DayMetrics(items: days.mapValues(\.answers), seconds: days.mapValues(\.seconds), byTime: true)
    }
}
