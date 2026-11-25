//
//  SchreibblattHubView.swift
//  german-ai-flashcards
//
//  The Schreibblatt hub: a new sheet, and the sheets already made. Sheets are local-only, so this
//  list is whatever was made on this device — stated in the footer rather than left to surprise
//  someone looking for yesterday's page on another device.
//
//  The rows read `strokeCount` rather than the ink, so listing never opens a file (docs/MEMORY.md).
//  Sheets the learner marked Fertig sit in their own section below the ones still being written.
//
//  Each row names the decks its words came from (`SchreibblattSheet.sourceDeckIDs`): beside the
//  sheet on a wide screen, under it on a narrow one, two at a time with a "+N" that opens the rest.
//  Tapping a deck, or a pill in the strip above the list, shows only that deck's sheets. Deck
//  titles are read once on appear into a dictionary, not through a `@Query` read in `body`.
//
//  A set of parts (a big selection split into sheets, `SchreibblattParts`) is one row, with how far
//  through it the learner is; it opens `SchreibblattSeriesView`, and moves to Fertig once every
//  part is. Deleting it deletes every part and its ink.
//

import SwiftData
import SwiftUI

extension EnvironmentValues {
    /// Leaves the whole writing flow (Wörter wählen ▸ setup ▸ sheet) back to the hub, which sets
    /// it on the picker it pushes. Nil where a sheet was opened straight from a list: dismissing
    /// the sheet is the way back there.
    @Entry var schreibblattLeave: SchreibblattLeave? = nil
}

