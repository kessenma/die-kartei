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
    // Bumped every time we (re)create the recognition task. Callbacks from a task that
    // was swapped out by `restart()` / `appendPunctuation(_:)` carry a stale value and
    // are ignored, so their cancellation error can't tear down the live session.
    private var recognitionGeneration = 0

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

            try startRecognitionTask(with: recognizer)
            isRecording = true
        } catch {
            availability = .unavailable("Couldn’t start recording: \(error.localizedDescription)")
            teardownAudio()
            isRecording = false
        }
    }

    /// Build a fresh recognition request + task on the audio engine, starting the engine
    /// if it isn't already running. Shared by `start()`, `restart()`, and `appendPunctuation(_:)`.
    private func startRecognitionTask(with recognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Let the recognizer insert commas/periods/question marks from prosody, so a spoken
        // "Ich glaube, dass…" doesn't come back comma-less and read as an error downstream.
        request.addsPunctuation = true
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

        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }

        recognitionGeneration += 1
        let generation = recognitionGeneration
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                // Ignore callbacks from a task we've since swapped out (restart / punctuation).
                guard generation == self.recognitionGeneration else { return }
                if let result {
                    self.ingest(result.bestTranscription.formattedString, isFinal: result.isFinal)
                }
                if error != nil {
                    // Deliver whatever we have on error (often just "no speech").
                    self.deliverAndTeardown()
                }
            }
        }
    }

    /// Tear down the in-flight recognition (task + request) without stopping the audio
    /// engine or delivering a result — used to swap in a fresh recognizer mid-recording.
    private func resetRecognitionTask() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
    }

    /// Stop recording and deliver the current transcript.
    func stop() {
        guard isRecording else { return }
        deliverAndTeardown()
    }

    /// Discard everything spoken so far and keep listening from scratch — for when the
    /// learner doesn't like what they said. The mic stays open; only the transcript resets.
    func restart() {
        guard isRecording, let recognizer else { return }
        resetRecognitionTask()
        transcript = ""
        committedText = ""
        currentUtterance = ""
        level = 0
        try? startRecognitionTask(with: recognizer)
    }

    /// Append a punctuation mark (e.g. "." or "?") to the running transcript. On-device
    /// recognition doesn't add end punctuation, so this lets the learner mark sentence
    /// boundaries while speaking — it matters in German, where "?" vs "." changes the meaning.
    func appendPunctuation(_ mark: String) {
        guard isRecording, let recognizer else { return }
        var base = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // With automatic punctuation on, the recognizer may already have ended the segment with a
        // mark — replace it rather than stacking ("Ich glaube." + "," → "Ich glaube,").
        while let last = base.last, ".,!?…".contains(last) {
            base.removeLast()
        }
        guard !base.isEmpty else { return }

        // Swap in a fresh recognizer so the in-progress utterance isn't re-delivered (and
        // re-appended) after we fold it into the committed text with its new mark.
        resetRecognitionTask()
        committedText = base + mark
        currentUtterance = ""
        transcript = committedText
        level = 0
        try? startRecognitionTask(with: recognizer)
    }

    /// Accumulate recognizer output across utterance resets so the whole spoken turn is kept.
    ///
    /// On-device recognition emits a run of results per spoken segment: partial hypotheses
    /// (`isFinal == false`) that revise the *same* segment, then a final result (`isFinal == true`)
    /// when a pause ends it. Each result's `formattedString` is the complete hypothesis for the
    /// *current* segment only (it resets after a pause), so we fold finalized segments into
    /// `committedText` and keep the in-progress one in `currentUtterance`.
    ///
    /// Partials *revise* earlier words — e.g. "neue Hof" → "neue Koffer" — they don't only append.
    /// So we replace the current segment wholesale rather than merging by prefix. The old
    /// prefix merge mistook such a revision for a brand-new sentence and kept both, which produced
    /// the duplicated "…neue Hof …neue Koffer" transcripts.
    private func ingest(_ raw: String, isFinal: Bool) {
        let segment = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if isFinal {
            commit(segment)
            currentUtterance = ""
        } else if isNewSegment(segment, replacing: currentUtterance) {
            // A pause began a fresh segment without a final result — bank the previous one.
            commit(currentUtterance)
            currentUtterance = segment
        } else {
            // Same segment, revised hypothesis — replace it, never append.
            currentUtterance = segment
        }

        transcript = [committedText, currentUtterance]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Fold a finished segment into the running committed transcript.
    private func commit(_ segment: String) {
        guard !segment.isEmpty else { return }
        committedText = committedText.isEmpty ? segment : committedText + " " + segment
    }

    /// Whether `next` is a brand-new segment rather than a revision of `current`. A fresh on-device
    /// segment starts over from scratch, so it shares no leading words with the prior hypothesis;
    /// a revision keeps most of them. Comparing on shared *words* (not raw character prefix) means
    /// the recognizer rewording a word or two no longer reads as a new segment — the bug that
    /// duplicated text.
    private func isNewSegment(_ next: String, replacing current: String) -> Bool {
        guard !current.isEmpty, !next.isEmpty else { return false }
        let currentWords = current.lowercased().split(separator: " ")
        let nextWords = next.lowercased().split(separator: " ")
        let sharedLeadingWords = zip(currentWords, nextWords).prefix { $0.0 == $0.1 }.count
        return sharedLeadingWords == 0 && !next.hasPrefix(current) && !current.hasPrefix(next)
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
