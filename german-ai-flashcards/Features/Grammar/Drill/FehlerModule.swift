//
//  FehlerModule.swift
//  german-ai-flashcards
//
//  Finde den Fehler on the shell: one article in a Rollen sentence is wrong (`FehlerQuestion`
//  plants it); the learner taps the word, then picks the fix. Two taps, one step: the find is
//  the scratch state (`Partial`), the fix grades. A fix after a missed find still teaches, but
//  the step counts as a miss and never moves the coach: the sentence had already pointed at the
//  word.
//

import SwiftUI

enum FehlerPick: Hashable {
    /// A word tapped in the sentence (`KasusWord.id`).
    case word(Int)
    /// A form picked for the fix.
    case form(String)
}

/// The find, kept until the fix.
struct FehlerFound: Hashable {
    let right: Bool
}

struct FehlerModule: KasusDrillModule {
    typealias Item = FehlerQuestion
    typealias Pick = FehlerPick
    typealias Partial = FehlerFound

    let unit: KasusUnit

    var kind: KasusDrillKind { .fehler }

    init(session: GrammarDrillSession) {
        unit = session.topic.unit ?? .dativ
    }

    /// The unit's Rollen items with a mistake planted in each, the unit's own case asked most.
    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [FehlerQuestion]? {
        let playables = KasusService.conceptPlayables(unit: unit, exercise: .roles)
        let round = FehlerQuestion.round(playables: playables, casesInPlay: unit.casesInPlay, emphasis: unit.focusCase,
                                         count: kind.meta.roundSize, rng: &rng)
        return round.count >= 4 ? round : nil
    }

    func answer(_ pick: FehlerPick, for item: FehlerQuestion, step: Int, partial: inout FehlerFound?) -> KasusDrillOutcome<FehlerFound> {
        if let found = partial {
            guard case .form(let form) = pick else { return .ignored }
            partial = nil
            let fixRight = form.lowercased() == item.answer.lowercased()
            let slip = !fixRight && item.isGenderSlip(form)
            let outcome: KasusItemOutcome = fixRight ? (found.right ? .right : .wrongPick) : slip ? .genderSlip : .caseMiss
            let explanation = item.explanation
            let record = KasusRoundItem.story(item.target, in: item.playable.story, pick: form, outcome: outcome, explanation: explanation)
            // A missed find is practice: the ring had shown the word before the fix.
            let result = KasusItemResult(kasus: item.kasus, genus: item.genus, firstTry: found.right && fixRight, slip: slip,
                                         targetIndex: item.target.index, record: record, scaffolded: !found.right)
            return .graded(KasusGradedAnswer(outcome: outcome, kasus: item.kasus, explanation: explanation,
                                             cardRight: fixRight && !slip ? (found.right ? nil : true) : nil, result: result))
        }
        guard case .word(let id) = pick, let word = item.playable.sentences.flatMap(\.words).first(where: { $0.id == id }) else { return .ignored }
        let right = item.isInPhrase(word)
        let found = FehlerFound(right: right)
        partial = found
        return .partial(found,
                        line: right ? "Gefunden · Found: „*\(item.wrong)*“ doesn't fit there. Now fix it."
                                    : "Nicht das · Not that one. The mistake is „*\(item.wrong)*“, ringed now. Fix it.",
                        right: right)
    }

    func debugPick(for item: FehlerQuestion, partial: FehlerFound?, want: KasusDebugWant) -> FehlerPick? {
        let words = item.playable.sentences.flatMap(\.words)
        if partial == nil {
            switch want {
            case .right: return words.first(where: item.isPlanted).map { .word($0.id) }
            case .wrong: return words.first(where: { !item.isInPhrase($0) && $0.role.targetIndex == nil }).map { .word($0.id) }
            case .slip:  return nil
            }
        }
        switch want {
        case .right: return .form(item.answer)
        case .wrong: return .form(item.wrong)
        case .slip:  return item.options.first(where: item.isGenderSlip).map { .form($0) }
        }
    }

    // MARK: Views

    func hero(_ ctx: KasusDrillContext<Self>) -> some View {
        FehlerHero(item: ctx.item, phase: phase(ctx), showEnglish: ctx.showEnglish) { id in
            ctx.pick(.word(id))
        }
    }

