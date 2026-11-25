//
//  PhraseGapCardView.swift
//  german-ai-flashcards
//
//  A phrase card with one word missing ("eine Störung _____") and four choices under it: the face
//  a phrase card shows in Default, Anki and Leitner when "Gaps on phrase cards" is on. Which word
//  and which choices is `PhraseGapPlanner`'s; this view only asks. A pick is graded at once, the
//  whole phrase shows with the word marked, and the deck screen turns the answer into its own
//  rating (`CardDeckView.answerGap`). See docs/PHRASES.md.
//

import SwiftUI

struct PhraseGapCardView: View {
    let question: PhraseGapQuestion
    /// The card's English: the meaning the learner fills the gap from.
    let english: String
    var accent: Color = .accentColor
    /// The pick already made on this card, when the screen is redrawn after it.
    var initialPick: String? = nil
    let onPick: (_ option: String, _ correct: Bool) -> Void

    @State private var picked: String?
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme

    private var answered: Bool { picked != nil }
    private var phrase: String { question.tokens.joined(separator: " ") }

    var body: some View {
        VStack(spacing: 16) {
            card
            KasusOptionGrid(
                options: question.options,
                answer: question.answer,
                kasus: .nominativ,
                picked: picked,
                columns: question.options.allSatisfy { $0.count <= 5 } ? 4 : 2,
                rowHeight: 52,
                font: .headline,
                color: accent
            ) { option in
                picked = option
                onPick(option, option.caseInsensitiveCompare(question.answer) == .orderedSame)
            }
            .id(question)
            .frame(maxWidth: 520)
        }
        .padding(.horizontal)
    }

    init(question: PhraseGapQuestion, english: String, accent: Color = .accentColor, initialPick: String? = nil,
         onPick: @escaping (_ option: String, _ correct: Bool) -> Void) {
        self.question = question
        self.english = english
        self.accent = accent
        self.initialPick = initialPick
        self.onPick = onPick
        _picked = State(initialValue: initialPick)
    }

    private var card: some View {
        VStack(spacing: 14) {
            Text(english)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(sentence)
                .font(.system(.title2, design: .serif))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if answered {
                Button {
                    SpeechService.shared.speak(phrase)
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
            } else {
                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: 520, minHeight: 170)
        .background {
            let shape = RoundedRectangle(cornerRadius: appTheme.innerRadius(16), style: .continuous)
            shape.fill(cardColor)
                .overlay(shape.stroke(appTheme.cardBorderWidth > 0 ? appTheme.cardBorderColor : accent.opacity(0.35),
                                      lineWidth: appTheme.cardBorderWidth > 0 ? appTheme.cardBorderWidth : 1))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(answered ? "\(phrase). \(english)" : "Fill the gap: \(question.blanked("blank").joined(separator: " ")). \(english)")
    }

    private var prompt: String {
        switch question.kind {
        case .preposition: "Which preposition goes here?"
        case .verb: "Which verb goes with it?"
        case .word: "Which word is missing?"
        }
    }

    /// The phrase with the gap, or after a pick with the answer in place and marked.
    private var sentence: AttributedString {
        var out = AttributedString()
        for (index, token) in question.tokens.enumerated() {
            if index > 0 { out += AttributedString(" ") }
            guard index == question.hiddenIndex else {
                out += AttributedString(token)
                continue
            }
            let parts = token.components(separatedBy: question.answer)
            let before = parts.first ?? ""
            let after = parts.count > 1 ? parts.dropFirst().joined(separator: question.answer) : ""
            out += AttributedString(before)
            var word = AttributedString(answered ? question.answer : "_____")
            word.foregroundColor = accent
            word.font = .system(.title2, design: .serif).weight(.bold)
            if answered { word.underlineStyle = .single }
            out += word
            out += AttributedString(after)
        }
        return out
    }

    /// The flip card's paper, so the gap face sits in the same deck.
    private var cardColor: Color {
        if appTheme != .klar { return appTheme.surface }
        return colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.20)
            : Color(red: 0.98, green: 0.96, blue: 0.93)
    }
}
