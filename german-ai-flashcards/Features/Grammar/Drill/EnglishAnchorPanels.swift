//
//  EnglishAnchorPanels.swift
//  german-ai-flashcards
//
//  „Englisch & Fälle“: the sentence as the learner sees it, and the five question buttons.
//
//    EnglishAnchorHero     the English line with one span ringed, the German twin beneath it
//    EnglishSpanLine       a line of word chips where one span wears the ring (the only new
//                          mechanic here: `KasusRichText` can colour a phrase but not ring one)
//    EnglishQuestionGrid   Wer · Wen · Wem · Wessen over two columns, Keine Frage on its own row
//
//  The ring is ink, never a case colour: the whole point is that the case is what the learner is
//  about to name. A colour appears only in the reveal — on the German phrase, on the English twin,
//  and on the button that was right.
//
//  The buttons' looks are the app's answer-button vocabulary (`KasusOptionButton.Look`), so right,
//  wrong and revealed read the same here as in every other grammar round.
//

import SwiftUI

// MARK: - The sentence

struct EnglishAnchorHero: View {
    let item: EnglishAnchorItem
    /// The other spans of this sentence the round will ask: ringed dashed, „still to come“.
    let siblings: [String]
    /// The grade, once the pick is in.
    let answer: KasusGradedAnswer?
    /// The cases already revealed on this sentence, by target index: an answered phrase keeps its
    /// colour, which is the elimination scaffold Leicht is allowed to give.
    var given: [Int: GrammarCase] = [:]
    let help: KasusHelp
    /// „Satz 2 · Fall 1 von 3“, where the round asks a whole sentence.
    let counter: String?

    @Environment(\.appTheme) private var appTheme

    private var stage: EnglishStage { item.stage }
    private var revealed: Bool { answer != nil }
    private var playable: KasusConceptPlayable { item.playable }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if stage.showsEnglish {
                lineLabel("Englisch")
                EnglishSpanLine(line: englishLine, span: item.english,
                                siblings: help.ringsEveryPhrase ? siblings : [],
                                tint: revealed ? item.kasus?.color : nil)
            }
            if stage.showsGerman || revealed {
                if stage.showsEnglish {
                    Divider().overlay(appTheme.cardBorderColor)
                }
                lineLabel("Deutsch")
                KasusSentenceList(sentences: playable.sentences, font: .title3) { word in
                    germanChip(word)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack {
            Text(counter ?? playable.story.level)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(stage.germanLabel)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
    }

    private func lineLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
    }

    /// The paragraph the asked span sits in, in English.
    private var englishLine: String {
        guard playable.story.paragraphs.indices.contains(item.paragraph) else { return "" }
        return playable.story.paragraphs[item.paragraph].en
    }

    /// The German line rings the same phrase, and takes its case colour once answered.
    private func germanChip(_ word: KasusWord) -> some View {
        var style = KasusChipStyle()
        if let index = word.role.targetIndex {
            if let kasus = given[index] {
                style.wash = kasus.color.opacity(0.18)
            }
            if index == item.targetIndex {
                style.selected = true
                if let answer {
                    style.wash = answer.kasus.color.opacity(0.18)
                    if let target = item.target, target.determinerRange == word.paragraphRange {
                        style.badge = answer.isRight ? .check(answer.kasus.color) : .cross
                    }
                }
            }
        }
        // Once answered, the preposition that decided a „Keine Frage“ phrase is underlined.
        if let answer, let target = item.target, let trigger = target.triggerRange,
           item.question == .keine, NSIntersectionRange(trigger, word.paragraphRange).length > 0 {
            style.underline = answer.kasus.color
        }
        return KasusChip(style: style) {
            KasusWordText.text(word)
        }
    }
}

/// One line of English with a span ringed. The span is one chip, so a phrase like „the friend's“
/// or one that carries a comma stays whole and wears a single ring.
struct EnglishSpanLine: View {
    let line: String
    let span: String
    /// Spans this sentence will ask later: a dashed ring, no colour.
    var siblings: [String] = []
    /// The span's case colour, once the answer is in.
    var tint: Color? = nil

