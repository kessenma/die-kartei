#if DEBUG
import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// One illustrated deck, made without the model.
///
/// The picture face takes over the whole card, so how it lays out — and in particular how a square
/// picture sits in the card on an iPad, where the card is capped rather than stretched — can only
/// be checked against a deck that *has* pictures. The real ones come out of on-device diffusion,
/// which the simulator can't run. So this draws stand-ins at the same 512×512 the generator
/// produces, through the same `CardImageStore`, on a deck the player opens like any other. Same
/// shapes, same sizes, same code path; only the pixels are fake.
///
/// `-cards.debugSeedPictures 1` creates it, `-cards.debugRemovePictures 1` takes it away.
enum CardPictureDebugSeeder {
    static let topicMarker = "[debug] Bilderdeck"

    /// Nouns across all three genders, so the gender tab and the article coloring over a picture
    /// can be read at the same time, plus one verb for the ruled text face. (`forms` is not stored
    /// on a `SavedCard` — it is looked up in the Goethe index — so these cards have none.)
    private static let words: [(de: String, en: String, article: String?, type: String)] = [
        ("Haufen", "pile", "der", "noun"),
        ("Wohnung", "flat", "die", "noun"),
        ("Fenster", "window", "das", "noun"),
        ("Brücke", "bridge", "die", "noun"),
        ("Teppich", "carpet", "der", "noun"),
        ("tragen", "to carry", nil, "verb")
    ]

    @MainActor
    static func existing(in context: ModelContext) -> SavedDeck? {
        let descriptor = FetchDescriptor<SavedDeck>()
        return (try? context.fetch(descriptor))?.first { $0.topic == topicMarker }
    }

    @discardableResult
    @MainActor
    static func seed(in context: ModelContext) -> String {
        if SyncManager.shared.isRunning { return "skipped: sync is running" }
        if existing(in: context) != nil { return "already there" }

        let cards = words.enumerated().map { index, word in
            SavedCard(
                germanWord: word.de,
                englishTranslation: word.en,
                wordType: word.type,
                article: word.article,
                exampleSentence: "Das ist \(word.article ?? "") \(word.de).",
                sortOrder: index
            )
        }

        let deck = SavedDeck(
            topic: topicMarker,
            wordCount: cards.count,
            includeExamples: true,
            cards: cards
        )
        context.insert(deck)

        // The last card stays without a picture on purpose: the ruled text face and the picture
        // face are different heights, and a deck with both is where that shows.
        var drawn = 0
        for (index, card) in cards.dropLast().enumerated() {
            let fileName = CardImageStore.newFileName(for: card.id)
            guard write(placeholder(index: index, word: card.germanWord),
                        fileName: fileName, deckID: deck.id) else { continue }
            card.imageFileName = fileName
            drawn += 1
        }

        try? context.save()
        return "seeded \(cards.count) cards, \(drawn) with a picture"
    }

    @discardableResult
    @MainActor
    static func remove(in context: ModelContext) -> Bool {
        guard let deck = existing(in: context) else { return false }
        try? FileManager.default.removeItem(at: CardImageStore.directory(for: deck.id))
        context.delete(deck)
        try? context.save()
        return true
    }

    // MARK: - Drawing

    /// A flat Bauhaus-ish square at the generator's own 512×512 (`ImageGenModel.outputResolution`),
    /// so the decoded cost and the proportions match a real picture. The word is drawn into it too,
    /// which is how you tell a cropped picture from a correctly fitted one at a glance: lose the
    /// top or bottom band and the text goes with it.
    private static func placeholder(index: Int, word: String) -> UIImage {
        let side: CGFloat = 512
        let palettes: [(UIColor, UIColor)] = [
            (UIColor(red: 0.12, green: 0.32, blue: 0.68, alpha: 1), UIColor(red: 0.95, green: 0.76, blue: 0.20, alpha: 1)),
            (UIColor(red: 0.84, green: 0.22, blue: 0.18, alpha: 1), UIColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1)),
            (UIColor(red: 0.16, green: 0.46, blue: 0.38, alpha: 1), UIColor(red: 0.95, green: 0.76, blue: 0.20, alpha: 1)),
            (UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1), UIColor(red: 0.84, green: 0.22, blue: 0.18, alpha: 1))
        ]
        let (ground, mark) = palettes[index % palettes.count]
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            ground.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            mark.setFill()
            switch index % 3 {
            case 0:
                ctx.cgContext.fillEllipse(in: CGRect(x: 96, y: 96, width: 320, height: 320))
            case 1:
                ctx.cgContext.fill(CGRect(x: 64, y: 192, width: 384, height: 128))
            default:
                ctx.cgContext.move(to: CGPoint(x: side / 2, y: 85))
                ctx.cgContext.addLine(to: CGPoint(x: side - 85, y: side - 107))
                ctx.cgContext.addLine(to: CGPoint(x: 85, y: side - 107))
                ctx.cgContext.fillPath()
            }
            // Bands at the very top and bottom edges: whatever a card's frame crops off the square
            // takes one of these with it, so a glance says how much is being lost.
            for label in [("TOP", CGFloat(14)), ("UNTEN", side - 52)] {
                let text = "\(label.0) · \(word)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 30, weight: .heavy),
                    .foregroundColor: ground
                ]
                mark.setFill()
                ctx.cgContext.fill(CGRect(x: 0, y: label.1 - 6, width: side, height: 50))
                text.draw(at: CGPoint(x: 16, y: label.1), withAttributes: attributes)
            }
        }
    }

    private static func write(_ image: UIImage, fileName: String, deckID: UUID) -> Bool {
        guard let data = image.pngData() else { return false }
        do {
            try data.write(to: CardImageStore.url(fileName: fileName, deckID: deckID), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
#endif
