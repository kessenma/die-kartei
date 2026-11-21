//
//  ClassLoop.swift
//  german-ai-flashcards
//
//  The loop around each class or tutor session (docs/CLASS_NOTES.md ▸ The loop around a session,
//  roadmap section E): when the course meets, the questions parked for the teacher, what the
//  learner recalled afterwards, and what the teacher corrected.
//

import Foundation

/// A question for the teacher, parked on the course until the next session (roadmap item 14).
nonisolated struct ClassQuestion: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var text: String
    /// Where it came from ("Wörterbuch · Gleis", "Gespräch", "Übung Dativ D1"), for the list.
    var context: String = ""
    var createdAt: Date = .now
    /// Set when ticked off.
    var answer: String? = nil
    var answeredAt: Date? = nil
    /// The entry the answer was written into.
    var entryID: UUID? = nil
    var deleted: Bool = false
    /// Last edit: questions merge per id across devices, the later edit winning.
    var at: Date = .now

    var isOpen: Bool { answeredAt == nil && !deleted }
}

/// What I said, what she said instead (roadmap item 17). Confirmed by a teacher, so it is a slip
/// the coach can trust and a card worth keeping.
nonisolated struct TeacherCorrection: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var said: String
    var better: String
    var note: String = ""
    var at: Date = .now
}

/// When a course meets, from its weekdays and optional time, or a tutor's next date.
nonisolated enum ClassSchedule {

    static func weekdays(_ raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...7).contains($0) })
    }

    static func raw(_ weekdays: Set<Int>) -> String {
        weekdays.sorted().map(String.init).joined(separator: ",")
    }

    /// The next session day on or after `from`'s day, or nil when the course has no schedule.
    /// A one-off date wins when it comes first; a past one-off date is ignored.
    static func nextSessionDay(weekdaysRaw: String, oneOff: Date?, from: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: from)
        var candidates: [Date] = []
        if let oneOff {
            let day = calendar.startOfDay(for: oneOff)
            if day >= today { candidates.append(day) }
        }
        let days = weekdays(weekdaysRaw)
        if !days.isEmpty {
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                if days.contains(calendar.component(.weekday, from: day)) { candidates.append(day); break }
            }
        }
        return candidates.min()
    }

    /// The most recent session day before `from`'s day (by the weekdays), for "since the last
    /// session". Nil without a schedule.
    static func previousSessionDay(weekdaysRaw: String, from: Date, calendar: Calendar = .current) -> Date? {
        let days = weekdays(weekdaysRaw)
        guard !days.isEmpty else { return nil }
        let today = calendar.startOfDay(for: from)
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if days.contains(calendar.component(.weekday, from: day)) { return day }
        }
        return nil
    }

    static func timeLabel(minutes: Int) -> String? {
        guard minutes >= 0 else { return nil }
        return String(format: "%02ld:%02ld", minutes / 60, minutes % 60)
    }
}

extension ClassCourse {
    var meetingWeekdays: Set<Int> {
        get { ClassSchedule.weekdays(meetingWeekdaysRaw) }
        set { meetingWeekdaysRaw = ClassSchedule.raw(newValue) }
    }

    var hasSchedule: Bool { !meetingWeekdaysRaw.isEmpty || nextSessionAt != nil }

    func nextSessionDay(from: Date = .now) -> Date? {
        ClassSchedule.nextSessionDay(weekdaysRaw: meetingWeekdaysRaw, oneOff: nextSessionAt, from: from)
    }

    /// Meets today.
    func meetsToday(_ now: Date = .now) -> Bool {
        nextSessionDay(from: now) == Calendar.current.startOfDay(for: now)
    }

    /// Meets tomorrow.
    func meetsTomorrow(_ now: Date = .now) -> Bool {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) else { return false }
        return nextSessionDay(from: tomorrow) == tomorrow
    }

    var questions: [ClassQuestion] {
        get {
            let dict = (questionsData.flatMap { try? JSONDecoder().decode([String: ClassQuestion].self, from: $0) }) ?? [:]
            return dict.values.filter { !$0.deleted }.sorted { $0.createdAt < $1.createdAt }
        }
    }

    var openQuestions: [ClassQuestion] { questions.filter(\.isOpen) }

    /// Adds or replaces one question; a delete is kept as a tombstone so it syncs.
    func upsert(_ question: ClassQuestion) {
        var dict = (questionsData.flatMap { try? JSONDecoder().decode([String: ClassQuestion].self, from: $0) }) ?? [:]
        var q = question
        q.at = .now
        dict[q.id] = q
        questionsData = try? JSONEncoder().encode(dict)
        updatedAt = .now
    }

    /// The entry for a given day, if one exists.
    func entry(on day: Date) -> ClassEntry? {
        let start = Calendar.current.startOfDay(for: day)
        return entries.first { Calendar.current.startOfDay(for: $0.date) == start }
    }
}

extension ClassEntry {
    var recall: [String] {
        get { recallData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
        set { recallData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var teacherCorrections: [TeacherCorrection] {
        get { teacherCorrectionsData.flatMap { try? JSONDecoder().decode([TeacherCorrection].self, from: $0) } ?? [] }
        set { teacherCorrectionsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
}