    /// Where the step is: looking for the word, found it (right or not), or fixed.
    private func phase(_ ctx: KasusDrillContext<Self>) -> FehlerHero.Phase {
        if let answer = ctx.answer, case .form(let form)? = ctx.picked {
            return .fixed(form: form, right: answer.outcome == .right || answer.outcome == .wrongPick)
        }
        if let found = ctx.partial { return .found(right: found.right) }
        return .finding
    }

    func panel(_ ctx: KasusDrillContext<Self>) -> some View {
        let item = ctx.item
        return Group {
            if case .finding = phase(ctx) {
                Color.clear.frame(height: 1)
            } else {
                KasusOptionGrid(options: item.options, answer: item.answer, kasus: item.kasus, picked: pickedForm(ctx),
                                columns: min(3, item.options.count), rowHeight: 58) { form in
                    ctx.pick(.form(form))
                }
            }
        }
        .id(item.id)
    }

    private func pickedForm(_ ctx: KasusDrillContext<Self>) -> String? {
        if case .form(let form)? = ctx.picked { return form }
        return nil
    }

    func hint(_ ctx: KasusDrillContext<Self>) -> String {
        if case .finding = phase(ctx) { return "Tap the word with the wrong ending." }
        return "Now tap the form that belongs there."
    }

    func scoreLine(_ round: KasusDrillRound<Self>) -> String { "found and fixed on the first try" }

    func summaryNote(_ round: KasusDrillRound<Self>) -> String? {
        "A fix after a missed find is practice: only a mistake you found yourself moves the coach."
    }
}

/// The numbered sentence with the planted mistake in it. Every word is a button while the
/// learner is looking; once found (or missed), the planted word is ringed; once fixed, it shows
/// the fix in its case colour with the planted form struck through.
struct FehlerHero: View {
    enum Phase: Hashable {
        case finding
        case found(right: Bool)
        case fixed(form: String, right: Bool)
    }

    let item: FehlerQuestion
    let phase: Phase
    @Binding var showEnglish: Bool
    let onTapWord: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(item.playable.story.level)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                KasusEnglishToggle(isOn: $showEnglish)
            }
            KasusSentenceList(sentences: item.playable.sentences, font: .title3) { word in
                chip(word)
            }
            if showEnglish {
                ForEach(Array(item.playable.story.paragraphs.indices), id: \.self) { paragraph in
                    Text(kasusRich: item.playable.englishLine(paragraph: paragraph, highlighting: [:]))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chip(_ word: KasusWord) -> some View {
        let planted = item.isPlanted(word)
        let style = chipStyle(planted: planted)
        let text = plantedText(word, planted: planted)
        if case .finding = phase {
            KasusChip(style: style, action: { onTapWord(word.id) }) { text }
        } else {
            KasusChip(style: style) { text }
        }
    }

    /// Every word outlined while looking; the planted one ringed once found (orange) or missed
    /// (red); washed in its case colour with a check or a cross once fixed.
    private func chipStyle(planted: Bool) -> KasusChipStyle {
        var style = KasusChipStyle()
        switch phase {
        case .finding:
            style.outline = .secondary.opacity(0.35)
        case .found(let right):
            if planted {
                style.selected = true
                style.wash = (right ? Color.orange : Color.red).opacity(0.18)
            }
        case .fixed(_, let right):
            if planted {
                style.selected = true
                style.wash = item.kasus.color.opacity(0.18)
                style.badge = right ? .check(item.kasus.color) : .cross
            }
        }
        return style
    }

    /// The planted word shows the wrong form until the fix, then the fix with the wrong form
    /// struck through in front of it; every other word is itself.
    private func plantedText(_ word: KasusWord, planted: Bool) -> Text {
        guard planted else { return KasusWordText.text(word) }
        var out = AttributedString(word.leading)
        var wrong = AttributedString(item.wrong)
        if case .fixed = phase {
            wrong.strikethroughStyle = Text.LineStyle(pattern: .solid, color: .secondary)
            wrong.foregroundColor = .secondary
            var fix = AttributedString(item.answer)
            fix.foregroundColor = item.kasus.color
            fix.inlinePresentationIntent = .stronglyEmphasized
            out += wrong + AttributedString(" ") + fix
        } else {
            out += wrong
        }
        out += AttributedString(word.trailing)
        return Text(out)
    }
}

#Preview("Finde den Fehler · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            GrammarDrillShell(session: GrammarDrillSession(kind: .fehler, topic: .kasus(.dativ)),
                              make: FehlerModule.init(session:), onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
    .inMemoryModelContainer(for: [LearnerProfile.self, StudyDay.self])
}
