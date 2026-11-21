//
//  GrammarTaskArtView.swift
//  german-ai-flashcards
//
//  Draws a `GrammarTaskArt`: the shape of one exercise's task, in the row's own colour, so a
//  learner reading „Üben · Practice“ can see what they are about to be asked to do.
//
//  Drawn, not a glyph and not a render. tools/blender/render_all.sh settled the render question —
//  „flat existed for 34pt row icons, which we never built — dimensional shading muds below ~40pt,
//  so small surfaces use SF Symbols instead“ — and a vector drawing is the third option: it doesn't
//  mud, and it says more than a glyph can. The day one of these earns a baked still,
//  `art.assetName` is already the slug, so the swap happens here and nowhere else (the
//  `BauhausIcon` contract, Features/Progress/PyramidView.swift).
//
//  Bare on the row, with no tinted chip behind it. PyramidView learned that a chip „just muddies
//  the alpha edge“, and bare-vs-chip is also what separates a task you can play from a place you
//  can enter — a room, a case or a rule sheet keeps its chip.
//
//  One `Canvas` per row, not a `ZStack` of ten shapes (the same reason `PyramidGlyph` is one): one
//  view instead of ten, dashes and arcs come free, and the drawing is a pure function of
//  (art, size, tint, theme, colorScheme). No `GeometryReader` — it would force a layout pass per
//  row — no `drawingGroup()`, no `RealityView`, so the one-live-scene rule is untouched.
//
//  This is a visible change on Klar. That is not a break of the theme invariant: `.themed*`
//  modifiers are no-ops on Klar, which is about chrome, and the drawing is content — the same
//  distinction TodayView draws for a recommendation's accent.
//
//  Every radius goes through `appTheme.innerRadius`, scaled to the box, so Grundform's bars square
//  off genuinely (it returns 0) and Sanft's soften, with no literal `cornerRadius` anywhere.
//

import SwiftUI

struct GrammarTaskArtView: View {
    let art: GrammarTaskArt
    /// The row's colour: a unit's case colour, a topic's, a preposition group's. Nil resolves the
    /// theme accent the way `.themedScreen()`'s `.tint` does — a `Canvas` can't read `.tint`, so
    /// leaving it to `Color.accentColor` would silently ignore Sanft, Kritzel and Grundform.
    var tint: Color? = nil
    var size: CGFloat = 52

    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelTheme) private var modelTheme
    @Environment(\.colorScheme) private var colorScheme

    private var ink: Color { tint ?? appTheme.accent(model: modelTheme) }
    /// Context strength. A wash over a dark ground reads a notch weaker than over a light one, so
    /// both lift in dark mode — the same „don't naively invert“ rule `GenderPalette` follows.
    private var faint: Double { colorScheme == .dark ? 0.55 : 0.45 }
    private var wash: Double { colorScheme == .dark ? 0.34 : 0.26 }

    /// Which drawings a baked still has been installed for. Resolved once, not per row per render:
    /// nothing ships today, so every lookup is a *miss*, and a miss is the expensive path.
    private static let shipped: Set<GrammarTaskArt> = Set(
        GrammarTaskArt.allCases.filter { UIImage(named: $0.assetName) != nil }
    )

    var body: some View {
        Group {
            // The still hatch, additive: a shipped render wins, a missing one draws the vector.
            if Self.shipped.contains(art) {
                Image(art.assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Canvas { context, box in
                    let draw = GrammarTaskDraw(
                        ctx: context, box: box, ink: ink, faint: faint, wash: wash,
                        radius: { appTheme.innerRadius($0 * box.width / 52) }
                    )
                    draw.paint(art)
                }
            }
        }
        .frame(width: size, height: size)
        // The row's title and subtitle carry the meaning; the drawing is a second telling of it.
        .accessibilityHidden(true)
    }
}

// MARK: - The primitives

/// Six marks, in unit coordinates (0…1 of the box), so 34pt and 52pt are the same drawing and no
/// composition carries a pixel number. Nothing here is lettered: the delivery table in
/// docs/PREPOSITION_3D.md gives matching tiles nothing rather than leak the meaning being tested,
/// and that holds for every launcher drawing.
private struct GrammarTaskDraw {
    let ctx: GraphicsContext
    let box: CGSize
    let ink: Color
    let faint: Double
    let wash: Double
    /// `AppTheme.innerRadius`, scaled to the box.
    let radius: (CGFloat) -> CGFloat

