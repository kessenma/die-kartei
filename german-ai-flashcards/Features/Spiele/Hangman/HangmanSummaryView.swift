//
//  HangmanSummaryView.swift
//  german-ai-flashcards
//
//  What the round came to. Lists every word with how it went, and says plainly where the words
//  came from — if half of them were borrowed to fill out a thin deck, the learner should not be
//  told they practised their own deck.
//

import SwiftUI

struct HangmanSummaryView: View {
    let session: HangmanSession
    let outcomes: [SpieleWordOutcome]
    let onDone: () -> Void

    @Environment(\.appTheme) private var appTheme

    private var solved: Int { outcomes.count { $0.solved } }
    private var clean: Int { outcomes.count { $0.clean } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        stat("\(solved)/\(outcomes.count)", "gelöst")
                        Divider().padding(.vertical, 6)
                        stat("\(clean)", clean == 1 ? "ohne Fehler" : "ohne Fehler")
                    }
                } header: {
                    Text("Ergebnis · Results").themedSectionHeader()
                } footer: {
                    if let toppedUp = session.topUpNote {
                        Text(toppedUp).font(.caption2)
                    }
                }
                .themedListRow()

                Section {
                    ForEach(outcomes) { outcome in
                        HStack(spacing: 10) {
                            Image(systemName: outcome.solved
                                  ? (outcome.clean ? "circle.fill" : "circle.lefthalf.filled")
                                  : "circle")
                                .font(.caption)
                                .foregroundStyle(outcome.solved ? AnyShapeStyle(.tint)
                                                                : AnyShapeStyle(.tertiary))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(outcome.word.display).font(.subheadline)
                                Text(outcome.word.english).font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if outcome.misses > 0 {
                                Text("\(outcome.misses)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Wörter · Words").themedSectionHeader()
                } footer: {
                    Text("A filled dot is a word you got with no misses and no hint.")
                        .font(.caption2)
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle(session.topic)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { onDone() }
                }
            }
        }
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
