//
//  GermanStem.swift
//  german-ai-flashcards
//
//  CISTEM, the German stemmer of Weissweiler & Fraser (2017, „Developing a Stemmer for German
//  Based on a Comparative Analysis of Publicly Available Stemmers“, GSCL), case-insensitive variant,
//  plus one rule of ours: „-nisse(n)“ is „-nis“, so „Kenntnisse“ and „Kenntnis“ meet.
//
//  Only ever a grouping key — two spellings with the same stem are one word in a count. It is
//  never shown, and never written to a card: „entwickeln“, „entwickelst“ and „entwickelt“ all
//  stem to „entwickel“, which is not a word.
//

import Foundation

nonisolated enum GermanStem {

    static func stem(_ word: String) -> String {
        var w = word.lowercased()
        guard !w.isEmpty else { return w }
        w = w.replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ä", with: "a")
            .replacingOccurrences(of: "ß", with: "ss")
        if w.hasSuffix("nissen") { w = String(w.dropLast(3)) } else if w.hasSuffix("nisse") { w = String(w.dropLast(2)) }
        // A „ge-“ in front of at least four more letters.
        if w.hasPrefix("ge"), w.count >= 6 { w = String(w.dropFirst(2)) }
        // Letter groups the suffix rules must not cut into, each one character for now.
        w = w.replacingOccurrences(of: "sch", with: "$")
            .replacingOccurrences(of: "ei", with: "%")
            .replacingOccurrences(of: "ie", with: "&")
        w = markDoubles(w)

        while w.count > 3 {
            if w.count > 5 {
                if w.hasSuffix("em") || w.hasSuffix("er") { w.removeLast(2); continue }
                if w.hasSuffix("nd") { w.removeLast(2); continue }
            }
            if w.hasSuffix("t") { w.removeLast(); continue }
            if let last = w.last, "esn".contains(last) { w.removeLast(); continue }
            break
        }

        w = unmarkDoubles(w)
        return w.replacingOccurrences(of: "&", with: "ie")
            .replacingOccurrences(of: "%", with: "ei")
            .replacingOccurrences(of: "$", with: "sch")
    }

    /// „nn“ → „n*“, so a doubled letter at the end isn't stripped as an ending.
    private static func markDoubles(_ w: String) -> String {
        var out = ""
        var previous: Character? = nil
        for c in w {
            if let previous, c == previous, c != "*" {
                out.append("*")
            } else {
                out.append(c)
            }
            previous = c
        }
        return out
    }

    private static func unmarkDoubles(_ w: String) -> String {
        var out = ""
        var previous: Character? = nil
        for c in w {
            if c == "*", let previous { out.append(previous) } else { out.append(c) }
            previous = c == "*" ? previous : c
        }
        return out
    }
}
