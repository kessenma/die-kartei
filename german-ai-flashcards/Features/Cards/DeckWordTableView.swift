//
//  DeckWordTableView.swift
//  german-ai-flashcards
//
//  Wortliste: every word in a deck at once, as a table. Search, sort by a column, show the
//  examples, see how each card went in flashcards (missed last time, forgotten N×) and how often
//  it has been written by hand on a finished Schreibblatt, and hide one column to test yourself
//  the way you would cover half a paper list. Opened from a deck's setup screen ("See all N
//  words") and from a deck row on a Deutschkurs course page. Shared as a PDF, CSV or text through
//  `DeckTableExport`.
//
//  The rows are a snapshot taken on appear, so the table never observes the deck's card
//  relationship in `body` (reading cards in body under a pushed screen is how the Präpositionen
//  hub once re-rendered forever).
//

import SwiftUI
import SwiftData

/// One word in the table, copied out of a card so the view holds plain values. Nonisolated and
/// Sendable so the export (`DeckTableExport`) can write it whenever the share sheet asks.
nonisolated struct DeckWordRow: Identifiable, Sendable {
    /// The card's position in the deck, from 1.
    let id: Int
    let german: String
    let article: String?
    let english: String
    let wordType: String?
    let example: String?
    let forms: String?
    /// How the card has gone in flashcards. Nil for loose cards that were never saved.
    let progress: Progress?
    /// Finished writing sheets this card was on. Nil when it has never been written by hand.
    let written: Written?

    struct Progress: Sendable {
        /// SM-2 / Leitner reviews. Default mode leaves this at 0 and only stamps `lastCorrect`.
        let reviews: Int
        /// Rated "Again" in Anki, or sent back to box 1 in Leitner.
        let lapses: Int
        /// The last answer in any mode; nil before the first one.
        let lastCorrect: Bool?

        enum State { case new, missed, knew }

        var state: State {
            switch lastCorrect {
            case false?: .missed
            case true?: .knew
            case nil: reviews == 0 ? .new : .knew
            }
        }

        var hasAnswers: Bool { lastCorrect != nil || reviews > 0 }

        /// "Missed last time", "Knew it", "New".
        var label: String {
            switch state {
            case .new: "New"
            case .missed: "Missed last time"
            case .knew: "Knew it"
            }
        }

        /// "Missed", "Knew it", "New": for a narrow column under a legend that says "last time".
        var shortLabel: String {
            switch state {
            case .new: "New"
            case .missed: "Missed"
            case .knew: "Knew it"
            }
        }

        /// "forgotten 2×" when the card has lapsed, else nil.
        var forgotten: String? { lapses > 0 ? "forgotten \(lapses)×" : nil }

        /// The label and the lapse count in one line, for an export cell.
        var summary: String { [label, forgotten].compactMap { $0 }.joined(separator: ", ") }
    }

    /// Handwriting on Schreibblatt sheets: each finished sheet writes every word on it
    /// `repetitions` times, so `times` is the sum of those.
    struct Written: Sendable {
        let times: Int
        let sheets: Int

        var label: String { "\(times)×" }
        var detail: String { sheets == 1 ? "\(times)× on 1 sheet" : "\(times)× on \(sheets) sheets" }
    }

    /// The German word without an article baked into it, for sorting and gender counts.
    var bareGerman: String {
        guard let article, !article.isEmpty,
              german.lowercased().hasPrefix(article.lowercased() + " ") else { return german }
        return String(german.dropFirst(article.count + 1))
    }

    var gender: Gender? { article.flatMap(Gender.init(article:)) }
}

extension DeckWordRow {
    static func rows(cards: [VocabCard], savedCards: [SavedCard],
                     written: [UUID: Written] = [:]) -> [DeckWordRow] {
        cards.enumerated().map { index, card in
            let saved = savedCards.indices.contains(index) ? savedCards[index] : nil
            return DeckWordRow(
                id: index + 1,
                german: card.germanWord,
                article: card.article,
                english: card.englishTranslation,
                wordType: card.wordType,
                example: card.exampleSentence,
                forms: card.forms,
                progress: saved.map {
                    Progress(reviews: $0.totalReviews, lapses: $0.lapses, lastCorrect: $0.lastReviewWasCorrect)
                },
                written: saved.flatMap { written[$0.id] }
            )
        }
    }

    static func rows(deck: SavedDeck, written: [UUID: Written] = [:]) -> [DeckWordRow] {
        let saved = deck.cards.sorted { $0.sortOrder < $1.sortOrder }
        return rows(cards: saved.map(\.vocabCard), savedCards: saved, written: written)
    }

