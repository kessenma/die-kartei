//
//  PencilWordMarking.swift
//  german-ai-flashcards
//
//  Marking words with the Apple Pencil in a text you read: tap a word, run a highlighter (or an
//  underline) over a few, or draw a loop around them. This decides, when the Pencil lifts, which
//  of the text's words the stroke meant. Pure geometry over the words' boxes, so the tests can pin
//  a tap, a swipe and a loop apart; the loop test is the one „circle to erase“ uses
//  (`PencilEraseLoop.isLoop`).
//

import CoreGraphics
import Foundation

enum PencilWordMarking {

    enum Gesture: Equatable {
        case tap(CGPoint)
        case loop([CGPoint])
        case stroke([CGPoint])
    }

    /// Shorter than this, end to end and along the way, is a tap.
    static let tapTravel: CGFloat = 10

    static func classify(_ points: [CGPoint]) -> Gesture? {
        guard let first = points.first else { return nil }
        let travel = zip(points, points.dropFirst()).reduce(CGFloat(0)) { $0 + distance($1.0, $1.1) }
        if travel < tapTravel { return .tap(first) }
        if PencilEraseLoop.isLoop(points) { return .loop(points) }
        return .stroke(points)
    }

    /// The indices of the words the gesture marks, in text order. `words[i]` is the boxes of word
    /// i (one per line it runs over), in the text's own coordinates.
    static func hits(_ gesture: Gesture, words: [[CGRect]]) -> [Int] {
        switch gesture {
        case .tap(let point):
            if let inside = words.firstIndex(where: { $0.contains { $0.insetBy(dx: -3, dy: -3).contains(point) } }) {
                return [inside]
            }
            // A tap just beside a word still means it, within a finger's slack.
            let nearest = words.indices.min { distance(to: words[$0], from: point) < distance(to: words[$1], from: point) }
            if let nearest, distance(to: words[nearest], from: point) <= 12 { return [nearest] }
            return []

        case .loop(let polygon):
            return words.indices.filter { index in
                guard let box = words[index].first else { return false }
                return PencilEraseLoop.contains(polygon, CGPoint(x: box.midX, y: box.midY))
            }

        case .stroke(let points):
            let path = PencilEraseLoop.resampled(points, spacing: 3)
            return words.indices.filter { index in
                words[index].contains { box in
                    // A highlighter runs through the word, an underline just under it.
                    let zone = CGRect(x: box.minX, y: box.minY - box.height * 0.15,
                                      width: box.width, height: box.height * 1.6)
                    return path.contains { zone.contains($0) }
                }
            }
        }
    }

    private static func distance(to boxes: [CGRect], from point: CGPoint) -> CGFloat {
        boxes.map { box in
            let dx = max(box.minX - point.x, 0, point.x - box.maxX)
            let dy = max(box.minY - point.y, 0, point.y - box.maxY)
            return (dx * dx + dy * dy).squareRoot()
        }.min() ?? .greatestFiniteMagnitude
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}

/// What a Pencil mark in a text came to: the words, in order, and — when they run on without a
/// gap — the stretch of text they make, which may be kept as one phrase.
struct PencilWordMark: Equatable {
    let words: [String]
    /// The words as they stand in the text, punctuation between them included; nil for one word or
    /// for words that are not next to each other.
    let span: String?
}
