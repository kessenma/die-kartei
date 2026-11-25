@testable import DieKarteiCore
import SwiftUI

/// Flashcards from a Goethe list: the German word on the front, the translation and example on
/// the back. No spaced repetition yet: the shared Leitner/SM-2 code still takes the SwiftData
/// `SavedCard`, so for now a round is the list shuffled, with a count of what you knew.
struct KartenView: View {
    @AppStorage("level") var levelRaw = GoetheLevel.a1.rawValue
    @State var deck: [A1Entry] = []
    @State var index = 0
    @State var flipped = false
    @State var known = 0
    @Environment(\.colorScheme) var scheme

    private var level: GoetheLevel { GoetheLevel(rawValue: levelRaw) ?? .a1 }

    var body: some View {
        VStack(spacing: 20) {
            Picker("Niveau", selection: $levelRaw) {
                ForEach(GoetheLevel.allCases) { level in
                    Text(level.rawValue).tag(level.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if index < deck.count {
                card(deck[index])
                    .onTapGesture { withAnimation { flipped.toggle() } }

                Text("Karte \(index + 1) von \(deck.count) · gewusst: \(known)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Button("Nochmal") { next(knewIt: false) }
                        .buttonStyle(.bordered)
                    Button("Gewusst") { next(knewIt: true) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Spacer()
                Text(deck.isEmpty ? "" : "Runde fertig: \(known) von \(deck.count) gewusst.")
                Button("Neue Runde") { shuffle() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding()
        .navigationTitle("Karteikarten")
        .onAppear { if deck.isEmpty { shuffle() } }
        .onChange(of: levelRaw) { _, _ in shuffle() }
    }

    private func card(_ entry: A1Entry) -> some View {
        VStack(spacing: 12) {
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
                GenderedWord(word: entry.word, article: entry.article)
                    .font(.largeTitle)
                Text("Tippen zum Umdrehen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 260)
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
    private func cardTint(_ entry: A1Entry) -> Color {
        guard let article = entry.article, let gender = Gender(article: article) else { return Color.gray }
        return AndroidPalette.gender(gender, dark: scheme == .dark)
    }

    private func next(knewIt: Bool) {
        if knewIt { known += 1 }
        flipped = false
        index += 1
    }

    private func shuffle() {
        deck = Array(GoetheVocabService.entries(for: level).shuffled().prefix(20))
        index = 0
        known = 0
        flipped = false
    }
}
