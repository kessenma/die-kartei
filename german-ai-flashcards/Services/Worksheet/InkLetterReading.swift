//
//  InkLetterReading.swift
//  german-ai-flashcards
//
//  One handwritten letter at a matching exercise's blank ("Schreibe den passenden Buchstaben").
//  Vision's text recognizer is built for words: given a lone "C" it usually returns nothing at all
//  (measured on handwriting-like fonts: 4 of 30 single letters read, 26 empty). Shown the same
//  letter three times in a row it reads a "word" ("CCC"), and the letter the copies agree on is
//  the answer (38 of 48, 2 empty). Vision also answers in Cyrillic look-alikes ("ВВВ" for BBB),
//  folded back here.
//
//  Pure Core Graphics + Vision and no app types, so scripts can compile it on its own to measure.
//

import CoreGraphics
import Foundation
#if canImport(Vision)
import Vision
#endif

nonisolated enum InkLetterReading {

    /// Cyrillic letters Vision returns for Latin ones that look the same.
    private static let lookalikes: [Character: Character] = [
        "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "К": "K", "М": "M", "О": "O", "Р": "P",
        "Т": "T", "Х": "X", "а": "a", "с": "c", "е": "e", "о": "o", "р": "p", "х": "x",
    ]

    /// Latin for Cyrillic look-alikes; everything else as it was.
    static func foldLookalikes(_ text: String) -> String {
        String(text.map { lookalikes[$0] ?? $0 })
    }

    /// The one letter of `letters` a reading agrees on: "C", "c", "CCC", "C C" → C. Nil when the
    /// reading holds none of them, or when two of them tie.
    static func vote(_ text: String, letters: [String]) -> String? {
        let allowed = Dictionary(letters.compactMap { option -> (Character, String)? in
            guard option.count == 1, let char = option.uppercased().first else { return nil }
            return (char, option)
        }, uniquingKeysWith: { first, _ in first })
        let counts = Dictionary(grouping: foldLookalikes(text).uppercased().filter { allowed[$0] != nil }, by: { $0 })
            .mapValues(\.count)
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        guard counts.values.filter({ $0 == top.value }).count == 1 else { return nil }
        return allowed[top.key]
    }

    /// A reading of copies all of one capital letter (after folding): "CCC", "C C C". What a
    /// learner writes in a matching exercise; a lowercase "aaa" for a capital D is a misreading.
    static func isClean(_ text: String) -> Bool {
        let letters = foldLookalikes(text).filter { !$0.isWhitespace }
        guard let first = letters.first, first.isUppercase, first.isLetter else { return false }
        return letters.allSatisfy { $0 == first }
    }

    /// The glyph `times` times side by side, a gap of 0.3 of its width apart, on a margin of its
    /// height: how Vision sees a single letter as a word.
    static func tiled(_ glyph: CGImage, times: Int = 3) -> CGImage? {
        let w = CGFloat(glyph.width), h = CGFloat(glyph.height)
        guard w > 0, h > 0, times > 0 else { return nil }
        let step = max(w, h * 0.5) * 1.3
        let margin = h
        let size = CGSize(width: step * CGFloat(times - 1) + w + 2 * margin, height: h + 2 * margin)
        guard let ctx = CGContext(data: nil, width: Int(size.width.rounded(.up)), height: Int(size.height.rounded(.up)),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        for index in 0..<times {
            ctx.draw(glyph, in: CGRect(x: margin + CGFloat(index) * step, y: margin, width: w, height: h))
        }
        return ctx.makeImage()
    }

    /// The height, in pixels, a glyph is drawn at before tiling. Measured: 40 read best.
    static let glyphHeight: CGFloat = 40

    #if canImport(Vision)
    /// Which of `letters` the glyph (dark ink on white, cropped to the ink) is, and whether the
    /// reading was clean enough to pre-accept. Nil when Vision agrees on none of them.
    static func read(_ glyph: CGImage, letters: [String]) -> (letter: String, isClean: Bool, confidence: Float)? {
        guard let image = tiled(glyph) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["de-DE"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let observations = request.results else { return nil }
        let readings = observations.flatMap { $0.topCandidates(3) }
        for reading in readings {
            if let letter = vote(reading.string, letters: letters) {
                return (letter, isClean(reading.string), reading.confidence)
            }
        }
        return nil
    }
    #endif
}
