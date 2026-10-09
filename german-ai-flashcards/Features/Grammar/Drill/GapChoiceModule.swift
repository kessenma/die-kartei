//
//  GapChoiceModule.swift
//  german-ai-flashcards
//
//  The gap-choice drills on the shell: a bundled sentence with a gap, the pronoun as buttons under
//  it (Akkusativ oder Dativ?, Die richtige Person) or as two chips in the sentence itself (the
//  worksheet's „dich / dir“ in brackets). The items come from `GapChoiceBank`, gated at load; the
//  explanation is derived from the item's facts (`ReflexivExplanation`). An item with several
//  gaps (the double gap, the Pronomen-Brücke) plays as one multi-tap step, a gap per tap.
//
//  Two chips are practice, not evidence: an inline item's answer is recorded as scaffolded, so
//  the coach only hears the button rounds (Kyle's call).
//

import SwiftUI

/// The picks made on a multi-gap item so far.
struct GapWalk: Hashable {
    var filled: [String]
}

struct GapChoiceModule: KasusDrillModule {
    typealias Item = GapChoiceItem
    typealias Pick = String
    typealias Partial = GapWalk

    let kind: KasusDrillKind
    let config: GapConfig

    init(session: GrammarDrillSession) {
        kind = session.kind
        if case .gap(let config) = session.variant {
            self.config = config
        } else {
            self.config = GapConfig(focus: session.kind == .reflexPerson ? .person : .case, count: session.kind.meta.roundSize)
        }
    }

    // MARK: Items and grading

    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [GapChoiceItem]? {
        var pool = GapChoiceBank.bundled.items(topic: session.topic.key, focus: config.focus)
        guard pool.count >= GapChoiceFocus.minimumItems else { return nil }
        pool.shuffle(using: &rng)
        var round: [GapChoiceItem]
        if config.focus == .case {
            // Both cases, constructively: at least a third of the round each, never the reshuffle
            // that hopes for it.
            let count = min(config.count, pool.count)
            let quota = Int((Double(count) / 3).rounded(.up))
            var akk = pool.filter { $0.kasus == .akkusativ }
            var dat = pool.filter { $0.kasus == .dativ }
            round = Array(akk.prefix(quota)) + Array(dat.prefix(quota))
            akk.removeFirst(min(quota, akk.count))
            dat.removeFirst(min(quota, dat.count))
            let rest = (akk + dat).shuffled(using: &rng)
            round += rest.prefix(max(0, count - round.count))
            round.shuffle(using: &rng)
        } else {
            round = Array(pool.prefix(config.count))
        }
        #if DEBUG
        if session.prefill != nil, let id = UserDefaults.standard.string(forKey: "kasus.debugItem") {
            if let at = round.firstIndex(where: { $0.id == id }) {
                round.insert(round.remove(at: at), at: 0)
            } else if let extra = GapChoiceBank.bundled.item(id: id) {
                round[0] = extra
            }
        }
        #endif
        return round.isEmpty ? nil : round
    }

    func answer(_ pick: String, for item: GapChoiceItem, step: Int, partial: inout GapWalk?) -> KasusDrillOutcome<GapWalk> {
        let index = partial?.filled.count ?? 0
        guard item.gaps.indices.contains(index) else { return .ignored }
        let gap = item.gaps[index]
        let right = pick.lowercased() == gap.answer.lowercased()
        let filled = (partial?.filled ?? []) + [pick]
        if filled.count < item.gaps.count {
            let walk = GapWalk(filled: filled)
            partial = walk
            return .partial(walk, line: right ? "„\(pick)“ ✓ · next gap" : "„\(pick)“ ✗ · it's „\(gap.answer)“ · next gap", right: right)
        }
        partial = nil
        let allRight = zip(filled, item.gaps).allSatisfy { $0.lowercased() == $1.answer.lowercased() }
        let firstGap = item.gaps[0]
        let firstPick = filled[0]
        let outcome: KasusItemOutcome
        if allRight {
            outcome = .right
        } else if ReflexivPronoun.otherCase(of: firstGap.answer)?.lowercased() == firstPick.lowercased() {
            outcome = .caseMiss
        } else {
            outcome = .wrongPick
        }
        let explanation = ReflexivExplanation.feedback(item, pick: firstPick)
        let record = KasusRoundItem(sentence: item.filled, phraseStart: item.answerStart(of: 0), phrase: firstGap.answer,
                                    answer: firstGap.answer, pick: filled.joined(separator: " · "), kasus: item.kasus, genus: .der,
                                    outcome: outcome, explanation: explanation, hasNounGender: false)
        let result = KasusItemResult(kasus: item.kasus, genus: .der, firstTry: allRight, record: record,
                                     scaffolded: item.presentation == .inline)
        return .graded(KasusGradedAnswer(outcome: outcome, kasus: item.kasus, explanation: explanation, result: result))
    }

