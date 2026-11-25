//
//  SchreibblattSheetView.swift
//  german-ai-flashcards
//
//  One writing sheet. On an iPad this is the Apple Pencil surface; on an iPhone or a Mac it is the
//  sheet's details and the Share button, because a full A4 page of tables is not a phone screen
//  and the Mac has no `PKCanvasView` at all.
//
//  The fork is on `ThisDevice.kind`, not `horizontalSizeClass`: this is about a physical page and
//  a pencil, not window width — a wide Mac window still has neither.
//
//  The "…" menu: the format (a blank sheet turns or rearranges in place; a written one offers a
//  blank copy in the new format, since that moves every table out from under the ink), the
//  notebook ruling, write the sheet again, and clear it. The paper, the ruling and how the page
//  fits the screen are also in the Pencil rail's gear (`canvasSettings`), next to the writing. Sharing
//  offers the PDF with or without the ruling; an endless sheet is not shared at all. Fertig marks the sheet done and
//  locks it (it scrolls and zooms, nothing writes) until "Wieder öffnen"; the hub lists finished
//  sheets in their own section. Full screen (iPad) takes the inline
//  canvas down a beat before it opens and rebuilds it with the ink written there when it closes,
//  so two canvases never hold one sheet's ink, the same hand-off as the worksheet's.
//
//  Spickzettel (iPad): the words float over the page in a small table that follows the pen
//  (`SchreibblattCribSheet`); the top bar's list button, the full-screen bar's and the gear show or
//  hide it.
//
//  Karten üben: Fertig opens a checkpoint (`SchreibblattCheckpointSheet`) offering the words just
//  written as flashcards, only those, through `DeckStore.practiceSession` (each word is a
//  `SavedCard` id); nothing is offered for words whose card is gone. For one part of a bigger set
//  (`SchreibblattParts`) it also offers the last two parts, everything so far, and the next part,
//  which opens in place of this one (`SchreibblattSheetView` is a host that swaps its page), so
//  working through a deck never stacks one canvas per part. The finished banner, the details and
//  "…" offer the same again.
//

import SwiftData
import SwiftUI

/// One sheet, or the part of a set being written: "Weiter" swaps the page for the next part
/// rather than pushing it, so going back still leads to where the set was opened from.
struct SchreibblattSheetView: View {
    @State private var sheet: SchreibblattSheet

    init(sheet: SchreibblattSheet) {
        _sheet = State(initialValue: sheet)
    }

    var body: some View {
        // A new identity per sheet: its page reads the ink in `init`, and the canvas is made once.
        SchreibblattSheetPage(sheet: sheet, openPart: { sheet = $0 })
            .id(sheet.id)
    }
}

private struct SchreibblattSheetPage: View {
    @Bindable var sheet: SchreibblattSheet
    /// Shows another part of the same set in this page's place.
    let openPart: (SchreibblattSheet) -> Void

    @Environment(\.modelContext) private var modelContext
    /// Optional so a screen shown without the shell (a debug sheet) has no practice offer rather
    /// than a crash.
    @Environment(ActivityRouter.self) private var router: ActivityRouter?
    /// Read in `init`, not `onAppear`: the canvas assigns the drawing exactly once, in
    /// `makeUIView`, and `updateUIView` must never reassign it (that would round-trip the
    /// learner's ink through a copy). `onAppear` runs *after* the canvas is made, so ink loaded
    /// there would silently never reach it and a written sheet would reopen blank.
    @State private var ink: Data?
    @State private var pencil = PencilBoard()
    @AppStorage("schreibblatt.fit") private var fit: SchreibblattFit = .width
    @AppStorage("schreibblatt.paper") private var paper: SchreibblattPaperStyle = .white
    @AppStorage(SchreibblattCrib.shownKey) private var cribShown = true

    /// Full screen, and the hand-off that keeps two canvases off one sheet (`PencilFullScreen`).
    @State private var fullScreen = PencilHandOff()

