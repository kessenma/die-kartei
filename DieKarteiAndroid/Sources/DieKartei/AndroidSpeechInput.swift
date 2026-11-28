import Foundation
import Observation
import SkipFuse
import SwiftUI
@testable import DieKarteiCore
import GermanVoice

/// The learner's spoken turn on Android (iOS `SpeechRecognitionService`): tap to start, tap to
/// stop, the turn delivered to `onFinal`. Android's recognizer ends at each pause, so the next
/// utterance starts by itself until the learner stops; the results fold together through the
/// shared `SpeechTranscript`, as on iOS.
@MainActor
@Observable
final class AndroidSpeechInput: SpeechInput {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var level: Double = 0
    private(set) var unavailableMessage: String?
    private var granted = false

    @ObservationIgnored private var words = SpeechTranscript()
    @ObservationIgnored private var onFinal: ((String) -> Void)?
    /// Bumped for each utterance; results from one that was swapped out are ignored (iOS's
    /// `recognitionGeneration`).
    @ObservationIgnored private var generation = 0
    /// On-device first, as iOS; online when the device has no German.
    @ObservationIgnored private var onDevice = true
    /// Transient recognizer failures in a row; a few are retried, as iOS's recognizer rides them out.
    @ObservationIgnored private var retries = 0

    var isAvailable: Bool { granted && GermanEar.shared.isAvailable }

    /// The microphone permission, then whether there's a recognizer.
    func requestAuthorization() async -> Bool {
        guard GermanEar.shared.isAvailable else {
            unavailableMessage = "German speech recognition isn't available on this device."
            return false
        }
        #if os(Android)
        granted = await UIApplication.shared.requestPermission("android.permission.RECORD_AUDIO")
        #else
        granted = false
        #endif
        unavailableMessage = granted ? nil : "Microphone access is required. Allow it in Settings › Apps › Die Kartei › Permissions."
        return granted
    }

    func start(onFinal: @escaping (String) -> Void) {
        guard !isRecording else { return }
        if unavailableMessage != nil, granted { unavailableMessage = nil }
        guard isAvailable else {
            unavailableMessage = unavailableMessage ?? "Speech recognition is temporarily unavailable."
            return
        }
        self.onFinal = onFinal
        retries = 0
        words = SpeechTranscript()
        transcript = ""
        isRecording = true
        listen()
    }

    /// One utterance; while the turn is open, the next one starts when it ends.
    private func listen() {
        generation += 1
        let mine = generation
        GermanEar.shared.listen(
            onDevice: onDevice,
            onText: { [weak self] text, isFinal in
                MainActor.assumeIsolated {
                    guard let self, mine == self.generation, self.isRecording else { return }
                    self.words.ingest(text, isFinal: isFinal)
                    self.transcript = self.words.text
                }
            },
            onLevel: { [weak self] level in
                MainActor.assumeIsolated {
                    guard let self, mine == self.generation else { return }
                    self.level = level
                }
            },
            onEnd: { [weak self] code in
                MainActor.assumeIsolated {
                    guard let self, mine == self.generation, self.isRecording else { return }
                    self.utteranceEnded(code)
                }
            })
    }

    private func utteranceEnded(_ code: Int) {
        level = 0
        switch code {
        case 0, GermanEar.errorNoMatch, GermanEar.errorSpeechTimeout:
            // A pause, or silence: the learner's turn stays open, as on iOS.
            retries = 0
            listen()
        case GermanEar.errorBusy, GermanEar.errorServerDisconnected, GermanEar.errorClient:
            if retries < 3 {
                retries += 1
                listen()
            } else {
                logger.warning("AndroidSpeechInput: recognizer error \(code), giving up")
                deliver()
            }
        case GermanEar.errorLanguageNotSupported, GermanEar.errorLanguageUnavailable:
            if onDevice {
                // No German speech pack on the device: ask for it, and listen online meanwhile.
                onDevice = false
                _ = GermanEar.shared.downloadGerman()
                listen()
            } else {
                unavailableMessage = "German speech recognition isn't on this phone yet. Add German under Settings › System › Languages › Speech, or type instead."
                deliver()
            }
        case GermanEar.errorAudio:
            unavailableMessage = "The microphone isn't giving any sound. Check it, or type instead."
            deliver()
        case GermanEar.errorPermission:
            granted = false
            unavailableMessage = "Microphone access is required. Allow it in Settings › Apps › Die Kartei › Permissions."
            deliver()
        default:
            // iOS delivers whatever was heard when recognition fails.
            logger.warning("AndroidSpeechInput: recognizer error \(code)")
            deliver()
        }
    }

    /// Stop recording and deliver the turn so far.
    func stop() {
        guard isRecording else { return }
        deliver()
    }

    /// Discard everything spoken so far and keep listening from scratch.
    func restart() {
        guard isRecording else { return }
        generation += 1
        GermanEar.shared.interrupt()
        words = SpeechTranscript()
        transcript = ""
        level = 0
        listen()
    }

    /// A mark ends the turn so far (`SpeechTranscript.punctuated`); a fresh utterance follows.
    func appendPunctuation(_ mark: String) {
        guard isRecording, let next = words.punctuated(mark) else { return }
        generation += 1
        GermanEar.shared.interrupt()
        words = next
        transcript = words.text
        level = 0
        listen()
    }

    /// Stop without delivering (leaving the screen).
    func cancel() {
        onFinal = nil
        generation += 1
        GermanEar.shared.cancel()
        isRecording = false
        words = SpeechTranscript()
        transcript = ""
        level = 0
    }

    private func deliver() {
        generation += 1
        GermanEar.shared.cancel()
        isRecording = false
        level = 0
        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onFinal
        onFinal = nil
        callback?(final)
    }
}
