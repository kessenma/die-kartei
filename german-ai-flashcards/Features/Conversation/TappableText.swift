import SwiftUI

/// Renders German text where each word is tappable (to translate/save), with an optional
/// read-along highlight (underline + tint — never bold, so the layout never reflows) and a
/// subtle marker on words already saved to the library.
struct TappableText: View {
    let text: String
    /// UTF-16 range of the word currently being read aloud, if any.
    var highlightRange: NSRange? = nil
    /// Lowercased German words already saved (shown with a subtle background).
    var savedWords: Set<String> = []
    var font: Font = .title3
    let onTapWord: (String) -> Void

    private struct Token { let text: String; let range: NSRange; let isWord: Bool }

    var body: some View {
        let tokens = tokenize(text)
        Text(attributed(tokens))
            .font(font)
            .tint(.primary)               // words are links; keep them looking like normal text
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "wtword",
                      let host = url.host, let index = Int(host),
                      index >= 0, index < tokens.count else { return .systemAction }
                onTapWord(tokens[index].text)
                return .handled
            })
    }

    private func attributed(_ tokens: [Token]) -> AttributedString {
        var result = AttributedString()
        for (index, token) in tokens.enumerated() {
            var run = AttributedString(token.text)
            if token.isWord {
                run.link = URL(string: "wtword://\(index)")
                run.foregroundColor = .primary

                if savedWords.contains(token.text.lowercased()) {
                    run.backgroundColor = Color.accentColor.opacity(0.16)
                }
                if let highlightRange, NSIntersectionRange(highlightRange, token.range).length > 0 {
                    run.foregroundColor = .accentColor
                    run.underlineStyle = .single
                }
            }
            result += run
        }
        return result
    }

    /// Split into word / non-word runs, tracking each run's UTF-16 range (matches AVSpeech ranges).
    private func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var startUTF16 = 0
        var utf16pos = 0
        var currentIsWord = false

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(Token(
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
