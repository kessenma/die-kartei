import Foundation

// The study-day log's rules, shared by iOS (`StudyDay`, a SwiftData row, through
// `StudyLogService`) and Android (`StudyDayRecord` in the record store): what one finished
// activity adds to the day, when a day counts as studied, the streak, time totals and the
// Wortschatz new-word budget. Fields are named as in the sync payload
// (`SyncKinds.studyDayCounterFields`), so both apps count the same thing into the same counter.

/// One thing the learner just finished — the unit recorded into the per-day `StudyDay` log.
nonisolated enum StudyActivity {
    case cards(Int)             // n flashcards reviewed
    case grammar(Int)           // n grammar exercises answered
    case conversation           // one chat finished
    case storyReading(Int)      // n seconds spent reading/listening to a story
    case storyQuestions(Int)    // n story comprehension questions answered
    case games(Int)             // n words solved in the Spiele room
    case drawing(Int)           // n words drawn in the Zeichnen room
    case writing(Int)           // n words written in the Schreiben room
    case sheetWords(Int)        // n words on a Schreibblatt sheet just marked Fertig
    case hoeren(Int)            // n items heard and answered in the Hören room

    /// Which time bucket this activity's seconds belong to.
    var timeBucket: StudyTimeBucket {
        switch self {
        case .cards:          return .cards
        case .grammar:        return .grammar
        case .conversation:   return .conversation
        case .storyReading:   return .storyReading
        case .storyQuestions: return .storyQuiz
        case .games:          return .games
        case .drawing:        return .drawing
        case .writing:        return .writing
        // Nothing times a sheet yet; were it to, by-hand writing is writing.
        case .sheetWords:     return .writing
        case .hoeren:         return .hoeren
        }
    }

    /// The counter the activity's count goes into, and how much.
    var tally: (field: String, amount: Int) {
        switch self {
        case .cards(let n):          return ("cardsReviewed", max(0, n))
        case .grammar(let n):        return ("grammarExercises", max(0, n))
        case .conversation:          return ("conversations", 1)
        case .storyReading(let s):   return ("storySeconds", max(0, s))
        case .storyQuestions(let n): return ("storyQuestions", max(0, n))
        case .games(let n):          return ("gameWordsSolved", max(0, n))
        case .drawing(let n):        return ("wordsDrawn", max(0, n))
        case .writing(let n):        return ("wordsWritten", max(0, n))
        case .sheetWords(let n):     return ("sheetWordsWritten", max(0, n))
        case .hoeren(let n):         return ("hoerenItems", max(0, n))
        }
    }
}

/// The time-on-task buckets a day is split into. Kept separate from `StudyActivity` because time
/// can accrue without anything being *finished* — a conversation drips seconds into the day while
/// it's still running.
nonisolated enum StudyTimeBucket: CaseIterable {
    case cards, grammar, conversation, storyReading, storyQuiz, games, drawing, writing, hoeren

    /// The day's seconds counter for this bucket.
    var secondsField: String {
        switch self {
        case .cards:        return "cardSeconds"
        case .grammar:      return "grammarSeconds"
        case .conversation: return "conversationSeconds"
        case .storyReading: return "storySeconds"
        case .storyQuiz:    return "storyQuizSeconds"
        case .games:        return "gameSeconds"
        case .drawing:      return "drawingSeconds"
        case .writing:      return "writingSeconds"
        case .hoeren:       return "hoerenSeconds"
        }
    }
}

/// What gets added to a day, as counter increments by field name.
nonisolated enum StudyDayTally {
    /// Time only counts as a study day once it passes a minute — a ten-second glance at a story
    /// shouldn't keep a streak alive, but a real read with no questions answered should.
    static let streakSeconds = 60

    /// The counts that make a day active on their own. The new-word fields never do: asking for
    /// ten more words is not studying.
    static let activityFields = ["cardsReviewed", "grammarExercises", "conversations", "storyQuestions",
                                 "gameWordsSolved", "wordsDrawn", "wordsWritten", "sheetWordsWritten",
                                 "hoerenItems"]

    static let secondsFields = StudyTimeBucket.allCases.map(\.secondsField)

    /// One finished activity. `seconds` is how long it took, banked into the activity's time
    /// bucket; `.storyReading` carries its own seconds (they *are* its count) and ignores it.
    static func increments(for activity: StudyActivity, seconds: Int = 0) -> [String: Int] {
        let (field, amount) = activity.tally
        var out = [field: amount]
        if case .storyReading = activity {} else if seconds > 0 {
            out[activity.timeBucket.secondsField, default: 0] += seconds
        }
        return out.filter { $0.value > 0 }
    }

    /// Time with nothing finished (the live drip from a chat).
    static func increments(time bucket: StudyTimeBucket, seconds: Int) -> [String: Int] {
        seconds > 0 ? [bucket.secondsField: seconds] : [:]
    }
}

