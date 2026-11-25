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
    /// UTF-16 ranges to tint with a noun's der/die/das color.
    var nounTints: [(range: NSRange, color: Color)] = []
    var font: Font = .title3
    let onTapWord: (String) -> Void

    var body: some View {
        let tokens = WordTokenizer.tokenize(text)
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

    private func attributed(_ tokens: [WordToken]) -> AttributedString {
        var result = AttributedString()
        for (index, token) in tokens.enumerated() {
            var run = AttributedString(token.text)
            if token.isWord {
                run.link = URL(string: "wtword://\(index)")
                run.foregroundColor = .primary

                if savedWords.contains(token.text.lowercased()) {
                    run.backgroundColor = Color.accentColor.opacity(0.16)
                }
                if let tint = nounTints.first(where: { NSIntersectionRange($0.range, token.range).length > 0 }) {
                    run.foregroundColor = tint.color
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
}
