//
//  WorksheetSetupView.swift
//  german-ai-flashcards
//
//  Picking the homework out of a lesson PDF. The parser finds the exercise pages; they start
//  ticked, except a page that already carries answers typed in during class. The learner unticks
//  what was finished in class and, per page, chooses how to work it: in the app (gaps, chips,
//  choices) or on the slide with the Pencil. Any other page can be added for the Pencil too — a
//  scanned PDF, which has no text to find exercises in, works that way only.
//
//  Saving writes the plan to the handout, lists the exercises as the class entry's homework, and
//  keeps every answer already given on pages that stay.
//

import SwiftUI
import SwiftData

struct WorksheetSetupView: View {
    @Bindable var material: ClassMaterial
    /// Called after saving, with whether a worksheet now exists.
    var onDone: (Bool) -> Void = { _ in }
    /// Shown instead of a back button when the setup is a step of adding the handout.
    var showsLater = false
    /// The pages already parsed (by the import that just read the file), so the PDF isn't read
    /// a second time.
    var prefetched: [WorksheetExercise]? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var pages: [WorksheetExercise] = []
    @State private var loading = true
    @State private var chosen: [Int: WorksheetPagePlan.Mode] = [:]
    @State private var showOtherPages = false
    @State private var thumbnails: PDFPageThumbnails?
    @State private var previewPage: Int?
    /// Her Lösungen pages, read alongside the exercises; saved with the setup.
    @State private var keyReading: WorksheetKeyReading?

    private var exercisePages: [WorksheetExercise] { pages.filter(\.isExercise) }
    private var otherPages: [WorksheetExercise] { pages.filter { !$0.isExercise } }
    private var accent: Color { ClassNotesTile.tint }

