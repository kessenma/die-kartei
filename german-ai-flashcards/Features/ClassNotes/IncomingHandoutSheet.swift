//
//  IncomingHandoutSheet.swift
//  german-ai-flashcards
//
//  A PDF opened in Die Kartei from outside — the share sheet in Files, Mail or the tutoring
//  platform's app — becomes a class handout: pick the course, then the usual import (review, and
//  for a lesson with exercises, picking the homework). The bytes are read once, at hand-off: the
//  system's copy in the app's Inbox is deleted straight away, since the handout keeps its own.
//

import SwiftUI
import SwiftData

/// A PDF handed to the app, already read.
struct IncomingHandoutPDF: Identifiable {
    let id = UUID()
    let data: Data
    let title: String

    /// Nil for anything that isn't a readable PDF file URL.
    init?(url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return nil }
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        self.data = data
        self.title = url.deletingPathExtension().lastPathComponent
        // iOS copies a document opened in a non-in-place app into Documents/Inbox; that copy is ours
        // to remove once read.
        if url.pathComponents.contains("Inbox") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

struct IncomingHandoutSheet: View {
    let incoming: IncomingHandoutPDF

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClassCourse.sortOrder) private var allCourses: [ClassCourse]

    @State private var target: ClassHandoutTarget?
    @State private var showCourseEditor = false

    private var courses: [ClassCourse] { allCourses.filter { !$0.isArchived } }

    var body: some View {
        if let target {
            ClassMaterialImportView(course: target.course, entry: target.entry, incoming: incoming) { _ in
                dismiss()
            }
        } else {
            NavigationStack {
                List {
                    Section {
                        Label(incoming.title, systemImage: "doc.richtext")
                            .font(.subheadline.weight(.semibold))
                    } footer: {
                        Text("It's filed as a handout under today's class. You'll find it, and any homework you set up, under Home ▸ Deutschkurs.")
                            .font(.caption2)
                    }
                    .themedListRow()

                    Section {
                        ForEach(courses) { course in
                            Button {
                                pick(course)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: course.kind.systemImage)
                                        .foregroundStyle(ClassNotesTile.tint)
                                        .frame(width: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(course.name).foregroundStyle(.primary)
                                        Text(course.subtitleLine).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Button {
                            showCourseEditor = true
                        } label: {
                            Label(courses.isEmpty ? "Set up a course" : "Another course", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Which course is it for?").themedSectionHeader()
                    }
                    .themedListRow()
                }
                .themedListScreen()
                .navigationTitle("Add a handout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .sheet(isPresented: $showCourseEditor) {
                    ClassCourseEditorView(course: nil, onSaved: { course in
                        DispatchQueue.main.async { pick(course) }
                    })
                }
            }
        }
    }

    private func pick(_ course: ClassCourse) {
        UserDefaults.standard.set(course.id.uuidString, forKey: "classNotes.lastCourseID")
        target = ClassHandoutTarget(course: course, entry: ClassEntryStore.todayEntry(in: course, context: modelContext))
    }
}
