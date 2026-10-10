//
//  BridgeModule.swift
//  german-ai-flashcards
//
//  Die Pronomen-Brücke on the shell: one frame, three taps (`BridgeQuestion`): the English
//  pronoun, the German pronoun, the article. A multi-tap step whose scratch state is the picks
//  so far; the third tap grades the whole chain. Recognition of a job the learner already feels
//  in English, so it never moves the coach.
//

import SwiftUI

/// The stages answered so far on one frame.
struct BridgeWalk: Hashable {
    var filled: [String]
}

struct BridgeModule: KasusDrillModule {
    typealias Item = BridgeQuestion
    typealias Pick = String
    typealias Partial = BridgeWalk

    let unit: KasusUnit

    var kind: KasusDrillKind { .bridge }

    init(session: GrammarDrillSession) {
        unit = session.topic.unit ?? .akkusativ
    }

    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [BridgeQuestion]? {
        guard BridgeQuestion.coversCases(unit.casesInPlay) else { return nil }
        let round = BridgeQuestion.round(cases: unit.casesInPlay, emphasis: unit.focusCase, count: kind.meta.roundSize, rng: &rng)
        return round.isEmpty ? nil : round
    }

    func answer(_ pick: String, for item: BridgeQuestion, step: Int, partial: inout BridgeWalk?) -> KasusDrillOutcome<BridgeWalk> {
        let stage = partial?.filled.count ?? 0
        guard item.answers.indices.contains(stage) else { return .ignored }
        let answer = item.answers[stage]
        let right = pick.lowercased() == answer.lowercased()
        let filled = (partial?.filled ?? []) + [pick]
        if stage < 2 {
            let walk = BridgeWalk(filled: filled)
            partial = walk
            let next = stage == 0 ? "Now the German pronoun." : "Now the article."
            return .partial(walk, line: (right ? "„*\(pick)*“ ✓ · " : "„*\(pick)*“ ✗ · it's „*\(answer)*“ · ") + next, right: right)
        }
        partial = nil
        let allRight = zip(filled, item.answers).allSatisfy { $0.lowercased() == $1.lowercased() }
        let outcome: KasusItemOutcome = allRight ? .right : .caseMiss
        let (before, after) = item.articleParts
        let record = KasusRoundItem(sentence: before + item.articleAnswer + after, phraseStart: before.utf16.count,
                                    phrase: "\(item.articleAnswer) \(item.nounForm)", answer: item.articleAnswer,
                                    pick: filled.joined(separator: " · "), kasus: item.kasus, genus: item.gender,
                                    outcome: outcome, explanation: item.explanation)
        let result = KasusItemResult(kasus: item.kasus, genus: item.gender, firstTry: allRight, record: record)
        return .graded(KasusGradedAnswer(outcome: outcome, kasus: item.kasus, explanation: item.explanation,
                                         cardRight: right && !allRight ? true : nil, result: result))
    }

    func debugPick(for item: BridgeQuestion, partial: BridgeWalk?, want: KasusDebugWant) -> String? {
        let stage = partial?.filled.count ?? 0
        guard item.answers.indices.contains(stage) else { return nil }
        switch want {
        case .right: return item.answers[stage]
        case .wrong: return item.options[stage].first { $0.lowercased() != item.answers[stage].lowercased() }
        case .slip:  return nil
        }
    }

    // MARK: Views

    func hero(_ ctx: KasusDrillContext<Self>) -> some View {
        BridgeHero(item: ctx.item, picks: Self.picks(ctx), graded: ctx.answer != nil)
    }

    /// The stages answered so far: the walk's, or once graded the record's.
    static func picks(_ ctx: KasusDrillContext<Self>) -> [String] {
        if ctx.answer != nil, let pick = ctx.answer?.result.record?.pick { return pick.components(separatedBy: " · ") }
        return ctx.partial?.filled ?? []
    }

    func panel(_ ctx: KasusDrillContext<Self>) -> some View {
        let item = ctx.item
        let stage = min(ctx.partial?.filled.count ?? (ctx.answer != nil ? 2 : 0), 2)
        let options = item.options[stage]
        return KasusOptionGrid(options: options, answer: item.answers[stage], kasus: item.kasus, picked: ctx.picked,
                               columns: min(3, options.count), rowHeight: 58) { option in
            ctx.pick(option)
        }
        .id("\(item.id)-\(stage)")
    }

    func hint(_ ctx: KasusDrillContext<Self>) -> String {
        switch ctx.partial?.filled.count ?? 0 {
        case 0:  return "English first: which pronoun fits?"
        case 1:  return "Now the German pronoun."
        default: return "Now the article on the noun."
        }
    }

    func scoreLine(_ round: KasusDrillRound<Self>) -> String { "chains right all the way through" }
}

/// The three stages, one under the other, each with its blank until answered: the English
/// sentence, the German one with a pronoun, the German one with the noun.
struct BridgeHero: View {
    let item: BridgeQuestion
    /// The stages answered so far (every stage once graded).
    let picks: [String]
    /// The whole chain is graded: every stage shows its answer.
    let graded: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .title) private var heroSize: CGFloat = 26

    private var current: Int { min(picks.count, 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                GenderTag(gender: item.gender)
                Text(item.isPlural ? "Plural of \(item.noun.singular)" : item.noun.singular)
                    .font(.headline.weight(.medium))
            }
            ForEach(0..<3, id: \.self) { stage in
                if stage <= current || graded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BridgeQuestion.stageLabels[stage])
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        line(stage)
                            .font(.system(size: sizeClass == .regular ? heroSize * 1.3 : heroSize, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.3), value: current)
    }

    /// A stage's sentence: a blank, or the answer in the case colour with a wrong pick struck
    /// through in front of it.
    private func line(_ stage: Int) -> Text {
        let sentence = item.sentences[stage]
        let pieces = sentence.components(separatedBy: "___")
        let before = pieces.first ?? "", after = pieces.dropFirst().first ?? ""
        let pick: String? = stage < picks.count ? picks[stage] : nil
        var blank: AttributedString
        if let pick {
            blank = AttributedString(item.answers[stage])
            blank.foregroundColor = item.kasus.color
            blank.inlinePresentationIntent = .stronglyEmphasized
            if pick.lowercased() != item.answers[stage].lowercased() {
                var wrong = AttributedString(pick)
                wrong.strikethroughStyle = .single
                wrong.foregroundColor = .secondary
                blank = wrong + AttributedString(" ") + blank
            }
        } else {
            blank = AttributedString("_____")
            blank.foregroundColor = .secondary
        }
        return Text(AttributedString(before) + blank + AttributedString(after))
    }
}

#Preview("Pronomen-Brücke · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            GrammarDrillShell(session: GrammarDrillSession(kind: .bridge, topic: .kasus(.dativ)),
                              make: BridgeModule.init(session:), onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
    .inMemoryModelContainer(for: [LearnerProfile.self, StudyDay.self])
}
