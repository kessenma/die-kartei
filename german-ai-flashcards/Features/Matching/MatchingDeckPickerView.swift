//
//  MatchingDeckPickerView.swift
//  german-ai-flashcards
//
//  Pushed from the Home ▸ Vocabulary "Card Matching" tile. Lists the decks worth a matching
//  round — bundled Goethe levels (always available) plus the learner's own saved decks with
//  enough pairs — and launches the immersive `.matching` game through the shared `ActivityRouter`.
//  Round size + tricky-pair repetition come from Settings ▸ Cards ▸ Card Matching; the progress
//  section on top reads the persisted `MatchingRound` / `MatchingPairStat` history.
//

import SwiftUI
import SwiftData

struct MatchingDeckPickerView: View {
    /// A round needs a few distinct pairs to be fun; below this a deck is hidden from the picker.
    private static let minPairs = 4

    var modelManager: MLXModelManager

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]
    @Query(sort: \MatchingRound.date, order: .reverse) private var rounds: [MatchingRound]
    @Query private var pairStats: [MatchingPairStat]
    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    private var deckStore: DeckStore { DeckStore(modelContext: modelContext) }

    private var playableDecks: [SavedDeck] {
        decks.filter { $0.isBrowsableContent && $0.cards.count >= Self.minPairs }
    }

    private var trickyCount: Int { pairStats.filter(\.isTricky).count }

    /// First-try accuracy across the most recent rounds, as a whole percent.
    private var recentAccuracy: Int? {
        let recent = rounds.prefix(10)
        let pairs = recent.reduce(0) { $0 + $1.pairCount }
        guard pairs > 0 else { return nil }
        let hits = recent.reduce(0) { $0 + $1.firstTryCount }
        return Int((Double(hits) / Double(pairs) * 100).rounded())
    }

    var body: some View {
        List {
            if !rounds.isEmpty {
                progressSection
            }
            Section {
                ForEach(GoetheLevel.allCases) { level in
                    Button {
                        router.launch(.matching(deckStore.goetheMatchingSession(
                            level: level,
                            maxPairs: modelManager.matchingPairCount,
                            trickyFirst: modelManager.matchingTrickyFirst
                        )))
                    } label: {
                        pickerRow("Goethe \(level.rawValue) Vocabulary", level.examName, "text.book.closed")
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Goethe Vocabulary")
            } footer: {
                Text("A quick recognition warm-up — match each German word to its English meaning against the clock.")
            }

            if !playableDecks.isEmpty {
                Section("Your Decks") {
                    ForEach(playableDecks, id: \.id) { deck in
                        Button {
                            router.launch(.matching(deckStore.matchingSession(
                                from: deck,
                                maxPairs: modelManager.matchingPairCount,
                                trickyFirst: modelManager.matchingTrickyFirst
                            )))
                        } label: {
                            pickerRow(deck.topic, "\(deck.cards.count) cards", "rectangle.stack")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Card Matching")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
    }

    // MARK: - Progress

    private var progressSection: some View {
        Section {
            HStack(spacing: 0) {
                progressStat("\(rounds.count)", rounds.count == 1 ? "round" : "rounds")
                if let accuracy = recentAccuracy {
                    Divider().padding(.vertical, 6)
                    progressStat("\(accuracy)%", "first-try, last 10")
                }
                Divider().padding(.vertical, 6)
                progressStat("\(trickyCount)", trickyCount == 1 ? "tricky pair" : "tricky pairs")
            }

            NavigationLink {
                TrickyPairsView()
            } label: {
                Label(
                    trickyCount == 0 ? "Tricky pairs" : "Review your tricky pairs",
                    systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
                )
                .font(.subheadline)
            }
        } header: {
            Text("Your Progress")
        }
    }

    private func progressStat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func pickerRow(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
