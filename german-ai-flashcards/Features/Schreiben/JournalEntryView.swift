//
//  JournalEntryView.swift
//  german-ai-flashcards
//
//  The one editor for a journal entry or an essay, by keyboard or, on the iPad, with the Pencil.
//
//  Keyboard: the text is edited in a local draft and written to the row a second after the last
//  keystroke, so autosave does not rewrite SQLite (and the sync history) on every character.
//  Leaving the screen flushes the draft and credits the words written to today's study day; a
//  minute of writing every minute goes to the day's time while the learner is typing.
//
//  Pencil (`ThisDevice.kind == .iPad`): a ruled `PencilPad` whose ink is a file beside the entry
//  (`JournalInkStore`). The ink is read in `init` (the canvas reads it once), the full-screen
//  page goes through the shared hand-off so two canvases never hold one page's ink, and "Read my
//  handwriting" turns the ink into text the learner confirms (`JournalHandwritingSheet`) before
//  it becomes the entry's text. On the iPhone and the Mac the ink is shown read-only above the
//  keyboard editor; it can still be read into text there.
//

import SwiftData
import SwiftUI
#if canImport(PencilKit)
import PencilKit
#endif

struct JournalEntryView: View {
    @Bindable var entry: JournalEntry
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // Keyboard
    @State private var draft: String
    @State private var titleDraft: String
    @State private var controller = ChatComposerController()
    @State private var saveTask: Task<Void, Never>?
    @State private var lastEdit: Date = .distantPast

    // Pencil
    enum InputMode: String { case keyboard, pencil }
    @AppStorage("schreiben.input") private var inputRaw = InputMode.keyboard.rawValue
    @State private var ink: Data?
    @State private var inkVersion = 0
    @State private var padToken = 0
    @State private var fullScreen = PencilHandOff()
    @State private var showHandwriting = false
    @State private var checkAfterHandwriting = false
    @State private var confirmClearInk = false

    // Check and housekeeping
    @State private var showCheck = false
    @State private var showShare = false
    @State private var promptExpanded = true
    @State private var lookup: LookupRequest?

    struct LookupRequest: Identifiable {
        let id = UUID()
        var word: String
    }
    @State private var confirmDelete = false
    @State private var deleted = false

    init(entry: JournalEntry, modelManager: MLXModelManager, mlxService: MLXGenerationService) {
        self.entry = entry
        self.modelManager = modelManager
        self.mlxService = mlxService
        _draft = State(initialValue: entry.text)
        _titleDraft = State(initialValue: entry.title)
        _ink = State(initialValue: JournalInkStore.read(entry.id))
    }

