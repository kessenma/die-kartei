//
//  KasusFeedback.swift
//  german-ai-flashcards
//
//  The right/wrong signal every case exercise shares, so the Schnellrunde, Finden and Einsetzen
//  answer the same way:
//
//    KasusVerdict         right · almost (a gender or number slip) · not quite, with its words
//    KasusFeedbackHeader  „Richtig!“ with a bounce, „Fast · Almost“, „Nicht ganz · Not quite“
//    KasusOptionGrid      big answer buttons: the right pick fills in the question's case color
//                         with a checkmark; a wrong pick shakes and greys out struck through, and
//                         the answer lights up in the case color
//    KasusProgressStrip   one dot per question, filled in its case color when right, a hollow
//                         grey ring when not, and the running score; past 20 the dots wrap
//    KasusCappedScroll    the verdict and its why at their own height, scrolling past a cap, so
//                         the buttons under them never leave the screen
//
//  Never green or red for right and wrong: gender colors mark forms, case colors mark cases, and a
//  miss is grey. So a right pick takes the case color, like its progress dot, never the gender
//  color: a right „die“ filled die-red would read as wrong. The form itself keeps its gender
//  color in the sentence. A miss shakes instead of flashing.
//

import SwiftUI

// MARK: - Verdict

/// What one answer was, as the learner hears it.
enum KasusVerdict: Hashable {
    case right
    /// Right case, wrong gender or number: close, and it says nothing about the case.
    case slip
    case miss

    init(_ outcome: KasusPickOutcome) {
        switch outcome {
        case .right:                    self = .right
        case .genderSlip, .numberSlip:  self = .slip
        case .caseMiss:                 self = .miss
        }
    }

    var title: String {
        switch self {
        case .right: "Richtig!"
        case .slip:  "Fast · Almost"
        case .miss:  "Nicht ganz · Not quite"
        }
    }

    var symbol: String {
        switch self {
        case .right: "checkmark.circle.fill"
        case .slip:  "circle.lefthalf.filled"
        case .miss:  "xmark.circle"
        }
    }
}

// MARK: - Header

/// The first line after an answer: the verdict, then the case it was. Right bounces its checkmark
/// in the case color; a slip or a miss stays grey and calm.
struct KasusFeedbackHeader: View {
    let verdict: KasusVerdict
    var kasus: GrammarCase? = nil
    /// Anything after the case label, e.g. the phrase („dem Hund“).
    var detail: String? = nil
    var font: Font = .headline

    @State private var bounce = false

