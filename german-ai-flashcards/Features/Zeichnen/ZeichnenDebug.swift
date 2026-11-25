//
//  ZeichnenDebug.swift
//  german-ai-flashcards
//
//  Launch arguments for the Zeichnen room. DEBUG only.
//
//  `-zeichnen.debugSeedArt 1` gives the first few words pictures without spending anything on
//  OpenRouter: flat-coloured shapes drawn here, filed as Kontur and Malvorlage pictures, plus a
//  paint-by-number begun on one of them. `-zeichnen.debugOpen hub|quick|run|review|studio|gallery|pbn|paint`
//  opens a screen the simulator can't tap its way to (the room sits under a wide Home tile).
//

#if DEBUG
import CoreGraphics
import Foundation
import SwiftData
import SwiftUI
#if canImport(PencilKit)
import PencilKit
#endif

enum ZeichnenDebugOpen: String, Identifiable, CaseIterable {
    case hub, quick, run, review, studio, gallery, pbn
    /// The paint-by-number piece `debugSeedArt` began, open to paint.
    case paint

    var id: String { rawValue }

    init?(argument: String) {
        self.init(rawValue: argument.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

@MainActor
enum ZeichnenDebugSeeder {
    /// Pictures for the first `count` words, and one paint-by-number begun. Idempotent per word.
    static func seed(count: Int = 4, in context: ModelContext) -> Int {
        let words = Array(ZeichnenCatalog.dedupe(ZeichnenCatalog.allWords(in: context)).prefix(count))
        var made = 0
        for (index, word) in words.enumerated() {
            guard WordArtLibrary.artworks(forKey: word.key, in: context).isEmpty else { continue }
            for style in [WordArtStyle.kontur, .malvorlage] {
                guard let image = sampleImage(seed: index * 7 + (style == .kontur ? 1 : 2), dark: style == .kontur) else { continue }
                let id = UUID()
                let fileName = WordArtStore.newPictureName(for: id)
                guard (try? WordArtStore.write(image, fileName: fileName, key: word.key)) != nil else { continue }
                let artwork = WordArtwork(wordKey: word.key, germanWord: word.display, english: word.english,
                                          kind: .ai, fileName: fileName, styleRaw: style.rawValue)
                artwork.id = id
                artwork.modelID = "debug/seed"
                context.insert(artwork)
                made += 1
            }
        }
        try? context.save()
        if let first = words.first,
           let source = WordArtLibrary.artworks(forKey: first.key, in: context).first(where: { $0.styleRaw == WordArtStyle.malvorlage.rawValue }),
           !WordArtLibrary.artworks(forKey: first.key, in: context).contains(where: { $0.kind == .paintByNumber }),
           let cg = WordArtStore.loadCGImage(fileName: source.fileName, key: source.wordKey, maxPixelSize: 1024),
           let template = PaintByNumberGenerator.make(from: cg, difficulty: .leicht),
           let piece = PaintByNumberLibrary.begin(word: first.word, template: template, source: source, in: context) {
            var progress = PaintByNumberProgress()
            progress.filled = Set(0..<min(3, template.facetCount))
            let preview = PaintByNumberRenderer.fill(template, map: template.facetMap(), filled: progress.filled)
            PaintByNumberLibrary.save(progress, preview: preview, for: piece, in: context)
        }
        return made
    }

    /// Flat shapes in a handful of colours, black outlines: something both a gallery and the
    /// paint-by-number generator can chew on.
    static func sampleImage(seed: Int, dark: Bool) -> CGImage? {
        let side = 512
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var rng = SeededGenerator(seed: UInt64(seed + 1))
        let palette: [(Double, Double, Double)] = dark
            ? [(0.98, 0.95, 0.30), (0.76, 0.20, 0.29), (0.93, 0.45, 0.40)]
            : [(0.95, 0.80, 0.30), (0.30, 0.55, 0.85), (0.85, 0.30, 0.30), (0.35, 0.70, 0.40), (0.60, 0.40, 0.75)]
        ctx.setFillColor(dark ? CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1) : CGColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        for i in 0..<7 {
            let c = palette[i % palette.count]
            ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
            let w = Double.random(in: 90...240, using: &rng), h = Double.random(in: 90...240, using: &rng)
            let rect = CGRect(x: Double.random(in: 20...(492 - w), using: &rng), y: Double.random(in: 20...(492 - h), using: &rng),
                              width: w, height: h)
            if i % 2 == 0 { ctx.fillEllipse(in: rect) } else { ctx.fill(rect) }
            ctx.setStrokeColor(dark ? CGColor(red: 0, green: 0, blue: 0, alpha: 1) : CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            ctx.setLineWidth(5)
            if i % 2 == 0 { ctx.strokeEllipse(in: rect) } else { ctx.stroke(rect) }
        }
        return ctx.makeImage()
    }

    #if canImport(PencilKit)
    /// A scribble standing in for a sketch.
    static func scribble(seed: Int) -> Data {
        var rng = SeededGenerator(seed: UInt64(seed + 11))
        let strokes = (0..<4).map { _ -> PKStroke in
            let x0 = Double.random(in: 120...500, using: &rng), y0 = Double.random(in: 120...500, using: &rng)
            let points = stride(from: 0.0, through: 220.0, by: 6.0).map { t in
                PKStrokePoint(location: CGPoint(x: x0 + t * cos(t / 40), y: y0 + 60 * sin(t / 30)),
                              timeOffset: t / 500, size: CGSize(width: 4, height: 4),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        return PKDrawing(strokes: strokes).dataRepresentation()
    }
    #endif

    /// A finished run for the review screen: five words, alternating knew / didn't.
    static func finishedSession(in context: ModelContext) -> QuickDrawSession {
        let words = Array(ZeichnenCatalog.dedupe(ZeichnenCatalog.allWords(in: context)).prefix(5))
        let session = QuickDrawSession(words: words, mode: .recall, secondsPerWord: 40, keepByDefault: false)
        for (i, _) in words.enumerated() {
            #if canImport(PencilKit)
            session.endDrawing(ink: i == 3 ? nil : scribble(seed: i))
            #else
            session.endDrawing(ink: nil)
            #endif
            session.mark(knewIt: i % 2 == 0)
        }
        return session
    }
}

/// The screen a `-zeichnen.debugOpen` value names.
struct ZeichnenDebugScreen: View {
    let open: ZeichnenDebugOpen
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch open {
        case .hub:
            ZeichnenHubView()
        case .quick:
            QuickDrawSetupView()
        case .run:
            let words = Array(ZeichnenCatalog.dedupe(ZeichnenCatalog.allWords(in: modelContext)).prefix(5))
            let refs = Dictionary(uniqueKeysWithValues: words.compactMap { w in
                ZeichnenReference.best(for: w, preferring: nil, in: modelContext).map { (w.id, $0) }
            })
            QuickDrawRunView(session: QuickDrawSession(words: words, mode: .copy, secondsPerWord: 60, keepByDefault: false),
                             references: refs)
        case .review:
            QuickDrawReviewView(session: ZeichnenDebugSeeder.finishedSession(in: modelContext)) {}
        case .paint:
            let pieces = (try? modelContext.fetch(FetchDescriptor<WordArtwork>())) ?? []
            if let piece = pieces.first(where: { $0.kind == .paintByNumber && $0.inProgress }),
               let word = ZeichnenCatalog.allWords(in: modelContext).first(where: { $0.key == piece.wordKey }) {
                PaintByNumberView(artwork: piece, word: word.word)
            } else {
                ContentUnavailableView("Nothing begun", systemImage: "paintpalette",
                                       description: Text("Run with -zeichnen.debugSeedArt 1"))
            }
        case .studio, .gallery, .pbn:
            if let word = firstWord {
                switch open {
                case .studio:
                    AtelierView(word: word.word, reference: WordArtLibrary.reference(forKey: word.key, in: modelContext))
                case .gallery:
                    WordArtGalleryView(word: word)
                default:
                    PaintByNumberStartView(word: word.word, preselected: nil)
                }
            } else {
                ContentUnavailableView("No words", systemImage: "rectangle.stack",
                                       description: Text("Make a deck, or seed one, first."))
            }
        }
    }

    /// The first word with pictures (after `-zeichnen.debugSeedArt 1`), else the first word.
    private var firstWord: ZeichnenWord? {
        let words = ZeichnenCatalog.dedupe(ZeichnenCatalog.allWords(in: modelContext))
        return words.first { !WordArtLibrary.artworks(forKey: $0.key, in: modelContext).isEmpty } ?? words.first
    }
}
#endif