    /// Handwriting per card, from every finished writing sheet on this device (sheets don't sync).
    /// A sheet counts the words actually on its pages (`writtenWords`), each once, the same rule
    /// as the Schreibblatt word picker's pencil count; `times` adds the sheet's repetitions.
    static func handwriting(in context: ModelContext) -> [UUID: Written] {
        let sheets = (try? context.fetch(FetchDescriptor<SchreibblattSheet>(
            predicate: #Predicate { $0.finishedAt != nil }))) ?? []
        var times: [UUID: Int] = [:]
        var count: [UUID: Int] = [:]
        for sheet in sheets where sheet.isFinished {
            for id in Set(sheet.writtenWords.map(\.id)) {
                times[id, default: 0] += max(sheet.repetitions, 1)
                count[id, default: 0] += 1
            }
        }
        return times.reduce(into: [:]) { out, entry in
            out[entry.key] = Written(times: entry.value, sheets: count[entry.key] ?? 0)
        }
    }
}

struct DeckWordTableView: View {
    let title: String
    private let load: (ModelContext) -> [DeckWordRow]

    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelContext) private var modelContext

    @State private var rows: [DeckWordRow] = []
    @State private var loaded = false
    @State private var searchText = ""
    @State private var sort: SortKey = .deck
    @State private var ascending = true
    @AppStorage("deckWordTable.showExamples") private var showExamples = false
    /// Whether a shared list carries the flashcard and handwriting columns.
    @AppStorage("deckWordTable.shareProgress") private var shareProgress = true
    @State private var cover: Cover = .none
    /// Rows tapped open while a column is hidden.
    @State private var revealed: Set<Int> = []
    @State private var width: CGFloat = 0

    /// A saved deck: rows are read from its cards when the screen appears.
    init(deck: SavedDeck) {
        self.title = deck.topic.replacingOccurrences(of: "Class: ", with: "")
        self.load = { DeckWordRow.rows(deck: deck, written: DeckWordRow.handwriting(in: $0)) }
    }

    /// The cards a study session holds (index-aligned with `savedCards` when they're saved).
    init(title: String, cards: [VocabCard], savedCards: [SavedCard]) {
        self.title = title.replacingOccurrences(of: "Class: ", with: "")
        self.load = { context in
            DeckWordRow.rows(cards: cards, savedCards: savedCards,
                             written: savedCards.isEmpty ? [:] : DeckWordRow.handwriting(in: context))
        }
    }

    /// The column hidden for self-testing; a tap on a row shows it for that row.
    enum Cover: String, CaseIterable, Identifiable {
        case none, german, english
        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: "Show both"
            case .german: "Hide German"
            case .english: "Hide English"
            }
        }
    }

    enum SortKey: String, CaseIterable, Identifiable {
        case deck, german, english, type, progress, written
        var id: String { rawValue }

        var label: String {
            switch self {
            case .deck: "Deck order"
            case .german: "Deutsch A–Z"
            case .english: "English A–Z"
            case .type: "Word type"
            case .progress: "Missed first"
            case .written: "Most written"
            }
        }

        var systemImage: String {
            switch self {
            case .deck: "list.number"
            case .german: "textformat"
            case .english: "textformat.abc"
            case .type: "tag"
            case .progress: "exclamationmark.circle"
            case .written: "pencil.and.scribble"
            }
        }
    }

    // MARK: - Derived

    /// A column of "New" says nothing, so progress shows once any card has been answered.
    private var hasProgress: Bool { rows.contains { $0.progress?.hasAnswers == true } }
    private var hasWritten: Bool { rows.contains { $0.written != nil } }
    private var hasExamples: Bool { rows.contains { !($0.example ?? "").isEmpty } }
    private var hasTypes: Bool { rows.contains { !($0.wordType ?? "").isEmpty } }
    /// iPad, Mac, or a phone in landscape: room for the type, example and progress columns.
    private var isWide: Bool { width >= 640 }

