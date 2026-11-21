//
//  QuickDrawSetupView.swift
//  german-ai-flashcards
//
//  Schnellskizze · Quick Draw: pick the words (the coach's weak words, decks, or a saved set),
//  how many and how long each, recall or copy, and whether to keep the sketches. Then draw.
//
//  The run itself is `QuickDrawRunView`, full screen; the review is `QuickDrawReviewView`.
//

import SwiftData
import SwiftUI

/// A picture to show for a word: one from its Bildermappe, or the card's own.
enum ZeichnenReference: Hashable {
    case art(fileName: String, key: String)
    case card(fileName: String, deckID: UUID)

    @MainActor
    static func best(for word: ZeichnenWord, preferring style: WordArtStyle?, in context: ModelContext) -> ZeichnenReference? {
        if let artwork = WordArtLibrary.reference(forKey: word.key, preferredStyle: style, in: context),
           WordArtStore.exists(fileName: artwork.fileName, key: artwork.wordKey) {
            return .art(fileName: artwork.fileName, key: artwork.wordKey)
        }
        if let name = word.word.imageFileName, let deck = word.word.imageDeckID,
           FileManager.default.fileExists(atPath: CardImageStore.url(fileName: name, deckID: deck).path) {
            return .card(fileName: name, deckID: deck)
        }
        return nil
    }

    func load(maxPixel: Int) -> UIImage? {
        switch self {
        case .art(let name, let key): WordArtStore.loadImage(fileName: name, key: key, maxPixelSize: maxPixel)
        case .card(let name, let deck): CardImageStore.loadImage(fileName: name, deckID: deck, maxPixelSize: maxPixel)
        }
    }
}