    var body: some View {
        KasusWordFlow {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                if token.kind == .plain, token.isPunctuation {
                    // A lone full stop after a ringed span: no chip padding, or it floats away
                    // from the phrase it belongs to.
                    Text(token.text)
                        .font(.title3)
                } else {
                    KasusChip(style: style(for: token)) {
                        Text(token.text)
                            .font(.title3.weight(token.kind == .asked ? .semibold : .regular))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private enum Kind { case plain, asked, later }
    private struct Token {
        let text: String
        let kind: Kind
        var isPunctuation: Bool { text.allSatisfy { ".,;:!?".contains($0) } }
    }

    /// The line split into the asked span, the spans still to come, and the words around them.
    private var tokens: [Token] {
        var pieces: [Token] = [Token(text: line, kind: .plain)]
        pieces = split(pieces, on: span, as: .asked)
        for sibling in siblings where sibling != span {
            pieces = split(pieces, on: sibling, as: .later)
        }
        return pieces.flatMap { piece -> [Token] in
            guard piece.kind == .plain else { return [piece] }
            return piece.text.split(separator: " ").map { Token(text: String($0), kind: .plain) }
        }
    }

    private func split(_ pieces: [Token], on phrase: String, as kind: Kind) -> [Token] {
        guard !phrase.isEmpty else { return pieces }
        return pieces.flatMap { piece -> [Token] in
            guard piece.kind == .plain, let range = piece.text.range(of: phrase) else { return [piece] }
            return [Token(text: String(piece.text[piece.text.startIndex..<range.lowerBound]), kind: .plain),
                    Token(text: phrase, kind: kind),
                    Token(text: String(piece.text[range.upperBound...]), kind: .plain)]
                .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    private func style(for token: Token) -> KasusChipStyle {
        var style = KasusChipStyle()
        switch token.kind {
        case .plain:
            break
        case .asked:
            style.selected = true
            if let tint {
                style.wash = tint.opacity(0.18)
                style.foreground = tint
            }
        case .later:
            style.outline = .secondary.opacity(0.5)
            style.dashed = true
        }
        return style
    }
}

// MARK: - The questions

struct EnglishQuestionGrid: View {
    let questions: [KasusQuestion]
    /// The question the span answers.
    let answer: KasusQuestion
    let picked: KasusQuestion?
    /// The case the span turned out to be, for `Keine Frage`'s reveal colour.
    let revealedCase: GrammarCase?
    let help: KasusHelp
    let onPick: (KasusQuestion) -> Void

    private var four: [KasusQuestion] { questions.filter { $0 != .keine } }

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(four) { question in
                    button(question)
                }
            }
            if questions.contains(.keine) {
                button(.keine)
            }
        }
    }

    private func button(_ question: KasusQuestion) -> some View {
        EnglishQuestionButton(question: question, state: state(of: question),
                              kasus: question.kasus ?? revealedCase ?? .nominativ,
                              showsCaseName: help.showsCaseName, showsGloss: help.showsEnglishGloss) {
            guard picked == nil else { return }
            onPick(question)
        }
    }

    private func state(of question: KasusQuestion) -> KasusOptionButton.Look {
        guard let picked else { return .open }
        if question == picked { return question == answer ? .pickedRight : .pickedWrong }
        if question == answer { return .revealed }
        return .passive
    }
}

/// One question: the case it names above it, the German question, and its English gloss. The case
/// name is the scaffold the dial takes away; `Keine Frage` names no case until it is answered.
struct EnglishQuestionButton: View {
    let question: KasusQuestion
    let state: KasusOptionButton.Look
    let kasus: GrammarCase
    var showsCaseName = true
    var showsGloss = false
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: appTheme.innerRadius(12), style: .continuous)
        Button(action: action) {
            VStack(alignment: .center, spacing: 3) {
                if showsCaseName {
                    Text(caseName)
                        .font(.caption2.weight(.heavy))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(caseNameColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(spacing: 5) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.caption.weight(.bold))
                    }
                    Text(question.germanLabel)
                        .font(question == .keine ? .subheadline.weight(.semibold) : .subheadline.weight(.bold))
                        .strikethrough(state == .pickedWrong)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if showsGloss {
                    Text(question.englishGloss)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, style: StrokeStyle(lineWidth: strokeWidth,
                                                                   dash: dashed ? [5, 4] : [])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(state == .passive ? 0.4 : 1)
        .modifier(KasusShake(shakes: state == .pickedWrong ? 1 : 0))
        .animation(.linear(duration: 0.45), value: state == .pickedWrong)
        .animation(.easeOut(duration: 0.2), value: state)
        .allowsHitTesting(state == .open)
        .accessibilityLabel("\(question.germanLabel), \(question.englishGloss)")
    }

    /// „Kein Fall zu erfragen“ never shows a case before the answer is in.
    private var caseName: String {
        guard question.kasus != nil else {
            return state == .open || state == .passive ? "Kein Fall" : kasus.name
        }
        return kasus.name
    }

    private var caseNameColor: Color {
        switch state {
        case .pickedRight: Color(.systemBackground).opacity(0.9)
        case .pickedWrong: .secondary
        default:           question.kasus == nil && (state == .open || state == .passive) ? .secondary : kasus.color
        }
    }

    /// `Keine Frage` is dashed while it is open: it is the answer that isn't one of the four.
    private var dashed: Bool { question == .keine && (state == .open || state == .passive) }

    private var symbol: String? {
        switch state {
        case .pickedRight, .revealed:     "checkmark"
        case .pickedWrong:                "xmark"
        case .open, .passive, .selected:  nil
        }
    }

    private var foreground: Color {
        switch state {
        case .pickedRight:                Color(.systemBackground)
        case .revealed:                   kasus.color
        case .pickedWrong:                .secondary
        case .open, .passive, .selected:  .primary
        }
    }

    private var fill: AnyShapeStyle {
        switch state {
        case .pickedRight:    AnyShapeStyle(kasus.color)
        case .revealed:       AnyShapeStyle(kasus.color.opacity(0.12))
        case .pickedWrong:    AnyShapeStyle(Color.secondary.opacity(0.14))
        case .selected:       AnyShapeStyle(.tint.opacity(0.16))
        case .open, .passive: AnyShapeStyle(appTheme.surface)
        }
    }

    private var stroke: AnyShapeStyle {
        switch state {
        case .revealed:    AnyShapeStyle(kasus.color)
        case .selected:    AnyShapeStyle(.tint)
        case .pickedRight: AnyShapeStyle(.clear)
        case .pickedWrong: AnyShapeStyle(Color.secondary.opacity(0.3))
        case .open, .passive:
            AnyShapeStyle(appTheme.cardBorderWidth > 0 ? appTheme.cardBorderColor : Color.primary.opacity(0.14))
        }
    }

    private var strokeWidth: CGFloat {
        switch state {
        case .revealed, .selected: 2.5
        default:                   max(1, appTheme.cardBorderWidth)
        }
    }
}
