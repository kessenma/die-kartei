//
//  HoerenPlayer.swift
//  german-ai-flashcards
//
//  The one way the Hören room plays audio: `SpeechService`, with the room's bookkeeping on top.
//  It counts plays (the first is the hearing, every later one a replay) and whether slow speech
//  was used, and it tells a natural end from a stop.
//
//  Two traps it exists for. `SpeechService` fires `onFinish` on `stop()` as well as at the end,
//  and a fresh `speak` cancels the one before, firing that one's `onFinish` too. A generation
//  counter drops stale callbacks, and `manualStop` marks a stop, so auto-advance never fires
//  because the learner pressed stop or left the screen.
//

import Foundation
import Observation

@MainActor
@Observable
final class HoerenPlayer {
    private(set) var isPlaying = false
    /// Plays of the current item. The first is the hearing; the rest are replays.
    private(set) var plays = 0
    private(set) var slowUsed = false

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var manualStop = false

    var replays: Int { max(0, plays - 1) }

    /// Plays `text`. `onNaturalEnd` runs only when the speech reaches its end by itself.
    func play(_ text: String, slow: Bool = false, onNaturalEnd: (() -> Void)? = nil) {
        generation += 1
        let mine = generation
        manualStop = false
        plays += 1
        if slow { slowUsed = true }
        isPlaying = true
        SpeechService.shared.speak(text, slow: slow) { [weak self] in
            guard let self, self.generation == mine else { return }
            self.isPlaying = false
            let stopped = self.manualStop
            self.manualStop = false
            if !stopped { onNaturalEnd?() }
        }
    }

    /// Story-length playback, segment by segment with each speaker's voice.
    func play(segments: [SpeechService.Segment], slow: Bool = false, onNaturalEnd: (() -> Void)? = nil) {
        generation += 1
        let mine = generation
        manualStop = false
        plays += 1
        if slow { slowUsed = true }
        isPlaying = true
        SpeechService.shared.speak(segments: segments, slow: slow, onFinish: { [weak self] in
            guard let self, self.generation == mine else { return }
            self.isPlaying = false
            let stopped = self.manualStop
            self.manualStop = false
            if !stopped { onNaturalEnd?() }
        })
    }

    func stop() {
        guard isPlaying else { return }
        manualStop = true
        SpeechService.shared.stop()
        isPlaying = false
    }

    /// A new item: the counts start again.
    func reset() {
        stop()
        plays = 0
        slowUsed = false
    }
}
