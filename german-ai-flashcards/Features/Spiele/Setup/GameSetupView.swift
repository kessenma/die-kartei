//
//  GameSetupView.swift
//  german-ai-flashcards
//
//  The one setup screen all three Spiele share: pick where the words come from, set the game's own
//  options, start. Each game wraps this with ~80 lines of its own toggles rather than keeping a
//  third near-copy of `ArticleGameSetupView`.
//
//  The round is composed *here*, before the game is launched, so the player never has an error
//  state: by the time the full-screen cover appears, the words are chosen and (for the grid games)
//  the puzzle is built. "Not enough words" is a question answered on the one screen that can
//  actually do something about it.
//

import SwiftUI
import SwiftData

struct GameSetupView<Options: View>: View {
    let kind: SpielKind
    /// The game's own toggles, shown in their own section.
    @ViewBuilder var options: () -> Options
    /// The single launch funnel. Called with a pool already fitted to this game's limits.
    let start: (GameWordPool) -> Void

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]
    @Query(sort: \ClassCourse.name) private var courses: [ClassCourse]
    @Environment(\.appTheme) private var appTheme

    /// Resolved off the render path: deck decoding and the merged Goethe index are both too slow
    /// for a view body, the same reason `ArticleGameSetupView` holds its pools in `@State`.
    @State private var summaries: [GameSourceSummary] = []
    @State private var resolved = false
    /// The source the learner tapped that didn't have enough words.
    @State private var shortfall: GameSourceSummary?
    @State private var errorMessage: String?

    private var requirements: GameWordRequirements { kind.requirements }

    private var goetheRows: [GameSourceSummary] {
        summaries.filter { if case .goethe = $0.source { true } else { false } }
    }
    private var deckRows: [GameSourceSummary] {
        summaries.filter { if case .deck = $0.source { true } else { false } }
    }
    private var courseRows: [GameSourceSummary] {
        summaries.filter { if case .course = $0.source { true } else { false } }
    }

    var body: some View {
        List {
            Section {
                options()
            } header: {
                Text("Einstellungen · Options").themedSectionHeader()
            }
            .themedListRow()

            sourceSection(goetheRows, header: "Goethe · Wortlisten",
                          footer: "Works before you have built a single deck.")

            if !deckRows.isEmpty {
                sourceSection(deckRows, header: "Deine Stapel · Your decks", footer: nil)
            }
            if !courseRows.isEmpty {
                sourceSection(courseRows, header: "Deutschkurs", footer: nil)
            }

            if !resolved {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Wörter zählen …").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .themedListRow()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle(kind.germanTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // `summaries` is rebuilt on every appearance: a deck may have gained cards since.
            summaries = GameWordResolver.summaries(decks: decks, courses: courses,
                                                   requirements: requirements)
            resolved = true
        }
        .sheet(item: $shortfall) { row in
            GameShortfallSheet(kind: kind, row: row, decks: decks, courses: courses) { pool in
                launch(pool)
            }
        }
    }

    @ViewBuilder
    private func sourceSection(_ rows: [GameSourceSummary], header: String,
                               footer: String?) -> some View {
        Section {
            ForEach(rows) { row in
                Button {
                    choose(row)
                } label: {
                    SourcePickerRow(title: row.title, subtitle: row.subtitle,
                                    icon: icon(for: row.source), isEnough: row.isEnough)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(header).themedSectionHeader()
        } footer: {
            if let footer { Text(footer).font(.caption2) }
        }
        .themedListRow()
    }

    private func icon(for source: GameWordSource) -> String {
        switch source {
        case .goethe:   "text.book.closed"
        case .deck:     "rectangle.stack"
        case .deckMix:  "square.stack.3d.up"
        case .course:   "graduationcap"
        case .aiTopic:  "sparkles"
        }
    }

    // MARK: - Starting a round

    private func choose(_ row: GameSourceSummary) {
        guard row.isEnough else {
            // Not enough words: hand it to the sheet that can offer a top-up, rather than
            // refusing with a message the learner can't act on.
            shortfall = row
            return
        }
        let pool = GameWordResolver.pool(for: row.source, decks: decks, courses: courses)
        launch(pool)
    }

    private func launch(_ pool: GameWordPool) {
        let fit = GameWordFitter.fit(pool.words, to: requirements)
        guard let words = GameWordFitter.round(requirements,
                                               canBuild: { kind.canBuild($0, seed: $1) },
                                               from: fit,
                                               seed: UInt64.random(in: 0..<UInt64.max))
        else {
            errorMessage = "Those words wouldn't make a round. \(requirements.blurb)"
            return
        }
        var round = pool
        round.words = words
        errorMessage = nil
        start(round)
    }
}
