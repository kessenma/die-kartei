import Foundation
import UserNotifications

/// Thin wrapper over local notifications for long-running, background-friendly work (model
/// downloads, story generation). Posting is always gated on the user's authorization, and asking
/// for permission is idempotent — it only prompts the first time and never blocks the task itself.
enum LocalNotificationService {
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // The underlying task should never depend on notification permission.
        }
    }

    /// Post a notification immediately, if the user has authorized notifications. In the foreground
    /// iOS delivers it silently to Notification Center (there's no presentation delegate) — the point
    /// is the banner you get when the app is backgrounded during a slow task.
    static func post(id: String, title: String, body: String) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Schedule a notification to fire at a future `date`, if the user has authorized notifications.
    /// No-op when `date` isn't in the future. Re-adding the same `id` replaces any pending request
    /// with that id, so callers can safely reschedule without stacking duplicates.
    static func schedule(id: String, title: String, body: String, at date: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        else { return }

        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Remove pending (not-yet-delivered) notifications with these identifiers. Safe to call with
    /// ids that were never scheduled — unknown ids are ignored.
    static func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

/// Notifications for the on-device story generator — mirrors the model-download notifications so a
/// learner who backgrounds the app during the (slow, on-device) generation still hears when their
/// story is ready, or that it didn't finish.
enum StoryNotificationService {
    static func notifyReady(title: String) async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        await LocalNotificationService.post(
            id: "story-ready",
            title: "Your story is ready",
            body: name.isEmpty ? "Your German story finished generating." : "„\(name)“ is ready to read."
        )
    }

    static func notifyFailed() async {
        await LocalNotificationService.post(
            id: "story-failed",
            title: "Story generation stopped",
            body: "Something went wrong while writing your story. Open the app to try again."
        )
    }
}

/// One summary notification when a batch-queue run ends, instead of a ping per job — the whole
/// point of the queue is walking away (or sleeping) through several generations.
enum BatchNotificationService {
    static func notifyFinished(done: Int, failed: Int) async {
        guard done + failed > 0 else { return }
        let title: String
        let body: String
        if failed == 0 {
            title = "Your batch queue is finished"
            body = done == 1
                ? "1 job finished. Everything is waiting in your Library."
                : "\(done) jobs finished. Everything is waiting in your Library."
        } else {
            title = "Your batch queue finished with problems"
            body = "\(done) job\(done == 1 ? "" : "s") finished, \(failed) didn't. Open the queue to see details."
        }
        await LocalNotificationService.post(id: "batch-queue-finished", title: title, body: body)
    }
}

/// Notification for a finished deck-illustration run, so a learner who backgrounded the app while
/// their flashcards were being drawn hears when the pictures are in.
enum DeckNotificationService {
    static func notifyReady(topic: String, count: Int) async {
        let name = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let pictures = count == 1 ? "1 picture" : "\(count) pictures"
        await LocalNotificationService.post(
            id: "deck-illustrations-ready",
            title: "Your cards have pictures",
            body: name.isEmpty
                ? "\(pictures) finished drawing."
                : "\(pictures) finished drawing for „\(name)“."
        )
    }
}
