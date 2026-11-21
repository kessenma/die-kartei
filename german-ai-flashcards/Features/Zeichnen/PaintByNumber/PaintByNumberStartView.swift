//
//  PaintByNumberStartView.swift
//  german-ai-flashcards
//
//  Malen nach Zahlen · Paint by number: pick one of the word's pictures (or have a Malvorlage
//  drawn), pick how fine, and the app numbers it. Pieces already begun are offered first.
//

import SwiftData
import SwiftUI

struct PaintByNumberStartView: View {
    let word: GameWord
    var preselected: WordArtwork?

    @Environment(\.modelContext) private var modelContext
    @State private var artworks: [WordArtwork] = []
    @State private var source: WordArtwork?
    @State private var difficulty: PaintByNumberDifficulty = .leicht
    @State private var making = false
    @State private var failed = false
    @State private var playing: WordArtwork?

    private var key: String { WordArtKey.make(word.german) }
    private var generator: WordArtGenerator { .shared }

    private var begun: [WordArtwork] { artworks.filter { $0.kind == .paintByNumber && $0.inProgress } }
    private var sources: [WordArtwork] { artworks.filter { $0.kind == .ai || $0.kind == .studio } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZeichnenWordHeader(word: word, font: .title)

                if !begun.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weitermalen · Continue").themedSectionHeader()
                        ForEach(begun) { piece in
                            Button {
                                playing = piece
                            } label: {
                                HStack {
                                    WordArtThumbnail(fileName: piece.fileName, key: piece.wordKey, pixels: 160)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text("Begonnen \(piece.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .themedCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Vorlage · Picture").themedSectionHeader()
                    if sources.isEmpty {
                        Text("This word has no picture to paint yet.")
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                        ForEach(sources) { artwork in
                            Button {
                                source = artwork
                            } label: {
                                WordArtThumbnail(fileName: artwork.fileName, key: artwork.wordKey, pixels: 300)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(ZeichnenTile.tint, lineWidth: source?.id == artwork.id ? 4 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    malvorlageRow
                }
                .padding(14)
                .themedCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Wie fein · How fine").themedSectionHeader()
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(PaintByNumberDifficulty.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("\(difficulty.colors) colours at most. Finer pictures have more, smaller regions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .themedCard()

                Button {
                    Task { await start() }
                } label: {
                    HStack {
                        if making { ProgressView().padding(.trailing, 6) }
                        Text(making ? "Wird nummeriert…" : "Malen · Paint")
                    }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZeichnenTile.tint)
                .controlSize(.large)
                .disabled(source == nil || making)

                if failed {
                    Text("That picture couldn't be turned into a paint-by-number. Try another.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(16)
        }
        .themedScreen()
        .navigationTitle("Malen nach Zahlen")
        .onAppear(perform: reload)
        .onChange(of: generator.runDone) { reload() }
        .navigationDestination(item: $playing) { piece in
            PaintByNumberView(artwork: piece, word: word)
        }
    }

    @ViewBuilder
    private var malvorlageRow: some View {
        if generator.isDrawing(key: key) {
            HStack { ProgressView(); Text("Drawing a Malvorlage…").font(.caption) }
        } else if WordArtGenerator.isReady {
            Button {
                let job = WordArtGenerator.Job(germanWord: word.display, english: word.english,
                                               wordType: word.wordType, style: .malvorlage)
                Task { await generator.run([job], in: modelContext) }
            } label: {
                Label("Have a Malvorlage drawn", systemImage: "paintpalette")
            }
            .disabled(generator.isRunning)
            Text("Flat colours and bold shapes, made for numbering. \(WordArtGenerator.costPhrase(pictures: 1).capitalizedFirst).")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("Connect OpenRouter in Settings ▸ Model to have a picture drawn for painting.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let report = generator.lastReport {
            PictureRunReportBanner(report: report, retryHint: nil) { generator.lastReport = nil }
        }
    }

    private func reload() {
        artworks = WordArtLibrary.artworks(forKey: key, in: modelContext)
        if source == nil || !artworks.contains(where: { $0.id == source?.id }) {
            source = preselected.flatMap { p in sources.first { $0.id == p.id } }
                ?? sources.first(where: { $0.styleRaw == WordArtStyle.malvorlage.rawValue })
                ?? sources.first
        }
    }

    private func start() async {
        guard let source else { return }
        making = true
        failed = false
        defer { making = false }
        let name = source.fileName, sourceKey = source.wordKey, difficulty = difficulty
        let template = await Task.detached(priority: .userInitiated) { () -> PaintByNumberTemplate? in
            guard let image = WordArtStore.loadCGImage(fileName: name, key: sourceKey, maxPixelSize: 1024) else { return nil }
            return PaintByNumberGenerator.make(from: image, difficulty: difficulty)
        }.value
        guard let template, let piece = PaintByNumberLibrary.begin(word: word, template: template, source: source, in: modelContext)
        else { failed = true; return }
        reload()
        playing = piece
    }
}

// MARK: - Files

@MainActor
enum PaintByNumberLibrary {
    /// A new piece: the template on disk and a `WordArtwork` marked in progress.
    static func begin(word: GameWord, template: PaintByNumberTemplate, source: WordArtwork?, in context: ModelContext) -> WordArtwork? {
        let key = WordArtKey.make(word.german)
        let id = UUID()
        guard let data = try? JSONEncoder().encode(template),
              (try? WordArtStore.writeData(data, fileName: WordArtStore.templateName(for: id), key: key)) != nil
        else { return nil }
        let artwork = WordArtwork(wordKey: key, germanWord: word.display, english: word.english,
                                  kind: .paintByNumber, fileName: WordArtStore.newPictureName(for: id))
        artwork.id = id
        artwork.inProgress = true
        artwork.sourceArtworkID = source?.id
        artwork.styleRaw = template.difficultyRaw
        context.insert(artwork)
        try? context.save()
        return artwork
    }

    static func template(for artwork: WordArtwork) -> PaintByNumberTemplate? {
        WordArtStore.readData(fileName: WordArtStore.templateName(for: artwork.id), key: artwork.wordKey)
            .flatMap { try? JSONDecoder().decode(PaintByNumberTemplate.self, from: $0) }
    }

    static func progress(for artwork: WordArtwork) -> PaintByNumberProgress {
        WordArtStore.readData(fileName: WordArtStore.progressName(for: artwork.id), key: artwork.wordKey)
            .flatMap { try? JSONDecoder().decode(PaintByNumberProgress.self, from: $0) } ?? PaintByNumberProgress()
    }

    /// Progress and a preview picture (so the gallery and the Weitermalen shelf show how far it is).
    static func save(_ progress: PaintByNumberProgress, preview: CGImage?, for artwork: WordArtwork, in context: ModelContext) {
        if let data = try? JSONEncoder().encode(progress) {
            try? WordArtStore.writeData(data, fileName: WordArtStore.progressName(for: artwork.id), key: artwork.wordKey)
        }
        if let preview {
            let fileName = WordArtStore.newPictureName(for: artwork.id)
            if (try? WordArtStore.write(preview, fileName: fileName, key: artwork.wordKey)) != nil {
                let old = artwork.fileName
                artwork.fileName = fileName
                try? context.save()
                if old != fileName {
                    try? FileManager.default.removeItem(at: WordArtStore.url(fileName: old, key: artwork.wordKey))
                }
            }
        }
    }
}