struct QuickDrawSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \QuickDrawSet.updatedAt, order: .reverse) private var sets: [QuickDrawSet]

    @AppStorage("zeichnen.quick.sourceKind") private var sourceKind = SourceKind.weak.rawValue
    @AppStorage("zeichnen.quick.count") private var count = 10
    @AppStorage("zeichnen.quick.seconds") private var seconds = 40
    @AppStorage("zeichnen.quick.mode") private var modeRaw = QuickDrawMode.recall.rawValue
    @AppStorage("zeichnen.quick.keep") private var keepSketches = false
    @AppStorage("zeichnen.quick.decks") private var lastDecks = ""

    @State private var deckRows: [ZeichnenCatalog.DeckRow] = []
    @State private var pickedDecks: Set<UUID> = []
    @State private var pickedSet: UUID?
    @State private var storedBytes: Int64?
    @State private var session: QuickDrawSession?
    @State private var references: [UUID: ZeichnenReference] = [:]
    @State private var emptyMessage: String?
    @State private var missingReferences: [ZeichnenWord] = []
    @State private var editingSet: QuickDrawSet?
    @State private var creatingSet = false

    enum SourceKind: String, CaseIterable, Identifiable {
        case weak, decks, set
        var id: String { rawValue }
        var title: String {
            switch self {
            case .weak: "Coach"
            case .decks: "Decks"
            case .set: "Sets"
            }
        }
    }

    private var kind: SourceKind { SourceKind(rawValue: sourceKind) ?? .weak }
    private var mode: QuickDrawMode { QuickDrawMode(rawValue: modeRaw) ?? .recall }

    private var source: QuickDrawSource? {
        switch kind {
        case .weak: .weak
        case .decks: pickedDecks.isEmpty ? nil : .decks(pickedDecks)
        case .set: pickedSet.map { .set($0) }
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Words from", selection: $sourceKind) {
                    ForEach(SourceKind.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                sourceDetail
            } header: {
                Text("Welche Wörter · Which words").themedSectionHeader()
            }
            .themedListRow()

            Section {
                Picker("Words", selection: $count) {
                    ForEach([5, 10, 20], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Seconds a word", selection: $seconds) {
                    ForEach([20, 40, 60], id: \.self) { Text("\($0) s").tag($0) }
                }
                Picker("Mode", selection: $modeRaw) {
                    ForEach(QuickDrawMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Runde · Round").themedSectionHeader()
            } footer: {
                Text("\(mode.blurb) About \(max(1, (count * seconds + 59) / 60)) min.")
            }
            .themedListRow()

            Section {
                Toggle("Keep my sketches", isOn: $keepSketches)
            } footer: {
                Text(keepFooter)
            }
            .themedListRow()

            if mode == .copy, !missingReferences.isEmpty {
                Section {
                    referenceRow
                } footer: {
                    Text("Copy mode shows a Skizze to sketch from. Words without one show their card picture, or just the word.")
                }
                .themedListRow()
            }

            Section {
                Button {
                    start()
                } label: {
                    Label("Los · Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZeichnenTile.tint)
                .disabled(source == nil)
                if let emptyMessage {
                    Text(emptyMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)
        }
        .themedListScreen()
        .navigationTitle("Schnellskizze")
        .onAppear(perform: load)
        .onChange(of: modeRaw) { refreshMissing() }
        .onChange(of: sourceKind) { refreshMissing() }
        .onChange(of: pickedDecks) { refreshMissing() }
        .onChange(of: pickedSet) { refreshMissing() }
        .onChange(of: count) { refreshMissing() }
        .onChange(of: WordArtGenerator.shared.runDone) { refreshMissing() }
        .sheet(isPresented: $creatingSet) {
            NavigationStack { QuickDrawSetEditor(set: nil) { pickedSet = $0.id; sourceKind = SourceKind.set.rawValue } }
        }
        .sheet(item: $editingSet) { set in
            NavigationStack { QuickDrawSetEditor(set: set) { _ in } }
        }
        #if os(iOS)
        .fullScreenCover(item: $session) { session in
            QuickDrawRunView(session: session, references: references)
        }
        #else
        .sheet(item: $session) { session in
            QuickDrawRunView(session: session, references: references)
        }
        #endif
    }

    // MARK: - Source detail

    @ViewBuilder
    private var sourceDetail: some View {
        switch kind {
        case .weak:
            Label("The coach picks the words that need practice most: lapses, wrong answers, overdue cards and game misses.",
                  systemImage: "sparkles")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .decks:
            if deckRows.isEmpty {
                Text("No decks yet.").foregroundStyle(.secondary)
            }
            ForEach(deckRows) { row in
                Button {
                    if pickedDecks.contains(row.id) { pickedDecks.remove(row.id) } else { pickedDecks.insert(row.id) }
                    lastDecks = pickedDecks.map(\.uuidString).joined(separator: ",")
                } label: {
                    HStack {
                        Image(systemName: pickedDecks.contains(row.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(pickedDecks.contains(row.id) ? ZeichnenTile.tint : .secondary)
                        Text(row.title).foregroundStyle(.primary)
                        Spacer()
                        Text("\(row.count)").foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
        case .set:
            ForEach(sets) { set in
                HStack {
                    Button {
                        pickedSet = set.id
                    } label: {
                        HStack {
                            Image(systemName: pickedSet == set.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(pickedSet == set.id ? ZeichnenTile.tint : .secondary)
                            Text(set.name.isEmpty ? "Unbenannt" : set.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(set.cardIDs.count)").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    Button {
                        editingSet = set
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onDelete { offsets in
                for index in offsets { modelContext.delete(sets[index]) }
                try? modelContext.save()
            }
            Button {
                creatingSet = true
            } label: {
                Label("Neues Set · New set", systemImage: "plus.circle")
            }
        }
    }

    private var referenceRow: some View {
        let generator = WordArtGenerator.shared
        return VStack(alignment: .leading, spacing: 6) {
            if generator.isRunning {
                ProgressView(value: Double(generator.runDone), total: Double(max(1, generator.runTotal))) {
                    Text("Drawing references…").font(.caption)
                }
            } else if WordArtGenerator.isReady {
                Button {
                    let jobs = missingReferences.map {
                        WordArtGenerator.Job(germanWord: $0.display, english: $0.english,
                                             wordType: $0.word.wordType, style: .skizze)
                    }
                    Task { await generator.run(jobs, in: modelContext) }
                } label: {
                    Label("Draw \(missingReferences.count) Skizze \(missingReferences.count == 1 ? "reference" : "references")",
                          systemImage: "scribble")
                }
                Text(WordArtGenerator.costPhrase(pictures: missingReferences.count).capitalizedFirst)
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("\(missingReferences.count) words have no Skizze. Connect OpenRouter in Settings ▸ Model to draw them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let report = generator.lastReport {
                PictureRunReportBanner(report: report, retryHint: nil) { generator.lastReport = nil }
            }
        }
    }

    private var keepFooter: String {
        var text = keepSketches
            ? "Every sketch goes to its word's Bildermappe. You can still untick any of them at the end."
            : "Sketches are let go at the end, unless you pick some to keep."
        text += " Kept sketches sync to your other devices through iCloud, about \(WordArtStore.sizePhrase(WordArtStore.typicalSketchBytes)) each"
        if let storedBytes, storedBytes > 0 {
            text += "; your pictures use \(WordArtStore.sizePhrase(storedBytes)) now."
        } else {
            text += "."
        }
        return text
    }

    // MARK: - Actions

    private func load() {
        deckRows = ZeichnenCatalog.deckRows(in: modelContext)
        if pickedDecks.isEmpty {
            let known = Set(deckRows.map(\.id))
            pickedDecks = Set(lastDecks.split(separator: ",").compactMap { UUID(uuidString: String($0)) }).intersection(known)
        }
        if pickedSet == nil { pickedSet = sets.first?.id }
        Task.detached(priority: .utility) {
            let bytes = WordArtStore.totalBytes()
            await MainActor.run { storedBytes = bytes }
        }
        refreshMissing()
    }

    private func refreshMissing() {
        guard mode == .copy, let source else { missingReferences = []; return }
        let words = ZeichnenCatalog.words(for: source, limit: count, in: modelContext)
        missingReferences = words.filter {
            WordArtLibrary.artworks(forKey: $0.key, in: modelContext)
                .first(where: { $0.styleRaw == WordArtStyle.skizze.rawValue }) == nil
        }
    }

    private func start() {
        emptyMessage = nil
        guard let source else { return }
        let words = ZeichnenCatalog.words(for: source, limit: count, in: modelContext)
        guard !words.isEmpty else {
            emptyMessage = kind == .weak
                ? "Nothing needs practice yet. Review some cards first, or pick a deck."
                : "No words to draw here."
            return
        }
        var refs: [UUID: ZeichnenReference] = [:]
        for word in words {
            refs[word.id] = ZeichnenReference.best(for: word, preferring: mode == .copy ? .skizze : nil, in: modelContext)
        }
        references = refs
        session = QuickDrawSession(words: words, mode: mode, secondsPerWord: seconds, keepByDefault: keepSketches)
    }
}

extension QuickDrawSession: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension String {
    /// "about $0.04…" → "About $0.04…".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