    var body: some View {
        // One line where it fits; at large text sizes the case moves under the verdict instead
        // of truncating.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                verdictLabel
                caseAndDetail
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            // Stacked, the verdict may wrap rather than lose its English half.
            VStack(alignment: .leading, spacing: 4) {
                verdictLabel
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    caseAndDetail
                }
                .lineLimit(1)
            }
        }
        .font(font)
        .onAppear { bounce.toggle() }
        .accessibilityElement(children: .combine)
    }

    private var verdictLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: verdict.symbol)
                .foregroundStyle(verdict == .right ? AnyShapeStyle(kasus?.color ?? .accentColor) : AnyShapeStyle(.secondary))
                .symbolEffect(.bounce, value: bounce)
            Text(verdict.title)
                .fontWeight(.bold)
        }
    }

    @ViewBuilder
    private var caseAndDetail: some View {
        if let kasus {
            CaseLabel(kasus: kasus, style: .name)
                .fontWeight(.semibold)
                .font(.subheadline)
        }
        if let detail {
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Answer buttons

/// The answer buttons, in rows of `columns` with the last row centred. Before a pick every button
/// is live; after it the picked one says right or wrong, the answer lights up, and the rest step
/// back. Give the grid a new `.id` per question so the shake and the pop start fresh.
struct KasusOptionGrid: View {
    let options: [String]
    /// Compared ignoring case, like every Kasus grade.
    let answer: String
    /// The question's case, whose color the right button takes.
    let kasus: GrammarCase
    let picked: String?
    var columns: Int = 3
    var rowHeight: CGFloat = 58
    var font: Font = .title3.weight(.semibold)
    let onPick: (String) -> Void

    var body: some View {
        KasusCenteredRows(columns: max(1, min(columns, options.count)), spacing: 10, rowHeight: rowHeight) {
            ForEach(options, id: \.self) { option in
                KasusOptionButton(
                    option: option,
                    state: state(of: option),
                    kasus: kasus,
                    font: font
                ) {
                    guard picked == nil else { return }
                    onPick(option)
                }
            }
        }
    }

    private func isAnswer(_ option: String) -> Bool {
        option.caseInsensitiveCompare(answer) == .orderedSame
    }

    private func state(of option: String) -> KasusOptionButton.Look {
        guard let picked else { return .open }
        if option == picked { return isAnswer(option) ? .pickedRight : .pickedWrong }
        if isAnswer(option) { return .revealed }
        return .passive
    }

    /// One row if every option is short (der, dem, des…), else three to a row.
    static func columns(for options: [String], maxInRow: Int = 6) -> Int {
        options.allSatisfy { $0.count <= 3 } && options.count <= maxInRow ? options.count : 3
    }
}

/// One answer button and its five looks.
struct KasusOptionButton: View {
    enum Look: Hashable {
        /// Waiting for a pick.
        case open
        /// Picked, and right: filled in the case color with a checkmark.
        case pickedRight
        /// Picked, and wrong: grey, struck through, an xmark, and a shake.
        case pickedWrong
        /// Not picked, but the answer: outlined and tinted in the case color with a checkmark.
        case revealed
        /// Neither: steps back.
        case passive
    }

    let option: String
    let state: Look
    let kasus: GrammarCase
    var font: Font = .title3.weight(.semibold)
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: appTheme.innerRadius(12), style: .continuous)
        Button(action: action) {
            // At large text sizes the mark gives way to the word; the fill and stroke still say
            // right or wrong.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.subheadline.weight(.bold))
                            .transition(.scale.combined(with: .opacity))
                    }
                    label
                }
                label
            }
            .font(font)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(KasusPressStyle())
        .opacity(state == .passive ? 0.4 : 1)
        .modifier(KasusShake(shakes: state == .pickedWrong ? 1 : 0))
        .animation(.linear(duration: 0.45), value: state == .pickedWrong)
        .keyframeAnimator(initialValue: 1.0, trigger: state == .pickedRight) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.08, duration: 0.14)
            SpringKeyframe(1.0, duration: 0.3)
        }
        .animation(.easeOut(duration: 0.2), value: state)
        .allowsHitTesting(state == .open)
        .accessibilityLabel(option)
        .accessibilityValue(accessibilityValue)
    }

    private var label: some View {
        Text(option)
            .strikethrough(state == .pickedWrong)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var symbol: String? {
        switch state {
        case .pickedRight, .revealed: "checkmark"
        case .pickedWrong:            "xmark"
        case .open, .passive:         nil
        }
    }

    private var foreground: Color {
        switch state {
        // The case colors brighten in dark mode, so the label flips with the ground to stay legible.
        case .pickedRight:              Color(.systemBackground)
        case .revealed:                 kasus.color
        case .pickedWrong:              .secondary
        case .open, .passive:           .primary
        }
    }

    private var fill: AnyShapeStyle {
        switch state {
        case .pickedRight:  AnyShapeStyle(kasus.color)
        case .revealed:     AnyShapeStyle(kasus.color.opacity(0.12))
        case .pickedWrong:  AnyShapeStyle(Color.secondary.opacity(0.14))
        case .open, .passive:  AnyShapeStyle(appTheme.surface)
        }
    }

    private var stroke: Color {
        switch state {
        case .revealed:     kasus.color
        case .pickedRight:  .clear
        case .pickedWrong:  Color.secondary.opacity(0.3)
        case .open, .passive:
            appTheme.cardBorderWidth > 0 ? appTheme.cardBorderColor : Color.primary.opacity(0.14)
        }
    }

    private var strokeWidth: CGFloat {
        switch state {
        case .revealed:  2.5
        case .open, .passive: max(1, appTheme.cardBorderWidth)
        default:         1
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .pickedRight:  "Your pick, right"
        case .pickedWrong:  "Your pick, not right"
        case .revealed:     "The answer"
        case .open, .passive: ""
        }
    }
}

/// A press that dips the button a little, since a custom fill has no system highlight.
private struct KasusPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Equal cells in rows of `columns`; a short last row sits in the middle instead of hanging left.
private struct KasusCenteredRows: Layout {
    let columns: Int
    let spacing: CGFloat
    let rowHeight: CGFloat

    private func rows(_ count: Int) -> Int { (count + columns - 1) / columns }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = rows(subviews.count)
        return CGSize(width: proposal.width ?? CGFloat(columns) * 90,
                      height: CGFloat(count) * rowHeight + CGFloat(max(0, count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        for (i, subview) in subviews.enumerated() {
            let row = i / columns
            let inRow = min(columns, subviews.count - row * columns)
            let rowWidth = CGFloat(inRow) * cell + CGFloat(inRow - 1) * spacing
            let x = bounds.minX + (bounds.width - rowWidth) / 2 + CGFloat(i % columns) * (cell + spacing)
            let y = bounds.minY + CGFloat(row) * (rowHeight + spacing)
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: cell, height: rowHeight))
        }
    }
}

/// A quick horizontal shake for a wrong pick, feedback without red. Animate `shakes` from 0 to 1.
struct KasusShake: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(shakes * .pi * 6) * 7, y: 0))
    }
}

// MARK: - Progress strip

/// One dot per question in order, and the running score. A dot fills in its case color once it's
/// right, turns into a hollow grey ring when it isn't (a slip keeps a small grey center, since it
/// was close), rings the question being asked, and stays a faint dot until then.
struct KasusProgressStrip: View {
    enum Mark: Hashable {
        case right(GrammarCase)
        case slip
        case miss
        case current
        case upcoming
    }

