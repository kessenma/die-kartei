//
//  GameShortfallSheet.swift
//  german-ai-flashcards
//
//  What happens when the source the learner picked doesn't have enough playable words.
//
//  It offers to top up rather than refusing: a deck of eight cards is a perfectly good start for a
//  word search, it just needs a few more words to hide. Borrowed words are marked in the pool so
//  the round's summary can say where they came from — the learner should never be told they
//  practised their own deck when half the grid came from a Goethe list.
//

import SwiftUI
import SwiftData

struct GameShortfallSheet: View {
    let kind: SpielKind
    let row: GameSourceSummary
    let decks: [SavedDeck]
    let courses: [ClassCourse]
    /// Called with a topped-up pool that is ready to play.
    let onStart: (GameWordPool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    private var requirements: GameWordRequirements { kind.requirements }

    private var needed: Int {
        max(0, requirements.wordCount.lowerBound - row.usableCount)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.title).font(.subheadline).fontWeight(.semibold)
                        Text("\(row.usableCount) playable \(row.usableCount == 1 ? "word" : "words") · \(kind.germanTitle) needs \(requirements.wordCount.lowerBound)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(requirements.blurb)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Zu wenige Wörter · Not enough words").themedSectionHeader()
                }
                .themedListRow()

                Section {
                    ForEach(GoetheLevel.allCases) { level in
                        Button {
                            topUp(from: level)
                        } label: {
                            SourcePickerRow(
                                title: "Aus Goethe \(level.rawValue)",
                                subtitle: "Add \(needed) \(needed == 1 ? "word" : "words") from \(level.examName)",
                                icon: "text.book.closed"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Auffüllen · Top up").themedSectionHeader()
                } footer: {
                    Text("Borrowed words are marked in the round's summary, so you can tell them from your own.")
                        .font(.caption2)
                }
                .themedListRow()

                if otherDecks.count > 0 {
                    Section {
                        ForEach(otherDecks, id: \.id) { deck in
                            Button {
                                topUp(with: deck)
                            } label: {
                                SourcePickerRow(title: deck.topic,
                                                subtitle: "Play both decks together",
                                                icon: "square.stack.3d.up")
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Mit einem Stapel · With another deck").themedSectionHeader()
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle(kind.germanTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    /// Decks other than the one that fell short, that have something to contribute.
    private var otherDecks: [SavedDeck] {
        guard case .deck(let picked) = row.source else { return [] }
        return decks.filter { $0.isBrowsableContent && $0.id != picked && !$0.gameWords.isEmpty }
    }

    // MARK: - Top-up

    private func topUp(from level: GoetheLevel) {
        var pool = base()
        let have = Set(pool.words.map(\.id))
        let extra = GameWordFitter
            .fit(GameWordResolver.goetheCandidates(level).filter { !have.contains($0.id) },
                 to: requirements)
            .usable
            .shuffled()
            .prefix(needed)
        pool.words += extra
        pool.toppedUp = .goethe(level)
        finish(pool)
    }

    private func topUp(with deck: SavedDeck) {
        var pool = base()
        let have = Set(pool.words.map(\.id))
        pool.words += deck.gameWords.filter { !have.contains($0.id) }
        pool.toppedUp = .moreDecks
        // Two decks are no longer one deck, so the result can't be credited to either.
        pool.deckID = nil
        pool.label = "\(pool.label) + \(deck.topic)"
        finish(pool)
    }

    private func base() -> GameWordPool {
        GameWordResolver.pool(for: row.source, decks: decks, courses: courses)
    }

    private func finish(_ pool: GameWordPool) {
        dismiss()
        // Let the sheet finish dismissing before the player covers the screen — the same ordering
        // `ActivityCategoryView` uses for the document-deck sheet.
        DispatchQueue.main.async { onStart(pool) }
    }
}