    @State private var confirmClear = false
    @State private var choosingFormat = false
    /// A written sheet asked for another format: the copy it would make instead.
    @State private var reformatting: SchreibblattFormat?
    @State private var copy: SchreibblattSheet?
    /// The sheet's words that still have a flashcard; empty hides every practice offer.
    @State private var practiceIDs: [UUID] = []
    /// What Fertig opens: practise these words, or more of the set, or write the next part.
    @State private var checkpoint: SchreibblattCheckpoint?
    /// What was picked there, done once the checkpoint is down.
    @State private var checkpointChoice: SchreibblattCheckpoint.Choice?
    /// The part to write after this one, once this one is done.
    @State private var nextPart: SchreibblattSheet?
    /// The flashcard cover this page opened, so the page notices it close and offers the way on.
    @State private var practiceActivityID: String?
    /// What the player's way on asked for (`StudyOnward`), done once its cover is down.
    @State private var onwardChoice: Onward?
    /// The finish screen: the set (or sheet) done, die Figur cheering.
    @State private var finishScreen: SchreibblattFinish?
    /// Its Fertig was tapped: leave the flow once the cover is down.
    @State private var leaveAfterFinish = false

    @Environment(\.dismiss) private var dismiss
    /// Back to the hub past Wörter wählen and the setup screen, when the sheet was made there.
    @Environment(\.schreibblattLeave) private var leaveFlow

    private enum Onward {
        case next(SchreibblattSheet)
        case finish
    }

    init(sheet: SchreibblattSheet, openPart: @escaping (SchreibblattSheet) -> Void) {
        self.sheet = sheet
        self.openPart = openPart
        _ink = State(initialValue: sheet.ink)
    }

    private var layout: SchreibblattLayout { sheet.layout }
    private var hasCanvas: Bool { ThisDevice.kind == .iPad }

