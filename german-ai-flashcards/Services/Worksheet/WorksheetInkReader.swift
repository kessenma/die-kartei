//
//  WorksheetInkReader.swift
//  german-ai-flashcards
//
//  Reading what the learner wrote with the Pencil, so the optional check can judge it. For each
//  blank (and the line under a sentence task) the ink near it — and only the ink: her printed
//  slide is left out — is drawn onto white and handed to Vision's on-device text recognizer. What
//  comes back is a reading to confirm, never an answer: the check screen shows each crop beside
//  its reading, unsure ones first, and only confirmed text is graded. Handwritten umlauts and
//  short words like "dem" are exactly where recognition slips, which is why.
//
//  Language correction is off: it "fixes" a lone "dem" or "des" into some longer word.
//  Strikes and circles on a printed "der / den" are not read; the learner taps the choice.
//
//  A matching exercise's single letter is read a second way when the first finds nothing
//  (`InkLetterReading`: Vision returns nothing for most lone letters), and every reading of a
//  closed set is matched to the sheet's own answers. Ink that still can't be read comes back as
//  an unread reading, never dropped: the learner picks or types it.
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

/// What the recognizer made of the ink at one blank.
nonisolated struct WorksheetInkReading: Identifiable, @unchecked Sendable {
    var key: String
    var page: Int
    /// Best first. Empty when there is ink at the blank but nothing could be read from it: the
    /// learner types it or picks one of `options`. Ink is never dropped without a word.
    var candidates: [String]
    /// Vision's confidence in the first candidate, 0…1.
    var confidence: Float
    /// The ink that was read, on white, for the learner to compare.
    var image: CGImage?
    /// The sheet's own answers when the blank takes one of a set (a matching exercise's letters,
    /// a word bank), offered as one-tap picks.
    var options: [String] = []

    var id: String { key }
    /// Below this the confirm screen asks rather than pre-accepting.
    static let sureEnough: Float = 0.6
    var best: String { candidates.first ?? "" }
    var isUnread: Bool { candidates.isEmpty }
    var isSure: Bool { !candidates.isEmpty && confidence >= Self.sureEnough }
}

