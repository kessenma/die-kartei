//
//  PastTenseVerbAuditTests.swift
//  german-ai-flashcardsTests
//
//  The regression net under `past_tense_verbs.json`. The file had no test at all, which is how
//  it came to ship `"Gestern habe ich ick."`, `"gewiederholt"` as a participle for *wiederholen*,
//  and 234 examples that were nothing but an auxiliary and a participle. The examples are now
//  retrieved from Tatoeba and gated by `training/scripts/past_tense_review.py`; these assertions
//  are what stops the next regeneration from quietly breaking them again.
//
//  Every rule here is also a rule in `scripts/check_content.py`, so a batch is caught offline
//  before it ever reaches the bundle. They are duplicated on purpose: the script gates the
//  pipeline, the test gates the app.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Past-tense verbs")
struct PastTenseVerbAuditTests {

    private static let entries = PastTenseVerbService.allEntries

    /// Auxiliary forms that may carry the Perfekt, for the agreement check below.
    private static let auxForms: [String: Set<String>] = [
        "haben": ["habe", "hast", "hat", "haben", "habt"],
        "sein": ["bin", "bist", "ist", "sind", "seid"],
    ]

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init))
    }

    @Test("The file loads and still has every level")
    func loads() {
        #expect(!Self.entries.isEmpty)
        for level in PastTenseLevel.allCases {
            #expect(!PastTenseVerbService.entries(for: level).isEmpty, "\(level.rawValue) is empty")
        }
    }

    @Test("An example contains the participle it is there to demonstrate")
    func exampleShowsItsParticiple() {
        let broken = Self.entries.filter { entry in
            guard let example = entry.example, !example.isEmpty else { return false }
            return !example.lowercased().contains(entry.pastParticiple.lowercased())
        }
        #expect(broken.isEmpty, Comment(rawValue: broken
            .map { "\($0.infinitive): \($0.pastParticiple) not in \"\($0.example ?? "")\"" }
            .joined(separator: "\n")))
    }

    @Test("The example uses the auxiliary the entry declares")
    func exampleUsesItsAuxiliary() {
        let wrong = Self.entries.filter { entry in
            guard let example = entry.example, !example.isEmpty,
                  let mine = Self.auxForms[entry.auxiliary],
                  let other = Self.auxForms[entry.auxiliary == "haben" ? "sein" : "haben"]
            else { return false }
            let used = Self.words(example)
            return used.isDisjoint(with: mine) && !used.isDisjoint(with: other)
        }
        #expect(wrong.isEmpty, Comment(rawValue: wrong
            .map { "\($0.infinitive) says \($0.auxiliary): \"\($0.example ?? "")\"" }
            .joined(separator: "\n")))
    }

    @Test("An example teaches more than an auxiliary and a participle")
    func exampleHasContent() {
        var filler: Set<String> = ["ich", "du", "er", "sie", "es", "wir", "ihr", "man",
                                   "gestern", "heute", "das", "mich", "mir", "sich"]
        filler.formUnion(Self.auxForms["haben"] ?? [])
        filler.formUnion(Self.auxForms["sein"] ?? [])
        let hollow = Self.entries.filter { entry in
            guard let example = entry.example, !example.isEmpty else { return false }
            return Self.words(example)
                .subtracting(filler)
                .subtracting([entry.pastParticiple.lowercased()])
                .isEmpty
        }
        #expect(hollow.isEmpty, Comment(rawValue: hollow
            .map { "\($0.infinitive): \"\($0.example ?? "")\"" }.joined(separator: "\n")))
    }

    @Test("A separable verb's participle carries its prefix")
    func separablePrefix() {
        let wrong = Self.entries.filter { entry in
            guard entry.isSeparable, let prefix = entry.prefix, !prefix.isEmpty else { return false }
            return !entry.pastParticiple.lowercased().hasPrefix(prefix.lowercased())
        }
        #expect(wrong.isEmpty, Comment(rawValue: wrong
            .map { "\($0.infinitive): \($0.pastParticiple) vs prefix \($0.prefix ?? "")" }
            .joined(separator: "\n")))
    }

    /// `PastTenseVerbEntry.id` is the infinitive, so a level's deck must not list one twice.
    @Test("An infinitive appears once per level")
    func uniquePerLevel() {
        for level in PastTenseLevel.allCases {
            let infinitives = PastTenseVerbService.entries(for: level).map(\.infinitive)
            let duplicates = Dictionary(grouping: infinitives, by: { $0 })
                .filter { $0.value.count > 1 }.keys.sorted()
            #expect(duplicates.isEmpty, "\(level.rawValue) lists \(duplicates) more than once")
        }
    }

    /// A verb listed at two levels is the same verb: it must not disagree with itself about
    /// anything a learner is taught.
    @Test("Level copies of one verb agree")
    func copiesAgree() {
        var problems: [String] = []
        for (infinitive, rows) in Dictionary(grouping: Self.entries, by: \.infinitive)
        where rows.count > 1 {
            for field in ["auxiliary", "pastParticiple", "example", "isSeparable", "prefix"] {
                let values: Set<String> = switch field {
                case "auxiliary":      Set(rows.map(\.auxiliary))
                case "pastParticiple": Set(rows.map(\.pastParticiple))
                case "example":        Set(rows.map { $0.example ?? "" })
                case "isSeparable":    Set(rows.map { "\($0.isSeparable)" })
                default:               Set(rows.map { $0.prefix ?? "" })
                }
                if values.count > 1 {
                    problems.append("\(infinitive) disagrees on \(field): \(values.sorted())")
                }
            }
        }
        #expect(problems.isEmpty, Comment(rawValue: problems.joined(separator: "\n")))
    }
}
