//
//  SelectableGermanText+Pencil.swift
//  german-ai-flashcards
//
//  The Apple Pencil on `SelectableGermanText`: tap a word, run over a few, or circle them, and
//  the text reports which words (`onPencilMark`). The Pencil gets a recognizer of its own that
//  takes the touch the moment it lands, so the text view's selection gestures and the scroll view
//  around it never see the Pencil; fingers scroll, select and double-tap as before.
//
//  The geometry — tap or stroke or loop, and which words each one means — is
//  `PencilWordMarking`, kept pure for the tests. This file only gathers the points, draws the
//  passing ink, and measures the words' boxes when the Pencil lifts.
//

#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// One Pencil stroke's points, in the view's coordinates. Begins on touch-down, which is what keeps
/// the touch from every other recognizer that isn't allowed alongside it.
final class PencilMarkRecognizer: UIGestureRecognizer {
    private(set) var points: [CGPoint] = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        delaysTouchesBegan = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first, let view, points.isEmpty else {
            state = .failed
            return
        }
        points = [touch.location(in: view)]
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            points.append(sample.location(in: view))
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view { points.append(touch.location(in: view)) }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        points = []
        super.reset()
    }

    /// Nothing else takes a Pencil touch once this has it: no text selection, no loupe.
    override func canBePrevented(by preventing: UIGestureRecognizer) -> Bool { false }
    override func canPrevent(_ prevented: UIGestureRecognizer) -> Bool { true }
}

extension SelectableGermanText.Coordinator {

    /// Install or remove the Pencil marker to match `onPencilMark`.
    func updatePencil(enabled: Bool) {
        guard let tv = textView else { return }
        if enabled, pencil == nil {
            let recognizer = PencilMarkRecognizer(target: self, action: #selector(handlePencil(_:)))
            recognizer.delegate = self
            tv.addGestureRecognizer(recognizer)
            pencil = recognizer
        } else if !enabled, let recognizer = pencil {
            tv.removeGestureRecognizer(recognizer)
            pencil = nil
        }
        if enabled {
            // The list or scroll view around the text isn't there yet on the first update.
            DispatchQueue.main.async { [weak self] in self?.keepPencilFromScrolling() }
        }
    }

    /// The Pencil marks; it doesn't scroll. Every scroll view around the text stops taking Pencil
    /// touches (fingers, the trackpad and the mouse still scroll). Without this, a stroke that
    /// starts a hair off a word drags the whole posting along.
    private func keepPencilFromScrolling() {
        guard let tv = textView else { return }
        let others: [NSNumber] = [UITouch.TouchType.direct, .indirect, .indirectPointer].map { NSNumber(value: $0.rawValue) }
        var view = tv.superview
        while let current = view {
            if let scroll = current as? UIScrollView, scroll.panGestureRecognizer.allowedTouchTypes != others {
                scroll.panGestureRecognizer.allowedTouchTypes = others
            }
            view = current.superview
        }
    }

    @objc func handlePencil(_ recognizer: PencilMarkRecognizer) {
        guard let tv = textView else { return }
        switch recognizer.state {
        case .began, .changed:
            drawInk(recognizer.points, in: tv)
        case .ended:
            let points = recognizer.points
            fadeInk()
            guard let gesture = PencilWordMarking.classify(points) else { return }
            let words = wordBoxes(in: tv)
            let hits = PencilWordMarking.hits(gesture, words: words.map(\.rects))
            guard !hits.isEmpty else { return }
            tv.selectedTextRange = nil
            parent.onPencilMark?(mark(hits, words: words, text: tv.text ?? ""))
        default:
            fadeInk()
        }
    }

    // MARK: Words

    private struct WordBox {
        let text: String
        let range: NSRange
        let rects: [CGRect]
    }

    /// Every word of the text with its boxes, in the text view's coordinates. Inline glosses (the
    /// English the handout reader prints) are not words to mark.
    private func wordBoxes(in tv: UITextView) -> [WordBox] {
        let text = tv.text ?? ""
        let attributed = tv.attributedText
        return JobVocabAnalyzer.tokens(in: text).compactMap { token in
            if let attributed, token.range.location < attributed.length,
               attributed.attribute(.inlineGloss, at: token.range.location, effectiveRange: nil) != nil {
                return nil
            }
            guard let start = tv.position(from: tv.beginningOfDocument, offset: token.range.location),
                  let end = tv.position(from: start, offset: token.range.length),
                  let range = tv.textRange(from: start, to: end) else { return nil }
            let rects = tv.selectionRects(for: range).map(\.rect).filter { $0.width > 0 && $0.height > 0 }
            return rects.isEmpty ? nil : WordBox(text: token.text, range: token.range, rects: rects)
        }
    }

    /// The marked words, and the stretch they make when they stand side by side.
    private func mark(_ hits: [Int], words: [WordBox], text: String) -> PencilWordMark {
        let marked = hits.map { words[$0].text }
        guard hits.count >= 2, let first = hits.first, let last = hits.last,
              hits == Array(first...last) else {
            return PencilWordMark(words: marked, span: nil)
        }
        let start = words[first].range.location
        let end = NSMaxRange(words[last].range)
        let span = (text as NSString).substring(with: NSRange(location: start, length: end - start))
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return PencilWordMark(words: marked, span: span)
    }

    // MARK: Ink

    /// The stroke as it is drawn: a marker line that fades when the Pencil lifts. Nothing is kept;
    /// the words it marked carry the mark from then on.
    private func drawInk(_ points: [CGPoint], in tv: UITextView) {
        let layer: CAShapeLayer
        if let existing = pencilInk {
            layer = existing
        } else {
            layer = CAShapeLayer()
            layer.fillColor = UIColor.clear.cgColor
            layer.lineCap = .round
            layer.lineJoin = .round
            tv.layer.addSublayer(layer)
            pencilInk = layer
        }
        layer.removeAllAnimations()
        layer.opacity = 1
        layer.strokeColor = UIColor.systemYellow.withAlphaComponent(0.6).cgColor
        layer.lineWidth = 5
        layer.frame = tv.bounds
        let path = UIBezierPath()
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        layer.path = path.cgPath
    }

    private func fadeInk() {
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
