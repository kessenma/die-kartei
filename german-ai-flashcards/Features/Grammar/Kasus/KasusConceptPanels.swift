//
//  KasusConceptPanels.swift
//  german-ai-flashcards
//
//  The pieces the Verstehen modules (Features/Grammar/Drill/ConceptModules.swift) show per exercise:
//
//    KasusRolesHero      the sentence as word chips (the asked phrase ringed, answered phrases
//                        washed in their case color), and the English twin on demand
//    KasusRoleGrid       the role chips, two to a row, with their six looks (`KasusOptionButton`)
//    KasusWalkPanel      Schritt für Schritt: one Kasus-Check question and Ja / Nein
//    KasusWerHero        the sentence(s) in large type, phrases colored once answered, the
//                        question line, the English
//    KasusProbeHero      the sentence with the phrase underlined, and the swapped sentence after
//                        the pick
//    KasusConceptSentence a round item's sentence with its phrase set off, for the summary
//
//  Colors follow the Kasus rules: phrases and roles in case colors, article letters in gender
//  colors, right in the case color, wrong grey.
//

import SwiftUI

// MARK: - Rollen

struct KasusRolesHero: View {
    let item: KasusConceptPlayable
    /// The phrase being asked (ringed).
    let target: KasusLocatedTarget?
    /// Answers given on this item, by target index.
    let answers: [Int: KasusConceptAnswer]
    @Binding var showEnglish: Bool

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(item.story.level)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                KasusEnglishToggle(isOn: $showEnglish)
            }
            KasusSentenceList(sentences: item.sentences, font: .title3) { word in
                chip(word)
            }
            if showEnglish {
                ForEach(Array(item.story.paragraphs.indices), id: \.self) { paragraph in
                    Text(kasusRich: item.englishLine(paragraph: paragraph, highlighting: highlightedCases))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The cases revealed so far on this item, by target index.
    private var highlightedCases: [Int: GrammarCase] {
        answers.mapValues(\.kasus)
    }

    private func chip(_ word: KasusWord) -> some View {
        var style = KasusChipStyle()
        if let index = word.role.targetIndex {
            if let given = answers[index] {
                style.wash = given.kasus.color.opacity(0.18)
                if let target = item.target(index), target.determinerRange == word.paragraphRange {
                    style.badge = given.isRight ? .check(given.kasus.color) : .cross
                }
            }
            if let target, target.index == index {
                style.selected = true
            }
        }
        // Once answered, the deciding word gets its dashed underline in the case color.
        if let target, let given = answers[target.index], let trigger = target.triggerRange,
           NSIntersectionRange(trigger, word.paragraphRange).length > 0 {
            style.underline = given.kasus.color
        }
        return KasusChip(style: style) {
            KasusWordText.text(word)
        }
    }
}

/// „EN“: shows the English twin.
struct KasusEnglishToggle: View {
    @Binding var isOn: Bool

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text("EN")
                .font(.caption.weight(.bold))
                .foregroundStyle(isOn ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.tint))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.12)), in: appTheme.pillShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("English")
        .accessibilityValue(isOn ? "shown" : "hidden")
    }
}

/// The role chips, two to a row. Before a pick every chip is live; after it the picked one says
/// right or wrong, the actual role lights up in its case color, and the rest step back.
struct KasusRoleGrid: View {
    let roles: [KasusRole]
    let unit: KasusUnit
    let picked: KasusRole?
    /// The phrase's role, once answered.
    let actual: KasusRole?
    /// The case the actual role revealed, whose color the right chip takes.
    let revealedCase: GrammarCase?
    let onPick: (KasusRole) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(roles) { role in
                KasusRoleButton(role: role, bridge: bridge(role), state: state(of: role),
                                kasus: revealedCase ?? role.fixedCase ?? .nominativ) {
                    guard picked == nil else { return }
                    onPick(role)
                }
            }
        }
    }

    private func bridge(_ role: KasusRole) -> String {
        role == .praeposition ? KasusRole.prepositionBridge(for: unit) : role.bridge
    }

    private func state(of role: KasusRole) -> KasusOptionButton.Look {
        guard let picked else { return .open }
        if role == picked { return role == actual ? .pickedRight : .pickedWrong }
        if role == actual { return .revealed }
        return .passive
    }
}