    /// A rect from a unit x/width and a unit *centre* y.
    private func rect(_ x: CGFloat, _ w: CGFloat, y: CGFloat, h: CGFloat) -> CGRect {
        CGRect(x: x * box.width, y: (y - h / 2) * box.height,
               width: w * box.width, height: h * box.height)
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * box.width, y: y * box.height)
    }

    private var hairline: CGFloat { max(1, box.width * 0.035) }

    /// A word: a bar 0.11 of the box thick (≈5.7pt at 52, ≈3.7pt at 34 — above the hairline floor
    /// at both, which is why the row slot is 52 and 34 only ever appears in the preview grid).
    func word(_ x: CGFloat, _ w: CGFloat, y: CGFloat, strength: Double = 1) {
        ctx.fill(Path(roundedRect: rect(x, w, y: y, h: 0.11), cornerRadius: radius(3)),
                 with: .color(ink.opacity(strength)))
    }

    /// A gap: a dashed box, taller than a word, the sentence-chip treatment
    /// (`KasusSentenceChip` — innerRadius(7), a 1.5pt dashed outline).
    func gap(_ x: CGFloat, _ w: CGFloat, y: CGFloat, h: CGFloat = 0.26) {
        ctx.stroke(Path(roundedRect: rect(x, w, y: y, h: h), cornerRadius: radius(7)),
                   with: .color(ink),
                   style: StrokeStyle(lineWidth: hairline,
                                      dash: [box.width * 0.07, box.width * 0.045]))
    }

    /// A block: a solid square for something given, a dash-outlined one for something you supply.
    func block(_ x: CGFloat, _ w: CGFloat, y: CGFloat, h: CGFloat = 0.26,
               filled: Bool = true, strength: Double = 1) {
        let path = Path(roundedRect: rect(x, w, y: y, h: h), cornerRadius: radius(4))
        if filled {
            ctx.fill(path, with: .color(ink.opacity(strength)))
        } else {
            ctx.stroke(path, with: .color(ink.opacity(strength)),
                       style: StrokeStyle(lineWidth: hairline,
                                          dash: [box.width * 0.07, box.width * 0.045]))
        }
    }

    /// A highlighter band: thick, translucent, tilted and overshooting, the way a marker lands.
    func band(_ x: CGFloat, _ w: CGFloat, y: CGFloat, tilt: Angle = .degrees(-2.5)) {
        let r = rect(x, w, y: y, h: 0.30)
        let centre = CGPoint(x: r.midX, y: r.midY)
        let path = Path(roundedRect: r, cornerRadius: radius(2))
            .applying(CGAffineTransform(translationX: -centre.x, y: -centre.y)
                .concatenating(CGAffineTransform(rotationAngle: tilt.radians))
                .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y)))
        ctx.fill(path, with: .color(ink.opacity(wash + 0.06)))
    }

    /// A thin rule under a word: „this one is the one to look at“.
    func rule(_ x: CGFloat, _ w: CGFloat, y: CGFloat) {
        var path = Path()
        path.move(to: point(x, y))
        path.addLine(to: point(x + w, y))
        ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: hairline, lineCap: .round))
    }

    func line(_ from: CGPoint, _ to: CGPoint, strength: Double = 1, dashed: Bool = false) {
        var path = Path()
        path.move(to: point(from.x, from.y))
        path.addLine(to: point(to.x, to.y))
        ctx.stroke(path, with: .color(ink.opacity(strength)),
                   style: StrokeStyle(lineWidth: hairline, lineCap: .round,
                                      dash: dashed ? [box.width * 0.06, box.width * 0.04] : []))
    }

    /// An arrowhead at a unit point. `pointing` is the direction in radians (0 = right).
    func arrowhead(at p: CGPoint, pointing: Angle) {
        let tip = point(p.x, p.y)
        let wing = box.width * 0.075
        var path = Path()
        path.move(to: tip)
        for side in [Angle.degrees(146), Angle.degrees(-146)] {
            let a = pointing.radians + side.radians
            path.addLine(to: CGPoint(x: tip.x + cos(a) * wing, y: tip.y + sin(a) * wing))
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(ink))
    }

    /// An arc over a line, joining two unit x positions: the agreement an exercise is about.
    func arc(fromX: CGFloat, toX: CGFloat, baseY: CGFloat, peakY: CGFloat) {
        var path = Path()
        path.move(to: point(fromX, baseY))
        path.addQuadCurve(to: point(toX, baseY),
                          control: point((fromX + toX) / 2, peakY * 2 - baseY))
        ctx.stroke(path, with: .color(ink.opacity(faint + 0.25)),
                   style: StrokeStyle(lineWidth: hairline, lineCap: .round))
    }

    /// A clock: the ring, one hand, and a swept arc for the time running out.
    func ring(centre c: CGPoint, r: CGFloat, hand: Angle, sweep: Angle) {
        let o = point(c.x, c.y)
        let radiusPt = r * box.width
        ctx.stroke(Path(ellipseIn: CGRect(x: o.x - radiusPt, y: o.y - radiusPt,
                                          width: radiusPt * 2, height: radiusPt * 2)),
                   with: .color(ink.opacity(faint)), style: StrokeStyle(lineWidth: hairline))
        var swept = Path()
        swept.addArc(center: o, radius: radiusPt, startAngle: .degrees(-90),
                     endAngle: .degrees(-90) + sweep, clockwise: false)
        ctx.stroke(swept, with: .color(ink),
                   style: StrokeStyle(lineWidth: hairline * 1.6, lineCap: .round))
        var needle = Path()
        needle.move(to: o)
        needle.addLine(to: CGPoint(x: o.x + cos(hand.radians) * radiusPt * 0.72,
                                   y: o.y + sin(hand.radians) * radiusPt * 0.72))
        ctx.stroke(needle, with: .color(ink), style: StrokeStyle(lineWidth: hairline, lineCap: .round))
    }

    /// A card: the outline, two text lines and a folded corner. Reading, not answering.
    func card(_ x: CGFloat, _ w: CGFloat, y: CGFloat, h: CGFloat, strength: Double = 1) {
        ctx.stroke(Path(roundedRect: rect(x, w, y: y, h: h), cornerRadius: radius(5)),
                   with: .color(ink.opacity(strength)), style: StrokeStyle(lineWidth: hairline))
    }
}

