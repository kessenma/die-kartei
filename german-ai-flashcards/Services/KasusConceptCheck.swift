//
//  KasusConceptCheck.swift
//  german-ai-flashcards
//
//  The gate for one tutor-written Verstehen item. It never trusts the tutor with a case:
//
//    1. parse    the `SATZ:` line (or, failing that, the first line; recorded as formatMissing)
//    2. contract exactly one sentence; every planned phrase verbatim; the verb there in a planned
//                form; a Wer plan opening with the phrase it asked for; no planned phrase without
//                a preposition sitting right behind one („in den Spiegel“ isn't sehen's object) or
//                behind a noun (where it would read as a Genitiv attribute)
//    3. frame    one simple clause (no comma, no conjunction); no article phrase beyond the planned
//                ones unless a preposition governs it („für ihre Hilfe“, „im Park“: allowed, never
//                asked; a bare one would be another subject or object); at most one planned phrase
//                whose article fits several cases
//    4. audit    the item built from the plan's roles, through `KasusConceptBank.audit`, plus the
//                generated-story rejects (wrong forms, a preposition or Wo/Wohin verb wanting the
//                other case, the `sentence.*` checks: broken German)
//
//  Why a phrase only its label decides may be graded here, when a tutor-written story never grades
//  one: the label is the app's plan, not the tutor's, and the frame fixes who is who. In one simple
//  clause with one verb, a subject the form proves and one more phrase, that phrase *is* the verb's
//  partner („Der Vater fragt die Schwester“); with two ambiguous phrases („Die Tochter sucht die
//  Zeitung“ / „Die Zeitung sucht die Tochter“) only word order would say, so the item is refused
//  (`concept.ambiguousRoles`). The facts invariants hold too: a Wer clue proven by form, a Probe
//  phrase really ambiguous.
//
//  It passes only with no contract code, no validator error and no facts problem.
//

import Foundation

/// Why a tutor's sentence was turned away, apart from the validator's own codes. Stable keys.
nonisolated enum KasusConceptCheckCode: String, CaseIterable, Codable, Hashable {
    /// No `SATZ:` line; the first line was read instead. Recorded, not rejecting.
    case formatMissing = "concept.formatMissing"
    /// Nothing that could be a sentence came back.
    case empty = "concept.empty"
    case notOneSentence = "concept.notOneSentence"
    /// A planned phrase isn't in the sentence word for word (a changed article or ending, a
    /// possessive in place of the article, a dropped preposition).
    case phraseAltered = "concept.phraseAltered"
    case verbMissing = "concept.verbMissing"
    /// A Wer plan's sentence doesn't open with the phrase it asked for.
    case orderIgnored = "concept.orderIgnored"
    /// A planned phrase follows a noun, where it may be a Genitiv attribute („die Mutter der Frau“).
    case roleUnsure = "concept.roleUnsure"
    /// A planned phrase without a preposition sits right behind one: it is no longer the verb's
    /// partner („sieht in den Spiegel“ for the object „den Spiegel“).
    case roleChanged = "concept.roleChanged"
    /// A comma, colon, semicolon or conjunction: more than one clause (or a label left on), so the
    /// frame no longer fixes the roles.
    case notSimple = "concept.notSimple"
    /// An article phrase the plan didn't have and no preposition governs: another subject or object.
    case extraPhrase = "concept.extraPhrase"
    /// A personal pronoun the plan didn't have („ruft dich an“): another person in the sentence.
    case extraPerson = "concept.extraPerson"
    /// An added phrase behind a preposition whose case the form and preposition don't prove
    /// („im Park“ after a verb that could be Wo or Wohin): the item couldn't vouch for it.
    case extraUnproven = "concept.extraUnproven"
    /// Two planned phrases whose article fits several cases: only word order would tell them apart.
    case ambiguousRoles = "concept.ambiguousRoles"

    var rejects: Bool { self != .formatMissing }
}

