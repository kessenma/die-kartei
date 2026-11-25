//
//  JournalLookupSheet.swift
//  german-ai-flashcards
//
//  "Nachschlagen": a word from the page (the selection, or typed) looked up in the bundled
//  dictionary. A hit is remembered on the entry, so the coach hand-off can offer it, and can go
//  into the room's deck. No tutor here: a lookup must not load a model while the learner is in
//  the middle of a sentence.
//

import SwiftData
import SwiftUI

struct JournalLookupSheet: View {
    @Bindable var entry: JournalEntry
    var initialWord: String = ""

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var word: String
    @State private var result: (english: String, article: GermanArticle?)?
    @State private var searched = false
    @State private var savedToDeck = false

    init(entry: JournalEntry, initialWord: String = "") {
        self.entry = entry
        self.initialWord = initialWord
        _word = State(initialValue: initialWord)
    }

    private var trimmed: String { word.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Wort · Word", text: $word)
                        .autocorrectionDisabled()
                        .onSubmit(lookup)
                    Button {
                        lookup()
                    } label: {
                        Label("Nachschlagen · Look up", systemImage: "character.book.closed")
                    }
                    .disabled(trimmed.isEmpty)
                } footer: {
                    Text("The bundled dictionary, offline. Looked-up words stay with the entry and can join the coach's words when you share it.")
                        .font(.caption2)
                }
                .themedListRow()

                if let result {
                    Section {
                        HStack {
                            Text(display(result.article))
                                .font(.body.weight(.semibold))
                            Spacer()
                            Text(result.english).foregroundStyle(.secondary)
                        }
                        Button {
                            savedToDeck = JournalDeckStore.saveWord(german: display(result.article), english: result.english,
                                                                     article: result.article, context: modelContext) || savedToDeck
                        } label: {
                            Label(savedToDeck ? "Im Deck · In the writing deck" : "In den Deck · Save to the writing deck",
                                  systemImage: savedToDeck ? "checkmark.circle.fill" : "rectangle.stack.badge.plus")
                        }
                        .disabled(savedToDeck)
                    } header: {
                        Text("Gefunden · Found").themedSectionHeader()
                    } footer: {
                        Text("The writing deck \"\(JournalDeckStore.topic)\" is in your Library like any other deck.")
                            .font(.caption2)
                    }
                    .themedListRow()
                } else if searched {
                    Section {
                        Text("Not in the dictionary. Check the spelling, or try the base form (der Hund, gehen).")
                            .foregroundStyle(.secondary)
                    }
                    .themedListRow()
                }

                if !entry.lookups.isEmpty {
                    Section {
                        ForEach(entry.lookups.sorted { $0.at > $1.at }) { lookup in
                            HStack {
                                Text(lookup.german)
                                Spacer()
                                Text(lookup.english).foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    } header: {
                        Text("Bisher nachgeschlagen · Looked up so far").themedSectionHeader()
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle("Nachschlagen")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { if !trimmed.isEmpty { lookup() } }
        }
    }

    private func display(_ article: GermanArticle?) -> String {
        let base = trimmed
        for prefix in ["der ", "die ", "das "] where base.lowercased().hasPrefix(prefix) { return base }
        if let article { return "\(article.rawValue) \(base)" }
        return base
    }

    private func lookup() {
        guard !trimmed.isEmpty else { return }
        searched = true
        savedToDeck = false
        result = WiktionaryValidator.shared.translation(for: trimmed)
        guard let result else { return }
        var list = entry.lookups
        let german = display(result.article)
        let found = JournalLookup(german: german, english: result.english, at: .now)
        if let i = list.firstIndex(where: { $0.id == found.id }) { list[i] = found } else { list.append(found) }
        entry.lookups = list
        entry.touch()
        try? modelContext.save()
        savedToDeck = JournalDeckStore.isWordSaved(german, context: modelContext)
    }
}
