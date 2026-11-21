//
//  ClassCourse.swift
//  german-ai-flashcards
//
//  A German course the learner is taking outside the app: a semester course at a university, a
//  private tutor, a Volkshochschule evening class, or a self-study plan. The course is the unit that
//  owns everything the class produces (dated entries, handouts, homework) and one accumulating
//  flashcard deck, because that is how a learner thinks about it: "my uni course" and "my HR
//  German tutor" are two different things with two different vocabularies and rhythms. A dated
//  course (start and end) labels its entries by week; an undated one is just a string of sessions.
//
//  Every property is defaulted or set in `init` so the entity is an additive migration (the app's
//  container deletes the store when a migration fails).
//

import Foundation
import SwiftData

@Model
final class ClassCourse {
    var id: UUID
    var createdAt: Date
    /// Bumped whenever an entry or handout lands, so the hub lists the course being worked on first.
    var updatedAt: Date
    var name: String
    /// Raw `Kind`.
    var kindRaw: String = "course"
    /// The teacher or tutor, as the learner wants them named.
    var teacher: String? = nil
    /// The teacher's email, for the one-tap "write to" on the course page.
    var teacherEmail: String? = nil
    /// The course's page online (Moodle, Canvas, the tutor's booking site), as typed.
    var courseURL: String? = nil
    /// What the course is for, in the learner's words ("HR German for job applications").
    var goal: String? = nil
    /// Raw `CEFRLevel` the course is pitched at, when the learner knows it.
    var levelRaw: String? = nil
    /// A semester has dates; a tutor usually does not.
    var startDate: Date? = nil
    var endDate: Date? = nil
    /// Finished courses stay for their notes and deck, but leave the hub's front page.
    var isArchived: Bool = false
    /// The course's one flashcard deck (`SavedDeck.id`), created on the first word saved.
    var deckIDRaw: String? = nil
    var sortOrder: Int = 0
    /// When it meets (roadmap item 12): `Calendar` weekdays (1 = Sunday … 7 = Saturday), comma
    /// separated. Empty for a course with no fixed slot.
    var meetingWeekdaysRaw: String = ""
    /// Start time in minutes after midnight, or -1 when not set.
    var meetingMinutes: Int = -1
    /// A tutor's next lesson, when it isn't weekly. Wins over the weekdays when it is sooner.
    var nextSessionAt: Date? = nil
    /// Encoded `[String: ClassQuestion]` by id: questions parked for the teacher (item 14).
    var questionsData: Data? = nil

    @Relationship(deleteRule: .cascade, inverse: \ClassEntry.course)
    var entries: [ClassEntry] = []

    init(name: String, kind: Kind = .course, createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.name = name
        self.kindRaw = kind.rawValue
    }

    enum Kind: String, CaseIterable, Identifiable {
        case course, tutor, selfStudy

        var id: String { rawValue }

        var label: String {
            switch self {
            case .course:    "Course"
            case .tutor:     "Private tutor"
            case .selfStudy: "On my own"
            }
        }

        var systemImage: String {
            switch self {
            case .course:    "person.3.fill"
            case .tutor:     "person.fill"
            case .selfStudy: "book.closed.fill"
            }
        }

        /// One line under the picker in the course editor.
        var blurb: String {
            switch self {
            case .course:    "A class with a term: a university semester or quarter, a Volkshochschule or Goethe-Institut course."
            case .tutor:     "One-to-one sessions, usually built around a goal rather than a syllabus."
            case .selfStudy: "A textbook or a plan you follow yourself."
            }
        }
    }

    // MARK: Derived

    var kind: Kind { Kind(rawValue: kindRaw) ?? .course }

    var level: CEFRLevel? {
        get { levelRaw.flatMap { CEFRLevel(rawValue: $0) } }
        set { levelRaw = newValue?.rawValue }
    }

    var deckID: UUID? {
        get { deckIDRaw.flatMap { UUID(uuidString: $0) } }
        set { deckIDRaw = newValue?.uuidString }
    }