    private var visibleRows: [DeckWordRow] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? rows : rows.filter {
            $0.german.localizedStandardContains(query)
                || $0.english.localizedStandardContains(query)
                || ($0.example ?? "").localizedStandardContains(query)
        }
        return ordered(filtered)
    }

    /// `rows` in the order the table is sorted by. The export takes every row this way, whatever
    /// the search, so a forgotten search never sends half a deck.
    private func ordered(_ filtered: [DeckWordRow]) -> [DeckWordRow] {
        let sorted: [DeckWordRow]
        switch sort {
        case .deck:
            sorted = filtered
        case .german:
            sorted = filtered.sorted { Self.order(Self.lettersFirst($0.bareGerman), Self.lettersFirst($1.bareGerman), $0.id, $1.id) }
        case .english:
            sorted = filtered.sorted { Self.order(Self.englishKey($0.english), Self.englishKey($1.english), $0.id, $1.id) }
        case .type:
            sorted = filtered.sorted { Self.order($0.wordType ?? "~", $1.wordType ?? "~", $0.id, $1.id) }
        case .progress:
            sorted = filtered.sorted { a, b in
                let ka = Self.trickiness(a), kb = Self.trickiness(b)
                return ka != kb ? ka > kb : a.id < b.id
            }
        case .written:
            sorted = filtered.sorted { a, b in
                let ta = a.written?.times ?? 0, tb = b.written?.times ?? 0
                return ta != tb ? ta > tb : a.id < b.id
            }
        }
        return ascending ? sorted : sorted.reversed()
    }

    private static func order(_ a: String, _ b: String, _ ia: Int, _ ib: Int) -> Bool {
        let result = a.compare(b, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        return result == .orderedSame ? ia < ib : result == .orderedAscending
    }

    /// "to run" sorts under r, not t, and a quoted gloss under its first word.
    private static func englishKey(_ english: String) -> String {
        let trimmed = lettersFirst(english)
        return trimmed.lowercased().hasPrefix("to ") ? String(trimmed.dropFirst(3)) : trimmed
    }

    /// Drops leading quotes, brackets and dashes so they don't all sort to the top.
    private static func lettersFirst(_ text: String) -> String {
        String(text.drop { !$0.isLetter && !$0.isNumber })
    }

    /// Missed last time ranks above everything, then the cards forgotten most often, then new.
    private static func trickiness(_ row: DeckWordRow) -> Int {
        // New cards rank between the forgotten and the known ones: unpractised, not proven.
        guard let p = row.progress else { return 0 }
        switch p.state {
        case .missed: return 10_000 + p.lapses
        case .knew: return p.lapses > 0 ? 1_000 + p.lapses : 0
        case .new: return 500
        }
    }

    // MARK: - Body

    var body: some View {
        let shown = visibleRows
        let columns = Columns(width: width, wide: isWide, showType: isWide && hasTypes,
                              showExample: showExamples && hasExamples && isWide, showProgress: hasProgress,
                              showWritten: hasWritten)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                summary
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                Section {
                    if shown.isEmpty && loaded {
                        Text(rows.isEmpty ? "This deck has no cards yet." : "No word matches “\(searchText)”.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { position, row in
                        rowView(row, columns: columns)
                            .background(position.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035))
                    }
                } header: {
                    headerRow(columns: columns)
                }
            }
            .padding(.bottom, 16)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .themedScreen()
        .navigationTitle("Wortliste")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search German or English")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { shareMenu }
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
        .onAppear {
            guard !loaded else { return }
            rows = load(modelContext)
            loaded = true
        }
    }

    // MARK: - Pieces

    /// Deck name, word count, and the der/die/das split in gender colours.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .themedLabel(.headline, size: 17)
                .lineLimit(2)
            HStack(spacing: 10) {
                Text(rows.count == 1 ? "1 word" : "\(rows.count) words")
                    .foregroundStyle(.secondary)
                ForEach([Gender.der, .die, .das], id: \.self) { gender in
                    let count = rows.filter { $0.gender == gender }.count
                    if count > 0 {
                        Text("\(gender.article) \(count)")
                            .foregroundStyle(gender.color)
                            .fontWeight(.semibold)
                    }
                }
            }
            .font(.subheadline)

            // Its own line: on a phone it does not fit beside the gender counts.
            if hasProgress || hasWritten {
                HStack(spacing: 14) {
                    let missed = rows.filter { $0.progress?.state == .missed }.count
                    if hasProgress {
                        Label("\(missed) missed last time", systemImage: "xmark.circle.fill")
                            .foregroundStyle(missed > 0 ? Color.red : Color.secondary)
                    }
                    if hasWritten {
                        Label("\(rows.filter { $0.written != nil }.count) written by hand",
                              systemImage: "pencil.and.scribble")
                            .foregroundStyle(.secondary)
                    }
                }
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 8)
    }

    /// Send the list to a tutor or classmates: a PDF table, a spreadsheet, or a message.
    private var shareMenu: some View {
        Menu {
            Section("All \(rows.count) words, in this order") {
                shareLink(.pdf, "PDF table", "doc.richtext")
                shareLink(.csv, "Spreadsheet (CSV)", "tablecells")
                shareLink(.text, "Text for a message", "text.bubble")
            }
            Section {
                if hasProgress || hasWritten {
                    Toggle("Include my progress", systemImage: "chart.bar.doc.horizontal", isOn: $shareProgress)
                }
                if hasExamples {
                    Toggle("Include examples", systemImage: "text.quote", isOn: $showExamples)
                }
            } footer: {
                if hasProgress || hasWritten {
                    Text("Progress: missed last time, times forgotten, and times written by hand.")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(rows.isEmpty)
        .accessibilityLabel("Share")
    }

    private func shareLink(_ format: DeckTableDocument.Format, _ label: String, _ symbol: String) -> some View {
        let document = DeckTableDocument(format: format, rows: ordered(rows), title: exportTitle,
                                         includeExamples: showExamples && hasExamples,
                                         includeProgress: shareProgress && (hasProgress || hasWritten))
        // No preview image: an SF Symbol renders as a blank tile there, the file's own icon doesn't.
        return ShareLink(item: document, preview: SharePreview(exportTitle)) {
            Label(label, systemImage: symbol)
        }
    }

    /// The deck's name; a session of loose cards has none worth putting on a page.
    private var exportTitle: String {
        title.isEmpty || title == "Flashcards" ? "Wortliste" : title
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Sort", selection: Binding(
                get: { sort },
                set: { sort = $0; ascending = true }
            )) {
                ForEach(SortKey.allCases.filter { key in
                    switch key {
                    case .progress: hasProgress
                    case .written: hasWritten
                    case .type: hasTypes
                    default: true
                    }
                }) { key in
                    Label(key.label, systemImage: key.systemImage).tag(key)
                }
            }
            if sort != .deck {
                Button(ascending ? "Reverse order" : "Original direction", systemImage: "arrow.up.arrow.down") {
                    ascending.toggle()
                }
            }
            Divider()
            Picker("Test yourself", selection: Binding(
                get: { cover },
                set: { cover = $0; revealed = [] }
            )) {
                ForEach(Cover.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            if hasExamples {
                Divider()
                Toggle("Show examples", systemImage: "text.quote", isOn: $showExamples)
            }
        } label: {
            Image(systemName: cover == .none ? "ellipsis.circle" : "eye.slash.circle")
        }
        .accessibilityLabel("Table options")
    }

    /// The sticky header. Tapping a column sorts by it; tapping it again reverses.
    private func headerRow(columns: Columns) -> some View {
        HStack(spacing: Columns.spacing) {
            if columns.wide {
                headerCell("#", key: .deck, width: Columns.indexWidth)
            }
            headerCell("Deutsch", key: .german, width: columns.german)
            headerCell("English", key: .english, width: columns.english)
            if columns.showType {
                headerCell("Type", key: .type, width: Columns.typeWidth)
            }
            if columns.showExample {
                Text("Example")
                    .frame(width: columns.example, alignment: .leading)
            }
            if columns.showProgress {
                headerCell(columns.wide ? "Flashcards" : "", key: .progress, width: columns.progress,
                           icon: columns.wide ? nil : "checkmark.circle")
            }
            if columns.showWritten {
                headerCell(columns.wide ? "Written" : "", key: .written, width: columns.written,
                           icon: "pencil.and.scribble")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(appTheme.uppercaseSectionHeaders ? .uppercase : nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func headerCell(_ title: String, key: SortKey, width: CGFloat, icon: String? = nil) -> some View {
        Button {
            if sort == key, key != .deck {
                ascending.toggle()
            } else {
                sort = key
                ascending = true
            }
        } label: {
            HStack(spacing: 3) {
                if let icon { Image(systemName: icon) }
                if !title.isEmpty { Text(title).lineLimit(1) }
                if sort == key, key != .deck {
                    Image(systemName: ascending ? "chevron.down" : "chevron.up")
                        .font(.caption2.weight(.bold))
                }
            }
            .foregroundStyle(sort == key ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowView(_ row: DeckWordRow, columns: Columns) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: Columns.spacing) {
                if columns.wide {
                    Text("\(row.id)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: Columns.indexWidth, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text.gendered(row.german, article: row.article)
                        .font(.body.weight(.medium))
                    if let forms = row.forms, !forms.isEmpty {
                        Text(forms)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .covered(isHidden(.german, row))
                .frame(width: columns.german, alignment: .leading)

                Text(row.english)
                    .font(.body)
                    .covered(isHidden(.english, row))
                    .frame(width: columns.english, alignment: .leading)

                if columns.showType {
                    Text(Self.typeLabel(row.wordType))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: Columns.typeWidth, alignment: .leading)
                }
                if columns.showExample {
                    Text(row.example ?? "")
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)
                        .covered(isHidden(.german, row))
                        .frame(width: columns.example, alignment: .leading)
                }
                if columns.showProgress {
                    progressCell(row.progress, wide: columns.wide)
                        .frame(width: columns.progress, alignment: .leading)
                }
                if columns.showWritten {
                    Text(row.written?.label ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: columns.written, alignment: .leading)
                        .accessibilityLabel(row.written.map { "Written \($0.detail)" } ?? "")
                }
            }
            // On a phone the example gets its own line under the pair. It would give the German
            // away, so it waits for the row to be opened too.
            if showExamples, !columns.wide, let example = row.example, !example.isEmpty,
               !isHidden(.german, row) {
                Text(example)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
        .contentShape(Rectangle())
        .onTapGesture {
            guard cover != .none else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                if revealed.contains(row.id) { revealed.remove(row.id) } else { revealed.insert(row.id) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func progressCell(_ progress: DeckWordRow.Progress?, wide: Bool) -> some View {
        if let progress {
            let (symbol, color, label): (String, Color, String) = switch progress.state {
            case .new: ("circle.dashed", .secondary, "New")
            case .missed: ("xmark.circle.fill", .red, "Missed")
            case .knew: ("checkmark.circle.fill", .green, "Knew it")
            }
            if wide {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: symbol).foregroundStyle(color)
                        Text(label)
                    }
                    if let forgotten = progress.forgotten {
                        Text(forgotten).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.subheadline)
                    .accessibilityLabel([progress.label, progress.forgotten].compactMap { $0 }.joined(separator: ", "))
            }
        } else {
            Text("")
        }
    }

    private func isHidden(_ column: Cover, _ row: DeckWordRow) -> Bool {
        cover == column && !revealed.contains(row.id)
    }

    private static func typeLabel(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    // MARK: - Column widths

    /// Column widths for the measured width, so every row lines up under the header.
    private struct Columns {
        static let spacing: CGFloat = 12
        static let indexWidth: CGFloat = 30
        static let typeWidth: CGFloat = 84

        let wide: Bool
        let showType: Bool
        let showExample: Bool
        let showProgress: Bool
        let showWritten: Bool
        let german: CGFloat
        let english: CGFloat
        let example: CGFloat
        let progress: CGFloat
        let written: CGFloat

        init(width: CGFloat, wide: Bool, showType: Bool, showExample: Bool, showProgress: Bool,
             showWritten: Bool) {
            self.wide = wide
            self.showType = showType
            self.showExample = showExample
            self.showProgress = showProgress
            self.showWritten = showWritten
            progress = showProgress ? (wide ? 120 : 22) : 0
            written = showWritten ? (wide ? 76 : 36) : 0

            var fixed: CGFloat = 32   // the row's horizontal padding
            var gaps = 1              // German | English
            if wide { fixed += Self.indexWidth; gaps += 1 }
            if showType { fixed += Self.typeWidth; gaps += 1 }
            if showProgress { fixed += progress; gaps += 1 }
            if showWritten { fixed += written; gaps += 1 }
            if showExample { gaps += 1 }
            let flex = max(width - fixed - CGFloat(gaps) * Self.spacing, 120)

            // German and English share evenly; an example column takes as much as the pair.
            let weights: CGFloat = showExample ? 4 : 2
            german = flex / weights
            english = flex / weights
            example = showExample ? flex * 2 / weights : 0
        }
    }
}

// MARK: - Covered cell

private extension View {
    /// A hidden table cell: the text keeps its size (so rows don't jump when opened) under a
    /// plain bar, and VoiceOver hears "Hidden" instead of the answer.
    @ViewBuilder
    func covered(_ isHidden: Bool) -> some View {
        if isHidden {
            self
                .opacity(0)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hidden")
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview("Wortliste") {
    let cards = [
        VocabCard(germanWord: "Flug", englishTranslation: "flight", wordType: "noun", article: "der",
                  exampleSentence: "Der Flug nach Berlin dauert eine Stunde.", forms: "Plural: Flüge"),
        VocabCard(germanWord: "Bewerbung", englishTranslation: "application", wordType: "noun", article: "die",
                  exampleSentence: "Ich schreibe eine Bewerbung."),
        VocabCard(germanWord: "Gespräch", englishTranslation: "conversation", wordType: "noun", article: "das"),
        VocabCard(germanWord: "sich bewerben", englishTranslation: "to apply", wordType: "verb",
                  exampleSentence: "Sie bewirbt sich um die Stelle."),
        VocabCard(germanWord: "Wie geht's?", englishTranslation: "How are you?", wordType: "phrase"),
    ]
    return NavigationStack {
        DeckWordTableView(title: "Woche 3 · Vokabeln", cards: cards, savedCards: [])
    }
}
