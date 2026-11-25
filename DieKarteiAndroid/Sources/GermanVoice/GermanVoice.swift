#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.speech.tts.TextToSpeech
#elseif canImport(AVFoundation)
import AVFoundation
#endif

/// Speaks German with the platform voice: Android's TextToSpeech (transpiled Kotlin), or
/// AVSpeechSynthesizer on Apple platforms (only Skip's iOS shell builds that side).
public final class GermanVoice {
    public static let shared = GermanVoice()

    #if SKIP
    private var engine: TextToSpeech? = nil
    private var ready = false
    private var pending: String? = nil
    #elseif canImport(AVFoundation)
    private let synthesizer = AVSpeechSynthesizer()
    #endif

    public init() {
    }

    /// Whether the Android engine has started and accepted German. Always true elsewhere.
    public var isReady: Bool {
        #if SKIP
        return ready
        #else
        return true
        #endif
    }

    /// Speaks `text` now, cutting off anything still playing. `slow` is the replay-slower button.
    public func speak(_ text: String, slow: Bool) {
        #if SKIP
        if ready, let engine = engine {
            engine.setSpeechRate(slow ? Float(0.6) : Float(0.95))
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, nil, "diekartei")
            return
        }
        // The engine starts asynchronously; the first request waits for it.
        pending = text
        if engine == nil {
            let context = ProcessInfo.processInfo.androidContext
            engine = TextToSpeech(context, TextToSpeech.OnInitListener { status in
                guard status == TextToSpeech.SUCCESS else { return }
                self.engine?.setLanguage(java.util.Locale.GERMANY)
                self.ready = true
                if let waiting = self.pending {
                    self.pending = nil
                    self.speak(waiting, slow: false)
                }
            })
        }
        #elseif canImport(AVFoundation)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.7 : 1.0)
        synthesizer.speak(utterance)
        #endif
    }
}
#endif