struct KasusConceptCheckResult {
    let plan: KasusConceptPlan
    let raw: String
    /// The sentence read from the output, or nil.
    let sentence: String?
    let codes: [KasusConceptCheckCode]
    /// The planned phrases found verbatim.
    let placed: Int
    /// Phrases the tutor added behind a preposition (allowed, never asked).
    var extras: [String] = []
    /// Planned phrase index → its target index in the item.
    var targetOf: [Int: Int] = [:]
    let item: KasusConceptItem?
    let audit: KasusConceptAudit?
    /// The generated-story rejects (wrong forms, broken sentences) from a second validation.
    var generatedErrors: [String] = []

    /// Validator errors (the story-level codes left out: one sentence is always "too short").
    var errorCodes: [String] {
        let authored = audit?.report.errors.filter { !$0.code.isStoryLevel }.map(\.code.rawValue) ?? []
        return authored + generatedErrors.filter { !authored.contains($0) }
    }

    var warningCodes: [String] {
        audit?.report.warnings.filter { !$0.code.isStoryLevel }.map(\.code.rawValue) ?? []
    }

    var factsProblems: [String] { audit?.facts.problems ?? [] }

    var passes: Bool {
        item != nil && !codes.contains(where: \.rejects) && errorCodes.isEmpty && factsProblems.isEmpty
    }

    /// The first reason it failed, for a table: a contract code, a validator code or "facts".
    var firstReject: String? {
        if let code = codes.first(where: \.rejects) { return code.rawValue }
        if let code = errorCodes.first { return code }
        if !factsProblems.isEmpty { return "concept.facts" }
        return nil
    }
}

@MainActor
enum KasusConceptCheck {

    private struct Entry {
        let location: Int
        let spec: KasusTargetSpec
        let planned: Int?
    }

