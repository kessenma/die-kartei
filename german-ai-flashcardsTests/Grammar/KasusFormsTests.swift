//
//  KasusFormsTests.swift
//  german-ai-flashcardsTests
//
//  The forms engine against the endings table as a teacher writes it: every cell, read forwards
//  (`form`) and backwards (`compatibleCases`), the gaps (ein and jeder have no plural), euer's
//  dropped e, the answer buttons each hint level offers, and the slips.
//

import Foundation
import Testing
@testable import Die_Kartei

/// One determiner family's table, m · f · n · pl per case, written out by hand rather than derived
/// from `GrammarCase.article`, so the engine is checked against the table and not against itself.
nonisolated struct FormTable: Sendable, CustomTestStringConvertible {
    let family: KasusFamily
    let stem: String
    let rows: [GrammarCase: [String?]]

    var testDescription: String { stem.isEmpty ? "der · die · das" : "\(stem)-" }

    func cell(_ kasus: GrammarCase, _ column: Int) -> String? {
        rows[kasus].flatMap { $0[column] }
    }

    static let einEndings: [GrammarCase: [String]] = [
        .nominativ: ["", "e", "", "e"],
        .akkusativ: ["en", "e", "", "e"],
        .dativ:     ["em", "er", "em", "en"],
        .genitiv:   ["es", "er", "es", "er"],
    ]

    static let derWordEndings: [GrammarCase: [String]] = [
        .nominativ: ["er", "e", "es", "e"],
        .akkusativ: ["en", "e", "es", "e"],
        .dativ:     ["em", "er", "em", "en"],
        .genitiv:   ["es", "er", "es", "er"],
    ]

    static func table(_ family: KasusFamily, _ stem: String, endings: [GrammarCase: [String]],
                      plural: Bool = true) -> FormTable {
        FormTable(family: family, stem: stem, rows: endings.mapValues { row in
            row.enumerated().map { column, ending in column == 3 && !plural ? nil : stem + ending }
        })
    }

    static let all: [FormTable] = [
        FormTable(family: .definite, stem: "", rows: [
            .nominativ: ["der", "die", "das", "die"],
            .akkusativ: ["den", "die", "das", "die"],
            .dativ:     ["dem", "der", "dem", "den"],
            .genitiv:   ["des", "der", "des", "der"],
        ]),
        table(.ein, "ein", endings: einEndings, plural: false),
        table(.kein, "kein", endings: einEndings),
        table(.possessive, "mein", endings: einEndings),
        table(.possessive, "dein", endings: einEndings),
        table(.possessive, "sein", endings: einEndings),
        table(.possessive, "ihr", endings: einEndings),
        table(.possessive, "unser", endings: einEndings),
        FormTable(family: .possessive, stem: "euer", rows: [
            .nominativ: ["euer", "eure", "euer", "eure"],
            .akkusativ: ["euren", "eure", "euer", "eure"],
            .dativ:     ["eurem", "eurer", "eurem", "euren"],
            .genitiv:   ["eures", "eurer", "eures", "eurer"],
        ]),
        table(.derWord, "dies", endings: derWordEndings),
        table(.derWord, "jed", endings: derWordEndings, plural: false),
        table(.derWord, "welch", endings: derWordEndings),
    ]
}