/// One role chip: the German name, its English, and the pronoun bridge in small type, with the
/// looks of an answer button.
struct KasusRoleButton: View {
    let role: KasusRole
    let bridge: String
    let state: KasusOptionButton.Look
    let kasus: GrammarCase
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: appTheme.innerRadius(12), style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.caption.weight(.bold))
                    } else {
                        Image(systemName: role.symbol)
                            .font(.caption)
                    }
                    Text(role.germanLabel)
                        .font(.subheadline.weight(.bold))
                        .strikethrough(state == .pickedWrong)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Text(role.englishLabel)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(kasusRich: bridge)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .opacity(0.8)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(state == .passive ? 0.4 : 1)
        .modifier(KasusShake(shakes: state == .pickedWrong ? 1 : 0))
        .animation(.linear(duration: 0.45), value: state == .pickedWrong)
        .animation(.easeOut(duration: 0.2), value: state)
        .allowsHitTesting(state == .open)
        .accessibilityLabel("\(role.germanLabel), \(role.englishLabel)")
        .accessibilityValue(accessibilityValue)
    }

    private var symbol: String? {
        switch state {
        case .pickedRight, .revealed: "checkmark"
        case .pickedWrong:            "xmark"
        case .open, .passive, .selected: nil
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
        case .pickedRight:  AnyShapeStyle(kasus.color)
        case .revealed:     AnyShapeStyle(kasus.color.opacity(0.12))
        case .pickedWrong:  AnyShapeStyle(Color.secondary.opacity(0.14))
        case .selected:     AnyShapeStyle(.tint.opacity(0.16))
        case .open, .passive: AnyShapeStyle(appTheme.surface)
        }
    }

    private var stroke: AnyShapeStyle {
        switch state {
        case .revealed:     AnyShapeStyle(kasus.color)
        case .selected:     AnyShapeStyle(.tint)
        case .pickedRight:  AnyShapeStyle(.clear)
        case .pickedWrong:  AnyShapeStyle(Color.secondary.opacity(0.3))
        case .open, .passive:
            AnyShapeStyle(appTheme.cardBorderWidth > 0 ? appTheme.cardBorderColor : Color.primary.opacity(0.14))
        }
    }

    private var strokeWidth: CGFloat {
        switch state {
        case .revealed, .selected: 2.5
        case .open, .passive:      max(1, appTheme.cardBorderWidth)
        default:                   1
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .pickedRight:  "Your pick, right"
        case .pickedWrong:  "Your pick, not right"
        case .revealed:     "The answer"
        case .selected:     "Your choice"
        case .open, .passive: ""
        }
    }
}

/// Schritt für Schritt: the Kasus-Check question for the ringed phrase, and Ja / Nein.
struct KasusWalkPanel: View {
    let question: KasusRole?
    let picked: String?
    let answer: String
    let kasus: GrammarCase
    /// Only the deciding question (or the last one) shows the case color; before that a right
    /// Ja or Nein takes the tint, so the buttons don't name the case ahead of the Check.
    let decides: Bool
    let graded: Bool
    let onPick: (Bool) -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(spacing: 10) {
            if let question {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(question.checkStep)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(kasusRich: question.question.de)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(question.question.en)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KasusOptionGrid(options: ["Ja", "Nein"], answer: answer, kasus: kasus, picked: picked,
                                graded: graded, columns: 2, rowHeight: 54,
                                color: decides ? nil : appTheme.accent(model: nil)) { option in
                    onPick(option == "Ja")
                }
            }
        }
    }
}

// MARK: - Wer macht was?

