import SwiftUI

/// "Say it in German" — the learner types or speaks (in English) what they want to say,
/// and the AI shows the natural German. They can hear it or use it as their spoken turn.
struct SayItView: View {
    let engine: ConversationEngine
    @Environment(\.dismiss) private var dismiss

    @State private var englishText = ""
    @State private var german: String?
    @State private var translating = false
    @State private var recognizer = SpeechRecognitionService(localeIdentifier: "en-US")
    @State private var authError: String?

    private var canTranslate: Bool {
        !englishText.trimmingCharacters(in: .whitespaces).isEmpty && !translating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want to say? (in English)", text: $englishText, axis: .vertical)
                        .lineLimit(2...5)

                    Button {
                        toggleRecording()
                    } label: {
                        Label(
                            recognizer.isRecording ? "Stop" : "Or speak in English",
                            systemImage: recognizer.isRecording ? "stop.circle.fill" : "mic.fill"
                        )
                        .foregroundStyle(recognizer.isRecording ? .red : .accentColor)
                    }

                    if recognizer.isRecording {
                        Text(recognizer.transcript.isEmpty ? "Listening…" : recognizer.transcript)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let authError {
                        Text(authError).font(.caption).foregroundStyle(.orange)
                    }
                } header: {
                    Text("In English")
                } footer: {
                    Text("Type or speak what you’d like to say. The AI will show you how to say it in German — then you can hear it or use it as your turn.")
                }

                Section {
                    Button {
                        translate()
                    } label: {
                        if translating {
                            HStack(spacing: 8) { ProgressView(); Text("Translating…") }
                        } else {
                            Label("Show me in German", systemImage: "arrow.right.circle.fill")
                        }
                    }
                    .disabled(!canTranslate)
                }

                if let german {
                    Section("In German") {
                        Text(german).font(.title3)
                        Button { SpeechService.shared.speak(german) } label: {
                            Label("Hear it", systemImage: "speaker.wave.2.fill")
                        }
                        Button {
                            recognizer.cancel()
                            engine.usePhrase(german)
                            dismiss()
                        } label: {
                            Label("Use as my response", systemImage: "paperplane.fill")
                        }
                    }
                }
            }
            .navigationTitle("Say it in German")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { recognizer.cancel(); dismiss() }
                }
            }
            .onDisappear { recognizer.cancel() }
        }
    }

    private func toggleRecording() {
        if recognizer.isRecording {
            recognizer.stop()
            return
        }
        Task {
            if !recognizer.isAvailable {
                let granted = await recognizer.requestAuthorization()
                guard granted else {
                    authError = "Microphone and speech-recognition access are needed to speak."
                    return
                }
            }
            authError = nil
            recognizer.start { final in
                let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { englishText = trimmed }
            }
        }
    }

    private func translate() {
        let text = englishText
        translating = true
        german = nil
        Task {
            german = await engine.englishToGerman(text)
            translating = false
        }
    }
}
