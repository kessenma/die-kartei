#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.speech.SpeechRecognizer
import android.speech.RecognizerIntent
import android.speech.RecognitionListener
import android.content.Intent
import android.os.Bundle
#endif

/// Listens for German with Android's SpeechRecognizer (transpiled Kotlin). One `listen` is one
/// utterance: Android ends a recognition at a pause, so the app's `AndroidSpeechInput` starts
/// the next one itself while the learner's turn is open, and folds the results together with
/// the shared `SpeechTranscript`. Elsewhere it is never available.
public final class GermanEar {
    public static let shared = GermanEar()

    /// Android's `SpeechRecognizer.ERROR_*` codes the app reacts to.
    public static let errorNoMatch = 7
    public static let errorSpeechTimeout = 6
    public static let errorPermission = 9
    public static let errorBusy = 8
    public static let errorClient = 5
    /// No microphone audio (`ERROR_AUDIO`).
    public static let errorAudio = 3
    /// The recognition service dropped the connection (`ERROR_SERVER_DISCONNECTED`).
    public static let errorServerDisconnected = 11
    /// No German on the device's recognizer (`ERROR_LANGUAGE_NOT_SUPPORTED`, `_UNAVAILABLE`).
    public static let errorLanguageNotSupported = 12
    public static let errorLanguageUnavailable = 13

    #if SKIP
    private var recognizer: SpeechRecognizer? = nil
    #endif

    public init() {
    }

    /// Whether this device has a speech recognizer at all.
    public var isAvailable: Bool {
        #if SKIP
        return SpeechRecognizer.isRecognitionAvailable(ProcessInfo.processInfo.androidContext)
        #else
        return false
        #endif
    }

    /// Listen for one utterance. `onText` gets each hypothesis (`isFinal` once the utterance has
    /// ended), `onLevel` the input level (0…1), `onEnd` a final error code, or 0 after results.
    /// `onDevice`: ask for on-device recognition (iOS's preference); without it the platform may
    /// use its online recognizer.
    public func listen(onDevice: Bool, onText: @escaping (String, Bool) -> Void, onLevel: @escaping (Double) -> Void,
                       onEnd: @escaping (Int) -> Void) {
        #if SKIP
        let context = ProcessInfo.processInfo.androidContext
        if recognizer == nil {
            recognizer = SpeechRecognizer.createSpeechRecognizer(context)
        }
        guard let recognizer = recognizer else {
            onEnd(GermanEar.errorClient)
            return
        }
        recognizer.setRecognitionListener(Listener(onText: onText, onLevel: onLevel, onEnd: onEnd))
        let intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "de-DE")
        intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        // As iOS: on the device when it can be.
        intent.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, onDevice)
        recognizer.startListening(intent)
        #else
        onEnd(GermanEar.errorClient)
        #endif
    }

    /// Ask the device to fetch its German speech pack (Android 13+); false when it can't.
    public func downloadGerman() -> Bool {
        #if SKIP
        guard android.os.Build.VERSION.SDK_INT >= 33 else { return false }
        let context = ProcessInfo.processInfo.androidContext
        let intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "de-DE")
        do {
            let downloader = recognizer ?? SpeechRecognizer.createSpeechRecognizer(context)
            downloader.triggerModelDownload(intent)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// End the utterance now; its last result still arrives.
    public func stopListening() {
        #if SKIP
        recognizer?.stopListening()
        #endif
    }

    /// Drop the utterance in progress, keeping the recognizer for the next one.
    public func interrupt() {
        #if SKIP
        recognizer?.cancel()
        #endif
    }

    /// Stop without a result, and let go of the recognizer.
    public func cancel() {
        #if SKIP
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = nil
        #endif
    }
}

#if SKIP
private final class Listener: RecognitionListener {
    let onText: (String, Bool) -> Void
    let onLevel: (Double) -> Void
    let onEnd: (Int) -> Void

    init(onText: @escaping (String, Bool) -> Void, onLevel: @escaping (Double) -> Void, onEnd: @escaping (Int) -> Void) {
        self.onText = onText
        self.onLevel = onLevel
        self.onEnd = onEnd
    }

    override func onReadyForSpeech(params: Bundle?) {}
    override func onBeginningOfSpeech() {}
    override func onBufferReceived(buffer: kotlin.ByteArray?) {}
    override func onEndOfSpeech() {}
    override func onEvent(eventType: Int, params: Bundle?) {}

    /// Android reports dB, roughly -2…10; the meter wants 0…1.
    override func onRmsChanged(rmsdB: Float) {
        onLevel(Double(max(Float(0.0), min(Float(1.0), (rmsdB + Float(2.0)) / Float(12.0)))))
    }

    override func onPartialResults(partialResults: Bundle?) {
        if let text = Listener.best(partialResults) { onText(text, false) }
    }

    override func onResults(results: Bundle?) {
        onText(Listener.best(results) ?? "", true)
        onEnd(0)
    }

    override func onError(error: Int) {
        onEnd(error)
    }

    static func best(_ bundle: Bundle?) -> String? {
        let list = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        guard let list = list, list.size > 0 else { return nil }
        return list.get(0)
    }
}
#endif
#endif
