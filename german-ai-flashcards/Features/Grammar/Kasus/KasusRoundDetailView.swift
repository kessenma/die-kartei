//
//  KasusRoundDetailView.swift
//  german-ai-flashcards
//
//  One Kasus round, opened from Verlauf or a unit's "Deine Runden": the score, what it did for
//  the coach, the tally per case, then every answer in its sentence, misses first. A miss shows
//  ~~pick~~ **answer** (the answer in its gender color, the phrase underlined in its case color)
//  and why; a right answer keeps its why folded until tapped. Rounds recorded before the history
//  kept answers show the counts only.
//

import SwiftUI
import SwiftData

struct KasusRoundDetailView: View {
    let round: KasusRound

    @Environment(\.appTheme) private var appTheme
    /// The right answers whose why is showing, by position in `round.items`.
    @State private var expanded: Set<Int> = []

    var body: some View {
        // Decoded once per render.
        let decoded = round.items
        let items = Array(decoded.enumerated())
        let misses = items.filter { !$0.element.outcome.isRight }
        let rights = items.filter { $0.element.outcome.isRight }
        List {
            headerSection(decoded).themedListRow()
            casesSection.themedListRow()
            if items.isEmpty {
                Section {
                    Text("This round is from before Verlauf kept each answer, so only the counts are here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .themedListRow()
            }
            if !misses.isEmpty {
                Section {
                    ForEach(misses, id: \.offset) { _, item in
                        missRow(item)
                    }
                } header: {
                    Text("Die Fehler · Your misses")
                        .themedSectionHeader()
                }
                .themedListRow()
            }
            if !rights.isEmpty {
                Section {
                    ForEach(rights, id: \.offset) { offset, item in
                        rightRow(item, offset: offset)
                    }
                } header: {
                    Text("Richtig · Right first try")
                        .themedSectionHeader()
                } footer: {
                    Text("Tap a sentence to see why.")
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Runde · Round")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
    }

    private var isFinden: Bool { round.step == .find }

    // MARK: - Header

    private func headerSection(_ items: [KasusRoundItem]) -> some View {
        let unit = round.unit
        return Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: unit?.symbol ?? "checklist")
                        .font(.title2)
                        .foregroundStyle(unit?.color ?? .secondary)
                        .frame(width: 44, height: 44)
                        .background((unit?.color ?? .secondary).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: appTheme.innerRadius(10), style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(round.displayTitle(showsUnit: true))
                            .font(.headline)
                        Text(stepLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(dateLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(round.firstTryCount) of \(round.askedCount)")
                        .themedLabel(.largeTitle.weight(.bold), size: 34)
                        .monospacedDigit()
                    Text(isFinden ? "marked right" : "right on the first try")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let coach = coachLine(items) {
                    Label(coach, systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Dativ · Einsetzen · Genus-Hilfe
    private var stepLine: String {
        var parts = [round.unit?.germanTitle ?? "Kasus"]
        if let step = round.step, step != .quick { parts.append(step.germanLabel) }
        if round.isQuickRound { parts.append("\(round.askedCount) Sätze") }
        if let hint = round.hintLevel { parts.append(hint.germanLabel) }
        return parts.joined(separator: " · ")
    }

    /// Montag, 21. September · 14:05 · 3m 12s
    private var dateLine: String {
        var parts = [KasusHistoryFormat.dayTitle(round.date), round.date.formatted(date: .omitted, time: .shortened)]
        if round.durationSeconds > 0 { parts.append(KasusHistoryFormat.duration(round.durationSeconds)) }
        return parts.joined(separator: " · ")
    }

    /// What the round did for the coach's case skills, by the rules `recordRound` used. Nil for a
    /// round that didn't keep its answers.
    private func coachLine(_ items: [KasusRoundItem]) -> String? {
        guard !items.isEmpty else { return nil }
        let counting = items.filter(\.countsTowardSkill)
        let moved = GrammarCase.allCases.filter { kasus in
            counting.filter { $0.kasus == kasus }.count >= KasusService.minItemsPerCase
        }
        if !moved.isEmpty {
            let names = moved.map(\.name).joined(separator: " and ")
            return "Moved the coach's \(names) skill, from \(counting.count) of your own answers."
        }
        if round.step == .find { return "Finden is for spotting cases, so it never moves the coach." }
        if round.unit == .nominativ { return "Nominativ has no coach skill, so this counted for the streak." }
        if round.hintLevel == .viel { return "Viel Hilfe counts for the streak but never moves the coach." }
        return "Didn't move the coach: a case needs \(KasusService.minItemsPerCase) answers without help."
    }

    // MARK: - Nach Fall

    private var casesSection: some View {
        Section {
            CaseTallyBars(perCase: round.perCase, showsCodeWord: true)
                .padding(.vertical, 4)
        } header: {
            Text("Nach Fall · By case")
                .themedSectionHeader()
        }
    }

    // MARK: - Answers

    private func missRow(_ item: KasusRoundItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: item.outcome.symbol)
                    .accessibilityHidden(true)
                Text("\(item.outcome.germanLabel) · \(item.outcome.englishLabel)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                if let kasus = item.kasus {
                    HStack(spacing: 3) {
                        Image(systemName: kasus.symbol)
                            .accessibilityHidden(true)
                        Text(kasus.short)
                    }
                    .foregroundStyle(kasus.color)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            sentence(item)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if isFinden {
                findenLine(item)
            }

            Text(kasusRich: item.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func rightRow(_ item: KasusRoundItem, offset: Int) -> some View {
        let isOpen = expanded.contains(offset)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isOpen { expanded.remove(offset) } else { expanded.insert(offset) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    sentence(item)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                if isOpen {
                    Text(kasusRich: item.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isOpen ? "Hides why" : "Shows why")
    }

    /// Finden, for a phrase painted with the wrong brush: that brush struck through, then the
    /// case it is. (A missed phrase's header already says so.)
    @ViewBuilder
    private func findenLine(_ item: KasusRoundItem) -> some View {
        if let picked = item.pickedCase, let kasus = item.kasus, item.outcome == .wrongPick {
            HStack(spacing: 6) {
                Text(picked.name)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                HStack(spacing: 4) {
                    Image(systemName: kasus.symbol)
                        .accessibilityHidden(true)
                    Text(kasus.name)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(kasus.color)
            }
            .font(.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Marked \(picked.name), it's \(kasus.name)")
        }
    }

    /// The sentence with the phrase in place: in Einsetzen and the Schnellrunde a wrong pick
    /// struck through in front of the answer. The answer is bold in its gender color, the phrase
    /// underlined in its case color. Falls back to the plain sentence when the phrase isn't in it.
    private func sentence(_ item: KasusRoundItem) -> Text {
        let text = item.sentence
        guard let range = phraseRange(item) else { return Text(text) }

        var out = AttributedString(String(text[..<range.lowerBound]))
        if !isFinden, let pick = item.pick, !item.outcome.isRight {
            var struck = AttributedString(pick)
            struck.strikethroughStyle = .single
            struck.foregroundColor = .secondary
            out += struck + AttributedString(" ")
        }

        let phrase = String(text[range])
        let splitAt = phrase.index(phrase.startIndex, offsetBy: min(item.answer.count, phrase.count))
        let underline = Text.LineStyle(pattern: .solid, color: item.kasus?.color ?? .secondary)
        var determiner = AttributedString(String(phrase[..<splitAt]))
        determiner.inlinePresentationIntent = .stronglyEmphasized
        // A pronoun („mir“) has no noun gender to color.
        determiner.foregroundColor = item.formGenus?.color
        determiner.underlineStyle = underline
        var noun = AttributedString(String(phrase[splitAt...]))
        noun.inlinePresentationIntent = .stronglyEmphasized
        noun.underlineStyle = underline
        out += determiner + noun

        out += AttributedString(String(text[range.upperBound...]))
        return Text(out)
    }

    /// Where the phrase sits: at its stored offset when that still holds it, else its first match.
    private func phraseRange(_ item: KasusRoundItem) -> Range<String.Index>? {
        let text = item.sentence
        let length = item.phrase.utf16.count
        if let start = item.phraseStart, start >= 0, start + length <= text.utf16.count {
            let lower = String.Index(utf16Offset: start, in: text)
            let upper = String.Index(utf16Offset: start + length, in: text)
            if text[lower..<upper] == item.phrase { return lower..<upper }
        }
        return text.range(of: item.phrase)
    }
}

// MARK: - Previews

#Preview("Round detail · 4 themes") {
    let container = KasusHistoryPreview.container()
    let round = try! container.mainContext.fetch(
        FetchDescriptor<KasusRound>(sortBy: [SortDescriptor(\.date, order: .reverse)])
    ).first!
    return TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                KasusRoundDetailView(round: round)
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .modelContainer(container)
}

#Preview("Round detail · counts only") {
    let round = KasusRound(storyID: "quick-dativ", unitRaw: KasusUnit.dativ.rawValue,
                           stepRaw: KasusRoundStep.quick.rawValue, askedCount: 10, firstTryCount: 6,
                           durationSeconds: 95,
                           perCase: [.nominativ: .init(asked: 2, firstTry: 2), .akkusativ: .init(asked: 3, firstTry: 2),
                                     .dativ: .init(asked: 5, firstTry: 2)])
    return NavigationStack {
        KasusRoundDetailView(round: round)
    }
    .modelContainer(for: KasusRound.self, inMemory: true)
}
