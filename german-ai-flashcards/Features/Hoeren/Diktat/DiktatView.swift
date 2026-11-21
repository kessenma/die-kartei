//
//  DiktatView.swift
//  german-ai-flashcards
//
//  Diktat: hear a sentence, write it, see it word by word (docs/HOEREN.md ▸ Diktat). Misses are
//  split into "ending only" (the stem was heard) and "word", because in German the meaning sits
//  at the ends of words (FSI lesson 8). DLI-STRAT 1c is the instruction on screen: write what you
//  understand, then fill the gaps from the grammar.
//

import SwiftData
import SwiftUI

struct DiktatView: View {
    let config: DiktatConfig

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var sentences: [DiktatSentence]
    @State private var player = HoerenPlayer()
    @State private var index = 0
    @State private var typed = ""
    @State private var result: DiktatResult?
    @State private var results: [HoerenItem] = []
    @State private var startedAt = Date()
    @State private var saved = false
    @State private var slow = false
    @State private var savedWords: Set<String> = []
    @FocusState private var fieldFocused: Bool

    init(config: DiktatConfig) {
        self.config = config
        _sentences = State(initialValue: config.sentences)
    }

    private var sentence: DiktatSentence? { sentences.indices.contains(index) ? sentences[index] : nil }
    private var finished: Bool { index >= sentences.count }

