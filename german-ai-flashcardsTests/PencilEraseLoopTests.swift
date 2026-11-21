//
//  PencilEraseLoopTests.swift
//  german-ai-flashcardsTests
//
//  Circle to erase (Features/Shared/Pencil/PencilEraseLoop.swift): a loop drawn with the eraser
//  clears what it holds, while rubbing back and forth only rubs. These hold the line between the
//  two, and which strokes a loop takes.
//

#if canImport(UIKit)
import CoreGraphics
import Foundation
import PencilKit
import Testing
import UIKit
@testable import Die_Kartei

@MainActor
@Suite struct PencilEraseLoopTests {

    private func loop(center: CGPoint = CGPoint(x: 200, y: 200), rx: CGFloat = 80, ry: CGFloat = 80,
                      turns: CGFloat = 1) -> [CGPoint] {
        let steps = Int(120 * turns)
        return (0...steps).map { i in
            let angle = CGFloat(i) / CGFloat(steps) * turns * 2 * .pi
            return CGPoint(x: center.x + rx * cos(angle), y: center.y + ry * sin(angle))
        }
    }

    private func line(from a: CGPoint, to b: CGPoint, step: CGFloat = 5) -> [CGPoint] {
        let length = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
        let count = max(2, Int(length / step))
        return (0...count).map { i in
            let t = CGFloat(i) / CGFloat(count)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    private func stroke(_ points: [CGPoint], mask: UIBezierPath? = nil) -> PKStroke {
        let controls = points.enumerated().map { i, point in
            PKStrokePoint(location: point, timeOffset: Double(i) / 100, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
                        path: PKStrokePath(controlPoints: controls, creationDate: Date()),
                        transform: .identity, mask: mask)
    }

    // MARK: Loop or not

    @Test func aCircleIsALoop() {
        #expect(PencilEraseLoop.isLoop(loop()))
    }

    @Test func aFlatLoopAroundAWordIsALoop() {
        #expect(PencilEraseLoop.isLoop(loop(rx: 90, ry: 30)))
    }

    @Test func aLoopThatOvershootsItsStartStillCounts() {
        #expect(PencilEraseLoop.isLoop(loop(turns: 1.25)))
    }

    @Test func aLoopThatStopsShortStillCounts() {
        #expect(PencilEraseLoop.isLoop(loop(turns: 0.9)))
    }

    @Test func rubbingBackAndForthIsNotALoop() {
        var scrub: [CGPoint] = []
        for pass in 0..<8 {
            let y = 200 + CGFloat(pass) * 3
            let (from, to) = pass.isMultiple(of: 2) ? (CGFloat(100), CGFloat(220)) : (CGFloat(220), CGFloat(100))
            scrub += line(from: CGPoint(x: from, y: y), to: CGPoint(x: to, y: y + 3))
        }
        #expect(!PencilEraseLoop.isLoop(scrub))
    }

    @Test func aStraightSwipeIsNotALoop() {
        #expect(!PencilEraseLoop.isLoop(line(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 140))))
    }

    @Test func aHalfCircleIsNotALoop() {
        #expect(!PencilEraseLoop.isLoop(loop(turns: 0.5)))
    }

    @Test func aTinyCircleIsNotALoop() {
        #expect(!PencilEraseLoop.isLoop(loop(rx: 6, ry: 6)))
    }

    @Test func aLoopDrawnTheOtherWayRoundCounts() {
        #expect(PencilEraseLoop.isLoop(loop().reversed()))
    }

    // MARK: What a loop takes

    @Test func theLoopTakesWhatIsInsideAndLeavesTheRest() {
        let around = loop(rx: 90, ry: 40)
        let drawing = PKDrawing(strokes: [
            stroke(line(from: CGPoint(x: 150, y: 200), to: CGPoint(x: 250, y: 205))),  // inside
            stroke(line(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 400, y: 200))),  // under half inside
            stroke(line(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 560, y: 500))),  // far away
        ])
        #expect(PencilEraseLoop.enclosedStrokes(in: drawing, loop: around) == IndexSet([0]))
    }

    @Test func theMiddleOfALoopDrawnOneAndAQuarterTimesIsInside() {
        let around = loop(rx: 90, ry: 40, turns: 1.25)
        let drawing = PKDrawing(strokes: [stroke(line(from: CGPoint(x: 160, y: 200), to: CGPoint(x: 240, y: 200)))])
        #expect(PencilEraseLoop.enclosedStrokes(in: drawing, loop: around) == IndexSet([0]))
    }

    @Test func aRubbedStrokeIsJudgedByWhatStillShows() {
        let around = loop(rx: 90, ry: 40)
        // Mostly outside the loop, but the eraser left only the part inside it.
        let long = line(from: CGPoint(x: 150, y: 200), to: CGPoint(x: 450, y: 200))
        let visible = UIBezierPath(rect: CGRect(x: 140, y: 180, width: 140, height: 40))
        let drawing = PKDrawing(strokes: [stroke(long), stroke(long, mask: visible)])
        #expect(PencilEraseLoop.enclosedStrokes(in: drawing, loop: around) == IndexSet([1]))
    }
}
#endif
