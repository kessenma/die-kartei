import SwiftUI
#if canImport(UIKit)
import UIKit

/// German text that supports two gestures, used for conversation messages and the correction card:
///  • **Double-tap a word** → inspect it (1:1 translation + save to the flashcard library).
///  • **Drag-select a span** → a custom edit menu offering "Translate" and "Save phrase", so the
///    learner can grab a whole phrase out of the chat and add it to their phrase library.
///
/// It also mirrors `TappableText`'s decorations: a read-along highlight (tint + underline, used
/// while a reply is spoken) and a subtle background on words already saved to the library.
///
/// Backed by a non-editable `UITextView` so we get the system selection handles for free; the
/// per-word tap and the two custom menu actions are layered on via a coordinator.
struct SelectableGermanText: UIViewRepresentable {
    let text: String
    var textStyle: UIFont.TextStyle = .callout
    var weight: UIFont.Weight = .regular
    /// Taps required to open the word inspector. Defaults to a double-tap so single taps and drags
    /// stay free for selecting phrases.
    var tapsToInspect: Int = 2
    /// UTF-16 range of the word currently being read aloud, if any.
    var highlightRange: NSRange? = nil
    /// Lowercased German words already saved (shown with a subtle background).
    var savedWords: Set<String> = []
    /// A single tapped word.
    var onTapWord: (String) -> Void
    /// A multi-word selection the learner asked to translate 1:1.
    var onTranslateSelection: (String) -> Void
    /// A multi-word selection the learner wants to save into their phrase library. When nil, the
    /// "Save phrase" edit-menu action is omitted (e.g. for the user's own messages).
    var onSavePhrase: ((String) -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.delegate = context.coordinator
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = tapsToInspect
        tap.delegate = context.coordinator
        tv.addGestureRecognizer(tap)

        context.coordinator.textView = tv
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: textStyle).pointSize, weight: weight)
        let font = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
        tv.attributedText = Self.attributed(text, font: font, savedWords: savedWords, highlightRange: highlightRange)
    }

    /// Build the styled string: base label color, an accent wash on saved words, and a read-along
    /// tint + underline on the spoken word. Mirrors `TappableText`'s decorations.
    private static func attributed(_ text: String,
                                   font: UIFont,
                                   savedWords: Set<String>,
                                   highlightRange: NSRange?) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.label
        ])
        let ns = text as NSString
        if !savedWords.isEmpty {
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { word, range, _, _ in
                if let word, savedWords.contains(word.lowercased()) {
                    result.addAttribute(.backgroundColor, value: UIColor.tintColor.withAlphaComponent(0.16), range: range)
                }
            }
        }
        if let highlightRange, highlightRange.location != NSNotFound,
           NSMaxRange(highlightRange) <= ns.length {
            result.addAttributes([
                .foregroundColor: UIColor.tintColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: highlightRange)
        }
        return result
    }

    /// Size to fit the text: hug its natural width when short, wrap within the proposed width when
    /// long, and let the height follow (no scrolling).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let proposed = proposal.width ?? 320
        let maxWidth = (proposed.isFinite && proposed > 0) ? proposed : 320
        let fit = tv.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: min(ceil(fit.width), maxWidth), height: ceil(fit.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: SelectableGermanText
        weak var textView: UITextView?

        init(_ parent: SelectableGermanText) { self.parent = parent }

        // Double-tap a word to inspect it. We then clear any selection the native double-tap-to-
        // select gesture may have left behind, so the word isn't highlighted under the inspector.
        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let tv = textView else { return }
            let point = gr.location(in: tv)
            guard let pos = tv.closestPosition(to: point) else { return }
            let offset = tv.offset(from: tv.beginningOfDocument, to: pos)
            if let word = Self.word(in: tv.text ?? "", atUTF16Offset: offset) {
                tv.selectedTextRange = nil
                parent.onTapWord(word)
            }
        }

        // Prepend our two actions to the selection's edit menu (iOS 16+).
        func textView(_ textView: UITextView,
                      editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0,
                  let full = textView.text,
                  let r = Range(range, in: full) else { return nil }
            let selected = String(full[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else { return nil }

            let translate = UIAction(title: "Translate",
                                     image: UIImage(systemName: "character.book.closed")) { [weak self] _ in
                self?.parent.onTranslateSelection(selected)
            }
            var actions: [UIMenuElement] = [translate]
            if parent.onSavePhrase != nil {
                let savePhrase = UIAction(title: "Save phrase",
                                          image: UIImage(systemName: "ear.badge.waveform")) { [weak self] _ in
                    self?.parent.onSavePhrase?(selected)
                }
                actions.append(savePhrase)
            }
            let mine = UIMenu(title: "", options: .displayInline, children: actions)
            return UIMenu(children: [mine] + suggestedActions)
        }

        // Let our tap coexist with the text view's own selection gestures.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// The word (letters/hyphen/apostrophe run) surrounding a UTF-16 offset, or nil.
        static func word(in text: String, atUTF16Offset offset: Int) -> String? {
            let ns = text as NSString
            guard ns.length > 0 else { return nil }

            func isWordChar(_ c: unichar) -> Bool {
                guard let scalar = Unicode.Scalar(c) else { return false }
                let ch = Character(scalar)
                return ch.isLetter || ch == "-" || ch == "'" || ch == "\u{2019}"
            }

            var i = min(max(offset, 0), ns.length)
            // A tap landing just past a word (or on a space) steps back onto the word's last letter.
            if i >= ns.length || !isWordChar(ns.character(at: i)) {
                if i > 0 && isWordChar(ns.character(at: i - 1)) { i -= 1 } else { return nil }
            }
            var start = i
            while start > 0 && isWordChar(ns.character(at: start - 1)) { start -= 1 }
            var end = i
            while end < ns.length && isWordChar(ns.character(at: end)) { end += 1 }
            let word = ns.substring(with: NSRange(location: start, length: end - start))
            return word.isEmpty ? nil : word
        }
    }
}
#endif
