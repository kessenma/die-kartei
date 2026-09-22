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
    /// Words explained in a glossary shown below the text (marked with a dotted underline).
    var glossary: GlossaryHighlight = .none
    /// Print each glossary word's English right after it in the text. Only the handout reader asks
    /// for this: the read-along and gender ranges of the other callers are computed against the
    /// plain text and would drift once glosses are inserted, so those callers leave it `.off`.
    var inlineGlosses: InlineGlossMode = .off
    /// Lowercased words this learner looked up in this text (marked with a red dashed underline).
    var lookedUpWords: Set<String> = []
    /// UTF-16 ranges to tint with a noun's der/die/das color. Range-based (not word-keyed) so a
    /// sentence-initial instance of the same word can stay untinted.
    var nounTints: [(range: NSRange, color: UIColor)] = []
    /// Pictures the text should flow around (the story reader's „Umfluss" layout). Empty everywhere
    /// else, which keeps those call sites on the plain layout path.
    var wrappedImages: [WrappedImageSpec] = []
    /// Whether this instance may be asked to wrap text around pictures. Set it up front — it picks
    /// the text engine at view-creation time, and the pictures usually arrive a moment later, once
    /// they've been read off disk.
    var usesImageWrapping: Bool = false
    /// A single tapped word.
    var onTapWord: (String) -> Void
    /// A multi-word selection the learner asked to translate 1:1.
    var onTranslateSelection: (String) -> Void
    /// The edit-menu label and symbol for `onTranslateSelection`. The flashcard builder reuses the
    /// gesture as "Add as card", where "Translate" would promise the wrong thing.
    var translateActionTitle: String = "Translate"
    var translateActionSymbol: String = "character.book.closed"
    /// A multi-word selection the learner wants to save into their phrase library. When nil, the
    /// "Save phrase" edit-menu action is omitted (e.g. for the user's own messages).
    var onSavePhrase: ((String) -> Void)? = nil
    /// A single tap anywhere in the text (distinct from the double-tap word inspect). When set, a
    /// tap fires this after the double-tap recognizer fails — used by the read-along player to
    /// "start reading from this sentence".
    var onSingleTap: (() -> Void)? = nil

    // Deliberately `UITextView` and not `WrappingTextView`: only a text view that actually has to
    // wrap around pictures is built from the subclass. Every other caller — chat, job prep, the
    // listen-mode transcript, the `kompakt`/`ganz` story layouts — gets the same plain `UITextView`
    // it always got, so the wrapping code cannot reach them at all.
    func makeUIView(context: Context) -> UITextView {
        let tv: UITextView = usesImageWrapping ? WrappingTextView() : UITextView()
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

        // Optional single-tap ("start reading here") that yields to the word-inspect double-tap.
        if onSingleTap != nil {
            let single = UITapGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.handleSingleTap(_:)))
            single.numberOfTapsRequired = 1
            single.delegate = context.coordinator
            single.require(toFail: tap)
            tv.addGestureRecognizer(single)
        }

        context.coordinator.textView = tv
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: textStyle).pointSize, weight: weight)
        let font = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
        let styled = Self.attributed(text, font: font, savedWords: savedWords,
                                     glossary: glossary, lookedUpWords: lookedUpWords,
                                     nounTints: nounTints,
                                     highlightRange: highlightRange)
        Self.insertInlineGlosses(into: styled, glossary: glossary, mode: inlineGlosses, font: font)
        tv.attributedText = styled
        (tv as? WrappingTextView)?.wrappedImages = wrappedImages
    }

    /// The gloss text after a word, in a smaller secondary face and tagged so a tap or a selection
    /// never treats it as part of the German. Phrases are glossed as a whole; a word inside a
    /// glossed phrase is left alone. `.first` glosses each entry once, where it first appears.
    private static func insertInlineGlosses(into result: NSMutableAttributedString,
                                            glossary: GlossaryHighlight,
                                            mode: InlineGlossMode,
                                            font: UIFont) {
        guard mode != .off, !glossary.isEmpty else { return }
        let ns = result.string as NSString
        var matches: [(range: NSRange, entry: GlossaryEntry)] = []
        var phraseRanges: [NSRange] = []
        for phrase in glossary.phrases {
            var searched = 0
            while searched < ns.length {
                let found = ns.range(of: phrase, options: .caseInsensitive,
                                     range: NSRange(location: searched, length: ns.length - searched))
                guard found.location != NSNotFound else { break }
                if let entry = glossary.phraseEntries[phrase.lowercased()] { matches.append((found, entry)) }
                phraseRanges.append(found)
                searched = max(NSMaxRange(found), searched + 1)
            }
        }
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { word, range, _, _ in
            guard let key = word?.lowercased(), let entry = glossary.words[key] else { return }
            if phraseRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) { return }
            matches.append((range, entry))
        }
        matches.sort { $0.range.location < $1.range.location }

        var seen = Set<String>()
        var chosen: [(NSRange, String)] = []
        for match in matches {
            let id = match.entry.german.lowercased()
            if mode == .first {
                guard !seen.contains(id) else { continue }
                seen.insert(id)
            }
            chosen.append((match.range, Self.shortGloss(match.entry.english)))
        }
        let glossFont = UIFont.systemFont(ofSize: font.pointSize * 0.82)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: glossFont,
            .foregroundColor: UIColor.secondaryLabel,
            .inlineGloss: true
        ]
        // From the end, so earlier ranges stay valid as the string grows.
        for (range, english) in chosen.reversed() {
            result.insert(NSAttributedString(string: " (\(english))", attributes: attributes), at: NSMaxRange(range))
        }
    }

    /// A gloss short enough to sit inside a sentence: the first sense, capped.
    private static func shortGloss(_ english: String) -> String {
        var gloss = english
        if let cut = gloss.range(of: " (") { gloss = String(gloss[..<cut.lowerBound]) }
        gloss = gloss.trimmingCharacters(in: .whitespaces)
        return gloss.count > 60 ? String(gloss.prefix(57)).trimmingCharacters(in: .whitespaces) + "…" : gloss
    }

    /// The text of a selection with any inline glosses left out, so "Translate" on a highlighted
    /// span never carries the English along.
    static func plainText(of attributed: NSAttributedString, in range: NSRange) -> String {
        guard NSMaxRange(range) <= attributed.length else { return "" }
        var out = ""
        let ns = attributed.string as NSString
        attributed.enumerateAttribute(.inlineGloss, in: range, options: []) { value, sub, _ in
            if value == nil { out += ns.substring(with: sub) }
        }
        return out
    }

    /// Build the styled string: base label color, an accent wash on saved words, a dotted underline
    /// on words the glossary below explains, a red dashed underline on words this learner looked up,
    /// and a read-along tint + solid underline on the spoken word. Mirrors `TappableText`'s
    /// decorations.
    private static func attributed(_ text: String,
                                   font: UIFont,
                                   savedWords: Set<String>,
                                   glossary: GlossaryHighlight,
                                   lookedUpWords: Set<String>,
                                   nounTints: [(range: NSRange, color: UIColor)],
                                   highlightRange: NSRange?) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.label
        ])
        let ns = text as NSString
        let dotted: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
            .underlineColor: UIColor.tintColor.withAlphaComponent(0.75)
        ]
        // Dashed rather than dotted, and red rather than the tint: a word this learner needed help
        // with reads differently from one the story shipped a translation for.
        let dashed: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDash.rawValue,
            .underlineColor: UIColor.systemRed.withAlphaComponent(0.8)
        ]
        if !savedWords.isEmpty || !glossary.words.isEmpty || !lookedUpWords.isEmpty {
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { word, range, _, _ in
                guard let key = word?.lowercased() else { return }
                if savedWords.contains(key) {
                    result.addAttribute(.backgroundColor, value: UIColor.tintColor.withAlphaComponent(0.16), range: range)
                }
                // The glossary's marking wins when a word is in both — it's the better answer, and
                // it's the one the list below the story explains.
                if glossary.words[key] != nil {
                    result.addAttributes(dotted, range: range)
                } else if lookedUpWords.contains(key) {
                    result.addAttributes(dashed, range: range)
                }
            }
        }
        for phrase in glossary.phrases {
            var searched = 0
            while searched < ns.length {
                let found = ns.range(of: phrase, options: .caseInsensitive,
                                     range: NSRange(location: searched, length: ns.length - searched))
                guard found.location != NSNotFound else { break }
                result.addAttributes(dotted, range: found)
                searched = max(NSMaxRange(found), searched + 1)
            }
        }
        // Gender colors sit under the read-along highlight, which is applied last and wins.
        for tint in nounTints where NSMaxRange(tint.range) <= ns.length {
            result.addAttribute(.foregroundColor, value: tint.color, range: tint.range)
        }
        if let highlightRange, highlightRange.location != NSNotFound,
           NSMaxRange(highlightRange) <= ns.length {
            // Solid, so a glossary word being read aloud reads as the spoken word rather than
            // keeping its dotted marking.
            result.addAttributes([
                .foregroundColor: UIColor.tintColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: UIColor.tintColor
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
        // Wrapped pictures are positioned against the full width, so the view has to take all of it
        // rather than hugging the text it happens to contain.
        let width = wrappedImages.isEmpty ? min(ceil(fit.width), maxWidth) : maxWidth
        return CGSize(width: width, height: ceil(fit.height))
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
            // An inline gloss is English the reader printed, not a word to look up.
            if let attributed = tv.attributedText, offset < attributed.length,
               attributed.attribute(.inlineGloss, at: offset, effectiveRange: nil) != nil {
                return
            }
            if let word = Self.word(in: tv.text ?? "", atUTF16Offset: offset) {
                tv.selectedTextRange = nil
                parent.onTapWord(word)
            }
        }

        // Single tap that isn't a word-inspect double-tap: "start reading from this sentence".
        @objc func handleSingleTap(_ gr: UITapGestureRecognizer) {
            textView?.selectedTextRange = nil
            parent.onSingleTap?()
        }

        // Prepend our two actions to the selection's edit menu (iOS 16+).
        func textView(_ textView: UITextView,
                      editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let attributed = textView.attributedText else { return nil }
            let selected = SelectableGermanText.plainText(of: attributed, in: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else { return nil }

            let translate = UIAction(title: parent.translateActionTitle,
                                     image: UIImage(systemName: parent.translateActionSymbol)) { [weak self] _ in
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

/// Whether, and how often, a text prints the glossary's English inline after a German word.
enum InlineGlossMode: String, CaseIterable, Identifiable {
    case off
    /// Once per entry, where it first appears: reads like a graded reader.
    case first
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:   "Off"
        case .first: "First time"
        case .all:   "Every time"
        }
    }
}

extension NSAttributedString.Key {
    /// Marks an inline gloss: English the reader printed after a word, skipped by taps and selections.
    static let inlineGloss = NSAttributedString.Key("dk.inlineGloss")
}
#endif
