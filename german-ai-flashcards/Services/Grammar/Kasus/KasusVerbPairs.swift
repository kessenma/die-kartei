//
//  KasusVerbPairs.swift
//  german-ai-flashcards
//
//  Verbs that fix their preposition's case („warten auf“ + Akkusativ, „Angst haben vor“ +
//  Dativ), as the Kasus check reads them. The data is the Verben-mit-Präpositionen list
//  (verb_prepositions.json); this turns it into a lookup: given a preposition and the words of a
//  phrase's part of its clause, is a pair's verb there, and which case does it fix?
//
//  Why the Kasus check needs it: after a two-way preposition the article's form usually leaves
//  one case, so a generated story's „wartet auf dem Bus“ used to read as a correct Dativ (a
//  place, Wo?). The pair says Akkusativ, whatever moves. With this, the validator and the
//  harvest let the pair decide (docs/KASUS.md, "Verb pairs").
//

import Foundation

/// A verb pair found around a phrase: the pair's infinitive („sich freuen über“), its
/// preposition, the case it fixes, and whether that preposition can also be a plain place with
/// this verb (`spatialToo`), which makes a clash ambiguous rather than wrong.
nonisolated struct KasusVerbPairMatch: Hashable {
    let verb: String
    let preposition: String
    let kasus: GrammarCase
    let spatialToo: Bool
}

@MainActor
enum KasusVerbPairs {

    private struct Entry {
        let match: KasusVerbPairMatch
        /// Each form as the words that must all stand in the clause.
        let forms: [Set<String>]
    }

    /// Entries by preposition.
    private static let byPreposition: [String: [Entry]] = {
        var out: [String: [Entry]] = [:]
        for pair in VerbPrepositionService.all() {
            guard let kasus: GrammarCase = pair.governs == .akkusativ ? .akkusativ
                    : pair.governs == .dativ ? .dativ : nil else { continue }
            let entry = Entry(
                match: KasusVerbPairMatch(verb: pair.verb, preposition: pair.preposition,
                                          kasus: kasus, spatialToo: pair.spatialToo ?? false),
                forms: pair.forms.map { Set($0.lowercased().split(separator: " ").map(String.init)) }
            )
            out[pair.preposition, default: []].append(entry)
        }
        return out
    }()

    /// The pair whose verb stands among `words` (lowercased tokens of the phrase's part of its
    /// clause, the phrase itself left out) and takes `preposition`. Nil when none does, or when
    /// two pairs that fix different cases both stand there, which leaves it open.
    static func match(preposition: String, among words: Set<String>) -> KasusVerbPairMatch? {
        let found = (byPreposition[preposition.lowercased()] ?? []).filter { entry in
            entry.forms.contains { $0.isSubset(of: words) }
        }
        guard let first = found.first else { return nil }
        guard found.allSatisfy({ $0.match.kasus == first.match.kasus }) else { return nil }
        return first.match
    }
}