    var body: some View {
        content
            .navigationTitle(sheet.title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !sheet.isFinished {
                        Button {
                            finish()
                        } label: {
                            Label("Fertig", systemImage: "checkmark.circle")
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityHint("Marks this sheet done and locks it")
                    }
                    #if os(iOS)
                    if hasCanvas {
                        Button {
                            $fullScreen.open()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .accessibilityLabel("Full screen")
                        if !sheet.isFinished {
                            SchreibblattCribButton(shown: $cribShown)
                        }
                    }
                    #endif
                    if layout.pageCount > 0, sheet.canExport {
                        share
                    }
                    Menu {
                        options
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Sheet options")
                }
            }
            .confirmationDialog("Alles löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Alles löschen", role: .destructive) { pencil.clear() }
            } message: {
                Text("Everything written on this sheet goes. Undo brings it back until you leave the sheet.")
            }
            .confirmationDialog(
                "Change the format?",
                isPresented: Binding(get: { reformatting != nil }, set: { if !$0 { reformatting = nil } }),
                titleVisibility: .visible,
                presenting: reformatting
            ) { format in
                Button("Neues Blatt: \(format.title)") { writeAgain(format) }
            } message: { format in
                Text("A new format moves every table, so your writing stays on this sheet. "
                     + "A new sheet with the same words starts blank: \(format.title).")
            }
            .sheet(isPresented: $choosingFormat) {
                SchreibblattFormatSheet(current: sheet.format, wordCount: layout.wordCount,
                                        repetitions: sheet.repetitions, isBlank: isBlank) { format in
                    reformat(to: format)
                }
            }
            .sheet(item: $checkpoint, onDismiss: actOnCheckpoint) { checkpoint in
                SchreibblattCheckpointSheet(checkpoint: checkpoint) { checkpointChoice = $0 }
            }
            .fullScreenCover(item: $finishScreen, onDismiss: {
                guard leaveAfterFinish else { return }
                leaveAfterFinish = false
                leave()
            }) { finish in
                SchreibblattCelebration(finish: finish) { leaveAfterFinish = true }
            }
            // The cards this page opened have closed: the way on they chose, or the checkpoint again.
            .onChange(of: router?.active?.id) { old, new in
                guard new == nil, let launched = practiceActivityID, old == launched else { return }
                practiceActivityID = nil
                // Once the player's cover is all the way down: `active` goes nil as it starts to
                // leave, and nothing can be presented over a cover still on its way out.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { cardsClosed() }
            }
            .navigationDestination(item: $copy) { SchreibblattSheetView(sheet: $0) }
            // Again on the way back from the cards or a copy: a card may have been deleted since.
            .onAppear { findPracticeCards() }
            .onChange(of: sheet.finishedAt, initial: true) {
                pencil.isLocked = sheet.isFinished
            }
            // Wieder öffnen hides the way on; finishing again finds it.
            .onChange(of: sheet.finishedAt) { findPracticeCards() }
            .onChange(of: paper, initial: true) {
                pencil.darkPaper = paper.isDark
            }
            // The ink is held in `@State`, so it is read again from what the cover wrote.
            .pencilFullScreen($fullScreen, onReturn: { ink = sheet.ink }) {
                SchreibblattFullScreen(sheet: sheet)
            }
    }

    @ViewBuilder
    private var content: some View {
        if hasCanvas {
            Group {
                if !fullScreen.inlineShown {
                    Color(.secondarySystemBackground)
                } else {
                    SchreibblattCanvas(layout: layout, ink: ink, fit: fit, lines: sheet.notebookLines,
                                       paper: paper, pencil: pencil) { data, strokes in
                        save(data, strokes: strokes)
                    }
                    .id(fullScreen.token)
                    .schreibblattNextTable(layout: layout, board: pencil, onFinish: finish)
                    .schreibblattCribSheet(layout: layout, board: pencil)
                    .pencilRail(pencil, accent: SchreibblattTile.tint,
                                canvasSettings: { SchreibblattCanvasSettings(sheet: sheet) },
                                tips: { SchreibblattTips() })
                    .overlay(alignment: .top) {
                        if let finishedAt = sheet.finishedAt {
                            finishedBanner(finishedAt)
                                .padding(.top, 12)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        } else {
            details
        }
    }

    /// Over a finished sheet: when it was done, and the two ways on.
    private func finishedBanner(_ date: Date) -> some View {
        HStack(spacing: 12) {
            Label("Fertig · \(date.formatted(.dateTime.day().month(.abbreviated)))",
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            Button("Wieder öffnen") { setFinished(false) }
                .buttonStyle(.bordered)
            // A sheet on its own leads with Abschließen below; "…" still writes it again.
            if !sheet.isPart && !setIsDone {
                Button("Nochmal schreiben") { writeAgain(sheet.format) }
                    .buttonStyle(.bordered)
            }
            if canPractice {
                Button(sheet.isPart ? "Karten üben…" : "Karten üben") { practiceOrAsk() }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Practice this sheet's words as flashcards")
            }
            if let next = nextPart {
                Button("Weiter: Teil \(next.partIndex + 1)") { openPart(next) }
                    .buttonStyle(.borderedProminent)
                    .tint(SchreibblattTile.tint)
                    .accessibilityHint("Opens the next part of this set")
            } else if setIsDone {
                Button {
                    celebrate()
                } label: {
                    Label("Abschließen", systemImage: "flag.checkered")
                }
                .buttonStyle(.borderedProminent)
                .tint(SchreibblattTile.tint)
                .accessibilityHint("Finishes and goes back to your sheets")
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    /// The PDF as the sheet looks, and without the ruling when it has some (for printing plain).
    @ViewBuilder
    private var share: some View {
        if sheet.notebookLines {
            Menu {
                ShareLink(item: document(lines: true),
                          preview: SharePreview(sheet.title, image: Image(systemName: "doc.text"))) {
                    Label("PDF mit Heftlinien", systemImage: "line.3.horizontal")
                }
                ShareLink(item: document(lines: false),
                          preview: SharePreview(sheet.title, image: Image(systemName: "doc.text"))) {
                    Label("PDF ohne Linien", systemImage: "doc")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share as PDF")
        } else {
            ShareLink(item: document(lines: false),
                      preview: SharePreview(sheet.title, image: Image(systemName: "doc.text")))
        }
    }

    @ViewBuilder
    private var options: some View {
        Section {
            Button {
                choosingFormat = true
            } label: {
                Label("Format: \(sheet.format.title)", systemImage: "rectangle.3.group")
            }
            Toggle(isOn: Binding(get: { sheet.notebookLines }, set: { lines in
                sheet.notebookLines = lines
                try? modelContext.save()
            })) {
                Label("Heftlinien", systemImage: "line.3.horizontal")
            }
        }
        Section {
            Button {
                writeAgain(sheet.format)
            } label: {
                Label("Nochmal schreiben", systemImage: "doc.on.doc")
            }
            if canPractice {
                Button {
                    practiceOrAsk()
                } label: {
                    Label(sheet.isPart ? "Karten üben…" : "Karten üben", systemImage: "rectangle.on.rectangle.angled")
                }
            }
            if let next = nextPart {
                Button {
                    openPart(next)
                } label: {
                    Label("Weiter: \(next.partLabel)", systemImage: "arrow.right.circle")
                }
            }
            if hasCanvas {
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Alles löschen", systemImage: "trash")
                }
                .disabled(pencil.strokeCount == 0 || sheet.isFinished)
            }
            if sheet.isFinished {
                Button {
                    setFinished(false)
                } label: {
                    Label("Wieder öffnen", systemImage: "lock.open")
                }
            }
        }
    }

    /// iPhone and Mac: what the sheet is, and the one thing to do with it here.
    private var details: some View {
        List {
            Section {
                LabeledContent("Wörter", value: "\(layout.wordCount)")
                LabeledContent("Wiederholungen", value: "\(sheet.repetitions)")
                LabeledContent("Seiten", value: sheet.canExport ? "\(layout.pageCount)" : "Endlos")
                LabeledContent("Format", value: sheet.format.title)
                if sheet.isPart {
                    LabeledContent("Teil", value: "\(sheet.partIndex + 1) von \(sheet.partCount)")
                }
            } header: {
                Text("Das Blatt").themedSectionHeader()
            } footer: {
                if !sheet.canExport {
                    Text("An endless sheet is written on the iPad with the Apple Pencil; it is not printed or shared.")
                } else {
                    Text(ThisDevice.kind == .mac
                         ? "Writing on the sheet needs an iPad and an Apple Pencil. Share it as a PDF and write on paper."
                         : "Share it as a PDF to print, or open this sheet on your iPad to write on it with the Apple Pencil.")
                }
            }
            .themedListRow()

            Section {
                if let finishedAt = sheet.finishedAt {
                    Label("Fertig · \(finishedAt.formatted(.dateTime.day().month(.abbreviated)))",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let next = nextPart {
                        Button {
                            openPart(next)
                        } label: {
                            Label("Weiter: \(next.partLabel)", systemImage: "arrow.right.circle.fill")
                        }
                    } else if setIsDone {
                        Button {
                            celebrate()
                        } label: {
                            Label("Abschließen · Finish", systemImage: "flag.checkered")
                        }
                    }
                    if canPractice {
                        Button {
                            practiceOrAsk()
                        } label: {
                            Label(sheet.isPart ? "Karten üben…" : "Karten üben", systemImage: "rectangle.on.rectangle.angled")
                        }
                    }
                    Button("Wieder öffnen") { setFinished(false) }
                    Button("Nochmal schreiben") { writeAgain(sheet.format) }
                } else {
                    Button {
                        finish()
                    } label: {
                        Label("Fertig", systemImage: "checkmark.circle")
                    }
                }
            } footer: {
                Text(sheet.isFinished
                     ? (canPractice
                        ? "Done. Practice these words as flashcards, open the sheet again to keep writing, or start a blank copy to do the drill again."
                        : "Done. Open it again to keep writing, or start a blank copy to do the drill again.")
                     : "Written it out on paper? Mark it done so your list shows it.")
            }
            .themedListRow()

            Section {
                ForEach(sheet.words) { word in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(word.german).font(.body.weight(.medium))
                        Text(word.english).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Vorlage").themedSectionHeader()
            }
            .themedListRow()
        }
        .themedListScreen()
    }

    /// The PDF is written when someone shares, with the ink on disk then.
    private func document(lines: Bool) -> SchreibblattDocument {
        SchreibblattDocument(layout: layout, title: sheet.title, inkFileName: sheet.inkFileName, lines: lines)
    }

    private func save(_ data: Data, strokes: Int) {
        sheet.saveInk(data, strokeCount: strokes)
        try? modelContext.save()
    }

    /// Nothing written, saved or still on the way to disk.
    private var isBlank: Bool { sheet.strokeCount == 0 && pencil.strokeCount == 0 }

    private func reformat(to format: SchreibblattFormat) {
        guard format != sheet.format else { return }
        if isBlank {
            sheet.format = format
            sheet.updatedAt = Date()
            try? modelContext.save()
        } else {
            reformatting = format
        }
    }

    private func setFinished(_ finished: Bool) {
        let now = Date()
        sheet.finishedAt = finished ? now : nil
        sheet.updatedAt = now
        // The day's log hears of a sheet once: its first Fertig.
        if finished, sheet.loggedAt == nil, !sheet.writtenWords.isEmpty {
            sheet.loggedAt = now
            StudyLogService.record(.sheetWords(sheet.writtenWords.count), in: modelContext)
        }
        try? modelContext.save()
    }

    // MARK: Karten üben, the next part, and the finish

    private var canPractice: Bool { router != nil && !practiceIDs.isEmpty }

    /// Finished, with no part left to write: a sheet on its own, or the set's last part.
    private var setIsDone: Bool { sheet.isFinished && nextPart == nil }

    /// Fertig: lock the sheet, then offer its words as flashcards (and, for a part, the rest of
    /// the set so far and the next part; at the end, the last round and the finish).
    private func finish() {
        setFinished(true)
        findPracticeCards()
        checkpoint = makeCheckpoint()
    }

    /// The words that still have a card, and the next part, read again whenever the page shows.
    private func findPracticeCards() {
        let ids = sheet.writtenWords.map(\.id)
        let existing = DeckStore(modelContext: modelContext).existingCardIDs(ids)
        practiceIDs = ids.filter(existing.contains)
        nextPart = nil
        if sheet.isPart, sheet.isFinished {
            let parts = sheet.parts(in: modelContext)
            if let next = SchreibblattParts.nextPart(parts: partFacts(parts, existing: nil), after: sheet.partIndex) {
                nextPart = parts.first { $0.partIndex == next }
            }
        }
    }

    /// The parts as `SchreibblattParts` sees them; with `existing`, only words with a card.
    private func partFacts(_ parts: [SchreibblattSheet], existing: Set<UUID>?) -> [SchreibblattParts.Part] {
        parts.map { part in
            let ids = part.writtenWords.map(\.id)
            return SchreibblattParts.Part(index: part.partIndex,
                                          wordIDs: existing.map { set in ids.filter(set.contains) } ?? ids,
                                          isFinished: part.isFinished)
        }
    }

    /// `practised`: back from the cards, so the title says so and going on leads.
    private func makeCheckpoint(practised: Bool = false) -> SchreibblattCheckpoint {
        let parts = sheet.parts(in: modelContext)
        let allIDs = parts.flatMap { $0.writtenWords.map(\.id) }
        let existing = DeckStore(modelContext: modelContext).existingCardIDs(allIDs)
        let facts = partFacts(parts, existing: existing)
        let options = router == nil ? [] : SchreibblattParts.practiceOptions(parts: facts, current: sheet.partIndex)
        let next = SchreibblattParts.nextPart(parts: facts, after: sheet.partIndex)
            .flatMap { index in parts.first { $0.partIndex == index } }
        let stats = SchreibblattStats.load(in: modelContext)

        guard sheet.isPart else {
            return SchreibblattCheckpoint(
                title: practised ? "Karten geübt" : "Fertig",
                subtitle: "\(SchreibblattParts.words(sheet.writtenWords.count)) written",
                progress: nil, options: options, next: nil, practised: practised, stats: stats)
        }
        let done = parts.filter(\.isFinished)
        let wordsDone = done.reduce(0) { $0 + $1.writtenWords.count }
        let wordsAll = parts.reduce(0) { $0 + $1.writtenWords.count }
        let title = practised
            ? "Karten geübt"
            : (done.count == parts.count ? "Alle Teile geschafft" : "\(sheet.partLabel) geschafft")
        return SchreibblattCheckpoint(
            title: title,
            subtitle: "\(wordsDone) of \(wordsAll) words written · \(done.count) of \(parts.count) parts",
            progress: parts.isEmpty ? nil : Double(done.count) / Double(parts.count),
            options: options, next: next, practised: practised, stats: stats)
    }

    /// A sheet on its own goes straight to its cards; a part asks how much of the set.
    private func practiceOrAsk() {
        if sheet.isPart {
            checkpoint = makeCheckpoint()
        } else {
            practice(practiceIDs, count: practiceIDs.count)
        }
    }

    private func actOnCheckpoint() {
        guard let choice = checkpointChoice else { return }
        checkpointChoice = nil
        switch choice {
        case .practice(let option): practice(option.wordIDs, count: option.wordIDs.count)
        case .next(let part): openPart(part)
        case .finish: celebrate()
        }
    }

    /// These words, and only these, in the flashcard player, with the way on as its main button
    /// at the end: the next part to write, or the finish.
    private func practice(_ ids: [UUID], count: Int) {
        guard let router,
              var session = DeckStore(modelContext: modelContext).practiceSession(
                  cardIDs: ids,
                  topic: sheet.isPart && !sheet.seriesTitle.isEmpty ? sheet.seriesTitle : sheet.title,
                  label: "Schreibblatt · \(SchreibblattParts.words(count))")
        else { return }
        if sheet.isFinished {
            if let next = nextPart {
                session.onward = StudyOnward(title: "Weiter: Teil \(next.partIndex + 1) schreiben",
                                             systemImage: "arrow.right.circle.fill") { onwardChoice = .next(next) }
            } else {
                session.onward = StudyOnward(title: "Abschließen", systemImage: "flag.checkered") {
                    onwardChoice = .finish
                }
            }
        }
        onwardChoice = nil
        practiceActivityID = Activity.cardDeck(session).id
        router.launch(.cardDeck(session))
    }

    /// The cards are down. Their way on if one was tapped; else, on a finished sheet, the
    /// checkpoint again, so going on is never only a banner on a locked page.
    private func cardsClosed() {
        let choice = onwardChoice
        onwardChoice = nil
        switch choice {
        case .next(let part): openPart(part)
        case .finish: celebrate()
        case nil:
            guard sheet.isFinished else { return }
            findPracticeCards()
            checkpoint = makeCheckpoint(practised: true)
        }
    }

    /// The finish screen, then out of the flow.
    private func celebrate() {
        let parts = sheet.parts(in: modelContext)
        let words = parts.reduce(0) { $0 + $1.writtenWords.count }
        let passes = sheet.repetitions == 1 ? "once" : "\(sheet.repetitions) times"
        finishScreen = SchreibblattFinish(
            title: sheet.isPart ? "Alle Teile geschafft!" : "Blatt geschafft!",
            subtitle: sheet.isPart
                ? "\(SchreibblattParts.words(words)) in \(parts.count) parts, each written \(passes)"
                : "\(SchreibblattParts.words(words)), each written \(passes)",
            stats: SchreibblattStats.load(in: modelContext))
    }

    /// Back to where the writing started: the hub, past Wörter wählen and the setup screen when
    /// the sheet was made there; else the list it was opened from.
    private func leave() {
        if let leaveFlow {
            leaveFlow()
        } else {
            dismiss()
        }
    }

    private func writeAgain(_ format: SchreibblattFormat) {
        let made = sheet.blankCopy(format: format)
        modelContext.insert(made)
        try? modelContext.save()
        copy = made
    }
}

// MARK: - Full screen

/// The sheet over the whole screen to write on: no navigation bar, no tab bar, the page fitted to
/// the screen and zoomable.
struct SchreibblattFullScreen: View {
    @Bindable var sheet: SchreibblattSheet

    @Environment(\.modelContext) private var modelContext
    @AppStorage("schreibblatt.fit") private var fit: SchreibblattFit = .width
    @AppStorage("schreibblatt.paper") private var paper: SchreibblattPaperStyle = .white
    @AppStorage(SchreibblattCrib.shownKey) private var cribShown = true
    @State private var ink: Data?
    @State private var pencil = PencilBoard()

    init(sheet: SchreibblattSheet) {
        self.sheet = sheet
        _ink = State(initialValue: sheet.ink)
    }

    var body: some View {
        PencilFullScreenPage {
            Text(sheet.title)
                .font(.headline)
                .lineLimit(1)
        } end: {
            // The crib sheet's switch, about as wide as Done, so the title stays in the middle; the
            // paper and the fit are in the dock's gear.
            if sheet.isFinished {
                Label("Done", systemImage: "arrow.down.right.and.arrow.up.left")
                    .padding(.horizontal, 12)
                    .hidden()
            } else {
                SchreibblattCribButton(shown: $cribShown, titled: true)
                    .buttonStyle(.bordered)
            }
        } canvas: {
            SchreibblattCanvas(layout: sheet.layout, ink: ink, fit: fit, lines: sheet.notebookLines,
                               paper: paper, pencil: pencil) { data, strokes in
                sheet.saveInk(data, strokeCount: strokes)
                try? modelContext.save()
            }
            .schreibblattNextTable(layout: sheet.layout, board: pencil)
            .schreibblattCribSheet(layout: sheet.layout, board: pencil)
            .pencilRail(pencil, accent: SchreibblattTile.tint,
                        canvasSettings: { SchreibblattCanvasSettings(sheet: sheet) },
                        tips: { SchreibblattTips() })
        }
        .tint(SchreibblattTile.tint)
        .onChange(of: sheet.finishedAt, initial: true) {
            pencil.isLocked = sheet.isFinished
        }
        .onChange(of: paper, initial: true) {
            pencil.darkPaper = paper.isDark
        }
    }
}

/// The Schreibblatt's own rows in the Pencil tips.
struct SchreibblattTips: View {
    var body: some View {
        PencilTipRow(symbol: "doc.richtext", title: "Papier · Paper",
                     detail: "The gear picks white, sepia or dark paper, and Heftlinien (notebook lines) rules it like an exercise book. Printed sheets are always white.",
                     accent: SchreibblattTile.tint)
        PencilTipRow(symbol: "list.bullet.rectangle", title: "Spickzettel · Crib sheet",
                     detail: "The words float over the page and mark the row you are writing. Drag it by its title, fold it to the word you are on and the next, or close it; the list button at the top brings it back.",
                     accent: SchreibblattTile.tint)
    }
}

/// Shows or hides the crib sheet: the top bar's icon, or with its name in the full-screen bar.
struct SchreibblattCribButton: View {
    @Binding var shown: Bool
    var titled = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            if titled {
                Label("Spickzettel", systemImage: shown ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
            } else {
                Image(systemName: shown ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
            }
        }
        .accessibilityLabel(shown ? "Hide the crib sheet" : "Show the crib sheet")
        .accessibilityHint("Spickzettel: the sheet's words floating over the page")
    }
}

// MARK: - Format

/// A sheet's format, chosen with a picture of it. A blank sheet changes in place; a written one is
/// told it gets a blank copy instead (the screen asks once more before making it).
private struct SchreibblattFormatSheet: View {
    let current: SchreibblattFormat
    let wordCount: Int
    let repetitions: Int
    let isBlank: Bool
    let onApply: (SchreibblattFormat) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var format: SchreibblattFormat

    init(current: SchreibblattFormat, wordCount: Int, repetitions: Int, isBlank: Bool,
         onApply: @escaping (SchreibblattFormat) -> Void) {
        self.current = current
        self.wordCount = wordCount
        self.repetitions = repetitions
        self.isBlank = isBlank
        self.onApply = onApply
        _format = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SchreibblattFormatPicker(format: $format, wordCount: wordCount, repetitions: repetitions)
                        .padding(.vertical, 4)
                } footer: {
                    Text(isBlank
                         ? "Nothing is written yet, so the sheet changes in place."
                         : "Your writing stays on this sheet. A new format starts a blank copy with the same words.")
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle("Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        dismiss()
                        // After the sheet is down, so a confirmation can show over the screen.
                        DispatchQueue.main.async { onApply(format) }
                    }
                    .disabled(format == current)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - The canvas's settings, in the rail's gear

/// Paper, ruling and fit: what changes how the sheet looks while writing, next to the writing.
/// The paper and the fit are screen preferences; the ruling belongs to the sheet (and its PDF).
struct SchreibblattCanvasSettings: View {
    @Bindable var sheet: SchreibblattSheet
    @Environment(\.modelContext) private var modelContext
    @AppStorage("schreibblatt.fit") private var fit: SchreibblattFit = .width
    @AppStorage("schreibblatt.paper") private var paper: SchreibblattPaperStyle = .white
    @AppStorage(SchreibblattCrib.shownKey) private var cribShown = true

    var body: some View {
        Toggle(isOn: $cribShown) {
            PencilSettingsLabel("Spickzettel · Crib sheet", caption: "The words float over the page and follow your pen, so you never scroll up to the Vorlage.")
        }
        PencilSettingsRow("Papier · Paper", caption: "White, sepia or dark. Printed sheets are always white.") {
            Picker("Paper", selection: $paper) {
                ForEach(SchreibblattPaperStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        Toggle(isOn: Binding(get: { sheet.notebookLines }, set: { lines in
            sheet.notebookLines = lines
            try? modelContext.save()
        })) {
            PencilSettingsLabel("Heftlinien · Notebook lines", caption: "Ruled like an exercise book, in line with the tables' rows.")
        }
        PencilSettingsRow("Ansicht · View", caption: "Seitenbreite fits the page's width; Ganze Seite shows a whole page.") {
            Picker("View", selection: $fit) {
                ForEach(SchreibblattFit.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
