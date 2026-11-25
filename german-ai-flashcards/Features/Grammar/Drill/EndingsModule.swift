//
//  EndingsModule.swift
//  german-ai-flashcards
//
//  The endings drills on the shell: the Schnellrunde (whole articles as buttons), Bau das Wort
//  (ending labels, the word built in 3D on the stage), and the variants the same engine plays
//  by configuration (`EndingsConfig`: a frame family, a pair of forms, a timer). One question is
//  an `EndingsQuestion` (Models/EndingsQuestion.swift); the pick is the whole form, which is how
//  grading, slips, feedback and the round history stay the Schnellrunde's whatever the buttons
//  show.
//

import SwiftUI

struct EndingsModule: KasusDrillModule {
    typealias Item = EndingsQuestion
    typealias Pick = String
    typealias Partial = Never

    let kind: KasusDrillKind
    let config: EndingsConfig
    let session: GrammarDrillSession

    init(session: GrammarDrillSession) {
        self.session = session
        kind = session.kind
        if case .endings(let config) = session.variant {
            self.config = config
        } else {
            self.config = EndingsConfig(cases: session.topic.casesInPlay, emphasis: session.topic.emphasis)
        }
    }

    var isBuilding: Bool { config.style == .ending }
    var isTimed: Bool { config.timeLimit != nil }
    /// A confusion pair: two forms as buttons, nothing else.
    var isPair: Bool { config.options != nil }

    var defersFeedback: Bool { config.deferredFeedback }

    // MARK: Items and grading

    func compose(_ session: GrammarDrillSession, rng: inout KasusSeededRandom) -> [EndingsQuestion]? {
        guard EndingsQuestion.coversCases(config.cases, family: config.family) else { return nil }
        let round = EndingsQuestion.round(cases: config.cases, emphasis: config.emphasis, count: config.count,
                                          family: config.family, genders: config.genders,
                                          determiners: config.determiners, options: config.options, rng: &rng)
        return round.isEmpty ? nil : round
    }

    func answer(_ pick: String, for q: EndingsQuestion, step: Int, partial: inout Never?) -> KasusDrillOutcome<Never> {
        let isAnswer = pick == q.answer
        let slip = !isAnswer && q.isGenderSlip(pick)
        let outcome: KasusItemOutcome = isAnswer ? .right : slip ? .genderSlip : .caseMiss
        let result = KasusItemResult(kasus: q.kasus, genus: q.gender, firstTry: isAnswer, slip: slip,
                                     record: q.roundItem(pick: pick))
        return .graded(KasusGradedAnswer(outcome: outcome, kasus: q.kasus, explanation: q.feedback(pick: pick), result: result))
    }

    /// A wrong option: a gender slip, or a case miss.
    func debugPick(for q: EndingsQuestion, partial: Never?, want: KasusDebugWant) -> String? {
        switch want {
        case .right: q.answer
        case .wrong: q.options.first { $0 != q.answer && !q.isGenderSlip($0) }
        case .slip:  q.options.first { $0 != q.answer && q.isGenderSlip($0) }
        }
    }

    // MARK: Views

    /// The word in 3D: an open slot on the stem until the pick, then the answer snapping in (a
    /// wrong ending bounces off first). A hero in Bau das Wort, a dimmed strip in the Schnellrunde.
    /// The Blitzrunde has the clock there instead.
    func stage(_ ctx: KasusDrillContext<Self>) -> some View {
        Group {
            if let limit = config.timeLimit {
                BlitzTimerStage(seconds: limit, answered: ctx.round.answers.count, right: ctx.round.firstTryCount,
                                best: ctx.session.personalBest, onExpire: ctx.finish)
            } else {
                EndingBlocksScene(state: blocks(ctx))
                    .frame(height: stageHeight(ctx.playHeight))
                    .frame(maxWidth: 640)
                    .opacity(ctx.picked == nil && !isBuilding ? 0.55 : 1)
            }
        }
    }

    private func blocks(_ ctx: KasusDrillContext<Self>) -> EndingBlocksState {
        let q = ctx.item
        guard let picked = ctx.picked else { return .open(stem: q.stem, genus: q.gender) }
        let rejected = picked == q.answer ? nil : q.ending(of: picked)
        return .built(q.answerParts, kasus: q.kasus, genus: q.gender, rejected: rejected)
    }

    /// The stage takes a slice of the play area: a hero in Bau das Wort, a strip in the
    /// Schnellrunde.
    private func stageHeight(_ playHeight: CGFloat) -> CGFloat {
        guard playHeight > 0 else { return isBuilding ? 150 : 96 }
        return isBuilding ? min(210, max(110, playHeight * 0.24)) : min(140, max(80, playHeight * 0.15))
    }

    func hero(_ ctx: KasusDrillContext<Self>) -> some View {
        EndingsHero(question: ctx.item, picked: ctx.picked, isBuilding: isBuilding)
    }

    func panel(_ ctx: KasusDrillContext<Self>) -> some View {
        let q = ctx.item
        return Group {
            if isBuilding {
                KasusOptionGrid(options: q.endingLabels, answer: KasusForms.endingLabel(q.answerParts.ending),
                                kasus: q.kasus, picked: ctx.picked.map { KasusForms.endingLabel(q.ending(of: $0)) },
                                columns: 3, rowHeight: 58) { label in
                    ctx.pick(q.form(endingLabel: label))
                }
            } else {
                KasusOptionGrid(options: q.options, answer: q.answer, kasus: q.kasus, picked: ctx.picked,
                                columns: 3, rowHeight: 58) { option in
                    ctx.pick(option)
                }
            }
        }
        // A fresh grid per question, so the shake and the pop start fresh.
        .id(q.id)
    }