/// The hub's way back (`schreibblattLeave`). Equal to any other, so setting it never invalidates
/// the views that read it: there is only ever the one hub behind a flow.
struct SchreibblattLeave: Equatable {
    let action: () -> Void
    func callAsFunction() { action() }
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

struct SchreibblattHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SchreibblattSheet.updatedAt, order: .reverse) private var sheets: [SchreibblattSheet]

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var picking = false
    /// Deck titles by id, read on appear. A deck deleted since keeps its sheets, untitled here.
    @State private var deckTitles: [UUID: String] = [:]
    /// Only sheets with words from this deck; nil shows them all.
    @State private var deckFilter: UUID?
    /// Sheets whose whole deck list is open.
    @State private var openDeckLists: Set<UUID> = []
    /// A swipe on a set with writing on it, waiting for a yes.
    @State private var pendingDelete: [Item] = []

    /// How many deck chips a row shows before "+N".
    private static let chipsShown = 2

    /// A row: a sheet on its own, or every part of a set.
    private enum Item: Identifiable {
        case sheet(SchreibblattSheet)
        case series(id: UUID, parts: [SchreibblattSheet])

        var id: UUID {
            switch self {
            case .sheet(let sheet): sheet.id
            case .series(let id, _): id
            }
        }
        var sheets: [SchreibblattSheet] {
            switch self {
            case .sheet(let sheet): [sheet]
            case .series(_, let parts): parts
            }
        }
        var isFinished: Bool { sheets.allSatisfy(\.isFinished) }
        var sourceDeckIDs: [UUID] { sheets.flatMap(\.sourceDeckIDs) }
    }

    /// Sheets on their own and sets, each set where its most recently touched part would be.
    private var items: [Item] {
        var out: [Item] = []
        var seriesSeen = Set<UUID>()
        let bySeries = Dictionary(grouping: sheets.filter(\.isPart)) { $0.seriesID ?? UUID() }
        for sheet in sheets {   // newest first
            guard let id = sheet.seriesID else { out.append(.sheet(sheet)); continue }
            guard seriesSeen.insert(id).inserted else { continue }
            out.append(.series(id: id, parts: (bySeries[id] ?? []).sorted { $0.partIndex < $1.partIndex }))
        }
        return out
    }

    private var shown: [Item] {
        guard let deckFilter else { return items }
        return items.filter { $0.sourceDeckIDs.contains(deckFilter) }
    }
    private var inProgress: [Item] { shown.filter { !$0.isFinished } }
    private var finished: [Item] { shown.filter(\.isFinished) }

    /// The decks the sheets come from, most sheets first: the filter strip's pills.
    private var filterDecks: [(id: UUID, title: String, sheets: Int)] {
        var counts: [UUID: Int] = [:]
        for item in items {
            for id in Set(item.sourceDeckIDs) where deckTitles[id] != nil { counts[id, default: 0] += 1 }
        }
        return counts
            .map { (id: $0.key, title: deckTitles[$0.key] ?? "", sheets: $0.value) }
            .sorted { $0.sheets != $1.sheets ? $0.sheets > $1.sheets : $0.title < $1.title }
    }

    var body: some View {
        List {
            Section {
                Button {
                    picking = true
                } label: {
                    Label("Neues Blatt", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Schreiben").themedSectionHeader()
            } footer: {
                Text("Pick your words, choose how many times to write each one, then write them "
                     + "with the Apple Pencil or print the tables.")
            }
            .themedListRow()

            if filterDecks.count > 1 {
                Section {
                    filterStrip.themedListRow()
                }
            }

            if !inProgress.isEmpty {
                Section {
                    ForEach(inProgress) { item in
                        NavigationLink {
                            destination(item)
                        } label: {
                            row(item)
                        }
                    }
                    .onDelete { delete(at: $0, in: inProgress) }
                } header: {
                    Text("Deine Blätter").themedSectionHeader()
                } footer: {
                    if finished.isEmpty {
                        Text("Sheets and what you wrote on them stay on this device.")
                    }
                }
                .themedListRow()
            }

            if !finished.isEmpty {
                Section {
                    ForEach(finished) { item in
                        NavigationLink {
                            destination(item)
                        } label: {
                            row(item)
                        }
                    }
                    .onDelete { delete(at: $0, in: finished) }
                } header: {
                    Text("Fertig").themedSectionHeader()
                } footer: {
                    Text("Sheets and what you wrote on them stay on this device.")
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle(SchreibblattTile.title)
        .onAppear(perform: loadDeckTitles)
        .confirmationDialog(
            "Delete every part?",
            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete \(pendingDelete.reduce(0) { $0 + $1.sheets.count }) sheets", role: .destructive) {
                remove(pendingDelete)
                pendingDelete = []
            }
        } message: {
            Text("This set's sheets go together, with everything written on them.")
        }
        .navigationDestination(isPresented: $picking) {
            // Finishing a sheet made from here leaves Wörter wählen and its setup screen too.
            SchreibblattWortwahlView()
                .environment(\.schreibblattLeave, SchreibblattLeave { picking = false })
        }
    }

    // MARK: - Decks

    private var filterStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterPill(label: "Alle", tint: SchreibblattTile.tint, isOn: deckFilter == nil,
                           showsClearGlyph: false) {
                    withAnimation(.snappy(duration: 0.2)) { deckFilter = nil }
                }
                ForEach(filterDecks, id: \.id) { deck in
                    FilterPill(label: deck.title.isEmpty ? "Deck" : deck.title,
                               systemImage: "rectangle.stack", tint: SchreibblattTile.tint,
                               isOn: deckFilter == deck.id) {
                        withAnimation(.snappy(duration: 0.2)) {
                            deckFilter = deckFilter == deck.id ? nil : deck.id
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Filter sheets by deck")
    }

    /// A row's decks that still exist, by title.
    private func decks(of item: Item) -> [(id: UUID, title: String)] {
        var seen: Set<UUID> = []
        return item.sourceDeckIDs
            .filter { seen.insert($0).inserted }
            .compactMap { id in deckTitles[id].map { (id: id, title: $0) } }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Two decks, then "+N" opening the rest in place. Each one filters the list to its sheets.
    /// Borderless buttons, so a tap on a chip is the chip's and not the row's link.
    private func deckChips(_ item: Item, _ decks: [(id: UUID, title: String)]) -> some View {
        let open = openDeckLists.contains(item.id)
        let visible = open ? decks : Array(decks.prefix(Self.chipsShown))
        let hidden = decks.count - Self.chipsShown
        return WrapLayout(spacing: 6) {
            ForEach(visible, id: \.id) { deck in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        deckFilter = deckFilter == deck.id ? nil : deck.id
                    }
                } label: {
                    Label(deck.title.isEmpty ? "Deck" : deck.title, systemImage: "rectangle.stack")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(deckFilter == deck.id ? .white : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(deckFilter == deck.id ? SchreibblattTile.tint : Color.secondary.opacity(0.1),
                                    in: Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Deck \(deck.title)")
                .accessibilityHint("Shows only this deck's sheets")
            }
            if hidden > 0 {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if open { openDeckLists.remove(item.id) } else { openDeckLists.insert(item.id) }
                    }
                } label: {
                    Text(open ? "Weniger" : "+\(hidden)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SchreibblattTile.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SchreibblattTile.tint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(open ? "Show fewer decks" : "Show \(hidden) more decks")
            }
        }
    }

    private func loadDeckTitles() {
        let decks = (try? modelContext.fetch(FetchDescriptor<SavedDeck>())) ?? []
        deckTitles = Dictionary(decks.map { ($0.id, $0.topic) }, uniquingKeysWith: { first, _ in first })
        if let deckFilter, deckTitles[deckFilter] == nil { self.deckFilter = nil }
    }

    // MARK: - Rows

    @ViewBuilder
    private func destination(_ item: Item) -> some View {
        switch item {
        case .sheet(let sheet): SchreibblattSheetView(sheet: sheet)
        case .series(let id, _): SchreibblattSeriesView(seriesID: id)
        }
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        let decks = decks(of: item)
        if decks.isEmpty {
            details(item)
        } else if sizeClass == .regular {
            // The row's free space on a wide screen: the decks in a column of their own.
            HStack(alignment: .center, spacing: 16) {
                details(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                deckChips(item, decks)
                    .frame(maxWidth: 380, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                details(item)
                deckChips(item, decks)
            }
        }
    }

    @ViewBuilder
    private func details(_ item: Item) -> some View {
        switch item {
        case .sheet(let sheet): details(sheet)
        case .series(_, let parts): seriesDetails(parts)
        }
    }

    /// A set: its name, how far through it, and a bar.
    private func seriesDetails(_ parts: [SchreibblattSheet]) -> some View {
        let done = parts.filter(\.isFinished)
        let wordsDone = done.reduce(0) { $0 + $1.writtenWords.count }
        let wordsAll = parts.reduce(0) { $0 + $1.writtenWords.count }
        return VStack(alignment: .leading, spacing: 4) {
            Label(parts.first?.seriesTitle ?? "Schreibblatt", systemImage: "square.stack.3d.up")
                .labelStyle(.titleAndIcon)
                .font(.body.weight(.medium))
            HStack(spacing: 6) {
                Text("\(parts.count) Teile · \(wordsDone) von \(wordsAll) Wörtern")
                if done.count == parts.count, let last = done.compactMap(\.finishedAt).max() {
                    Text("·")
                    Label("Fertig \(last.formatted(.dateTime.day().month(.abbreviated)))",
                          systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                } else if let next = parts.first(where: { !$0.isFinished }) {
                    Text("·")
                    Text("weiter mit Teil \(next.partIndex + 1)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: parts.isEmpty ? 0 : Double(done.count) / Double(parts.count))
                .tint(SchreibblattTile.tint)
                .frame(maxWidth: 240)
                .accessibilityLabel("\(done.count) of \(parts.count) parts done")
        }
    }

    private func details(_ sheet: SchreibblattSheet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sheet.title).font(.body.weight(.medium))
            HStack(spacing: 6) {
                Text(sheet.summary)
                if let finishedAt = sheet.finishedAt {
                    Text("·")
                    Label("Fertig \(finishedAt.formatted(.dateTime.day().month(.abbreviated)))",
                          systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                } else if sheet.strokeCount > 0 {
                    Text("·")
                    Label("begonnen", systemImage: "hand.draw")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// A set goes as a whole: every part, and every part's ink. One with writing on it asks first.
    private func delete(at offsets: IndexSet, in list: [Item]) {
        let items = offsets.map { list[$0] }
        if items.contains(where: { item in
            if case .series = item { return item.sheets.contains { $0.strokeCount > 0 || $0.isFinished } }
            return false
        }) {
            pendingDelete = items
        } else {
            remove(items)
        }
    }

    private func remove(_ items: [Item]) {
        for sheet in items.flatMap(\.sheets) {
            // SwiftData does not own the ink file.
            sheet.deleteInk()
            modelContext.delete(sheet)
        }
        try? modelContext.save()
    }
}
