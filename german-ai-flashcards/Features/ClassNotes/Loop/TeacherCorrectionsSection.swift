//
//  TeacherCorrectionsSection.swift
//  german-ai-flashcards
//
//  Korrekturen der Lehrerin (roadmap item 17, DLI-STRAT 3f): a quick capture on a class entry, what
//  I said and what she said instead. Each pair becomes a card on the course deck (the one
//  `CardKind` path, so a phrase stays a phrase card with its gap face) and a slip in the coach's
//  memory marked as confirmed by a teacher (`MemorySource.teacher`). No recording of the lesson.
//

import SwiftData
import SwiftUI

enum TeacherCorrectionStore {
    /// Saves the pair on the entry, a card on the course deck, and a teacher-confirmed slip.
    @MainActor
    static func add(_ correction: TeacherCorrection, to entry: ClassEntry, context: ModelContext) {
        entry.teacherCorrections = entry.teacherCorrections + [correction]
        entry.updatedAt = .now
        if let course = entry.course {
            let deck = ClassDeckStore.orCreateDeck(for: course, context: context)
            DeckCardAdder.add(german: correction.better, english: correction.note, example: nil, to: deck, context: context)
        }
        LearnerMemoryService.noteSlips([slip(for: correction)], in: context)
        try? context.save()
    }

    /// A one-word fix becomes a word slip with its sentence (a cloze card); anything bigger is kept
    /// whole.
    nonisolated static func slip(for c: TeacherCorrection) -> LexicalSlip {
        if let swap = WritingDiff.singleSwap(c.said, c.better) {
            let index = WritingDiff.tokens(c.better).firstIndex(of: swap.right)
            return LexicalSlip(wrong: swap.wrong, right: swap.right, note: c.note.isEmpty ? "Lehrerin" : c.note,
                               lastSeen: .now, timesSeen: 1, sentence: c.better, blankIndex: index,
                               source: MemorySource.teacher)
        }
        return LexicalSlip(wrong: c.said, right: c.better, note: c.note.isEmpty ? "Lehrerin" : c.note,
                           lastSeen: .now, timesSeen: 1, source: MemorySource.teacher)
    }
}

struct TeacherCorrectionsSection: View {
    @Bindable var entry: ClassEntry

    @Environment(\.modelContext) private var modelContext
    @State private var said = ""
    @State private var better = ""
    @State private var note = ""
    @State private var adding = false

    var body: some View {
        Section {
            ForEach(entry.teacherCorrections) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.said).strikethrough().foregroundStyle(.secondary)
                    Text(c.better).fontWeight(.semibold)
                    if !c.note.isEmpty { Text(c.note).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if adding {
                TextField("What I said", text: $said, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("What she said instead", text: $better, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Why, or the English (optional)", text: $note)
                HStack {
                    Button("Cancel") { reset() }
                    Spacer()
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(said.trimmingCharacters(in: .whitespaces).isEmpty || better.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    adding = true
                } label: {
                    Label("Add a correction", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Korrekturen der Lehrerin · Her corrections").themedSectionHeader()
        } footer: {
            Text("Each one becomes a card on the course deck and something the coach watches for, marked as checked by your teacher.")
        }
        .themedListRow()
    }

    private func save() {
        let c = TeacherCorrection(said: said.trimmingCharacters(in: .whitespacesAndNewlines),
                                  better: better.trimmingCharacters(in: .whitespacesAndNewlines),
                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        TeacherCorrectionStore.add(c, to: entry, context: modelContext)
        reset()
    }

    private func reset() {
        said = ""; better = ""; note = ""; adding = false
    }
}
