//
//  KasusHarvest.swift
//  german-ai-flashcards
//
//  Every article + noun phrase in a generated story that the app didn't plan (Phase 3). The tutor
//  writes more than the planned phrases, and Markieren must never call a correct phrase wrong, so
//  each one gets a verdict here:
//
//    proven        the article's form, narrowed by a preposition directly in front, leaves exactly
//                  one case for exactly one reading of the noun. It becomes a target with the
//                  `inferred` reason, whose explanation names only the form and the preposition.
//    wrong         no reading fits at all („das Tasche“, „des Mann“, „die hohen Anteil“), or the
//                  preposition takes a case the form can't be („mit den Hund“). It becomes a
//                  target labelled by its form, so the validator raises the code that rejects the
//                  whole story. An adjective in between doesn't hide it: the article still has to
//                  fit the noun.
//    unverifiable  anything else: several cases fit („die Katze“), the noun isn't one the app
//                  knows, an adjective in between (when the article does fit), a possible
//                  relative pronoun, a pronoun „ihr“, a verb used as a noun („beim Spielen“), a
//                  Genitiv plural that hangs on nothing, a Dativ next to sein. Left untargeted, so
//                  Markieren shows it as not counted and Endungen never blanks it.
//
//  A noun is read only through lemmas the app knows (the Goethe nouns, the plan's, the
//  learner's), never by looking the surface form up: Wiktionary files plural forms with the
//  singular's gender („Kinder“ → das), which would read „dem Kinder“ as fine.
//

import Foundation

// MARK: - Known nouns

/// The lemmas the harvest may read a noun through, and the plural forms that lead back to them.
@MainActor
struct KasusNounIndex {
    let lemmas: Set<String>
    /// Plural form → lemmas, from the Goethe plural markers („Kinder“ → Kind).
    let pluralToLemma: [String: [String]]

