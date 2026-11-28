@testable import DieKarteiCore
import GermanVoice
import SwiftUI

/// The Settings tab, grouped like the iOS app's (App / Learning / About). Only settings that do
/// something on Android are here; the rest are named at the bottom so nobody hunts for them.
struct SettingsView: View {
    /// "", "light" or "dark"; ContentView applies it.
    @AppStorage("appearance") var appearance = ""
    /// The level every Goethe screen opens at (Karteikarten, Wortschatz, Grammar, Spiele).
    @AppStorage("level") var levelRaw = GoetheLevel.a1.rawValue
    /// Hören keeps its own level (it goes past B1 on iOS); Your Level moves it along.
    @AppStorage("hoerenLevel") var hoerenLevelRaw = CEFRLevel.a1.rawValue

    var body: some View {
        List {
            Section("App") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                NavigationLink { VoiceSettingsView() } label: {
                    Text("Voice")
                }
            }
            Section("Learning") {
                Picker("Your Level", selection: $levelRaw) {
                    ForEach(GoetheLevel.allCases) { level in
                        Text(level.rawValue).tag(level.rawValue)
                    }
                }
                .onChange(of: levelRaw) { _, newValue in
                    hoerenLevelRaw = newValue
                    // iOS's level anchor, which chats start at (`ChatPrefs.level`).
                    UserDefaults.standard.set(newValue, forKey: ChatPrefs.levelKey)
                }
                NavigationLink { FlashcardsSettingsView() } label: {
                    Text("Flashcards")
                }
                NavigationLink { TutorModelView() } label: {
                    Text("Tutor Model")
                }
                NavigationLink { ConversationSettingsView() } label: {
                    Text("Conversation")
                }
            }
            Section("About") {
                NavigationLink { SourcesView() } label: {
                    Text("Sources & Credits")
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Self.version).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Not on Android yet: iCloud Sync, Reminders and themes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }
}

// MARK: - Voice

/// Settings ▸ Voice. The voice is Android's German text-to-speech, which is chosen and
/// downloaded in Android's own settings, so this screen plays a sample and links there.
struct VoiceSettingsView: View {
    @State var couldNotOpen = false

    static let sample = "Guten Tag! Ich lerne Deutsch mit der Kartei."

    var body: some View {
        List {
            Section {
                Button("Probehören") { GermanVoice.shared.speak(Self.sample, slow: false) }
                Button("Langsam") { GermanVoice.shared.speak(Self.sample, slow: true) }
            } footer: {
                Text("Die Kartei speaks with Android's German voice.")
            }
            Section {
                Button("Android voice settings") {
                    couldNotOpen = !GermanVoice.shared.openSystemVoiceSettings()
                }
            } footer: {
                Text(couldNotOpen
                     ? "This device has no text-to-speech settings screen."
                     : "Pick or download German voices there.")
            }
        }
        .navigationTitle("Voice")
    }
}

// MARK: - Flashcards

/// Settings ▸ Flashcards: iOS's Wortschatz settings (same keys, `WortschatzPrefs`), and starting a
/// deck over.
struct FlashcardsSettingsView: View {
    @AppStorage(WortschatzPrefs.newPerDayKey) var newPerDay = WortschatzPrefs.newPerDayDefault
    @AppStorage(WortschatzPrefs.sessionCapKey) var sessionCap = WortschatzPrefs.sessionCapDefault
    @State var store = StudyStore.shared
    /// Kept apart from the alert's flag: Compose clears the flag before the button's action
    /// runs, so the level has to outlive it.
    @State var levelToReset: GoetheLevel = .a1
    @State var confirmReset = false

    var body: some View {
        List {
            Section {
                Picker("New words per day", selection: $newPerDay) {
                    ForEach(WortschatzPrefs.newPerDayOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                Picker("Cards per session", selection: $sessionCap) {
                    ForEach(WortschatzPrefs.sessionCapOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
            } footer: {
                Text("Due cards come first, then new words, up to the day's new words.")
            }
            Section("Progress") {
                ForEach(GoetheLevel.allCases) { level in
                    let stats = store.stats(for: level)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Goethe \(level.rawValue)")
                            Text("\(stats.seen) von \(stats.total) gelernt")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset") {
                            levelToReset = level
                            confirmReset = true
                        }
                            .disabled(stats.seen == 0)
                    }
                }
            }
        }
        .navigationTitle("Flashcards")
        .alert("Start Goethe \(levelToReset.rawValue) over?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.reset(level: levelToReset) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every word in it goes back to new. This can't be undone.")
        }
    }
}

// MARK: - Sources

/// Settings ▸ Sources & Credits: the iOS screen's sections for the data Android ships.
struct SourcesView: View {
    var body: some View {
        List {
            Section("Goethe-Institut Word Lists") {
                Text("The A1, A2 and B1 decks are built from the official word lists the Goethe-Institut publishes for its exams.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("A1 · Start Deutsch 1", destination: URL(string: "https://www.goethe.de/pro/relaunch/prf/de/A1_SD1_Wortliste_02.pdf")!)
                Link("A2 · Goethe-Zertifikat A2", destination: URL(string: "https://www.goethe.de/pro/relaunch/prf/de/Goethe-Zertifikat_A2_Wortliste.pdf")!)
                Link("B1 · Goethe-Zertifikat B1", destination: URL(string: "https://www.goethe.de/pro/relaunch/prf/de/Goethe-Zertifikat_B1_Wortliste.pdf")!)
            }
            Section("Wortkiste") {
                Text("The plural and Perfekt forms on Goethe cards follow Wortkiste, an open-source word box for the same exams by matchaDataHub (MIT license).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("Wortkiste on GitHub", destination: URL(string: "https://github.com/matchaDataHub/wortkiste")!)
            }
            Section("Tatoeba") {
                Text("The Perfekt example sentences are real sentences by native speakers from the Tatoeba corpus (CC BY 2.0 FR).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("Tatoeba", destination: URL(string: "https://tatoeba.org")!)
            }
        }
        .navigationTitle("Sources & Credits")
    }
}
