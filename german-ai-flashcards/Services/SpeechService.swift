import AVFoundation

/// Lightweight wrapper around AVSpeechSynthesizer for speaking German text.
@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?
    /// Called as each word is about to be spoken, with its range in the utterance string.
    private var onWord: ((NSRange) -> Void)?

    /// True while an utterance is actively being spoken.
    private(set) var isSpeaking = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak German text.
    /// - Parameters:
    ///   - slow: Uses a slower rate (the "turtle" playback control).
    ///   - onWord: Called on the main actor with the character range of each word as it's spoken
    ///     (used to highlight along while reading).
    ///   - onFinish: Called on the main actor when speech finishes or is cancelled.
    func speak(_ text: String, slow: Bool = false, onWord: ((NSRange) -> Void)? = nil, onFinish: (() -> Void)? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        // Recording uses a record category; switch back to playback for TTS.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        let storedID = UserDefaults.standard.string(forKey: "selectedVoiceIdentifier")
        if let id = storedID, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        }
        let base = AVSpeechUtteranceDefaultSpeechRate
        utterance.rate = slow ? base * 0.5 : base * 0.85

        self.onFinish = onFinish
        self.onWord = onWord
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stop any in-progress speech. Fires the pending `onFinish`.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onWord?(characterRange) }
    }

    private func finish() {
        isSpeaking = false
        let callback = onFinish
        onFinish = nil
        onWord = nil
        callback?()
    }
}
