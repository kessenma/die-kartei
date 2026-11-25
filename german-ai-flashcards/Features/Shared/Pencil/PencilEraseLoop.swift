//
//  PencilEraseLoop.swift
//  german-ai-flashcards
//
//  Circle to erase: with the eraser, a loop drawn around a word clears every stroke inside it.
//  The eraser itself is PencilKit's bitmap eraser, so it rubs out whatever it passes over either
//  way; this only decides, when the eraser lifts, whether its path was a loop and what it held.
//
//  Pure geometry in drawing space, so the tests can hold the line between a loop and a scrub.
//  The numbers are a first guess, tuned on a device:
//   • a loop turns through at least 270° in total; a back-and-forth scrub nets about 0°;
//   • it comes back near where it started (anywhere in its last 40%, so a loop that overshoots
//     its start still counts);
//   • it encloses real area: a scrub's shoelace area cancels out.
//  Inside is the nonzero winding rule, not even-odd, so a loop drawn one and a quarter times
//  still holds its middle.
//

import CoreGraphics
import Foundation

enum PencilEraseLoop {

    /// Shorter than this is a tap or a nudge, not a loop.
    static let minimumLength: CGFloat = 60
    /// Total turning, in radians.
    static let minimumTurning: CGFloat = .pi * 1.5
    /// Enclosed area against the bounding box: a circle is 0.785, a scrub close to 0.
    static let minimumFill: CGFloat = 0.35
    /// A stroke goes when this share of its points is inside the loop.
    static let enclosedShare: Double = 0.7

    static func isLoop(_ points: [CGPoint]) -> Bool {
        let path = resampled(points, spacing: 4)
        guard path.count >= 8, let first = path.first else { return false }
        let box = bounds(of: path)
        guard box.width > 8, box.height > 8 else { return false }

        let length = zip(path, path.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
        guard length >= minimumLength else { return false }

        let diagonal = (box.width * box.width + box.height * box.height).squareRoot()
        let reach = max(30, diagonal * 0.3)
        let tail = path[(path.count * 6 / 10)...]
        guard tail.contains(where: { distance($0, first) <= reach }) else { return false }

        guard abs(turning(path)) >= minimumTurning else { return false }
        return abs(area(path)) >= minimumFill * box.width * box.height
    }

    /// True when `point` is inside the closed `polygon` (nonzero winding).
    static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var winding = 0
        for (a, b) in zip(polygon, polygon.dropFirst() + [polygon[0]]) {
            let side = (b.x - a.x) * (point.y - a.y) - (point.x - a.x) * (b.y - a.y)
            if a.y <= point.y {
                if b.y > point.y, side > 0 { winding += 1 }
            } else if b.y <= point.y, side < 0 {
                winding -= 1
            }
        }
        return winding != 0
    }

    /// True when most of `points` (a stroke's visible points) are inside `loop`.
    static func encloses(_ loop: [CGPoint], _ points: [CGPoint]) -> Bool {
        guard !points.isEmpty else { return false }
        let inside = points.filter { contains(loop, $0) }.count
        return Double(inside) >= Double(points.count) * enclosedShare
    }

    // MARK: - Geometry

    /// Even spacing, so a slow wobble doesn't add turning that a fast stroke wouldn't.
    static func resampled(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var out = [last]
        for point in points.dropFirst() where distance(point, last) >= spacing {
            out.append(point)
            last = point
        }
        return out
    }

    /// The signed sum of the angles between successive segments.
    static func turning(_ path: [CGPoint]) -> CGFloat {
        guard path.count >= 3 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<(path.count - 1) {
            let a = CGVector(dx: path[i].x - path[i - 1].x, dy: path[i].y - path[i - 1].y)
            let b = CGVector(dx: path[i + 1].x - path[i].x, dy: path[i + 1].y - path[i].y)
            total += atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy)
        }
        return total
    }

    /// The shoelace area of the path closed back to its start.
    static func area(_ path: [CGPoint]) -> CGFloat {
        guard path.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for (a, b) in zip(path, path.dropFirst() + [path[0]]) {
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}

#if canImport(UIKit)
import PencilKit

extension PencilEraseLoop {
    /// The strokes of `drawing` that `loop` holds, by index.
    static func enclosedStrokes(in drawing: PKDrawing, loop: [CGPoint]) -> IndexSet {
        let box = bounds(of: loop)
        var hit = IndexSet()
        for (index, stroke) in drawing.strokes.enumerated() where stroke.renderBounds.intersects(box) {
            if encloses(loop, visiblePoints(of: stroke)) { hit.insert(index) }
        }
        return hit
    }

    /// A stroke's points in drawing space. A stroke the eraser already rubbed part of carries a
    /// mask; only what still shows is counted, so the rubbed-out tail outside the loop can't
    /// keep the rest of it on the page.
    static func visiblePoints(of stroke: PKStroke) -> [CGPoint] {
        stroke.path.interpolatedPoints(by: .distance(4)).compactMap { point in
            if let mask = stroke.mask, !mask.contains(point.location) { return nil }
            return point.location.applying(stroke.transform)
        }
    }
}
#endif
