//
//  DeckMixPickerSheet.swift
//  german-ai-flashcards
//
//  Library ▸ Decks ▸ Mix decks: tick several saved decks and study them as one session in the
//  regular player (`DeckStore.mixSession`). The last mix is remembered on this device, so a
//  learner who always studies the same few decks together opens the sheet with them ticked.
//

import SwiftUI
import SwiftData

struct DeckMixPickerSheet: View {
    /// The decks on offer, in the Library's order.
    let decks: [SavedDeck]
    /// Called with the chosen decks once the learner taps Study. The sheet dismisses itself first.
    let onStudy: ([SavedDeck]) -> Void

    @Environment(\.dismiss) private var dismiss
    /// The last mix, as comma-joined deck UUIDs. A per-device convenience only.
    @AppStorage("deckMix.lastSelection") private var lastSelection = ""
    @State private var selected: Set<UUID> = []

    private var picked: [SavedDeck] { decks.filter { selected.contains($0.id) } }
    private var cardCount: Int { picked.reduce(0) { $0 + $1.cards.count } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(decks, id: \.id) { deck in
                        Button {
                            if selected.remove(deck.id) == nil { selected.insert(deck.id) }
                        } label: {
                            row(deck)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("The cards play as one session, in the study mode you pick next. Each deck keeps its own progress and is credited for its cards. Closing a mix ends it; ratings you already gave are kept.")
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle("Mix Decks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selected.isEmpty {
                        Button("Select All") { selected = Set(decks.map(\.id)) }
                    } else {
                        Button("Clear") { selected = [] }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { studyBar }
        }
        .onAppear {
            let available = Set(decks.map(\.id))
            selected = Set(lastSelection.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
                .intersection(available)
        }
    }

    private func row(_ deck: SavedDeck) -> some View {
        let isOn = selected.contains(deck.id)
        return HStack(spacing: 12) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.topic)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("\(deck.cards.count) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let symbol = deck.kindSymbol {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var studyBar: some View {
        Button {
            let chosen = picked
            lastSelection = chosen.map(\.id.uuidString).joined(separator: ",")
            dismiss()
            onStudy(chosen)
        } label: {
            Label(
                picked.count < 2 ? "Pick two or more decks" : "Study \(picked.count) decks · \(cardCount) cards",
                systemImage: "play.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(picked.count < 2)
        .padding()
        .background(.bar)
    }
}