    var body: some View {
        Group {
            if sentences.isEmpty {
                ContentUnavailableView("No sentences", systemImage: "text.cursor",
                                       description: Text("Pick another level or source."))
            } else if finished {
                DiktatSummaryView(results: results, onAgain: restart, onDone: { dismiss() })
            } else if let sentence {
                drill(sentence)
            }
        }
        .navigationTitle(HoerenRoundKind.diktat.germanLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(finished ? "Done" : "End") {
                    saveIfNeeded()
                    dismiss()
                }
            }
        }
        .themedScreen()
        .onAppear { playCurrent(after: 0.5) }
        .onDisappear {
            player.stop()
            saveIfNeeded()
        }
    }

    // MARK: - Drill

    private func drill(_ sentence: DiktatSentence) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    ProgressView(value: Double(index), total: Double(max(1, sentences.count)))
                        .tint(HoerenTile.tint)
                    Text("Satz \(index + 1) von \(sentences.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                controls(sentence)

                if let result {
                    resultCard(result, sentence: sentence)
                } else {
                    writingField(sentence)
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func controls(_ sentence: DiktatSentence) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                Button {
                    if player.isPlaying { player.stop() } else { player.play(sentence.text, slow: slow) }
                } label: {
                    Image(systemName: player.isPlaying ? "stop.fill" : (player.plays == 0 ? "play.fill" : "arrow.counterclockwise"))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(HoerenTile.tint, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Stop" : "Play")

                if config.playback == .study {
                    Toggle(isOn: $slow) {
                        Label("Langsam", systemImage: "tortoise")
                    }
                    .toggleStyle(.button)
                    .tint(HoerenTile.tint)
                }
            }
            Text(player.plays <= 1 ? (config.playback == .singlePass ? "Heard once. A replay is allowed, and counted." : "Replay and slow down as often as you need.")
                                   : "Played \(player.plays)×")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func writingField(_ sentence: DiktatSentence) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Write what you hear", text: $typed, axis: .vertical)
                .font(.title3)
                .lineLimit(2...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .padding(14)
                .themedCard()

            HStack(spacing: 8) {
                ForEach(["ä", "ö", "ü", "ß", "Ä", "Ö", "Ü"], id: \.self) { letter in
                    Button(letter) { typed.append(letter) }
                        .font(.body.weight(.medium))
                        .buttonStyle(.bordered)
                }
            }
            .tint(HoerenTile.tint)

            Text("Write every word you catch. Where you miss one, let the grammar fill the gap: which ending does the case need?")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                check(sentence)
            } label: {
                Text("Prüfen · Check").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HoerenTile.tint)
            .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || player.plays == 0)
        }
    }

    private func resultCard(_ result: DiktatResult, sentence: DiktatSentence) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(result.rightCount) of \(result.referenceCount) words")
                    .font(.headline)
                Spacer()
                if result.isPerfect {
                    Label("Perfekt", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }

            DiktatDiffView(result: result)

            DiktatLegend(result: result)

            saveButtons(result, sentence: sentence)

            Button {
                next()
            } label: {
                Text(index + 1 < sentences.count ? "Weiter · Next" : "Fertig · Finish")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HoerenTile.tint)
        }
        .padding(16)
        .themedCard()
        .tint(HoerenTile.tint)
    }

    /// The sentence's headword when it was missed; otherwise up to three missed words, with the
    /// dictionary's English.
    @ViewBuilder
    private func saveButtons(_ result: DiktatResult, sentence: DiktatSentence) -> some View {
        let candidates = saveCandidates(result, sentence: sentence)
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(candidates, id: \.german) { word in
                    let done = savedWords.contains(word.german)
                    Button {
                        HoerenDeckStore.save(german: word.german, english: word.english, sentence: sentence.text,
                                             context: modelContext)
                        savedWords.insert(word.german)
                    } label: {
                        Label(done ? "„\(word.german)“ is in the Hören deck" : "Save „\(word.german)“ to the Hören deck",
                              systemImage: done ? "checkmark" : "plus.rectangle.on.rectangle")
                            .font(.callout)
                    }
                    .disabled(done)
                }
            }
        }
    }

    private func saveCandidates(_ result: DiktatResult, sentence: DiktatSentence) -> [(german: String, english: String)] {
        let missed = result.tokens.filter { $0.reference != nil && !$0.cls.countsRight }
        guard !missed.isEmpty else { return [] }
        if let head = sentence.headword {
            return [(german: head, english: sentence.headwordEnglish ?? "")]
        }
        // Content words only: nouns first, then longer words, and only ones the dictionary knows.
        // "ist" or "und" in the Hören deck would be noise.
        let words = missed.filter { $0.cls == .word }.compactMap(\.reference)
            .filter { $0.count >= 4 && !DiktatScorer.isDeterminer($0) }
            .sorted { ($0.first?.isUppercase == true ? 0 : 1) < ($1.first?.isUppercase == true ? 0 : 1) }
        return words.prefix(3).compactMap { word in
            guard let found = WiktionaryValidator.shared.translation(for: word) else { return nil }
            let german = found.article.map { "\($0.rawValue) \(word)" } ?? word
            return (german: german, english: found.english)
        }
    }

    // MARK: - Flow

    private func playCurrent(after delay: Double) {
        guard let sentence else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.sentence?.text == sentence.text, result == nil, player.plays == 0 else { return }
            player.play(sentence.text, slow: slow) { fieldFocused = true }
        }
    }

    private func check(_ sentence: DiktatSentence) {
        guard result == nil else { return }
        player.stop()
        let scored = DiktatScorer.score(reference: sentence.text, typed: typed, focusByWord: sentence.focuses)
        var record = HoerenItem(id: index, expected: sentence.text, spoken: sentence.text)
        record.typed = typed
        record.correct = scored.isPerfect
        record.replays = player.replays
        record.slow = player.slowUsed
        record.diktat = scored
        record.sentenceSourceRaw = sentence.source.rawValue
        record.headword = sentence.headword
        record.headwordEnglish = sentence.headwordEnglish
        results.append(record)
        result = scored
        fieldFocused = false
    }

    private func next() {
        result = nil
        typed = ""
        player.reset()
        index += 1
        if finished { saveIfNeeded() } else { playCurrent(after: 0.3) }
    }

    private func restart() {
        saveIfNeeded()
        var rng = SystemRandomNumberGenerator()
        if config.sourceRaw.hasPrefix("course:") {
            sentences = config.sentences.shuffled(using: &rng)
        } else {
            let kinds = Set(config.sourceRaw.split(separator: ",").compactMap { DiktatSourceKind(rawValue: String($0)) })
            sentences = DiktatSentenceBank.round(level: config.level, sources: kinds, count: config.sentences.count, rng: &rng)
        }
        results = []
        result = nil
        typed = ""
        saved = false
        savedWords = []
        startedAt = Date()
        player.reset()
        index = 0
        playCurrent(after: 0.4)
    }

    private func saveIfNeeded() {
        guard !saved, !results.isEmpty else { return }
        saved = true
        let round = HoerenRound(kind: .diktat)
        round.playbackRaw = config.playback.rawValue
        round.levelRaw = config.level.rawValue
        round.sourceRaw = config.sourceRaw
        round.askedCount = results.count
        round.correctCount = results.filter(\.correct).count
        round.firstPassCount = results.filter(\.firstPass).count
        round.replayCount = results.reduce(0) { $0 + $1.replays }
        round.durationSeconds = max(1, Int(Date().timeIntervalSince(startedAt)))
        round.items = results
        HoerenScoringService.save(round, in: modelContext)
    }
}

// MARK: - Word by word