    static func run(raw: String, plan: KasusConceptPlan, lexicon: some KasusLexicon = AppKasusLexicon()) -> KasusConceptCheckResult {
        var codes: [KasusConceptCheckCode] = []
        func fail(_ sentence: String?, placed: Int = 0) -> KasusConceptCheckResult {
            KasusConceptCheckResult(plan: plan, raw: raw, sentence: sentence, codes: codes, placed: placed, item: nil, audit: nil)
        }

        // 1. The sentence.
        guard let (sentence, labelled) = extract(raw) else {
            codes.append(.empty)
            return fail(nil)
        }
        if !labelled { codes.append(.formatMissing) }
        if KasusScanner.sentences(in: sentence).count != 1 { codes.append(.notOneSentence) }

        // 2. The planned phrases, verbatim, in the sentence.
        var located: [(index: Int, range: NSRange)] = []
        for (index, phrase) in plan.phrases.enumerated() {
            // A Genitiv attribute only counts right behind its head: „den Hund des Lehrers“.
            if let head = phrase.head, plan.phrases.indices.contains(head) {
                if let range = find(plan.fullExpression(head), in: sentence) {
                    let inner = (sentence as NSString).range(of: phrase.phrase, options: [.caseInsensitive, .backwards], range: range)
                    if inner.location != NSNotFound { located.append((index, inner)) }
                }
                continue
            }
            if let range = find(phrase.expression, in: sentence) {
                let inner = (sentence as NSString).range(of: phrase.phrase, options: [.caseInsensitive], range: range)
                located.append((index, inner.location == NSNotFound ? range : inner))
            }
        }
        if located.count < plan.phrases.count { codes.append(.phraseAltered) }
        let foundVerb = plan.verbForms.first { find($0, in: sentence) != nil }
        if foundVerb == nil { codes.append(.verbMissing) }
        if let first = plan.firstPhrase, plan.phrases.indices.contains(first) {
            let opener = plan.fullExpression(first)
            let trimmed = sentence.trimmingCharacters(in: CharacterSet(charactersIn: "„“\"' "))
            if trimmed.range(of: opener, options: [.caseInsensitive, .anchored]) == nil { codes.append(.orderIgnored) }
        }
        for hit in located where plan.phrases[hit.index].preposition == nil && !plan.phrases[hit.index].isAttribute {
            // Only a form a Genitiv could have reads as an attribute: „dem Kind einen Ball“ doesn't.
            let article = plan.phrases[hit.index].phrase.split(separator: " ").first.map { $0.lowercased() } ?? ""
            if ["der", "des", "einer", "eines"].contains(article), followsNoun(hit.range, in: sentence),
               !codes.contains(.roleUnsure) {
                codes.append(.roleUnsure)
            }
            if let before = wordBefore(hit.range, in: sentence), lexicon.prepositionCases(before) != nil,
               !codes.contains(.roleChanged) {
                codes.append(.roleChanged)
            }
        }
        guard located.count == plan.phrases.count, let foundVerb else { return fail(sentence, placed: located.count) }

        // 3. The frame.
        let words = KasusScanner.words(in: sentence).map { $0.text.lowercased() }
        // A colon or semicolon is a label left on („Erklärung: …“) or a second clause.
        if sentence.contains(where: { ",;:".contains($0) }) || words.contains(where: conjunctions.contains) {
            codes.append(.notSimple)
        }
        if words.contains(where: personalPronouns.contains) { codes.append(.extraPerson) }
        let nouns = KasusNounIndex(extra: plan.phrases.map(\.lemma), lexicon: lexicon)
        let extras = KasusHarvest.harvest(paragraphs: [sentence], excluding: [0: located.map(\.range)],
                                          nouns: nouns, lexicon: lexicon)
        if extras.contains(where: { $0.preposition == nil }) { codes.append(.extraPhrase) }
        if extras.contains(where: { $0.preposition != nil && $0.spec == nil }) { codes.append(.extraUnproven) }

        // 4. Targets in reading order: the planned phrases, and the added ones a preposition
        //    proves (validated like the rest, never asked). Then the item and the audit.
        var entries: [Entry] = located.map { hit in
            let p = plan.phrases[hit.index]
            let surface = (sentence as NSString).substring(with: hit.range)
            let trigger = p.head.map { plan.phrases[$0].phrase.split(separator: " ").last.map(String.init) ?? "" }
                ?? p.preposition ?? foundVerb
            let spec = KasusTargetSpec(phrase: surface, kasus: p.kasus, genus: p.genus, lemma: p.lemma,
                                       reason: p.reason, trigger: trigger)
            return Entry(location: hit.range.location, spec: spec, planned: hit.index)
        }
        for extra in extras where extra.preposition != nil {
            if let spec = extra.spec { entries.append(Entry(location: extra.range.location, spec: spec, planned: nil)) }
        }
        entries.sort { $0.location < $1.location }
        let targetOf: [Int: Int] = Dictionary(uniqueKeysWithValues: entries.enumerated().compactMap { i, e in
            e.planned.map { ($0, i) }
        })

        let id = "kg-concept-\(plan.id)"
        func story(_ source: KasusStorySource) -> KasusStory {
            KasusStory(id: id, unitRaw: plan.unitRaw, level: plan.level, source: source,
                       reviewed: .init(by: "", date: ""), title: id, titleEnglish: "",
                       question: .init(de: "", en: "", options: [], answer: 0),
                       paragraphs: [.init(de: sentence, en: "")], targets: entries.map(\.spec), notTargets: [])
        }
        let detail: KasusConceptItem.Detail
        switch plan.kind {
        case .whoDoesWhat:
            let subject = plan.phrases.firstIndex { $0.reason == .subject } ?? 0
            let partner = plan.phrases.indices.first { $0 != subject && !plan.phrases[$0].isAttribute } ?? 1
            let options = [targetOf[subject] ?? 0, targetOf[partner] ?? 1].sorted()
            let verb = foundVerb.split(separator: " ").first.map(String.init) ?? plan.verbShown
            detail = .whoDoesWhat(question: .init(de: "Wer \(verb)?", en: ""), options: options,
                                  answer: targetOf[subject] ?? 0)
        case .probe:
            detail = .probe(target: targetOf[plan.probePhrase ?? 0] ?? 0, noun: .mann)
        case .roles, .sameMeaning:
            let asked = plan.phrases.indices.compactMap { targetOf[$0] }.sorted()
            detail = .roles(ask: asked.count == entries.count ? nil : asked)
        }
        // Audited with the plan as the label (the authored policy), and once more under the
        // generated policy for what a tutor's German can get wrong: those codes reject.
        let item = KasusConceptItem(id: id, kind: plan.kind, story: story(.authored), detail: detail)
        let audit = KasusConceptBank.audit(item, lexicon: lexicon)
        let generated = KasusValidator.validate(story(.generated), source: .generated, lexicon: lexicon)
        let broken = generated.errors.filter { KasusValidator.Policy.rejectsGeneratedStory($0.code) && !$0.code.isStoryLevel }
        // An attribute's place behind its noun settles it; only the others can be confused.
        if audit.report.located.filter({ $0.proof == .label && $0.spec.reason != .attribute }).count > 1 {
            codes.append(.ambiguousRoles)
        }
        return KasusConceptCheckResult(plan: plan, raw: raw, sentence: sentence, codes: codes,
                                       placed: located.count, extras: extras.map(\.surface), targetOf: targetOf,
                                       item: item, audit: audit,
                                       generatedErrors: broken.map(\.code.rawValue))
    }

