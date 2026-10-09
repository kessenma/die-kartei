//
//  KasusConceptFixtures.swift
//  german-ai-flashcards
//
//  The golden numbers for the bundled Verstehen items, per unit and kind, and the verifier
//  `-kasus.debugVerify 1` prints after the stories (the tests run the same). A change to an
//  item's text, targets or the rules that moves a number shows up here. Every unit × kind that has
//  items needs a row; an empty row means "add it".
//

#if DEBUG
import Foundation

enum KasusConceptFixtures {

    /// What a unit's items of one kind must come out as.
    struct Golden: Hashable {
        let items: Int
        let targets: Int
        let byCase: [GrammarCase: Int]
        let proofs: [KasusProof: Int]
        /// Wer …? items whose first phrase isn't the doer.
        var ovs = 0
    }

    /// Keyed `"<unit>/<kind>"`.
    static let golden: [String: Golden] = [
        "nominativ/roles": Golden(items: 50, targets: 86, byCase: [.nominativ: 57, .dativ: 29],
                      proofs: [.form: 47, .preposition: 12, .copula: 2, .label: 25]),
        "akkusativ/roles": Golden(items: 51, targets: 138, byCase: [.nominativ: 51, .akkusativ: 73, .dativ: 14],
                      proofs: [.form: 85, .preposition: 15, .copula: 1, .label: 37]),
        "akkusativ/whoDoesWhat": Golden(items: 50, targets: 117, byCase: [.nominativ: 50, .akkusativ: 50, .dativ: 17],
                      proofs: [.form: 65, .preposition: 2, .copula: 0, .label: 50], ovs: 18),
        "akkusativ/sameMeaning": Golden(items: 4, targets: 16, byCase: [.nominativ: 8, .akkusativ: 8],
                      proofs: [.form: 10, .preposition: 0, .copula: 0, .label: 6]),
        "akkusativ/probe": Golden(items: 50, targets: 115, byCase: [.nominativ: 49, .akkusativ: 50, .dativ: 16],
                      proofs: [.form: 60, .preposition: 3, .copula: 0, .label: 52]),
        "dativ/roles": Golden(items: 51, targets: 134, byCase: [.nominativ: 51, .akkusativ: 26, .dativ: 57],
                      proofs: [.form: 86, .preposition: 4, .copula: 0, .label: 44]),
        "dativ/whoDoesWhat": Golden(items: 50, targets: 122, byCase: [.nominativ: 50, .akkusativ: 8, .dativ: 64],
                      proofs: [.form: 62, .preposition: 11, .copula: 0, .label: 49], ovs: 25),
        "dativ/sameMeaning": Golden(items: 4, targets: 18, byCase: [.nominativ: 8, .akkusativ: 2, .dativ: 8],
                      proofs: [.form: 12, .preposition: 0, .copula: 0, .label: 6]),
        "dativ/probe": Golden(items: 50, targets: 132, byCase: [.nominativ: 48, .akkusativ: 16, .dativ: 68],
                      proofs: [.form: 62, .preposition: 17, .copula: 0, .label: 53]),
        "genitiv/roles": Golden(items: 81, targets: 234, byCase: [.nominativ: 82, .akkusativ: 33, .dativ: 38, .genitiv: 81],
                      proofs: [.form: 132, .preposition: 25, .copula: 1, .label: 76]),
        "genitiv/whoDoesWhat": Golden(items: 38, targets: 125, byCase: [.nominativ: 38, .akkusativ: 23, .dativ: 26, .genitiv: 38],
                      proofs: [.form: 73, .preposition: 4, .copula: 0, .label: 48], ovs: 20),
        "genitiv/sameMeaning": Golden(items: 4, targets: 24, byCase: [.nominativ: 8, .akkusativ: 4, .dativ: 4, .genitiv: 8],
                      proofs: [.form: 16, .preposition: 0, .copula: 0, .label: 8]),
        "genitiv/probe": Golden(items: 78, targets: 206, byCase: [.nominativ: 78, .akkusativ: 28, .dativ: 53, .genitiv: 47],
                      proofs: [.form: 106, .preposition: 25, .copula: 0, .label: 75]),
        "alleFaelle/roles": Golden(items: 51, targets: 193, byCase: [.nominativ: 51, .akkusativ: 69, .dativ: 50, .genitiv: 23],
                      proofs: [.form: 129, .preposition: 21, .copula: 0, .label: 43]),
        "alleFaelle/whoDoesWhat": Golden(items: 50, targets: 109, byCase: [.nominativ: 50, .akkusativ: 33, .dativ: 24, .genitiv: 2],
                      proofs: [.form: 59, .preposition: 0, .copula: 0, .label: 50], ovs: 24),
        "alleFaelle/sameMeaning": Golden(items: 4, targets: 22, byCase: [.nominativ: 8, .akkusativ: 6, .dativ: 8],
                      proofs: [.form: 15, .preposition: 0, .copula: 0, .label: 7]),
        "alleFaelle/probe": Golden(items: 50, targets: 133, byCase: [.nominativ: 50, .akkusativ: 20, .dativ: 46, .genitiv: 17],
                      proofs: [.form: 65, .preposition: 24, .copula: 0, .label: 44]),
    ]