struct KasusWerHero: View {
    let item: KasusConceptPlayable
    let answer: KasusConceptAnswer?
    @Binding var showEnglish: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .title) private var heroSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            HStack {
                Text(item.story.level)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                KasusEnglishToggle(isOn: $showEnglish)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(item.story.paragraphs.indices), id: \.self) { paragraph in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if item.story.paragraphs.count > 1 {
                            Text("\(paragraph + 1).")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        sentence(paragraph)
                    }
                    .font(.system(size: sizeClass == .regular ? heroSize * 1.3 : heroSize, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: item.story.paragraphs.count > 1 ? .leading : .center)
            .multilineTextAlignment(item.story.paragraphs.count > 1 ? .leading : .center)
            if let question = item.question {
                KasusInstruction(german: question.de, english: question.en)
                    .multilineTextAlignment(.center)
            } else if item.same != nil {
                KasusInstruction(german: "Gleich oder anders?", english: "Do the two sentences mean the same?")
            }
            if showEnglish || answer != nil {
                ForEach(Array(item.story.paragraphs.indices), id: \.self) { paragraph in
                    Text(kasusRich: item.englishLine(paragraph: paragraph, highlighting: answer == nil ? [:] : revealed))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Every target's case, once answered.
    private var revealed: [Int: GrammarCase] {
        Dictionary(uniqueKeysWithValues: item.targets.map { ($0.index, $0.kasus) })
    }

    /// The sentence, its phrases in their case colors once answered.
    private func sentence(_ paragraph: Int) -> Text {
        let text = item.story.paragraphs[paragraph].de
        guard answer != nil else { return Text(text) }
        var out = AttributedString(text)
        for target in item.targets where target.paragraphIndex == paragraph {
            guard let range = Range(target.range, in: out) else { continue }
            out[range].foregroundColor = target.kasus.color
        }
        return Text(out)
    }
}

/// Wer …? with pictures: the two readings side by side, as stills. Before the pick both show the
/// thing chased in grey, so neither gives the case away; after it they show it in its case
/// color, the picked one says right or wrong, and the right one is outlined. Stills, not live
/// scenes: two at once would mean two RealityKit surfaces, and a still reads at a glance.
struct KasusPictureChoice: View {
    let item: KasusConceptPlayable
    let doer: KasusLocatedTarget
    let picked: Int?
    let onPick: (Int) -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(item.options, id: \.index) { option in
                picture(option)
            }
        }
    }

    private func picture(_ option: KasusLocatedTarget) -> some View {
        let asset = item.item.pictures[option.index] ?? ""
        let answered = picked != nil
        let isAnswer = option.index == doer.index
        let isPicked = option.index == picked
        let shape = RoundedRectangle(cornerRadius: appTheme.innerRadius(12), style: .continuous)
        let kasus = item.facts.clue.flatMap(item.target)?.kasus ?? .akkusativ
        let stroke: Color = !answered ? Color.primary.opacity(0.14)
            : isAnswer ? kasus.color : isPicked ? Color.secondary.opacity(0.5) : Color.primary.opacity(0.08)
        return Button {
            guard picked == nil else { return }
            onPick(option.index)
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = PrepositionScene.image(for: asset, state: answered ? "dat" : "neutral") {
                        // The pair fills only x 159–350, y 283–384 of the 512-px still: zoom
                        // 3.4× and lift its centre (18 pt below the middle at 120 pt, so ×3.4)
                        // so the animals fill the box.
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(3.4)
                            .offset(y: -60)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipped()
                if answered, isAnswer || isPicked {
                    Image(systemName: isAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isAnswer ? kasus.color : Color.secondary)
                        .background(Circle().fill(appTheme.surface))
                        .padding(6)
                }
            }
            .background(shape.fill(appTheme.surface))
            .overlay(shape.strokeBorder(stroke, lineWidth: answered && (isAnswer || isPicked) ? 2.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(answered && !isAnswer && !isPicked ? 0.5 : 1)
        .modifier(KasusShake(shakes: answered && isPicked && !isAnswer ? 1 : 0))
        .animation(.linear(duration: 0.45), value: answered && isPicked && !isAnswer)
        .allowsHitTesting(!answered)
        .accessibilityLabel(pictureLabel(for: asset))
        .accessibilityValue(!answered ? "" : isAnswer ? "The answer" : isPicked ? "Your pick, not right" : "")
    }

    /// What the picture shows, for VoiceOver: its scene's sentence.
    private func pictureLabel(for asset: String) -> String {
        switch asset {
        case KasusLessonScene.jagenHund.asset:  "Picture: the dog chases the cat"
        case KasusLessonScene.jagenKatze.asset: "Picture: the cat chases the dog"
        default:                                 "Picture"
        }
    }
}

// MARK: - Die Probe

struct KasusProbeHero: View {
    let item: KasusConceptPlayable
    let probe: KasusProbeQuestion
    let answer: KasusConceptAnswer?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .title) private var heroSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 18) {
            Text(item.story.level)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            original
                .font(.system(size: sizeClass == .regular ? heroSize * 1.3 : heroSize, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            KasusInstruction(
                german: "Ersetze „\(probe.target.surface)“ durch *\(probe.noun.dictionaryForm)*.",
                english: "Swap in the masculine test noun. Which form fits the slot?"
            )
            .multilineTextAlignment(.center)
            if answer != nil {
                swapped
                    .font(.system(size: sizeClass == .regular ? heroSize * 1.1 : heroSize * 0.85, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                Text(kasusRich: item.englishLine(paragraph: probe.target.paragraphIndex,
                                                  highlighting: [probe.target.index: probe.kasus]))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The sentence with the asked phrase underlined in the tint.
    private var original: Text {
        var out = AttributedString(probe.sentence)
        let length = probe.target.surface.utf16.count
        if let range = Range(NSRange(location: probe.phraseStart, length: length), in: out) {
            out[range].underlineStyle = .single
            out[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return Text(out)
    }

    /// The swapped sentence: the test noun's form bold, its article in the masculine blue, on a
    /// wash in the case color.
    private var swapped: Text {
        var out = AttributedString(probe.swappedSentence)
        let length = probe.swappedPhrase.utf16.count
        if let range = Range(NSRange(location: probe.phraseStart, length: length), in: out) {
            out[range].inlinePresentationIntent = .stronglyEmphasized
            out[range].backgroundColor = probe.kasus.color.opacity(0.18)
            let articleLength = probe.swappedArticle.utf16.count
            if let article = Range(NSRange(location: probe.phraseStart, length: articleLength), in: out) {
                out[article].foregroundColor = Gender.der.color
            }
        }
        return Text(out)
    }
}

// MARK: - A round item's sentence

/// A `KasusRoundItem`'s sentence with its phrase bold and underlined in its case color, for the
/// summary's misses (the round detail draws its own).
enum KasusConceptSentence {
    static func text(_ item: KasusRoundItem) -> Text {
        let text = item.sentence
        guard let range = range(of: item) else { return Text(text) }
        var out = AttributedString(text)
        if let r = Range(range, in: out) {
            out[r].inlinePresentationIntent = .stronglyEmphasized
            out[r].underlineStyle = Text.LineStyle(pattern: .solid, color: item.kasus?.color ?? .secondary)
        }
        return Text(out)
    }

    private static func range(of item: KasusRoundItem) -> NSRange? {
        let ns = item.sentence as NSString
        let length = item.phrase.utf16.count
        if let start = item.phraseStart, start >= 0, start + length <= ns.length,
           ns.substring(with: NSRange(location: start, length: length)) == item.phrase {
            return NSRange(location: start, length: length)
        }
        let found = ns.range(of: item.phrase)
        return found.location == NSNotFound ? nil : found
    }
}
