//
//  ClassCourseEditorView.swift
//  german-ai-flashcards
//
//  Create or edit a course: what it is, who teaches it or what it is for, its level, and its
//  dates when it has them. An existing course can also be archived (finished, kept) or deleted
//  (with its entries and handouts; the deck stays in the Library).
//

import SwiftUI
import SwiftData

struct ClassCourseEditorView: View {
    /// Nil creates a new course.
    var course: ClassCourse?
    /// The learner's declared level, offered as the default for a new course.
    var defaultLevel: CEFRLevel = .a2
    var onSaved: (ClassCourse) -> Void = { _ in }
    /// Called after a delete, so the screen that showed the course can leave.
    var onDeleted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Query(sort: \ClassCourse.sortOrder) private var courses: [ClassCourse]

    @State private var name = ""
    @State private var kind: ClassCourse.Kind = .course
    @State private var teacher = ""
    @State private var goal = ""
    @State private var levelRaw = ""
    @State private var hasDates = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isArchived = false
    @State private var showDeleteConfirm = false
    @State private var loaded = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, teacher, goal }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                kindSection
                detailsSection
                levelSection
                datesSection
                if course != nil {
                    statusSection
                }
            }
            .themedListScreen()
            .navigationTitle(course == nil ? "New course" : "Edit course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
            .confirmationDialog(
                "Delete this course?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete course and its entries", role: .destructive) { deleteCourse() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every entry and handout goes with it. The flashcard deck stays in the Library.")
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Course name", text: $name)
                .focused($focused, equals: .name)
                .submitLabel(.next)
                .onSubmit { focused = .teacher }
        } header: {
            Text("Name").themedSectionHeader()
        } footer: {
            Text("As you'd say it: \"Deutsch A2 an der Uni\", \"HR-Deutsch mit Anna\".")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var kindSection: some View {
        Section {
            Picker("Kind", selection: $kind) {
                ForEach(ClassCourse.Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("What kind of course").themedSectionHeader()
        } footer: {
            Text(kind.blurb)
                .font(.caption2)
        }
        .themedListRow()
    }

    private var detailsSection: some View {
        Section {
            TextField("Teacher or tutor", text: $teacher)
                .focused($focused, equals: .teacher)
                .submitLabel(.next)
                .onSubmit { focused = .goal }
            TextField("Goal", text: $goal, axis: .vertical)
                .focused($focused, equals: .goal)
                .lineLimit(1...3)
        } header: {
            Text("Details").themedSectionHeader()
        } footer: {
            Text("The goal is what the course is for, in your words: \"pass the B1 exam\", \"HR German for job applications\". Optional, and the tutors will read it later.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var levelSection: some View {
        Section {
            Picker("Level", selection: $levelRaw) {
                Text("Not set").tag("")
                ForEach(CEFRLevel.allCases) { level in
                    Text("\(level.rawValue) · \(level.englishLabel)").tag(level.rawValue)
                }
            }
        } header: {
            Text("Level").themedSectionHeader()
        } footer: {
            Text("The level the course is pitched at, if you know it.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var datesSection: some View {
        Section {
            Toggle("Has dates", isOn: $hasDates.animation())
            if hasDates {
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
            }
        } header: {
            Text("Dates").themedSectionHeader()
        } footer: {
            Text(hasDates
                 ? "Entries are labelled by week of the course (\"Woche 5\")."
                 : "A semester has dates; a tutor usually doesn't. With dates, entries are labelled by week.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var statusSection: some View {
        Section {
            Toggle("Finished", isOn: $isArchived)
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete course", systemImage: "trash")
            }
        } header: {
            Text("Status").themedSectionHeader()
        } footer: {
            Text("A finished course leaves the front page but keeps its notes and deck.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let course {
            name = course.name
            kind = course.kind
            teacher = course.teacher ?? ""
            goal = course.goal ?? ""
            levelRaw = course.levelRaw ?? ""
            hasDates = course.startDate != nil
            startDate = course.startDate ?? Date()
            endDate = course.endDate ?? (Calendar.current.date(byAdding: .month, value: 4, to: startDate) ?? startDate)
            isArchived = course.isArchived
        } else {
            levelRaw = defaultLevel.rawValue
            endDate = Calendar.current.date(byAdding: .month, value: 4, to: startDate) ?? startDate
            focused = .name
        }
    }

    private func save() {
        focused = nil
        let target: ClassCourse
        if let course {
            target = course
        } else {
            target = ClassCourse(name: trimmedName, kind: kind)
            target.sortOrder = (courses.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(target)
        }
        target.name = trimmedName
        target.kindRaw = kind.rawValue
        target.teacher = optional(teacher)
        target.goal = optional(goal)
        target.levelRaw = levelRaw.isEmpty ? nil : levelRaw
        target.startDate = hasDates ? Calendar.current.startOfDay(for: startDate) : nil
        target.endDate = hasDates ? Calendar.current.startOfDay(for: endDate) : nil
        target.isArchived = isArchived
        target.updatedAt = .now
        try? modelContext.save()
        dismiss()
        onSaved(target)
    }

    private func deleteCourse() {
        guard let course else { return }
        ClassEntryStore.delete(course, context: modelContext)
        try? modelContext.save()
        dismiss()
        onDeleted()
    }

    private func optional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(120))
    }
}

// MARK: - Preview

#Preview("Course editor · 4 themes") {
    ForEach(AppTheme.allCases) { theme in
        ClassCourseEditorView(course: nil, defaultLevel: .a2)
            .environment(\.appTheme, theme)
            .modelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self], inMemory: true)
    }
}
