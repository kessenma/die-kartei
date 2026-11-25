//
//  WordTokenizer.swift
//  german-ai-flashcards
//
//  Splits text into word and non-word runs, each with its UTF-16 range in the source. The ranges
//  use the same convention as AVSpeech's read-along callbacks and the Kasus validator, so a
//  renderer can intersect them directly. Shared by `TappableText` (tap a word to translate it) and
//  `KasusText` (tap a phrase in a Kasus story).
//

import Foundation

/// One run of the source string: a word (letters, hyphens, apostrophes) or everything between.
nonisolated struct WordToken: Hashable {
    let text: String
    /// UTF-16 range in the source string.
    let range: NSRange
    let isWord: Bool
}

nonisolated enum WordTokenizer {
    /// Split into word / non-word runs, tracking each run's UTF-16 range (matches AVSpeech ranges).
    static func tokenize(_ s: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var current = ""
        var startUTF16 = 0
        var utf16pos = 0
        var currentIsWord = false

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(WordToken(
                text: current,
                range: NSRange(location: startUTF16, length: utf16pos - startUTF16),
                isWord: currentIsWord
            ))
            current = ""
        }

        for ch in s {
            let isWord = ch.isLetter || ch == "-" || ch == "'" || ch == "’"
            if current.isEmpty {
                current = String(ch); startUTF16 = utf16pos; currentIsWord = isWord
            } else if isWord == currentIsWord {
                current.append(ch)
            } else {
                flush()
                current = String(ch); startUTF16 = utf16pos; currentIsWord = isWord
            }
            utf16pos += ch.utf16.count
        }
        flush()
        return tokens
    }
}