// MARK: - The compositions

private extension GrammarTaskDraw {
    func paint(_ art: GrammarTaskArt) {
        switch art {

        // A sentence, one whole word missing. The gaps either side of the box are the point: what's
        // missing is a word, not a tail (compare `.endingGap`).
        case .wordGap:
            word(0.08, 0.20, y: 0.30)
            word(0.32, 0.14, y: 0.30)
            gap(0.52, 0.34, y: 0.30)
            word(0.08, 0.36, y: 0.72, strength: faint)
            word(0.50, 0.26, y: 0.72, strength: faint)

        // Endungen: the word is there, its tail isn't. The dashed stub butts straight onto the bar,
        // with no leading gap — the one thing that tells it from `.wordGap` at a glance.
        case .endingGap:
            word(0.08, 0.28, y: 0.30)
            gap(0.36, 0.13, y: 0.30, h: 0.20)
            word(0.57, 0.30, y: 0.30, strength: faint)
            word(0.08, 0.22, y: 0.72, strength: faint)
            gap(0.30, 0.12, y: 0.72, h: 0.18)

        // Bau das Wort: the ending snaps onto the stem. Both are blocks of one height, so they read
        // as two pieces of one word; the gap between them is where the ending is about to land.
        case .snapEnding:
            block(0.04, 0.38, y: 0.50, h: 0.26, strength: faint + 0.2)
            block(0.52, 0.18, y: 0.50, h: 0.26)
            line(CGPoint(x: 0.76, y: 0.50), CGPoint(x: 0.83, y: 0.50), strength: faint)
            line(CGPoint(x: 0.87, y: 0.50), CGPoint(x: 0.92, y: 0.50), strength: wash + 0.10)

        // One of these two: a gap, and exactly two candidates under it, one lifted.
        case .pickOfTwo:
            gap(0.30, 0.40, y: 0.24, h: 0.24)
            block(0.16, 0.28, y: 0.68, h: 0.28)
            block(0.56, 0.28, y: 0.76, h: 0.28, filled: false)

        // The verb decides: it's marked, and a bracket reaches from it forward to the gap.
        case .verbDecides:
            word(0.06, 0.17, y: 0.30, strength: faint)
            block(0.28, 0.20, y: 0.30, h: 0.22)
            rule(0.28, 0.20, y: 0.44)
            gap(0.60, 0.32, y: 0.30, h: 0.24)
            line(CGPoint(x: 0.38, y: 0.50), CGPoint(x: 0.38, y: 0.76), strength: faint + 0.2)
            line(CGPoint(x: 0.38, y: 0.76), CGPoint(x: 0.76, y: 0.76), strength: faint + 0.2)
            line(CGPoint(x: 0.76, y: 0.76), CGPoint(x: 0.76, y: 0.56), strength: faint + 0.2)
            arrowhead(at: CGPoint(x: 0.76, y: 0.48), pointing: .degrees(-90))

        // One word is out of true. Misalignment and a ring carry it: no red, because the palette
        // rule forbids marking right/wrong in green/red where genders are coloured.
        case .spotTheOddOne:
            word(0.06, 0.17, y: 0.56, strength: faint)
            word(0.27, 0.15, y: 0.56, strength: faint)
            block(0.46, 0.19, y: 0.36, h: 0.22, filled: false)
            word(0.71, 0.21, y: 0.56, strength: faint)
            ctx.stroke(Path(ellipseIn: CGRect(x: 0.40 * box.width, y: 0.17 * box.height,
                                              width: 0.31 * box.width, height: 0.38 * box.height)),
                       with: .color(ink.opacity(faint)), style: StrokeStyle(lineWidth: hairline * 0.8))

        // The pronoun follows the subject: a solid lead, a later gap, and an arc saying they agree.
        case .followTheSubject:
            block(0.08, 0.20, y: 0.66, h: 0.24)
            word(0.34, 0.14, y: 0.66, strength: faint)
            gap(0.54, 0.30, y: 0.66, h: 0.24)
            arc(fromX: 0.18, toX: 0.69, baseY: 0.52, peakY: 0.22)
            arrowhead(at: CGPoint(x: 0.69, y: 0.50), pointing: .degrees(80))

        // Markieren: a marker laid across two words of a line, overshooting, the way a hand does it.
        case .markWords:
            word(0.08, 0.34, y: 0.20, strength: wash + 0.12)
            word(0.48, 0.22, y: 0.20, strength: wash + 0.12)
            band(0.26, 0.60, y: 0.52)
            word(0.08, 0.14, y: 0.52, strength: faint)
            word(0.30, 0.22, y: 0.52)
            word(0.58, 0.18, y: 0.52)
            word(0.08, 0.26, y: 0.84, strength: wash + 0.12)
            word(0.40, 0.30, y: 0.84, strength: wash + 0.12)

        // Rollen: one sentence in three phrases, each with a blank tag over it. The tags are blank
        // because the roles are the answer.
        case .tagPhrases:
            block(0.07, 0.17, y: 0.28, h: 0.18)
            block(0.33, 0.21, y: 0.28, h: 0.18, filled: false, strength: faint + 0.25)
            block(0.64, 0.21, y: 0.28, h: 0.18, filled: false, strength: faint + 0.25)
            word(0.07, 0.19, y: 0.66, strength: faint)
            word(0.33, 0.23, y: 0.66, strength: faint)
            word(0.64, 0.23, y: 0.66, strength: faint)

        // Wer macht was?: the line could read either way, and only the ending tells which.
        case .twoReadings:
            block(0.06, 0.18, y: 0.34, h: 0.24)
            block(0.74, 0.18, y: 0.34, h: 0.24)
            line(CGPoint(x: 0.30, y: 0.72), CGPoint(x: 0.70, y: 0.72), strength: faint)
            arrowhead(at: CGPoint(x: 0.24, y: 0.72), pointing: .degrees(180))
            arrowhead(at: CGPoint(x: 0.76, y: 0.72), pointing: .degrees(0))

        // Die Probe: swap one word in and read it again. Vertical on purpose — the horizontal
        // two-headed arrow is already `CasePalette.wechselSymbol` and means „it depends“.
        case .swapInPlace:
            word(0.34, 0.44, y: 0.24, strength: faint)
            word(0.26, 0.44, y: 0.76)
            line(CGPoint(x: 0.16, y: 0.36), CGPoint(x: 0.16, y: 0.64))
            arrowhead(at: CGPoint(x: 0.16, y: 0.28), pointing: .degrees(-90))
            arrowhead(at: CGPoint(x: 0.16, y: 0.72), pointing: .degrees(90))

        // Pronomen-Brücke: the same job carried across three steps, the last one yours.
        case .threeStepChain:
            block(0.05, 0.20, y: 0.50, h: 0.28)
            line(CGPoint(x: 0.27, y: 0.50), CGPoint(x: 0.34, y: 0.50), strength: faint)
            arrowhead(at: CGPoint(x: 0.37, y: 0.50), pointing: .degrees(0))
            block(0.40, 0.20, y: 0.50, h: 0.28, strength: faint + 0.2)
            line(CGPoint(x: 0.62, y: 0.50), CGPoint(x: 0.69, y: 0.50), strength: faint)
            arrowhead(at: CGPoint(x: 0.72, y: 0.50), pointing: .degrees(0))
            block(0.75, 0.20, y: 0.50, h: 0.28, filled: false)

        // Two lines, one phrase. The ring sits in the upper line (the English), the same slot is
        // marked again below (the German twin), and the dashed drop joins them.
        case .ringOneSpan:
            word(0.06, 0.18, y: 0.26)
            block(0.28, 0.26, y: 0.26, h: 0.22, filled: false)
            word(0.60, 0.20, y: 0.26, strength: faint)
            line(CGPoint(x: 0.41, y: 0.41), CGPoint(x: 0.41, y: 0.59), strength: faint, dashed: true)
            word(0.06, 0.18, y: 0.74, strength: wash + 0.18)
            block(0.28, 0.26, y: 0.74, h: 0.22, strength: faint + 0.25)

        // One phrase, two roads. The road your English takes is struck through, the other one runs.
        case .forkedPath:
            block(0.34, 0.26, y: 0.22, h: 0.24)
            line(CGPoint(x: 0.44, y: 0.36), CGPoint(x: 0.22, y: 0.64), strength: faint + 0.2)
            arrowhead(at: CGPoint(x: 0.19, y: 0.70), pointing: .degrees(128))
            line(CGPoint(x: 0.50, y: 0.36), CGPoint(x: 0.74, y: 0.64), strength: faint + 0.2)
            arrowhead(at: CGPoint(x: 0.77, y: 0.70), pointing: .degrees(52))
            rule(0.10, 0.22, y: 0.86)

        // The question is given at the top; three phrases wait below for the one that answers it.
        case .pickThePhrase:
            block(0.33, 0.34, y: 0.20, h: 0.22)
            arrowhead(at: CGPoint(x: 0.50, y: 0.46), pointing: .degrees(90))
            gap(0.05, 0.26, y: 0.76, h: 0.22)
            gap(0.37, 0.26, y: 0.76, h: 0.22)
            gap(0.69, 0.26, y: 0.76, h: 0.22)

        // Which label does this word take? One word, a row of labels, one of them the answer.
        case .labelOneWord:
            word(0.28, 0.44, y: 0.28)
            block(0.08, 0.22, y: 0.70, h: 0.24, filled: false, strength: faint + 0.2)
            block(0.39, 0.22, y: 0.70, h: 0.24)
            block(0.70, 0.22, y: 0.70, h: 0.24, filled: false, strength: faint + 0.2)

        // Find the pairs: four blocks, one pair already joined. Blank, because the meanings are
        // exactly what the exercise is testing.
        case .matchPairs:
            block(0.08, 0.26, y: 0.28, h: 0.26)
            block(0.66, 0.26, y: 0.28, h: 0.26)
            line(CGPoint(x: 0.34, y: 0.28), CGPoint(x: 0.66, y: 0.28), strength: faint + 0.2)
            block(0.08, 0.26, y: 0.76, h: 0.26, filled: false, strength: faint + 0.25)
            block(0.66, 0.26, y: 0.76, h: 0.26, filled: false, strength: faint + 0.25)

        // A deck to flip through. The stagger is wide enough that three cards read as three.
        case .cardStack:
            card(0.32, 0.54, y: 0.32, h: 0.40, strength: wash + 0.14)
            card(0.21, 0.54, y: 0.50, h: 0.40, strength: faint)
            card(0.10, 0.54, y: 0.68, h: 0.40)
            word(0.18, 0.28, y: 0.63)
            word(0.18, 0.18, y: 0.75, strength: faint)

        // The deck, with cards coming back round: what's due again today.
        case .reviewQueue:
            card(0.22, 0.52, y: 0.56, h: 0.42, strength: faint)
            card(0.14, 0.52, y: 0.66, h: 0.42)
            word(0.22, 0.26, y: 0.64)
            arc(fromX: 0.18, toX: 0.84, baseY: 0.32, peakY: 0.10)
            arrowhead(at: CGPoint(x: 0.84, y: 0.34), pointing: .degrees(80))

        // A short thing to read, not to answer: a card with a folded corner.
        case .ideaCard:
            card(0.18, 0.60, y: 0.50, h: 0.60)
            word(0.26, 0.36, y: 0.42, strength: faint)
            word(0.26, 0.28, y: 0.60, strength: faint)
            line(CGPoint(x: 0.60, y: 0.20), CGPoint(x: 0.78, y: 0.38), strength: faint + 0.2)

        // Lines against a clock. The ring sits beside the stack, never over it — an overlap would
        // need a halo in the theme's surface, and a halo is a bug waiting for a theme to change it.
        case .beatTheClock:
            word(0.05, 0.42, y: 0.22, strength: faint)
            word(0.05, 0.36, y: 0.50, strength: faint)
            word(0.05, 0.44, y: 0.78, strength: faint)
            ring(centre: CGPoint(x: 0.72, y: 0.52), r: 0.22,
                 hand: .degrees(-40), sweep: .degrees(250))

        // Die Tabelle: a grid of cells, one still open, and a block dropping into it. The grid is
        // what tells it from `.snapEnding` — that one is a word, this one is a table.
        case .fillTheGrid:
            for (row, y) in [(0, 0.22), (1, 0.50)] as [(Int, CGFloat)] {
                for (column, x) in [(0, 0.08), (1, 0.38), (2, 0.68)] as [(Int, CGFloat)] {
                    let isOpen = row == 1 && column == 2
                    block(x, 0.24, y: y, h: 0.22, filled: !isOpen,
                          strength: isOpen ? faint + 0.25 : (row == 0 ? wash + 0.16 : faint))
                }
            }
            block(0.68, 0.24, y: 0.88, h: 0.18)
            arrowhead(at: CGPoint(x: 0.80, y: 0.66), pointing: .degrees(-90))
        }
    }
}

