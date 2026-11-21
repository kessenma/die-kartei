//
//  ZeichnenHubView.swift
//  german-ai-flashcards
//
//  The Zeichnen room: three ways to draw a word (Schnellskizze, Atelier, Malen nach Zahlen),
//  pieces still being painted, and the words that already have pictures.
//
//  Read once on appear and again on return, not through `@Query` (the room lists across every
//  deck; docs/MEMORY.md ▸ the `@Query` body loop).
//

import SwiftData
import SwiftUI

struct ZeichnenHubView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var recentWords: [(word: ZeichnenWord, artwork: WordArtwork)] = []
    @State private var begun: [(word: ZeichnenWord, artwork: WordArtwork)] = []
    @State private var wordsDrawn = 0
    @State private var storedBytes: Int64 = 0

    var body: some View {
        List {
            Section {
                NavigationLink {
                    QuickDrawSetupView()
                } label: {
                    row("Schnellskizze · Quick Draw", "Sketch n words against the clock, from memory or from a picture",
                        systemImage: "timer")
                }
                NavigationLink {
                    ZeichnenWordPicker(title: "Atelier", footer: "Pick a word to draw slowly from one of its pictures.") { word in
                        AtelierView(word: word.word,
                                    reference: WordArtLibrary.reference(forKey: word.key, in: modelContext))
                    }
                } label: {
                    row("Atelier · Studio", "Take your time: trace a picture, more brushes, halftone finishes",
                        systemImage: "paintbrush.pointed")
                }
                NavigationLink {
                    ZeichnenWordPicker(title: "Malen nach Zahlen", footer: "Pick a word, then one of its pictures to number.") { word in
                        PaintByNumberStartView(word: word.word, preselected: nil)
                    }
                } label: {
                    row("Malen nach Zahlen · Paint by number", "A calm one: fill the numbered regions, learn the colours",
                        systemImage: "paintpalette")
                }
            } header: {
                Text("Zeichnen").themedSectionHeader()
            } footer: {
                Text("Drawing a word fixes it in memory better than writing it out. Sketch it, study it, or paint it.")
            }
            .themedListRow()

            if !begun.isEmpty {
                Section {
                    ForEach(begun, id: \.artwork.id) { item in
                        NavigationLink {
                            PaintByNumberView(artwork: item.artwork, word: item.word.word)
                        } label: {
                            HStack(spacing: 12) {
                                WordArtThumbnail(fileName: item.artwork.fileName, key: item.artwork.wordKey, pixels: 160)
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text.gendered(item.word.word.german, article: item.word.word.article)
                            }
                        }
                    }
                } header: {
                    Text("Weitermalen · Continue").themedSectionHeader()
                }
                .themedListRow()
            }

            Section {
                if !recentWords.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recentWords, id: \.artwork.id) { item in
                                NavigationLink {
                                    WordArtGalleryView(word: item.word)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        WordArtThumbnail(fileName: item.artwork.fileName, key: item.artwork.wordKey, pixels: 240)
                                            .frame(width: 110, height: 110)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        Text(item.word.display).font(.caption).lineLimit(1).frame(width: 110, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                NavigationLink {
                    ZeichnenWordPicker(title: "Bildermappe", footer: "Every word's pictures: drawn by you, or by Muse Image or Nano Banana in a style you pick.") { word in
                        WordArtGalleryView(word: word)
                    }
                } label: {
                    Label("Alle Wörter · All words", systemImage: "photo.on.rectangle.angled")
                }
            } header: {
                Text("Bildermappe · Picture folders").themedSectionHeader()
            } footer: {
                Text(footer)
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle(ZeichnenTile.title)
        .onAppear(perform: load)
    }

    private func row(_ title: String, _ subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(ZeichnenTile.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var footer: String {
        var parts: [String] = []
        if wordsDrawn > 0 { parts.append("\(wordsDrawn) \(wordsDrawn == 1 ? "word" : "words") drawn so far.") }
        if storedBytes > 0 { parts.append("Pictures use \(WordArtStore.sizePhrase(storedBytes)) and sync through iCloud.") }
        return parts.isEmpty ? "Pictures sync to your other devices through iCloud." : parts.joined(separator: " ")
    }

    private func load() {
        let words = ZeichnenCatalog.allWords(in: modelContext)
        var byKey: [String: ZeichnenWord] = [:]
        for word in words where byKey[word.key] == nil { byKey[word.key] = word }

        let artworks = (try? modelContext.fetch(FetchDescriptor<WordArtwork>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []

        func word(for artwork: WordArtwork) -> ZeichnenWord? {
            if let known = byKey[artwork.wordKey] { return known }
            // The word's card is gone, but its pictures are still here.
            guard let game = GameWord(german: artwork.germanWord.strippingArticle, english: artwork.english,
                                      article: artwork.germanWord.leadingArticle)
            else { return nil }
            return ZeichnenWord(id: SyncNameUUID.make("WordArtOrphan", artwork.wordKey), word: game,
                                deckID: UUID(), deckTitle: "")
        }

        var seen = Set<String>()
        recentWords = artworks.filter { !$0.inProgress && seen.insert($0.wordKey).inserted }
            .prefix(12)
            .compactMap { artwork in word(for: artwork).map { ($0, artwork) } }
        begun = artworks.filter { $0.kind == .paintByNumber && $0.inProgress }
            .compactMap { artwork in word(for: artwork).map { ($0, artwork) } }

        let stats = (try? modelContext.fetch(FetchDescriptor<WordDrawingStat>())) ?? []
        wordsDrawn = stats.filter { $0.totalDrawn > 0 }.count
        Task.detached(priority: .utility) {
            let bytes = WordArtStore.totalBytes()
            await MainActor.run { storedBytes = bytes }
        }
    }
}

private extension String {
    var leadingArticle: String? {
        let first = split(separator: " ").first.map { $0.lowercased() }
        return ["der", "die", "das"].contains(first ?? "") && split(separator: " ").count > 1 ? first : nil
    }

    var strippingArticle: String {
        guard leadingArticle != nil else { return self }
        return split(separator: " ").dropFirst().joined(separator: " ")
    }
}
