@testable import DieKarteiCore
import GermanVoice
import SwiftUI

/// Zahlen-Diktat from the Hören room: hear a number, type it. The round, the spelling and the
/// answer check are the iOS engine's (HoerenNumberGenerator, HoerenNumberAnswer); the voice is
/// Android's own German TextToSpeech.
struct HoerenView: View {
    @AppStorage("hoerenLevel") var levelRaw = CEFRLevel.a1.rawValue
    @State var kind: HoerenNumberKind = .small

    var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .a1 }

    var body: some View {
        List {
            Section {
                Picker("Niveau", selection: $levelRaw) {
                    ForEach([CEFRLevel.a1, .a2, .b1]) { level in
                        Text(level.rawValue).tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Zahlen-Diktat") {
                ForEach(HoerenNumberKind.kinds(for: level)) { kind in
                    NavigationLink {
                        ZahlenDiktatView(kind: kind, level: level)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.germanLabel)
                            Text(kind.englishLabel).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Hören")
    }
}

struct ZahlenDiktatView: View {
    let kind: HoerenNumberKind
    let level: CEFRLevel
    @State var items: [HoerenNumberItem] = []
    @State var index = 0
    @State var right = 0
    @State var typed = ""
    @State var verdict: Bool?

    var body: some View {
        VStack(spacing: 18) {
            if index < items.count {
                let item = items[index]
                ScoreLine(done: index, right: right, total: items.count)
                HStack(spacing: 12) {
                    Button { GermanVoice.shared.speak(item.spoken, slow: false) } label: {
                        // SkipUI tints symbols with foregroundStyle (else Color.primary), not with
                        // the prominent button's content colour, so set it as iOS draws it.
                        Label("Anhören", systemImage: "play.fill")
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { GermanVoice.shared.speak(item.spoken, slow: true) } label: {
                        Text("Langsam").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                TextField("Was hast du gehört?", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                    .disabled(verdict != nil)
                if let verdict {
                    VStack(spacing: 6) {
                        Text(verdict ? "Richtig!" : "Gehört: \(item.written)")
                            .font(.headline)
                            .foregroundStyle(verdict ? Color.green : Color.red)
                        Text(item.spelled).font(.footnote).multilineTextAlignment(.center)
                        Button("Weiter") { next() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button("Prüfen") { check(item) }
                        .buttonStyle(.borderedProminent)
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Text("\(right) von \(items.count) richtig").font(.title2)
                Button("Neue Runde") { newRound() }.buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
        .navigationTitle(kind.germanLabel)
        .onAppear { StudyLog.shared.begin(); if items.isEmpty { newRound() } }
    }

    func check(_ item: HoerenNumberItem) {
        let ok = HoerenNumberAnswer.parse(typed, kind: kind)
            .map { HoerenNumberAnswer.matches($0, expected: item.value, kind: kind) } ?? false
        if ok { right += 1 }
        verdict = ok
    }

    func next() {
        // An item heard and answered, right or wrong (iOS: listening is the work).
        if verdict != nil { StudyLog.shared.answered(.hoeren(1)) }
        typed = ""
        verdict = nil
        index += 1
        if index < items.count { GermanVoice.shared.speak(items[index].spoken, slow: false) }
    }

    func newRound() {
        StudyLog.shared.begin()
        var rng = SystemRandomNumberGenerator()
        items = HoerenNumberGenerator.round(kinds: [kind], level: level, mode: .bare, count: 10, rng: &rng)
        index = 0
        right = 0
        typed = ""
        verdict = nil
        if let first = items.first { GermanVoice.shared.speak(first.spoken, slow: false) }
    }
}
