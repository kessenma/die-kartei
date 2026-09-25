//
//  KasusSentences.swift
//  german-ai-flashcards
//
//  The story as the class worksheet prints it: numbered sentences, one per row, with a hanging
//  number and every word its own chip, so tapping a short „den“ is as easy as tapping „Schwester“.
//  Markieren and Endungen both use it; Lesen keeps the paragraphs (`KasusText`).
//
//    KasusSentenceList  the rows: „1.“ hanging in its own column, the words wrapping beside it
//    KasusWordFlow      the wrapping layout for one sentence's chips
//    KasusChip          one word's chip: a wash, an outline (solid or dashed), a strikethrough,
//                       a small ✓ / ✗ badge in the corner, and a ring when it's selected
//    KasusWordText      a word with its punctuation (and a class-style „(m)“ tag before it)
//
//  A chip's width never changes with its look: washes, outlines and badges draw around the word
//  (the badge overlaps the corner), so marking or checking never moves a line. Only a wrong
//  ending, which shows ~~pick~~ answer, makes its chip wider.
//

import SwiftUI

// MARK: - Sentences

/// Numbered sentences, one per row. `word` draws each word's chip.
struct KasusSentenceList<Word: View>: View {
    let sentences: [KasusSentence]
    var font: Font = .title3
    @ViewBuilder let word: (KasusWord) -> Word

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sentences) { sentence in
                HStack(alignment: .top, spacing: 4) {
                    // The widest number, hidden, holds the column, so „9.“ and „10.“ end on
                    // the same line, as a worksheet's numbers do.
                    ZStack(alignment: .trailing) {
                        Text("\(sentences.last?.number ?? 1).").hidden()
                        Text("\(sentence.number).")
                    }
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.vertical, KasusChipMetrics.verticalPadding)
                    .accessibilityHidden(true)
                    KasusWordFlow {
                        ForEach(sentence.words) { item in
                            word(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(font)
                .id(sentence.number)
            }
        }
    }
}

/// Chips left to right, wrapping at the width given, each row's chips centred on one line.
struct KasusWordFlow: Layout {
    var spacing: CGFloat = KasusChipMetrics.wordSpacing
    var lineSpacing: CGFloat = KasusChipMetrics.lineSpacing

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            // A word wider than the line (a long compound at the largest text sizes) wraps inside
            // its chip instead of running off the edge.
            if size.width > width {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? .greatestFiniteMagnitude
        let rows = rows(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: width == .greatestFiniteMagnitude ? used : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                                           anchor: .topLeading, proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
}

// MARK: - Chip

enum KasusChipMetrics {
    static let horizontalPadding: CGFloat = 3.5
    static let verticalPadding: CGFloat = 5
    /// The gaps between chips in a sentence, across and down. Each chip's tap area grows into
    /// half of each (`KasusChipHitArea`), so a thumb landing between two words still hits one,
    /// and a row of title3 chips is about 40 pt from line to line.
    static let wordSpacing: CGFloat = 2
    static let lineSpacing: CGFloat = 5
}

/// The small mark in a chip's corner once it's judged. Never green or red: right wears the case
/// color, wrong and almost are grey.
enum KasusChipBadge: Hashable {
    case check(Color)
    case cross
    case slip
}

/// How one chip is dressed. Nothing here changes the chip's size.
struct KasusChipStyle {
    /// The word's color; nil is primary.
    var foreground: Color? = nil
    var wash: Color? = nil
    var outline: Color? = nil
    /// The outline dashed: a word that was missed.
    var dashed = false
    var strikethrough = false
    var badge: KasusChipBadge? = nil
    /// A dashed line under the word: the word that decides the focused gap's case.
    var underline: Color? = nil
    /// A ring around the chip: the word the tray is talking about.
    var selected = false
}

/// One word, or one gap, as a chip. With an `action` it's a button; without, it only takes up
/// the same room, so the rows line up the same either way.
struct KasusChip<Label: View>: View {
    var style = KasusChipStyle()
    var action: (() -> Void)? = nil
    @ViewBuilder let label: () -> Label

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        if let action {
            Button(action: action) { dressed }
                .buttonStyle(KasusChipPressStyle())
        } else {
            dressed
        }
    }

    private var dressed: some View {
        let shape = RoundedRectangle(cornerRadius: appTheme.innerRadius(7), style: .continuous)
        return label()
            .padding(.horizontal, KasusChipMetrics.horizontalPadding)
            .padding(.vertical, KasusChipMetrics.verticalPadding)
            .overlay(alignment: .bottom) {
                if let underline = style.underline {
                    Line()
                        .stroke(underline, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .frame(height: 1.5)
                        .padding(.horizontal, KasusChipMetrics.horizontalPadding)
                        .padding(.bottom, 3)
                }
            }
            .background(shape.fill(style.wash ?? .clear))
            .overlay {
                if let outline = style.outline {
                    shape.strokeBorder(outline, style: StrokeStyle(lineWidth: 1.5, dash: style.dashed ? [4, 3] : []))
                }
            }
            .overlay {
                if style.selected {
                    shape.inset(by: -2.5).stroke(Color.primary.opacity(0.55), lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge = style.badge {
                    badgeView(badge)
                        .offset(x: 5, y: -6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(KasusChipHitArea())
    }

    @ViewBuilder
    private func badgeView(_ badge: KasusChipBadge) -> some View {
        let (symbol, fill): (String, Color) = switch badge {
        case .check(let color): ("checkmark", color)
        case .cross:            ("xmark", Color(.systemGray))
        case .slip:             ("circle.lefthalf.filled", Color(.systemGray))
        }
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(Color(.systemBackground))
            .frame(width: 15, height: 15)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
            .accessibilityHidden(true)
    }

    /// A straight line along the bottom edge, for the dashed trigger underline.
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// Plain, but dimmed while pressed, so a finger can see which word it's on before letting go.
private struct KasusChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// A chip's tap area: the chip grown into half the gap to each neighbour.
private struct KasusChipHitArea: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: -KasusChipMetrics.wordSpacing / 2, dy: -KasusChipMetrics.lineSpacing / 2))
    }
}

// MARK: - Word text

/// A word with the punctuation glued to it, as one `Text`: „ in front, , . ? behind, and a
/// class-style tag („(m)“, „(pl)“) between the word and its punctuation, so „Drucker (m).“ reads
/// like the worksheet. Only the word itself takes the strikethrough.
enum KasusWordText {
    static func text(_ word: KasusWord, foreground: Color? = nil, strikethrough: Bool = false,
                     tag: String? = nil, tagColor: Color = .secondary) -> Text {
        Text(attributed(word, foreground: foreground, strikethrough: strikethrough, tag: tag, tagColor: tagColor))
    }

    static func attributed(_ word: KasusWord, foreground: Color? = nil, strikethrough: Bool = false,
                           tag: String? = nil, tagColor: Color = .secondary) -> AttributedString {
        var out = AttributedString(word.leading)
        var body = AttributedString(word.text)
        if let foreground { body.foregroundColor = foreground }
        if strikethrough {
            body.strikethroughStyle = Text.LineStyle(pattern: .solid, color: .secondary)
        }
        out += body
        if let tag {
            // A no-break space, so the tag never wraps away from its noun.
            var run = AttributedString("\u{00A0}" + tag)
            run.font = .footnote.weight(.bold)
            run.foregroundColor = tagColor
            out += run
        }
        out += AttributedString(word.trailing)
        return out
    }
}
