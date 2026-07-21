import SwiftUI

/// The "ⓘ" affordance from a story's Listen mode: explains two-voice dialogue playback and lets
/// the learner set a voice per speaker role right here (the same section as Settings ▸ Cards),
/// plus a shortcut to the natural-voice download guide.
struct DialogueVoicesInfoSheet: View {
    @Bindable var modelManager: MLXModelManager
    var accent: Color = .accentColor

    @Environment(\.dismiss) private var dismiss
    @State private var showGuide = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Two voices for dialogues", systemImage: "person.2.wave.2.fill")
                            .font(.headline)
                        Text("In Dialogue and E-Mail stories, each speaker can read in their own voice. Choose a voice per role below — set just one and it reads everyone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                DialogueVoicePickerSection(modelManager: modelManager)

                Section {
                    Button {
                        SpeechService.shared.speak("Hallo! Ich lese den Dialog für dich vor.")
                    } label: {
                        Label("Preview voice", systemImage: "speaker.wave.2")
                    }
                    Button {
                        showGuide = true
                    } label: {
                        Label("How to download natural German voices", systemImage: "arrow.down.circle")
                    }
                }
            }
            .navigationTitle("Voices")
            .navigationBarTitleDisplayMode(.inline)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showGuide) {
                VoiceGuideSheet()
            }
        }
    }
}
