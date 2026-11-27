@testable import DieKarteiCore
import Foundation
import SwiftUI

/// The case path's lesson markup (iOS: KasusRichText.swift), for Android:
///   {m:den} {f:die} {n:das} {pl:die}   a form in its gender colour, bold
///   {nom:…} {akk:…} {dat:…} {gen:…} {wechsel:…}   a case word in its case colour, bold
///   **bold** and *italic*
/// Parsed by hand rather than through AttributedString(markdown:), which Android's
/// Foundation may not carry.
enum KasusRichAndroid {
    static func attributed(_ source: String, dark: Bool) -> AttributedString {
        var result = AttributedString()
        var plain = ""
        var bold = false
        var italic = false
        let chars = Array(source)
        var i = 0

        func flush() {
            guard !plain.isEmpty else { return }
            var run = AttributedString(plain)
            if bold && italic {
                run.inlinePresentationIntent = [.stronglyEmphasized, .emphasized]
            } else if bold {
                run.inlinePresentationIntent = .stronglyEmphasized
            } else if italic {
                run.inlinePresentationIntent = .emphasized
            }
            result += run
            plain = ""
        }

        while i < chars.count {
            let c = chars[i]
            if c == "{", let close = chars[i...].firstIndex(of: "}"),
               let colon = chars[i..<close].firstIndex(of: ":") {
                let tag = String(chars[(i + 1)..<colon])
                let text = String(chars[(colon + 1)..<close])
                if let color = color(for: tag, dark: dark) {
                    flush()
                    var run = AttributedString(text)
                    run.foregroundColor = color
                    run.inlinePresentationIntent = .stronglyEmphasized
                    result += run
                    i = close + 1
                    continue
                }
            }
            if c == "*" {
                flush()
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    bold.toggle()
                    i += 2
                } else {
                    italic.toggle()
                    i += 1
                }
                continue
            }
            plain.append(c)
            i += 1
        }
        flush()
        return result
    }

    static func color(for tag: String, dark: Bool) -> Color? {
        switch tag {
        case "m": AndroidPalette.gender(.der, dark: dark)
        case "f": AndroidPalette.gender(.die, dark: dark)
        case "n": AndroidPalette.gender(.das, dark: dark)
        case "pl": AndroidPalette.gender(.plural, dark: dark)
        case "nom": AndroidPalette.kasus(.nominativ, dark: dark)
        case "akk": AndroidPalette.kasus(.akkusativ, dark: dark)
        case "dat": AndroidPalette.kasus(.dativ, dark: dark)
        case "gen": AndroidPalette.kasus(.genitiv, dark: dark)
        case "wechsel": AndroidPalette.hex(dark ? 0xA98BF5 : 0x7B4FD6)
        default: nil
        }
    }
}

struct RichText: View {
    let source: String
    @Environment(\.colorScheme) var scheme

    init(_ source: String) { self.source = source }

    var body: some View {
        Text(KasusRichAndroid.attributed(source, dark: scheme == .dark))
    }
}

/// The four cases' lessons from the case path (KasusLesson.cards), one page at a time.
struct KasusLessonsView: View {
    var body: some View {
        List {
            ForEach(KasusUnit.allCases) { unit in
                NavigationLink {
                    KasusLessonView(unit: unit)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unit.germanTitle)
                        Text(unit.englishRole).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Kasus-Lektionen")
    }
}

struct KasusLessonView: View {
    let unit: KasusUnit
    @State var page = 0

    var cards: [KasusLessonCard] { KasusLesson.cards(for: unit) }

    var body: some View {
        VStack(spacing: 12) {
            if cards.isEmpty {
                Text("Keine Lektion")
            } else {
                let card = cards[min(page, cards.count - 1)]
                Text("Seite \(page + 1) von \(cards.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(card.title).font(.title2).bold()
                        Text(card.english).foregroundStyle(.secondary)
                        ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                            RichText(line)
                        }
                        if let example = card.example {
                            VStack(alignment: .leading, spacing: 6) {
                                RichText(example.de).font(.title3)
                                RichText(example.en).foregroundStyle(.secondary)
                                ForEach(Array(example.steps.enumerated()), id: \.offset) { _, step in
                                    RichText("\(step.checkStep). **\(step.phrase)**: \(step.line)")
                                        .font(.footnote)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                        }
                        if let mnemonic = card.mnemonic {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mnemonic.title).font(.headline)
                                RichText(mnemonic.line)
                                RichText(mnemonic.why).font(.footnote).foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.15)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Zurück") { page -= 1 }
                        .disabled(page == 0)
                    Spacer()
                    Button("Weiter") { page += 1 }
                        .buttonStyle(.borderedProminent)
                        .disabled(page + 1 >= cards.count)
                }
            }
        }
        .padding()
        .navigationTitle(unit.germanTitle)
    }
}
