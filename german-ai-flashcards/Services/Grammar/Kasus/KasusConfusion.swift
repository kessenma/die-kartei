//
//  KasusConfusion.swift
//  german-ai-flashcards
//
//  Verwechslungs-Paare: the two forms a learner mixes up most. Every round whose pick is a form
//  (Endungen, the Schnellrunde, Bau das Wort, Die Probe, the reflexive drills …) keeps each
//  answer with its pick and its right form in the round history (`KasusRoundItem`), so a
//  group-by turns „Dativ needs work“ into „you pick den where dem belongs“. Once one pair stands
//  clear of the rest, the hub and Coach's Notes show it with a two-button drill on exactly those
//  forms (`KasusDrillKind.pair`), which is practice and never moves the coach.
//

import Foundation

/// Two forms and how often one was picked for the other, either way round.
nonisolated struct KasusConfusionPair: Hashable {
    /// Lowercased, in alphabetical order, so den/dem and dem/den are one pair.
    let a: String
    let b: String
    let count: Int
    /// The gender the misses were mostly on (dem for den on masculine nouns), so the drill asks
    /// those nouns and not every gender the two forms happen to fit.
    let genus: Gender?

    init(a: String, b: String, count: Int, genus: Gender? = nil) {
        let pair = [a.lowercased(), b.lowercased()].sorted()
        self.a = pair[0]
        self.b = pair[1]
        self.count = count
        self.genus = genus
    }

    /// „dem ↔ den“
    var label: String { "\(a) ↔ \(b)" }
}

nonisolated enum KasusConfusion {

    /// A pair needs this many misses before it is worth a card …
    static let minimumMisses = 6
    /// … and at least this many times the runner-up's, so the card names a real habit.
    static let standoutRatio = 2.0

    /// Every pair of forms confused in `rounds`, most often first. Only rounds whose step's
    /// pick is a form, only answers the learner gave (never a revealed one), and only picks that
    /// are forms of the same family as the answer (den for dem; „meinem“ for „dem“ is a different
    /// word, not a mix-up of endings).
    static func pairs(rounds: [KasusRound]) -> [KasusConfusionPair] {
        var counts: [String: (pair: KasusConfusionPair, count: Int, genders: [Gender: Int])] = [:]
        for round in rounds where round.step?.meta.pickIsForm == true && round.isListed {
            for item in round.items {
                guard item.outcome != .right, !item.wasRevealed, let pick = item.pick else { continue }
                let answer = item.answer.lowercased()
                let picked = pick.lowercased()
                guard picked != answer,
                      let p = KasusForms.parseDeterminer(picked), let a = KasusForms.parseDeterminer(answer),
                      p.family == a.family, p.stem == a.stem else { continue }
                let pair = KasusConfusionPair(a: picked, b: answer, count: 0)
                let key = pair.label
                var entry = counts[key] ?? (pair, 0, [:])
                entry.count += 1
                if let genus = item.genus { entry.genders[genus, default: 0] += 1 }
                counts[key] = entry
            }
        }
        return counts.values
            .map { entry in
                let genus = entry.genders.max { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }?.key
                return KasusConfusionPair(a: entry.pair.a, b: entry.pair.b, count: entry.count, genus: genus)
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
    }

    /// The pair worth a card: the top one, with at least `minimumMisses` and at least
    /// `standoutRatio` times the runner-up.
    static func standout(rounds: [KasusRound]) -> KasusConfusionPair? {
        let ranked = pairs(rounds: rounds)
        guard let top = ranked.first, top.count >= minimumMisses else { return nil }
        if let next = ranked.dropFirst().first, Double(top.count) < Double(next.count) * standoutRatio { return nil }
        return top
    }

    /// The drill for a pair: ten sentences over the cases the two forms can show, on the nouns
    /// whose gender both forms fit, with only the two forms as buttons. Nil when the forms aren't
    /// one article family the endings drill knows, or can't span two cases.
    @MainActor static func drill(for pair: KasusConfusionPair) -> GrammarDrillSession? {
        guard let a = KasusForms.parseDeterminer(pair.a), let b = KasusForms.parseDeterminer(pair.b),
              a.family == b.family, a.stem == b.stem, let determiner = endingsDeterminer(a) else { return nil }
        let fitting = Set(Gender.allCases.filter {
            !KasusForms.compatibleCases(a, genus: $0).isEmpty && !KasusForms.compatibleCases(b, genus: $0).isEmpty
        })
        // The gender the misses were on, when both forms fit it; else every gender they fit.
        let genders: Set<Gender> = pair.genus.map { fitting.contains($0) ? [$0] : fitting } ?? fitting
        guard !genders.isEmpty else { return nil }
        var cases = Set<GrammarCase>()
        for genus in genders {
            cases.formUnion(KasusForms.compatibleCases(a, genus: genus))
            cases.formUnion(KasusForms.compatibleCases(b, genus: genus))
        }
        let inPlay = GrammarCase.allCases.filter(cases.contains)
        guard inPlay.count >= 2 else { return nil }
        // The first unit of the path that has every case the pair spans.
        guard let unit = KasusUnit.allCases.first(where: { Set($0.casesInPlay).isSuperset(of: cases) }) else { return nil }
        let config = EndingsConfig(style: .article, cases: inPlay, emphasis: nil, count: KasusRoundStep.pair.meta.roundSize,
                                   options: [pair.a, pair.b], genders: genders, determiners: [determiner])
        return GrammarDrillSession(kind: .pair, topic: .kasus(unit), variant: .endings(config))
    }

    /// The endings drill's family for a parsed determiner: der, ein, kein or mein. Other
    /// possessives and the der-words have no drill row.
    private static func endingsDeterminer(_ determiner: KasusDeterminer) -> EndingsDeterminer? {
        switch determiner.family {
        case .definite:   return .definite
        case .ein:        return .ein
        case .kein:       return .kein
        case .possessive: return determiner.stem == "mein" ? .mein : nil
        case .derWord:    return nil
        }
    }
}
