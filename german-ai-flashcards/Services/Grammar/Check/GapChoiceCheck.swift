//
//  GapChoiceCheck.swift
//  german-ai-flashcards
//
//  The gate for one gap-choice item, and for a whole pack. It never trusts the writer (a planner,
//  a person, one day a model) with a case: every fact on the item is checked against the tables
//  in ReflexivForms.swift, the forms engine and the lexicon, and the case the answer shows must
//  follow from the verb and the second object by the rule the lesson teaches.
//
//    shape      placeholders match the gaps; ≥ 2 distinct options with the answer among them;
//               an inline item has exactly two; a known topic and level; an `rx-` id
//    subject    a table subject, standing at the start of the sentence
//    verb       in the table; its form the table's for the subject; in the sentence; a
//               separable prefix last
//    answer     the table's pronoun for the subject's person and the gap's case
//    case rule  akk ⇒ no second object; dat ⇒ one; both ⇒ Dativ exactly when one follows
//    object     written after the gap; its determiner fits the Akkusativ for the lemma's gender
//               and number; the lexicon agrees on the gender
//    frame      one simple clause; no article phrase beyond the object and the tail; no other
//               pronoun that shows a case
//    words      every word known to the lexicon (a warning, not a reject)
//
//  A pack is also checked as a whole (`composition`): unique ids and sentences, both cases
//  present in an Akkusativ-oder-Dativ pack, and in a batch-sized pack every verb and person
//  represented (the valid-data-wrong-shape lesson). Compiled into training/kasus_cli.
//

import Foundation

/// Why an item was turned away. Stable keys, like the validator's.
nonisolated enum GapChoiceCheckCode: String, CaseIterable, Hashable {
    case shape = "gap.shape"
    case options = "gap.options"
    case id = "gap.id"
    case topic = "gap.topic"
    case level = "gap.level"
    case subject = "gap.subject"
    case verbUnknown = "gap.verbUnknown"
    case verbForm = "gap.verbForm"
    case prefix = "gap.prefix"
    case answer = "gap.answer"
    case caseRule = "gap.caseRule"
    case object = "gap.object"
    case objectCase = "gap.objectCase"
    case objectGender = "gap.objectGender"
    case extraPhrase = "gap.extraPhrase"
    case extraPronoun = "gap.extraPronoun"
    case notSimple = "gap.notSimple"
    case english = "gap.english"
    /// A word the lexicon doesn't know. Recorded, not rejecting: a name or a plural form the
    /// dictionary lacks shouldn't stop a sentence a person has read.
    case unknownWord = "gap.unknownWord"
    /// The lexicon has no verdict on the object's gender. Recorded, not rejecting.
    case objectUnverified = "gap.objectUnverified"

    var rejects: Bool { self != .unknownWord && self != .objectUnverified }
}

/// What a whole pack can get wrong.
nonisolated enum GapCompositionCode: String, CaseIterable, Hashable {
    case duplicateID = "gap.composition.duplicateID"
    case duplicateSentence = "gap.composition.duplicateSentence"
    /// An Akkusativ-oder-Dativ pack must hold both cases, each at least a third of it.
    case caseBalance = "gap.composition.caseBalance"
    /// A batch-sized pack must use every table verb.
    case verbCoverage = "gap.composition.verbCoverage"
    /// A batch-sized pack must use every person.
    case personSpread = "gap.composition.personSpread"
}

/// One thing found wrong, with what was found.
nonisolated struct GapChoiceProblem: Hashable {
    let code: GapChoiceCheckCode
    let detail: String
    var line: String { "\(code.rawValue) \(detail)" }
}

nonisolated struct GapChoiceCheckResult {
    let item: GapChoiceItem
    let codes: [GapChoiceCheckCode]
    let problems: [GapChoiceProblem]

    var passes: Bool { !codes.contains(where: \.rejects) }
    var firstReject: String? { codes.first(where: \.rejects)?.rawValue }
    /// The rejecting problems, one line each.
    var errors: [String] { problems.filter { $0.code.rejects }.map(\.line) }
    /// The recorded ones (unknown words, an unverified gender).
    var warnings: [String] { problems.filter { !$0.code.rejects }.map(\.line) }
}

