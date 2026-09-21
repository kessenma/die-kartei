//
//  ClassEntryEditorView.swift
//  german-ai-flashcards
//
//  Logging one class, or editing the log later: which course and day, what grammar and topics
//  were covered, the new words, notes, and the homework. Built as a draft in local state and
//  written back in one go on Save, so Cancel leaves the entry as it was.
//

import SwiftUI
import SwiftData

struct ClassEntryEditorView: View {
    /// Nil creates a new entry.
    var entry: ClassEntry?
    /// The course a new entry starts under; the picker can change it while several exist.
    var course: ClassCourse?
    var onSaved: (ClassEntry) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Query(sort: \ClassCourse.sortOrder) private var allCourses: [ClassCourse]
    @AppStorage("classNotes.lastCourseID") private var lastCourseID = ""

    @State private var selectedCourseID: UUID?
    @State private var newCourseName = "Deutschkurs"
    @State private var date = Date()
    @State private var title = ""
    @State private var foci: Set<GrammarFocus> = []
    @State private var topics: [String] = []
    @State private var topicDraft = ""
    @State private var words: [ClassWord] = []
    @State private var notes = ""
    @State private var homework = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var showPasteList = false
    @State private var loaded = false
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case courseName, title, topic, notes, homework
        case wordGerman(UUID), wordEnglish(UUID)
    }

    private var courses: [ClassCourse] { allCourses.filter { !$0.isArchived } }
    private var isNew: Bool { entry == nil }

    /// Nothing worth saving yet.
    private var draftIsEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && homework.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && foci.isEmpty && topics.isEmpty
            && !words.contains { !$0.trimmedGerman.isEmpty }
    }

    private var needsCourseName: Bool {
        isNew && courses.isEmpty && newCourseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                courseSection
                whenSection
                grammarSection
                topicsSection
                wordsSection
                notesSection
                homeworkSection
            }
            .themedListScreen()
            .navigationTitle(isNew ? "Log a class" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(draftIsEmpty || needsCourseName)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
            .sheet(isPresented: $showPasteList) {
                ClassWordListPasteSheet { parsed in
                    merge(parsed)
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var courseSection: some View {
        Section {
            if let entry, let course = entry.course {
                LabeledContent("Course", value: course.name)
            } else if courses.isEmpty {
                TextField("Course name", text: $newCourseName)
                    .focused($focused, equals: .courseName)
            } else {
                Picker("Course", selection: $selectedCourseID) {
                    ForEach(courses) { course in
                        Text(course.name).tag(Optional(course.id))
                    }
                }
            }
        } header: {
            Text("Kurs · Course").themedSectionHeader()
        } footer: {
            if isNew && courses.isEmpty {
                Text("Your first course is created with this entry. Teacher, level, and dates can be added later from its page.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    private var whenSection: some View {
        Section {
            DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            TextField("Title", text: $title)
                .focused($focused, equals: .title)
        } header: {
            Text("Unterricht · Class").themedSectionHeader()
        } footer: {
            Text("A title is optional: \"Kapitel 4 · Wechselpräpositionen\", \"Bewerbungsgespräch üben\". Without one the entry is named after its week or day.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var grammarSection: some View {
        Section {
            WrapLayout(spacing: 6) {
                ForEach(GrammarFocus.allCases) { focus in
                    FilterPill(
                        label: focus.germanLabel,
                        tint: ClassNotesTile.tint,
                        isOn: foci.contains(focus),
                        showsClearGlyph: false
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            if foci.contains(focus) { foci.remove(focus) } else { foci.insert(focus) }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Grammatik · Grammar covered").themedSectionHeader()
        } footer: {
            let selected = GrammarFocus.allCases.filter { foci.contains($0) }
            Text(selected.isEmpty
                 ? "Tap what the class worked on. These are the same structures the coach tracks."
                 : selected.map { "\($0.germanLabel): \($0.englishLabel)" }.joined(separator: " · "))
                .font(.caption2)
        }
        .themedListRow()
    }

    private var topicsSection: some View {
        Section {
            if !topics.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(topics, id: \.self) { topic in
                        FilterPill(label: topic, tint: ClassNotesTile.tint, isOn: true) {
                            withAnimation(.snappy(duration: 0.2)) { topics.removeAll { $0 == topic } }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            TextField("Add a topic", text: $topicDraft)
                .focused($focused, equals: .topic)
                .submitLabel(.done)
                .onSubmit(addTopic)
        } header: {
            Text("Themen · Topics").themedSectionHeader()
        } footer: {
            Text("Themes rather than grammar: \"Wohnen\", \"Im Restaurant\", \"Lebenslauf\". Return adds one; tap a topic to remove it.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var wordsSection: some View {
        Section {
            ForEach($words) { $word in
                HStack(spacing: 10) {
                    TextField("German", text: $word.german)
                        .focused($focused, equals: .wordGerman(word.id))
                        .textInputAutocapitalization(.never)
                        .submitLabel(.next)
                        .onSubmit { focused = .wordEnglish(word.id) }
                    Divider()
                    TextField("English", text: $word.english)
                        .focused($focused, equals: .wordEnglish(word.id))
                        .textInputAutocapitalization(.never)
                        .submitLabel(.next)
                        .onSubmit { addWord() }
                    if word.addedToDeck {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ClassNotesTile.tint)
                            .accessibilityLabel("In the deck")
                    }
                }
            }
            .onDelete { offsets in words.remove(atOffsets: offsets) }

            Button {
                addWord()
            } label: {
                Label("Add a word", systemImage: "plus.circle")
            }
            Button {
                focused = nil
                showPasteList = true
            } label: {
                Label("Paste a list", systemImage: "doc.on.clipboard")
            }
        } header: {
            Text("Neue Wörter · New words").themedSectionHeader()
        } footer: {
            Text("Write nouns with their article (der Tisch). The English side can wait; words with both sides can go into the course deck from the entry.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var notesSection: some View {
        Section {
            TextEditor(text: $notes)
                .frame(minHeight: 140)
                .focused($focused, equals: .notes)
        } header: {
            Text("Notizen · Notes").themedSectionHeader()
        } footer: {
            Text("Anything else from the class, in whichever language it comes.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var homeworkSection: some View {
        Section {
            TextField("Assignment", text: $homework, axis: .vertical)
                .focused($focused, equals: .homework)
                .lineLimit(1...5)
            Toggle("Due date", isOn: $hasDue.animation())
            if hasDue {
                DatePicker("Due", selection: $due, displayedComponents: .date)
            }
        } header: {
            Text("Hausaufgabe · Homework").themedSectionHeader()
        } footer: {
            Text("Stays on the Deutschkurs page until you tick it off.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Actions

    private func addTopic() {
        let topic = topicDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return }
        if !topics.contains(where: { $0.caseInsensitiveCompare(topic) == .orderedSame }) {
            withAnimation(.snappy(duration: 0.2)) { topics.append(String(topic.prefix(60))) }
        }
        topicDraft = ""
    }

    private func addWord() {
        // Reuse a trailing blank row rather than stacking empties.
        if let last = words.last, last.trimmedGerman.isEmpty {
            focused = .wordGerman(last.id)
            return
        }
        let word = ClassWord(german: "")
        words.append(word)
        focused = .wordGerman(word.id)
    }

    /// Fold a pasted list into the rows: new keys appended, an existing row gains a translation it
    /// was missing.
    private func merge(_ parsed: [ClassWord]) {
        var existing = words.filter { !$0.trimmedGerman.isEmpty }
        for word in parsed {
            if let index = existing.firstIndex(where: { $0.key == word.key }) {
                if existing[index].trimmedEnglish.isEmpty { existing[index].english = word.english }
            } else {
                existing.append(word)
            }
        }
        withAnimation(.snappy(duration: 0.2)) { words = existing }
    }

    // MARK: - Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let entry {
            date = entry.date
            title = entry.title
            foci = Set(entry.grammarFoci)
            topics = entry.topics
            words = entry.words
            notes = entry.notes
            homework = entry.homework
            hasDue = entry.homeworkDue != nil
            due = entry.homeworkDue ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        } else {
            selectedCourseID = course?.id
                ?? courses.first { $0.id.uuidString == lastCourseID }?.id
                ?? courses.first?.id
            due = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
            if courses.isEmpty { focused = .courseName } else { focused = .title }
        }
    }

    private func save() {
        focused = nil
        addTopic()
        let cleanWords = words
            .map { ClassWord(id: $0.id, german: $0.trimmedGerman, english: $0.trimmedEnglish, addedToDeck: $0.addedToDeck) }
            .filter { !$0.german.isEmpty }

        let target: ClassEntry
        if let entry {
            target = entry
        } else {
            target = ClassEntry(date: date)
            modelContext.insert(target)
        }
        target.date = Calendar.current.startOfDay(for: date)
        target.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(90))
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.grammarFoci = GrammarFocus.allCases.filter { foci.contains($0) }
        target.topics = topics
        target.setWords(cleanWords)
        target.homework = homework.trimmingCharacters(in: .whitespacesAndNewlines)
        target.homeworkDue = hasDue && target.hasHomework ? Calendar.current.startOfDay(for: due) : nil
        if !target.hasHomework { target.homeworkDone = false }

        if entry == nil {
            let owner = resolveCourse()
            target.course = owner
            owner.updatedAt = .now
            lastCourseID = owner.id.uuidString
        } else if let owner = target.course {
            owner.updatedAt = .now
        }
        target.updatedAt = .now
        try? modelContext.save()
        dismiss()
        onSaved(target)
    }

    /// The picked course, or the one created inline when there was none.
    private func resolveCourse() -> ClassCourse {
        if let selectedCourseID, let picked = courses.first(where: { $0.id == selectedCourseID }) {
            return picked
        }
        if let first = courses.first { return first }
        let name = newCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = ClassCourse(name: name.isEmpty ? "Deutschkurs" : String(name.prefix(80)))
        created.sortOrder = (allCourses.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(created)
        return created
    }
}

// MARK: - Paste a list

/// A vocabulary list pasted in one go, one word per line, parsed by `ClassWord.parseList`.
struct ClassWordListPasteSheet: View {
    var onParsed: ([ClassWord]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: [ClassWord] { ClassWord.parseList(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("One word per line").themedSectionHeader()
                } footer: {
                    Text("der Tisch – table\ngehen = to go\nBuch: book\nA bare German word is fine too.")
                        .font(.caption2)
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle("Paste a list")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    let count = parsed.count
                    Button(count == 0 ? "Add" : "Add \(count)") {
                        onParsed(parsed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(count == 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Entry editor · 4 themes") {
    ForEach(AppTheme.allCases) { theme in
        ClassEntryEditorView(entry: nil, course: nil)
            .environment(\.appTheme, theme)
            .modelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self], inMemory: true)
    }
}