/// A day's tallies, read the same way on both platforms.
nonisolated protocol StudyDayCounts {
    /// Local midnight of the day.
    var dayStart: Date { get }
    /// A counter by its payload name (`SyncKinds.studyDayCounterFields`); 0 when unset.
    func count(_ field: String) -> Int
}

nonisolated extension StudyDayCounts {
    /// Every second logged on the day, across all activities — the number the calendar totals.
    var totalSeconds: Int { StudyDayTally.secondsFields.reduce(0) { $0 + count($1) } }

    /// Did the learner do anything at all on this day?
    var hasActivity: Bool {
        StudyDayTally.activityFields.contains { count($0) > 0 } || totalSeconds >= StudyDayTally.streakSeconds
    }
}

/// Time on task over a date range, plus the context that makes the number mean something.
nonisolated struct StudyTimeSummary {
    var totalSeconds: Int
    var activeDays: Int
    /// Average over *active* days only — an average over 365 calendar days would read as zero
    /// for anyone with a normal life.
    var averageSeconds: Int { activeDays > 0 ? totalSeconds / activeDays : 0 }
    var hasTime: Bool { totalSeconds > 0 }
}

/// Reading the log: pure over an already-fetched set of days.
nonisolated enum StudyStreak {
    /// Did the learner study today?
    static func studiedToday<D: StudyDayCounts>(_ days: [D], asOf now: Date = Date(),
                                                calendar: Calendar = .current) -> Bool {
        studiedDays(days, calendar).contains(calendar.startOfDay(for: now))
    }

    /// The current streak: consecutive days with activity ending today. If today has no activity
    /// yet but yesterday did, the streak is still "alive" (counted from yesterday) so today's
    /// session can be framed as *keeping* it. Zero once a full day is missed.
    static func currentStreak<D: StudyDayCounts>(_ days: [D], asOf now: Date = Date(),
                                                 calendar cal: Calendar = .current) -> Int {
        let studied = studiedDays(days, cal)
        guard !studied.isEmpty else { return 0 }
        let today = cal.startOfDay(for: now)
        var cursor = today
        if !studied.contains(today) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                  studied.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while studied.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Sum the log over `start ..< end` (both expected at midnight).
    static func timeSummary<D: StudyDayCounts>(_ days: [D], from start: Date, to end: Date) -> StudyTimeSummary {
        var total = 0
        var active = 0
        for day in days where day.dayStart >= start && day.dayStart < end {
            guard day.hasActivity else { continue }
            active += 1
            total += day.totalSeconds
        }
        return StudyTimeSummary(totalSeconds: total, activeDays: active)
    }

    /// Today's introduced count and bonus.
    static func todayNewWords<D: StudyDayCounts>(_ days: [D], asOf now: Date = Date(),
                                                 calendar: Calendar = .current) -> (introduced: Int, bonus: Int) {
        let today = calendar.startOfDay(for: now)
        guard let day = days.first(where: { calendar.startOfDay(for: $0.dayStart) == today }) else { return (0, 0) }
        return (day.count("newWordsIntroduced"), day.count("newWordsBonus"))
    }

    /// New words still allowed today under `newPerDay`.
    static func newWordBudgetRemaining<D: StudyDayCounts>(_ days: [D], newPerDay: Int, asOf now: Date = Date(),
                                                          calendar: Calendar = .current) -> Int {
        let today = todayNewWords(days, asOf: now, calendar: calendar)
        return max(0, newPerDay + today.bonus - today.introduced)
    }

    private static func studiedDays<D: StudyDayCounts>(_ days: [D], _ cal: Calendar) -> Set<Date> {
        Set(days.filter(\.hasActivity).map { cal.startOfDay(for: $0.dayStart) })
    }
}

/// Android's day rows: the record keeps its counters by payload name already.
nonisolated extension StudyDayRecord: StudyDayCounts {
    var dayStart: Date { SyncDayKey.dayStart(for: day) ?? Date(timeIntervalSinceReferenceDate: 0) }
    func count(_ field: String) -> Int { self[field] }

    /// Fold increments into the day; `now` stamps `lastActivityAt` (iOS leaves it alone for the
    /// new-word counters, which aren't study).
    mutating func add(_ increments: [String: Int], at now: Date?) {
        for (field, n) in increments where n > 0 { self[field] += n }
        if let now { lastActivityAt = now }
    }
}