    /// The Goethe nouns (every headword with an article), plus `extra`: the plan's nouns and the
    /// learner's.
    init(extra: [String] = [], lexicon: any KasusLexicon) {
        var lemmas = Self.goetheLemmas
        lemmas.formUnion(extra.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        self.lemmas = lemmas
        var plurals: [String: [String]] = [:]
        for lemma in lemmas.sorted() {
            guard let plural = KasusForms.expectedPlural(lemma: lemma, marker: lexicon.goethePlural(forLemma: lemma)),
                  plural != lemma else { continue }
            plurals[plural, default: []].append(lemma)
        }
        pluralToLemma = plurals
    }

    private static var goetheCache: Set<String>?

    /// Every Goethe headword that has an article: the nouns.
    static var goetheLemmas: Set<String> {
        if let goetheCache { return goetheCache }
        let lemmas = Set(GoetheVocabService.index.values.compactMap { word -> String? in
            guard let article = word.article?.trimmingCharacters(in: .whitespaces), !article.isEmpty,
                  word.word.first?.isUppercase == true, !word.word.contains(" ") else { return nil }
            return word.word
        })
        goetheCache = lemmas
        return lemmas
    }
}

// MARK: - Readings

/// One way to read a noun after an article: a lemma, a gender (or the plural), and the cases the
/// article allows with it once the noun's own ending is checked (the Genitiv -s, the Dativ
/// plural -n).
nonisolated struct KasusNounReading: Hashable {
    let lemma: String
    /// `.plural` for a plural reading.
    let genus: Gender
    /// The cases left after the noun's ending is checked.
    let cases: Set<GrammarCase>
    /// The cases the article's form allows with this gender, ending unchecked.
    let formCases: Set<GrammarCase>
    /// The noun is written exactly as the lemma (a singular or an unchanged plural).
    let isBareLemma: Bool
}

/// Why an unplanned phrase isn't graded. Stable raw values: the Lab counts them.
nonisolated enum KasusUnverifiable: String, Codable, CaseIterable, Hashable {
    /// Several cases fit, and no preposition in front narrows them („die Katze“).
    case ambiguousCase
    /// One case, but the noun reads two ways (two genders, or singular and plural).
    case ambiguousNoun
    /// No lemma the app knows explains the noun (a name, a compound, a word off the lists).
    case unknownNoun
    /// The sources disagree on the noun's gender, or know nothing.
    case gender
    /// An n-noun or a noun made from an adjective: its endings aren't checked here.
    case nNoun
    /// An adjective between article and noun; targets are article + noun only for now.
    case adjective
    /// A der/die/das right after a comma (or a comma and a preposition): maybe a relative pronoun.
    case relative
    /// kein, a possessive or dieser that no reading fits, or a bare „ihr“, which is as often a
    /// pronoun („Habt ihr Hunger?“, „Er gibt ihr Kaffee.“) as the possessive.
    case notAnArticle
    /// „ein Uhr“: a time, not an article.
    case time
    /// A target that an identical, untargeted phrase earlier in the text would shadow: the
    /// validator finds targets by walking forward, so it could land on the wrong one.
    case shadowed
    /// A „wrong“ phrase the validator didn't confirm as wrong German, so it's left alone.
    case unconfirmed
    /// A verb used as a noun („beim Spielen“, „das Arbeiten“): not the Dativ plural it looks like.
    case nominalised
    /// Only a Genitiv plural reading fits, but nothing it could hang on: no noun in front and no
    /// Genitiv preposition. More likely a wrong gender („Der Zimmer ist groß“).
    case genitiveRole
    /// A Dativ with no preposition where sein is the verb: right in „Das ist dem Kind egal“,
    /// wrong in „Ich war dem Haus zu Hause“, and the form can't tell them apart.
    case copula
}

/// An article + noun phrase the harvest looked at.
nonisolated struct KasusHarvestedPhrase: Hashable {
    nonisolated enum Verdict: Hashable {
        case proven
        case wrong
        case unverifiable(KasusUnverifiable)
    }

    let paragraphIndex: Int
    /// UTF-16 range in the paragraph, determiner to noun (adjectives included).
    let range: NSRange
    /// As written: „dem Hund“, „im Garten“, „den großen Hund“.
    let surface: String
    let determiner: String
    let noun: String
    /// The preposition that decides, lowercased: the one directly in front, or a contraction's own.
    let preposition: String?
    /// Set for proven and wrong phrases.
    let kasus: GrammarCase?
    let genus: Gender?
    let lemma: String?
    var verdict: Verdict

    var isProven: Bool { verdict == .proven }
    var isWrong: Bool { verdict == .wrong }
    var unverifiable: KasusUnverifiable? {
        if case .unverifiable(let why) = verdict { return why }
        return nil
    }

    /// The target it becomes: proven and wrong phrases only.
    var spec: KasusTargetSpec? {
        guard verdict == .proven || verdict == .wrong, let kasus, let genus, let lemma else { return nil }
        return KasusTargetSpec(phrase: surface, kasus: kasus, genus: genus, lemma: lemma,
                               reason: .inferred, trigger: preposition ?? "")
    }
}

// MARK: - The harvest

@MainActor
enum KasusHarvest {

