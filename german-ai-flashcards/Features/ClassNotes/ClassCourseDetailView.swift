//
//  ClassCourseDetailView.swift
//  german-ai-flashcards
//
//  One course: what it is, the doors to log a class or add a handout, its open homework, every
//  entry (by week for a dated course, by month otherwise), its handouts, and its deck.
//

import SwiftUI
import SwiftData

struct ClassCourseDetailView: View {
    @Bindable var course: ClassCourse
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityRouter.self) private var router

    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]

    @State private var showEditor = false
    @State private var showEntryEditor = false
    @State private var importTarget: ClassHandoutTarget?
    @State private var openedEntry: ClassEntry?
    @State private var showAddDeckChoice = false
    @State private var showDocumentDeck = false
    @State private var showDeckLink = false
    @AppStorage("classNotes.lastCourseID") private var lastCourseID = ""

    /// Every deck on this course: its own word deck, decks built from its handouts, linked ones.
    private var courseDecks: [SavedDeck] { decks.filter { $0.courseID == course.id } }

    /// Entries grouped for the list: "Woche N" for a dated course, else the month.
    private var groups: [(label: String, entries: [ClassEntry])] {
        let sorted = course.sortedEntries
        guard !sorted.isEmpty else { return [] }
        var labels: [String] = []
        var buckets: [String: [ClassEntry]] = [:]
        for entry in sorted {
            let label: String
            if let week = course.weekNumber(for: entry.date) {
                label = "Woche \(week)"
            } else {
                label = entry.date.formatted(.dateTime.month(.wide).year())
            }
            if buckets[label] == nil { labels.append(label) }
            buckets[label, default: []].append(entry)
        }
        return labels.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        List {
            headerSection
            actionsSection
            decksSection
            if !course.openHomework.isEmpty {
                homeworkSection
            }
            if groups.isEmpty {
                emptySection
            } else {
                ForEach(groups, id: \.label) { group in
                    entriesSection(group.label, group.entries)
                }
            }
            if !course.materials.isEmpty {
                handoutsSection
            }
        }
        .themedListScreen()
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditor = true }
            }
        }
        .navigationDestination(item: $openedEntry) { entry in
            ClassEntryDetailView(entry: entry, modelManager: modelManager, mlxService: mlxService)
        }
        .sheet(isPresented: $showEditor) {
            ClassCourseEditorView(course: course, defaultLevel: modelManager.germanLevel, onDeleted: { dismiss() })
        }
        .sheet(isPresented: $showEntryEditor) {
            ClassEntryEditorView(entry: nil, course: course) { entry in
                DispatchQueue.main.async { openedEntry = entry }
            }
        }
        .sheet(item: $importTarget) { target in
            ClassMaterialImportView(course: target.course, entry: target.entry) { _ in
                DispatchQueue.main.async { openedEntry = target.entry }
            }
        }
        .sheet(isPresented: $showDocumentDeck) {
            DocumentDeckImportView(modelManager: modelManager, mlxService: mlxService, course: course) { _ in }
        }
        .sheet(isPresented: $showDeckLink) {
            CourseDeckLinkView(course: course)
        }
        .confirmationDialog("Add a flashcard deck", isPresented: $showAddDeckChoice, titleVisibility: .visible) {
            Button("From a document (PDF, photo, text)") { showDocumentDeck = true }
            Button("Link a deck from the Library") { showDeckLink = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A vocab sheet is paired into cards for you; in a handout or story you highlight the phrases you want.")
        }
        .onAppear { lastCourseID = course.id.uuidString }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: course.kind.systemImage)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(ClassNotesTile.tint, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(12), style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.kind.label)
                        .font(.subheadline.weight(.semibold))
                    if let teacher = course.teacher, !teacher.isEmpty {
                        Text(teacher).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let goal = course.goal, !goal.isEmpty {
                        Text(goal).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        if let level = course.level {
                            Text(level.rawValue)
                        }
                        if let start = course.startDate {
                            if let end = course.endDate {
                                Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))")
                            } else {
                                Text("From \(start.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
                        if let week = course.currentWeekLabel {
                            Text(week).foregroundStyle(ClassNotesTile.tint)
                        }
                        if course.isArchived {
                            Text("Finished")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .themedListRow()
    }

    private var actionsSection: some View {
        Section {
            Button {
                showEntryEditor = true
            } label: {
                ActivityRow("Log a class", "Grammar, topics, new words, homework", "square.and.pencil")
            }
            .buttonStyle(.plain)
            Button {
                importTarget = ClassHandoutTarget(course: course, entry: ClassEntryStore.todayEntry(in: course, context: modelContext))
            } label: {
                ActivityRow("Add a handout", "PDF, photo, or pasted text, filed under today", "doc.text.viewfinder")
            }
            .buttonStyle(.plain)
            Button {
                showAddDeckChoice = true
            } label: {
                ActivityRow("Add a flashcard deck", "From a vocab sheet or a handout, or one you already have", "rectangle.stack.badge.plus")
            }
            .buttonStyle(.plain)
        }
        .themedListRow()
    }

    private var decksSection: some View {
        Section {
            if courseDecks.isEmpty {
                Text("No decks yet. Words you log and save build the course's own deck; a vocab sheet becomes a deck of its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(courseDecks) { deck in
                Button {
                    router.launch(.cardDeck(DeckStore(modelContext: modelContext).session(for: deck, style: modelManager.flashcardStyle)))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: deck.kindSymbol ?? "rectangle.stack.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deck.topic.replacingOccurrences(of: "Class: ", with: ""))
                                .font(.body)
                                .lineLimit(1)
                            Text(deck.cards.isEmpty ? "No cards yet" : "\(deck.cards.count) cards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(deck.cards.isEmpty)
                .swipeActions(edge: .trailing) {
                    if deck.id != course.deckID {
                        Button {
                            deck.courseID = nil
                            try? modelContext.save()
                        } label: {
                            Label("Unlink", systemImage: "link.badge.minus")
                        }
                    }
                }
            }
        } header: {
            Text("Decks").themedSectionHeader()
        } footer: {
            if !courseDecks.isEmpty {
                Text("Also under Library ▸ Decks. Swipe to take a deck off the course; the deck itself stays.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    private var homeworkSection: some View {
        Section {
            ForEach(course.openHomework) { entry in
                ClassHomeworkRow(entry: entry)
            }
        } header: {
            Text("Hausaufgaben · Homework").themedSectionHeader()
        }
        .themedListRow()
    }

    private var emptySection: some View {
        Section {
            Text("No entries yet. Log a class to start.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Einträge · Entries").themedSectionHeader()
        }
        .themedListRow()
    }

    private func entriesSection(_ label: String, _ entries: [ClassEntry]) -> some View {
        Section {
            ForEach(entries) { entry in
                NavigationLink {
                    ClassEntryDetailView(entry: entry, modelManager: modelManager, mlxService: mlxService)
                } label: {
                    ClassEntryRow(entry: entry)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        ClassEntryStore.delete(entry, context: modelContext)
                        try? modelContext.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text(label).themedSectionHeader()
        }
        .themedListRow()
    }

    private var handoutsSection: some View {
        Section {
            ForEach(course.materials) { material in
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
        } header: {
            Text("Handouts").themedSectionHeader()
        }
        .themedListRow()
    }
}

/// One handout in a list: where it came from, what it's called, how long it is.
struct ClassMaterialRow: View {
    let material: ClassMaterial
    var showsEntry = false

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: material.sourceKind.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))
            VStack(alignment: .leading, spacing: 2) {
                Text(material.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if showsEntry, let entry = material.entry {
                        if let course = entry.course { Text(course.name) }
                        Text(entry.dateLine)
                    } else {
                        Text(material.createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    Text("\(material.wordCount) Wörter")
                    let lookups = material.lookups.count
                    if lookups > 0 {
                        Label("\(lookups)", systemImage: "character.book.closed.fill")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

@MainActor
private func classCoursePreview(_ theme: AppTheme) -> some View {
    let course = ClassCourse(name: "Deutsch A2 an der Uni")
    course.teacher = "Frau Müller"
    course.startDate = Calendar.current.date(byAdding: .weekOfYear, value: -6, to: .now)
    course.endDate = Calendar.current.date(byAdding: .weekOfYear, value: 14, to: .now)
    return NavigationStack {
        ClassCourseDetailView(course: course, modelManager: MLXModelManager(), mlxService: MLXGenerationService())
    }
    .environment(ActivityRouter())
    .environment(\.appTheme, theme)
    .modelContainer(
        for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self, SavedDeck.self, SavedCard.self],
        inMemory: true
    )
}

#Preview("Course · System")  { classCoursePreview(.klar) }
#Preview("Course · Soft")    { classCoursePreview(.sanft) }
#Preview("Course · Notebook") { classCoursePreview(.kritzel) }
#Preview("Course · Bauhaus") { classCoursePreview(.grundform) }
