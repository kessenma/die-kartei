import SwiftUI
import UIKit   // VoiceGuideSheet (below) uses UIImage / UIApplication

/// Learning ▸ Flashcards settings: flashcard study style plus the game-mechanic toggles (haptics,
/// card matching, der/die/das coaching). Voice, reminders, and sources each moved to their own
/// App/About screen in the theme-upgrade Settings IA.
struct CardSettingsView: View {
    @Bindable var modelManager: MLXModelManager

    /// Shared with the same picker in the deck-creation options.
    @AppStorage(CardImageTiming.defaultsKey) private var imageTiming: CardImageTiming = .keptCards

    var body: some View {
        Group {
            Section {
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

                // Mirrors the toggle in the deck-creation options; hidden until the image model
                // is downloaded (Settings ▸ Model).
                if ImageGenModel.current.isDownloaded {
                    Toggle("AI pictures on new decks", isOn: $modelManager.flashcardIllustrationsEnabled)
                    Text("Draws a picture for each new card on-device and shows it on the German side. Existing decks can be illustrated from their start screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if modelManager.flashcardIllustrationsEnabled {
                        Picker("Draw pictures for", selection: $imageTiming) {
                            ForEach(CardImageTiming.allCases) { timing in
                                Text(timing.label).tag(timing)
                            }
                        }
                        Text(imageTiming.caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    CardImageStyleRow()
                    Text("Sets the look of new card pictures. A deck already illustrated keeps its pictures until you redraw it from its start screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Flashcard Style").themedSectionHeader()
            }
            .themedListRow()

            Section {
                Picker("Game vibrations", selection: $modelManager.hapticFeedbackMode) {
                    ForEach(HapticFeedbackMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(modelManager.hapticFeedbackMode.description + " Applies to the matching, der/die/das, and grammar drills — never stories, chat, or flashcards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Haptics").themedSectionHeader()
            }
            .themedListRow()

            Section {
                Picker("Pairs per round", selection: $modelManager.matchingPairCount) {
                    ForEach([6, 8, 10, 12], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }

                Toggle("Bring back tricky pairs", isOn: $modelManager.matchingTrickyFirst)
                Text("Rounds mix in words you've missed before until you match them first-try a few rounds in a row.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Share tricky words with the coach", isOn: $modelManager.matchingFeedsCoach)
                Text("Words you keep missing join the coach's memory, so conversations work them in and they show up in Coach's Notes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Card Matching").themedSectionHeader()
            }
            .themedListRow()

            Section {
                Toggle("Share missed nouns with the coach", isOn: $modelManager.articleFeedsCoach)
                Text("Nouns whose article keeps tripping you up join the coach's memory too, and every round nudges the profile's Artikel skill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Der · Die · Das").themedSectionHeader()
            }
            .themedListRow()

            Section {
                Toggle("Share tricky prepositions with the coach", isOn: $modelManager.prepositionsFeedCoach)
                Text("Prepositions whose case keeps tripping you up join the coach's memory, and every round nudges the profile's Präpositionen skill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Präpositionen").themedSectionHeader()
            }
            .themedListRow()
        }
    }
}

// MARK: - Voice Download Guide

struct VoiceGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The voices in this app come from iOS. The built-in “basic” voices sound robotic, but iOS offers free Enhanced and Premium German voices that sound much more natural.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .themedListRow()

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
                .themedListRow()

                Section {
                    stepRow(1, "Open the Settings app and tap the search bar at the bottom.",
                            image: "voice-guide-settings-search")
                    stepRow(2, "Type “voice”, then tap Voices under Accessibility → Live Speech.",
                            image: "voice-guide-voice-search")
                } header: {
                    Text("Quickest: search Settings").themedSectionHeader()
                }
                .themedListRow()

                Section {
                    stepRow(1, "Or open Settings and tap Accessibility.",
                            image: "voice-guide-accessibility")
                    stepRow(2, "Under Speech, tap Live Speech.",
                            image: "voice-guide-live-speech")
                } header: {
                    Text("Or browse to it").themedSectionHeader()
                }
                .themedListRow()

                Section {
                    stepRow(1, "Scroll to Preferred Voices and tap Add Preferred Voice…",
                            image: "voice-guide-add-voice")
                    stepRow(2, "Choose German. On an English iPhone it's listed as “German”, not “Deutsch”.",
                            image: "voice-guide-german")
                    stepRow(3, "Tap the cloud icon next to a voice to download its Enhanced or Premium version. Skip the Siri voices (crossed out) — apps can't use those.",
                            image: "voice-guide-voice-picker")
                } header: {
                    Text("Download a German voice").themedSectionHeader()
                } footer: {
                    Text("Good picks: Yannick, Petra, Viktor, or Anna. After it downloads, force-quit this app and reopen it, then choose the voice in Pronunciation above.")
                }
                .themedListRow()

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
                .themedListRow()

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
                .themedListRow()
            }
            .themedListScreen()
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
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12)))
                    .overlay(
                        RoundedRectangle(cornerRadius: appTheme.innerRadius(12))
                            .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    )
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, 4)
    }
}
