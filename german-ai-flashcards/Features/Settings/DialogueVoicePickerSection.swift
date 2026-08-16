import SwiftUI
import AVFoundation

/// Reusable Settings section for assigning a downloaded German voice to each speaker role in
/// dialogue/e-mail stories. Shared by Settings ▸ Cards and the Listen-mode voices sheet, so both
/// edit the same per-role identifiers on `MLXModelManager`.
struct DialogueVoicePickerSection: View {
    @Bindable var modelManager: MLXModelManager

    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var showChildren = false

    var body: some View {
        Section {
            picker("Man's voice", selection: $modelManager.voiceMaleIdentifier)
            picker("Woman's voice", selection: $modelManager.voiceFemaleIdentifier)

            DisclosureGroup(isExpanded: $showChildren) {
                picker("Boy's voice", selection: $modelManager.voiceBoyIdentifier)
                picker("Girl's voice", selection: $modelManager.voiceGirlIdentifier)
            } label: {
                Text("Children's voices")
            }
        } header: {
            Text("Dialogue Voices")
                .themedSectionHeader()
        } footer: {
            Text("Give each speaker their own voice in Dialogue and E-Mail stories. Set just one and that voice reads everyone. Add natural German voices in iOS Settings ▸ Accessibility ▸ Spoken Content ▸ Voices.")
        }
        .themedListRow()
        .onAppear { voices = GermanVoiceCatalog.sorted() }
    }

    private func picker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: Binding(
            get: { selection.wrappedValue ?? "" },
            set: { selection.wrappedValue = $0.isEmpty ? nil : $0 }
        )) {
            Text("Default voice").tag("")
            ForEach(voices, id: \.identifier) { voice in
                Text(GermanVoiceCatalog.name(for: voice)).tag(voice.identifier)
            }
        }
    }
}

/// Shared lookup for the installed German voices — the sort (natural voices first) and the
/// "(Premium/Enhanced/Basic)" naming used across every voice picker.
enum GermanVoiceCatalog {
    static func sorted() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("de") }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
    }

    static func name(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium:  return "\(voice.name) (Premium)"
        case .enhanced: return "\(voice.name) (Enhanced)"
        default:        return "\(voice.name) (Basic)"
        }
    }
}
