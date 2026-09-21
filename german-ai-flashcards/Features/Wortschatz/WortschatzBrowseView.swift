//
//  WortschatzBrowseView.swift
//  german-ai-flashcards
//
//  Every Goethe word with its status. Search German or English, narrow by level, word class, and
//  what the box knows about the word (new, due, difficult, known), and tap one for its history.
//

import SwiftUI
import SwiftData

struct WortschatzBrowseView: View {
    /// The hub's scope on arrival; the word-class chips start from it, the level chips from "all".
    let initialScope: WortschatzScope
    let style: FlashcardStyle
    /// The status chip to start on (the hub's "See all from today" link).
    var initialStatus: StatusFilter? = nil

    @Query(filter: #Predicate<SavedDeck> { $0.generatorRaw == "goethe-srs" }) private var srsDecks: [SavedDeck]
    @Query private var articleStats: [ArticleWordStat]
    @Query private var pairStats: [MatchingPairStat]
    @Environment(\.appTheme) private var theme

    @State private var searchText = ""
    @State private var level: GoetheLevel? = nil
    @State private var wordTypes: Set<GoetheWordType> = []
    @State private var status: StatusFilter? = nil
    @State private var selectedWord: GoetheWord? = nil

    enum StatusFilter: String, CaseIterable, Identifiable {
        case today, new, due, difficult, known

        var id: String { rawValue }

        var label: String {
            switch self {
            case .today: "Today"
            case .new: "New"
            case .due: "Due"
            case .difficult: "Tricky"
            case .known: "Known"
            }
        }

        var systemImage: String {
            switch self {
            case .today: "calendar"
            case .new: "sparkle"
            case .due: "clock"
            case .difficult: "exclamationmark.triangle"
            case .known: "checkmark.seal"
            }
        }

        var tint: Color {
            switch self {
            case .today: .blue
            case .new: .gray
            case .due: .orange
            case .difficult: .red
            case .known: .green
            }
        }
    }

    private var deck: SavedDeck? { srsDecks.first { $0.topic == DeckStore.wortschatzTopic } }

    var body: some View {
        let lookup = Lookup(deck: deck, articleStats: articleStats, pairStats: pairStats)
        let leitnerSession = deck?.quizResults.count ?? 0
        let words = filteredWords(lookup: lookup, leitnerSession: leitnerSession)

        List {
            Section {
                WortschatzLevelChips(level: $level)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 0))
                typeChips
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
                statusChips
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 0))
            }
            .themedListRow()

            Section {
                ForEach(words) { word in
                    let card = lookup.card(for: word)
                    Button {
                        selectedWord = word
                    } label: {
                        GoetheEntryRow(
                            word: word,
                            badge: card.map { WortschatzService.badgeText($0, style: style, leitnerSession: leitnerSession) } ?? "new",
                            badgeColor: card.map { WortschatzService.badgeColor($0, style: style, leitnerSession: leitnerSession) } ?? .gray
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(words.count) words").themedSectionHeader()
            }
            .themedListRow()
        }
        .themedListScreen()
        .searchable(text: $searchText, prompt: "Search words or translations")
        .navigationTitle("All Words")
        .navigationBarTitleDisplayMode(.large)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .onAppear {
            if wordTypes.isEmpty {
                wordTypes = initialScope.wordTypes
                status = initialStatus
            }
        }
        .sheet(item: $selectedWord) { word in
            WortschatzWordSheet(
                word: word,
                card: lookup.card(for: word),
                articleStat: lookup.articleStat(for: word),
                matchingStat: lookup.matchingStat(for: word),
                style: style,
                leitnerSession: leitnerSession
            )
        }
    }

    // MARK: - Chips

    private var typeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(GoetheWordType.allCases) { type in
                    FilterPill(label: type.label, tint: .purple, isOn: wordTypes.contains(type), showsClearGlyph: false) {
                        withAnimation(.snappy(duration: 0.25)) {
                            if wordTypes.contains(type) {
                                if wordTypes.count > 1 { wordTypes.remove(type) }
                            } else {
                                wordTypes.insert(type)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var statusChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(StatusFilter.allCases) { candidate in
                    FilterPill(label: candidate.label, systemImage: candidate.systemImage,
                               tint: candidate.tint, isOn: status == candidate) {
                        withAnimation(.snappy(duration: 0.25)) {
                            status = status == candidate ? nil : candidate
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Filtering

    private func filteredWords(lookup: Lookup, leitnerSession: Int) -> [GoetheWord] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return GoetheVocabService.orderedWords.filter { word in
            if let level, !word.levels.contains(level) { return false }
            guard wordTypes.contains(word.wordType) else { return false }
            if !query.isEmpty,
               !word.word.localizedCaseInsensitiveContains(query),
               !(word.translation?.localizedCaseInsensitiveContains(query) ?? false) {
                return false
            }
            guard let status else { return true }
            let card = lookup.card(for: word)
            switch status {
            case .today:
                guard let card else { return false }
                return WortschatzService.reviewedToday(card)
            case .new:
                return card.map { WortschatzService.isNew($0) } ?? true
            case .due:
                guard let card else { return false }
                return WortschatzService.isDue(card, style: style, leitnerSession: leitnerSession)
            case .difficult:
                guard let card else { return false }
                return WortschatzService.isDifficult(
                    card,
                    articleTricky: lookup.articleStat(for: word)?.isTricky ?? false,
                    matchingTricky: lookup.matchingStat(for: word)?.isTricky ?? false
                )
            case .known:
                guard let card else { return false }
                return WortschatzService.isKnown(card)
            }
        }
    }

    /// The per-word joins, built once per body pass rather than once per row.
    private struct Lookup {
        let cards: [String: SavedCard]
        let articles: [String: ArticleWordStat]
        /// Several pair rows can share a headword (one per translation); the trickiest wins.
        let pairs: [String: MatchingPairStat]

        init(deck: SavedDeck?, articleStats: [ArticleWordStat], pairStats: [MatchingPairStat]) {
            cards = Dictionary((deck?.cards ?? []).map { ($0.germanWord, $0) }, uniquingKeysWith: { first, _ in first })
            articles = Dictionary(articleStats.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            pairs = Dictionary(pairStats.map { (ArticleGameService.key(for: $0.german), $0) }) { a, b in
                if a.isTricky != b.isTricky { return a.isTricky ? a : b }
                return a.timesMissed >= b.timesMissed ? a : b
            }
        }

        func card(for word: GoetheWord) -> SavedCard? { cards[word.word] }
        func articleStat(for word: GoetheWord) -> ArticleWordStat? { articles[ArticleGameService.key(for: word.word)] }
        func matchingStat(for word: GoetheWord) -> MatchingPairStat? { pairs[ArticleGameService.key(for: word.word)] }
    }
}

#Preview("Browse · 4 themes") {
    ForEach(AppTheme.allCases) { theme in
        NavigationStack {
            WortschatzBrowseView(initialScope: .all, style: .anki)
        }
        .environment(\.appTheme, theme)
    }
    .modelContainer(for: [SavedDeck.self, SavedCard.self, ArticleWordStat.self, MatchingPairStat.self], inMemory: true)
}
