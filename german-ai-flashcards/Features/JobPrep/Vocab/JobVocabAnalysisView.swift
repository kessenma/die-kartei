//
//  JobVocabAnalysisView.swift
//  german-ai-flashcards
//
//  Häufige Wörter · Word count: the words of one or more job ads, counted. With one ad it is the
//  ad's word list, most frequent first, to tick the unknown ones in a single pass instead of
//  finding each in the text. With several it shows which words the ads share — „in 4 of 5 ads“ —
//  which is the vocabulary of the job itself. Basic words (der, und, Sie, mit…), words already in
//  a deck and, optionally, the Goethe lists up to a level are hidden, so what's left is what the
//  learner might not know. Tick, then „Add to deck“: the same save sheet as the reader's.
//

import SwiftUI
import SwiftData

struct JobVocabAnalysisView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// The ads to count. Nil: every posting (the most recent dozen).
    var initialSelection: Set<UUID>? = nil
    var initialTab: Tab = .words

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \JobPosting.updatedAt, order: .reverse) private var postings: [JobPosting]
    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]

    @AppStorage("jobVocab.hideBasic") private var hideBasic = true
    @AppStorage("jobVocab.hideKnown") private var hideKnown = true
    /// Raw `GoetheLevel`, or "" for no level filter.
    @AppStorage("jobVocab.hideUpTo") private var hideUpToRaw = ""
    @AppStorage("jobVocab.groupForms") private var groupForms = true

    @State private var selected: Set<UUID> = []
    @State private var didSetUp = false
    /// The first count with three ads or more starts on the shared words (in at least two).
    @State private var startOnShared = true
    @State private var tab: Tab = .words
    @State private var minimumAds = 1
    @State private var search = ""
    @State private var words: [JobVocabTerm] = []
    @State private var phrases: [JobVocabTerm] = []
    @State private var formulas: [JobVocabTerm] = []
    /// The parts of each compound in the count, by term id („Software + Entwicklung“).
    @State private var compounds: [String: [String]] = [:]
    @State private var isCounting = false
    @State private var ticked: Set<String> = []
    @State private var showPicker = false
    @State private var showSave = false
    @State private var contextTerm: JobVocabTerm?
    @State private var savedNote: String?
    /// Matched against a term's spellings and stem to hide what is already in a deck.
    @State private var deckWords = JobVocabDeckWords()
    /// Lowercased Goethe headwords and the first level each is on.
    @State private var goetheLevels: [String: GoetheLevel] = [:]

    enum Tab: String, CaseIterable, Identifiable {
        case words = "Wörter"
        case phrases = "Wendungen"
        case formulas = "Formeln"
        var id: String { rawValue }
    }

    private var chosen: [JobPosting] { postings.filter { selected.contains($0.id) } }
    private var hideUpTo: GoetheLevel? { GoetheLevel(rawValue: hideUpToRaw) }

    private var terms: [JobVocabTerm] {
        switch tab {
        case .words: words
        case .phrases: phrases
        case .formulas: formulas
        }
    }

    /// What the list shows after the filters.
    private var visible: [JobVocabTerm] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return terms.filter { term in
            // The formulas are few and each worth knowing: no frequency floor.
            if tab != .formulas, term.adCount < minimumAds { return false }
            if !query.isEmpty, !term.forms.keys.contains(where: { $0.lowercased().contains(query) }) { return false }
            if hideBasic, term.isBasic { return false }
            if hideKnown, deckWords.contains(term), !ticked.contains(term.id) { return false }
            if let hideUpTo, !term.isPhrase, let level = goetheLevel(of: term), level.rank <= hideUpTo.rank { return false }
            return true
        }
    }

    var body: some View {
        List {
            sourcesSection
            if chosen.isEmpty {
                Section {
                    ContentUnavailableView("No ads chosen", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Choose the job ads to count."))
                }
                .themedListRow()
            } else {
                summarySection
                termsSection
            }
        }
        .themedListScreen()
        .navigationTitle("Häufige Wörter")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a word")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { filterMenu }
        }
        .safeAreaInset(edge: .bottom) {
            if !ticked.isEmpty || savedNote != nil { bottomBar }
        }
        .sheet(isPresented: $showPicker) {
            JobPostingMultiPicker(selection: $selected, modelManager: modelManager, mlxService: mlxService)
        }
        .sheet(isPresented: $showSave) {
            JobVocabSaveSheet(
                picks: tickedPicks,
                posting: chosen.count == 1 ? chosen.first : nil,
                modelManager: modelManager,
                mlxService: mlxService
            ) { added, deckTitle, _ in
                ticked.removeAll()
                refreshKnown()
                flash(added == 0 ? "Nothing new for \(deckTitle)" : "Added \(added) to \(deckTitle)")
            }
        }
        .sheet(item: $contextTerm) { term in
            JobVocabContextSheet(term: term, sources: chosen.map(\.asVocabSource))
        }
        .onAppear(perform: setUp)
        .onChange(of: selected) { _, _ in recount() }
        .onChange(of: groupForms) { _, _ in recount() }
    }

    // MARK: - Sections

    private var sourcesSection: some View {
        Section {
            Button {
                showPicker = true
            } label: {
                HStack {
                    Label(chosen.count == 1 ? chosen[0].title : "\(chosen.count) Stellenanzeigen",
                          systemImage: chosen.count == 1 ? "doc.text" : "doc.on.doc")
                        .lineLimit(1)
                    Spacer()
                    Text("Change").font(.caption.weight(.semibold))
                }
            }
        } header: {
            Text("Counting").themedSectionHeader()
        } footer: {
            Text(chosen.count > 1
                 ? "Words the ads share come first: they are the job's own vocabulary."
                 : "Every word of the ad, most frequent first. Choose more ads to see which words they share.")
        }
        .themedListRow()
    }

    @ViewBuilder
    private var summarySection: some View {
        Section {
            Picker("Show", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            if isCounting {
                Text("Counting…")
            } else {
                Text(summaryLine)
            }
        }
        if chosen.count > 1, tab != .formulas {
            Section {
                Stepper("In at least \(minimumAds) of \(chosen.count) ads", value: $minimumAds, in: 1...max(1, chosen.count))
                    .font(.subheadline)
            }
            .themedListRow()
        }
    }

    private var summaryLine: String {
        let content = words.filter { !$0.isBasic }
        let total = content.reduce(0) { $0 + $1.total }
        let known = content.filter { deckWords.contains($0) }.reduce(0) { $0 + $1.total }
        let share = total == 0 ? 0 : Int((Double(known) / Double(total) * 100).rounded())
        let shared = chosen.count > 1 ? " · \(content.filter { $0.adCount > 1 }.count) in more than one ad" : ""
        let shown = "\(visible.count) shown"
        if tab == .formulas {
            return "\(formulas.count) of the usual job-ad phrases · \(shown)"
        }
        if tab == .phrases {
            return "\(phrases.count) phrases\(chosen.count > 1 ? " used in two ads or more" : " used twice or more") · \(shown)"
        }
        return "\(content.count) different words\(shared) · your decks already cover \(share)% of the text · \(shown)"
    }

    private var termsSection: some View {
        Section {
            if !isCounting, visible.isEmpty {
                Text(emptyLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(visible) { term in
                JobVocabTermRow(
                    term: term,
                    adTotal: chosen.count,
                    ticked: ticked.contains(term.id),
                    known: deckWords.contains(term),
                    level: term.isPhrase || tab == .formulas ? nil : goetheLevel(of: term),
                    parts: compounds[term.id]
                ) {
                    toggle(term)
                } onInfo: {
                    contextTerm = term
                }
            }
        } header: {
            HStack {
                Text(tab.rawValue).themedSectionHeader()
                Spacer()
                if !visible.isEmpty {
                    Button(allVisibleTicked ? "Untick all" : "Tick all") { tickAllVisible() }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                }
            }
        }
        .themedListRow()
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Hide basic words (der, und, Sie…)", isOn: $hideBasic)
            Toggle("Hide words in my decks", isOn: $hideKnown)
            Toggle("Group word forms", isOn: $groupForms)
            Picker("Hide Goethe words", selection: $hideUpToRaw) {
                Text("Show all levels").tag("")
                ForEach(GoetheLevel.allCases) { level in
                    Text("Hide up to \(level.rawValue)").tag(level.rawValue)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter")
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let savedNote {
                Label(savedNote, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
            } else {
                Text("\(ticked.count) ticked")
                    .font(.subheadline.weight(.semibold))
                Button("Clear") { ticked.removeAll() }
                    .font(.subheadline)
                Spacer()
                Button {
                    showSave = true
                } label: {
                    Label("Add to deck", systemImage: "rectangle.stack.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - State

    private var allVisibleTicked: Bool { visible.allSatisfy { ticked.contains($0.id) } }

    private func tickAllVisible() {
        if allVisibleTicked {
            ticked.subtract(visible.map(\.id))
        } else {
            ticked.formUnion(visible.map(\.id))
        }
    }

    private func toggle(_ term: JobVocabTerm) {
        if ticked.contains(term.id) { ticked.remove(term.id) } else { ticked.insert(term.id) }
    }

    private var emptyLine: String {
        switch tab {
        case .words: "Nothing left to show: the filters hide every word."
        case .phrases: "No phrase comes up often enough. Choose more ads, or lower the count."
        case .formulas: hideKnown ? "No usual job-ad phrase here that isn't in a deck already." : "None of the usual job-ad phrases here."
        }
    }

    private var tickedPicks: [JobVocabPick] {
        (words + phrases + formulas).filter { ticked.contains($0.id) }.map { JobVocabPick(german: $0.display, example: $0.example) }
    }

    private func goetheLevel(of term: JobVocabTerm) -> GoetheLevel? {
        term.forms.keys.compactMap { goetheLevels[$0.lowercased()] }.min { $0.rank < $1.rank }
    }

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        refreshKnown()
        var levels: [String: GoetheLevel] = [:]
        for word in GoetheVocabService.orderedWords {
            levels[word.word.lowercased()] = levels[word.word.lowercased()] ?? word.lowestLevel
        }
        goetheLevels = levels
        tab = initialTab
        if let initialSelection {
            selected = initialSelection
        } else {
            selected = Set(postings.prefix(12).map(\.id))
        }
        minimumAds = 1
        recount()
    }

    private func refreshKnown() {
        deckWords = JobVocabDeckWords.from(decks)
    }

    /// The compounds among the counted words, split against the Goethe lists, the learner's cards
    /// and the ads' own words.
    private func splitCompounds() {
        var extra: [(word: String, noun: Bool, asWhole: Bool)] = []
        for deck in decks where deck.isBrowsableContent {
            for card in deck.cards { extra.append((card.germanWord, card.article != nil || card.wordType == "noun", true)) }
        }
        for term in words where !term.isBasic {
            for form in term.forms.keys { extra.append((form, form.first?.isUppercase == true, false)) }
        }
        let lexicon = GermanCompoundLexicon.standard(extra: extra)
        var found: [String: [String]] = [:]
        for term in words where !term.isBasic && term.display.first?.isUppercase == true {
            if let parts = GermanCompound.split(term.display, lexicon: lexicon) { found[term.id] = parts }
        }
        compounds = found
    }

    private func recount() {
        let sources = chosen.map(\.asVocabSource)
        let group = groupForms
        isCounting = true
        if minimumAds > max(1, sources.count) { minimumAds = 1 }
        Task {
            let counted = await Task.detached(priority: .userInitiated) {
                (JobVocabAnalyzer.words(in: sources, groupForms: group), JobVocabAnalyzer.phrases(in: sources),
                 JobVocabAnalyzer.formulas(in: sources))
            }.value
            words = counted.0
            phrases = counted.1
            formulas = counted.2
            splitCompounds()
            isCounting = false
            if startOnShared {
                startOnShared = false
                if sources.count > 2 { minimumAds = 2 }
            }
        }
    }

    private func flash(_ note: String) {
        savedNote = note
        Task {
            try? await Task.sleep(for: .seconds(2))
            savedNote = nil
        }
    }
}

extension JobPosting {
    var asVocabSource: JobVocabSource { JobVocabSource(id: id, title: title, text: text) }
}

extension GoetheLevel {
    /// A1 < A2 < B1.
    var rank: Int { GoetheLevel.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Row

private struct JobVocabTermRow: View {
    let term: JobVocabTerm
    let adTotal: Int
    let ticked: Bool
    let known: Bool
    let level: GoetheLevel?
    var parts: [String]? = nil
    let onToggle: () -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(ticked ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(term.display)
                                .font(.body.weight(.medium))
                            if known {
                                Image(systemName: "rectangle.stack.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("In a deck")
                            }
                            if let level {
                                Text(level.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let gloss = term.gloss {
                            Text(gloss)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let note = term.note {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        } else if !term.otherForms.isEmpty {
                            Text("also " + term.otherForms.prefix(4).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let parts {
                            Text(parts.joined(separator: " + "))
                                .font(.caption)
                                .foregroundStyle(.indigo)
                                .accessibilityLabel("Made of " + parts.joined(separator: " and "))
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        if adTotal > 1 {
                            Text("\(term.adCount) of \(adTotal) ads")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                            AdShareBar(share: Double(term.adCount) / Double(max(1, adTotal)))
                        }
                        Text("\(term.total)×")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onInfo) {
                Image(systemName: "text.quote")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Where it comes up")
        }
        .padding(.vertical, 2)
    }
}

private struct AdShareBar: View {
    let share: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(Color.accentColor).frame(width: geo.size.width * share)
            }
        }
        .frame(width: 54, height: 4)
    }
}

// MARK: - Where a word comes up

/// The sentences a word or phrase stands in, ad by ad: whether it is worth a card often depends on
/// what it means there.
struct JobVocabContextSheet: View {
    let term: JobVocabTerm
    let sources: [JobVocabSource]

    @Environment(\.dismiss) private var dismiss

    private var hits: [(title: String, sentences: [String])] {
        sources.filter { term.sources.contains($0.id) }.map { source in
            let sentences = JobVocabAnalyzer.sentences(of: source.text).filter { sentence in
                let words = JobVocabAnalyzer.tokens(in: sentence).map(\.text)
                if term.gloss != nil {
                    return term.forms.keys.contains { sentence.range(of: $0, options: [.caseInsensitive]) != nil }
                }
                if term.isPhrase {
                    return sentence.range(of: term.display, options: [.caseInsensitive]) != nil
                }
                return words.contains { term.forms[$0] != nil }
            }
            return (source.title, Array(sentences.prefix(4)))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                    Section {
                        ForEach(hit.sentences, id: \.self) { sentence in
                            Text(sentence).font(.callout)
                        }
                    } header: {
                        Text(hit.title).themedSectionHeader()
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle(term.display)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
