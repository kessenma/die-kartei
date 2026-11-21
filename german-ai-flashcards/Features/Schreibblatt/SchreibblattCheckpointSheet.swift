//
//  SchreibblattCheckpointSheet.swift
//  german-ai-flashcards
//
//  What Fertig opens: the words just written, offered as flashcards. For a part of a bigger set
//  (`SchreibblattParts`) it also shows how far through the set the learner is, offers the last two
//  parts and everything so far, and the next part to write.
//
//  The sheet only says what was chosen (`Choice`) and closes; the screen acts once it is down
//  (`onDismiss`), because the flashcard player is the shell's cover and a cover cannot open over a
//  sheet still on its way down.
//

import SwiftUI

/// Everything the checkpoint shows, read once when Fertig is tapped.
struct SchreibblattCheckpoint: Identifiable {
    let id = UUID()
    /// "Teil 3 von 5 geschafft", or "Fertig" for a sheet on its own.
    let title: String
    /// "30 of 50 words written · 3 of 5 parts".
    let subtitle: String
    /// Parts done out of all of them; nil for a sheet on its own.
    let progress: Double?
    let options: [SchreibblattParts.PracticeOption]
    /// The part to write next, and its "Teil 4 von 5".
    let next: SchreibblattSheet?

    enum Choice {
        case practice(SchreibblattParts.PracticeOption)
        case next(SchreibblattSheet)
    }

    /// Nothing to offer: no card left to practise and no part left to write.
    var isEmpty: Bool { options.isEmpty && next == nil }
}

struct SchreibblattCheckpointSheet: View {
    let checkpoint: SchreibblattCheckpoint
    let onChoose: (SchreibblattCheckpoint.Choice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                    // Up here, not under the offers: going on is the main way out of a part, and
                    // a short sheet would hide it below the fold.
                    if let next = checkpoint.next {
                        Button {
                            choose(.next(next))
                        } label: {
                            Label("Weiter: \(next.partLabel)", systemImage: "arrow.right.circle.fill")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SchreibblattTile.tint)
                        .accessibilityHint("Opens the next part to write")
                    }
                } footer: {
                    if checkpoint.next != nil {
                        Text("Your place is kept either way: the set's row in Schreibblatt opens the next part too.")
                    }
                }
                .themedListRow()

                if !checkpoint.options.isEmpty {
                    Section {
                        ForEach(checkpoint.options) { option in
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
                        Text("Karten üben · Practice").themedSectionHeader()
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
            Label(checkpoint.title, systemImage: "checkmark.seal.fill")
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

    private func choose(_ choice: SchreibblattCheckpoint.Choice) {
        onChoose(choice)
        dismiss()
    }
}