    func hint(_ ctx: KasusDrillContext<Self>) -> String {
        if isTimed { return "Fast: tap the article, and the next sentence comes straight up." }
        if isPair { return "Tap the form that fits." }
        return isBuilding ? "Tap the ending that fits." : "Tap the article that fits."
    }

    func missText(_ item: EndingsQuestion, _ answer: KasusDrillAnswer<String>) -> Text {
        EndingsHero.sentence(item, picked: answer.pick, isBuilding: isBuilding)
    }

    func scoreLine(_ round: KasusDrillRound<Self>) -> String {
        if let limit = config.timeLimit { return "right in \(limit) seconds" }
        return "right on the first try"
    }

    func summaryNote(_ round: KasusDrillRound<Self>) -> String? {
        if isTimed {
            let best = session.personalBest.map { " Best so far: \($0)." } ?? ""
            return "A speed round: it counts for your streak and your time, never for the coach." + best
        }
        if isPair { return "Two forms are practice, not evidence: this round never moves the coach." }
        return nil
    }
}

/// The Blitzrunde's clock above the sentence: the seconds left, how many were answered, the
/// personal best. When it reaches zero the round ends over what was answered.
struct BlitzTimerStage: View {
    let seconds: Int
    let answered: Int
    let right: Int
    let best: Int?
    let onExpire: () -> Void

    @State private var start = Date()
    @State private var expired = false

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(start))
            let remaining = max(0, seconds - elapsed)
            HStack(spacing: 14) {
                Label(String(format: "%d:%02d", remaining / 60, remaining % 60), systemImage: "bolt.fill")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(remaining <= 10 ? .red : .primary)
                    .contentTransition(.numericText())
                Spacer()
                Text("\(right) / \(answered)")
                    .font(.headline)
                    .monospacedDigit()
                if let best {
                    Text("Best \(best)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: 640)
            .onChange(of: remaining) { _, left in
                guard left == 0, !expired else { return }
                expired = true
                onExpire()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The question: which noun the blank belongs to, then the sentence with its gap, large.
struct EndingsHero: View {
    let question: EndingsQuestion
    let picked: String?
    let isBuilding: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The sentence's size: Large Title on a phone, and it follows Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 22) {
            nounHeader
                .font(.headline)
            Self.sentence(question, picked: picked, isBuilding: isBuilding)
                // Bigger on an iPad, where Large Title looks lost in the middle of the screen.
                .font(.system(size: sizeClass == .regular ? heroSize * 1.4 : heroSize, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    /// Which noun the blank belongs to. A Nominativ blank shows the gender tag instead of
    /// „der Hund“, since the dictionary form *is* the Nominativ answer.
    @ViewBuilder
    private var nounHeader: some View {
        let q = question
        if q.kasus == .nominativ {
            HStack(spacing: 8) {
                GenderTag(gender: q.gender)
                Text(q.isPlural ? "Plural of \(q.noun.singular)" : q.noun.singular)
                    .fontWeight(.medium)
            }
        } else {
            HStack(spacing: 6) {
                Text(q.isPlural ? "Plural of" : "Noun:")
                    .foregroundStyle(.secondary)
                Text.gendered(q.noun.singular, article: q.noun.gender.article)
                    .fontWeight(.medium)
            }
        }
    }

    /// The sentence with its gap. Answered: the answer in its gender colour, bold, and a wrong
    /// pick struck through in grey in front of it.
    static func sentence(_ q: EndingsQuestion, picked: String?, isBuilding: Bool) -> Text {
        let (before, after) = q.parts
        var blank: AttributedString
        if let picked {
            blank = AttributedString(q.answer)
            blank.foregroundColor = q.gender.color
            blank.inlinePresentationIntent = .stronglyEmphasized
            if picked != q.answer {
                var wrong = AttributedString(picked)
                wrong.strikethroughStyle = .single
                wrong.foregroundColor = .secondary
                blank = wrong + AttributedString(" ") + blank
            }
        } else if isBuilding {
            var gap = AttributedString("___")
            gap.foregroundColor = .secondary
            blank = AttributedString(q.stem) + gap
        } else {
            blank = AttributedString("_____")
            blank.foregroundColor = .secondary
        }
        return Text(AttributedString(before) + blank + AttributedString(after))
    }
}

// MARK: - Previews

#Preview("Schnellrunde · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            GrammarDrillShell(session: GrammarDrillSession(kind: .quick, topic: .kasus(.genitiv)),
                              make: EndingsModule.init(session:), onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
    .inMemoryModelContainer(for: [LearnerProfile.self, StudyDay.self])
}

#Preview("Bau das Wort · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            GrammarDrillShell(session: GrammarDrillSession(kind: .build, topic: .kasus(.dativ)),
                              make: EndingsModule.init(session:), onComplete: { _ in }, onDismiss: {})
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
    .inMemoryModelContainer(for: [LearnerProfile.self, StudyDay.self])
}