nonisolated enum WorksheetInkReader {

    /// Where the answer to a blank would be written, in the canvas's space (page points, origin
    /// top-left): the blank itself, a little beyond it to the right, and a line's height above,
    /// since handwriting rides above an underline and runs longer than "___".
    static func region(for key: String, part: WorksheetPagePart) -> CGRect? {
        guard let geometry = part.geometry else { return nil }
        let bounds = part.bounds
        let rect: CGRect
        if let gap = geometry.gaps[key] {
            let h = gap.height
            rect = CGRect(x: gap.minX - h * 0.4, y: gap.minY - h * 0.35,
                          width: gap.width + h * 3, height: h * 2.1)
        } else if key.hasSuffix(".w"), let item = geometry.items[String(key.dropLast(2))] {
            let h = item.height
            rect = CGRect(x: item.minX, y: item.minY - h * 2.2, width: bounds.maxX - item.minX - h, height: h * 2.2)
        } else {
            return nil
        }
        // Page space (y-up) → canvas space (y-down).
        return CGRect(x: rect.minX - bounds.minX, y: bounds.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    #if canImport(PencilKit) && canImport(Vision)
    /// Readings for every key that has ink at its blank, read or not. Runs the recognizer once per
    /// blank (twice for a letter it can't read at first); call it off the main actor. `allowed`
    /// holds the sheet's own answers for a blank that takes one of a set.
    static func read(ink: Data, page: Int, part: WorksheetPagePart, keys: [String],
                     allowed: [String: [String]] = [:]) -> [WorksheetInkReading] {
        // Highlighting is not handwriting: marker strokes are left out of what is read.
        guard let inked = try? PKDrawing(data: ink) else { return [] }
        let drawing = PKDrawing(strokes: inked.strokes.filter { $0.ink.inkType != .marker })
        guard !drawing.strokes.isEmpty else { return [] }
        let regions = keys.compactMap { key in region(for: key, part: part).map { (key, $0) } }
        let owned = assign(drawing.strokes, to: regions)
        var out: [WorksheetInkReading] = []
        for (key, area) in regions {
            guard let strokes = owned[key], !strokes.isEmpty else { continue }
            // Only this blank's own strokes, and all of each: a letter written high above the line
            // isn't cut off, and the rows above and below stay out.
            let own = PKDrawing(strokes: strokes)
            let crop = area.union(bounds(of: strokes, near: area) ?? area)
            guard let image = inkOnWhite(own, area: crop) else { continue }
            var (candidates, confidence) = recognize(image)
            candidates = candidates.map(InkLetterReading.foldLookalikes)
            let options = allowed[key] ?? []
            if isLetters(options) {
                // A matching exercise: the answer is one of the sheet's letters, or not read.
                candidates = snapLetters(candidates, to: options)
                if candidates.isEmpty, let glyph = tightInk(own, strokes: strokes, near: area),
                   let letter = InkLetterReading.read(glyph, letters: options) {
                    candidates = [letter.letter]
                    // A clean "CCC" is as good as a word read; anything else is asked about.
                    confidence = letter.isClean ? max(letter.confidence, WorksheetInkReading.sureEnough) : min(letter.confidence, WorksheetInkReading.sureEnough / 2)
                }
            } else if !options.isEmpty, !candidates.isEmpty {
                // A word bank: put the sheet's own spelling first, and ask about anything not in it
                // (a misreading, or a word she didn't offer).
                if let match = options.first(where: { WorksheetKeyReader.normalize($0) == WorksheetKeyReader.normalize(candidates[0]) }) {
                    candidates[0] = match
                } else {
                    confidence = min(confidence, WorksheetInkReading.sureEnough / 2)
                }
            }
            out.append(WorksheetInkReading(key: key, page: page, candidates: candidates,
                                           confidence: candidates.isEmpty ? 0 : confidence, image: image,
                                           options: options))
        }
        return out
    }

    /// The sheet's answers are single letters: a matching exercise.
    static func isLetters(_ options: [String]) -> Bool {
        !options.isEmpty && options.allSatisfy { $0.count == 1 && $0.first?.isLetter == true }
    }

    /// Readings of a letter blank, each turned into one of the sheet's letters ("c" → C); a
    /// reading that holds none of them is dropped.
    static func snapLetters(_ candidates: [String], to letters: [String]) -> [String] {
        var out: [String] = []
        for candidate in candidates {
            if let letter = InkLetterReading.vote(candidate, letters: letters), !out.contains(letter) {
                out.append(letter)
            }
        }
        return out
    }

    /// Each stroke to the one blank it overlaps most. Handwriting rides high and runs into the
    /// rows around it ("C" above row 1 dips into row 2's region); read for every region it
    /// touched, one letter turned up at two blanks and two letters at one.
    static func assign(_ strokes: [PKStroke], to regions: [(String, CGRect)]) -> [String: [PKStroke]] {
        var out: [String: [PKStroke]] = [:]
        for stroke in strokes {
            let box = stroke.renderBounds
            var best: (key: String, overlap: CGFloat)?
            for (key, area) in regions {
                let shared = area.intersection(box)
                guard !shared.isNull else { continue }
                // A zero-height stroke (a straight dash) still counts by its length.
                let overlap = max(shared.width, 0.5) * max(shared.height, 0.5)
                if best == nil || overlap > best!.overlap { best = (key, overlap) }
            }
            if let best { out[best.key, default: []].append(stroke) }
        }
        return out
    }

    /// Where a blank's own strokes are, kept to around the blank (a stroke reaching far away, a
    /// line across the page, is clipped).
    static func bounds(of strokes: [PKStroke], near area: CGRect) -> CGRect? {
        let bounds = strokes.map(\.renderBounds).reduce(CGRect.null) { $0.union($1) }
            .intersection(area.insetBy(dx: -area.height * 0.5, dy: -area.height * 0.5))
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        return bounds
    }

    /// The strokes at a blank, cropped to themselves and scaled so the letter is `glyphHeight`
    /// pixels tall: what `InkLetterReading` reads.
    static func tightInk(_ drawing: PKDrawing, strokes: [PKStroke], near area: CGRect) -> CGImage? {
        guard let bounds = bounds(of: strokes, near: area) else { return nil }
        let scale = min(max(InkLetterReading.glyphHeight / bounds.height, 0.5), 8)
        return inkOnWhite(drawing, area: bounds, scale: scale)
    }

    /// The ink inside `area` at 3×, composited on white so the recognizer sees dark on light.
    static func inkOnWhite(_ drawing: PKDrawing, area: CGRect, scale: CGFloat = 3) -> CGImage? {
        #if canImport(UIKit)
        var rendered: CGImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            rendered = drawing.image(from: area, scale: scale).cgImage
        }
        guard let ink = rendered else { return nil }
        #else
        guard let ink = drawing.image(from: area, scale: scale).cgImage else { return nil }
        #endif
        guard let ctx = CGContext(data: nil, width: ink.width, height: ink.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: ink.width, height: ink.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(full)
        ctx.draw(ink, in: full)
        return ctx.makeImage()
    }

    /// Up to three readings of the whole crop, best first, and the confidence in the best.
    static func recognize(_ image: CGImage) -> ([String], Float) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["de-DE"]
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results, !observations.isEmpty else { return ([], 0) }
        // Left to right, top to bottom, as written.
        let ordered = observations.sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.25
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        let best = ordered.compactMap { $0.topCandidates(1).first }
        guard !best.isEmpty else { return ([], 0) }
        let first = best.map(\.string).joined(separator: " ")
        let confidence = best.map(\.confidence).min() ?? 0
        var candidates = [first]
        // Alternatives only make sense for a single word; a sentence keeps its one reading.
        if ordered.count == 1 {
            for alternative in ordered[0].topCandidates(3).dropFirst() where !candidates.contains(alternative.string) {
                candidates.append(alternative.string)
            }
        }
        return (candidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }, confidence)
    }
    #endif
}
