@testable import DieKarteiCore
import GermanVoice
import SwiftUI

/// The Wortschatz deck with spaced repetition: what's due, then a few new words. Rated with the
/// iOS app's four buttons, scheduled by the shared SM-2 code (`SRSScheduling`), saved on device.
struct KartenView: View {
    @AppStorage("level") var levelRaw = GoetheLevel.a1.rawValue
    @State var store = StudyStore.shared
    @State var deck: [A1Entry] = []
    @State var index = 0
    @State var flipped = false
    @State var rated = 0
    /// The session's place in today's log. iOS logs a finished session and pauses the rest to
    /// resume later; Android has no pause yet, so a session left early is logged on leaving.
    @State var studyRound = StudyRound { .cards($0) }
    @Environment(\.colorScheme) var scheme

    var level: GoetheLevel { GoetheLevel(rawValue: levelRaw) ?? .a1 }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Niveau", selection: $levelRaw) {
                ForEach(GoetheLevel.allCases) { level in
                    Text(level.rawValue).tag(level.rawValue)
                }
            }
            .pickerStyle(.segmented)

            let stats = store.stats(for: level)
            Text("\(stats.seen) von \(stats.total) gelernt · \(stats.due) fällig")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if index < deck.count {
                card(deck[index])
                    .onTapGesture { withAnimation { flipped.toggle() } }

                Text("Karte \(index + 1) von \(deck.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if flipped {
                    ratingButtons(for: deck[index])
                } else {
                    Button("Umdrehen") { withAnimation { flipped = true } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Spacer()
                Text(rated == 0 ? "Nichts fällig." : "Fertig für jetzt: \(rated) Karten.")
                    .font(.title3)
                Button("Weiter lernen") { reload() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Karteikarten")
        .onAppear { if deck.isEmpty { reload() } }
        .onDisappear { studyRound.finish() }
        .onChange(of: levelRaw) { _, _ in reload() }
    }

    func ratingButtons(for entry: A1Entry) -> some View {
        let previews = store.previews(for: entry, level: level, index: index)
        return HStack(spacing: 8) {
            ForEach(AnkiRating.allCases, id: \.rawValue) { rating in
                Button {
                    store.rate(entry, level: level, index: index, rating: rating)
                    studyRound.add()
                    if index + 1 == deck.count { studyRound.finish() }
                    rated += 1
                    flipped = false
                    index += 1
                } label: {
                    VStack(spacing: 2) {
                        Text(rating.label).font(.caption).lineLimit(1)
                        Text(previews[rating] ?? "").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(ratingColor(rating))
            }
        }
    }

    func ratingColor(_ rating: AnkiRating) -> Color {
        switch rating {
        case .again: Color.red
        case .hard: Color.orange
        case .good: Color.green
        case .easy: Color.blue
        }
    }

    func card(_ entry: A1Entry) -> some View {
        VStack(spacing: 12) {
            GenderedWord(word: entry.word, article: entry.article)
                .font(.largeTitle)
            Button {
                GermanVoice.shared.speak([entry.article, entry.word].compactMap { $0 }.joined(separator: " "), slow: false)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            if flipped {
                Text(entry.translation ?? "–")
                    .font(.title2)
                if let example = entry.example, !example.isEmpty {
                    Text(example)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Tippen zum Umdrehen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardTint(entry).opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardTint(entry), lineWidth: 2)
        )
    }

    /// The card's edge takes the noun's gender colour, as on iOS.
    func cardTint(_ entry: A1Entry) -> Color {
        guard let article = entry.article, let gender = Gender(article: article) else { return Color.gray }
        return AndroidPalette.gender(gender, dark: scheme == .dark)
    }

    func reload() {
        studyRound.finish()
        studyRound.start()
        deck = store.session(for: level)
        index = 0
        rated = 0
        flipped = false
    }
}
