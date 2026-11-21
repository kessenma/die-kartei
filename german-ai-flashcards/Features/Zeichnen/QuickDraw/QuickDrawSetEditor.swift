//
//  QuickDrawSetEditor.swift
//  german-ai-flashcards
//
//  A Quick Draw set: a name and the words in it, picked from every deck. The set points at cards,
//  so a word keeps its pictures and article; the store is read once on appear.
//

import SwiftData
import SwiftUI

struct QuickDrawSetEditor: View {
    let set: QuickDrawSet?
    var onSave: (QuickDrawSet) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var words: [ZeichnenWord] = []
    @State private var picked: [UUID] = []
    @State private var search = ""
    @State private var loaded = false

    private var pickedSet: Set<UUID> { Set(picked) }

    private var visible: [ZeichnenWord] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return words }
        return words.filter {
            $0.word.german.lowercased().contains(query) || $0.english.lowercased().contains(query)
                || $0.deckTitle.lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            Section {
                TextField("Name", text: $name)
            } footer: {
                Text("\(picked.count) \(picked.count == 1 ? "word" : "words") picked")
            }
            .themedListRow()

            Section {
                ForEach(visible) { word in
                    Button {
                        toggle(word.id)
                    } label: {
                        HStack {
                            Image(systemName: pickedSet.contains(word.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(pickedSet.contains(word.id) ? ZeichnenTile.tint : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text.gendered(word.word.german, article: word.word.article)
                                    .foregroundStyle(.primary)
                                Text("\(word.english) · \(word.deckTitle)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            } header: {
                Text("Wörter · Words").themedSectionHeader()
            }
            .themedListRow()
        }
        .themedListScreen()
        .searchable(text: $search, prompt: "Wort oder Deck suchen")
        .navigationTitle(set == nil ? "Neues Set" : "Set bearbeiten")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { save() }
                    .disabled(picked.isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func toggle(_ id: UUID) {
        if let index = picked.firstIndex(of: id) { picked.remove(at: index) } else { picked.append(id) }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        words = ZeichnenCatalog.dedupe(ZeichnenCatalog.allWords(in: modelContext))
            .sorted { $0.word.german.localizedCaseInsensitiveCompare($1.word.german) == .orderedAscending }
        if let set {
            name = set.name
            picked = set.cardIDs
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? "Set \(Date().formatted(date: .abbreviated, time: .omitted))" : trimmed
        let target: QuickDrawSet
        if let set {
            set.name = finalName
            set.cardIDs = picked
            target = set
        } else {
            target = QuickDrawSet(name: finalName, cardIDs: picked)
            modelContext.insert(target)
        }
        try? modelContext.save()
        onSave(target)
        dismiss()
    }
}
