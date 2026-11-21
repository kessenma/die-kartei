//
//  WorksheetSamplePDF.swift
//  german-ai-flashcards
//
//  A small exercise deck drawn with Core Text in the shape teachers' slide exports have: 16:9
//  pages, a running header and footer, a shouted title, an imperative instruction, numbered items
//  with "___" blanks, a two-column page, a dialog with numbered gaps, inline "der / den" choices
//  and answer lines drawn as rules. The words are the app's own, never a teacher's: a real lesson
//  PDF is licensed for the learner's use and must not ship in the app or the repo.
//
//  Used by the tests (the iOS PDFKit reading of a known layout), the previews and
//  `-classNotes.debugOpen worksheet`.
//

import CoreGraphics
import CoreText
import Foundation

nonisolated enum WorksheetSamplePDF {

    static let pageSize = CGSize(width: 960, height: 540)

    /// One page: lines of text at positions (top-left origin, like a slide), plus rules to draw.
    struct Page {
        var texts: [(text: String, x: CGFloat, y: CGFloat, size: CGFloat)]
        var rules: [(x: CGFloat, y: CGFloat, width: CGFloat)] = []
    }

    static let pages: [Page] = [
        Page(texts: [
            ("ÜBUNGEN · BEISPIEL", 60, 200, 40),
            ("Präpositionen und Artikel", 60, 260, 24),
        ]),
        Page(texts: [
            ("DATIV D1: ARTIKEL ERGÄNZEN", 60, 70, 32),
            ("ÜBUNG · BESTIMMTE ARTIKEL", 60, 108, 16),
            ("Ergänze dem, der oder den.", 60, 160, 22),
            ("1. Wir fahren mit ___ Zug.", 60, 205, 22),
            ("2. Sie wohnt bei ___ Tante.", 60, 245, 22),
            ("3. Er kommt aus ___ Büro.", 60, 285, 22),
            ("4. Ich spreche mit ___ Kindern.", 60, 325, 22),
            ("Nomen: der Zug, die Tante, das Büro, die Kinder. Lösungen: Folie 9.", 60, 440, 16),
        ]),
        Page(texts: [
            ("GEMISCHTE ÜBUNG M1", 60, 70, 32),
            ("ABSCHLUSS · ALLE FÄLLE", 60, 108, 16),
            ("Ergänze den bestimmten Artikel. Notiere den Fall der Lücke.", 60, 160, 22),
            ("1. ___ Zug ist pünktlich.", 60, 210, 22),
            ("2. Ich warte auf ___ Bus.", 60, 260, 22),
            ("3. Wir sitzen in ___ Küche.", 60, 310, 22),
            ("4. Sie fährt ohne ___ Fahrrad.", 500, 210, 22),
            ("5. Wegen ___ Wetters bleiben wir hier.", 500, 260, 22),
            ("6. Er hilft ___ Nachbarin.", 500, 310, 22),
            ("Nomen: der Zug, der Bus, die Küche, das Fahrrad, das Wetter, die Nachbarin.", 60, 440, 16),
        ]),
        Page(texts: [
            ("AKKUSATIV AK1: ERKENNEN", 60, 70, 32),
            ("ÜBUNG · RICHTIGEN ARTIKEL AUSWÄHLEN", 60, 108, 16),
            ("Wähle die passende Form. Markiere die Präposition.", 60, 160, 22),
            ("1. durch der / den Park", 60, 205, 22),
            ("2. für die / der Lehrerin", 60, 245, 22),
            ("3. ohne das / dem Geld", 60, 285, 22),
            ("Lösungen: Folie 9.", 60, 440, 16),
        ]),
        Page(texts: [
            ("GENITIV G2: SÄTZE VERBINDEN", 60, 70, 32),
            ("AUFBAU · WEGEN UND TROTZ", 60, 108, 16),
            ("Verbinde die Sätze mit der angegebenen Präposition.", 60, 160, 22),
            ("1. Es regnet. Wir bleiben zu Hause. (wegen des Regens)", 60, 205, 22),
            ("2. Es ist kalt. Wir gehen spazieren. (trotz)", 60, 290, 22),
        ], rules: [(90, 255, 780), (90, 340, 780)]),
        Page(texts: [
            ("GEMISCHTE ÜBUNG M2", 60, 70, 32),
            ("ABSCHLUSS · IM CAFÉ", 60, 108, 16),
            ("Ergänze die bestimmten Artikel. Lies den Dialog laut.", 60, 160, 22),
            ("A (1) ___ Kaffee ist heiß!", 60, 205, 22),
            ("B Ja, und ich sitze gern an (2) ___ Fenster.", 60, 245, 22),
            ("A Nach (3) ___ Kuchen gehen wir.", 60, 285, 22),
        ]),
    ]

    static let header = "BEISPIEL · ÜBUNGEN"
    static let footer = "Die Kartei · Beispielblatt"

    /// The deck as PDF bytes.
    static func data() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        for page in pages {
            context.beginPDFPage(nil)
            draw(header, x: 60, y: 30, size: 12, in: context)
            draw(footer, x: 60, y: 515, size: 11, in: context)
            for text in page.texts {
                draw(text.text, x: text.x, y: text.y, size: text.size, in: context)
            }
            context.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
            context.setLineWidth(1)
            for rule in page.rules {
                context.move(to: CGPoint(x: rule.x, y: pageSize.height - rule.y))
                context.addLine(to: CGPoint(x: rule.x + rule.width, y: pageSize.height - rule.y))
                context.strokePath()
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// `y` is the baseline from the top, as on a slide.
    private static func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.2, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: pageSize.height - y)
        CTLineDraw(line, context)
    }
}