nonisolated struct GapCompositionProblem: Hashable {
    let code: GapCompositionCode
    let detail: String
}

@MainActor
enum GapChoiceCheck {

    /// Topic keys a pack may file under: the reflexive topic, or a unit of the case path.
    static let knownTopics = Set(["reflexiv"] + KasusUnit.allCases.map(\.rawValue))

    /// Words that join clauses.
    static let conjunctions: Set<String> = ["und", "oder", "aber", "denn", "dass", "weil", "wenn", "ob", "als",
                                            "obwohl", "damit", "nachdem", "bevor", "sondern", "sodass", "wo", "wie"]

    static func run(_ item: GapChoiceItem, lexicon: some KasusLexicon = AppKasusLexicon()) -> GapChoiceCheckResult {
        var codes: [GapChoiceCheckCode] = []
        var problems: [GapChoiceProblem] = []
        func flag(_ code: GapChoiceCheckCode, _ detail: String) {
            if !codes.contains(code) { codes.append(code) }
            problems.append(GapChoiceProblem(code: code, detail: detail))
        }

        // Shape.
        if !item.id.hasPrefix("rx-") { flag(.id, "id „\(item.id)“ doesn't start with rx-") }
        if !knownTopics.contains(item.topic) { flag(.topic, "unknown topic \(item.topic)") }
        if CEFRLevel(rawValue: item.level) == nil { flag(.level, "unknown level \(item.level)") }
        if item.english.trimmingCharacters(in: .whitespaces).isEmpty { flag(.english, "no English") }
        let numbers = item.placeholderNumbers
        if item.gaps.isEmpty || numbers.sorted() != Array(1...max(1, item.gaps.count)) || numbers.count != item.gaps.count {
            flag(.shape, "placeholders \(numbers) for \(item.gaps.count) gap(s)")
        }
        if item.sentence.contains("___") { flag(.shape, "a bare blank in the sentence") }
        for (i, gap) in item.gaps.enumerated() {
            let options = gap.options.map { $0.lowercased() }
            if Set(options).count != options.count || options.count < 2 || !options.contains(gap.answer.lowercased()) {
                flag(.options, "gap \(i + 1): options \(gap.options) for „\(gap.answer)“")
            }
            if item.presentation == .inline, options.count != 2 { flag(.options, "gap \(i + 1): an inline gap has two options, not \(options.count)") }
            if gap.kind == .pronoun {
                for option in options where !ReflexivPronoun.all.contains(option) { flag(.options, "gap \(i + 1): „\(option)“ isn't a reflexive pronoun") }
                if gap.kasus == nil { flag(.shape, "gap \(i + 1): a pronoun gap names its case") }
            }
        }
        if let first = item.gaps.first, first.kind != .pronoun { flag(.shape, "only pronoun gaps are gated yet") }
        guard let gap = item.gaps.first, gap.kind == .pronoun, let kasus = gap.kasus,
              !codes.contains(.shape), !codes.contains(.options) else {
            return GapChoiceCheckResult(item: item, codes: codes, problems: problems)
        }

        let filled = item.filled

        // Subject.
        if ReflexivSubject.matching(item.subject) == nil {
            flag(.subject, "„\(item.subject.text)“ as \(item.subject.person)\(item.subject.number.rawValue) isn't a table subject")
        }
        if filled.range(of: item.subject.text, options: [.caseInsensitive, .anchored]) == nil {
            flag(.subject, "the sentence doesn't start with „\(item.subject.text)“")
        }

        // Verb.
        let words = KasusScanner.words(in: filled).map { $0.text }
        let lower = words.map { $0.lowercased() }
        if let verb = ReflexivVerb.named(item.verb.lemma) {
            if verb.takes != item.verb.takes { flag(.verbUnknown, "„\(verb.lemma)“ takes \(verb.takes.rawValue), not \(item.verb.takes.rawValue)") }
            if let expected = verb.form(person: item.subject.person, number: item.subject.number), expected != item.verb.form {
                flag(.verbForm, "„\(item.verb.form)“ for \(item.subject.text): the table says „\(expected)“")
            }
            if (verb.prefix ?? "") != (item.verb.prefix ?? "") { flag(.prefix, "prefix „\(item.verb.prefix ?? "")“, the table says „\(verb.prefix ?? "")“") }
        } else {
            flag(.verbUnknown, "„\(item.verb.lemma)“ isn't in ReflexivVerb.table")
        }
        if !lower.contains(item.verb.form.lowercased()) { flag(.verbForm, "„\(item.verb.form)“ isn't in the sentence") }
        if let prefix = item.verb.prefix {
            if lower.last != prefix.lowercased() { flag(.prefix, "„\(prefix)“ must be the last word") }
        }

        // Answer and the case rule.
        if let expected = ReflexivPronoun.form(person: item.subject.person, number: item.subject.number, kasus: kasus) {
            if expected != gap.answer.lowercased() { flag(.answer, "„\(gap.answer)“: \(item.subject.text) in the \(kasus.rawValue) is „\(expected)“") }
        } else {
            flag(.answer, "no reflexive form for \(item.subject.person)\(item.subject.number.rawValue) in the \(kasus.rawValue)")
        }
        switch (item.verb.takes, item.secondObject) {
        case (.akk, nil) where kasus == .akkusativ: break
        case (.akk, _):            flag(.caseRule, "„sich \(item.verb.lemma)“ takes the Akkusativ and no second object")
        case (.dat, .some) where kasus == .dativ: break
        case (.dat, _):            flag(.caseRule, "„sich etwas \(item.verb.lemma)“ needs a second object and the Dativ")
        case (.both, nil) where kasus == .akkusativ: break
        case (.both, .some) where kasus == .dativ: break
        case (.both, let object):  flag(.caseRule, object == nil ? "no second object, so the Akkusativ" : "a second object, so the Dativ")
        }

        // The second object: after the gap, verbatim; its determiner an Akkusativ one for the
        // lemma's gender and number; the lexicon's gender.
        var excluded: [NSRange] = []
        let ns = filled as NSString
        if let object = item.secondObject {
            let gapStart = item.answerStart(of: 0) ?? 0
            let range = ns.range(of: object.text, options: [], range: NSRange(location: gapStart, length: ns.length - gapStart))
            if range.location == NSNotFound {
                flag(.object, "„\(object.text)“ isn't written after the gap")
            } else {
                excluded.append(range)
            }
            let genus: Gender = object.number == .pl ? .plural : object.genus
            if let determiner = object.text.split(separator: " ").first.map(String.init), KasusForms.parseDeterminer(determiner.lowercased()) != nil {
                if !KasusForms.compatibleCases(determiner: determiner.lowercased(), genus: genus).contains(.akkusativ) {
                    flag(.objectCase, "„\(determiner)“ isn't an Akkusativ form for \(genus.rawValue) „\(object.lemma)“")
                }
            } else {
                flag(.object, "„\(object.text)“ doesn't start with an article")
            }
            switch lexicon.gender(forLemma: object.lemma) {
            case .verified(let found):
                if object.number == .sg, found != object.genus { flag(.objectGender, "„\(object.lemma)“ is \(found.rawValue), not \(object.genus.rawValue)") }
                if object.number == .pl, found != object.genus, found != .plural { flag(.objectGender, "„\(object.lemma)“ is \(found.rawValue), not \(object.genus.rawValue)") }
            case .conflict(let genders):
                if !genders.contains(object.genus) { flag(.objectGender, "„\(object.lemma)“: the sources say \(genders.map(\.rawValue))") }
            case .unverified:
                flag(.objectUnverified, "„\(object.lemma)“ has no verified gender")
            }
        }
        if let tail = item.tail {
            let range = ns.range(of: tail)
            if range.location == NSNotFound { flag(.shape, "the tail „\(tail)“ isn't in the sentence") } else { excluded.append(range) }
        }

        // The frame: one simple clause, nothing the plan didn't have.
        if filled.contains(where: { ",;:".contains($0) }) || lower.contains(where: conjunctions.contains) {
            flag(.notSimple, "a second clause or a label")
        }
        if KasusScanner.sentences(in: filled).count != 1 { flag(.notSimple, "not one sentence") }
        let nouns = KasusNounIndex(extra: item.secondObject.map { [$0.lemma] } ?? [], lexicon: lexicon)
        let extras = KasusHarvest.harvest(paragraphs: [filled], excluding: [0: excluded], nouns: nouns, lexicon: lexicon)
        for extra in extras { flag(.extraPhrase, "„\(extra.surface)“ isn't the second object or the tail") }
        let answerIndex = lower.firstIndex(of: gap.answer.lowercased())
        for (i, word) in lower.enumerated() where i != answerIndex {
            if ReflexivPronoun.all.contains(word) || KasusForms.caseVisiblePronouns[word] != nil {
                flag(.extraPronoun, "„\(words[i])“ is another pronoun that shows a case")
            }
        }

        // Words the lexicon knows. Skipped for a lexicon without a dictionary.
        let known: Set<String> = ReflexivPronoun.all
            .union(ReflexivSubject.all.map { $0.text.lowercased() })
            .union([item.verb.form.lowercased(), (item.verb.prefix ?? "").lowercased()])
        for word in lower where !known.contains(word) && !word.isEmpty && word.allSatisfy(\.isLetter) {
            // Articles and contractions are the forms engine's, not the dictionary's.
            if KasusForms.parseDeterminer(word) != nil || KasusForms.contraction(word) != nil { continue }
            if let parts = lexicon.partsOfSpeech(word), parts.isEmpty { flag(.unknownWord, "„\(word)“") }
        }

        return GapChoiceCheckResult(item: item, codes: codes, problems: problems)
    }

