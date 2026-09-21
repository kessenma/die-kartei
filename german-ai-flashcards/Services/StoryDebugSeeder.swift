#if DEBUG
import Foundation
import SwiftData
import UIKit

/// One illustrated story, made without the model.
///
/// The reader's three picture layouts can only be checked against a story that *has* pictures, and
/// the real ones come out of on-device diffusion — which the simulator can't run. So this draws
/// stand-ins at the same 768×768 the generator produces, through the same `StoryImageStore`, and
/// anchors them to paragraphs the same way. Same shapes, same sizes, same code path; only the
/// pixels are fake.
///
/// `-stories.debugSeed 1` creates it, `-stories.debugOpen 1` creates it (if needed) and opens it.
enum StoryDebugSeeder {
    static let titleMarker = "[debug] Ein Tag in Berlin"

    /// The seeded story, or nil if it isn't there.
    @MainActor
    static func existing(in context: ModelContext) -> StudyStory? {
        let descriptor = FetchDescriptor<StudyStory>()
        return (try? context.fetch(descriptor))?.first { $0.title == titleMarker }
    }

    @discardableResult
    @MainActor
    static func seed(in context: ModelContext) -> StudyStory? {
        if let existing = existing(in: context) { return existing }

        let story = StudyStory(topic: "Ein Tag in Berlin", level: .a2, genre: .alltag)
        story.title = titleMarker
        story.storyText = paragraphs.joined(separator: "\n\n")
        story.englishText = englishParagraphs.joined(separator: "\n\n")
        story.setGlossary([
            GlossaryEntry(german: "der Zug", english: "train"),
            GlossaryEntry(german: "besuchen", english: "to visit"),
            GlossaryEntry(german: "die Currywurst", english: "curried sausage"),
            GlossaryEntry(german: "treffen", english: "to meet")
        ])
        story.setLookups([GlossaryEntry(german: "Abend", english: "evening")])

        // Slot 0 is the header (no anchor), then one picture after paragraphs 0, 1 and 3 — the
        // uneven spacing matters: it's what shows whether a paragraph with no picture still lays
        // out correctly between two that have one.
        var records: [StoryImageRecord] = []
        for (index, anchor) in [nil, 0, 1, 3].enumerated() {
            let fileName = String(format: "%02d.png", index)
            guard write(placeholder(index: index), fileName: fileName, storyID: story.id) else { continue }
            records.append(StoryImageRecord(
                fileName: fileName,
                prompt: "[debug] placeholder \(index)",
                paragraphAnchorIndex: anchor
            ))
        }
        story.setImages(records)

        context.insert(story)
        try? context.save()
        return story
    }

    /// Remove the seeded story and its pictures.
    @discardableResult
    @MainActor
    static func remove(in context: ModelContext) -> Bool {
        guard let story = existing(in: context) else { return false }
        StoryImageStore.deleteImages(for: story.id)
        context.delete(story)
        try? context.save()
        return true
    }

    // MARK: - Drawing

    /// A flat Bauhaus-ish square at the generator's own 768×768, so the decoded cost and the
    /// proportions match a real illustration.
    private static func placeholder(index: Int) -> UIImage {
        let side: CGFloat = 768
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
                ctx.cgContext.fillEllipse(in: CGRect(x: 144, y: 144, width: 480, height: 480))
            case 1:
                ctx.cgContext.fill(CGRect(x: 96, y: 288, width: 576, height: 192))
            default:
                ctx.cgContext.move(to: CGPoint(x: side / 2, y: 128))
                ctx.cgContext.addLine(to: CGPoint(x: side - 128, y: side - 160))
                ctx.cgContext.addLine(to: CGPoint(x: 128, y: side - 160))
                ctx.cgContext.fillPath()
            }
            // A number, so it's obvious which picture landed where.
            let label = "\(index)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 120, weight: .heavy),
                .foregroundColor: ground
            ]
            let size = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2),
                       withAttributes: attributes)
        }
    }

    private static func write(_ image: UIImage, fileName: String, storyID: UUID) -> Bool {
        guard let data = image.pngData() else { return false }
        let url = StoryImageStore.url(fileName: fileName, storyID: storyID)
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Text

    /// Deliberately uneven: a very short paragraph next to a picture is where wrapping goes wrong,
    /// so one of them is a single line.
    private static let paragraphs = [
        "Anna steht früh auf. Sie fährt mit dem Zug nach Berlin, weil sie ihre alte Freundin Mira besuchen will. Im Zug liest sie ein Buch und schaut aus dem Fenster. Die Felder sind grün und der Himmel ist weit.",
        "Am Bahnhof wartet Mira schon.",
        "Zusammen gehen sie in den Zoo. Sie sehen die Elefanten und die Pinguine, und Anna macht viele Fotos. Später essen sie eine Currywurst an einem kleinen Stand neben dem Park, und Mira erzählt von ihrer neuen Arbeit in einem Büro am Fluss.",
        "Am Abend gehen sie ins Theater. Das Stück ist lang und ein bisschen traurig, aber die Musik gefällt Anna sehr. Danach trinken sie noch einen Tee und reden über früher, über die Schule und über die Sommer am See.",
        "Um Mitternacht fährt Anna zurück. Der Zug ist fast leer. Sie denkt an den Tag und schläft ein."
    ]

    private static let englishParagraphs = [
        "Anna gets up early. She takes the train to Berlin, because she wants to visit her old friend Mira. On the train she reads a book and looks out of the window. The fields are green and the sky is wide.",
        "Mira is already waiting at the station.",
        "Together they go to the zoo. They see the elephants and the penguins, and Anna takes lots of photos. Later they eat a curried sausage at a little stand next to the park, and Mira talks about her new job in an office by the river.",
        "In the evening they go to the theatre. The play is long and a little sad, but Anna likes the music very much. Afterwards they have a tea and talk about the old days, about school and about the summers at the lake.",
        "At midnight Anna travels back. The train is almost empty. She thinks about the day and falls asleep."
    ]
}
#endif
