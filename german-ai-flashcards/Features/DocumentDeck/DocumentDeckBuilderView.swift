//
//  DocumentDeckBuilderView.swift
//  german-ai-flashcards
//
//  From a document's text to a deck. Two ways in, both feeding one list of rows:
//   • **Word list** — a two-column sheet the parser paired (`VocabListParser`), every row
//     editable, guessed splits flagged, the sheet's ✓ marks kept so "only the quiz words" is one
//     toggle; the tutor can re-read a list the parser misjudged.
//   • **From the text** — a story or a handout: double-tap a word or highlight a phrase and add
//     it as one card. A phrase is one card, not one card per word.
//  Rows without English are translated by the tutor when the deck is made, if a tutor is on the
//  device; otherwise they are skipped and the button says so.
//

import SwiftUI
import SwiftData

struct DocumentDeckBuilderView: View {
    let draft: DocumentDeckDraft
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    var course: ClassCourse? = nil
    /// Presented as the sheet's root (a Cancel button is needed) rather than pushed.
    var isRoot = false
    var onCreated: (SavedDeck) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Query(sort: \ClassCourse.sortOrder) private var allCourses: [ClassCourse]

    private enum Mode: String, CaseIterable, Identifiable {
        case list = "Word list"
        case text = "From the text"
        var id: String { rawValue }
    }

    private enum Field: Hashable {
        case title
        case german(UUID), english(UUID)
    }

    @State private var mode: Mode = .list
    @State private var rows: [VocabListRow] = []
    @State private var title = ""
    @State private var hasMarks = false
    @State private var onlyMarked = false
    @State private var guessedCount = 0
    @State private var courseID: UUID?
    @State private var service: DocumentDeckService?
    @State private var showProgress = false
    @State private var errorMessage: String?
    @State private var loaded = false
    @FocusState private var focused: Field?

    private let accent = ClassNotesTile.tint

    private var courses: [ClassCourse] { allCourses.filter { !$0.isArchived } }
    private var selectedCourse: ClassCourse? { courses.first { $0.id == courseID } }

    /// Tutors already on this device that it can run, best first: what the picker offers. Never a
    /// download for a deck.
    private var downloadedTutors: [MLXModel] {
        let rank: (MLXModel) -> Int = { MLXModel.germanTutors.firstIndex(of: $0) ?? MLXModel.germanTutors.count }
        return MLXModel.allCases
            .filter { $0.isDownloaded && DeviceCapability.mayRun($0) }
            .sorted { rank($0) < rank($1) }
    }

    /// The tutor that pairs and translates: the learner's document tutor when it is on the device,
    /// else the best one that is.
    private var tutor: MLXModel {
        let picked = modelManager.selectedPaperModel
        if picked.isDownloaded, DeviceCapability.mayRun(picked) { return picked }
        return downloadedTutors.first ?? picked
    }
    private var tutorOnDevice: Bool { tutor.isDownloaded }