/// The sentence as the learner should have written it, each word marked by what happened to it.
struct DiktatDiffView: View {
    let result: DiktatResult

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(result.tokens) { token in
                tokenView(token)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func tokenView(_ token: DiktatToken) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(display(token))
                .font(.title3)
            if let under = underline(token) {
                Text(under)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .strikethrough(token.cls != .capital)
            }
        }
    }

    private func display(_ token: DiktatToken) -> AttributedString {
        guard let reference = token.reference else {
            var extra = AttributedString(token.typed ?? "")
            extra.foregroundColor = .secondary
            extra.strikethroughStyle = .single
            return extra
        }
        var out = AttributedString(token.leading)
        switch token.cls {
        case .right:
            out += AttributedString(reference)
        case .capital:
            var w = AttributedString(reference)
            w.foregroundColor = .blue
            out += w
        case .umlautEszett:
            var w = AttributedString(reference)
            w.foregroundColor = .orange
            w.inlinePresentationIntent = .stronglyEmphasized
            out += w
        case .ending:
            let typed = token.typed ?? ""
            let shared = zip(reference.lowercased(), typed.lowercased()).prefix { $0 == $1 }.count
            let stem = String(reference.prefix(shared))
            var ending = AttributedString(String(reference.dropFirst(shared)))
            ending.foregroundColor = .orange
            ending.inlinePresentationIntent = .stronglyEmphasized
            ending.underlineStyle = .single
            out += AttributedString(stem) + ending
        case .word, .extra:
            var w = AttributedString(reference)
            w.foregroundColor = .red
            w.inlinePresentationIntent = .stronglyEmphasized
            out += w
        }
        out += AttributedString(token.trailing)
        return out
    }

    /// What the learner wrote, under a word they got wrong.
    private func underline(_ token: DiktatToken) -> String? {
        guard token.reference != nil else { return nil }
        switch token.cls {
        case .right: return nil
        case .capital: return "capital"
        case .word: return token.typed ?? "—"
        default: return token.typed
        }
    }
}

/// The counts under a sentence, one line per kind of miss that happened.
struct DiktatLegend: View {
    let result: DiktatResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let endings = result.endingMisses
            if !endings.isEmpty {
                let tags = Set(endings.compactMap(\.focus)).map(\.germanLabel).sorted()
                line(.orange, "Ending only: \(endings.count)" + (tags.isEmpty ? "" : " (\(tags.joined(separator: ", ")))"),
                     "You heard the word; the ending carries the grammar.")
            }
            if result.count(.umlautEszett) > 0 {
                line(.orange, "Umlaut or ß: \(result.count(.umlautEszett))", "schon and schön are different words.")
            }
            if result.wordMisses.count > 0 {
                line(.red, "Word: \(result.wordMisses.count)", nil)
            }
            if result.count(.capital) > 0 {
                line(.blue, "Capital letter: \(result.count(.capital))", "Counted as heard; nouns take a capital.")
            }
            if result.count(.extra) > 0 {
                line(.secondary, "Extra: \(result.count(.extra))", "Not counted against you.")
            }
        }
        .font(.caption)
    }

    private func line(_ color: Color, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).fontWeight(.semibold)
            if let detail { Text(detail).foregroundStyle(.secondary) }
        }
    }
}

/// The end of a Diktat round.
struct DiktatSummaryView: View {
    let results: [HoerenItem]
    let onAgain: () -> Void
    let onDone: () -> Void

    private var scored: [DiktatResult] { results.compactMap(\.diktat) }
    private var words: Int { scored.reduce(0) { $0 + $1.referenceCount } }
    private var right: Int { scored.reduce(0) { $0 + $1.rightCount } }
    private var endingsByFocus: [(GrammarFocus?, Int)] {
        let endings = scored.flatMap(\.endingMisses)
        let grouped = Dictionary(grouping: endings, by: { $0.focus }).mapValues(\.count)
        return grouped.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text(words == 0 ? "–" : "\(Int((Double(right) / Double(words) * 100).rounded()))%")
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    Text("\(right) of \(words) words · \(results.filter(\.correct).count) of \(results.count) sentences perfect")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .themedListRow()

            if !endingsByFocus.isEmpty {
                Section {
                    ForEach(endingsByFocus, id: \.0?.rawValue) { focus, count in
                        HStack {
                            Text(focus?.germanLabel ?? "Other endings")
                            Spacer()
                            Text("×\(count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } header: {
                    Text("Endungen · Endings you missed").themedSectionHeader()
                } footer: {
                    Text("The stem was heard and the ending wasn't. Endings tied to a case go to Coach's Notes as fill-in cards; they never change your level.")
                }
                .themedListRow()
            }

            Section {
                ForEach(results) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        if let d = item.diktat { DiktatDiffView(result: d) }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Alle Sätze · All sentences").themedSectionHeader()
            }
            .themedListRow()

            Section {
                Button {
                    onAgain()
                } label: {
                    Label("Noch eine Runde · Another round", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                Button("Fertig · Done", action: onDone)
                    .frame(maxWidth: .infinity)
            }
            .themedListRow()
        }
        .themedListScreen()
    }
}
