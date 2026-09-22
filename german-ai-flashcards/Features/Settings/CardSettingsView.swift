import SwiftUI
import UIKit   // VoiceGuideSheet (below) uses UIApplication.openSettingsURLString

/// Learning ▸ Flashcards settings: flashcard study style plus the game-mechanic toggles (haptics,
/// card matching, der/die/das coaching). Voice, reminders, and sources each moved to their own
/// App/About screen in the theme-upgrade Settings IA.
struct CardSettingsView: View {
    @Bindable var modelManager: MLXModelManager

    /// Shared with the same picker in the deck-creation options.
    @AppStorage(CardImageTiming.defaultsKey) private var imageTiming: CardImageTiming = .keptCards

    // Shared with the player's own pickers and the Wortschatz hub through the same keys.
    @AppStorage(CardStudyPrefs.germanFirstKey) private var germanFirst = true
    @AppStorage(CardStudyPrefs.articleQuizKey) private var articleQuiz = true
    @AppStorage(CardStudyPrefs.repeatMissedKey) private var repeatMissed = true
    @AppStorage(WortschatzPrefs.styleKey) private var wortschatzStyleRaw = FlashcardStyle.anki.rawValue
    @AppStorage(WortschatzPrefs.newPerDayKey) private var newPerDay = WortschatzPrefs.newPerDayDefault
    @AppStorage(WortschatzPrefs.sessionCapKey) private var sessionCap = WortschatzPrefs.sessionCapDefault

    private var wortschatzStyle: FlashcardStyle {
        FlashcardStyle(rawValue: wortschatzStyleRaw).flatMap { $0 == .default ? nil : $0 } ?? .anki
    }

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

                Picker("Front side", selection: $germanFirst) {
                    Text("German").tag(true)
                    Text("English").tag(false)
                }
                .pickerStyle(.segmented)
                Text("Which side a card shows first. You can still switch it inside any deck.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Ask der / die / das first", isOn: $articleQuiz)
                Text("Nouns hide their article on the German side until you flip, so every noun is a small gender check.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Repeat missed cards", isOn: $repeatMissed)
                Text("A card you mark Didn't know comes back a few cards later in the same session.")
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
                Picker("Study with", selection: $wortschatzStyleRaw) {
                    Text(FlashcardStyle.anki.rawValue).tag(FlashcardStyle.anki.rawValue)
                    Text(FlashcardStyle.leitner.rawValue).tag(FlashcardStyle.leitner.rawValue)
                }
                .pickerStyle(.segmented)
                Text(wortschatzStyle.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("New words per day", selection: $newPerDay) {
                    ForEach(WortschatzPrefs.newPerDayOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                Text("How many unseen Goethe words a session may introduce. Lower it if reviews pile up; the box offers ten more whenever you want them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Cards per session", selection: $sessionCap) {
                    ForEach(WortschatzPrefs.sessionCapOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                Text("Due reviews come first, then new words up to the daily budget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Wortschatz · Goethe").themedSectionHeader()
            }
            .themedListRow()

            Section {
                Picker("Game vibrations", selection: $modelManager.hapticFeedbackMode) {
                    ForEach(HapticFeedbackMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(modelManager.hapticFeedbackMode.description + " Covers the matching, der/die/das, and grammar drills, plus two soft ticks in chat: when recording starts or stops, and when a spoken turn lands clean. Stories and flashcards never vibrate.")
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
                    SettingsStepRow(1, "Open the Settings app and tap the search bar at the bottom.",
                                    image: "voice-guide-settings-search")
                    SettingsStepRow(2, "Type “voice”, then tap Voices under Accessibility → Live Speech.",
                                    image: "voice-guide-voice-search")
                } header: {
                    Text("Quickest: search Settings").themedSectionHeader()
                }
                .themedListRow()

                Section {
                    SettingsStepRow(1, "Or open Settings and tap Accessibility.",
                                    image: "voice-guide-accessibility")
                    SettingsStepRow(2, "Under Speech, tap Live Speech.",
                                    image: "voice-guide-live-speech")
                } header: {
                    Text("Or browse to it").themedSectionHeader()
                }
                .themedListRow()

                Section {
                    SettingsStepRow(1, "Scroll to Preferred Voices and tap Add Preferred Voice…",
                                    image: "voice-guide-add-voice")
                    SettingsStepRow(2, "Choose German. On an English iPhone it's listed as “German”, not “Deutsch”.",
                                    image: "voice-guide-german")
                    SettingsStepRow(3, "Tap the cloud icon next to a voice to download its Enhanced or Premium version. Skip the Siri voices (crossed out) — apps can't use those.",
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

}
