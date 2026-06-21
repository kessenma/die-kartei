import SwiftUI
import AVFoundation

/// The "Cards" tab of the Settings screen: flashcard study style, pronunciation/voice, and the
/// app's sources/attributions.
struct CardSettingsView: View {
    @Bindable var modelManager: MLXModelManager

    @State private var germanVoices: [AVSpeechSynthesisVoice] = []
    @State private var showVoiceGuide = false

    var body: some View {
        Group {
            Section("Flashcard Style") {
                Picker("Style", selection: $modelManager.flashcardStyle) {
                    ForEach(FlashcardStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Text(modelManager.flashcardStyle.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-advance", isOn: $modelManager.autoAdvance)
                Text("Moves to the next card automatically after selecting a rating — no need to tap Next.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pronunciation") {
                Picker("German Voice", selection: Binding(
                    get: { modelManager.selectedVoiceIdentifier ?? "" },
                    set: { modelManager.selectedVoiceIdentifier = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System Default").tag("")
                    ForEach(germanVoices, id: \.identifier) { voice in
                        Text(voiceName(voice)).tag(voice.identifier)
                    }
                }

                Button {
                    SpeechService.shared.speak("Guten Tag! Wie geht es Ihnen?")
                } label: {
                    Label("Preview Voice", systemImage: "speaker.wave.2")
                }

                // Shows which natural German voices the user has downloaded. Compact
                // voices ship with iOS; an Enhanced or Premium voice only exists
                // because the user downloaded it, so quality is a reliable
                // "did I download this myself?" signal.
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
                            Text("•  \(voiceName(voice))")
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

            Section("About") {
                NavigationLink(destination: SourcesView()) {
                    Label("Sources & Attributions", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .onAppear {
            germanVoices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix("de") }
                .sorted { lhs, rhs in
                    // Natural (Premium/Enhanced) voices first, then by name.
                    if lhs.quality != rhs.quality {
                        return lhs.quality.rawValue > rhs.quality.rawValue
                    }
                    return lhs.name < rhs.name
                }
        }
        .sheet(isPresented: $showVoiceGuide) {
            VoiceGuideSheet()
        }
    }

    /// German voices the user downloaded (Enhanced/Premium). Compact voices are
    /// pre-installed with iOS, so anything above compact quality was added by
    /// the user — we use that as the "you downloaded this" signal.
    private var downloadedGermanVoices: [AVSpeechSynthesisVoice] {
        germanVoices.filter { $0.quality == .enhanced || $0.quality == .premium }
    }

    private func voiceName(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "\(voice.name) (Premium)"
        case .enhanced: return "\(voice.name) (Enhanced)"
        default: return "\(voice.name) (Basic)"
        }
    }
}

// MARK: - Voice Download Guide

private struct VoiceGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The voices in this app come from iOS. The built-in “basic” voices sound robotic, but iOS offers free Enhanced and Premium German voices that sound much more natural.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Siri voices can't be used")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Apple's Siri voices sound the best, but Apple keeps them private — no third-party app, including this one, is allowed to use them. The best voice available here is a Premium one, which still sounds far better than the basic voices.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.bubble")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    stepRow(1, "Open the Settings app and tap the search bar at the bottom.",
                            image: "voice-guide-settings-search")
                    stepRow(2, "Type “voice”, then tap Voices under Accessibility → Live Speech.",
                            image: "voice-guide-voice-search")
                } header: {
                    Text("Quickest: search Settings")
                }

                Section {
                    stepRow(1, "Or open Settings and tap Accessibility.",
                            image: "voice-guide-accessibility")
                    stepRow(2, "Under Speech, tap Live Speech.",
                            image: "voice-guide-live-speech")
                } header: {
                    Text("Or browse to it")
                }

                Section {
                    stepRow(1, "Scroll to Preferred Voices and tap Add Preferred Voice…",
                            image: "voice-guide-add-voice")
                    stepRow(2, "Choose German. On an English iPhone it's listed as “German”, not “Deutsch”.",
                            image: "voice-guide-german")
                    stepRow(3, "Tap the cloud icon next to a voice to download its Enhanced or Premium version. Skip the Siri voices (crossed out) — apps can't use those.",
                            image: "voice-guide-voice-picker")
                } header: {
                    Text("Download a German voice")
                } footer: {
                    Text("Good picks: Yannick, Petra, Viktor, or Anna. After it downloads, force-quit this app and reopen it, then choose the voice in Pronunciation above.")
                }

                Section {
                    Label {
                        Text("Only German voices work here. English voices like “Zoe” can't pronounce German, so they won't appear in this app's voice list — make sure you download from the German section.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                }

                Section {
                    Button {
                        // openSettingsURLString is the only Apple-sanctioned deep
                        // link — it opens this app's own page in Settings. There's
                        // no public way to open Accessibility or the Settings root.
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text("Opens this app's page in Settings. Tap back to reach the main list, then Accessibility — or pull down and search “voice”.")
                }
            }
            .navigationTitle("Download Voices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// A numbered instruction with an optional screenshot beneath it. The image
    /// only renders when its asset exists in the catalog, so steps stay safe if
    /// a screenshot is ever renamed or removed.
    @ViewBuilder
    private func stepRow(_ number: Int, _ text: String, image: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let image, UIImage(named: image) != nil {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    )
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
    }
}
