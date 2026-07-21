import Foundation
import SwiftData

/// One "you haven't practiced in a while" checkpoint, measured from the learner's most recent
/// activity. Turning several on builds an escalating ladder — the gaps grow, so the reminders get
/// *less* frequent the longer someone's been away rather than nagging every day.
enum ReminderCheckpoint: String, CaseIterable, Identifiable, Comparable {
    case day
    case threeDays
    case week
    case twoWeeks
    case month

    var id: String { rawValue }

    /// How long after the last practice this checkpoint fires.
    var interval: TimeInterval {
        let day: TimeInterval = 24 * 60 * 60
        switch self {
        case .day:       return 1  * day
        case .threeDays: return 3  * day
        case .week:      return 7  * day
        case .twoWeeks:  return 14 * day
        case .month:     return 30 * day
        }
    }

    /// The Settings row label.
    var title: String {
        switch self {
        case .day:       return "1 day"
        case .threeDays: return "3 days"
        case .week:      return "1 week"
        case .twoWeeks:  return "2 weeks"
        case .month:     return "1 month"
        }
    }

    /// Stable identifier so rescheduling *replaces* (never duplicates) this checkpoint's reminder.
    var notificationID: String { "practice-reminder-\(rawValue)" }

    var notificationTitle: String {
        switch self {
        case .day, .threeDays: return "Time for some German?"
        case .week, .twoWeeks: return "Your German is waiting"
        case .month:           return "Ready for a fresh start?"
        }
    }

    var notificationBody: String {
        switch self {
        case .day:       return "A few cards today keeps everything fresh. Guten Tag!"
        case .threeDays: return "It's been a few days. Five quick minutes gets you back on track."
        case .week:      return "A week away? Pick up right where you left off."
        case .twoWeeks:  return "It's been two weeks. One short session brings it back fast."
        case .month:     return "It's been a month. No pressure, one small session is a great restart."
        }
    }

    static func < (lhs: ReminderCheckpoint, rhs: ReminderCheckpoint) -> Bool {
        lhs.interval < rhs.interval
    }
}

/// Schedules the learner's opt-in practice reminders. Each enabled `ReminderCheckpoint` becomes one
/// pending local notification timed from the last time they practiced *anything* (a card review,
/// grammar drill, or conversation — whatever's most recent in `StudyDay`). Rescheduling is
/// idempotent: it clears the whole set first, so calling it on every app foreground/background keeps
/// the ladder anchored to the real last-practice date. Practicing moves that date forward, which
/// moves every reminder forward, so an active learner never actually sees one.
enum PracticeReminderService {
    /// Reminders are nudged into this local-time window so one never buzzes overnight.
    private static let earliestHour = 9
    private static let latestHour = 21

    /// Re-derive the reminder ladder from the learner's current settings and last-practice date.
    @MainActor
    static func refresh(context: ModelContext, modelManager: MLXModelManager) async {
        await reschedule(
            lastActivity: latestActivityDate(in: context),
            enabled: modelManager.practiceRemindersEnabled,
            checkpoints: modelManager.practiceReminderCheckpoints
        )
    }

    static func reschedule(lastActivity: Date?, enabled: Bool, checkpoints: Set<ReminderCheckpoint>) async {
        // Always clear the full set first, so a disabled or edited config never leaves stragglers.
        LocalNotificationService.cancel(ids: ReminderCheckpoint.allCases.map(\.notificationID))
        guard enabled, !checkpoints.isEmpty else { return }

        // No practice history yet? Anchor the ladder to now so enabling reminders still does something.
        let baseline = lastActivity ?? Date()
        for checkpoint in checkpoints {
            let fireDate = daytimeAdjusted(baseline.addingTimeInterval(checkpoint.interval))
            await LocalNotificationService.schedule(
                id: checkpoint.notificationID,
                title: checkpoint.notificationTitle,
                body: checkpoint.notificationBody,
                at: fireDate
            )
        }
    }

    @MainActor
    private static func latestActivityDate(in context: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<StudyDay>(sortBy: [SortDescriptor(\.lastActivityAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.lastActivityAt
    }

    /// Shift a fire time into the `[earliestHour, latestHour)` window so reminders arrive during the
    /// day, never at 3am. It only ever moves a time *later* (to the morning), so a reminder never
    /// lands before its checkpoint has actually elapsed.
    private static func daytimeAdjusted(_ date: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        guard hour < earliestHour || hour >= latestHour else { return date }
        let base = hour >= latestHour ? (calendar.date(byAdding: .day, value: 1, to: date) ?? date) : date
        return calendar.date(bySettingHour: earliestHour, minute: 0, second: 0, of: base) ?? date
    }
}