    /// The whole pack: duplicates, and the balance an Akkusativ-oder-Dativ pack needs. From
    /// `batchSize` items on, every table verb and every person must appear.
    static func composition(_ items: [GapChoiceItem], batchSize: Int = 40) -> [GapCompositionProblem] {
        var problems: [GapCompositionProblem] = []
        var ids = Set<String>()
        var sentences = Set<String>()
        for item in items {
            if !ids.insert(item.id).inserted { problems.append(.init(code: .duplicateID, detail: item.id)) }
            if !sentences.insert(item.filled.lowercased()).inserted { problems.append(.init(code: .duplicateSentence, detail: item.filled)) }
        }
        let packs = Dictionary(grouping: items) { "\($0.topic)/\($0.focus.rawValue)" }
        for (key, pack) in packs.sorted(by: { $0.key < $1.key }) {
            let focus = pack.first?.focus
            if focus == .case, pack.count >= 3 {
                let need = Int((Double(pack.count) / 3).rounded(.up))
                for kasus in [GrammarCase.akkusativ, .dativ] {
                    let have = pack.filter { $0.kasus == kasus }.count
                    if have < need { problems.append(.init(code: .caseBalance, detail: "\(key): \(kasus.short) \(have) < \(need)")) }
                }
            }
            if pack.count >= batchSize, focus == .case || focus == .person {
                let verbs = Set(pack.map(\.verb.lemma))
                for verb in ReflexivVerb.table where !verbs.contains(verb.lemma) {
                    problems.append(.init(code: .verbCoverage, detail: "\(key): „\(verb.lemma)“ never appears"))
                }
                let persons = Set(pack.map { "\($0.subject.person)\($0.subject.number.rawValue)" })
                let wanted = focus == .case ? ["1sg", "2sg"] : ["1sg", "2sg", "3sg", "1pl", "2pl", "3pl"]
                for person in wanted where !persons.contains(person) {
                    problems.append(.init(code: .personSpread, detail: "\(key): no \(person) subject"))
                }
            }
        }
        return problems
    }
}
