//
//  HangmanFlatView.swift
//  german-ai-flashcards
//
//  The three motifs in 2D. Nobody hangs: each is six parts that come or go as the misses mount.
//
//  This is the twin the house rules require for Stills Only and Reduce Motion, and it is also what
//  ships first — the 3D canvas is an upgrade over this, never a prerequisite. Drawn with a `Canvas`
//  of rectangles and circles, which is both the Bauhaus vocabulary and cheap enough to sit under a
//  keyboard without costing a frame.
//

import SwiftUI

struct HangmanFlatView: View {
    let motif: HangmanMotif
    let misses: Int
    var maxMisses: Int = HangmanState.maxMisses
    var tint: Color = FigurScene.defaultTint
    /// Die Figur's mood. Drawn, not animated — this view never holds a display link.
    var mood: Mood = .warten

    enum Mood { case warten, jubel, kummer }

    private var remaining: Int { max(0, maxMisses - misses) }

    var body: some View {
        Canvas { context, size in
            let ground = size.height * 0.88
            let unit = min(size.width, size.height) / 10

            context.stroke(
                Path { $0.move(to: CGPoint(x: unit, y: ground))
                        $0.addLine(to: CGPoint(x: size.width - unit, y: ground)) },
                with: .color(tint.opacity(0.35)), lineWidth: 2
            )

            switch motif {
            case .turm:    drawTurm(&context, size: size, ground: ground, unit: unit)
            case .ballon:  drawBallon(&context, size: size, ground: ground, unit: unit)
            case .geruest: drawGeruest(&context, size: size, ground: ground, unit: unit)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch mood {
        case .jubel:  "\(motif.germanTitle): gewonnen"
        case .kummer: "\(motif.germanTitle): verloren"
        case .warten: "\(motif.germanTitle): \(remaining) von \(maxMisses) übrig"
        }
    }

    // MARK: - Die Figur

    /// Six rigid parts, same vocabulary as the Blender rig: two legs, torso, two arms, head.
    private func drawFigur(_ context: inout GraphicsContext, feet: CGPoint, unit: CGFloat) {
        let legs = unit * 1.1, torso = unit * 1.3, head = unit * 0.42
        let slump = mood == .kummer ? unit * 0.22 : 0
        let hip = CGPoint(x: feet.x, y: feet.y - legs + slump)
        let shoulder = CGPoint(x: hip.x, y: hip.y - torso)

        for side in [-1.0, 1.0] {
            context.stroke(Path {
                $0.move(to: hip)
                $0.addLine(to: CGPoint(x: feet.x + unit * 0.22 * side, y: feet.y))
            }, with: .color(tint), lineWidth: unit * 0.17)
        }
        context.stroke(Path { $0.move(to: hip); $0.addLine(to: shoulder) },
                       with: .color(tint), lineWidth: unit * 0.3)

        // Arms: up for a win, down for a loss, out to the sides while waiting.
        let armDrop: CGFloat = mood == .jubel ? -unit * 0.75 : (mood == .kummer ? unit * 0.7 : unit * 0.2)
        for side in [-1.0, 1.0] {
            context.stroke(Path {
                $0.move(to: shoulder)
                $0.addLine(to: CGPoint(x: shoulder.x + unit * 0.62 * side, y: shoulder.y + armDrop))
            }, with: .color(tint), lineWidth: unit * 0.15)
        }

        let headCentre = CGPoint(x: shoulder.x, y: shoulder.y - head - unit * 0.1)
        context.fill(
            Path(ellipseIn: CGRect(x: headCentre.x - head, y: headCentre.y - head,
                                   width: head * 2, height: head * 2)),
            with: .color(tint)
        )
    }

    // MARK: - Der Turm

    /// Die Figur stands on a block tower; every miss takes the block under its feet.
    private func drawTurm(_ context: inout GraphicsContext, size: CGSize, ground: CGFloat,
                          unit: CGFloat) {
        let blockHeight = unit * 0.62, blockWidth = unit * 2.4
        let centre = size.width / 2

        for index in 0..<remaining {
            let rect = CGRect(x: centre - blockWidth / 2,
                              y: ground - blockHeight * CGFloat(index + 1),
                              width: blockWidth, height: blockHeight - 2)
            context.fill(Path(roundedRect: rect, cornerRadius: 2),
                         with: .color(tint.opacity(index.isMultiple(of: 2) ? 0.85 : 0.6)))
        }
        // No ghost outlines for the blocks that are gone: as the tower shrinks the figure
        // descends into exactly that space, and drawing both put it inside a cage. The dots in
        // the top bar already say how many tries are left.

        drawFigur(&context, feet: CGPoint(x: centre, y: ground - blockHeight * CGFloat(remaining)),
                  unit: unit)
    }

    // MARK: - Der Ballon

    /// Die Figur rides a balloon that sinks a little with every miss.
    ///
    /// The envelope is placed above the **figure's head**, not just above the basket: sized off
    /// the basket alone it deflates straight onto the passenger. Every span is a fraction of the
    /// canvas so the full-lift balloon still fits inside the frame.
    private func drawBallon(_ context: inout GraphicsContext, size: CGSize, ground: CGFloat,
                            unit: CGFloat) {
        let centre = size.width / 2
        let lift = CGFloat(remaining) / CGFloat(maxMisses)
        let figurUnit = unit * 0.55
        let figurHeight = figurUnit * 3.3

        let basketY = ground - unit * 0.4 - lift * (size.height * 0.22)
        let basket = CGRect(x: centre - unit * 0.6, y: basketY,
                            width: unit * 1.2, height: unit * 0.45)

        // The envelope deflates as well as sinks, so a near-loss reads at a glance.
        let radius = unit * (0.6 + 0.45 * lift)
        let envelopeBottom = basketY - figurHeight - unit * 0.25
        let envelope = CGRect(x: centre - radius, y: envelopeBottom - radius * 2,
                              width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: envelope), with: .color(tint.opacity(0.22)))
        context.stroke(Path(ellipseIn: envelope), with: .color(tint.opacity(0.7)), lineWidth: 2)

        // Ropes run from the envelope's shoulders down past the passenger to the basket.
        for side in [-1.0, 1.0] {
            context.stroke(Path {
                $0.move(to: CGPoint(x: centre + radius * 0.7 * side, y: envelope.maxY - radius * 0.3))
                $0.addLine(to: CGPoint(x: basket.midX + basket.width * 0.5 * side, y: basket.minY))
            }, with: .color(tint.opacity(0.45)), lineWidth: 1)
        }

        context.fill(Path(roundedRect: basket, cornerRadius: 2), with: .color(tint.opacity(0.85)))
        drawFigur(&context, feet: CGPoint(x: centre, y: basket.minY), unit: figurUnit)
    }

    // MARK: - Das Gerüst

    /// Beams assemble over six misses while die Figur stands beside them, watching.
    ///
    /// Deliberately a **symmetric frame**: two posts, two crossbeams and a brace. The first shape
    /// tried here — one post, one crossbeam, a short drop at the end — rebuilt a gallows exactly,
    /// which is the thing this motif exists to avoid. Nothing may hang off the end.
    private func drawGeruest(_ context: inout GraphicsContext, size: CGSize, ground: CGFloat,
                             unit: CGFloat) {
        let left = size.width * 0.42
        let right = size.width * 0.80
        let top = ground - unit * 3.6
        let middle = ground - unit * 1.8

        // One beam per miss, in the order scaffolding actually goes up.
        let beams: [(CGPoint, CGPoint)] = [
            // Footings, both posts at once, so neither side ever stands alone.
            (CGPoint(x: left - unit * 0.4, y: ground), CGPoint(x: right + unit * 0.4, y: ground)),
            (CGPoint(x: left, y: ground), CGPoint(x: left, y: middle)),
            (CGPoint(x: right, y: ground), CGPoint(x: right, y: middle)),
            (CGPoint(x: left, y: middle), CGPoint(x: right, y: middle)),
            (CGPoint(x: left, y: middle), CGPoint(x: left, y: top)),
            (CGPoint(x: left, y: top), CGPoint(x: right, y: top)),
        ]

        for (index, beam) in beams.enumerated() {
            let placed = index < misses
            context.stroke(Path { $0.move(to: beam.0); $0.addLine(to: beam.1) },
                           with: .color(tint.opacity(placed ? 0.85 : 0.12)),
                           lineWidth: placed ? unit * 0.18 : 1)
        }

        // The right post only rises to the middle, so the top beam ends on open air rather than
        // over a drop — a scaffold under construction, not a frame with something hanging in it.
        drawFigur(&context, feet: CGPoint(x: size.width * 0.18, y: ground), unit: unit)
    }
}

#Preview("Turm") {
    VStack {
        ForEach(0..<4) { misses in
            HangmanFlatView(motif: .turm, misses: misses * 2).frame(height: 150)
        }
    }
}

#Preview("Ballon · Gerüst") {
    HStack {
        HangmanFlatView(motif: .ballon, misses: 3).frame(height: 200)
        HangmanFlatView(motif: .geruest, misses: 4).frame(height: 200)
    }
}