    private var chosenRows: [VocabListRow] {
        rows.filter { !$0.german.trimmingCharacters(in: .whitespaces).isEmpty && (!onlyMarked || $0.marked) }
    }
    private var completeCount: Int { chosenRows.filter(\.isComplete).count }
    private var pendingCount: Int { chosenRows.count - completeCount }
    private var markedCount: Int { rows.filter(\.marked).count }
    /// Lowercased words already on a row, for the text picker's highlight.
    private var pickedWords: Set<String> {
        var words = Set<String>()
        for row in rows {
            for token in row.german.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" }) {
                words.insert(String(token))
            }
        }
        return words
    }

    var body: some View {
        Form {
            deckSection
            modeSection
            if mode == .list {
                rowsSection
            } else {
                textSection
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Make flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .safeAreaInset(edge: .bottom) {
            makeButton
        }
        .overlay {
            if showProgress, let service {
                progressOverlay(service)
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private var deckSection: some View {
        Section {
            TextField("Deck name", text: $title)
                .focused($focused, equals: .title)
            if !courses.isEmpty {
                Picker("Course", selection: $courseID) {
                    Text("None").tag(UUID?.none)
                    ForEach(courses) { course in
                        Text(course.name).tag(Optional(course.id))
                    }
                }
            }
            if !downloadedTutors.isEmpty {
                Picker("Tutor", selection: Binding(
                    get: { tutor },
                    set: { modelManager.selectedPaperModel = $0 }
                )) {
                    ForEach(downloadedTutors) { model in
                        Text(model.rawValue).tag(model)
                    }
                }
            }
        } header: {
            Text("Deck").themedSectionHeader()
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if !courses.isEmpty {
                    Text("A deck with a course shows on that course's page under Deutschkurs.")
                }
                Text(downloadedTutors.isEmpty
                     ? "No tutor is on this device yet. A word list still becomes a deck; download a tutor in Settings ▸ Model to translate what has no English."
                     : "The tutor translates rows without English and can re-read a list the reader got wrong. Only tutors already on this device are listed.")
            }
            .font(.caption2)
        }
        .themedListRow()
    }

    private var modeSection: some View {
        Section {
            Picker("How", selection: $mode.animation()) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(mode == .list
                 ? "The document read as a two-column word list, one row per card."
                 : "Double-tap a word, or highlight a phrase and choose Add as card. A phrase becomes one card.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var rowsSection: some View {
        Section {
            if rows.isEmpty {
                Text("No word pairs found in this document. Switch to From the text and pick the words and phrases you want.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if hasMarks {
                Toggle(isOn: $onlyMarked.animation()) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only marked rows (✓)")
                        Text("\(markedCount) of \(rows.count) rows carry the sheet's mark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach($rows) { $row in
                if !onlyMarked || row.marked {
                    rowEditor($row)
                }
            }
            .onDelete { offsets in
                // Offsets index the visible rows; map them back when the marked filter is on.
                let visible = rows.indices.filter { !onlyMarked || rows[$0].marked }
                let doomed = Set(offsets.map { visible[$0] })
                rows = rows.enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
            }
            Button {
                addRow()
            } label: {
                Label("Add a row", systemImage: "plus.circle")
            }
            if !draft.text.isEmpty {
                Button {
                    reparse()
                } label: {
                    Label("Read the list again", systemImage: "arrow.counterclockwise")
                }
                Button {
                    pairWithTutor()
                } label: {
                    Label("Let the tutor pair the list", systemImage: "sparkles")
                }
                .disabled(!tutorOnDevice)
            }
        } header: {
            Text("Pairs · \(chosenRows.count)").themedSectionHeader()
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if guessedCount > 0 {
                    Text("An orange dot marks a row whose German/English split was a guess. Check it, or swipe right to swap the sides.")
                }
                Text(tutorOnDevice
                     ? "If the columns came out wrong, the tutor can read the list instead."
                     : "Download a tutor in Settings to have the list read by the AI or missing translations filled in.")
            }
            .font(.caption2)
        }
        .themedListRow()
    }

    private func rowEditor(_ row: Binding<VocabListRow>) -> some View {
        HStack(spacing: 8) {
            if !row.wrappedValue.confident {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Guessed split")
            }
            TextField("German", text: row.german, axis: .vertical)
                .focused($focused, equals: .german(row.wrappedValue.id))
                .textInputAutocapitalization(.never)
                .lineLimit(1...3)
            Divider()
            TextField("English", text: row.english, axis: .vertical)
                .focused($focused, equals: .english(row.wrappedValue.id))
                .textInputAutocapitalization(.never)
                .lineLimit(1...3)
                .foregroundStyle(.secondary)
            if row.wrappedValue.marked {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .accessibilityLabel("Marked on the sheet")
            }
        }
        .font(.subheadline)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                let german = row.wrappedValue.german
                row.wrappedValue.german = row.wrappedValue.english
                row.wrappedValue.english = german
                row.wrappedValue.confident = true
            } label: {
                Label("Swap", systemImage: "arrow.left.arrow.right")
            }
            .tint(accent)
        }
    }

    private var textSection: some View {
        Section {
            SelectableGermanText(
                text: draft.text.replacingOccurrences(of: #"\n?\[Seite \d+\]\n?"#, with: "\n\n", options: .regularExpression),
                textStyle: .body,
                savedWords: pickedWords,
                onTapWord: { add(phrase: $0) },
                onTranslateSelection: { add(phrase: $0) },
                translateActionTitle: "Add as card",
                translateActionSymbol: "rectangle.stack.badge.plus",
                onSavePhrase: nil
            )
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("Text").themedSectionHeader()
                Spacer()
                Button {
                    withAnimation { mode = .list }
                } label: {
                    Text("\(chosenRows.count) card\(chosenRows.count == 1 ? "" : "s") so far")
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                }
            }
        } footer: {
            Text("Words already on a card are washed in color. Everything you add here is translated by the tutor when the deck is made.")
                .font(.caption2)
        }
        .themedListRow()
    }

    @ViewBuilder
    private var makeButton: some View {
        VStack(spacing: 6) {
            Button {
                makeDeck()
            } label: {
                Text(makeTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
            .disabled(completeCount == 0 && !(pendingCount > 0 && tutorOnDevice))
            if pendingCount > 0 {
                Text(tutorOnDevice
                     ? "\(pendingCount) without English: the tutor translates them first."
                     : "\(pendingCount) without English will be left out; no tutor is downloaded to translate them.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var makeTitle: String {
        let count = tutorOnDevice ? chosenRows.count : completeCount
        return count == 0 ? "Make the deck" : "Make the deck · \(count) card\(count == 1 ? "" : "s")"
    }

    private func progressOverlay(_ service: DocumentDeckService) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: service.progress)
                    .tint(accent)
                Text(service.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(16), style: .continuous))
            .padding()
        }
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        courseID = course?.id
        reparse()
        if title.isEmpty { title = draft.title }
    }

    private func reparse() {
        let parsed = VocabListParser.parse(draft.text)
        rows = parsed.rows
        hasMarks = parsed.hasMarks
        onlyMarked = false
        guessedCount = parsed.guessedCount
        mode = parsed.looksLikeList ? .list : .text
        if let sheetTitle = parsed.title, title.isEmpty || title == draft.title {
            title = sheetTitle
        }
        errorMessage = nil
    }

    private func addRow() {
        if let last = rows.last, last.german.trimmingCharacters(in: .whitespaces).isEmpty {
            focused = .german(last.id)
            return
        }
        let row = VocabListRow(german: "", english: "", marked: false, confident: true)
        rows.append(row)
        focused = .german(row.id)
    }

    /// A word or a highlighted phrase from the text: one row, English to come from the tutor.
    private func add(phrase: String) {
        let cleaned = phrase
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?„“”\"()"))
        guard cleaned.count >= 2 else { return }
        let key = DocumentDeckService.key(cleaned)
        guard !rows.contains(where: { DocumentDeckService.key($0.german) == key }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            rows.append(VocabListRow(german: cleaned, english: "", marked: false, confident: true))
        }
    }

    private func pairWithTutor() {
        focused = nil
        let lines = draft.text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.range(of: #"^\[Seite \d+\]$"#, options: .regularExpression) == nil }
        guard !lines.isEmpty else { return }
        let svc = DocumentDeckService(mlxService: mlxService, modelContext: modelContext)
        service = svc
        showProgress = true
        Task {
            var paired = await svc.pair(lines: lines, model: tutor)
            // The sheet's marks survive the tutor's rewrite: a row is marked when the line it came
            // from carried one.
            if var rows = paired {
                let markedLines = lines.filter { $0.unicodeScalars.contains { "✓✔☑✅★".unicodeScalars.contains($0) } }.map { $0.lowercased() }
                for index in rows.indices {
                    let german = rows[index].german.lowercased()
                    rows[index].marked = markedLines.contains { $0.contains(german) }
                }
                paired = rows
            }
            showProgress = false
            if let paired {
                rows = paired
                hasMarks = paired.contains(where: \.marked)
                guessedCount = 0
                onlyMarked = false
                errorMessage = nil
            } else if case .failed(let message) = svc.phase {
                errorMessage = message
            }
        }
    }

    private func makeDeck() {
        focused = nil
        errorMessage = nil
        let svc = DocumentDeckService(mlxService: mlxService, modelContext: modelContext)
        service = svc
        let chosen = chosenRows
        Task {
            var final = chosen
            if pendingCount > 0, tutorOnDevice {
                showProgress = true
                final = await svc.translate(chosen, model: tutor)
                showProgress = false
                if case .failed(let message) = svc.phase {
                    errorMessage = message
                    return
                }
            }
            if let deck = svc.save(title: title, rows: final, course: selectedCourse, sourceLabel: draft.sourceLabel) {
                onCreated(deck)
            } else {
                errorMessage = "No row had both a German and an English side."
            }
        }
    }
}

// MARK: - Preview

@MainActor
private func documentDeckBuilderPreview(_ theme: AppTheme) -> some View {
    NavigationStack {
        DocumentDeckBuilderView(
            draft: DocumentDeckDraft(
                title: "Vokabelliste",
                text: """
                Vokabelliste für „Hänsel und Gretel“
                Deutsch English Study for
                Quiz?
                der Holzhacker lumberjack ✓
                das Bübchen old expression: young boy
                die Sorge/ die Sorgen (pl) worry ✓
                ernähren to feed ✓
                in aller Frühe in the early morning ✓
                anzünden/ zündete…an/ hat
                angezündet to ignite ✓
                """,
                sourceLabel: "PDF"
            ),
            modelManager: MLXModelManager(),
            mlxService: MLXGenerationService(),
            isRoot: true
        ) { _ in }
    }
    .environment(ActivityRouter())
    .environment(\.appTheme, theme)
    .modelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self, SavedDeck.self, SavedCard.self], inMemory: true)
}

#Preview("Builder · System")  { documentDeckBuilderPreview(.klar) }
#Preview("Builder · Soft")    { documentDeckBuilderPreview(.sanft) }
#Preview("Builder · Notebook") { documentDeckBuilderPreview(.kritzel) }
#Preview("Builder · Bauhaus") { documentDeckBuilderPreview(.grundform) }