    /// "Private tutor · HR German for job applications", whichever parts are filled in.
    var subtitleLine: String {
        var parts = [kind.label]
        if let teacher = trimmed(teacher) { parts.append(teacher) }
        else if let goal = trimmed(goal) { parts.append(goal) }
        return parts.joined(separator: " · ")
    }

    var isDated: Bool { startDate != nil }

    /// The course page as a link, "https://" assumed when the learner typed none.
    var pageURL: URL? {
        guard let raw = trimmed(courseURL) else { return nil }
        let withScheme = raw.contains("://") ? raw : "https://" + raw
        return URL(string: withScheme)
    }

    /// "mailto:" for the teacher, when an email is on file.
    var teacherMailURL: URL? {
        guard let email = trimmed(teacherEmail), email.contains("@") else { return nil }
        return URL(string: "mailto:" + email)
    }

    /// The 1-based week of the course a date falls in, counted from the start of the week that
    /// holds `startDate`. Nil for an undated course, or for a date before it began.
    func weekNumber(for date: Date) -> Int? {
        guard let startDate else { return nil }
        return Self.weekNumber(of: date, start: startDate, calendar: .current)
    }

    /// How many weeks the course runs, when both dates are set.
    var totalWeeks: Int? {
        guard let endDate, let start = startDate, endDate >= start else { return nil }
        return weekNumber(for: endDate)
    }

    /// The week of a course starting on `start` that `date` falls in, counted from the start of the
    /// calendar week that holds `start`. Nil before the course began.
    nonisolated static func weekNumber(of date: Date, start: Date, calendar: Calendar) -> Int? {
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start
            ?? calendar.startOfDay(for: start)
        let days = calendar.dateComponents([.day], from: firstWeek, to: calendar.startOfDay(for: date)).day ?? 0
        guard days >= 0 else { return nil }
        return days / 7 + 1
    }

    /// The end date that makes a course starting on `start` run `weeks` weeks: the last day of its
    /// `weeks`-th calendar week. The exact inverse of `weeks(start:end:calendar:)`; counting from
    /// `start` itself instead would make a course that starts mid-week one week too long.
    nonisolated static func endDate(start: Date, weeks: Int, calendar: Calendar) -> Date {
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start
            ?? calendar.startOfDay(for: start)
        let lastDay = calendar.date(byAdding: .day, value: max(1, weeks) * 7 - 1, to: firstWeek) ?? start
        return max(calendar.startOfDay(for: lastDay), calendar.startOfDay(for: start))
    }

    /// How many weeks a course from `start` to `end` runs, by the same count as `totalWeeks`.
    nonisolated static func weeks(start: Date, end: Date, calendar: Calendar) -> Int {
        max(1, weekNumber(of: max(end, start), start: start, calendar: calendar) ?? 1)
    }

    /// "Woche 7 von 20" for a dated course that is running, "Woche 7" without an end date,
    /// nil otherwise.
    var currentWeekLabel: String? {
        guard let week = weekNumber(for: .now) else { return nil }
        if let totalWeeks {
            guard week <= totalWeeks else { return "Finished" }
            return "Woche \(week) von \(totalWeeks)"
        }
        return "Woche \(week)"
    }

    var sortedEntries: [ClassEntry] {
        entries.sorted { $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date }
    }

    /// Entries with homework still to do, soonest due first (undated last).
    var openHomework: [ClassEntry] {
        entries.filter(\.hasOpenHomework).sorted(by: ClassCourse.homeworkOrder)
    }

    /// Soonest due first; undated homework after every dated one, newest class first.
    static func homeworkOrder(_ lhs: ClassEntry, _ rhs: ClassEntry) -> Bool {
        let far = Date.distantFuture
        let left: Date = lhs.homeworkDue ?? far
        let right: Date = rhs.homeworkDue ?? far
        if left != right { return left < right }
        return lhs.date > rhs.date
    }

    /// Every handout across the course's entries, newest first.
    var materials: [ClassMaterial] {
        entries.flatMap(\.materials).sorted { $0.createdAt > $1.createdAt }
    }

    private func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
