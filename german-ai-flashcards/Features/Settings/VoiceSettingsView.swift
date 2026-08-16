import SwiftUI
import AVFoundation

/// App ▸ Voice. Everything about how German is spoken aloud, gathered in one place: the general
/// pronunciation voice (used for flashcards and single-line playback) and the per-role Dialogue
/// Voices (used in Dialogue/E-Mail stories). Both were previously buried inside the Cards settings
/// tab; the theme-upgrade IA promotes them to their own App-level screen.
struct VoiceSettingsView: View {
    @Bindable var modelManager: MLXModelManager

    @State private var germanVoices: [AVSpeechSynthesisVoice] = []
    @State private var showVoiceGuide = false

    var body: some View {
        Form {
            SettingsHeader(icon: "waveform", title: "Voice")

            Section("Pronunciation") {
                Picker("German Voice", selection: Binding(
                    get: { modelManager.selectedVoiceIdentifier ?? "" },
                    set: { modelManager.selectedVoiceIdentifier = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System Default").tag("")
                    ForEach(germanVoices, id: \.identifier) { voice in
                        Text(GermanVoiceCatalog.name(for: voice)).tag(voice.identifier)
                    }
                }

                Button {
                    SpeechService.shared.speak("Guten Tag! Wie geht es Ihnen?")
                } label: {
                    Label("Preview Voice", systemImage: "speaker.wave.2")
                }

                // Compact voices ship with iOS; an Enhanced or Premium voice only exists because the
                // user downloaded it, so quality is a reliable "did I download this myself?" signal.
                if downloadedGermanVoices.isEmpty {
                    Label {
                        Text("No natural German voices downloaded yet — every option above is a basic (robotic) voice. Tap below to add an Enhanced or Premium one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("You downloaded these", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        ForEach(downloadedGermanVoices, id: \.identifier) { voice in
                            Text("•  \(GermanVoiceCatalog.name(for: voice))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    showVoiceGuide = true
                } label: {
                    Label("How to download natural German voices", systemImage: "info.circle")
                }
            }

            DialogueVoicePickerSection(modelManager: modelManager)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { germanVoices = GermanVoiceCatalog.sorted() }
        .sheet(isPresented: $showVoiceGuide) {
            VoiceGuideSheet()
        }
    }

    /// German voices the user downloaded (Enhanced/Premium) — anything above compact quality.
    private var downloadedGermanVoices: [AVSpeechSynthesisVoice] {
        germanVoices.filter { $0.quality == .enhanced || $0.quality == .premium }
    }
}
