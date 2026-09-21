//
//  ClassEntryDetailView.swift
//  german-ai-flashcards
//
//  One logged class: what it covered (each grammar point opens its quick lesson), the new words
//  (into the course deck in one tap), the notes, the homework with its tick, and the handouts.
//

import SwiftUI
import SwiftData

struct ClassEntryDetailView: View {
    @Bindable var entry: ClassEntry
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(ActivityRouter.self) private var router

    @State private var showEditor = false
    @State private var lessonFocus: GrammarFocus?
    @State private var importTarget: ClassHandoutTarget?
    /// Briefly the count after "Add to deck", to confirm.
    @State private var addedCount: Int?

    private var course: ClassCourse? { entry.course }
    private var deck: SavedDeck? {
        guard let course else { return nil }
        return ClassDeckStore.deck(for: course, context: modelContext)
    }

    var body: some View {
        List {
            headerSection
            coveredSection
            wordsSection
            if !entry.notes.isEmpty {
                notesSection
            }
            if entry.hasHomework {
                homeworkSection
            }
            materialsSection
        }
        .themedListScreen()
        .navigationTitle(entry.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) {
            ClassEntryEditorView(entry: entry, course: course)
        }
        .sheet(item: $lessonFocus) { focus in
            GrammarLessonSheet(focus: focus)
        }
        .sheet(item: $importTarget) { target in
            ClassMaterialImportView(course: target.course, entry: target.entry) { _ in }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: 10) {
                Text(entry.date.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                Spacer()
                if let course, let week = course.weekNumber(for: entry.date) {
                    Text("Woche \(week)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ClassNotesTile.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(ClassNotesTile.tint.opacity(0.12), in: appTheme.pillShape)
                }
            }
            if let course {
                Label(course.name, systemImage: course.kind.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .themedListRow()
    }

    private var coveredSection: some View {
        Section {
            let foci = entry.grammarFoci
            if foci.isEmpty && entry.topics.isEmpty {
                Text("Nothing tagged yet. Edit the entry to add the grammar and topics the class covered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !foci.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(foci) { focus in
                        FilterPill(label: focus.germanLabel, systemImage: "book", tint: ClassNotesTile.tint, isOn: false) {
                            lessonFocus = focus
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if !entry.topics.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(entry.topics, id: \.self) { topic in
                        Text(topic)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemFill), in: appTheme.pillShape)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Behandelt · Covered").themedSectionHeader()
        } footer: {
            if !entry.grammarFoci.isEmpty {
                Text("Tap a grammar point for its quick lesson.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    @ViewBuilder
    private var wordsSection: some View {
        let words = entry.words
        Section {
            if words.isEmpty {
                Text("No words logged. Edit the entry to add the ones the class introduced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(words) { word in
                    HStack(spacing: 10) {
                        Text(word.german)
                            .fontWeight(.medium)
                        Spacer()
                        if word.english.isEmpty {
                            Text("no translation yet")
                                .foregroundStyle(.tertiary)
                                .italic()
                        } else {
                            Text(word.english)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        if word.addedToDeck {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ClassNotesTile.tint)
                                .accessibilityLabel("In the deck")
                        }
                        Button {
                            SpeechService.shared.speak(word.german)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                }

                let pending = words.filter { $0.isComplete && !$0.addedToDeck }.count
                Button {
                    addWordsToDeck()
                } label: {
                    Label(
                        addedCount.map { "Added \($0) to the course deck" }
                            ?? (pending == 0 ? "All in the course deck" : "Add \(pending) to the course deck"),
                        systemImage: addedCount != nil ? "checkmark.circle.fill" : "rectangle.stack.badge.plus"
                    )
                }
                .disabled(pending == 0 || addedCount != nil || course == nil)

                if let deck, !deck.cards.isEmpty {
                    Button {
                        router.launch(.cardDeck(DeckStore(modelContext: modelContext).session(for: deck, style: modelManager.flashcardStyle)))
                    } label: {
                        Label("Study the course deck (\(deck.cards.count))", systemImage: "rectangle.stack.fill")
                    }
                }
            }
        } header: {
            Text("Neue Wörter · New words").themedSectionHeader()
        } footer: {
            if !words.isEmpty {
                Text("Words with both sides go into the course's flashcard deck. Ones without a translation wait.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    private var notesSection: some View {
        Section {
            Text(entry.notes)
                .font(.body)
                .textSelection(.enabled)
        } header: {
            Text("Notizen · Notes").themedSectionHeader()
        }
        .themedListRow()
    }

    private var homeworkSection: some View {
        Section {
            ClassHomeworkRow(entry: entry)
        } header: {
            Text("Hausaufgabe · Homework").themedSectionHeader()
        }
        .themedListRow()
    }

    private var materialsSection: some View {
        Section {
            ForEach(entry.materials.sorted { $0.createdAt > $1.createdAt }) { material in
                NavigationLink {
                    ClassMaterialDetailView(material: material, modelManager: modelManager, mlxService: mlxService)
                } label: {
                    ClassMaterialRow(material: material)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        ClassEntryStore.delete(material, context: modelContext)
                        try? modelContext.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button {
                guard let course else { return }
                importTarget = ClassHandoutTarget(course: course, entry: entry)
            } label: {
                Label("Add a handout", systemImage: "doc.text.viewfinder")
            }
            .disabled(course == nil)
        } header: {
            Text("Handouts").themedSectionHeader()
        } footer: {
            Text("A PDF, a photo of a page, or pasted text from this class. Read it word by word and save what you look up.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Actions

    private func addWordsToDeck() {
        let added = ClassDeckStore.saveWords(of: entry, feedsCoach: modelManager.storyFeedsCoach, context: modelContext)
        addedCount = added
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            addedCount = nil
        }
    }
}

// MARK: - Preview

@MainActor
private func classEntryPreview(_ theme: AppTheme) -> some View {
    let entry = ClassEntry(date: .now, title: "Kapitel 4 · Wechselpräpositionen")
    entry.grammarFoci = [.wechselpraepositionen, .dativ]
    entry.topics = ["Wohnen", "Im Zimmer"]
    entry.setWords([
        ClassWord(german: "der Schrank", english: "wardrobe"),
        ClassWord(german: "das Regal", english: "shelf", addedToDeck: true),
        ClassWord(german: "hängen")
    ])
    entry.notes = "Wo? + Dativ, wohin? + Akkusativ. Ich stelle die Lampe auf den Tisch. Die Lampe steht auf dem Tisch."
    entry.homework = "Arbeitsbuch S. 42, Übung 3 und 4"
    entry.homeworkDue = Calendar.current.date(byAdding: .day, value: 2, to: .now)
    return NavigationStack {
        ClassEntryDetailView(entry: entry, modelManager: MLXModelManager(), mlxService: MLXGenerationService())
    }
    .environment(ActivityRouter())
    .environment(\.appTheme, theme)
    .modelContainer(
        for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self, SavedDeck.self, SavedCard.self],
        inMemory: true
    )
}

#Preview("Entry · System")   { classEntryPreview(.klar) }
#Preview("Entry · Soft")     { classEntryPreview(.sanft) }
#Preview("Entry · Notebook") { classEntryPreview(.kritzel) }
#Preview("Entry · Bauhaus")  { classEntryPreview(.grundform) }
