//
//  ResumeView.swift
//  german-ai-flashcards
//
//  Lebenslauf (roadmap item 18): import the résumé (paste, PDF, scan or photo), let the tutor write
//  the Kurzprofil and split the facts once, then read and edit both. What the learner sees here is
//  exactly what the recruiter gets. Career words go to a "Lebenslauf" deck through `CardKind`.
//  On this device only (`Resume`).
//

import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The "Lebenslauf" deck: words for talking about one's own career.
@MainActor
enum ResumeDeckStore {
    static let generatorRaw = "resume"
    static let topic = "Lebenslauf"

    static func orCreateDeck(context: ModelContext) -> SavedDeck {
        let id = SyncSingletonDecks.deckID(generatorRaw: generatorRaw, topic: topic)
        var d = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        if let existing = (try? context.fetch(d))?.first { return existing }
        let deck = SavedDeck(topic: topic, wordCount: 0, includeExamples: false, includeGender: true)
        deck.generatorRaw = generatorRaw
        deck.id = id
        context.insert(deck)
        return deck
    }
}

struct ResumeView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext

    @State private var resume: Resume?
    @State private var pasting = false
    @State private var pasteText = ""
    @State private var importingPDF = false
    @State private var photoItem: PhotosPickerItem?
    @State private var ocr = PhotoOCRService()
    @State private var working: String?
    @State private var newFact = ""
    @State private var wordsAdded: Int?
    @State private var errorText: String?

    private var model: MLXModel { modelManager.selectedChatModel }
    private var cap: Int { ResumePrompts.kurzprofilSlice(saver: MemorySaver.isActive(for: model)) }

    var body: some View {
        List {
            importSection
            if let resume, !resume.fullText.isEmpty {
                kurzprofilSection(resume)
                factsSection(resume)
                wordsSection(resume)
            }
            Section {
                Text("Your résumé stays on this device. It isn't synced, it isn't sent to cloud pictures, and the coach never sees it. In an interview the recruiter reads only the Kurzprofil and one fact per question.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
        }
        .themedListScreen()
        .navigationTitle("Lebenslauf")
        .onAppear { resume = ResumeStore.current(in: modelContext) }
        .sheet(isPresented: $pasting) { pasteSheet }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { Task { await importPDF(url) } }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .alert("Couldn't read that", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: - Sections

    private var importSection: some View {
        Section {
            if let working {
                HStack(spacing: 10) { ProgressView(); Text(working).foregroundStyle(.secondary) }
            }
            Button { pasting = true } label: { Label("Paste the text", systemImage: "doc.on.clipboard") }
            Button { importingPDF = true } label: { Label("From a PDF", systemImage: "doc.richtext") }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("From a photo or scan", systemImage: "camera")
            }
        } header: {
            Text(resume?.fullText.isEmpty == false ? "Neu importieren · Import again" : "Lebenslauf · Your résumé").themedSectionHeader()
        } footer: {
            if let resume, !resume.fullText.isEmpty {
                Text("\(resume.fullText.count.formatted()) characters kept in full. Importing again replaces it.")
            } else {
                Text("German or English. The whole text is kept; the interview only ever uses the short profile and single facts made from it.")
            }
        }
        .themedListRow()
    }

    private func kurzprofilSection(_ resume: Resume) -> some View {
        Section {
            TextEditor(text: Binding(get: { resume.kurzprofil }, set: { resume.kurzprofil = $0; resume.updatedAt = .now }))
                .frame(minHeight: 140)
            HStack {
                Text("\(resume.kurzprofil.count) / \(cap) characters reach the recruiter")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(resume.kurzprofil.count > cap ? .orange : .secondary)
                Spacer()
                Button("Write it with the tutor") { Task { await writeKurzprofil(resume) } }
                    .font(.caption)
                    .disabled(working != nil || !model.isDownloaded)
            }
        } header: {
            Text("Kurzprofil").themedSectionHeader()
        } footer: {
            Text("Current role, years, main skills, two achievements, education, languages, in German. Edit it freely: this exact text is what the recruiter knows about you.")
        }
        .themedListRow()
    }

    private func factsSection(_ resume: Resume) -> some View {
        Section {
            ForEach(resume.facts) { fact in
                Text(fact.text).font(.callout)
            }
            .onDelete { offsets in
                var list = resume.facts
                list.remove(atOffsets: offsets)
                resume.facts = list
                save()
            }
            HStack {
                TextField("Add a fact", text: $newFact)
                Button("Add") {
                    let t = newFact.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    resume.facts = resume.facts + [ResumeFact(text: t)]
                    newFact = ""
                    save()
                }
                .disabled(newFact.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button("Split the facts with the tutor") { Task { await splitFacts(resume) } }
                .disabled(working != nil || !model.isDownloaded)
        } header: {
            Text("Fakten · Single facts").themedSectionHeader()
        } footer: {
            Text("One role, one project, one degree each. Each turn the recruiter gets the one fact that matches the question coming up, so it can ask about it by name.")
        }
        .themedListRow()
    }

    private func wordsSection(_ resume: Resume) -> some View {
        Section {
            Button {
                Task { await saveCareerWords(resume) }
            } label: {
                Label(wordsAdded.map { "\($0) words added to the Lebenslauf deck" } ?? "Career words to a deck",
                      systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(working != nil || !model.isDownloaded || wordsAdded != nil)
        } footer: {
            Text("The words for your own job, picked by the tutor, as flashcards.")
        }
        .themedListRow()
    }

    private var pasteSheet: some View {
        NavigationStack {
            TextEditor(text: $pasteText)
                .padding()
                .navigationTitle("Paste your résumé")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pasting = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use") {
                            store(pasteText, source: "paste")
                            pasteText = ""
                            pasting = false
                        }
                        .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).count < 40)
                    }
                }
        }
    }

    // MARK: - Import

    private func store(_ text: String, source: String) {
        let r = ResumeStore.orCreate(in: modelContext)
        r.fullText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        r.sourceRaw = source
        // A fresh start from the text, until the tutor (or the learner) writes something better.
        r.facts = ResumePrompts.heuristicFacts(r.fullText).map { ResumeFact(text: $0) }
        if r.kurzprofil.isEmpty { r.kurzprofil = "" }
        r.updatedAt = .now
        save()
        resume = r
        wordsAdded = nil
    }

    private func importPDF(_ url: URL) async {
        working = "Reading the PDF…"
        defer { working = nil }
        guard let data = { () -> Data? in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            return try? Data(contentsOf: url)
        }(), let result = PDFTextExtractor.extract(from: data) else {
            errorText = "That PDF couldn't be opened."
            return
        }
        if !result.looksScanned {
            store(result.text, source: "pdf")
            return
        }
        // A scan: read each page as a picture.
        var pages: [String] = []
        for page in 1...max(1, min(result.pageCount, 4)) {
            #if canImport(UIKit)
            guard let image = PDFTextExtractor.pageImage(from: data, page: page), let png = image.pngData() else { continue }
            if case .success(let text) = await ocr.extractText(from: png) { pages.append(text) }
            #endif
        }
        let text = pages.joined(separator: "\n\n")
        guard text.count >= 40 else { errorText = "No text could be read from this PDF."; return }
        store(text, source: "pdf")
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        working = "Reading the photo…"
        defer { working = nil; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        switch await ocr.extractText(from: data) {
        case .success(let text) where text.count >= 40: store(text, source: "photo")
        default: errorText = "No text could be read from this photo."
        }
    }

    // MARK: - Tutor

    private func ensureModel() async -> Bool {
        if mlxService.isModelLoaded && mlxService.currentModel == model { return true }
        await mlxService.loadModel(model)
        return mlxService.isModelLoaded && mlxService.currentModel == model
    }

    private func writeKurzprofil(_ resume: Resume) async {
        working = "Writing the Kurzprofil…"
        defer { working = nil }
        guard await ensureModel(),
              let raw = try? await mlxService.generateText(system: ResumePrompts.kurzprofilSystem,
                                                           user: ResumePrompts.kurzprofilUser(resume.fullText),
                                                           model: model, maxTokens: 260) else { return }
        let text = ResumePrompts.cleanKurzprofil(raw)
        guard text.count >= 40 else { return }
        resume.kurzprofil = text
        resume.updatedAt = .now
        save()
    }

    private func splitFacts(_ resume: Resume) async {
        working = "Splitting the facts…"
        defer { working = nil }
        guard await ensureModel(),
              let raw = try? await mlxService.generateText(system: ResumePrompts.factsSystem,
                                                           user: ResumePrompts.kurzprofilUser(resume.fullText),
                                                           model: model, maxTokens: 500) else { return }
        let facts = ResumePrompts.parseFacts(raw)
        guard !facts.isEmpty else { return }
        resume.facts = facts.map { ResumeFact(text: $0) }
        save()
    }

    private func saveCareerWords(_ resume: Resume) async {
        working = "Picking your career words…"
        defer { working = nil }
        guard await ensureModel(),
              let raw = try? await mlxService.generateText(system: ResumePrompts.wordsSystem,
                                                           user: ResumePrompts.kurzprofilUser(resume.fullText),
                                                           model: model, maxTokens: 300) else { return }
        let deck = ResumeDeckStore.orCreateDeck(context: modelContext)
        var added = 0
        for (german, english) in StoryStudyService.parsePairs(raw).prefix(12) {
            if DeckCardAdder.add(german: german, english: english, to: deck, context: modelContext) { added += 1 }
        }
        wordsAdded = added
    }

    private func save() { try? modelContext.save() }
}
