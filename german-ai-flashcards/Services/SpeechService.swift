import AVFoundation
import MediaPlayer

/// Lightweight wrapper around AVSpeechSynthesizer for speaking German text. Speaks an ordered
/// queue of segments, each with its own voice — a single string is just a one-segment queue, so
/// dialogue stories can alternate voices per speaker while everything else keeps working as before.
///
/// For "player"-style playback (the story read-along) it also supports pause/resume, skipping
/// between segments, starting mid-queue, and driving the lock screen / Dynamic Island via
/// `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` so playback keeps going out of the app.
@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()

    /// One spoken chunk. `rangeOffset` is the UTF-16 offset of `text` within the full display
    /// string, so word-highlight ranges can be reported back in full-text coordinates.
    struct Segment {
        let text: String
        let voiceIdentifier: String?
        let rangeOffset: Int

        init(text: String, voiceIdentifier: String? = nil, rangeOffset: Int = 0) {
            self.text = text
            self.voiceIdentifier = voiceIdentifier
            self.rangeOffset = rangeOffset
        }
    }

    /// Lock screen / Dynamic Island metadata. Pass when starting a "player" playback (e.g. a story);
    /// omit for incidental speech (glossary words, chat replies) so those don't hijack Now Playing.
    struct NowPlayingInfo {
        let title: String
        let artist: String
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    /// Called as each word is about to be spoken, with its range in the full display string.
    private var onWord: ((NSRange) -> Void)?
    /// Called when playback moves to a new segment (index into the queue), for follow-along UIs.
    private var onSegmentChange: ((Int) -> Void)?

    // Queue state.
    private var queue: [Segment] = []
    private var queueIndex = 0
    private var slowRate = false
    /// True while a `stop()` (or a fresh `speak`) is tearing down the current queue, so the
    /// resulting `didCancel` fires the finish callback exactly once (and stray cancels don't).
    private var isCancelling = false
    /// When set, the pending stop is a skip: `didCancel` restarts at this index instead of finishing.
    private var pendingSkipIndex: Int?

    /// True while a queue is active (playing or paused).
    private(set) var isSpeaking = false
    /// True while an active queue is paused mid-utterance.
    private(set) var isPaused = false

    // Now Playing.
    private var nowPlaying: NowPlayingInfo?
    private var remoteCommandsWired = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Speak

    /// Speak a single German string. Incidental speech — no lock-screen Now Playing.
    /// - Parameters:
    ///   - slow: Uses a slower rate (the "turtle" playback control).
    ///   - voiceIdentifier: A specific voice; nil falls back to the app's selected voice, then de-DE.
    ///   - onWord: Called with the character range of each word as it's spoken (for read-along).
    ///   - onFinish: Called when speech finishes or is cancelled.
    func speak(_ text: String, slow: Bool = false, voiceIdentifier: String? = nil,
               onWord: ((NSRange) -> Void)? = nil, onFinish: (() -> Void)? = nil) {
        speak(segments: [Segment(text: text, voiceIdentifier: voiceIdentifier)],
              slow: slow, onWord: onWord, onFinish: onFinish)
    }

    /// Speak an ordered queue of segments, each in its own voice, optionally starting mid-queue and
    /// showing Now Playing controls. `onFinish` fires once, after the last segment completes (or as
    /// soon as the queue is cancelled).
    func speak(segments: [Segment], startingAt startIndex: Int = 0, slow: Bool = false,
               nowPlaying: NowPlayingInfo? = nil,
               onWord: ((NSRange) -> Void)? = nil,
               onSegmentChange: ((Int) -> Void)? = nil,
               onFinish: (() -> Void)? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        // Recording uses a record category; switch back to playback for TTS.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        queue = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        queueIndex = queue.isEmpty ? 0 : min(max(startIndex, 0), queue.count - 1)
        slowRate = slow
        self.onWord = onWord
        self.onSegmentChange = onSegmentChange
        self.onFinish = onFinish
        isCancelling = false
        pendingSkipIndex = nil
        isPaused = false

        guard !queue.isEmpty else { finish(); return }
        isSpeaking = true

        self.nowPlaying = nowPlaying
        if nowPlaying != nil {
            wireRemoteCommandsIfNeeded()
            updateNowPlayingInfo()
        } else {
            clearNowPlaying()
        }

        onSegmentChange?(queueIndex)
        speakCurrent()
    }

    private func speakCurrent() {
        guard queueIndex < queue.count else { finish(); return }
        let segment = queue[queueIndex]
        let utterance = AVSpeechUtterance(string: segment.text)
        let storedID = segment.voiceIdentifier ?? UserDefaults.standard.string(forKey: "selectedVoiceIdentifier")
        if let id = storedID, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        }
        let base = AVSpeechUtteranceDefaultSpeechRate
        utterance.rate = slowRate ? base * 0.5 : base * 0.85
        synthesizer.speak(utterance)
    }

    // MARK: - Transport

    /// Stop any in-progress speech. Fires the pending `onFinish`.
    func stop() {
        guard isSpeaking else { return }
        isCancelling = true
        pendingSkipIndex = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Pause mid-utterance (resumable). No-op if not currently speaking.
    func pause() {
        guard isSpeaking, !isPaused else { return }
        isPaused = true
        synthesizer.pauseSpeaking(at: .word)
        updateNowPlayingInfo()
    }

    /// Resume after `pause()`.
    func resume() {
        guard isSpeaking, isPaused else { return }
        isPaused = false
        synthesizer.continueSpeaking()
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        guard isSpeaking else { return }
        isPaused ? resume() : pause()
    }

    /// Jump to a segment and start speaking it. Restarts playback if paused.
    func skipToSegment(_ index: Int) {
        guard isSpeaking, !queue.isEmpty else { return }
        pendingSkipIndex = max(0, min(index, queue.count - 1))
        synthesizer.stopSpeaking(at: .immediate) // fires didCancel → restarts at pendingSkipIndex
    }

    /// Advance to the next segment, or stop if already on the last one.
    func nextSegment() {
        guard isSpeaking else { return }
        if queueIndex + 1 >= queue.count { stop() } else { skipToSegment(queueIndex + 1) }
    }

    /// Go back to the previous segment (clamped at the first).
    func previousSegment() {
        guard isSpeaking else { return }
        skipToSegment(queueIndex - 1)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.advance() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // A pending skip restarts the queue at the requested segment instead of finishing.
            if let target = self.pendingSkipIndex {
                self.pendingSkipIndex = nil
                self.queueIndex = target
                self.isPaused = false
                self.onSegmentChange?(target)
                self.updateNowPlayingInfo()
                self.speakCurrent()
                return
            }
            // Only the deliberate teardown of the active queue should finish; a cancel from
            // starting a fresh queue (isCancelling == false) is ignored.
            if self.isCancelling { self.finish() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let offset = self.queueIndex < self.queue.count ? self.queue[self.queueIndex].rangeOffset : 0
            self.onWord?(NSRange(location: offset + characterRange.location, length: characterRange.length))
        }
    }

    /// A segment finished naturally — move to the next, or finish when the queue is exhausted.
    private func advance() {
        guard isSpeaking, !isCancelling else { return }
        queueIndex += 1
        if queueIndex < queue.count {
            onSegmentChange?(queueIndex)
            updateNowPlayingInfo()
            speakCurrent()
        } else {
            finish()
        }
    }

    private func finish() {
        isSpeaking = false
        isPaused = false
        isCancelling = false
        pendingSkipIndex = nil
        queue = []
        queueIndex = 0
        let callback = onFinish
        onFinish = nil
        onWord = nil
        onSegmentChange = nil
        clearNowPlaying()
        callback?()
    }

    // MARK: - Now Playing (lock screen / Dynamic Island)

    /// Register the remote-control handlers once; they act on whatever queue is currently playing.
    /// Delivered on the main thread, so `assumeIsolated` is safe here.
    private func wireRemoteCommandsIfNeeded() {
        guard !remoteCommandsWired else { return }
        remoteCommandsWired = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSpeaking else { return .commandFailed }
                self.resume(); return .success
            }
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSpeaking else { return .commandFailed }
                self.pause(); return .success
            }
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSpeaking else { return .commandFailed }
                self.togglePlayPause(); return .success
            }
        }
        center.stopCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSpeaking else { return .commandFailed }
                self.stop(); return .success
            }
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSpeaking else { return .commandFailed }
                self.nextSegment(); return .success
            }
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isSpeaking else { return .commandFailed }
                self.previousSegment(); return .success
            }
        }
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
    }

    private func updateNowPlayingInfo() {
        guard let nowPlaying else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyArtist: nowPlaying.artist,
            MPMediaItemPropertyPlaybackDuration: estimatedDuration(),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: estimatedElapsed(),
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPaused ? .paused : .playing
    }

    private func clearNowPlaying() {
        nowPlaying = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    /// TTS gives no true duration, so estimate one from character count and speaking pace — enough
    /// to render a plausible, moving lock-screen scrubber.
    private var charsPerSecond: Double { slowRate ? 7 : 14 }
    private var totalChars: Int { queue.reduce(0) { $0 + ($1.text as NSString).length } }
    private var charsBeforeCurrent: Int {
        queue.prefix(queueIndex).reduce(0) { $0 + ($1.text as NSString).length }
    }
    private func estimatedDuration() -> Double { max(1, Double(totalChars) / charsPerSecond) }
    private func estimatedElapsed() -> Double { Double(charsBeforeCurrent) / charsPerSecond }
}
