//
//  DeckImportSheet.swift
//  german-ai-flashcards
//
//  What the learner sees when they open a `.kartei` file from another device: what is in it, and
//  — when they already have this deck — whether to replace it or keep both.
//
//  The sheet is deliberately the only way a deck ever enters the store from a file. Importing on
//  open with a toast afterwards would be one tap fewer and would also mean a stray tap in Files
//  could overwrite a studied deck's scheduling with an older copy's.
//

import SwiftUI
import SwiftData

/// A decoded file waiting for the learner's decision. Identifiable so it can drive a `.sheet(item:)`.
struct DeckImportRequest: Identifiable {
    let id = UUID()
    let envelope: DeckTransferEnvelope
}

struct DeckImportSheet: View {
    let request: DeckImportRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var existing: SavedDeck?
    @State private var imported = false

    private var deck: DeckTransferEnvelope.Deck { request.envelope.deck }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Topic", value: deck.topic)
                    LabeledContent("Cards", value: "\(deck.cards.count)")
                    if request.envelope.includesProgress {
                        LabeledContent("Progress") {
                            Label("Included", systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.green)
                        }
                    }
                    LabeledContent("Shared", value: request.envelope.exportedAt, format: .dateTime.month(.abbreviated).day().year())
                } header: {
                    Text("Deck importieren · Import deck")
                        .themedSectionHeader()
                }

                if !request.envelope.includesImages && deck.cards.count > 0 {
                    Section {
                        Label(
                            "Card pictures stay on the device that drew them. You can illustrate this deck again here.",
                            systemImage: "photo.badge.exclamationmark"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if existing != nil {
                    Section {
                        Button {
                            perform(.replace)
                        } label: {
                            Label("Replace my copy", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            perform(.keepBoth)
                        } label: {
                            Label("Keep both", systemImage: "rectangle.stack.badge.plus")
                        }
                    } header: {
                        Text("You already have this deck")
                            .themedSectionHeader()
                    } footer: {
                        Text("Replacing takes the arriving deck's cards and progress. Keeping both leaves your copy untouched and adds a second one.")
                    }
                } else {
                    Section {
                        Button {
                            perform(.keepBoth)
                        } label: {
                            Label("Add to my decks", systemImage: "tray.and.arrow.down")
                        }
                    }
                }
            }
            .themedListScreen()
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                existing = DeckImporter.existingDeck(for: request.envelope, in: modelContext)
            }
        }
    }

    private func perform(_ mode: DeckImporter.Mode) {
        guard !imported else { return }
        imported = true
        DeckImporter.insert(request.envelope, mode: mode, into: modelContext)
        dismiss()
    }
}
