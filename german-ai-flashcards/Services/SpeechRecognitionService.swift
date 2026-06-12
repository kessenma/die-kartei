import Foundation
import Speech
import AVFoundation

/// On-device German speech-to-text for the conversation feature.
/// Tap to start, tap to stop; the final transcript is delivered via `onFinal`.
@Observable
@MainActor
final class SpeechRecognitionService {

    enum Availability {
        case unknown
        case ready
        case denied(String)
        case unavailable(String)
    }

    /// Live partial transcript shown while recording.
    private(set) var transcript: String = ""
    private(set) var isRecording = false
    private(set) var availability: Availability = .unknown
    /// Audio input level (0…1), updated while recording for a simple meter animation.
    private(set) var level: Double = 0

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()

    init(localeIdentifier: String = "de-DE") {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onFinal: ((String) -> Void)?
    private var hasDelivered = false

    // On-device recognition resets `formattedString` after each pause/utterance, so we
    // accumulate finalized utterances ourselves to keep the whole spoken turn.
    private var committedText = ""
    private var currentUtterance = ""

    var isAvailable: Bool {
        if case .ready = availability { return true }
        return false
    }

    // MARK: - Authorization

    /// Request microphone + speech-recognition permission. Returns true if both granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard recognizer != nil else {
            availability = .unavailable("German speech recognition isn’t available on this device.")
            return false
        }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            availability = .denied("Speech recognition permission is required. Enable it in Settings › Privacy › Speech Recognition.")
            return false
        }

        let micGranted = await requestMicPermission()
        guard micGranted else {
            availability = .denied("Microphone access is required. Enable it in Settings › Privacy › Microphone.")
            return false
        }

        availability = .ready
        return true
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Recording

    func start(onFinal: @escaping (String) -> Void) {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            availability = .unavailable("Speech recognition is temporarily unavailable. Check your connection and try again.")
            return
        }

        self.onFinal = onFinal
        self.hasDelivered = false
        self.transcript = ""
        self.committedText = ""
        self.currentUtterance = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let rms = Self.rms(of: buffer)
                Task { @MainActor in self?.level = rms }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                Task { @MainActor in
                    if let result {
                        self.ingest(result.bestTranscription.formattedString, isFinal: result.isFinal)
                    }
                    if error != nil {
                        // Deliver whatever we have on error (often just "no speech").
                        self.deliverAndTeardown()
                    }
                }
            }
        } catch {
            availability = .unavailable("Couldn’t start recording: \(error.localizedDescription)")
            teardownAudio()
            isRecording = false
        }
    }

    /// Stop recording and deliver the current transcript.
    func stop() {
        guard isRecording else { return }
        deliverAndTeardown()
    }

    /// Accumulate recognizer output across utterance resets so the whole spoken turn is kept.
    /// On-device recognition restarts `formattedString` after each pause; without this, only the
    /// last sentence would survive.
    private func ingest(_ utterance: String, isFinal: Bool) {
        let next = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        if !next.isEmpty {
            if currentUtterance.isEmpty {
                currentUtterance = next
            } else {
                let a = currentUtterance.lowercased(), b = next.lowercased()
                if a.hasPrefix(b) || b.hasPrefix(a) {
                    // Same utterance being refined — keep the longer (more complete) form.
                    if next.count >= currentUtterance.count { currentUtterance = next }
                } else {
                    // Text diverged → the recognizer started a new utterance; keep the old one.
                    committedText = committedText.isEmpty ? currentUtterance : committedText + " " + currentUtterance
                    currentUtterance = next
                }
            }
        }
        if committedText.isEmpty {
            transcript = currentUtterance
        } else if currentUtterance.isEmpty {
            transcript = committedText
        } else {
            transcript = committedText + " " + currentUtterance
        }
        if isFinal {
            committedText = transcript
            currentUtterance = ""
        }
    }

    /// Cancel without delivering a result (e.g. leaving the screen).
    func cancel() {
        onFinal = nil
        hasDelivered = true
        teardownAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        transcript = ""
        committedText = ""
        currentUtterance = ""
        level = 0
    }

    private func deliverAndTeardown() {
        guard !hasDelivered else { return }
        hasDelivered = true

        request?.endAudio()
        teardownAudio()
        task?.finish()
        task = nil
        request = nil
        isRecording = false
        level = 0

        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onFinal
        onFinal = nil
        callback?(final)
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = (sum / Float(count)).squareRoot()
        // Map to a roughly 0…1 range for the meter.
        return Double(min(1, max(0, rms * 12)))
    }
}
