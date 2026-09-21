import Foundation
import UIKit

/// Decides *what* text a transform acts on, and how to put the result back.
///
/// Three sources, in order of how much we trust them:
///
/// 1. **The host's selection.** `UITextDocumentProxy.selectedText` is public API, and inserting
///    over a live selection replaces it. Best case: the user says exactly what they mean.
/// 2. **What this keyboard typed.** Every character we emit is recorded here, so we know the draft
///    precisely and can delete exactly that many characters back. This is the reason the keyboard
///    has its own keys: it removes all dependence on the host reporting its document correctly.
/// 3. **The paragraph before the cursor**, read from `documentContextBeforeInput`. The fallback for
///    "typed it with another keyboard, switched to this one" — hosts vary in how much they hand
///    over, so this is last.
///
/// The tracked buffer is discarded the moment it can no longer be trusted: the user moving the
/// caret or editing elsewhere means the characters behind the cursor are no longer the ones we
/// typed, and deleting backwards blind would eat someone's message.
@MainActor
final class DraftTracker {

    /// What the transform will act on, and how to replace it.
    struct Source {
        let text: String
        let origin: Origin

        enum Origin: String {
            case selection = "selection"
            case typed = "typed here"
            case paragraph = "paragraph"
        }
    }

    private(set) var typed = ""

    // MARK: - Recording what we type

    func record(_ text: String) {
        typed += text
    }

    func recordBackspace() {
        guard !typed.isEmpty else { return }
        typed.removeLast()
    }

    /// Called when the caret moves or the host's text changes underneath us. Anything we thought we
    /// knew about the characters behind the cursor is now a guess, so drop it.
    func invalidate() {
        typed = ""
    }

    // MARK: - Resolving

    func source(from proxy: UITextDocumentProxy?) -> Source? {
        guard let proxy else { return nil }

        if let selected = proxy.selectedText, !selected.trimmed.isEmpty {
            return Source(text: selected, origin: .selection)
        }
        if !typed.trimmed.isEmpty, stillMatches(proxy) {
            return Source(text: typed, origin: .typed)
        }
        let before = proxy.documentContextBeforeInput ?? ""
        let paragraph = before.lastParagraph
        if !paragraph.trimmed.isEmpty {
            return Source(text: paragraph, origin: .paragraph)
        }
        return nil
    }

    /// Is the text behind the cursor still the text we typed?
    ///
    /// Cheaper and far more robust than trying to notice every way the buffer could go stale
    /// through lifecycle callbacks: `textDidChange` also fires for our own inserts, and
    /// `selectionDidChange` can't tell the user moving the caret from us moving it. Checking the
    /// document directly answers the only question that matters, right when it matters — because
    /// the cost of being wrong here is deleting backwards over someone's real message.
    private func stillMatches(_ proxy: UITextDocumentProxy) -> Bool {
        guard let before = proxy.documentContextBeforeInput else {
            // The host tells us nothing about its document. Our own record is then the only
            // evidence there is, and it was right when we wrote it.
            return true
        }
        if before.hasSuffix(typed) { return true }
        // Some hosts hand over only a window of the document. If everything they *did* show us is
        // the tail of what we typed, the buffer is still consistent with the document.
        if !before.isEmpty, typed.hasSuffix(before) { return true }
        return false
    }

    /// Is it still safe to replace `source`, some seconds after it was resolved?
    ///
    /// A transform takes a few seconds and the keys stay live throughout, so the document can have
    /// moved on. Deleting `source.text.count` characters back from a cursor that has since
    /// advanced would eat text the user typed while waiting.
    func canStillReplace(_ source: Source, in proxy: UITextDocumentProxy?) -> Bool {
        guard let proxy else { return false }
        switch source.origin {
        case .selection:
            return proxy.selectedText == source.text
        case .typed, .paragraph:
            guard let before = proxy.documentContextBeforeInput else { return typed == source.text }
            return before.hasSuffix(source.text)
        }
    }

    /// Record a correction applied to the tail of the buffer, keeping it in step with the document.
    func replaceTail(_ count: Int, with replacement: String) {
        guard count <= typed.count else { return invalidate() }
        typed.removeLast(count)
        typed += replacement
    }

    /// Swap `source` for `replacement` in the host document.
    func replace(_ source: Source, with replacement: String, in proxy: UITextDocumentProxy?) {
        guard let proxy else { return }

        switch source.origin {
        case .selection:
            // Inserting while a selection is live replaces it, so there is nothing to delete.
            proxy.insertText(replacement)
        case .typed, .paragraph:
            // `count` on the String, not utf16: deleteBackward removes one visible character at a
            // time, so an emoji or a combined umlaut is one delete, not two.
            for _ in 0..<source.text.count { proxy.deleteBackward() }
            proxy.insertText(replacement)
        }

        // The document no longer matches what we typed: the German is now the draft.
        typed = replacement
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The run of text after the last newline — one paragraph, so a transform never swallows the
    /// quoted message or the signature below a reply.
    var lastParagraph: String {
        guard let index = lastIndex(of: "\n") else { return self }
        return String(self[self.index(after: index)...])
    }
}