    /// Every article + noun phrase in `paragraphs`, in reading order, except those starting inside
    /// `excluding` (the planned targets' ranges, per paragraph).
    static func harvest(paragraphs: [String], excluding: [Int: [NSRange]] = [:],
                        nouns: KasusNounIndex, lexicon: any KasusLexicon) -> [KasusHarvestedPhrase] {
        var found: [KasusHarvestedPhrase] = []
        for (p, text) in paragraphs.enumerated() {
            let paragraph = KasusScannedParagraph(text)
            let tokens = paragraph.tokens
            let skip = excluding[p] ?? []
            for (i, token) in tokens.enumerated() {
                let lower = token.text.lowercased()
                let contraction = KasusForms.contraction(lower)
                let determiner = contraction == nil ? KasusForms.parseDeterminer(lower) : nil
                guard contraction != nil || determiner != nil else { continue }
                // sein/seid … are verbs when no noun follows; nounAfterDeterminer checks that.
                guard let nounIndex = KasusValidator.nounAfterDeterminer(at: i, in: paragraph) else { continue }
                let start = NSRange(token.range, in: text).location
                if skip.contains(where: { NSLocationInRange(start, $0) }) { continue }
                let range = token.range.lowerBound..<tokens[nounIndex].range.upperBound
                let nounToken = tokens[nounIndex]

                // The preposition in front: a contraction's own, else the word directly before
                // (bis, um, ohne … are skipped: they also open clauses and zu-infinitives).
                var preposition: String?
                var prepositionCases: Set<GrammarCase>?
                if let contraction {
                    preposition = contraction.preposition
                    prepositionCases = lexicon.prepositionCases(contraction.preposition)
                } else if i > 0, paragraph.isWhitespaceGap(tokens[i - 1], token) {
                    let before = tokens[i - 1].text.lowercased()
                    if before == "entlang" {
                        preposition = before
                        prepositionCases = KasusForms.entlangCases(after: false)
                    } else if !KasusForms.softPrepositions.contains(before), let cases = lexicon.prepositionCases(before) {
                        preposition = before
                        prepositionCases = cases
                    }
                }

                let article = contraction?.article ?? lower
                let family = determiner?.family
                let adjective = nounIndex != i + 1
                let relative = family == .definite && mayBeRelative(at: i, in: paragraph, lexicon: lexicon)
                let mayReject = (contraction != nil || family == .definite || family == .ein) && !relative

                var verdict: KasusHarvestedPhrase.Verdict
                var chosen: (kasus: GrammarCase, reading: KasusNounReading)?
                if relative {
                    verdict = .unverifiable(.relative)
                } else if lower == "ein", nounToken.text == "Uhr" {
                    verdict = .unverifiable(.time)
                } else if determiner?.family == .possessive, determiner?.stem == "ihr", determiner?.ending.isEmpty == true {
                    verdict = .unverifiable(.notAnArticle)
                } else {
                    let (readings, blocked) = self.readings(noun: nounToken.text, article: article,
                                                            nouns: nouns, lexicon: lexicon)
                    if blocked == nil, isNominalised(noun: nounToken.text, article: article, readings: readings, lexicon: lexicon) {
                        verdict = .unverifiable(.nominalised)
                    } else {
                        (verdict, chosen) = decide(readings: readings, blocked: blocked,
                                                   prepositionCases: prepositionCases, mayReject: mayReject)
                    }
                    // With an adjective in between, only a wrong article counts: the adjective's
                    // own ending isn't checked, so a phrase that fits stays ungraded.
                    if adjective, verdict != .wrong {
                        verdict = .unverifiable(.adjective)
                        chosen = nil
                    }
                    if verdict == .proven, let pick = chosen, preposition == nil {
                        if pick.kasus == .genitiv, pick.reading.genus == .plural,
                           !followsNoun(at: i, in: paragraph) {
                            verdict = .unverifiable(.genitiveRole)
                            chosen = nil
                        } else if pick.kasus == .dativ, dativeNextToCopula(range, in: paragraph) {
                            verdict = .unverifiable(.copula)
                            chosen = nil
                        }
                    }
                }
                found.append(KasusHarvestedPhrase(
                    paragraphIndex: p,
                    range: NSRange(range, in: text),
                    surface: String(text[range]),
                    determiner: token.text,
                    noun: nounToken.text,
                    preposition: preposition,
                    kasus: chosen?.kasus,
                    genus: chosen?.reading.genus,
                    lemma: chosen?.reading.lemma,
                    verdict: verdict
                ))
            }
        }
        return found
    }

    /// A verb used as a noun: a singular, neuter article (or a contraction: beim, zum, vom) in
    /// front of an -en/-ern/-eln word that isn't itself a singular noun the app knows, whose
    /// lowercase form the dictionary knows as a verb. „beim Spielen“ would otherwise read as a
    /// Dativ plural of Spiel and reject a correct story; „dem Kindern“ stays wrong, since
    /// „kindern“ is no verb.
    static func isNominalised(noun: String, article: String, readings: [KasusNounReading],
                              lexicon: any KasusLexicon) -> Bool {
        guard ["dem", "das", "des", "einem", "ein", "eines"].contains(article),
              noun.hasSuffix("en") || noun.hasSuffix("ern") || noun.hasSuffix("eln"),
              !readings.contains(where: { $0.isBareLemma && $0.genus != .plural }),
              let pos = lexicon.partsOfSpeech(noun.lowercased()) else { return false }
        return pos.contains("verb")
    }