// MARK: - Previews

/// The preview that answers the legibility question: every drawing at the row size (52) and at the
/// old chip size (34), in both a case colour and the theme accent, across all four themes. 34 is
/// here as a check, never as a row size.
#Preview("Task art · every drawing · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(GrammarTaskArt.allCases, id: \.self) { art in
                        HStack(spacing: 16) {
                            GrammarTaskArtView(art: art, size: 52)
                            GrammarTaskArtView(art: art, tint: CasePalette.color(.dativ), size: 52)
                            GrammarTaskArtView(art: art, size: 34)
                            GrammarTaskArtView(art: art, tint: CasePalette.color(.dativ), size: 34)
                            Text(art.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding()
            }
            .themedListScreen()
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
}

/// Grundform and Kritzel on a near-black ground: the two themes the dark-mode strengths exist for.
#Preview("Task art · dark") {
    TabView {
        ForEach([AppTheme.grundform, .kritzel]) { theme in
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(GrammarTaskArt.allCases, id: \.self) { art in
                        HStack(spacing: 16) {
                            GrammarTaskArtView(art: art, size: 52)
                            GrammarTaskArtView(art: art, tint: CasePalette.color(.akkusativ), size: 52)
                            GrammarTaskArtView(art: art, size: 34)
                            Text(art.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding()
            }
            .themedListScreen()
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .preferredColorScheme(.dark)
}