    var body: some View {
        List {
            if loading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Finding the exercises…").foregroundStyle(.secondary)
                    }
                }
                .themedListRow()
            } else {
                introSection
                if !exercisePages.isEmpty { exercisesSection }
                otherPagesSection
            }
        }
        .themedListScreen()
        .navigationTitle("Hausaufgabe")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsLater)
        .toolbar {
            if showsLater {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { onDone(material.worksheet != nil) }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(chosen.isEmpty)
            }
        }
        .sheet(item: Binding(get: { previewPage.map(PagePreview.init) }, set: { previewPage = $0?.page })) { preview in
            WorksheetPagePreviewSheet(thumbnails: thumbnails, page: preview.page)
        }
        .task { await load() }
        .onDisappear { thumbnails?.purge() }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            if exercisePages.isEmpty {
                Label("No exercises found in the text. Pick the pages to write on with the Pencil.",
                      systemImage: "pencil.and.scribble")
                    .font(.subheadline)
            } else {
                Text("Tick the exercises that are homework; untick the ones you finished in class. Each one can be answered here or written on the slide with the Pencil.")
                    .font(.subheadline)
            }
        } footer: {
            if let teacher = material.entry?.course?.teacher, !teacher.isEmpty {
                Text("When you're done, share it as a PDF: \(teacher)'s slides with your answers written in.")
                    .font(.caption2)
            } else {
                Text("When you're done, share it as a PDF: the slides with your answers written in.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    private var exercisesSection: some View {
        Section {
            ForEach(exercisePages) { exercise in
                pageRow(exercise)
            }
        } header: {
            Text("Übungen · \(exercisePages.count) found").themedSectionHeader()
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let keyLine {
                    Label(keyLine, systemImage: "key")
                }
                Text("A page marked \"filled in\" already has answers typed into it, so it starts unticked.")
            }
            .font(.caption2)
        }
        .themedListRow()
    }

    @ViewBuilder
    private var otherPagesSection: some View {
        Section {
            Toggle("Show the other pages", isOn: $showOtherPages.animation())
            if showOtherPages || exercisePages.isEmpty {
                ForEach(otherPages) { page in
                    pageRow(page)
                }
            }
        } header: {
            Text("Andere Seiten · Other pages").themedSectionHeader()
        } footer: {
            Text("Any page can be added to write on with the Pencil.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private func pageRow(_ exercise: WorksheetExercise) -> some View {
        let isOn = chosen[exercise.page] != nil
        let canAnswer = exercise.verdict == .interactive
        return HStack(alignment: .top, spacing: 12) {
            Button {
                toggle(exercise)
            } label: {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? accent : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isOn ? "Remove \(exercise.displayTitle)" : "Add \(exercise.displayTitle)")

            Button {
                previewPage = exercise.page
            } label: {
                WorksheetThumbnail(thumbnails: thumbnails, page: exercise.page)
                    .frame(width: 112)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show page \(exercise.page)")

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(detail(exercise))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if exercise.hasTypedAnswers {
                    Label("Filled in", systemImage: "pencil.line")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if isOn, canAnswer {
                    Picker("How", selection: Binding(
                        get: { chosen[exercise.page] ?? .answer },
                        set: { chosen[exercise.page] = $0 }
                    )) {
                        Text("In the app").tag(WorksheetPagePlan.Mode.answer)
                        Text("Pencil").tag(WorksheetPagePlan.Mode.pencil)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func detail(_ exercise: WorksheetExercise) -> String {
        var parts = ["Seite \(exercise.page)"]
        let gaps = exercise.items.reduce(0) { $0 + $1.gaps.count }
        let choices = exercise.items.reduce(0) { $0 + $1.choices.count }
        let writes = exercise.items.filter(\.writeBelow).count
        if gaps > 0 { parts.append(gaps == 1 ? "1 gap" : "\(gaps) gaps") }
        if choices > 0 { parts.append(choices == 1 ? "1 choice" : "\(choices) choices") }
        if writes > 0 { parts.append(writes == 1 ? "1 sentence" : "\(writes) sentences") }
        if exercise.verdict == .writeOnly { parts.append("Pencil only") }
        if !exercise.isExercise { parts.append(exercise.displayTitle == "Seite \(exercise.page)" ? "no text" : "Pencil") }
        return parts.joined(separator: " · ")
    }

    /// "Answer key found for 14 Übungen": what Prüfen will compare with.
    private var keyLine: String? {
        guard let keyReading, !keyReading.isEmpty else { return nil }
        let full = keyReading.exercises.filter { !$0.isSample && $0.placed > 0 }.count
        let examples = keyReading.exercises.filter { $0.isSample && $0.placed > 0 }.count
        var line = "Her answer key was found for \(full) Übung\(full == 1 ? "" : "en")"
        if examples > 0 { line += ", with example answers for \(examples) more" }
        return line + ". Prüfen compares with it."
    }

    // MARK: - Actions

    private func toggle(_ exercise: WorksheetExercise) {
        if chosen[exercise.page] != nil {
            chosen[exercise.page] = nil
        } else {
            chosen[exercise.page] = exercise.verdict == .interactive ? .answer : .pencil
        }
    }

    private func load() async {
        guard loading else { return }
        guard let url = material.snapshotURL, let data = try? Data(contentsOf: url) else {
            loading = false
            return
        }
        thumbnails = PDFPageThumbnails(pdfData: data)
        let document = WorksheetDocumentActor(data: data)
        if let prefetched {
            pages = prefetched
        } else {
            pages = await document.allPages()
        }
        keyReading = await document.answerKey()
        if let existing = material.worksheet {
            chosen = Dictionary(existing.pages.map { ($0.page, $0.mode) }, uniquingKeysWith: { first, _ in first })
        } else {
            for exercise in exercisePages where !exercise.hasTypedAnswers {
                chosen[exercise.page] = exercise.verdict == .interactive ? .answer : .pencil
            }
        }
        loading = false
    }

    private func save() {
        let byPage = Dictionary(pages.map { ($0.page, $0) }, uniquingKeysWith: { first, _ in first })
        let plans = chosen.keys.sorted().compactMap { number -> WorksheetPagePlan? in
            guard let mode = chosen[number] else { return nil }
            let exercise = byPage[number]
            // A page the app can't answer is worked with the Pencil whatever was picked.
            let resolved: WorksheetPagePlan.Mode = exercise?.verdict == .interactive ? mode : .pencil
            var plan = WorksheetPagePlan(page: number, mode: resolved,
                                         title: exercise?.displayTitle ?? "Seite \(number)")
            if let items = exercise?.items {
                plan.anchors = Dictionary(items.map { ($0.key, $0.anchor) }, uniquingKeysWith: { first, _ in first })
            }
            return plan
        }
        var setup = material.worksheet ?? WorksheetSetup(parserVersion: WorksheetParser.version, pages: [])
        setup.pages = plans
        setup.parserVersion = WorksheetParser.version
        if let keyReading {
            setup.key = keyReading.key
            setup.samples = keyReading.samples.isEmpty ? nil : keyReading.samples
        }
        material.worksheet = plans.isEmpty ? nil : setup
        noteHomework(plans)
        try? modelContext.save()
        onDone(!plans.isEmpty)
    }

    /// The exercises go on the class entry's homework, so the Homework lists show them and open
    /// them. One short line ("9 Übungen aus <handout>"; the titles are on the exercise screen),
    /// added to what the learner wrote, never over it, and replacing this handout's earlier line.
    private func noteHomework(_ plans: [WorksheetPagePlan]) {
        guard let entry = material.entry, !plans.isEmpty else { return }
        let count = plans.count == 1 ? "1 Übung" : "\(plans.count) Übungen"
        let line = "\(count) aus \(material.title)"
        let current = entry.homework.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = current.split(separator: "\n").filter { existing in
            // This handout's line, in the current form or the first one ("Übungen (title): …").
            !(existing.contains(material.title) && existing.contains("Übung"))
        }
        entry.homework = (kept.map(String.init) + [line]).joined(separator: "\n")
        entry.homeworkDone = false
        entry.updatedAt = .now
    }

    private struct PagePreview: Identifiable {
        let page: Int
        var id: Int { page }
    }
}

// MARK: - Thumbnails

/// One slide, small, from the shared thumbnail cache.
struct WorksheetThumbnail: View {
    let thumbnails: PDFPageThumbnails?
    let page: Int

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.12))
            if let image = thumbnails?.thumbnail(page: page) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("\(page)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.quaternary))
        .task(id: page) { await thumbnails?.request(page: page, width: 240) }
    }
}

/// A slide at reading size: "is page 21 the one we did in class?"
struct WorksheetPagePreviewSheet: View {
    let thumbnails: PDFPageThumbnails?
    let page: Int

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Seite \(page)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { image = await thumbnails?.fullPage(page) }
    }
}