    /// Audits every bundled item, group by group, against the golden numbers. The text's lines
    /// read like
    /// "concepts akkusativ/whoDoesWhat OK · 8 items · 16 targets · Nom 8 · Akk 8 · form 8 · label 8 · OVS 4 · golden ✓".
    static func verify(bank: KasusConceptBank, lexicon: some KasusLexicon) -> KasusFixtures.VerifyResult {
        var lines: [String] = []
        var failures: [String] = []
        var ids = Set<String>()

        for unit in KasusUnit.allCases {
            for kind in KasusConceptKind.allCases {
                let items = bank.items(for: unit, kind: kind)
                guard !items.isEmpty else { continue }
                let key = "\(unit.rawValue)/\(kind.rawValue)"
                var targets = 0
                var byCase: [GrammarCase: Int] = [:]
                var proofs: [KasusProof: Int] = [:]
                var ovs = 0
                var problems: [String] = []
                for item in items {
                    if !ids.insert(item.id).inserted { problems.append("\(item.id): duplicate id") }
                    let audit = KasusConceptBank.audit(item, lexicon: lexicon)
                    targets += audit.report.located.count
                    for target in audit.report.located {
                        byCase[target.kasus, default: 0] += 1
                        proofs[target.proof, default: 0] += 1
                    }
                    if audit.facts.isOVS { ovs += 1 }
                    problems += audit.problems.map { "\(item.id): \($0)" }
                    for (index, phrase) in item.english where !item.story.paragraphs.contains(where: { $0.en.contains(phrase) }) {
                        problems.append("\(item.id): #\(index + 1) „\(phrase)“ isn't in the English line")
                    }
                }
                var parts = ["concepts \(key) \(problems.isEmpty ? "OK" : "FAIL")", "\(items.count) items", "\(targets) targets"]
                parts += GrammarCase.allCases.compactMap { kasus in byCase[kasus].map { "\(kasus.short) \($0)" } }
                parts += KasusProof.allCases.compactMap { proof in proofs[proof].map { "\(proof.rawValue) \($0)" } }
                if kind == .whoDoesWhat { parts.append("OVS \(ovs)") }
                var misses: [String] = []
                if let golden = golden[key] {
                    if items.count != golden.items { misses.append("items \(items.count) ≠ \(golden.items)") }
                    if targets != golden.targets { misses.append("targets \(targets) ≠ \(golden.targets)") }
                    for kasus in GrammarCase.allCases where byCase[kasus, default: 0] != golden.byCase[kasus, default: 0] {
                        misses.append("\(kasus.short) \(byCase[kasus, default: 0]) ≠ \(golden.byCase[kasus, default: 0])")
                    }
                    for proof in KasusProof.allCases where proofs[proof, default: 0] != golden.proofs[proof, default: 0] {
                        misses.append("\(proof.rawValue) \(proofs[proof, default: 0]) ≠ \(golden.proofs[proof, default: 0])")
                    }
                    if kind == .whoDoesWhat, ovs != golden.ovs { misses.append("OVS \(ovs) ≠ \(golden.ovs)") }
                } else {
                    misses.append("none: add \(key) to KasusConceptFixtures.golden")
                }
                parts.append(misses.isEmpty ? "golden ✓" : "golden ✗ " + misses.joined(separator: ", "))
                lines.append(parts.joined(separator: " · "))
                lines += problems.map { "  " + $0 }
                failures += problems
                failures += misses.map { "\(key) golden: \($0)" }
            }
            let offered = bank.offered(for: unit).map(\.rawValue).joined(separator: " · ")
            lines.append("  offered \(unit.rawValue): \(offered.isEmpty ? "nothing" : offered)")
        }

        lines.append(failures.isEmpty ? "Concepts ALL OK" : "Concepts \(failures.count) FAILED")
        return KasusFixtures.VerifyResult(text: lines.joined(separator: "\n"), failures: failures)
    }
}
#endif