/// A family's whole set of answer buttons, in table order.
nonisolated struct FamilyOptions: Sendable, CustomTestStringConvertible {
    let family: KasusFamily
    let stem: String
    let genitive: Bool
    let expected: [String]

    var testDescription: String { "\(stem.isEmpty ? "der" : stem)\(genitive ? " + Gen" : "")" }

    static let all: [FamilyOptions] = [
        FamilyOptions(family: .definite, stem: "", genitive: false, expected: ["der", "die", "das", "den", "dem"]),
        FamilyOptions(family: .definite, stem: "", genitive: true, expected: ["der", "die", "das", "den", "dem", "des"]),
        FamilyOptions(family: .ein, stem: "ein", genitive: false, expected: ["ein", "eine", "einen", "einem", "einer"]),
        FamilyOptions(family: .ein, stem: "ein", genitive: true, expected: ["ein", "eine", "einen", "einem", "einer", "eines"]),
        FamilyOptions(family: .kein, stem: "kein", genitive: false, expected: ["kein", "keine", "keinen", "keinem", "keiner"]),
        FamilyOptions(family: .possessive, stem: "euer", genitive: true, expected: ["euer", "eure", "euren", "eurem", "eurer", "eures"]),
        FamilyOptions(family: .derWord, stem: "dies", genitive: false, expected: ["dieser", "diese", "dieses", "diesen", "diesem"]),
        FamilyOptions(family: .derWord, stem: "jed", genitive: true, expected: ["jeder", "jede", "jedes", "jeden", "jedem"]),
    ]
}

/// Viel Hilfe: the noun's own gender through the cases in play, plus one other form below three.
nonisolated struct VielHilfeCase: Sendable, CustomTestStringConvertible {
    let answer: String
    let family: KasusFamily
    let stem: String
    let genus: Gender
    let genitive: Bool
    let expected: [String]

    var testDescription: String { "\(answer) (\(genus.columnLabel))\(genitive ? " + Gen" : "")" }

    static let all: [VielHilfeCase] = [
        VielHilfeCase(answer: "dem", family: .definite, stem: "", genus: .der, genitive: false, expected: ["der", "den", "dem"]),
        VielHilfeCase(answer: "dem", family: .definite, stem: "", genus: .der, genitive: true, expected: ["der", "den", "dem", "des"]),
        VielHilfeCase(answer: "der", family: .definite, stem: "", genus: .die, genitive: false, expected: ["die", "der", "dem"]),
        VielHilfeCase(answer: "dem", family: .definite, stem: "", genus: .das, genitive: false, expected: ["das", "dem", "den"]),
        VielHilfeCase(answer: "den", family: .definite, stem: "", genus: .plural, genitive: false, expected: ["die", "den", "dem"]),
        VielHilfeCase(answer: "seiner", family: .possessive, stem: "sein", genus: .die, genitive: false, expected: ["seine", "seiner", "seinem"]),
        VielHilfeCase(answer: "einen", family: .ein, stem: "ein", genus: .der, genitive: false, expected: ["ein", "einen", "einem"]),
        VielHilfeCase(answer: "diesem", family: .derWord, stem: "dies", genus: .der, genitive: false, expected: ["dieser", "diesen", "diesem"]),
    ]
}

/// A wrong pick and whether it is the right case for another singular gender.
nonisolated struct GenderSlipCase: Sendable, CustomTestStringConvertible {
    let pick: String
    let kasus: GrammarCase
    let genus: Gender
    var family: KasusFamily = .definite
    var stem: String = ""
    let isSlip: Bool
    let why: String

    var testDescription: String { "„\(pick)“ for \(kasus.short) \(genus.columnLabel): \(why)" }

    static let all: [GenderSlipCase] = [
        GenderSlipCase(pick: "der", kasus: .dativ, genus: .der, isSlip: false, why: "the Nominativ left unchanged (auf der Boden)"),
        GenderSlipCase(pick: "den", kasus: .dativ, genus: .der, isSlip: false, why: "den for dem is also the masculine Akkusativ"),
        GenderSlipCase(pick: "das", kasus: .akkusativ, genus: .der, isSlip: true, why: "neuter Akkusativ"),
        GenderSlipCase(pick: "die", kasus: .akkusativ, genus: .der, isSlip: true, why: "feminine Akkusativ"),
        GenderSlipCase(pick: "dem", kasus: .dativ, genus: .die, isSlip: true, why: "in dem Tasche"),
        GenderSlipCase(pick: "die", kasus: .akkusativ, genus: .die, isSlip: false, why: "the answer itself"),
        GenderSlipCase(pick: "der", kasus: .akkusativ, genus: .die, isSlip: false, why: "the noun's own Dativ"),
        GenderSlipCase(pick: "der", kasus: .dativ, genus: .das, isSlip: true, why: "feminine Dativ"),
        GenderSlipCase(pick: "dem", kasus: .dativ, genus: .plural, isSlip: false, why: "a plural answer never slips on gender"),
        GenderSlipCase(pick: "ein", kasus: .akkusativ, genus: .der, family: .ein, stem: "ein", isSlip: false, why: "ein for einen is a case miss"),
        GenderSlipCase(pick: "eine", kasus: .akkusativ, genus: .der, family: .ein, stem: "ein", isSlip: true, why: "feminine Akkusativ"),
        GenderSlipCase(pick: "dieser", kasus: .dativ, genus: .der, family: .derWord, stem: "dies", isSlip: false, why: "like der for dem"),
        GenderSlipCase(pick: "diese", kasus: .akkusativ, genus: .der, family: .derWord, stem: "dies", isSlip: true, why: "feminine Akkusativ"),
    ]
}

