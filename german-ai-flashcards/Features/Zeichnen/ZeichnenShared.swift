//
//  ZeichnenShared.swift
//  german-ai-flashcards
//
//  Small pieces every Zeichnen screen uses: a picture thumbnail that loads off the main actor and
//  reloads when its file lands from another device, the word header, and the word picker.
//

import SwiftData
import SwiftUI

// MARK: - Thumbnail

/// One gallery picture, downsampled to what it is drawn at. Reloads when the file arrives by
/// iCloud (`.syncedFileLanded`), since the record can land before its bytes.
struct WordArtThumbnail: View {
    let fileName: String
    let key: String
    var pixels: Int = 360
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var landings = 0

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .clipped()
        .task(id: "\(fileName)#\(landings)") {
            let name = fileName, key = key, pixels = pixels
            image = await Task.detached(priority: .userInitiated) {
                WordArtStore.loadImage(fileName: name, key: key, maxPixelSize: pixels)
            }.value
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncedFileLanded)) { note in
            guard let path = note.userInfo?["path"] as? String, path.hasSuffix(fileName) else { return }
            landings += 1
        }
    }
}

// MARK: - Word header

struct ZeichnenWordHeader: View {
    let word: GameWord
    var font: Font = .largeTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text.gendered(word.german, article: word.article)
                .font(font.weight(.bold))
                .minimumScaleFactor(0.5)
                .lineLimit(2)
            Text(word.english)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Word picker

/// Every word on the device, searchable, one row per word (the same word in two decks is one
/// row). Snapshots the store on appear; a row shows how many pictures the word has.
struct ZeichnenWordPicker<Destination: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let destination: (ZeichnenWord) -> Destination

    @Environment(\.modelContext) private var modelContext
    @State private var words: [ZeichnenWord] = []
    @State private var pictureCounts: [String: Int] = [:]
    @State private var search = ""
    @State private var loaded = false

    private var visible: [ZeichnenWord] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return words }
        return words.filter {
            $0.word.german.lowercased().contains(query) || $0.english.lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            if words.isEmpty, loaded {
                ContentUnavailableView("Noch keine Wörter", systemImage: "rectangle.stack",
                                       description: Text("Make a deck first, then come back to draw its words."))
            }
            Section {
                ForEach(visible) { word in
                    NavigationLink {
                        destination(word)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text.gendered(word.word.german, article: word.word.article)
                                    .font(.body.weight(.medium))
                                Text(word.english).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let count = pictureCounts[word.key], count > 0 {
                                Label("\(count)", systemImage: "photo.on.rectangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                if let footer { Text(footer) }
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle(title)
        .searchable(text: $search, prompt: "Wort suchen · Search")
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let all = ZeichnenCatalog.dedupe(ZeichnenCatalog.allWords(in: modelContext))
        words = all.sorted { $0.word.german.localizedCaseInsensitiveCompare($1.word.german) == .orderedAscending }
        let artworks = (try? modelContext.fetch(FetchDescriptor<WordArtwork>())) ?? []
        pictureCounts = Dictionary(grouping: artworks, by: \.wordKey).mapValues(\.count)
    }
}

// MARK: - Saving a picture

@MainActor
enum ZeichnenSaving {
    /// File the learner's drawing of `word` as a gallery picture. Returns the artwork, or nil if
    /// the ink couldn't be rendered or written.
    @discardableResult
    static func save(
        ink: Data,
        word: GameWord,
        kind: WordArtworkKind,
        dark: Bool = false,
        pixels: Int = WordArtStore.sketchMaxPixel,
        keepInk: Bool = false,
        configure: (WordArtwork) -> Void = { _ in },
        in context: ModelContext
    ) -> WordArtwork? {
        guard let image = ZeichnenRender.image(ink: ink, dark: dark, pixels: pixels) else { return nil }
        let key = WordArtKey.make(word.german)
        let id = UUID()
        let fileName = WordArtStore.newPictureName(for: id)
        do {
            try WordArtStore.write(image, fileName: fileName, key: key)
            var inkName: String?
            if keepInk {
                inkName = WordArtStore.inkName(for: id)
                try WordArtStore.writeData(ink, fileName: inkName!, key: key)
            }
            let artwork = WordArtwork(wordKey: key, germanWord: word.display, english: word.english,
                                      kind: kind, fileName: fileName)
            artwork.id = id
            artwork.inkFileName = inkName
            configure(artwork)
            context.insert(artwork)
            try? context.save()
            return artwork
        } catch {
            return nil
        }
    }
}