    /// A capitalised word stands right in front, and it isn't the first word of the sentence:
    /// the phrase can hang on it („die Mutter der Kinder“).
    static func followsNoun(at index: Int, in paragraph: KasusScannedParagraph) -> Bool {
        guard index > 0 else { return false }
        let before = paragraph.tokens[index - 1]
        guard paragraph.isWhitespaceGap(before, paragraph.tokens[index]),
              before.text.first?.isUppercase == true else { return false }
        return paragraph.sentence(containing: before.range.lowerBound).lowerBound != before.range.lowerBound
    }

    /// sein, werden, bleiben or heißen is the verb of the phrase's part of its clause.
    static func dativeNextToCopula(_ range: Range<String.Index>, in paragraph: KasusScannedParagraph) -> Bool {
        let sentence = paragraph.sentence(containing: range.lowerBound)
        let clause = paragraph.clause(containing: range, in: sentence)
        return KasusValidator.mainCopula(in: paragraph.coordinatedPart(of: range, in: clause), of: paragraph) != nil
    }

    /// A der/die/das … right after a comma, or after a comma and a preposition („, mit dem …“),
    /// may be a relative pronoun: „Der Mann, der Kaffee trinkt“ must not read as „der Kaffee“.
    static func mayBeRelative(at index: Int, in paragraph: KasusScannedParagraph, lexicon: any KasusLexicon) -> Bool {
        func gapBefore(_ i: Int) -> Substring {
            let text = paragraph.text
            let start = i > 0 ? paragraph.tokens[i - 1].range.upperBound : text.startIndex
            return text[start..<paragraph.tokens[i].range.lowerBound]
        }
        if gapBefore(index).contains(",") { return true }
        guard index > 0, paragraph.isWhitespaceGap(paragraph.tokens[index - 1], paragraph.tokens[index]) else { return false }
        let before = paragraph.tokens[index - 1].text.lowercased()
        let isPreposition = KasusForms.softPrepositions.contains(before) || before == "entlang"
            || lexicon.prepositionCases(before) != nil
        return isPreposition && gapBefore(index - 1).contains(",")
    }

    /// The readings a noun has after `article` (lowercased; a contraction's article), through the
    /// lemmas the index knows. `blocked` says why nothing may be read at all.
    static func readings(noun: String, article: String, nouns: KasusNounIndex,
                         lexicon: any KasusLexicon) -> (readings: [KasusNounReading], blocked: KasusUnverifiable?) {
        var candidates: [String] = [noun]
        for suffix in ["es", "s"] where noun.count > suffix.count + 1 && noun.hasSuffix(suffix) {
            candidates.append(String(noun.dropLast(suffix.count)))
        }
        if noun.count > 2, noun.hasSuffix("n") {
            let shorter = String(noun.dropLast())
            candidates.append(shorter)
            candidates += nouns.pluralToLemma[shorter] ?? []
        }
        candidates += nouns.pluralToLemma[noun] ?? []
        var seen = Set<String>()
        let known = candidates.filter { nouns.lemmas.contains($0) && seen.insert($0).inserted }
        guard !known.isEmpty else { return ([], .unknownNoun) }

        var readings: [KasusNounReading] = []
        var anyGender = false
        for lemma in known {
            if KasusForms.isNDeklination(lemma) || KasusForms.isAdjectivalNoun(lemma) { return ([], .nNoun) }
            let genus: Gender
            if KasusForms.isPluraleTantum(lemma) {
                genus = .plural
            } else if case .verified(let verified) = lexicon.gender(forLemma: lemma) {
                genus = verified
            } else {
                continue
            }
            anyGender = true
            func compatible(_ g: Gender) -> Set<GrammarCase> { KasusForms.compatibleCases(determiner: article, genus: g) }
            let endsNS = { (word: String) in word.hasSuffix("n") || word.hasSuffix("s") }

            if genus == .plural {
                let form = compatible(.plural)
                if noun == lemma {
                    readings.append(.init(lemma: lemma, genus: .plural,
                                          cases: endsNS(lemma) ? form : form.subtracting([.dativ]),
                                          formCases: form, isBareLemma: true))
                } else if noun == lemma + "n", !endsNS(lemma) {
                    readings.append(.init(lemma: lemma, genus: .plural, cases: form.intersection([.dativ]),
                                          formCases: form, isBareLemma: false))
                }
                continue
            }
            // Singular, the noun as the lemma: no Genitiv for a masculine or neuter noun, which
            // needs its -(e)s.
            if noun == lemma {
                let form = compatible(genus)
                let cases = genus == .der || genus == .das ? form.subtracting([.genitiv]) : form
                readings.append(.init(lemma: lemma, genus: genus, cases: cases, formCases: form, isBareLemma: true))
            }
            // Genitiv singular: des Hundes, des Wetters.
            if noun != lemma, genus == .der || genus == .das, KasusForms.isGenitiveSingular(noun, of: lemma) {
                let form = compatible(genus)
                readings.append(.init(lemma: lemma, genus: genus, cases: form.intersection([.genitiv]),
                                      formCases: form, isBareLemma: false))
            }
            // Plural: the Goethe marker's plural, or the lemma itself for a noun that doesn't change.
            let marker = lexicon.goethePlural(forLemma: lemma)
            let plural = KasusForms.expectedPlural(lemma: lemma, marker: marker)
                ?? (KasusForms.mightBeSameInPlural(lemma: lemma, genus: genus, goethePlural: marker) ? lemma : nil)
            if let plural {
                let form = compatible(.plural)
                if noun == plural {
                    readings.append(.init(lemma: lemma, genus: .plural,
                                          cases: endsNS(plural) ? form : form.subtracting([.dativ]),
                                          formCases: form, isBareLemma: plural == lemma))
                } else if noun == plural + "n", !endsNS(plural) {
                    readings.append(.init(lemma: lemma, genus: .plural, cases: form.intersection([.dativ]),
                                          formCases: form, isBareLemma: false))
                }
            }
        }
        if readings.isEmpty { return ([], anyGender ? .unknownNoun : .gender) }
        return (readings, nil)
    }

