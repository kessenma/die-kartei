//
//  KasusText.swift
//  german-ai-flashcards
//
//  One paragraph of a Kasus story as a single SwiftUI `Text` built from an `AttributedString` of
//  link runs, with taps caught by `.environment(\.openURL)`: the `TappableText` technique. One
//  `Text` means the paragraph wraps like prose, and the whole of a phrase is one run, so tapping
//  any of its words selects the phrase.
//
//    plain    spaces and punctuation, never tappable
//    target   one case-marked phrase, `kasus://t/<index>` (Finden)
//    blank    an Einsetzen gap and the noun after it, `kasus://b/<index>`
//    word     any other word, `kasus://w/<n>`, so a tap outside a phrase can still say something
//    tag      a small raised m/f/n/pl (or sg/pl) after a blank's noun
//
//  Styling inside the text is limited to what can't move a line: a wash (background), an underline,
//  a strikethrough, a foreground color. Never bold, never a new word. The one extra run is the tag,
//  and it is there from the first render, so answering a blank never pushes the text around.
//  Case labels, symbols, chips and explanations live in the player's bottom tray, not in here.
//

import SwiftUI

/// What a tap in a `KasusText` landed on. Indices are target indices (`KasusLocatedTarget.index`)
/// for phrases and blanks, and a running count for other words.
enum KasusTap: Hashable {
    case target(Int)
    case blank(Int)
    case word(Int)

    init?(url: URL) {
        guard url.scheme == "kasus", let host = url.host,
              let index = Int(url.lastPathComponent) else { return nil }
        switch host {
        case "t": self = .target(index)
        case "b": self = .blank(index)
        case "w": self = .word(index)
        default:  return nil
        }
    }
}

/// The in-text styling a run may carry. Nothing here changes a glyph's width.
struct KasusTextStyle {
    var foreground: Color? = nil
    /// A background tint behind the run: a painted phrase, a focused blank.
    var wash: Color? = nil
    var underline: Text.LineStyle? = nil
    var strikethrough: Text.LineStyle? = nil
}

/// One run of a rendered paragraph.
struct KasusTextSegment {
    enum Kind {
        case plain
        case target(Int)
        case blank(Int)
        case word(Int)
        /// A raised gender or number tag: smaller type, lifted off the baseline.
        case tag
    }

    let text: String
    let kind: Kind
    var style = KasusTextStyle()
}

struct KasusText: View {
    let segments: [KasusTextSegment]
    var font: Font = .title3
    var onTap: (KasusTap) -> Void = { _ in }

    var body: some View {
        Text(attributed)
            .font(font)
            // Room for the washes and underlines between lines.
            .lineSpacing(6)
            .tint(.primary)               // phrases are links; keep them looking like prose
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard let tap = KasusTap(url: url) else { return .systemAction }
                onTap(tap)
                return .handled
            })
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for segment in segments {
            var run = AttributedString(Self.keptTogether(segment))
            run.foregroundColor = segment.style.foreground ?? .primary
            switch segment.kind {
            case .plain:
                break
            case .target(let index):
                run.link = URL(string: "kasus://t/\(index)")
            case .blank(let index):
                run.link = URL(string: "kasus://b/\(index)")
            case .word(let index):
                run.link = URL(string: "kasus://w/\(index)")
            case .tag:
                run.font = .caption2.weight(.bold)
                run.baselineOffset = 7
            }
            if let wash = segment.style.wash { run.backgroundColor = wash }
            if let underline = segment.style.underline { run.underlineStyle = underline }
            if let strike = segment.style.strikethrough { run.strikethroughStyle = strike }
            result += run
        }
        return result
    }

    /// A phrase or a blank never breaks across a line: its spaces become no-break spaces. A wash on
    /// a phrase that wrapped would run on to the margin behind the space at the line end, and a gap
    /// left at the end of one line reads as detached from its noun. Every state renders the same
    /// characters, so painting or answering still never moves a line.
    private static func keptTogether(_ segment: KasusTextSegment) -> String {
        switch segment.kind {
        case .target, .blank: segment.text.replacingOccurrences(of: " ", with: "\u{00A0}")
        default:              segment.text
        }
    }
}

