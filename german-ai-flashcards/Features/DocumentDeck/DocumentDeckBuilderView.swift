//
//  DocumentDeckBuilderView.swift
//  german-ai-flashcards
//
//  From a document's text to a deck. Two ways in, both feeding one list of rows:
//   • **Word list** — a sheet the parser paired (`VocabListParser`), every row editable, guessed
//     splits flagged, the sheet's ✓ marks kept so "only the quiz words" is one toggle; the tutor
//     can re-read a list the parser misjudged. A document of several pages shows a card per page
//     with the pages that read as a word table already on, and a field to type the pages instead;
//     where the sheet gave an example sentence or a plural, each row shows them under its two
//     fields and one switch keeps or drops them for the whole deck.
//   • **From the text** — a story or a handout: double-tap a word or highlight a phrase and add
//     it as one card. A phrase is one card, not one card per word.
//  A card never has an empty English side. Rows without English are translated by the tutor when
//  the deck is made, if a tutor is on the device; what it can't translate is written back as left
//  out and the deck waits for a second tap, and without a tutor they are left out from the start.
//  Either way the line under the button says how many (`DocumentDeckService.makesCard`).
//
//  Every row carries a Wortart (Nomen, Verb, Adjektiv, Adverb) worked out from the dictionary and
//  the row's own shape, tappable to correct and stored on the card. A document with a real PDF
//  behind it shows each page as a picture, tappable to use or drop and with a magnifier to see it
//  big; anything else keeps the numbered pills.
//
//  A word the sheet lists twice is badged with the page its first mention was on. There are two
//  row predicates and they are not interchangeable: `isOnPage` is what the deck is made of (every
//  count, the merge, both tutor jobs), `isVisible` is what the list draws (that one, minus the
//  repeats when they are hidden). "Hide repeats" must never reach the deck's row set, because
//  `save` merges a repeat into the first mention to fill its holes.
//
//  Reading the document happens off the main actor and the section says so while it runs: the
//  builder must never show its empty state while it is still reading, which on a 37-page export
//  read as "no word pairs found". Picking pages needs none of that — `rows` always holds every
//  page and the pills are filters over it, so switching a page on or off involves no parse at all.
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

    /// The page the preview sheet is open on.
    private struct EnlargedPage: Identifiable { let id: Int }

    /// Which mention of a word a row is, and the page the first one was on.
    struct RepeatMark: Equatable {
        var ordinal: Int
        var firstPage: Int?
    }

    @State private var mode: Mode = .list
    /// Every page's rows, always. The page strip and the ✓ toggle are filters over this one list,
    /// never a reason to rebuild it — an edit has to survive switching a page off and on again.
    @State private var rows: [VocabListRow] = []
    @State private var pages: [VocabListParser.Page] = []
    @State private var selectedPages: Set<Int> = []
    /// The pills written out ("8-15, 34-35"), and the same field typed into to set them.
    @State private var pageRangeText = ""
    @State private var pageRangeIsBad = false
    @State private var keepsExtras = true
    /// A view filter only: the rows it hides still go into the deck, where `save` merges them.
    @State private var hideRepeats = false
    /// Row id → which mention it is and where the first one was. Only repeats have an entry, so
    /// the count is the number of repeats. Held rather than computed: `body` reads the row filter
    /// many times per render, and this is one walk per change instead of one per read.
    @State private var repeatMarks: [UUID: RepeatMark] = [:]
    @State private var tagger = WordClassTagger()
    /// Nil when the draft carries no PDF; then the strip is the old numbered pills.
    @State private var thumbnails: PDFPageThumbnails?
    @State private var enlarged: EnlargedPage?
    @State private var title = ""
    @State private var onlyMarked = false
    @State private var courseID: UUID?
    @State private var service: DocumentDeckService?
    @State private var showProgress = false
    @State private var errorMessage: String?
    /// Rows the tutor was asked to translate and left without English of their own. They're left
    /// out of the deck, counted under the button, and not sent to the tutor again.
    @State private var untranslatable: Set<UUID> = []
    @State private var loaded = false
    /// True until the first parse comes back. The rows section says so rather than drawing its
    /// empty state, which on a long document read as "no words found" while it was still reading.
    @State private var isParsing = true
    /// The document with its `[Seite N]` markers taken out, for the text picker. Computed once with
    /// the parse: it used to be a regular-expression pass run inside `body`, i.e. on every render.
    @State private var pickText = ""
    @FocusState private var focused: Field?

    private let accent = ClassNotesTile.tint

    private var courses: [ClassCourse] { allCourses.filter { !$0.isArchived } }
    private var selectedCourse: ClassCourse? { courses.first { $0.id == courseID } }

    /// Tutors already on this device, best first (`DocumentTutorChoice`); the one that pairs and
    /// translates here is the learner's document tutor when it is among them.
    private var downloadedTutors: [MLXModel] { DocumentTutorChoice.downloaded }
    private var tutor: MLXModel { DocumentTutorChoice.current(modelManager) }
    private var tutorOnDevice: Bool { tutor.isDownloaded }

    /// Which rows the deck is made of. A row the learner typed has no page and is always in, so
    /// "From the text" still works with every page switched off. Every count, the merge and both
    /// tutor jobs read this one — never `isVisible`.
    private func isOnPage(_ row: VocabListRow) -> Bool {
        !row.german.trimmingCharacters(in: .whitespaces).isEmpty
            && (!onlyMarked || row.marked)
            && (row.page.map(selectedPages.contains) ?? true)
    }

    /// Which rows the list draws. The same set, minus the repeats when they are hidden — and
    /// *only* the list and its delete offsets may use it, so hiding a repeat can never quietly
    /// drop the example or plural that mention was going to contribute to the card.
    private func isVisible(_ row: VocabListRow) -> Bool {
        isOnPage(row) && !(hideRepeats && repeatMarks[row.id] != nil)
    }

    private var chosenRows: [VocabListRow] { rows.filter(isOnPage) }
    /// Rows that are cards as they stand (`DocumentDeckService.makesCard`).
    private var completeCount: Int { chosenRows.filter(DocumentDeckService.makesCard).count }
    /// Rows with no English yet that the tutor hasn't tried: it translates them when the deck is made.
    private var pendingCount: Int { chosenRows.filter(isPending).count }
    /// Rows that won't become cards: English the tutor couldn't supply, or English that is no
    /// English of their own (the German again, a German note, a dash). Pending rows count here
    /// too when no tutor is on the device to translate them.
    private var leftOutCount: Int {
        chosenRows.filter { !DocumentDeckService.makesCard($0) && !(isPending($0) && tutorOnDevice) }.count
    }
    private func isPending(_ row: VocabListRow) -> Bool {
        row.english.trimmingCharacters(in: .whitespaces).isEmpty && !untranslatable.contains(row.id)
    }
    /// What the deck will actually hold. A word the sheet lists twice — a Wortliste repeating what
    /// the lesson pages taught — is one card, so the rows are counted by the same key `save` merges
    /// on. Without this the button promises 80 cards and the deck holds 40.
    private var cardCount: Int {
        var seen = Set<String>()
        for row in chosenRows where DocumentDeckService.makesCard(row) || (isPending(row) && tutorOnDevice) {
            seen.insert(DocumentDeckService.key(row.german))
        }
        return seen.count
    }
    // These two describe the ✓ filter itself ("12 of 40 rows carry the mark"), so they deliberately
    // keep the page predicate inline rather than going through `isOnPage` — that one already applies
    // `onlyMarked`, and counting through it would make the caption describe itself.
    private var markedCount: Int { rows.filter { $0.marked && ($0.page.map(selectedPages.contains) ?? true) }.count }
    private var onPageCount: Int { rows.filter { $0.page.map(selectedPages.contains) ?? true }.count }
    private var repeatCount: Int { repeatMarks.count }
    private var hasMarks: Bool { chosenRows.contains(where: \.marked) || markedCount > 0 }
    private var guessedCount: Int { chosenRows.filter { !$0.confident }.count }
    /// Whether the sheet gave anything beyond the two columns, so the switch is worth showing.
    private var hasExtras: Bool { chosenRows.contains { $0.example != nil || $0.forms != nil } }
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
                if pages.count > 1 { pagesSection }
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
        .task { await load() }
        .onChange(of: rows) { _, _ in refreshRepeats() }
        .onChange(of: selectedPages) { _, _ in refreshRepeats() }
        .onChange(of: onlyMarked) { _, _ in refreshRepeats() }
        .onDisappear { thumbnails?.purge() }
        .sheet(item: $enlarged) { item in
            if let thumbnails {
                DocumentPagePreviewSheet(
                    pages: pages,
                    thumbnails: thumbnails,
                    accent: accent,
                    selectedPages: Binding(
                        get: { selectedPages },
                        set: { selectedPages = $0; writePageRangeText() }
                    ),
                    startAt: item.id
                )
            }
        }
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
            DocumentTutorPicker(modelManager: modelManager)
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
            .disabled(isParsing)
        } footer: {
            Text(mode == .list
                 ? "The document read as a word list, one row per card. A sheet that prints an example sentence or a plural keeps them."
                 : "Double-tap a word, or highlight a phrase and choose Add as card. A phrase becomes one card.")
                .font(.caption2)
        }
        .themedListRow()
    }

    /// One card per page the parser read, the pages that read as a word table already on, plus the
    /// same selection as a field to type. A 50-page module is quicker to say than to tap, and a
    /// page the detector read wrong needs a way in that does not depend on it.
    private var pagesSection: some View {
        Section {
            DocumentDeckPageStrip(
                pages: pages,
                selectedPages: selectedPages,
                thumbnails: thumbnails,
                accent: accent,
                onToggle: { number in
                    if selectedPages.contains(number) {
                        selectedPages.remove(number)
                    } else {
                        selectedPages.insert(number)
                    }
                    writePageRangeText()
                },
                onEnlarge: { enlarged = EnlargedPage(id: $0) }
            )
            HStack(spacing: 10) {
                TextField("e.g. 8-15, 34-35", text: $pageRangeText)
                    .font(.subheadline.monospacedDigit())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .foregroundStyle(pageRangeIsBad ? Color.red : Color.primary)
                    .onSubmit(applyPageRangeText)
                    .onChange(of: pageRangeText) { _, _ in pageRangeIsBad = false }
                Button("All") {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedPages = Set(pages.map(\.number))
                        writePageRangeText()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                Button("None") {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedPages = []
                        writePageRangeText()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
            }
            .font(.subheadline)
        } header: {
            Text("Seiten · Pages \(selectedPages.count) of \(pages.count)").themedSectionHeader()
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if pageRangeIsBad {
                    Text("Pages are numbers and ranges, separated by commas: 8-15, 34-35.")
                } else if thumbnails != nil {
                    Text("The pages that read as a word table are on. Tap a page to use it or drop it, the magnifier to see it big, or type the ones you want.")
                } else {
                    Text("The pages that read as a word table are on. Tap a page to add or drop it, or type the ones you want.")
                }
                if let thumbnails, pages.count < thumbnails.documentPageCount {
                    Text("Only pages with text can be read: \(pages.count) of \(thumbnails.documentPageCount) pages carry words.")
                }
            }
            .font(.caption2)
        }
        .themedListRow()
    }

    private var rowsSection: some View {
        Section {
            if isParsing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Die Liste wird gelesen…").font(.subheadline)
                    }
                    Text("Pages and pairs appear as soon as the document has been read.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if chosenRows.isEmpty {
                Text(pages.count > 1 && selectedPages.isEmpty
                     ? "No pages are switched on. Tap a page above, or switch to From the text and pick the words you want."
                     : "No word pairs found in this document. Switch to From the text and pick the words and phrases you want.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if hasMarks {
                Toggle(isOn: $onlyMarked.animation()) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only marked rows (✓)")
                        Text("\(markedCount) of \(onPageCount) rows carry the sheet's mark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if repeatCount > 0 {
                Toggle(isOn: $hideRepeats.animation()) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide repeats")
                        Text("\(repeatCount) of \(chosenRows.count) rows repeat a word from another page")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if hasExtras {
                Toggle(isOn: $keepsExtras.animation()) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep examples and plurals")
                        Text("The sheet's example sentence and plural go on the card")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach($rows) { $row in
                if isVisible(row) {
                    rowEditor($row)
                }
            }
            .onDelete { offsets in
                // Offsets index the visible rows; map them back through the same predicate the
                // list drew them with.
                let visible = rows.indices.filter { isVisible(rows[$0]) }
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
                    Task { await reparse() }
                } label: {
                    Label("Read the list again", systemImage: "arrow.counterclockwise")
                }
                .disabled(isParsing)
                Button {
                    pairWithTutor()
                } label: {
                    Label("Let the tutor pair the list", systemImage: "sparkles")
                }
                .disabled(!tutorOnDevice || isParsing)
            }
        } header: {
            Text(isParsing
                 ? "Paare · Pairs"
                 : repeatCount > 0
                   ? "Paare · Pairs \(chosenRows.count) · \(repeatCount) Dubletten"
                   : "Paare · Pairs \(chosenRows.count)")
                .themedSectionHeader()
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if guessedCount > 0 {
                    Text("An orange dot marks a row whose German/English split was a guess. Check it, or swipe right to swap the sides.")
                }
                if repeatCount > 0 {
                    Text("A word listed twice becomes one card either way; the second mention only fills what the first was missing.")
                }
                Text("The word class comes from the dictionary and the row itself. Tap a tag to correct it; it goes on the card, so a later grammar drill can pick out the verbs.")
                Text(tutorOnDevice
                     ? "If the columns came out wrong, the tutor can read the list instead."
                     : "Download a tutor in Settings to have the list read by the AI or missing translations filled in.")
            }
            .font(.caption2)
        }
        .themedListRow()
    }

    private func rowEditor(_ row: Binding<VocabListRow>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            rowFields(row)
            // What the sheet said beyond the two columns, read-only: the two fields stay the only
            // things to tap, so a row does not grow four targets to hit with a thumb.
            if keepsExtras, row.wrappedValue.example != nil || row.wrappedValue.forms != nil {
                HStack(spacing: 8) {
                    if let forms = row.wrappedValue.forms {
                        Text(forms)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(accent)
                    }
                    if let example = row.wrappedValue.example {
                        Text(example)
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
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

    private func rowFields(_ row: Binding<VocabListRow>) -> some View {
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
            TextField(englishPlaceholder(row.wrappedValue), text: row.english, axis: .vertical)
                .focused($focused, equals: .english(row.wrappedValue.id))
                .textInputAutocapitalization(.never)
                .lineLimit(1...3)
                .foregroundStyle(.secondary)
            WordClassChip(wordClass: row.wrappedValue.wordClass) { picked in
                row.wrappedValue.wordClass = picked
            }
            if let mark = repeatMarks[row.wrappedValue.id] {
                repeatBadge(mark)
            }
            if row.wrappedValue.marked {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                    .accessibilityLabel("Marked on the sheet")
            }
        }
        .font(.subheadline)
    }

    /// "2× S. 8": this is the second mention, the first was on page 8. In accent rather than
    /// orange, which on this very row already means "the German/English split was a guess".
    /// An empty English field says what will happen to the row, so a blank never reads as a card.
    private func englishPlaceholder(_ row: VocabListRow) -> String {
        if untranslatable.contains(row.id) { return "No English: left out" }
        return tutorOnDevice ? "Tutor translates" : "English"
    }

    private func repeatBadge(_ mark: RepeatMark) -> some View {
        Text(mark.firstPage.map { "\(mark.ordinal)× S. \($0)" } ?? "\(mark.ordinal)× dabei")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(accent.opacity(0.14), in: appTheme.pillShape)
            .accessibilityLabel(mark.firstPage.map { "Repeat of the word on page \($0)" }
                                ?? "Repeat of a word already on the list")
    }

    private var textSection: some View {
        Section {
            SelectableGermanText(
                text: pickText,
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
            .disabled(isParsing || (completeCount == 0 && !(pendingCount > 0 && tutorOnDevice)))
            if let note = leftOutNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Under the button: what the tutor will translate, and what stays out of the deck. A card
    /// never has an empty English side, so a row without English is either translated or left out,
    /// and the learner is told which before anything is made.
    private var leftOutNote: String? {
        var parts: [String] = []
        if pendingCount > 0, tutorOnDevice {
            parts.append("\(pendingCount) without English: the tutor translates them first, and any it can't are left out.")
        }
        if leftOutCount > 0 {
            parts.append(leftOutCount == 1
                ? "1 row has no English of its own and is left out."
                : "\(leftOutCount) rows have no English of their own and are left out.")
            if pendingCount > 0, !tutorOnDevice {
                parts.append("No tutor is downloaded to translate them.")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var makeTitle: String {
        let count = cardCount
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

    private func load() async {
        guard !loaded else { return }
        loaded = true
        courseID = course?.id
        thumbnails = PDFPageThumbnails(draft: draft)
        if title.isEmpty { title = draft.title }
        await reparse()
    }

    /// One hop off the main actor for the whole read. `VocabListParser` is `nonisolated` and its
    /// `Page`/`VocabListRow` are plain value types, so the pages come back across on their own.
    /// Note the fold rather than a second `parse(draft.text)`: a 37-page document was being read
    /// twice, on the main thread, to answer one question about it.
    private func reparse() async {
        isParsing = true
        let text = draft.text
        let (parsed, picker) = await Task.detached(priority: .userInitiated) {
            (VocabListParser.pages(text), Self.readingText(text))
        }.value

        pages = parsed
        rows = parsed.flatMap(\.rows)
        pickText = picker
        onlyMarked = false
        keepsExtras = true

        // The pages that read as a vocabulary table start on. Nothing reading that way (a story,
        // a one-page handout) means the whole document is on and the list, if any, is all of it.
        selectedPages = Set(parsed.filter(\.looksLikeVocab).map(\.number))
        let foundVocabPages = !selectedPages.isEmpty
        if !foundVocabPages { selectedPages = Set(parsed.map(\.number)) }
        writePageRangeText()

        // A module of 40 pages is mostly exercises, so the whole document scores well under the
        // list threshold even when eight of its pages are perfect word tables. One such page is
        // enough to open on the list.
        mode = foundVocabPages || VocabListParser.fold(parsed).looksLikeList ? .list : .text

        if title.isEmpty || title == draft.title,
           let sheetTitle = parsed.first(where: { selectedPages.contains($0.number) && $0.title != nil })?.title {
            title = sheetTitle
        }
        errorMessage = nil
        isParsing = false
        await tagWordClasses()
    }

    /// The document as the text picker shows it: the `[Seite N]` markers out, the page break left as
    /// a blank line. Hoisted out of `body` so a long document is scanned once, not once per render.
    static func readingText(_ text: String) -> String {
        text.replacingOccurrences(of: #"\n?\[Seite \d+\]\n?"#, with: "\n\n", options: .regularExpression)
    }

    // MARK: - Pages

    /// The pills written back into the field, runs collapsed ("8,9,10,34" → "8-10, 34").
    private func writePageRangeText() {
        pageRangeIsBad = false
        pageRangeText = Self.describe(selectedPages)
    }

    private func applyPageRangeText() {
        guard let picked = Self.pageSelection(pageRangeText, in: Set(pages.map(\.number))) else {
            pageRangeIsBad = true
            return
        }
        withAnimation(.snappy(duration: 0.2)) {
            selectedPages = picked
            writePageRangeText()
        }
    }

    /// "8-15, 34-35" → those page numbers, keeping only pages the document has. Nil when the text
    /// says nothing a page number could be read out of, so the field can say so and change nothing.
    static func pageSelection(_ text: String, in available: Set<Int>) -> Set<Int>? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return [] }
        var picked = Set<Int>()
        for part in parts {
            let ends = part.split(separator: "-", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let numbers = ends.compactMap(Int.init)
            guard numbers.count == ends.count, let first = numbers.first, let last = numbers.last,
                  numbers.count <= 2 else { return nil }
            for page in min(first, last)...max(first, last) where available.contains(page) {
                picked.insert(page)
            }
        }
        return picked
    }

    /// The inverse: a set of page numbers as the runs a learner would have typed.
    static func describe(_ selection: Set<Int>) -> String {
        var runs: [String] = []
        var start: Int?
        var previous: Int?
        for page in selection.sorted() {
            if let last = previous, page == last + 1 { previous = page; continue }
            if let begin = start, let end = previous {
                runs.append(begin == end ? "\(begin)" : "\(begin)-\(end)")
            }
            start = page
            previous = page
        }
        if let begin = start, let end = previous {
            runs.append(begin == end ? "\(begin)" : "\(begin)-\(end)")
        }
        return runs.joined(separator: ", ")
    }

    // MARK: - Dubletten

    /// The rows that repeat a word already listed, keyed by row id: ordinal 2 for the second
    /// mention, 3 for the third, with the page the first one was on. A first mention gets no entry.
    ///
    /// The key is `DocumentDeckService.key` — the same one `save` merges on and `cardCount` counts
    /// with, so the badge can never say something the deck then contradicts. Pass only the rows on
    /// screen: a repeat is a repeat among those, so switching a page off can promote one to being
    /// the only mention, and its badge goes away.
    static func repeatMarks(in rows: [VocabListRow]) -> [UUID: RepeatMark] {
        var firstSeen: [String: (page: Int?, count: Int)] = [:]
        var marks: [UUID: RepeatMark] = [:]
        for row in rows {
            let key = DocumentDeckService.key(row.german)
            guard !key.isEmpty else { continue }
            if let seen = firstSeen[key] {
                firstSeen[key] = (seen.page, seen.count + 1)
                marks[row.id] = RepeatMark(ordinal: seen.count + 1, firstPage: seen.page)
            } else {
                firstSeen[key] = (row.page, 1)
            }
        }
        return marks
    }

    // MARK: - Wortart

    /// Fills in the word class for every row that has none, a chunk at a time. Only nils are
    /// written, so a tag the learner corrected stays corrected; `pair(lines:)` builds fresh rows
    /// and so loses the classes, which is why it calls this again afterwards.
    private func tagWordClasses() async {
        await tagger.tag(rows) { batch in
            for index in rows.indices where rows[index].wordClass == nil {
                if let wordClass = batch[rows[index].id] { rows[index].wordClass = wordClass }
            }
        }
    }

    private func refreshRepeats() {
        repeatMarks = Self.repeatMarks(in: rows.filter(isOnPage))
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
        Task { await tagWordClasses() }
    }

    private func pairWithTutor() {
        focused = nil
        // Only the pages that are on, and with the table's tabs flattened: the tutor is asked for
        // lines "ohne Trennzeichen" and would read a three-column row as one run-on phrase.
        let source = pages.isEmpty
            ? draft.text
            : pages.filter { selectedPages.contains($0.number) }
                .map { page in page.rows.map { "\($0.german) \($0.english)" }.joined(separator: "\n") }
                .joined(separator: "\n")
        let lines = source.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.range(of: #"^\[Seite \d+\]$"#, options: .regularExpression) == nil }
        guard !lines.isEmpty else { return }
        // A tutor of several gigabytes is about to load; the page pictures give up their memory
        // first (docs/MEMORY.md: one heavy resident at a time). They re-render on demand.
        thumbnails?.purge()
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
                // The tutor replaced the page structure, so the pills no longer describe anything.
                pages = []
                selectedPages = []
                pageRangeText = ""
                onlyMarked = false
                errorMessage = nil
                // The tutor's rows are new objects, so they carry no word class; work them out again.
                await tagWordClasses()
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
        // Rows the tutor already couldn't translate aren't asked again.
        let asked = Set(chosen.filter(isPending).map(\.id))
        Task {
            var final = chosen
            if !asked.isEmpty, tutorOnDevice {
                thumbnails?.purge()
                showProgress = true
                let translated = await svc.translate(chosen.filter { !untranslatable.contains($0.id) }, model: tutor)
                showProgress = false
                if case .failed(let message) = svc.phase {
                    errorMessage = message
                    return
                }
                let byID = Dictionary(translated.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                final = chosen.map { byID[$0.id] ?? $0 }
                // The tutor's English goes onto the rows, so the list shows what the deck will hold.
                for row in final where asked.contains(row.id) {
                    if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index].english = row.english }
                }
                // What it couldn't translate (or answered with the German again) is left out. Say
                // so and wait for a second tap, rather than making a deck with holes in silence.
                let failed = final.filter { asked.contains($0.id) && !DocumentDeckService.makesCard($0) }.map(\.id)
                if !failed.isEmpty {
                    untranslatable.formUnion(failed)
                    errorMessage = failed.count == 1
                        ? "The tutor couldn't translate 1 row. It's left out: type its English, or tap Make the deck again."
                        : "The tutor couldn't translate \(failed.count) rows. They're left out: type their English, or tap Make the deck again."
                    return
                }
            }
            if !keepsExtras {
                // Stripped here rather than passed down, so `save` keeps one way of reading a row.
                for index in final.indices {
                    final[index].example = nil
                    final[index].forms = nil
                }
            }
            if let deck = svc.save(title: title, rows: final, course: selectedCourse, sourceLabel: draft.sourceLabel, keeping: draft) {
                onCreated(deck)
            } else {
                errorMessage = "No row had both a German and an English side of its own."
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
    .inMemoryModelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self, SavedDeck.self, SavedCard.self])
}

#Preview("Builder · System")  { documentDeckBuilderPreview(.klar) }
#Preview("Builder · Soft")    { documentDeckBuilderPreview(.sanft) }
#Preview("Builder · Notebook") { documentDeckBuilderPreview(.kritzel) }
#Preview("Builder · Bauhaus") { documentDeckBuilderPreview(.grundform) }
