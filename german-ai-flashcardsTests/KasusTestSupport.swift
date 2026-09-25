//
//  KasusTestSupport.swift
//  german-ai-flashcardsTests
//
//  Shared pieces for the Kasus engine tests. The tests run hosted in the app, so `Bundle.main` is
//  the app bundle and `AppKasusLexicon` reads the real Wiktionary database and Goethe lists: the
//  same answer key `-kasus.debugVerify 1` prints, as assertions.
//

import Foundation
import Testing
@testable import Die_Kartei

/// The bundled stories, decoded straight from the app bundle. Not `KasusStoryBank.bundled`: its
/// DEBUG assert would crash the whole run on a broken story instead of failing one test.
enum KasusTestData {
    static let lexicon = AppKasusLexicon()

    static let stories: [KasusStory] = BundledStories.file?.stories ?? []

    static func story(_ id: String) -> KasusStory? {
        stories.first { $0.id == id }
    }

    /// Validated under the story's own source policy, as the player does.
    static func report(_ story: KasusStory) -> KasusReport {
        KasusValidator.validate(story, source: story.source, lexicon: lexicon)
    }

    /// „Der verlorene Schlüssel“, the Phase 1 story every service expectation was written for.
    static let schluesselID = "ks-dat-a2-schluessel"
}

/// Story ids for parameterized tests. Nonisolated, so `@Test(arguments:)` can read it.
nonisolated enum BundledStories {
    static let file: KasusStoryFile? = {
        guard let url = Bundle.main.url(forResource: "kasus_stories", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(KasusStoryFile.self, from: data)
    }()

    static let ids: [String] = file?.stories.map(\.id) ?? []
}

/// Checks a string written in the `KasusRich` markup the way the renderer will read it:
/// `{tag:text}` tokens with a known tag, no stray braces, and `**` / `*` pairing up within each
/// stretch between tokens (the renderer parses Markdown per stretch, so emphasis can't span a
/// token). Returns what's wrong, empty when it renders cleanly.
enum RichMarkup {
    static let token = try! NSRegularExpression(pattern: #"\{(m|f|n|pl|nom|akk|dat|gen|wechsel):([^{}]+)\}"#)

    static func problems(_ source: String) -> [String] {
        var problems: [String] = []
        let ns = source as NSString
        var segments: [String] = []
        var cursor = 0
        for match in token.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            segments.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length
        }
        segments.append(ns.substring(from: cursor))
        for segment in segments {
            if segment.contains("{") || segment.contains("}") { problems.append("stray brace in „\(segment)“") }
            let bold = segment.components(separatedBy: "**").count - 1
            let single = segment.replacingOccurrences(of: "**", with: "").filter { $0 == "*" }.count
            if bold % 2 != 0 || single % 2 != 0 { problems.append("unpaired emphasis in „\(segment)“") }
        }
        let plain = KasusRich.plain(source)
        if plain.contains(where: { "*{}".contains($0) }) { problems.append("markup left in the plain text: \(plain)") }
        return problems
    }
}