    private var hasCanvas: Bool { ThisDevice.kind == .iPad }
    private var input: InputMode { hasCanvas ? (InputMode(rawValue: inputRaw) ?? .keyboard) : .keyboard }
    private var hasInk: Bool { ink != nil || entry.hasInk }
    private var wordCount: Int { WritingSentences.wordCount(draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if entry.hasPrompt {
                promptCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            TextField("Titel · Title (optional)", text: $titleDraft)
                .font(.title3.weight(.semibold))
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            if hasCanvas {
                Picker("Eingabe · Input", selection: inputBinding) {
                    Label("Tastatur", systemImage: "keyboard").tag(InputMode.keyboard)
                    Label("Stift", systemImage: "pencil.tip").tag(InputMode.pencil)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider().padding(.horizontal, 16)

            if input == .pencil {
                pencilPage
            } else {
                keyboardPage
            }
        }
        .themedScreen()
        .navigationTitle(entry.kind.germanLabel)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .sheet(isPresented: $showCheck, onDismiss: { draft = entry.text }) {
            JournalCheckView(entry: entry, modelManager: modelManager, mlxService: mlxService)
        }
        .sheet(isPresented: $showShare) {
            JournalCoachShareSheet(entry: entry, modelManager: modelManager, mlxService: mlxService)
        }
        .sheet(item: $lookup) { request in
            JournalLookupSheet(entry: entry, initialWord: request.word)
        }
        .sheet(isPresented: $showHandwriting, onDismiss: {
            draft = entry.text
            if checkAfterHandwriting {
                checkAfterHandwriting = false
                showCheck = true
            }
        }) {
            JournalHandwritingSheet(entry: entry) { check in
                checkAfterHandwriting = check
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteEntry() }
        } message: {
            Text("The text and any handwriting on it go with it.")
        }
        .confirmationDialog("Clear the handwriting?", isPresented: $confirmClearInk, titleVisibility: .visible) {
            Button("Handschrift löschen", role: .destructive) { clearInk() }
        } message: {
            Text("The ink on this page goes. Text already taken from it stays.")
        }
        .pencilFullScreen($fullScreen, onReturn: {
            ink = JournalInkStore.read(entry.id)
            inkVersion += 1
        }) {
            JournalInkFullScreen(entry: entry)
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: titleDraft) { _, _ in scheduleSave() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive { putDown() }
        }
        .onDisappear { putDown() }
        .task { await tickTime() }
    }

    private var inputBinding: Binding<InputMode> {
        Binding(get: { input }, set: { mode in
            if mode == .pencil {
                flush()
                if entry.inkHeight == 0 {
                    entry.inkHeight = JournalInkStore.initialHeight
                    try? modelContext.save()
                }
            }
            inputRaw = mode.rawValue
        })
    }

    // MARK: - Pages

    private var keyboardPage: some View {
        VStack(spacing: 8) {
            if hasInk {
                JournalInkPreview(entryID: entry.id, pageHeight: entry.inkHeight, version: inkVersion,
                                  maxHeight: hasCanvas ? 160 : 220)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            JournalTextEditor(text: $draft, controller: controller, placeholder: placeholder,
                              onLookup: { word in lookup = LookupRequest(word: word) })
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var pencilPage: some View {
        Group {
            if !fullScreen.inlineShown {
                Color(.secondarySystemBackground)
            } else {
                PencilPad(ink: ink,
                          size: CGSize(width: JournalInkStore.pageWidth, height: CGFloat(pageHeight)),
                          style: paper, lines: true, accent: SchreibenTile.tint,
                          onSave: { data in saveInk(data) },
                          settings: { JournalPadSettings(entry: entry) },
                          tips: { JournalPencilTips() })
                    .id("\(fullScreen.token)-\(padToken)")
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var paper: PencilPaperStyle { PencilPaperStyle(rawValue: entry.inkPaperRaw) ?? .white }
    private var pageHeight: Int { entry.inkHeight > 0 ? entry.inkHeight : JournalInkStore.initialHeight }

    // MARK: - Header and toolbar

    private var header: some View {
        HStack(spacing: 8) {
            Label(entry.dateLine, systemImage: entry.kind.systemImage)
                .labelStyle(.titleAndIcon)
            Text("·")
            Text(entry.level.rawValue)
            Spacer()
            Text(wordLine)
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var wordLine: String {
        if entry.hasTarget {
            return "\(wordCount) · Ziel \(entry.targetMin)–\(entry.targetMax)"
        }
        return "\(wordCount) \(wordCount == 1 ? "word" : "words")"
    }

    /// The essay's question, its English, and the bank's sentence starters, which type themselves
    /// into the text. Folds to one line once the learner is writing.
    private var promptCard: some View {
        let scaffold = entry.promptID.flatMap(WritingPromptBank.find(id:))?.scaffold ?? []
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { promptExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening").font(.caption).foregroundStyle(SchreibenTile.tint).padding(.top, 3)
                    Text(entry.promptDE ?? "")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .lineLimit(promptExpanded ? nil : 1)
                    Spacer(minLength: 4)
                    Image(systemName: promptExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            if promptExpanded {
                if let en = entry.promptEN, !en.isEmpty {
                    Text(en).font(.caption).foregroundStyle(.secondary)
                }
                if !scaffold.isEmpty, input == .keyboard {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(scaffold, id: \.self) { starter in
                                Button(starter) {
                                    controller.focus()
                                    controller.insert(starter.hasSuffix("…") ? String(starter.dropLast()) : starter + " ")
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(SchreibenTile.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholder: String {
        switch entry.kind {
        case .tagebuch: "Wie war's heute? · How did it go today? German, English or both."
        case .aufsatz: "Schreib deinen Aufsatz · Write your essay here."
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
            if hasCanvas, input == .pencil {
                Button {
                    $fullScreen.open()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Full screen")
            }
            #endif
            Button {
                flush()
                showCheck = true
            } label: {
                Label("Prüfen · Check",
                      systemImage: entry.hasCheck && !entry.checkIsStale ? "checkmark.seal.fill" : "checkmark.seal")
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Menu {
                Button {
                    lookup = LookupRequest(word: selectedWord())
                } label: {
                    Label("Nachschlagen · Look up a word", systemImage: "character.book.closed")
                }
                Button {
                    flush()
                    showShare = true
                } label: {
                    Label("Mit dem Coach teilen · Share with the coach", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !entry.hasCheck)
                if hasInk {
                    Button {
                        flush()
                        showHandwriting = true
                    } label: {
                        Label("Handschrift lesen · Read my handwriting", systemImage: "text.viewfinder")
                    }
                    Button(role: .destructive) {
                        confirmClearInk = true
                    } label: {
                        Label("Handschrift löschen · Clear the handwriting", systemImage: "eraser")
                    }
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Löschen · Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: - Saving

    private func scheduleSave() {
        lastEdit = .now
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush() {
        guard !deleted else { return }
        var changed = false
        if entry.text != draft { entry.text = draft; changed = true }
        if entry.title != titleDraft { entry.title = titleDraft; changed = true }
        guard changed else { return }
        entry.touch()
        try? modelContext.save()
    }

    /// Leaving, or the app going away: save now and credit the words.
    private func putDown() {
        saveTask?.cancel()
        guard !deleted else { return }
        flush()
        JournalEntryStore.creditWords(for: entry, in: modelContext)
    }

    /// A minute of writing a minute, while the learner is typing or drawing.
    private func tickTime() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, !deleted else { return }
            if Date.now.timeIntervalSince(lastEdit) < 90 {
                StudyLogService.recordTime(.writing, seconds: 60, in: modelContext)
            }
        }
    }

    private func saveInk(_ data: Data?) {
        guard !deleted else { return }
        lastEdit = .now
        JournalEntryStore.saveInk(data, for: entry, in: modelContext)
        ink = data
        inkVersion += 1
    }

    private func clearInk() {
        JournalEntryStore.saveInk(nil, for: entry, in: modelContext)
        ink = nil
        inkVersion += 1
        padToken += 1   // a fresh canvas, so the cleared ink isn't saved back
    }

    private func deleteEntry() {
        saveTask?.cancel()
        deleted = true
        JournalEntryStore.delete(entry, in: modelContext)
        dismiss()
    }

    /// The word under the selection on iOS, for the menu's Nachschlagen; empty elsewhere.
    private func selectedWord() -> String {
        #if canImport(UIKit)
        guard let field = controller.field, let text = field.text,
              let range = Range(field.selectedRange, in: text), !range.isEmpty else { return "" }
        let selected = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return selected.contains("\n") || selected.count > 40 ? "" : selected
        #else
        return ""
        #endif
    }
}

// MARK: - Full screen

/// The page over the whole screen: no navigation bar, no tab bar. Saves straight to the ink file;
/// the editor re-reads it on return.
struct JournalInkFullScreen: View {
    @Bindable var entry: JournalEntry
    @Environment(\.modelContext) private var modelContext
    @State private var ink: Data?

    init(entry: JournalEntry) {
        self.entry = entry
        _ink = State(initialValue: JournalInkStore.read(entry.id))
    }

    var body: some View {
        PencilFullScreenPage {
            Text(entry.displayTitle)
                .font(.headline)
                .lineLimit(1)
        } end: {
            Label("Done", systemImage: "arrow.down.right.and.arrow.up.left")
                .padding(.horizontal, 12)
                .hidden()
        } canvas: {
            PencilPad(ink: ink,
                      size: CGSize(width: JournalInkStore.pageWidth,
                                   height: CGFloat(entry.inkHeight > 0 ? entry.inkHeight : JournalInkStore.initialHeight)),
                      style: PencilPaperStyle(rawValue: entry.inkPaperRaw) ?? .white,
                      lines: true, accent: SchreibenTile.tint,
                      onSave: { data in JournalEntryStore.saveInk(data, for: entry, in: modelContext) },
                      settings: { JournalPadSettings(entry: entry) },
                      tips: { JournalPencilTips() })
        }
        .tint(SchreibenTile.tint)
    }
}

// MARK: - Gear rows and tips

/// The entry's rows in the Pencil gear's "Blatt" group: the paper, more room, and how the
/// handwriting is read.
struct JournalPadSettings: View {
    @Bindable var entry: JournalEntry
    @Environment(\.modelContext) private var modelContext
    @AppStorage("schreiben.inkLanguageCorrection") private var languageCorrection = false

    var body: some View {
        PencilSettingsRow("Papier · Paper", caption: "White, sepia or dark, for this page.") {
            Picker("Paper", selection: Binding(
                get: { PencilPaperStyle(rawValue: entry.inkPaperRaw) ?? .white },
                set: { entry.inkPaperRaw = $0.rawValue; entry.touch(); try? modelContext.save() }
            )) {
                ForEach(PencilPaperStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        Button {
            entry.inkHeight = min(JournalInkStore.maxHeight,
                                  (entry.inkHeight > 0 ? entry.inkHeight : JournalInkStore.initialHeight) + JournalInkStore.heightStep)
            entry.touch()
            try? modelContext.save()
        } label: {
            PencilSettingsLabel("Mehr Platz · More room",
                                caption: "Adds half a page below. The page is \(pageDescription) now.")
        }
        .disabled(entry.inkHeight >= JournalInkStore.maxHeight)
        Toggle(isOn: $languageCorrection) {
            PencilSettingsLabel("Lesehilfe · Dictionary smoothing",
                                caption: "When your handwriting is read, let the reader nudge words toward the dictionary. Off reads exactly what you wrote.")
        }
    }

    private var pageDescription: String {
        let pages = Double(entry.inkHeight > 0 ? entry.inkHeight : JournalInkStore.initialHeight) / Double(JournalInkStore.initialHeight)
        return pages == 1 ? "one screen tall" : String(format: "%.1f screens tall", pages)
    }
}

/// The room's own rows in the Pencil tips.
struct JournalPencilTips: View {
    var body: some View {
        PencilTipRow(symbol: "text.viewfinder", title: "Handschrift lesen · Read my handwriting",
                     detail: "From the ⋯ menu. Your page is read line by line; you confirm each line before the text goes into the entry and to the tutor.",
                     accent: SchreibenTile.tint)
        PencilTipRow(symbol: "arrow.down.to.line", title: "Mehr Platz · More room",
                     detail: "The gear adds half a page below when you reach the bottom.",
                     accent: SchreibenTile.tint)
    }
}
