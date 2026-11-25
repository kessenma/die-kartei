//
//  WordArtGalleryView.swift
//  german-ai-flashcards
//
//  Bildermappe · Picture folder: every picture of one word. AI pictures in the learner's chosen
//  styles, kept quick sketches, Atelier pieces and paint-by-number pictures, side by side.
//
//  New pictures are drawn on the learner's OpenRouter account (`WordArtGenerator`). The list is
//  fetched, not a filtered `@Query`, and refreshed after a run and when sync lands a record
//  (docs/MEMORY.md ▸ the `@Query` body loop).
//

import SwiftData
import SwiftUI

struct WordArtGalleryView: View {
    let word: ZeichnenWord

    @Environment(\.modelContext) private var modelContext
    @State private var artworks: [WordArtwork] = []
    @State private var filter: Filter = .all
    @State private var style: WordArtStyle = .kontur
    @State private var variants = 1
    @State private var viewing: WordArtwork?
    @State private var stat: WordDrawingStat?
    @State private var showingAccount = false
    @State private var adoptMessage: String?

    private var generator: WordArtGenerator { .shared }

    enum Filter: String, CaseIterable, Identifiable {
        case all, ai, quick, studio, painted
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Alle"
            case .ai: "KI"
            case .quick: "Skizzen"
            case .studio: "Atelier"
            case .painted: "Gemalt"
            }
        }
        func matches(_ kind: WordArtworkKind) -> Bool {
            switch self {
            case .all: true
            case .ai: kind == .ai
            case .quick: kind == .quick
            case .studio: kind == .studio
            case .painted: kind == .paintByNumber
            }
        }
    }

    private var shown: [WordArtwork] { artworks.filter { filter.matches($0.kind) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZeichnenWordHeader(word: word.word)
                if let stat, stat.totalDrawn > 0 { statLine(stat) }

                generateCard

                if let report = generator.lastReport {
                    PictureRunReportBanner(report: report, retryHint: "Zeichnen lassen") {
                        generator.lastReport = nil
                    }
                }

                drawCard

                if !artworks.isEmpty {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                grid
            }
            .padding(16)
        }
        .themedScreen()
        .navigationTitle("Bildermappe")
        .onAppear(perform: reload)
        .onChange(of: generator.runDone) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .syncedFileLanded)) { _ in reload() }
        .sheet(item: $viewing) { artwork in
            NavigationStack {
                WordArtViewer(artwork: artwork, word: word, onChange: reload)
            }
        }
        .sheet(isPresented: $showingAccount) { CloudAccountSheet() }
        .alert("Kartenbild", isPresented: Binding(get: { adoptMessage != nil }, set: { if !$0 { adoptMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(adoptMessage ?? "")
        }
    }

    // MARK: - Sections

    private func statLine(_ stat: WordDrawingStat) -> some View {
        var parts: [String] = []
        if stat.quickCount > 0 { parts.append("\(stat.quickCount)× sketched") }
        if stat.studioCount > 0 { parts.append("\(stat.studioCount)× in the Atelier") }
        if stat.paintedCount > 0 { parts.append("\(stat.paintedCount)× painted") }
        let recall = stat.recallRight + stat.recallMissed
        if recall > 0 { parts.append("recalled \(stat.recallRight) of \(recall)") }
        return Label(parts.joined(separator: " · "), systemImage: "pencil.and.scribble")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var generateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Neues Bild · New picture").themedSectionHeader()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WordArtStyle.allCases) { option in
                        Button {
                            style = option
                        } label: {
                            Label(option.shortLabel, systemImage: option.symbol)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(style == option ? ZeichnenTile.tint.opacity(0.18) : Color.secondary.opacity(0.10),
                                            in: Capsule())
                                .overlay(Capsule().strokeBorder(style == option ? ZeichnenTile.tint : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(style.subtitle).font(.caption).foregroundStyle(.secondary)

            if WordArtGenerator.isReady {
                HStack {
                    Stepper("\(variants) \(variants == 1 ? "picture" : "pictures")", value: $variants, in: 1...4)
                        .fixedSize()
                    Spacer()
                    if generator.isDrawing(key: word.key) {
                        ProgressView()
                        Button("Stop", role: .cancel) { generator.stop() }
                    } else {
                        Button("Zeichnen lassen") { generate() }
                            .buttonStyle(.borderedProminent)
                            .tint(ZeichnenTile.tint)
                            .disabled(generator.isRunning)
                    }
                }
                Text("Drawn by \(CloudImageModel.current.displayName), \(WordArtGenerator.costPhrase(pictures: variants)).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    showingAccount = true
                } label: {
                    Label("Connect OpenRouter to draw pictures", systemImage: "cloud")
                }
                Text("Pictures are drawn by Muse Image or Nano Banana on your own OpenRouter account.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .themedCard()
    }

    private var drawCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selbst zeichnen · Draw it yourself").themedSectionHeader()
            NavigationLink {
                AtelierView(word: word.word, reference: reference)
            } label: {
                Label("Im Atelier zeichnen · Studio", systemImage: "paintbrush.pointed")
            }
            NavigationLink {
                PaintByNumberStartView(word: word.word, preselected: paintSource)
            } label: {
                Label("Malen nach Zahlen · Paint by number", systemImage: "paintpalette")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    private var reference: WordArtwork? {
        artworks.first(where: \.starred) ?? artworks.first(where: { $0.kind == .ai })
    }

    private var paintSource: WordArtwork? {
        artworks.first(where: { $0.styleRaw == WordArtStyle.malvorlage.rawValue })
            ?? artworks.first(where: { $0.kind == .ai })
    }

    @ViewBuilder
    private var grid: some View {
        if artworks.isEmpty && !generator.isDrawing(key: word.key) {
            ContentUnavailableView("Noch keine Bilder", systemImage: "photo.on.rectangle.angled",
                                   description: Text("Draw one yourself, or have one drawn in a style above."))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                if generator.isDrawing(key: word.key) {
                    ForEach(0..<max(1, generator.drawing[word.key] ?? 1), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(ProgressView())
                    }
                }
                ForEach(shown) { artwork in
                    Button {
                        viewing = artwork
                    } label: {
                        cell(artwork)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { actions(for: artwork) }
                }
            }
        }
    }

    private func cell(_ artwork: WordArtwork) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WordArtThumbnail(fileName: artwork.fileName, key: artwork.wordKey)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if artwork.starred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .shadow(radius: 2)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if artwork.inProgress {
                        Text("begonnen")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                            .padding(6)
                    }
                }
            Text(wordArtCaption(artwork)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    @ViewBuilder
    private func actions(for artwork: WordArtwork) -> some View {
        Button {
            artwork.starred.toggle()
            try? modelContext.save()
            reload()
        } label: {
            Label(artwork.starred ? "Unstar" : "Star", systemImage: artwork.starred ? "star.slash" : "star")
        }
        Button {
            adopt(artwork)
        } label: {
            Label("Use as card picture", systemImage: "rectangle.on.rectangle")
        }
        Button(role: .destructive) {
            WordArtLibrary.delete(artwork, in: modelContext)
            reload()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func reload() {
        artworks = WordArtLibrary.artworks(forKey: word.key, in: modelContext)
        stat = WordDrawingLog.stat(forKey: word.key, in: modelContext)
    }

    private func generate() {
        let job = WordArtGenerator.Job(germanWord: word.display, english: word.english,
                                       wordType: word.word.wordType, style: style)
        let jobs = Array(repeating: job, count: variants)
        Task { await generator.run(jobs, in: modelContext) }
    }

    private func adopt(_ artwork: WordArtwork) {
        let id = word.id
        var d = FetchDescriptor<SavedCard>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let card = (try? modelContext.fetch(d))?.first else { return }
        guard WordArtLibrary.canAdopt(into: card) else {
            adoptMessage = "Wortschatz cards show the Goethe list's own content, so they can't take a picture. It stays in the Bildermappe."
            return
        }
        adoptMessage = WordArtLibrary.adopt(artwork, into: card, in: modelContext)
            ? "This picture is now the card's picture in \(word.deckTitle)."
            : "The picture couldn't be copied onto the card."
    }
}

func wordArtCaption(_ artwork: WordArtwork) -> String {
    switch artwork.kind {
    case .ai: artwork.styleRaw.flatMap(WordArtStyle.init(rawValue:))?.shortLabel ?? "KI"
    case .quick: artwork.recalled == false ? "Skizze · missed" : "Skizze"
    case .studio: "Atelier"
    case .paintByNumber: "Malen nach Zahlen"
    }
}

// MARK: - Viewer

/// One picture, large, with its actions.
struct WordArtViewer: View {
    let artwork: WordArtwork
    let word: ZeichnenWord
    var onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WordArtThumbnail(fileName: artwork.fileName, key: artwork.wordKey, pixels: 1024, contentMode: .fit)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text.gendered(word.word.german, article: word.word.article).font(.title2.weight(.bold))
                Text("\(wordArtCaption(artwork)) · \(artwork.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    NavigationLink {
                        AtelierView(word: word.word, reference: artwork)
                    } label: {
                        Label("Draw this", systemImage: "paintbrush.pointed")
                    }
                    .buttonStyle(.bordered)
                    NavigationLink {
                        PaintByNumberStartView(word: word.word, preselected: artwork)
                    } label: {
                        Label("Paint by number", systemImage: "paintpalette")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .themedScreen()
        .navigationTitle(wordArtCaption(artwork))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    artwork.starred.toggle()
                    try? modelContext.save()
                    onChange()
                } label: {
                    Image(systemName: artwork.starred ? "star.fill" : "star")
                }
            }
        }
    }
}
