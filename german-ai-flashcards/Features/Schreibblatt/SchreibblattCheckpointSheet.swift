//
//  SchreibblattCheckpointSheet.swift
//  german-ai-flashcards
//
//  What Fertig opens, and what comes back after the flashcards: the words just written, offered
//  as cards, one writing number (`SchreibblattStatCard`), and the way on. For a part of a bigger
//  set (`SchreibblattParts`) it shows how far through the set the learner is, offers the last two
//  parts and everything so far, and leads with the next part to write. Once every part is done
//  (or for a sheet on its own) it leads with the last round of cards over the whole set, and
//  "Abschließen" finishes, which opens the finish screen (`SchreibblattCelebration`).
//
//  Back from the cards (`practised`), going on leads: "Weiter: Teil 4", or "Abschließen" at the
//  end, with the practice offers kept below for another round.
//
//  The sheet only says what was chosen (`Choice`) and closes; the screen acts once it is down
//  (`onDismiss`), because the flashcard player is the shell's cover and a cover cannot open over a
//  sheet still on its way down.
//

import SwiftUI

/// Everything the checkpoint shows, read once when it opens.
struct SchreibblattCheckpoint: Identifiable {
    let id = UUID()
    /// "Teil 3 von 5 geschafft", or "Fertig" for a sheet on its own.
    let title: String
    /// "30 of 50 words written · 3 of 5 parts".
    let subtitle: String
    /// Parts done out of all of them; nil for a sheet on its own.
    let progress: Double?
    let options: [SchreibblattParts.PracticeOption]
    /// The part to write next, and its "Teil 4 von 5". Nil once every part is done.
    let next: SchreibblattSheet?
    /// Back from the flashcards rather than from Fertig.
    var practised = false
    /// The writing numbers, one shown at a time.
    var stats: SchreibblattStats?

    enum Choice {
        case practice(SchreibblattParts.PracticeOption)
        case next(SchreibblattSheet)
        /// Finish the set (or the sheet): the finish screen, then back out of the flow.
        case finish
    }

    /// Nothing left to write: the way out is finishing.
    var isFinal: Bool { next == nil }

    /// The last round: the widest offer (the whole set, or everything so far).
    var finalRound: SchreibblattParts.PracticeOption? { isFinal ? options.last : nil }
}

struct SchreibblattCheckpointSheet: View {
    let checkpoint: SchreibblattCheckpoint
    let onChoose: (SchreibblattCheckpoint.Choice) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The last round leads at the top, so it is not listed again below.
    private var leadingRound: SchreibblattParts.PracticeOption? {
        checkpoint.practised ? nil : checkpoint.finalRound
    }

    private var listedOptions: [SchreibblattParts.PracticeOption] {
        checkpoint.options.filter { $0.id != leadingRound?.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                    if let stats = checkpoint.stats, !stats.stats.isEmpty {
                        SchreibblattStatCard(stats: stats)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                    }
                    // Up here, not under the offers: going on is the main way out, and a short
                    // sheet would hide it below the fold.
                    wayOn
                } footer: {
                    if checkpoint.next != nil {
                        Text("Your place is kept either way: the set's row in Schreibblatt opens the next part too.")
                    } else if leadingRound != nil {
                        Text(checkpoint.progress != nil
                             ? "One last round over every word, then Abschließen. Or finish now."
                             : "Practice the words as flashcards, then Abschließen. Or finish now.")
                    }
                }
                .themedListRow()

                if !listedOptions.isEmpty {
                    Section {
                        ForEach(listedOptions) { option in
                            Button {
                                choose(.practice(option))
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text(option.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "rectangle.on.rectangle.angled")
                                        .foregroundStyle(SchreibblattTile.tint)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Practice these words as flashcards")
                        }
                    } header: {
                        Text(checkpoint.practised ? "Nochmal üben · Again" : "Karten üben · Practice")
                            .themedSectionHeader()
                    } footer: {
                        Text("Only these words go into the flashcards, nothing else from their decks.")
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle("Checkpoint")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .tint(SchreibblattTile.tint)
        // An iPad's form sheet at medium height clips the offers; a phone's half sheet is fine.
        .presentationDetents(ThisDevice.kind == .iPad ? [.large] : [.medium, .large])
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(checkpoint.title, systemImage: checkpoint.practised ? "rectangle.on.rectangle.angled" : "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(checkpoint.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let progress = checkpoint.progress {
                ProgressView(value: progress)
                    .tint(SchreibblattTile.tint)
                    .accessibilityLabel("Parts done")
            }
        }
        .padding(.vertical, 4)
    }

    /// The main way on: the next part; else the last round and finishing; else finishing.
    @ViewBuilder
    private var wayOn: some View {
        if let next = checkpoint.next {
            primary("Weiter: \(next.partLabel)", symbol: "arrow.right.circle.fill",
                    hint: "Opens the next part to write") { choose(.next(next)) }
        } else if let round = leadingRound {
            let isSet = checkpoint.progress != nil
            primary(isSet ? "Letzte Runde: \(round.title)" : "Karten üben · \(round.detail)",
                    symbol: "rectangle.on.rectangle.angled",
                    hint: "Practice these words as flashcards, then finish") { choose(.practice(round)) }
            Button {
                choose(.finish)
            } label: {
                Label("Abschließen · Finish", systemImage: "flag.checkered")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Finishes without the flashcards")
        } else {
            primary("Abschließen · Finish", symbol: "flag.checkered",
                    hint: "Finishes and goes back to your sheets") { choose(.finish) }
        }
    }

    private func primary(_ title: String, symbol: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(SchreibblattTile.tint)
        .accessibilityHint(hint)
    }

    private func choose(_ choice: SchreibblattCheckpoint.Choice) {
        onChoose(choice)
        dismiss()
    }
}
