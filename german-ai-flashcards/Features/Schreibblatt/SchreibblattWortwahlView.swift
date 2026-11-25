//
//  SchreibblattWortwahlView.swift
//  german-ai-flashcards
//
//  Picking the words for a writing sheet. Every word on the device in one checkbox list, looked
//  at four ways: newest first, grouped by deck, alphabetical, and ranked by how much practice it
//  looks like it needs.
//
//  **The selection is the state; a lens is only a view of it.** Switching lens or typing in the
//  search field never changes a tick. That is what makes four lenses feel like one screen rather
//  than four pickers, and `SchreibblattPractice` is written to keep the promise (every lens
//  returns the same set, reordered).
//
//  **The cards are snapshotted once on appear.** A filtered `@Query` whose cards are read in
//  `body` re-renders forever once the screen is pushed, and with thousands of cards this is the
//  likeliest screen in the app to hit it — the freeze looks like a crash. So the `@Query`s here
//  are read exactly once, into value structs, and every lens, the search and the ranking run off
//  that array.
//
//  The deck filter (the Decks pill) narrows the rows the way the search does, never the selection:
//  a word ticked under another deck stays ticked, and the bar says how many ticks are out of view.
//  Every row outside the Deck lens names its deck, and "Alle abwählen" clears every tick at once
//  (a new sheet starts from the last sheet's words, so this is the quick way to start over).
//
//  A word already written carries a pencil and a count on the right: how many finished sheets it
//  was on (`writtenCounts`, read once with the cards). Started-but-unfinished sheets and the blank
//  parts of a set don't count.
//
//  See docs/SCHREIBBLATT.md.
//

import SwiftData
import SwiftUI