    /// Wrong: the same person's other case where the options have it (a case miss), else another
    /// person. There is no gender slip on a pronoun.
    func debugPick(for item: GapChoiceItem, partial: GapWalk?, want: KasusDebugWant) -> String? {
        let index = partial?.filled.count ?? 0
        guard item.gaps.indices.contains(index) else { return nil }
        let gap = item.gaps[index]
        switch want {
        case .right: return gap.answer
        case .slip:  return nil
        case .wrong:
            if let other = ReflexivPronoun.otherCase(of: gap.answer), gap.options.contains(where: { $0.lowercased() == other }) { return other }
            return gap.options.first { $0.lowercased() != gap.answer.lowercased() }
        }
    }

    // MARK: Views

    func hero(_ ctx: KasusDrillContext<Self>) -> some View {
        GapChoiceHero(item: ctx.item, filled: ctx.partial?.filled ?? [], picked: ctx.picked,
                      locked: ctx.isShowingFeedback, showEnglish: ctx.showEnglish) { option in
            ctx.pick(option)
        }
    }

    func panel(_ ctx: KasusDrillContext<Self>) -> some View {
        let item = ctx.item
        let index = min(ctx.partial?.filled.count ?? 0, item.gaps.count - 1)
        let gap = item.gaps[index]
        return Group {
            if item.presentation == .buttons {
                KasusOptionGrid(options: gap.options, answer: gap.answer, kasus: gap.kasus ?? item.kasus, picked: ctx.picked,
                                columns: gap.options.count == 4 ? 2 : min(3, gap.options.count), rowHeight: 58) { option in
                    ctx.pick(option)
                }
            } else {
                // The chips are in the sentence; nothing under it.
                Color.clear.frame(height: 1)
            }
        }
        .id("\(item.id)-\(index)")
    }

    func hint(_ ctx: KasusDrillContext<Self>) -> String {
        if ctx.item.presentation == .inline { return "Tap the pronoun in the sentence." }
        switch config.focus {
        case .person: return "Tap the pronoun for „\(ctx.item.subject.text)“."
        default:      return "Tap the pronoun that fits: the person, and the case."
        }
    }

    func summaryNote(_ round: KasusDrillRound<Self>) -> String? {
        round.items.contains { $0.presentation == .inline }
            ? "The two-chip sentences are practice; only the button rounds move the coach's reflexive-verbs skill."
            : nil
    }
}

/// The verb, then the sentence with its gap, large. An inline item shows its two forms as chips
/// in the sentence until one is tapped; after the pick every item shows the answer in its case
/// colour, a wrong pick struck through in front of it.
struct GapChoiceHero: View {
    let item: GapChoiceItem
    /// Earlier gaps' picks on a multi-gap item.
    let filled: [String]
    /// This gap's pick, until Weiter.
    let picked: String?
    let locked: Bool
    @Binding var showEnglish: Bool
    let onPick: (String) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 34

