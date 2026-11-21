//
//  JournalInkReader.swift
//  german-ai-flashcards
//
//  Reading a page of handwriting into lines of text, for the learner to confirm before the tutor
//  sees it. The worksheet reader (`WorksheetInkReader`) reads the ink near one blank; a journal
//  page is prose, so this one reads the whole page in bands, keeps Vision's text lines in reading
//  order, and joins them into a transcript with a paragraph break where a rule was skipped.
//
//  The page is read in 1024-point bands at 2×, never as one tall bitmap, so a long page costs the
//  same memory as a short one, and all of it happens before the tutor is loaded (one heavy
//  resident, docs/MEMORY.md). Language correction is off by default: on, Vision smooths a
//  misspelt word into a dictionary word, which hides exactly what the check should see. A toggle
//  in the Pencil gear turns it on for a hand it keeps misreading.
//
//  Only ever a reading to confirm, never an answer: the confirm sheet shows each line's crop
//  beside its text, unsure ones marked, and only confirmed text becomes the entry.
//

import CoreGraphics
import Foundation
#if canImport(PencilKit)
import PencilKit
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif

/// One line of handwriting as Vision read it.
nonisolated struct JournalInkLine: Identifiable, @unchecked Sendable {
    var id: Int
    /// Best reading.
    var text: String
    /// Best first, including `text`; alternatives only for a line Vision saw as one piece.
    var candidates: [String]
    /// Vision's confidence in the best reading, 0…1 (the least confident piece of the line).
    var confidence: Float
    /// The ink of this line on white, for the learner to compare.
    var image: CGImage?
    /// Where the line sits on the page, in page points with the origin top-left.
    var box: CGRect

    static let sureEnough: Float = 0.6
    var isSure: Bool { confidence >= Self.sureEnough }
}

nonisolated enum JournalInkReader {

    /// The page is read in bands this tall, overlapping so a line on a seam is read whole.
    static let bandHeight: CGFloat = 1024
    static let bandOverlap: CGFloat = 96
    static let scale: CGFloat = 2
    /// The ruled paper's pitch (`PencilBlankPaper`), which is also how far apart two lines of
    /// handwriting sit.
    static let rulePitch: CGFloat = 28

    #if canImport(PencilKit) && canImport(Vision)
    /// Every line of handwriting on the page, top to bottom. Call it off the main actor.
    static func read(ink: Data, pageWidth: CGFloat, pageHeight: CGFloat, languageCorrection: Bool) -> [JournalInkLine] {
        guard let inked = try? PKDrawing(data: ink) else { return [] }
        // Highlighting is not handwriting.
        let drawing = PKDrawing(strokes: inked.strokes.filter { $0.ink.inkType != .marker })
        guard !drawing.strokes.isEmpty else { return [] }

        struct Piece {
            var candidates: [(String, Float)]
            var box: CGRect
        }
        var pieces: [Piece] = []

        var y: CGFloat = 0
        while y < pageHeight {
            let band = CGRect(x: 0, y: y, width: pageWidth, height: min(bandHeight, pageHeight - y))
            defer { y += bandHeight - bandOverlap }
            guard drawing.strokes.contains(where: { $0.renderBounds.intersects(band) }),
                  let image = WorksheetInkReader.inkOnWhite(drawing, area: band, scale: scale) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = languageCorrection
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            guard (try? handler.perform([request])) != nil, let observations = request.results else { continue }
            for observation in observations {
                let top = observation.topCandidates(3)
                guard let best = top.first, !best.string.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                // Vision's box is normalized with the origin bottom-left; the page's origin is top-left.
                let bb = observation.boundingBox
                let box = CGRect(x: band.minX + bb.minX * band.width,
                                 y: band.minY + (1 - bb.maxY) * band.height,
                                 width: bb.width * band.width,
                                 height: bb.height * band.height)
                let piece = Piece(candidates: top.map { ($0.string, $0.confidence) }, box: box)
                // The same line read in two overlapping bands: keep the surer reading.
                if let twin = pieces.firstIndex(where: { overlaps($0.box, box) }) {
                    if best.confidence > pieces[twin].candidates.first?.1 ?? 0 { pieces[twin] = piece }
                } else {
                    pieces.append(piece)
                }
            }
        }
        guard !pieces.isEmpty else { return [] }

        // Reading order, then pieces on one rule become one line.
        pieces.sort { abs($0.box.midY - $1.box.midY) > rulePitch / 2 ? $0.box.midY < $1.box.midY : $0.box.minX < $1.box.minX }
        var groups: [[Piece]] = []
        for piece in pieces {
            if let last = groups.last, let anchor = last.first, abs(anchor.box.midY - piece.box.midY) <= rulePitch / 2 {
                groups[groups.count - 1].append(piece)
            } else {
                groups.append([piece])
            }
        }

        return groups.enumerated().map { index, group in
            let ordered = group.sorted { $0.box.minX < $1.box.minX }
            let text = ordered.compactMap { $0.candidates.first?.0 }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let confidence = ordered.compactMap { $0.candidates.first?.1 }.min() ?? 0
            var candidates = [text]
            if ordered.count == 1 {
                for (alternative, _) in ordered[0].candidates.dropFirst() where !candidates.contains(alternative) {
                    candidates.append(alternative)
                }
            }
            let box = ordered.dropFirst().reduce(ordered[0].box) { $0.union($1.box) }
            let pad = box.height * 0.4
            let crop = box.insetBy(dx: -pad, dy: -pad).intersection(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            let image = WorksheetInkReader.inkOnWhite(drawing, area: crop, scale: scale)
            return JournalInkLine(id: index, text: text, candidates: candidates, confidence: confidence,
                                  image: image, box: box)
        }
    }

    /// Two boxes that are the same line seen twice: on one rule, and sharing most of their width.
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        guard abs(a.midY - b.midY) <= rulePitch / 2 else { return false }
        let shared = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        return shared > 0.6 * min(a.width, b.width)
    }
    #endif

    /// The lines as one text: a space between lines on consecutive rules, a paragraph break where
    /// a rule was skipped. `edits` holds the learner's corrections by line id.
    static func transcript(from lines: [JournalInkLine], edits: [Int: String] = [:]) -> String {
        var out = ""
        var previous: JournalInkLine?
        for line in lines {
            let text = (edits[line.id] ?? line.text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let previous {
                let gap = line.box.midY - previous.box.midY
                out += gap > 1.6 * rulePitch ? "\n\n" : " "
            }
            out += text
            previous = line
        }
        return out
    }
}
