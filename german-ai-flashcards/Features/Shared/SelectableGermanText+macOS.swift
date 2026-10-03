#if os(macOS)
import AppKit
import SwiftUI

/// The macOS side of `SelectableGermanText`: the same styled string in a `WrappingTextView`
/// (an `NSTextView`). Double-click a word to inspect it; select a phrase and right-click for
/// "Translate" and "Save phrase"; a single click is the read-along player's "start here".
extension SelectableGermanText: NSViewRepresentable {
    func makeNSView(context: Context) -> WrappingTextView {
        let tv = WrappingTextView()
        let coordinator = context.coordinator
        tv.onInspect = { [weak coordinator] offset in coordinator?.inspect(atUTF16Offset: offset) }
        tv.selectionMenuItems = { [weak coordinator] range in coordinator?.menuItems(for: range) ?? [] }
        coordinator.textView = tv
        return tv
    }

    func updateNSView(_ tv: WrappingTextView, context: Context) {
        context.coordinator.parent = self
        tv.clicksToInspect = tapsToInspect
        let coordinator = context.coordinator
        tv.onSingleClick = onSingleTap == nil ? nil : { [weak coordinator] in coordinator?.parent.onSingleTap?() }
        // View ▸ Bigger / Smaller Text scales the German you read (`MacReadingTextSize`).
        let size = NSFont.preferredFont(forTextStyle: textStyle).pointSize * context.environment.macReadingScale
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let styled = Self.attributed(text, font: font, savedWords: savedWords,
                                     glossary: glossary, lookedUpWords: lookedUpWords,
                                     nounTints: nounTints,
                                     highlightRange: highlightRange)
        Self.insertInlineGlosses(into: styled, glossary: glossary, mode: inlineGlosses, font: font)
        tv.setStyledText(styled)
        tv.wrappedImages = wrappedImages
    }

    /// Hug the text's natural width when short, wrap within the proposed width when long.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: WrappingTextView, context: Context) -> CGSize? {
        let proposed = proposal.width ?? 320
        let maxWidth = (proposed.isFinite && proposed > 0) ? proposed : 320
        let fit = tv.fittingSize(forWidth: maxWidth)
        let width = wrappedImages.isEmpty ? min(ceil(fit.width), maxWidth) : maxWidth
        return CGSize(width: width, height: ceil(fit.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator {
        var parent: SelectableGermanText
        weak var textView: WrappingTextView?

        init(_ parent: SelectableGermanText) { self.parent = parent }

        func inspect(atUTF16Offset offset: Int) {
            guard let tv = textView else { return }
            let attributed = tv.attributedString()
            // An inline gloss is English the reader printed, not a word to look up.
            if offset < attributed.length,
               attributed.attribute(.inlineGloss, at: offset, effectiveRange: nil) != nil {
                return
            }
            if let word = SelectableGermanText.word(in: tv.string, atUTF16Offset: offset) {
                parent.onTapWord(word)
            }
        }

        func menuItems(for range: NSRange) -> [NSMenuItem] {
            guard let tv = textView else { return [] }
            let selected = SelectableGermanText.plainText(of: tv.attributedString(), in: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else { return [] }
            var items: [NSMenuItem] = [
                ClosureMenuItem(title: parent.translateActionTitle, symbol: parent.translateActionSymbol) { [weak self] in
                    self?.parent.onTranslateSelection(selected)
                }
            ]
            if parent.onSavePhrase != nil {
                items.append(ClosureMenuItem(title: "Save phrase", symbol: "ear.badge.waveform") { [weak self] in
                    self?.parent.onSavePhrase?(selected)
                })
            }
            return items
        }
    }
}
#endif
