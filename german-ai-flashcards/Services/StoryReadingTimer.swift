//
//  StoryReadingTimer.swift
//  german-ai-flashcards
//
//  A stopwatch for time spent with a story. Owned by the story screen: it runs while the story is
//  on screen and the app is in the foreground, pauses when either stops being true, and hands its
//  accumulated seconds to `StoryProgressService` when the screen goes away.
//
//  Time is measured from wall-clock stamps, not by counting ticks, so a suspended app can never
//  inflate (or lose) a session; the one-second tick exists only to drive the live clock in the UI.
//

import Foundation

@Observable
@MainActor
final class StoryReadingTimer {

    /// Whole seconds accumulated since the last `take()`, refreshed every second while running.
    private(set) var seconds: Int = 0

    /// Completed stretches since the last `take()`.
    private var accumulated: TimeInterval = 0
    /// Start of the stretch currently running, or nil when paused.
    private var startedAt: Date?
    private var ticker: Task<Void, Never>?

    var isRunning: Bool { startedAt != nil }

    /// Start (or resume) counting. Idempotent, so it's safe on every `onAppear` / scene change.
    func start() {
        guard startedAt == nil else { return }
        startedAt = Date()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    /// Stop counting but keep what's accumulated (backgrounding, leaving read mode).
    func pause() {
        commit()
        ticker?.cancel()
        ticker = nil
    }

    /// Pause and hand back the whole seconds read since the last take, resetting the counter so
    /// the same time can never be logged twice.
    func take() -> Int {
        pause()
        let total = Int(accumulated.rounded())
        accumulated = 0
        seconds = 0
        return total
    }

    /// Put seconds back after a `take()` whose caller couldn't use them (a stretch too short to
    /// record). Without this, backgrounding the app every 10 seconds would quietly erase the time.
    func giveBack(_ seconds: Int) {
        guard seconds > 0 else { return }
        accumulated += TimeInterval(seconds)
        refresh()
    }

    /// Fold the running stretch into the accumulated total and stop it.
    private func commit() {
        if let startedAt {
            accumulated += Date().timeIntervalSince(startedAt)
        }
        startedAt = nil
        refresh()
    }

    private func refresh() {
        let running = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        seconds = Int((accumulated + running).rounded())
    }
}