    private var gapIndex: Int { min(filled.count, item.gaps.count - 1) }
    private var heroFont: Font { .system(size: sizeClass == .regular ? heroSize * 1.4 : heroSize, weight: .semibold) }

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 6) {
                Text("Verb:")
                    .foregroundStyle(.secondary)
                Text(ReflexivVerb.named(item.verb.lemma)?.infinitive ?? "sich \(item.verb.lemma)")
                    .fontWeight(.medium)
            }
            .font(.headline)
            if item.presentation == .inline, picked == nil, !locked {
                inlineSentence
            } else {
                Self.sentence(item, filled: filled, picked: picked)
                    .font(heroFont)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showEnglish {
                Text(item.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            KasusEnglishToggle(isOn: $showEnglish)
        }
        .padding(.horizontal, 4)
    }

    /// The sentence as words, the gap as its two forms, tappable.
    private var inlineSentence: some View {
        let gap = item.gaps[gapIndex]
        let before = item.sentence(filling: { $0 < gapIndex ? filled[$0] : $0 == gapIndex ? "\u{1F}" : item.gaps[$0].answer })
        let halves = before.components(separatedBy: "\u{1F}")
        // Plain words carry their own gap; the chips bring theirs.
        return KasusWordFlow(spacing: 9, lineSpacing: 10) {
            ForEach(Array(words(halves.first ?? "").enumerated()), id: \.offset) { _, word in
                Text(word).font(heroFont).padding(.vertical, 6)
            }
            ForEach(Array(gap.options.enumerated()), id: \.offset) { i, option in
                if i > 0 { Text("/").font(heroFont).foregroundStyle(.secondary).padding(.vertical, 6) }
                KasusChip(style: KasusChipStyle(outline: .secondary, selected: false), action: { onPick(option) }) {
                    Text(option).font(heroFont)
                }
                .accessibilityLabel("Choose \(option)")
            }
            ForEach(Array(words(halves.count > 1 ? halves[1] : "").enumerated()), id: \.offset) { _, word in
                Text(word).font(heroFont).padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func words(_ text: String) -> [String] {
        text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /// The sentence with its gap: a blank, or the answer in its case colour with a wrong pick
    /// struck through in front of it.
    static func sentence(_ item: GapChoiceItem, filled: [String], picked: String?) -> Text {
        let current = min(filled.count, item.gaps.count - 1)
        var out = AttributedString()
        let ns = item.sentence as NSString
        var cursor = 0
        for match in GapChoiceItem.placeholder.matches(in: item.sentence, range: NSRange(location: 0, length: ns.length)) {
            out += AttributedString(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            let index = (Int(ns.substring(with: match.range(at: 1))) ?? 1) - 1
            let gap = item.gaps.indices.contains(index) ? item.gaps[index] : item.gaps[0]
            let pick: String? = index < filled.count ? filled[index] : index == current ? picked : nil
            if let pick {
                var answer = AttributedString(gap.answer)
                answer.foregroundColor = (gap.kasus ?? item.kasus).color
                answer.inlinePresentationIntent = .stronglyEmphasized
                if pick.lowercased() != gap.answer.lowercased() {
                    var wrong = AttributedString(pick)
                    wrong.strikethroughStyle = .single
                    wrong.foregroundColor = .secondary
                    out += wrong + AttributedString(" ")
                }
                out += answer
            } else {
                var blank = AttributedString("_____")
                blank.foregroundColor = .secondary
                out += blank
            }
            cursor = match.range.location + match.range.length
        }
        out += AttributedString(ns.substring(from: cursor))
        return Text(out)
    }
}

// MARK: - Previews

#Preview("Akkusativ oder Dativ? · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            GrammarDrillShell(session: GrammarDrillSession(kind: .reflexCase, topic: .reflexiv),
                              make: GapChoiceModule.init(session:), onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
    .inMemoryModelContainer(for: [LearnerProfile.self, StudyDay.self])
}

#Preview("Die richtige Person · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            GrammarDrillShell(session: GrammarDrillSession(kind: .reflexPerson, topic: .reflexiv),
                              make: GapChoiceModule.init(session:), onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
    .inMemoryModelContainer(for: [LearnerProfile.self, StudyDay.self])
}
