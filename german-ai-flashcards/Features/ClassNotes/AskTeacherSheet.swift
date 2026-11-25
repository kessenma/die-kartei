//
//  AskTeacherSheet.swift
//  german-ai-flashcards
//
//  Fragen für die Stunde (roadmap item 14, FSI lessons 6 and 9): where the learner gets stuck, they
//  can park a question for their teacher. It waits on the course and shows before the next session;
//  ticking it off writes the answer into that session's entry (`ClassQuestionsSection`).
//
//  The entry points: the word inspector, a conversation's correction card, a missed drill step,
//  and a worksheet check. Each passes a prefilled question and where it came from.
//

import SwiftData
import SwiftUI

/// A small "Ask my teacher" button that opens `AskTeacherSheet`. Hidden when there is no course.
struct AskTeacherButton: View {
    let prefill: String
    let context: String
    var compact = false

    @Query(filter: #Predicate<ClassCourse> { !$0.isArchived }) private var courses: [ClassCourse]
    @State private var asking = false

    var body: some View {
        if !courses.isEmpty {
            Button {
                asking = true
            } label: {
                if compact {
                    Label("Ask my teacher", systemImage: "questionmark.bubble")
                        .labelStyle(.iconOnly)
                } else {
                    Label("Ask my teacher", systemImage: "questionmark.bubble")
                }
            }
            .accessibilityLabel("Ask my teacher")
            .sheet(isPresented: $asking) {
                AskTeacherSheet(prefill: prefill, context: context)
            }
        }
    }
}

struct AskTeacherSheet: View {
    let prefill: String
    let context: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ClassCourse> { !$0.isArchived }, sort: \ClassCourse.sortOrder) private var courses: [ClassCourse]
    @AppStorage("classNotes.lastCourseID") private var lastCourseID = ""

    @State private var text = ""
    @State private var courseID: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your question", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                } footer: {
                    if !context.isEmpty { Text("From: \(context)") }
                }
                .themedListRow()

                if courses.count > 1 {
                    Section {
                        Picker("For", selection: $courseID) {
                            ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    .themedListRow()
                }

                Section {
                    Text("It waits on the course and comes up before your next session. Tick it off there and the answer goes into that day's notes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            .themedListScreen()
            .navigationTitle("Ask my teacher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || target == nil)
                }
            }
            .onAppear {
                text = prefill
                courseID = courses.first { $0.id.uuidString == lastCourseID }?.id ?? courses.first?.id
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var target: ClassCourse? { courses.first { $0.id == courseID } ?? courses.first }

    private func save() {
        guard let course = target else { return }
        course.upsert(ClassQuestion(text: text.trimmingCharacters(in: .whitespacesAndNewlines), context: context))
        try? modelContext.save()
        dismiss()
    }
}

/// The course's open questions, with a way to tick one off: the answer goes into an entry's notes
/// (the session's entry: today's, else the most recent) and the question is kept as answered.
struct ClassQuestionsSection: View {
    @Bindable var course: ClassCourse
    /// Show answered ones too (the course page); Today's prep shows only open ones.
    var showsAnswered = true

    @Environment(\.modelContext) private var modelContext
    @State private var answering: ClassQuestion?
    @State private var answer = ""

    var body: some View {
        let open = course.openQuestions
        let answered = course.questions.filter { $0.answeredAt != nil }
        if !open.isEmpty || (showsAnswered && !answered.isEmpty) {
            Section {
                ForEach(open) { q in
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            answer = ""
                            answering = q
                        } label: {
                            Image(systemName: "circle").font(.title3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Answered")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.text)
                            if !q.context.isEmpty {
                                Text(q.context).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            var gone = q
                            gone.deleted = true
                            course.upsert(gone)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                if showsAnswered {
                    ForEach(answered.suffix(5)) { q in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(q.text, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                            if let a = q.answer, !a.isEmpty {
                                Text(a).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Fragen für die Stunde · Questions").themedSectionHeader()
            } footer: {
                Text("Saved with \"Ask my teacher\" from a word, a correction, a drill or a worksheet. Tick one off when she has answered.")
            }
            .themedListRow()
            .alert("Her answer", isPresented: Binding(get: { answering != nil }, set: { if !$0 { answering = nil } })) {
                TextField("What she said", text: $answer)
                Button("Save") { tickOff() }
                Button("Cancel", role: .cancel) { answering = nil }
            } message: {
                Text(answering?.text ?? "")
            }
        }
    }

    private func tickOff() {
        guard var q = answering else { return }
        let entry = course.entry(on: .now) ?? course.sortedEntries.first
        q.answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        q.answeredAt = .now
        q.entryID = entry?.id
        course.upsert(q)
        if let entry {
            let line = "Frage: \(q.text)" + ((q.answer ?? "").isEmpty ? "" : "\nAntwort: \(q.answer ?? "")")
            entry.notes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? line : entry.notes + "\n\n" + line
            entry.updatedAt = .now
        }
        try? modelContext.save()
        answering = nil
    }
}