@Suite("Kasus forms engine")
struct KasusFormsTests {

    // MARK: The table

    @Test("The engine writes every cell of the endings table", arguments: FormTable.all)
    func tableForms(_ table: FormTable) {
        for kasus in GrammarCase.allCases {
            for (column, genus) in Gender.allCases.enumerated() {
                let engine = KasusForms.form(family: table.family, stem: table.stem, case: kasus, genus: genus)
                #expect(engine == table.cell(kasus, column), "\(kasus.short) \(genus.columnLabel)")
            }
        }
    }

    @Test("compatibleCases reads every real cell back to exactly the cases that share it", arguments: FormTable.all)
    func compatibleCasesRoundTrip(_ table: FormTable) {
        for (column, genus) in Gender.allCases.enumerated() {
            var byForm: [String: Set<GrammarCase>] = [:]
            for kasus in GrammarCase.allCases {
                if let form = table.cell(kasus, column) { byForm[form, default: []].insert(kasus) }
            }
            for (form, cases) in byForm {
                for written in [form, form.capitalized] {
                    #expect(KasusForms.compatibleCases(determiner: written, genus: genus) == cases,
                            "„\(written)“ with a \(genus.columnLabel) noun")
                }
                let parsed = KasusForms.parseDeterminer(form)
                #expect(parsed?.family == table.family, "„\(form)“ parses as \(String(describing: parsed?.family))")
                #expect(parsed?.stem == table.stem, "„\(form)“ parses with stem \(parsed?.stem ?? "nil")")
            }
        }
    }

    @Test("The debug round trip passes over all 184 cells")
    func fixtureRoundTrip() {
        let result = KasusFixtures.roundTrip()
        #expect(result.failures.isEmpty, "\(result.failures.joined(separator: "\n"))")
        // 12 families × 16 cells, less the 4 plural cells ein and jeder don't have, twice.
        #expect(result.cells == 184)
    }

    @Test("ein and jeder have no plural; kein does")
    func missingPlurals() {
        for kasus in GrammarCase.allCases {
            #expect(KasusForms.form(family: .ein, stem: "ein", case: kasus, genus: .plural) == nil)
            #expect(KasusForms.form(family: .derWord, stem: "jed", case: kasus, genus: .plural) == nil)
        }
        for (family, stem) in [(KasusFamily.ein, "ein"), (.derWord, "jed")] {
            for form in KasusForms.fullFamilyOptions(family: family, stem: stem, includeGenitive: true) {
                #expect(KasusForms.compatibleCases(determiner: form, genus: .plural).isEmpty,
                        "„\(form)“ fits a plural noun")
            }
        }
        #expect(KasusForms.compatibleCases(determiner: "keine", genus: .plural) == [.nominativ, .akkusativ])
        #expect(KasusForms.compatibleCases(determiner: "keinen", genus: .plural) == [.dativ])
    }

    @Test("euer drops its second e before an ending")
    func euer() {
        #expect(KasusForms.form(family: .possessive, stem: "euer", case: .nominativ, genus: .der) == "euer")
        #expect(KasusForms.form(family: .possessive, stem: "euer", case: .akkusativ, genus: .der) == "euren")
        #expect(KasusForms.form(family: .possessive, stem: "euer", case: .nominativ, genus: .die) == "eure")
        #expect(KasusForms.parseDeterminer("euer") == KasusDeterminer(family: .possessive, stem: "euer", ending: "", word: "euer"))
        #expect(KasusForms.parseDeterminer("Euren") == KasusDeterminer(family: .possessive, stem: "euer", ending: "en", word: "euren"))
        #expect(KasusForms.parseDeterminer("eueren") == nil)
        #expect(KasusForms.parseDeterminer("eur") == nil)
    }

    @Test("Other determiner readings")
    func parsing() {
        #expect(KasusForms.parseDeterminer("Der") == KasusDeterminer(family: .definite, stem: "", ending: "der", word: "der"))
        #expect(KasusForms.parseDeterminer("SEINEN")?.family == .possessive)
        #expect(KasusForms.parseDeterminer("Welchem")?.family == .derWord)
        #expect(KasusForms.parseDeterminer("dies") == nil, "a bare der-word stem")
        #expect(KasusForms.parseDeterminer("jed") == nil, "a bare der-word stem")
        #expect(KasusForms.parseDeterminer("Hund") == nil)
        #expect(KasusForms.compatibleCases(determiner: "Der", genus: .die) == [.dativ, .genitiv])
        #expect(KasusForms.compatibleCases(determiner: "welches", genus: .das) == [.nominativ, .akkusativ, .genitiv])
        #expect(KasusForms.matchingCapitalization("dem", like: "Der") == "Dem")
        #expect(KasusForms.matchingCapitalization("dem", like: "der") == "dem")
    }

    // MARK: Answer buttons

    @Test("A family's full option set, in table order", arguments: FamilyOptions.all)
    func fullFamilyOptions(_ set: FamilyOptions) {
        #expect(KasusForms.fullFamilyOptions(family: set.family, stem: set.stem, includeGenitive: set.genitive) == set.expected)
    }

    @Test("Viel Hilfe offers the noun's own gender, never fewer than three", arguments: VielHilfeCase.all)
    func vielHilfeOptions(_ example: VielHilfeCase) {
        let options = KasusForms.vielHilfeOptions(answer: example.answer, family: example.family, stem: example.stem,
                                                  genus: example.genus, includeGenitive: example.genitive)
        #expect(options == example.expected)
        #expect(options.count >= 3)
        #expect(options.contains(example.answer))
    }

    // MARK: Slips

    @Test("Right case, wrong gender", arguments: GenderSlipCase.all)
    func genderSlip(_ example: GenderSlipCase) {
        let slip = KasusForms.isRightCaseWrongGender(pick: example.pick, answerCase: example.kasus, genus: example.genus,
                                                     family: example.family, stem: example.stem)
        #expect(slip == example.isSlip)
    }

    @Test("Right case, wrong number")
    func numberSlip() {
        #expect(KasusForms.isRightCaseWrongNumber(pick: "die", answerCase: .akkusativ, genus: .der, family: .definite, stem: ""))
        #expect(KasusForms.isRightCaseWrongNumber(pick: "den", answerCase: .dativ, genus: .der, family: .definite, stem: ""))
        #expect(KasusForms.isRightCaseWrongNumber(pick: "seine", answerCase: .akkusativ, genus: .der, family: .possessive, stem: "sein"))
        #expect(!KasusForms.isRightCaseWrongNumber(pick: "seinen", answerCase: .akkusativ, genus: .der, family: .possessive, stem: "sein"),
                "the answer itself")
        #expect(!KasusForms.isRightCaseWrongNumber(pick: "die", answerCase: .akkusativ, genus: .die, family: .definite, stem: ""),
                "the feminine Akkusativ is the plural's form too, and it is the answer")
        #expect(!KasusForms.isRightCaseWrongNumber(pick: "eine", answerCase: .akkusativ, genus: .der, family: .ein, stem: "ein"),
                "ein has no plural")
    }

    @Test("The gender a slip picked")
    func genderOfSlip() {
        #expect(KasusForms.genderOfSlip(pick: "dem", kasus: .dativ, genus: .die, family: .definite, stem: "") == .der)
        #expect(KasusForms.genderOfSlip(pick: "das", kasus: .akkusativ, genus: .der, family: .definite, stem: "") == .das)
        #expect(KasusForms.genderOfSlip(pick: "den", kasus: .dativ, genus: .die, family: .definite, stem: "") == nil)
    }

    // MARK: Nouns

    @Test("Goethe plural markers spelled out")
    func expectedPlurals() {
        let examples: [(lemma: String, marker: String?, plural: String?)] = [
            ("Hund", "-e", "Hunde"), ("Haus", "\\u00a8-er", "Häuser"), ("Boden", "\\u00a8-", "Böden"),
            ("Mutter", "¨-", "Mütter"), ("Werkstatt", "\\u00a8-en", "Werkstätten"), ("Bus", "-se", "Busse"),
            ("Schlüssel", "-", "Schlüssel"), ("Leute", "only pl.", "Leute"), ("Konto", "Konten", "Konten"),
            ("Milch", "only sg.", nil), ("Baum", "\\u00a8-e", "Bäume"), ("Tasche", nil, nil),
        ]
        for example in examples {
            #expect(KasusForms.expectedPlural(lemma: example.lemma, marker: example.marker) == example.plural,
                    "\(example.lemma) \(example.marker ?? "no marker")")
        }
    }

    @Test("n-nouns and the Genitiv -s")
    func nounEndings() {
        let nEndings: [(lemma: String, kasus: GrammarCase, ending: String)] = [
            ("Junge", .akkusativ, "n"), ("Herr", .dativ, "n"), ("Nachbar", .akkusativ, "n"), ("Student", .genitiv, "en"),
            ("Name", .genitiv, "ns"), ("Name", .dativ, "n"), ("Gedanke", .genitiv, "ns"), ("Bauer", .akkusativ, "n"),
            ("Mensch", .dativ, "en"),
        ]
        for example in nEndings {
            #expect(KasusForms.nDeklinationEnding(lemma: example.lemma, kasus: example.kasus) == example.ending,
                    "\(example.lemma) \(example.kasus.short)")
        }
        let genitives: [(noun: String, lemma: String, valid: Bool)] = [
            ("Mannes", "Mann", true), ("Manns", "Mann", true), ("Sofas", "Sofa", true), ("Hauses", "Haus", true),
            ("Haus", "Haus", false), ("Busses", "Bus", true), ("Buss", "Bus", false), ("Herzens", "Herz", true),
            ("Mann", "Mann", false), ("Zeugnisses", "Zeugnis", true),
        ]
        for example in genitives {
            #expect(KasusForms.isGenitiveSingular(example.noun, of: example.lemma) == example.valid,
                    "des \(example.noun)")
        }
    }

    @Test("Which nouns read the same in the plural")
    func sameInPlural() {
        let examples: [(lemma: String, genus: Gender?, marker: String?, same: Bool)] = [
            ("Schlüssel", .der, "-", true), ("Termin", .der, "-e", false), ("Lehrer", .der, nil, true),
            ("Mädchen", .das, nil, true), ("Mutter", .die, "\\u00a8-", false), ("Zimmer", .das, nil, true),
            ("Tasche", .die, nil, false), ("Boden", .der, nil, false), ("Garten", .der, nil, false),
            ("Boden", .der, "\\u00a8-", false),
        ]
        for example in examples {
            #expect(KasusForms.mightBeSameInPlural(lemma: example.lemma, genus: example.genus,
                                                   goethePlural: example.marker) == example.same,
                    "\(example.lemma) \(example.marker ?? "no marker")")
        }
    }

    // MARK: Verbs, contractions, pronouns

    @Test("Dativ verb forms lead back to their infinitive")
    func dativeVerbs() {
        #expect(KasusForms.dativeVerbLemma(for: "gefällt") == "gefallen")
        #expect(KasusForms.dativeVerbLemma(for: "Hilft") == "helfen")
        #expect(KasusForms.dativeVerbLemma(for: "hört zu") == "zuhören")
        #expect(KasusForms.dativeVerbLemma(for: "hörten  zu") == "zuhören")
        #expect(KasusForms.dativeVerbLemma(for: "sieht") == nil)
    }

    @Test("Every contraction the prepositions file lists has the same parts in the engine")
    func contractionsMatchPrepositions() throws {
        let url = try #require(Bundle.main.url(forResource: "prepositions", withExtension: "json"))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let list = try #require(json?["prepositions"] as? [[String: Any]])
        var listed = 0
        for preposition in list {
            for contraction in preposition["contractions"] as? [[String: String]] ?? [] {
                guard let short = contraction["short"], let long = contraction["long"] else { continue }
                listed += 1
                let parts = long.split(separator: " ").map(String.init)
                let engine = KasusForms.contraction(short)
                #expect(engine?.preposition == parts.first && engine?.article == parts.last, "\(short) = \(long)")
            }
        }
        #expect(listed > 0)
        #expect(KasusForms.contraction("Im")?.article == "dem")
        #expect(KasusForms.contraction("zur")?.preposition == "zu")
        for (short, parts) in KasusForms.contractions {
            #expect(KasusForms.parseDeterminer(parts.article)?.family == .definite, "\(short)")
        }
    }

    @Test("Only the six pronouns whose form shows the case")
    func pronouns() {
        #expect(Set(KasusForms.caseVisiblePronouns.keys) == ["mich", "dich", "ihn", "mir", "dir", "ihm"])
        #expect(KasusForms.pronoun("Mir")?.kasus == .dativ)
        #expect(KasusForms.pronoun("ihn")?.kasus == .akkusativ)
        for word in ["uns", "euch", "ihr", "sie", "es"] {
            #expect(KasusForms.pronoun(word) == nil, "„\(word)“ reads the same in two cases")
        }
        for pronoun in KasusForms.caseVisiblePronouns.values {
            let other = KasusForms.pronoun(pronoun.otherCase)
            #expect(other?.otherCase == pronoun.word, "\(pronoun.word) ↔ \(pronoun.otherCase)")
            #expect(other?.kasus != pronoun.kasus)
        }
    }

    @Test("A pronoun target may leave out genus and lemma; a noun target may not")
    func targetSpecDecoding() throws {
        let minimal = #"{"phrase": "mir", "case": "dativ", "reason": "dativeVerb", "trigger": "hilft"}"#
        let decoded = try JSONDecoder().decode(KasusTargetSpec.self, from: Data(minimal.utf8))
        #expect(decoded.lemma == "ich")
        #expect(decoded.genus == .der)
        let noun = #"{"phrase": "dem Hund", "case": "dativ", "reason": "dativeVerb", "trigger": "hilft"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KasusTargetSpec.self, from: Data(noun.utf8))
        }
        let full = KasusTargetSpec(phrase: "den Ball", kasus: .akkusativ, genus: .der, lemma: "Ball",
                                   reason: .object, trigger: "wirft")
        let roundTripped = try JSONDecoder().decode(KasusTargetSpec.self, from: JSONEncoder().encode(full))
        #expect(roundTripped == full)
    }
}
