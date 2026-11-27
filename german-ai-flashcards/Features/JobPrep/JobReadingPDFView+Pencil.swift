//
//  JobReadingPDFView+Pencil.swift
//  german-ai-flashcards
//
//  The Apple Pencil on the saved PDF of a job ad: tap a word, run over a few, or circle them, the
//  same as on the text surface (`SelectableGermanText+Pencil`). The Pencil gets its own
//  recognizer, which takes the touch on landing, so PDFKit's selection and the page's scrolling
//  never see it; fingers scroll, zoom and select as before.
//
//  A page's words and their boxes come from the page's text layer (`PDFPage.string` and
//  `characterBounds(at:)`), built once per page on the first mark and kept in page space; they
//  are moved into the view's space for each mark, so zoom and scroll don't matter. The geometry —
//  tap, stroke or loop, and which words each means — is `PencilWordMarking`, shared and tested.
//

#if canImport(UIKit)
import PDFKit
import UIKit

/// A word on a PDF page: its text, where it stands in the page's string, and its boxes (one per
/// line it runs over), in page space.
struct PDFPencilWord {
    let text: String
    let range: NSRange
    let rects: [CGRect]
}

extension JobReadingPDFView {

    func updatePencil() {
        if onPencilMark != nil, pencilRecognizer == nil {
            let recognizer = PencilMarkRecognizer(target: self, action: #selector(handlePencil(_:)))
            addGestureRecognizer(recognizer)
            pencilRecognizer = recognizer
            // The word tap is for fingers now: a Pencil tap is a mark of its own, not a second pick.
            wordTap?.allowedTouchTypes = [UITouch.TouchType.direct, .indirect, .indirectPointer].map { NSNumber(value: $0.rawValue) }
            DispatchQueue.main.async { [weak self] in self?.keepPencilFromScrolling() }
        } else if onPencilMark == nil, let recognizer = pencilRecognizer {
            removeGestureRecognizer(recognizer)
            pencilRecognizer = nil
        }
    }

    /// PDFKit's scroll view (and anything around it) stops taking Pencil touches; fingers, the
    /// trackpad and the mouse still scroll.
    func keepPencilFromScrolling() {
        let others: [NSNumber] = [UITouch.TouchType.direct, .indirect, .indirectPointer].map { NSNumber(value: $0.rawValue) }
        var stack: [UIView] = [self]
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView { scroll.panGestureRecognizer.allowedTouchTypes = others }
            stack.append(contentsOf: view.subviews)
        }
        var up = superview
        while let view = up {
            if let scroll = view as? UIScrollView { scroll.panGestureRecognizer.allowedTouchTypes = others }
            up = view.superview
        }
    }

    @objc func handlePencil(_ recognizer: PencilMarkRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            drawPencilInk(recognizer.points)
        case .ended:
            let points = recognizer.points
            fadePencilInk()
            guard let gesture = PencilWordMarking.classify(points) else { return }
            let words = visibleWords()
            let hits = PencilWordMarking.hits(gesture, words: words.map(\.rects))
            guard !hits.isEmpty else { return }
            clearSelection()
            onPencilMark?(mark(hits, words: words))
        default:
            fadePencilInk()
        }
    }

    // MARK: Words

    private struct ViewWord {
        let page: PDFPage
        let word: PDFPencilWord
        let rects: [CGRect]
    }

    /// The words of the pages on screen, in reading order, with their boxes in view space.
    private func visibleWords() -> [ViewWord] {
        var out: [ViewWord] = []
        for page in visiblePages {
            let words = pageWords(page)
            for word in words {
                let rects = word.rects.map { convert($0, from: page) }
                guard rects.contains(where: { $0.intersects(bounds.insetBy(dx: -20, dy: -20)) }) else { continue }
                out.append(ViewWord(page: page, word: word, rects: rects))
            }
        }
        return out
    }

    /// A page's words, built once. Two character boxes per word (its first and last letter) when
    /// they sit on one line; letter by letter for a word that wraps.
    func pageWords(_ page: PDFPage) -> [PDFPencilWord] {
        let id = ObjectIdentifier(page)
        if let cached = pencilWords[id] { return cached }
        let text = page.string ?? ""
        var words: [PDFPencilWord] = []
        for token in JobVocabAnalyzer.tokens(in: text) {
            let first = page.characterBounds(at: token.range.location)
            let last = page.characterBounds(at: NSMaxRange(token.range) - 1)
            guard !first.isEmpty || !last.isEmpty else { continue }
            if abs(first.midY - last.midY) < max(first.height, last.height) * 0.5 {
                words.append(PDFPencilWord(text: token.text, range: token.range, rects: [first.union(last)]))
            } else {
                var lines: [CGRect] = []
                for offset in 0 ..< token.range.length {
                    let box = page.characterBounds(at: token.range.location + offset)
                    guard !box.isEmpty else { continue }
                    if let current = lines.last, abs(current.midY - box.midY) < box.height * 0.5 {
                        lines[lines.count - 1] = current.union(box)
                    } else {
                        lines.append(box)
                    }
                }
                if !lines.isEmpty { words.append(PDFPencilWord(text: token.text, range: token.range, rects: lines)) }
            }
        }
        pencilWords[id] = words
        return words
    }

    /// The marked words, and the stretch they make when they stand side by side on one page.
    private func mark(_ hits: [Int], words: [ViewWord]) -> PencilWordMark {
        let marked = hits.map { words[$0].word.text }
        guard hits.count >= 2, let first = hits.first, let last = hits.last,
              hits == Array(first...last),
              words[first].page === words[last].page,
              let text = words[first].page.string else {
            return PencilWordMark(words: marked, span: nil)
        }
        let start = words[first].word.range.location
        let end = NSMaxRange(words[last].word.range)
        let span = (text as NSString).substring(with: NSRange(location: start, length: end - start))
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return PencilWordMark(words: marked, span: span)
    }

    // MARK: Ink

    private func drawPencilInk(_ points: [CGPoint]) {
        let layer: CAShapeLayer
        if let existing = pencilInk {
            layer = existing
        } else {
            layer = CAShapeLayer()
            layer.fillColor = UIColor.clear.cgColor
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.zPosition = 10
            self.layer.addSublayer(layer)
            pencilInk = layer
        }
        layer.removeAllAnimations()
        layer.opacity = 1
        layer.strokeColor = UIColor.systemYellow.withAlphaComponent(0.6).cgColor
        layer.lineWidth = 5
        layer.frame = bounds
        let path = UIBezierPath()
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        layer.path = path.cgPath
    }

    private func fadePencilInk() {
        guard let layer = pencilInk else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer] in layer?.path = nil }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.35
        layer.opacity = 0
        layer.add(fade, forKey: "fade")
        CATransaction.commit()
    }
}
#endif
