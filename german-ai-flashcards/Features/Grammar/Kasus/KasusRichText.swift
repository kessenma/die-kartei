//
//  KasusRichText.swift
//  german-ai-flashcards
//
//  One small markup for every rule line, Kasus-Check step and explanation the case path shows,
//  so forms carry their color wherever they are written:
//
//    {m:den} {f:die} {n:das} {pl:die}                  a form in its gender color, bold
//    {nom:Nominativ} {akk:…} {dat:…} {gen:…} {wechsel:…}  a case word in its case color, bold
//    **bold** and *italic*                              inline Markdown
//
//  Gender colors mark forms, case colors mark case words, the same split GrammarPalette keeps.
//  Tokens are not nested inside Markdown emphasis: `*{m:den}*` renders the token, not italics.
//  Strings stay plain Swift strings, so the Foundation-only engine (KasusExplanation) can emit
//  them and the host harness can still print them.
//

import SwiftUI

enum KasusRich {
    /// `{tag:text}` where tag is a gender column label or a case short name.
    private static let token = try! NSRegularExpression(
        pattern: #"\{(m|f|n|pl|nom|akk|dat|gen|wechsel):([^{}]+)\}"#
    )

    /// The styled string: tokens colored and bold, the rest parsed as inline Markdown.
    static func attributed(_ source: String) -> AttributedString {
        let ns = source as NSString
        var result = AttributedString()
        var cursor = 0
        for match in token.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                result += markdown(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            let tag = ns.substring(with: match.range(at: 1))
            var run = AttributedString(ns.substring(with: match.range(at: 2)))
            run.foregroundColor = color(for: tag)
            run.inlinePresentationIntent = .stronglyEmphasized
            result += run
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += markdown(ns.substring(from: cursor))
        }
        return result
    }

    /// The same text with every token and emphasis mark removed, for logs and accessibility
    /// strings that aren't rendered through `Text`.
    static func plain(_ source: String) -> String {
        let ns = source as NSString
        let untokened = token.stringByReplacingMatches(
            in: source, range: NSRange(location: 0, length: ns.length), withTemplate: "$2"
        )
        return String(markdown(untokened).characters)
    }

    private static func markdown(_ segment: String) -> AttributedString {
        (try? AttributedString(
            markdown: segment,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(segment)
    }

    private static func color(for tag: String) -> Color {
        switch tag {
        case "m":       Gender.der.color
        case "f":       Gender.die.color
        case "n":       Gender.das.color
        case "pl":      Gender.plural.color
        case "nom":     GrammarCase.nominativ.color
        case "akk":     GrammarCase.akkusativ.color
        case "dat":     GrammarCase.dativ.color
        case "gen":     GrammarCase.genitiv.color
        default:        CasePalette.wechsel
        }
    }
}

extension Text {
    /// A rule line, Kasus-Check step or explanation written in the `KasusRich` markup.
    init(kasusRich source: String) {
        self.init(KasusRich.attributed(source))
    }
}

#Preview("Kasus rich text") {
    VStack(alignment: .leading, spacing: 12) {
        Text(kasusRich: "Only *masculine* changes: {m:der} → {m:den}, {m:ein} → {m:einen}.")
        Text(kasusRich: "„mit“ always takes the {dat:Dativ}. Masculine Dativ in **mrmn** is *m*: {m:dem}.")
        Text(kasusRich: "{f:die}, {n:das} and {pl:die} look the same in {nom:Nominativ} and {akk:Akkusativ}.")
        Text(kasusRich: "Two-way: {wechsel:Wo?} → {dat:Dativ}, {wechsel:Wohin?} → {akk:Akkusativ}.")
    }
    .padding()
}