struct SchreibblattWortwahlView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    /// Unfiltered on purpose — the snapshot below reads these once, so there is no live filtered
    /// query whose results get read in `body`.
    @Query private var decks: [SavedDeck]
    @Query private var articleStats: [ArticleWordStat]
    @Query private var pairStats: [MatchingPairStat]

    @State private var candidates: [SchreibblattPractice.Candidate] = []
    @State private var selected: Set<UUID> = []
    @State private var lens: SchreibblattPractice.Lens = .neu
    @State private var searchText = ""
    /// Decks the rows are narrowed to; empty shows every deck.
    @State private var deckFilter: Set<UUID> = []
    /// Every deck with a word here, newest first, with its word count. Read once with the cards.
    @State private var deckOptions: [DeckOption] = []
    @State private var loaded = false
    /// The picker pushes the setup screen itself rather than handing the words back up. Two
    /// `navigationDestination` modifiers on one view is a fragile arrangement, and this keeps the
    /// hub to one.
    @State private var pending: Pending?
    /// Finished sheets each card's word was written on, by card id. Read once with the cards.
    @State private var writtenCounts: [UUID: Int] = [:]

    private struct DeckOption: Identifiable, Hashable {
        let id: UUID
        let title: String
        let count: Int
    }

    private struct Pending: Identifiable, Hashable {
        let id = UUID()
        let words: [SchreibblattWord]
        let deckIDs: [UUID]
        let deckOfWord: [UUID: UUID]
    }

    /// The last sheet's words, so a second sheet starts from the first. Mirrors
    /// `DeckMixPickerSheet`'s `deckMix.lastSelection`, with its own key.
    @AppStorage("schreibblatt.lastSelection") private var lastSelection = ""

    var body: some View {
        List {
            Section {
                lensChips.themedListRow()
            }

            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.rows) { candidate in
                        row(candidate)
                    }
                    .themedListRow()
                } header: {
                    if let title = group.title {
                        header(title, rows: group.rows)
                    }
                }
            }

            if visible.isEmpty {
                Section {
                    ContentUnavailableView(
                        candidates.isEmpty ? "Noch keine Wörter" : "Nichts gefunden",
                        systemImage: candidates.isEmpty ? "rectangle.stack" : "magnifyingglass",
                        description: Text(candidates.isEmpty
                            ? "Make a deck first — every word on your device shows up here."
                            : (searchText.isEmpty
                               ? "No word in the chosen decks."
                               : "No word matches “\(searchText)”."))
                    )
                    .themedListRow()
                }
            }
        }
        .themedListScreen()
        .navigationTitle("Wörter wählen")
        .searchable(text: $searchText, prompt: "Search words or translations")
        .safeAreaInset(edge: .bottom) { selectionBar }
        .onAppear(perform: load)
        .navigationDestination(item: $pending) {
            SchreibblattSetupView(words: $0.words, sourceDeckIDs: $0.deckIDs, deckOfWord: $0.deckOfWord)
        }
    }

    // MARK: - Rows

    private func row(_ candidate: SchreibblattPractice.Candidate) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { toggle(candidate.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected.contains(candidate.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected.contains(candidate.id)
                                     ? SchreibblattTile.tint : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.word.german)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(candidate.word.english)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Only Braucht Übung explains itself; elsewhere this would just repeat the
                    // lens's own sort key on every row.
                    if lens.showsReasons {
                        Text(candidate.detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if let written = writtenCounts[candidate.id] {
                    writtenBadge(written)
                }
                // The Deck lens already heads each group with it.
                if lens != .deck {
                    deckChip(candidate.deckTitle)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// How many finished sheets a word was written on.
    private func writtenBadge(_ count: Int) -> some View {
        Label("\(count)", systemImage: "pencil.line")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(SchreibblattTile.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(SchreibblattTile.tint.opacity(0.12), in: Capsule())
            .fixedSize()
            .accessibilityLabel(count == 1 ? "Written on 1 sheet" : "Written on \(count) sheets")
    }

    /// Which deck a word is from, in the row's free space.
    private func deckChip(_ title: String) -> some View {
        Label(title.isEmpty ? "Deck" : title, systemImage: "rectangle.stack")
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1), in: Capsule())
            .frame(maxWidth: 260, alignment: .trailing)
            .layoutPriority(-1)
            .accessibilityLabel("Deck: \(title)")
    }

    private func header(_ title: String, rows: [SchreibblattPractice.Candidate]) -> some View {
        let ids = rows.map(\.id)
        let allOn = !ids.isEmpty && ids.allSatisfy { selected.contains($0) }
        return HStack {
            Text(title).themedSectionHeader()
            Spacer()
            // What replaces a deck-level picker: the Deck lens selects words, and its header
            // takes the whole deck in one tap.
            Button(allOn ? "Keine" : "Alle") {
                withAnimation(.snappy(duration: 0.2)) {
                    if allOn { selected.subtract(ids) } else { selected.formUnion(ids) }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(SchreibblattTile.tint)
        }
    }

    private var lensChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SchreibblattPractice.Lens.allCases) { candidate in
                    FilterPill(label: candidate.title, tint: SchreibblattTile.tint,
                               isOn: lens == candidate, showsClearGlyph: false) {
                        withAnimation(.snappy(duration: 0.25)) { lens = candidate }
                    }
                }
                if deckOptions.count > 1 {
                    Divider().frame(height: 18)
                    deckMenu
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    /// Narrow the rows to some decks. A menu, since there may be dozens; it stays open while
    /// decks are ticked.
    private var deckMenu: some View {
        let isOn = !deckFilter.isEmpty
        let tint = SchreibblattTile.tint
        return Menu {
            Toggle("Alle Decks · Every deck", isOn: Binding(
                get: { deckFilter.isEmpty },
                set: { on in if on { withAnimation(.snappy(duration: 0.2)) { deckFilter = [] } } }
            ))
            Divider()
            ForEach(deckOptions) { deck in
                Toggle(isOn: Binding(
                    get: { deckFilter.contains(deck.id) },
                    set: { on in
                        withAnimation(.snappy(duration: 0.2)) {
                            if on { deckFilter.insert(deck.id) } else { deckFilter.remove(deck.id) }
                        }
                    }
                )) {
                    Text(deck.title.isEmpty ? "Deck" : deck.title)
                    Text(deck.count == 1 ? "1 Wort" : "\(deck.count) Wörter")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(deckFilterTitle)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? .white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? tint : tint.opacity(0.12), in: theme.pillShape)
        }
        .keepsMenuOpen()
        .accessibilityLabel("Filter by deck")
        .accessibilityValue(deckFilterTitle)
    }

    private var deckFilterTitle: String {
        switch deckFilter.count {
        case 0: return "Decks"
        case 1: return deckOptions.first { deckFilter.contains($0.id) }?.title ?? "1 Deck"
        default: return "\(deckFilter.count) Decks"
        }
    }

    // MARK: - The bar

    private var selectionBar: some View {
        let count = selected.count
        let limit = SchreibblattLayout.maxWordCount()
        let tooMany = count > limit
        let shown = Set(visible.map(\.id))
        let outOfView = selected.subtracting(shown).count
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(count == 1 ? "1 ausgewählt" : "\(count) ausgewählt")
                        .font(.subheadline.weight(.semibold))
                    Text(tooMany
                         ? "More than a page holds, so they're written in parts"
                         : (count == 0 ? "Pick the words you want to write out"
                                       : (outOfView > 0 ? "\(outOfView) of them not in this view"
                                                        : "tables of \(count)")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if count > 0 {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selected = [] }
                    } label: {
                        Label("Alle abwählen", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.secondary)
                    .accessibilityLabel("Deselect all")
                }
                Button("Weiter") { cont() }
                    .buttonStyle(.borderedProminent)
                    .tint(SchreibblattTile.tint)
                    .disabled(count == 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    // MARK: - Data

    /// Read the store once. Everything after this is value types, which is what keeps the screen
    /// off the `@Query` body loop.
    private func load() {
        guard !loaded else { return }
        loaded = true

        let facts = decks.flatMap { deck -> [SchreibblattPractice.CardFacts] in
            deck.cards.map { card in
                SchreibblattPractice.CardFacts(
                    id: card.id,
                    german: card.germanWord.withArticle(card.article),
                    english: card.englishTranslation,
                    deckID: deck.id,
                    deckTitle: deck.topic,
                    deckCreatedAt: deck.createdAt,
                    sortOrder: card.sortOrder,
                    lapses: card.lapses,
                    repetitions: card.repetitions,
                    interval: card.interval,
                    lastReviewWasCorrect: card.lastReviewWasCorrect,
                    lastReviewedAt: card.lastReviewedAt,
                    nextReviewDate: card.nextReviewDate
                )
            }
        }

        writtenCounts = Self.writtenCounts(
            (try? modelContext.fetch(FetchDescriptor<SchreibblattSheet>(
                predicate: #Predicate { $0.finishedAt != nil }))) ?? [])

        candidates = SchreibblattPractice.candidates(
            cards: facts,
            articleStats: articleStats.map {
                .init(key: SchreibblattPractice.joinKey($0.key), timesMissed: $0.timesMissed,
                      lastMissedAt: $0.lastMissedAt, isTricky: $0.isTricky)
            },
            pairStats: pairStats.map {
                .init(key: SchreibblattPractice.joinKey($0.german), timesMissed: $0.timesMissed,
                      lastMissedAt: $0.lastMissedAt, isTricky: $0.isTricky)
            }
        )

        var counts: [UUID: (title: String, created: Date, count: Int)] = [:]
        for candidate in candidates {
            counts[candidate.deckID, default: (candidate.deckTitle, candidate.deckCreatedAt, 0)].count += 1
        }
        deckOptions = counts
            .sorted { $0.value.created > $1.value.created }
            .map { DeckOption(id: $0.key, title: $0.value.title, count: $0.value.count) }

        // Restore the last sheet's words, keeping only ones still on the device.
        let known = Set(candidates.map(\.id))
        selected = Set(lastSelection.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
            .intersection(known)
    }

    /// What the rows show: the lens's order, narrowed by the search and the deck filter. The
    /// selection is never narrowed.
    private var visible: [SchreibblattPractice.Candidate] {
        let rows = SchreibblattPractice.matching(
            SchreibblattPractice.ordered(candidates, by: lens), search: searchText)
        return deckFilter.isEmpty ? rows : rows.filter { deckFilter.contains($0.deckID) }
    }

    private struct Group {
        /// Nil in a flat lens; `ForEach` still needs an id, so the title doubles as one.
        var title: String?
        var rows: [SchreibblattPractice.Candidate]
    }

    /// The visible rows, cut into sections where the lens groups them. Order is preserved, so a
    /// grouped lens's rows are already contiguous per group.
    private var groups: [Group] {
        let rows = visible
        guard lens.isGrouped else { return rows.isEmpty ? [] : [Group(title: nil, rows: rows)] }
        var out: [Group] = []
        for row in rows {
            let title = SchreibblattPractice.group(for: row, lens: lens)
            if out.last?.title == title, !out.isEmpty {
                out[out.count - 1].rows.append(row)
            } else {
                out.append(Group(title: title, rows: [row]))
            }
        }
        return out
    }

    // MARK: - Actions

    /// Ticks live in `selected`, not in the row list, so search and lens cannot disturb them.
    /// Finished sheets per word, counting only what was on the page (`writtenWords`) and a word
    /// once per sheet.
    static func writtenCounts(_ sheets: [SchreibblattSheet]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for sheet in sheets where sheet.isFinished {
            for id in Set(sheet.writtenWords.map(\.id)) { counts[id, default: 0] += 1 }
        }
        return counts
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func cont() {
        // In the order the current lens shows them, so the sheet reads the way the screen did.
        let picked = SchreibblattPractice.ordered(candidates, by: lens)
            .filter { selected.contains($0.id) }
        guard !picked.isEmpty else { return }
        lastSelection = picked.map(\.id.uuidString).joined(separator: ",")
        pending = Pending(words: picked.map(\.word), deckIDs: Array(Set(picked.map(\.deckID))),
                          deckOfWord: Dictionary(picked.map { ($0.id, $0.deckID) },
                                                 uniquingKeysWith: { first, _ in first }))
    }
}

private extension View {
    /// Ticking several decks without the menu closing after each. iOS only: the Mac's menus have
    /// no such option and close as menus do there.
    @ViewBuilder
    func keepsMenuOpen() -> some View {
        #if os(iOS)
        menuActionDismissBehavior(.disabled)
        #else
        self
        #endif
    }
}