    /// Personal pronouns that are someone the plan doesn't have (er/sie/es/ihr are left out: an
    /// „ihr“ is mostly a possessive here, and a pronoun standing for a planned phrase would leave
    /// that phrase missing, which `phraseAltered` already turns away).
    static let personalPronouns: Set<String> = ["ich", "du", "wir", "mich", "dich", "ihn", "uns", "euch",
                                                "mir", "dir", "ihm", "ihnen"]

    /// Words that join clauses: with one of them the sentence is more than the planned frame.
    static let conjunctions: Set<String> = ["und", "oder", "aber", "denn", "dass", "weil", "wenn", "ob", "als",
                                            "obwohl", "damit", "nachdem", "bevor", "sondern", "sodass", "wo", "wie"]

    // MARK: Parsing

    /// The sentence after `SATZ:` (true), or the first non-empty line (false). Markdown, list
    /// marks and quotes around it come off.
    static func extract(_ raw: String) -> (String, Bool)? {
        let lines = raw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        func clean(_ text: String) -> String {
            var t = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "-•> \t"))
            if let first = t.first, "„\"“'".contains(first), let last = t.last, "“\"”'".contains(last), t.count > 2 {
                t = String(t.dropFirst().dropLast())
            }
            return t.trimmingCharacters(in: .whitespaces)
        }
        for line in lines {
            let stripped = line.replacingOccurrences(of: "**", with: "")
            if let range = stripped.range(of: "SATZ:", options: [.caseInsensitive]),
               stripped[..<range.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
                let text = clean(String(stripped[range.upperBound...]))
                return text.isEmpty ? nil : (text, true)
            }
        }
        guard let first = lines.first(where: { !$0.isEmpty }) else { return nil }
        let text = clean(first)
        return text.isEmpty ? nil : (text, false)
    }

    /// A phrase as whole words, any capitalisation of its first letter.
    static func find(_ phrase: String, in sentence: String) -> NSRange? {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}])\(escaped)(?![\\p{L}])", options: [.caseInsensitive]) else { return nil }
        let ns = sentence as NSString
        return regex.firstMatch(in: sentence, range: NSRange(location: 0, length: ns.length))?.range
    }

    /// The word right before `range`, lowercased.
    static func wordBefore(_ range: NSRange, in sentence: String) -> String? {
        let before = (sentence as NSString).substring(to: range.location)
        return KasusScanner.words(in: before).last.map { $0.text.lowercased() }
    }

    /// The word right before `range` is capitalised and isn't the sentence's first word: a noun
    /// the phrase could hang on („Die Mutter der Frau“).
    static func followsNoun(_ range: NSRange, in sentence: String) -> Bool {
        let before = (sentence as NSString).substring(to: range.location).trimmingCharacters(in: .whitespaces)
        let words = before.split(separator: " ")
        guard words.count >= 2, let last = words.last, let first = last.first else { return false }
        let bare = last.trimmingCharacters(in: .punctuationCharacters)
        return first.isUppercase && bare == String(last) && KasusForms.parseDeterminer(bare) == nil
    }
}