// MARK: - Building a paragraph

extension KasusText {
    /// One paragraph's segments. `targets` are the ones in this paragraph, in reading order (the
    /// validator's order; they never overlap). `render` returns a target's own segments, or nil to
    /// leave it as ordinary words. Everything between targets is split into words and plain runs;
    /// with `linkWords` the words become `.word` links, and `wordStyle` can dress a word by its
    /// range in the paragraph (the trigger underline).
    static func segments(
        paragraph: String,
        targets: [KasusLocatedTarget],
        linkWords: Bool = false,
        wordStyle: (NSRange) -> KasusTextStyle? = { _ in nil },
        render: (KasusLocatedTarget) -> [KasusTextSegment]?
    ) -> [KasusTextSegment] {
        let ns = paragraph as NSString
        var out: [KasusTextSegment] = []
        var cursor = 0
        var wordCount = 0

        func emitWords(upTo end: Int) {
            guard end > cursor else { return }
            let start = cursor
            let gap = ns.substring(with: NSRange(location: start, length: end - start))
            for token in WordTokenizer.tokenize(gap) {
                guard token.isWord else {
                    out.append(KasusTextSegment(text: token.text, kind: .plain))
                    continue
                }
                let range = NSRange(location: token.range.location + start, length: token.range.length)
                let style = wordStyle(range) ?? KasusTextStyle()
                out.append(KasusTextSegment(text: token.text, kind: linkWords ? .word(wordCount) : .plain,
                                            style: style))
                wordCount += 1
            }
            cursor = end
        }

        for target in targets.sorted(by: { $0.range.location < $1.range.location }) {
            guard target.range.location >= cursor, NSMaxRange(target.range) <= ns.length,
                  let own = render(target) else { continue }
            emitWords(upTo: target.range.location)
            out.append(contentsOf: own)
            cursor = NSMaxRange(target.range)
        }
        emitWords(upTo: ns.length)
        return out
    }

    /// The raised tag after a noun: a narrow no-break space (so the tag never wraps away from its
    /// noun), then m/f/n/pl (or sg/pl) in `color`.
    static func tag(_ label: String, color: Color) -> KasusTextSegment {
        KasusTextSegment(text: "\u{202F}" + label, kind: .tag, style: KasusTextStyle(foreground: color))
    }

    /// An empty blank's gap, as long as the longest option plus one, so the gap doesn't hint at the
    /// answer's length and a fill barely moves the line.
    static func gap(for options: [String]) -> String {
        String(repeating: "_", count: max(3, (options.map(\.count).max() ?? 3) + 1))
    }
}

// MARK: - Previews

#Preview("Kasus text") {
    let paragraph = "Er spielt mit dem Schlüssel! Jonas gibt dem Hund einen Keks."
    VStack(alignment: .leading, spacing: 16) {
        KasusText(segments: [
            .init(text: "Er spielt ", kind: .plain),
            .init(text: "mit", kind: .word(0),
                  style: .init(underline: .init(pattern: .dash, color: .secondary))),
            .init(text: " ", kind: .plain),
            .init(text: "dem Schlüssel", kind: .target(0),
                  style: .init(wash: GrammarCase.dativ.color.opacity(0.28))),
            .init(text: "! Jonas gibt ", kind: .plain),
            .init(text: "dem Hund", kind: .target(1),
                  style: .init(underline: .init(pattern: .dot, color: GrammarCase.dativ.color))),
            .init(text: " ", kind: .plain),
            .init(text: "den", kind: .blank(2),
                  style: .init(foreground: .secondary, wash: Color.gray.opacity(0.2),
                               strikethrough: .init(pattern: .solid, color: .secondary))),
            .init(text: " ", kind: .blank(2)),
            .init(text: "einen", kind: .blank(2),
                  style: .init(foreground: Gender.der.color, underline: .init(pattern: .solid, color: Gender.der.color))),
            .init(text: " Keks", kind: .blank(2)),
            KasusText.tag("m", color: Gender.der.color),
            .init(text: ".", kind: .plain),
        ])
        Text(paragraph)
            .font(.title3)
            .foregroundStyle(.secondary)
    }
    .padding()
}