    /// The verdict from the readings and the preposition in front.
    static func decide(readings: [KasusNounReading], blocked: KasusUnverifiable?,
                       prepositionCases: Set<GrammarCase>?, mayReject: Bool)
    -> (KasusHarvestedPhrase.Verdict, (kasus: GrammarCase, reading: KasusNounReading)?) {
        if let blocked { return (.unverifiable(blocked), nil) }
        guard !readings.isEmpty else { return (.unverifiable(.unknownNoun), nil) }
        func first(_ cases: Set<GrammarCase>) -> GrammarCase? { GrammarCase.allCases.first(where: cases.contains) }
        /// The reading a wrong phrase is labelled by: the bare singular if there is one.
        func wrongPick(_ pool: [KasusNounReading]) -> KasusNounReading {
            pool.first { $0.isBareLemma && $0.genus != .plural } ?? pool[0]
        }

        var live = readings.filter { !$0.cases.isEmpty }
        guard !live.isEmpty else {
            // No reading fits: an impossible article („das Tasche“), or a missing ending („des
            // Mann“, „den Hunde“). Labelled by the form, so the validator names it.
            guard mayReject else { return (.unverifiable(.notAnArticle), nil) }
            let reading = wrongPick(readings)
            return (.wrong, (first(reading.formCases) ?? .nominativ, reading))
        }
        if let prepositionCases {
            let narrowed = live.compactMap { reading -> KasusNounReading? in
                let cases = reading.cases.intersection(prepositionCases)
                guard !cases.isEmpty else { return nil }
                return KasusNounReading(lemma: reading.lemma, genus: reading.genus, cases: cases,
                                        formCases: reading.formCases, isBareLemma: reading.isBareLemma)
            }
            guard !narrowed.isEmpty else {
                // „mit den Hund“: the preposition takes a case the form can't be.
                guard mayReject else { return (.unverifiable(.notAnArticle), nil) }
                let reading = wrongPick(live)
                return (.wrong, (first(reading.cases) ?? .nominativ, reading))
            }
            live = narrowed
        }
        let cases = live.reduce(into: Set<GrammarCase>()) { $0.formUnion($1.cases) }
        let identities = Set(live.map { "\($0.lemma)|\($0.genus.columnLabel)" })
        guard cases.count == 1, let kasus = cases.first else { return (.unverifiable(.ambiguousCase), nil) }
        guard identities.count == 1 else { return (.unverifiable(.ambiguousNoun), nil) }
        return (.proven, (kasus, live[0]))
    }
}