    let marks: [Mark]
    /// Hides the score, where the screen already shows it big.
    var showsScore = true

    private var rightCount: Int {
        marks.filter { if case .right = $0 { return true } else { return false } }.count
    }

    private var answeredCount: Int {
        marks.filter { $0 != .current && $0 != .upcoming }.count
    }

    /// Past this many marks (a B1 story's Finden has 51) the dots keep a fixed size and wrap onto
    /// more rows, instead of shrinking until a ring can't be told from a filled dot.
    private static let wrapThreshold = 20
    private var wraps: Bool { marks.count > Self.wrapThreshold }

    var body: some View {
        HStack(alignment: wraps ? .top : .center, spacing: 10) {
            Group {
                if wraps {
                    KasusDotFlow(dot: 9, spacing: 4) {
                        ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                            dot(mark)
                        }
                    }
                } else {
                    HStack(spacing: marks.count > 16 ? 3 : 6) {
                        ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                            dot(mark)
                                .frame(maxWidth: 11, maxHeight: 11)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy(duration: 0.25), value: marks)
            if showsScore {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                    Text("\(rightCount)")
                        .contentTransition(.numericText())
                        .animation(.snappy, value: rightCount)
                }
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rightCount) right of \(answeredCount) answered, \(marks.count) in all")
    }

    @ViewBuilder
    private func dot(_ mark: Mark) -> some View {
        switch mark {
        case .right(let kasus):
            Circle().fill(kasus.color)
        case .miss:
            Circle().strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.5)
        case .slip:
            Circle().strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.5)
                .overlay(Circle().fill(Color.secondary.opacity(0.7)).scaleEffect(0.36))
        case .current:
            Circle().strokeBorder(.tint, lineWidth: 2.5)
        case .upcoming:
            Circle().fill(Color.secondary.opacity(0.22)).padding(1.5)
        }
    }
}

/// Fixed-size dots in rows that wrap at the width they're given, for a long strip.
private struct KasusDotFlow: Layout {
    let dot: CGFloat
    let spacing: CGFloat

    private func perRow(_ width: CGFloat?) -> Int {
        guard let width, width.isFinite else { return 30 }
        return max(1, Int((width + spacing) / (dot + spacing)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let columns = perRow(proposal.width)
        let rows = (subviews.count + columns - 1) / columns
        let natural = CGFloat(min(columns, subviews.count)) * (dot + spacing) - spacing
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? max(0, natural)
        return CGSize(width: width, height: CGFloat(rows) * dot + CGFloat(max(0, rows - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = perRow(bounds.width)
        for (i, subview) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(i % columns) * (dot + spacing)
            let y = bounds.minY + CGFloat(i / columns) * (dot + spacing)
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: dot, height: dot))
        }
    }
}

// MARK: - Capped scroll

/// Its content at its own height up to `maxHeight`, and scrolling past that. A tray or answer
/// panel puts the verdict and its why in one, so a long explanation at a large text size scrolls
/// in place instead of pushing the answer buttons and Weiter off the screen.
struct KasusCappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        KasusHeightCap(maxHeight: maxHeight) {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicatorsFlash(onAppear: true)
        }
    }
}

/// Its one child at the child's own height, never taller than `maxHeight`: a scroll view asked
/// for its ideal height reports its content's, so it hugs short content and scrolls long.
private struct KasusHeightCap: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: min(ideal.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

// MARK: - Previews

#Preview("Kasus feedback · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            VStack(alignment: .leading, spacing: 22) {
                KasusProgressStrip(marks: [.right(.nominativ), .right(.akkusativ), .miss, .slip,
                                           .right(.dativ), .current, .upcoming, .upcoming, .upcoming, .upcoming])
                // A B1 story's Finden: wraps instead of shrinking.
                KasusProgressStrip(marks: (0..<41).map { i in
                    i % 7 == 3 ? .miss : i % 11 == 5 ? .slip : .right(GrammarCase.allCases[i % 4])
                }, showsScore: false)
                KasusFeedbackHeader(verdict: .right, kasus: .dativ, detail: "„dem Hund“")
                KasusOptionGrid(options: ["der", "die", "das", "den", "dem"], answer: "dem",
                                kasus: .dativ, picked: "dem") { _ in }
                KasusFeedbackHeader(verdict: .miss, kasus: .akkusativ)
                KasusOptionGrid(options: ["meine", "meinen", "meinem", "meiner", "mein"], answer: "meine",
                                kasus: .akkusativ, picked: "meinen") { _ in }
                KasusFeedbackHeader(verdict: .slip, kasus: .dativ)
                KasusOptionGrid(options: ["der", "die", "das", "den", "dem", "des"], answer: "der",
                                kasus: .dativ, picked: nil, columns: 6, rowHeight: 46) { _ in }
            }
            .padding()
            .frame(maxHeight: .infinity)
            .background(ThemedBackground().ignoresSafeArea())
            .environment(\.appTheme, theme)
            .tint(theme.accent(model: nil))
            .tabItem { Text(theme.label) }
        }
    }
}
