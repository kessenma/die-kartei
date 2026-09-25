//
//  KasusValidator.swift
//  german-ai-flashcards
//
//  The answer key for the Kasus stories. `validate` finds every target in the text, derives what
//  can be proved about its case, and reports anything wrong under a stable issue code (the same
//  codes the Phase 3 Lab histograms). It gates the bundled stories in DEBUG now and the tutor's
//  stories later. No SwiftData, no UI; the lexicon is injected, so it runs the same on a stub.
//
//  Proof rule: candidates = the cases the determiner fits with this gender. One left → `.form`.
//  Otherwise narrow by the preposition in front (`.preposition`), then, for a predicate, by a
//  main-verb sein/werden/bleiben/heißen (`.copula`). Still several → `.label`: only the annotation
//  decides, which an authored story may rely on and a generated one may not.
//
//  A contraction („im“, „zur“) is read as its preposition + article, so it is proven by the
//  article's form or by its own preposition; a case-visible pronoun (mich, mir …) by its form.
//  Both are spot-only targets: gradable, never blankable.
//

import Foundation

// MARK: - Lexicon

/// What the validator needs to know about words. The app's version (`AppKasusLexicon`) reads the
/// Wiktionary database, the Goethe lists and prepositions.json; tests pass a stub.
protocol KasusLexicon {
    /// The gender of a singular lemma. `.plural` for a noun that only exists in the plural.
    func gender(forLemma lemma: String) -> KasusLexiconVerdict
    /// The Goethe list's plural marker ("-", "-e", "¨-er", "only pl." …), when a list has the noun.
    func goethePlural(forLemma lemma: String) -> String?
    /// The cases a preposition governs, ignoring case. Nil when the word isn't a preposition.
    func prepositionCases(_ word: String) -> Set<GrammarCase>?
    /// Whether it is a two-way (Wo/Wohin) preposition.
    func isTwoWay(_ word: String) -> Bool
}

nonisolated enum KasusLexiconVerdict: Hashable {
    case verified(Gender)
    /// The sources disagree; every gender any of them gave, in table order.
    case conflict([Gender])
    case unverified
}

// MARK: - Issues

/// Stable issue codes. The raw values are the histogram keys, so never rename one.
nonisolated enum KasusIssueCode: String, CaseIterable, Hashable {
    case locateNotFound = "locate.notFound"
    case unknownDeterminer = "np.unknownDeterminer"
    case impossibleForm = "morph.impossibleForm"
    case caseMismatch = "morph.caseMismatch"
    case pluralForm = "morph.pluralForm"
    case nDeklination = "morph.nDeklination"
    case genitiveS = "morph.genitiveS"
    case lexGender = "lex.gender"
    case lexConflict = "lex.conflict"
    case lexUnverified = "lex.unverified"
    case triggerMissing = "trigger.missing"
    case triggerPrepositionCase = "trigger.prepositionCase"
    case triggerWechselVerb = "trigger.wechselVerb"
    case reasonCaseMismatch = "reason.caseMismatch"
    case untargetedDeterminer = "coverage.untargetedDeterminer"
    case unitCaseCount = "story.unitCaseCount"
    case wordCount = "story.wordCount"

    /// The German itself is wrong, not just the annotation.
    var isMorphology: Bool { rawValue.hasPrefix("morph.") }
    var isStoryLevel: Bool { rawValue.hasPrefix("story.") }
}

nonisolated struct KasusIssue: Hashable {
    nonisolated enum Severity: String, Hashable { case error, warning }

    let severity: Severity
    let code: KasusIssueCode
    /// For the developer, in English.
    let message: String
    /// Index into `story.targets`; nil for story-level issues.
    let target: Int?
}

// MARK: - Report

struct KasusReport {
    let storyID: String
    let source: KasusStorySource
    let storyIssues: [KasusIssue]
    let targets: [TargetResult]
    /// Authored: no errors at all. Generated: nothing that rejects the whole story.
    let passes: Bool
    let gradableByCase: [GrammarCase: Int]
    /// Over every located target.
    let proofTally: [KasusProof: Int]
    let wordCount: Int

    /// One entry per `story.targets` element, in order. `located` is nil when the phrase wasn't
    /// found.
    struct TargetResult {
        let index: Int
        let spec: KasusTargetSpec
        let located: KasusLocatedTarget?
        let issues: [KasusIssue]
    }

    /// The targets found in the text, in reading order: what Finden and Einsetzen render.
    var located: [KasusLocatedTarget] { targets.compactMap(\.located) }

    var allIssues: [KasusIssue] { storyIssues + targets.flatMap(\.issues) }
    var errors: [KasusIssue] { allIssues.filter { $0.severity == .error } }
    var warnings: [KasusIssue] { allIssues.filter { $0.severity == .warning } }

    var codeHistogram: [KasusIssueCode: Int] {
        allIssues.reduce(into: [:]) { $0[$1.code, default: 0] += 1 }
    }

    /// Located targets per kind: how many are spot-only contractions and pronouns.
    var kindTally: [KasusTargetKind: Int] {
        located.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }

    /// Labelled case counts over located targets ("Nom 6 · Akk 11 · Dat 9").
    var casesLine: String {
        let counts = located.reduce(into: [GrammarCase: Int]()) { $0[$1.kasus, default: 0] += 1 }
        return GrammarCase.allCases.compactMap { kasus in
            counts[kasus].map { "\(kasus.short) \($0)" }
        }.joined(separator: " · ")
    }

    /// "ks-dat-a2-schluessel OK · 26 targets · form 20 · preposition 2 · copula 0 · label 4 · 0 errors"
    var summaryLine: String {
        var parts = ["\(storyID) \(passes ? "OK" : "FAIL")", "\(targets.count) targets"]
        parts += KasusProof.allCases.map { "\($0.rawValue) \(proofTally[$0, default: 0])" }
        parts.append("\(errors.count) error\(errors.count == 1 ? "" : "s")")
        if !warnings.isEmpty { parts.append("\(warnings.count) warning\(warnings.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    /// One line per issue, for asserts and the debug report.
    var issueLines: [String] {
        allIssues.map { issue in
            let severity = issue.severity.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
            let target = issue.target.map { "#\($0 + 1) " } ?? ""
            return "\(severity) \(issue.code.rawValue)  \(target)\(issue.message)"
        }
    }
}

// MARK: - Validator

enum KasusValidator {

    /// The tunable counts and the source-dependent rules.
    enum Policy {
        /// A unit's story needs at least this many targets of the unit's case.
        static let minUnitCaseTargets = 3
        /// Alle Fälle has no single case, so it needs this many of each of the four instead.
        static let minPerCaseAllCases = 2

        /// Coverage can only be promised for a story a human annotated in full, and word count is
        /// a guide for an author but a hard limit for the tutor. The gender sources disagreeing,
        /// or knowing nothing, is never the story's fault.
        static func severity(of code: KasusIssueCode, source: KasusStorySource) -> KasusIssue.Severity {
            switch code {
            case .lexConflict, .lexUnverified:  return .warning
            case .wordCount:                    return source == .authored ? .warning : .error
            case .untargetedDeterminer:         return source == .authored ? .error : .warning
            default:                            return .error
            }
        }

        /// Generated stories: these errors mean the German itself is wrong, so the whole story goes
        /// rather than a single target. A wrong gender on a verified noun almost always means a
        /// wrong article in the text („das Tasche“), so it is here too. Other target errors only
        /// make that target plain text.
        static func rejectsGeneratedStory(_ code: KasusIssueCode) -> Bool {
            code.isMorphology || code.isStoryLevel
                || code == .triggerPrepositionCase || code == .triggerWechselVerb || code == .lexGender
        }
    }

    static func validate(_ story: KasusStory, source: KasusStorySource, lexicon: some KasusLexicon) -> KasusReport {
        let texts = story.paragraphs.map(\.de)
        let paragraphs = texts.map(KasusScannedParagraph.init)

        var results: [KasusReport.TargetResult] = []
        var cursor: (paragraph: Int, index: String.Index)? = texts.first.map { (0, $0.startIndex) }

        for (index, spec) in story.targets.enumerated() {
            func issue(_ code: KasusIssueCode, _ message: String) -> KasusIssue {
                KasusIssue(severity: Policy.severity(of: code, source: source), code: code, message: message, target: index)
            }
            guard let start = cursor,
                  let hit = locate(spec.phrase, in: texts, from: start)
            else {
                let place = index == 0 ? "in the text" : "after target #\(index)"
                results.append(.init(index: index, spec: spec, located: nil,
                                     issues: [issue(.locateNotFound, "„\(spec.phrase)“ not found \(place)")]))
                continue
            }
            cursor = (hit.paragraph, hit.range.upperBound)
            let (located, issues) = analyze(spec, index: index, paragraph: paragraphs[hit.paragraph],
                                            paragraphIndex: hit.paragraph, range: hit.range,
                                            lexicon: lexicon, issue: issue)
            results.append(.init(index: index, spec: spec, located: located, issues: issues))
        }

        var storyIssues: [KasusIssue] = []
        func storyIssue(_ code: KasusIssueCode, _ message: String) {
            storyIssues.append(KasusIssue(severity: Policy.severity(of: code, source: source),
                                          code: code, message: message, target: nil))
        }

        // Coverage: every determiner (or contraction) that opens a noun phrase starts a target or
        // sits inside a notTargets phrase. A story that targets one case-visible pronoun targets
        // all of them (mich, mir, dich, dir, ihn, ihm), so Finden's hunt stays complete.
        let targetsPronouns = results.contains { $0.located?.kind == .pronoun }
        for (p, paragraph) in paragraphs.enumerated() {
            let starts = Set(results.compactMap { result -> Int? in
                guard let located = result.located, located.paragraphIndex == p else { return nil }
                return located.range.location
            })
            let exempt = story.notTargets.flatMap { notTarget in
                KasusScanner.occurrences(of: notTarget.phrase, in: paragraph.text)
            }
            for (i, token) in paragraph.tokens.enumerated() {
                let lower = token.text.lowercased()
                let phraseEnd: String.Index
                if targetsPronouns, KasusForms.pronoun(lower) != nil {
                    phraseEnd = token.range.upperBound
                } else if KasusForms.parseDeterminer(lower) != nil || KasusForms.contractions[lower] != nil,
                          let nounIndex = nounAfterDeterminer(at: i, in: paragraph) {
                    phraseEnd = paragraph.tokens[nounIndex].range.upperBound
                } else {
                    continue
                }
                let location = NSRange(token.range, in: paragraph.text).location
                if starts.contains(location) { continue }
                if exempt.contains(where: { $0.contains(token.range.lowerBound) }) { continue }
                let phrase = paragraph.text[token.range.lowerBound..<phraseEnd]
                storyIssue(.untargetedDeterminer,
                           "„\(phrase)“ in paragraph \(p + 1) is neither a target nor a notTarget")
            }
        }

        // Gradable, per source policy. Only an article target can be blanked.
        results = results.map { result in
            guard var located = result.located else { return result }
            let hasError = result.issues.contains { $0.severity == .error }
            var gradable = !hasError
            if source == .generated {
                if located.proof == .label { gradable = false }
                if case .verified = located.genderVerdict {} else { gradable = false }
            }
            located.gradable = gradable
            located.blankable = gradable && located.kind == .article && located.parsed != nil
            return .init(index: result.index, spec: result.spec, located: located, issues: result.issues)
        }
        let located = results.compactMap(\.located)
        let gradableByCase = located.filter(\.gradable).reduce(into: [GrammarCase: Int]()) { $0[$1.kasus, default: 0] += 1 }
        let proofTally = located.reduce(into: [KasusProof: Int]()) { $0[$1.proof, default: 0] += 1 }

        // Enough of the unit's case. Authored stories count their labels; generated ones only what
        // can be graded.
        let caseCounts = source == .authored
            ? located.reduce(into: [GrammarCase: Int]()) { $0[$1.kasus, default: 0] += 1 }
            : gradableByCase
        if let unit = story.unit {
            if let focus = unit.focusCase {
                let count = caseCounts[focus, default: 0]
                if count < Policy.minUnitCaseTargets {
                    storyIssue(.unitCaseCount, "\(count) \(focus.name) target\(count == 1 ? "" : "s"); a \(focus.name) story needs \(Policy.minUnitCaseTargets)")
                }
            } else {
                for kasus in unit.casesInPlay where caseCounts[kasus, default: 0] < Policy.minPerCaseAllCases {
                    storyIssue(.unitCaseCount, "\(caseCounts[kasus, default: 0]) \(kasus.name) targets; Alle Fälle needs \(Policy.minPerCaseAllCases) of each case")
                }
            }
        } else {
            storyIssue(.unitCaseCount, "unknown unit „\(story.unitRaw)“")
        }

        // Length for the level.
        let wordCount = paragraphs.reduce(0) { $0 + $1.tokens.count }
        if let range = story.cefr?.storyWordRange {
            if !range.contains(wordCount) {
                storyIssue(.wordCount, "\(wordCount) words; \(story.level) stories run \(range.lowerBound)–\(range.upperBound)")
            }
        } else {
            storyIssue(.wordCount, "unknown level „\(story.level)“")
        }

        let allErrors = (storyIssues + results.flatMap(\.issues)).filter { $0.severity == .error }
        let passes = source == .authored
            ? allErrors.isEmpty
            : !allErrors.contains { Policy.rejectsGeneratedStory($0.code) }

        return KasusReport(storyID: story.id, source: source, storyIssues: storyIssues, targets: results,
                           passes: passes, gradableByCase: gradableByCase, proofTally: proofTally,
                           wordCount: wordCount)
    }

    /// Words that may stand between an article and its adjective („ein sehr großer Hund“).
    private static let intensifiers: Set<String> = ["sehr", "ganz", "besonders", "ziemlich", "wirklich"]

    /// The noun a determiner or contraction opens, with nothing but spaces in between: the next
    /// word when it is capitalised („den Ball“), or the first capitalised word after up to three
    /// adjectives whose ending fits the article („einen großen Ball“, „ein sehr kleines Kind“).
    /// A bare ein-word takes -er/-es adjectives, every other article -e/-en, so a relative „der“
    /// or a pronoun „ihr“ in front of a verb or adverb doesn't read as an article. Nil when no
    /// noun follows.
    private static func nounAfterDeterminer(at index: Int, in paragraph: KasusScannedParagraph) -> Int? {
        let tokens = paragraph.tokens
        let bare = KasusForms.parseDeterminer(tokens[index].text).map { $0.family != .definite && $0.ending.isEmpty } ?? false
        let adjectiveEndings = bare ? ["er", "es"] : ["e", "en"]
        var j = index + 1
        var skipped = 0
        while j < tokens.count, paragraph.isWhitespaceGap(tokens[j - 1], tokens[j]) {
            let word = tokens[j].text
            if word.first?.isUppercase == true { return j }
            let lower = word.lowercased()
            let isAdjective = word.count > 3 && adjectiveEndings.contains { lower.hasSuffix($0) }
                && KasusForms.parseDeterminer(lower) == nil && KasusForms.contractions[lower] == nil
            guard skipped < 3, isAdjective || intensifiers.contains(lower) else { return nil }
            skipped += 1
            j += 1
        }
        return nil
    }

    // MARK: Locating

    /// Verbatim, on word boundaries, first letter case-insensitive, starting where the previous
    /// target ended and moving on through later paragraphs.
    private static func locate(_ phrase: String, in texts: [String],
                               from start: (paragraph: Int, index: String.Index)) -> (paragraph: Int, range: Range<String.Index>)? {
        let phrase = phrase.trimmingCharacters(in: .whitespaces)
        guard let head = phrase.first, KasusScanner.isWordCharacter(head) else { return nil }
        for p in start.paragraph..<texts.count {
            let from = p == start.paragraph ? start.index : texts[p].startIndex
            if let range = KasusScanner.find(phrase, in: texts[p], from: from) { return (p, range) }
        }
        return nil
    }

    // MARK: Per target

    private static func analyze(
        _ spec: KasusTargetSpec,
        index: Int,
        paragraph: KasusScannedParagraph,
        paragraphIndex: Int,
        range: Range<String.Index>,
        lexicon: some KasusLexicon,
        issue: (KasusIssueCode, String) -> KasusIssue
    ) -> (KasusLocatedTarget, [KasusIssue]) {
        let text = paragraph.text
        let tokens = paragraph.tokens
        var issues: [KasusIssue] = []

        // The phrase's words: the determiner first, the noun last. A match that doesn't start on a
        // token („Mail“ inside „E-Mail“) is read as one unknown word.
        let firstIndex = tokens.firstIndex { $0.range.lowerBound == range.lowerBound }
        let lastIndex = tokens.lastIndex { $0.range.lowerBound >= range.lowerBound && $0.range.upperBound <= range.upperBound }
        let first = firstIndex ?? 0
        let last = firstIndex == nil ? first : max(first, lastIndex ?? first)
        let determinerToken = firstIndex.map { tokens[$0] }
            ?? KasusScanner.Token(text: String(text[range]), range: range)
        let nounToken = firstIndex == nil ? determinerToken : tokens[last]
        let isSingleWord = firstIndex == nil || last == first
        let sentence = paragraph.sentence(containing: range.lowerBound)
        let clause = paragraph.clause(containing: range, in: sentence)
        let trigger = spec.trigger.trimmingCharacters(in: .whitespaces)
        let triggerLower = trigger.lowercased()
        let lemma = spec.lemma.trimmingCharacters(in: .whitespaces)
        let noun = nounToken.text

        // What opens the phrase: a lone case-visible pronoun, a contraction + noun, or an article.
        let pronoun = firstIndex != nil && isSingleWord ? KasusForms.pronoun(determinerToken.text) : nil
        let contraction = firstIndex != nil && !isSingleWord ? KasusForms.contraction(determinerToken.text) : nil
        let kind: KasusTargetKind = pronoun != nil ? .pronoun : contraction != nil ? .contraction : .article
        // „zur“ reads as „zur (zu + der)“ in a message.
        let formLabel = contraction.map { "„\(determinerToken.text)“ (\($0.preposition) + \($0.article))" }
            ?? "„\(determinerToken.text)“"

        // Determiner and the cases its form allows.
        var parsed = KasusForms.parseDeterminer(determinerToken.text)
        if isSingleWord || kind != .article { parsed = nil }
        if parsed == nil, kind == .article {
            let why = isSingleWord
                ? "is one word; a target is determiner + noun, or one of mich, mir, dich, dir, ihn, ihm"
                : "doesn't start with an article word (der, ein, kein, a possessive, dieser) or a contraction"
            issues.append(issue(.unknownDeterminer, "„\(spec.phrase)“ \(why)"))
        }
        let candidates: Set<GrammarCase> = switch kind {
        case .article:     parsed.map { KasusForms.compatibleCases($0, genus: spec.genus) } ?? []
        case .contraction: contraction.map { KasusForms.compatibleCases(determiner: $0.article, genus: spec.genus) } ?? []
        case .pronoun:     pronoun.map { [$0.kasus] } ?? []
        }

        // Gender, always on the singular lemma. The curated lists come before the lexicon. A
        // pronoun has no lemma to look up: ihn stands for a masculine noun, ihm for a masculine or
        // neuter one, and the ich/du forms have no gender to check.
        let verdict: KasusLexiconVerdict
        if let pronoun {
            verdict = .verified(spec.genus)
            if let genders = pronoun.genders, !genders.contains(spec.genus) {
                let names = Gender.allCases.filter(genders.contains).map(\.genderName).joined(separator: " or ")
                issues.append(issue(.lexGender, "„\(determinerToken.text)“ stands for a \(names) noun, not \(spec.genus.genderName)"))
            }
        } else if let dual = KasusForms.dualGenders(of: lemma) {
            verdict = spec.genus == .plural || dual.contains(spec.genus)
                ? .verified(spec.genus)
                : .conflict(Gender.allCases.filter(dual.contains))
        } else if KasusForms.isPluraleTantum(lemma) {
            verdict = .verified(.plural)
        } else if lemma.isEmpty {
            verdict = .unverified
        } else {
            verdict = lexicon.gender(forLemma: lemma)
        }
        switch verdict {
        case .verified(let gender):
            if gender == .plural, spec.genus != .plural {
                issues.append(issue(.lexGender, "\(lemma) only exists in the plural, but the target says \(spec.genus.columnLabel)"))
            } else if gender != .plural, spec.genus != .plural, gender != spec.genus {
                issues.append(issue(.lexGender, "\(lemma) is \(gender.columnLabel), not \(spec.genus.columnLabel)"))
            }
        case .conflict(let genders):
            let listed = genders.map(\.columnLabel).joined(separator: "/")
            if spec.genus != .plural, !genders.contains(spec.genus) {
                issues.append(issue(.lexGender, "\(lemma) is \(listed) in the sources, never \(spec.genus.columnLabel)"))
            } else {
                issues.append(issue(.lexConflict, "the sources disagree on \(lemma): \(listed)"))
            }
        case .unverified:
            issues.append(issue(.lexUnverified, lemma.isEmpty ? "no lemma" : "no source knows the gender of \(lemma)"))
        }
        var singularGender: Gender?
        if case .verified(let gender) = verdict, gender != .plural { singularGender = gender }
        let goethePlural = lemma.isEmpty || pronoun != nil ? nil : lexicon.goethePlural(forLemma: lemma)
        let sameInPlural = pronoun == nil
            && KasusForms.mightBeSameInPlural(lemma: lemma, genus: singularGender, goethePlural: goethePlural)
        // A Dativ plural adds -n (den Schlüsseln), so there only a noun already ending in -n or -s
        // (dem Mädchen) could be either number. An n-noun outside the Nominativ reads the same in
        // both numbers too (den Nachbarn · die Nachbarn). Only a blank shows the tag, so spot-only
        // targets never need it.
        let bareNounAmbiguous = sameInPlural && noun.caseInsensitiveCompare(lemma) == .orderedSame
            && (spec.kasus != .dativ || noun.hasSuffix("n") || noun.hasSuffix("s"))
        let nNounAmbiguous = pronoun == nil
            && KasusForms.nNounReadsAsPlural(noun: noun, lemma: lemma, kasus: spec.kasus)
        let numberAmbiguous = kind == .article && !KasusForms.isPluraleTantum(lemma)
            && (bareNounAmbiguous || nNounAmbiguous)

        // The preposition: directly in front of the phrase, with nothing but a space between. The
        // authored trigger may also reach back across „und/oder + noun phrase“, or follow the noun
        // as a postposition. A contraction carries its own preposition („im“ → in), whatever
        // stands before it („bis zum“ is still zu).
        func context(_ token: KasusScanner.Token, _ position: KasusPrepositionContext.Position,
                     coordinated: Bool) -> KasusPrepositionContext? {
            let word = token.text.lowercased()
            let cases: Set<GrammarCase>
            let twoWay: Bool
            if word == "entlang" {
                cases = KasusForms.entlangCases(after: position == .after)
                twoWay = false
            } else {
                guard let governed = lexicon.prepositionCases(word) else { return nil }
                cases = governed
                twoWay = lexicon.isTwoWay(word)
            }
            if position == .after, !KasusForms.postpositions.contains(word) { return nil }
            return KasusPrepositionContext(word: word, cases: cases, isTwoWay: twoWay, position: position,
                                           viaCoordination: coordinated, range: NSRange(token.range, in: text))
        }
        var governing: KasusPrepositionContext?
        if let contraction {
            governing = KasusPrepositionContext(word: contraction.preposition,
                                                cases: lexicon.prepositionCases(contraction.preposition) ?? [],
                                                isTwoWay: lexicon.isTwoWay(contraction.preposition),
                                                position: .before, viaCoordination: false,
                                                range: NSRange(determinerToken.range, in: text))
        } else if firstIndex != nil, first > 0, paragraph.isWhitespaceGap(tokens[first - 1], determinerToken) {
            governing = context(tokens[first - 1], .before, coordinated: false)
        }
        // A contraction target's trigger may name the contraction („am“) or its preposition („an“).
        let triggerIsContraction = contraction != nil && triggerLower == determinerToken.text.lowercased()
        let triggerIsPreposition = triggerLower == "entlang" || lexicon.prepositionCases(triggerLower) != nil
            || triggerIsContraction
        if governing == nil, firstIndex != nil, triggerIsPreposition {
            if first > 1, KasusForms.coordinators.contains(tokens[first - 1].text.lowercased()),
               paragraph.isWhitespaceGap(tokens[first - 1], determinerToken) {
                // Walk back over the coordinated noun phrase to its determiner.
                var j = first - 2
                while j >= 0, j >= first - 6, paragraph.isWhitespaceGap(tokens[j], tokens[j + 1]) {
                    if KasusForms.parseDeterminer(tokens[j].text) != nil {
                        if j > 0, paragraph.isWhitespaceGap(tokens[j - 1], tokens[j]),
                           tokens[j - 1].text.lowercased() == triggerLower {
                            governing = context(tokens[j - 1], .before, coordinated: true)
                        }
                        break
                    }
                    j -= 1
                }
            }
            if governing == nil, last + 1 < tokens.count,
               paragraph.isWhitespaceGap(nounToken, tokens[last + 1]),
               tokens[last + 1].text.lowercased() == triggerLower {
                governing = context(tokens[last + 1], .after, coordinated: false)
            }
        }
        // bis, um, ohne … open clauses and zu-infinitives too („um dem Hund zu helfen“), so they
        // only count when the reason is `preposition` or the trigger names them („seit“ for a time).
        // A contraction („ums“) is always a preposition.
        var effective = governing
        if contraction == nil, let word = governing?.word, KasusForms.softPrepositions.contains(word),
           spec.reason != .preposition, triggerLower != word {
            effective = nil
        }

        // A main-verb copula, for predicate targets.
        let copulaVerb = spec.reason == .predicate ? mainCopula(in: clause, of: paragraph) : nil

        // Proof.
        var proof = KasusProof.label
        if candidates.count == 1 {
            proof = .form
        } else if candidates.count > 1 {
            var narrowed = candidates
            if let effective {
                narrowed.formIntersection(effective.cases)
                if narrowed.count == 1 { proof = .preposition }
            }
            if proof == .label, copulaVerb != nil {
                narrowed.formIntersection([.nominativ])
                if narrowed.count == 1 { proof = .copula }
            }
        }

        // Morphology: the determiner against the table, then the noun's own endings. A pronoun is
        // one word with one case.
        if let pronoun {
            if pronoun.kasus != spec.kasus {
                issues.append(issue(.caseMismatch, "„\(determinerToken.text)“ is \(pronoun.kasus.name), not \(spec.kasus.name) (the \(spec.kasus.name) is „\(pronoun.otherCase)“)"))
            }
        } else if parsed != nil || contraction != nil {
            if candidates.isEmpty {
                issues.append(issue(.impossibleForm, "\(formLabel) can't go with a \(spec.genus.genderName) noun in any case"))
            } else if !candidates.contains(spec.kasus) {
                let fits = GrammarCase.allCases.filter(candidates.contains).map(\.name).joined(separator: " or ")
                issues.append(issue(.caseMismatch, "\(formLabel) with a \(spec.genus.genderName) noun is \(fits), not \(spec.kasus.name)"))
            }
        }
        if pronoun != nil {
            // No noun, so no plural, n-noun or Genitiv -s to check.
        } else if spec.genus == .plural {
            // The plural the Goethe marker spells (Hund -e → Hunde), with the Dativ -n on top.
            // Without a marker, only the two things every plural shows.
            let known = KasusForms.isPluraleTantum(lemma)
                ? lemma : KasusForms.expectedPlural(lemma: lemma, marker: goethePlural)
            if let known {
                let wanted = spec.kasus == .dativ && !(known.hasSuffix("n") || known.hasSuffix("s")) ? known + "n" : known
                if noun.caseInsensitiveCompare(wanted) != .orderedSame {
                    issues.append(issue(.pluralForm, "„\(noun)“ isn't the \(spec.kasus == .dativ ? "Dativ " : "")plural of \(lemma): \(wanted)"))
                }
            } else if noun.caseInsensitiveCompare(lemma) == .orderedSame, !sameInPlural {
                issues.append(issue(.pluralForm, "„\(noun)“ is the singular; a plural target needs the plural of \(lemma)"))
            } else if spec.kasus == .dativ, !(noun.hasSuffix("n") || noun.hasSuffix("s")) {
                issues.append(issue(.pluralForm, "Dativ plural nouns end in -n (or -s): „\(noun)“"))
            }
        }
        if pronoun == nil, spec.genus == .der, spec.kasus != .nominativ, KasusForms.isNDeklination(lemma) {
            let wanted = lemma + KasusForms.nDeklinationEnding(lemma: lemma, kasus: spec.kasus)
            if noun.caseInsensitiveCompare(wanted) != .orderedSame {
                issues.append(issue(.nDeklination, "\(lemma) is an n-noun: \(spec.kasus.name) needs \(wanted), not „\(noun)“"))
            }
        }
        if pronoun == nil, spec.kasus == .genitiv, spec.genus == .der || spec.genus == .das,
           !KasusForms.isNDeklination(lemma), !KasusForms.isAdjectivalNoun(lemma),
           !KasusForms.isGenitiveSingular(noun, of: lemma) {
            issues.append(issue(.genitiveS, "masculine and neuter Genitiv nouns take -(e)s: „\(noun)“"))
        }

        // Trigger present where it should be.
        var triggerRange: NSRange?
        if trigger.isEmpty {
            issues.append(issue(.triggerMissing, "no trigger"))
        } else if spec.reason.needsPreposition || (spec.reason == .time && triggerIsPreposition) {
            if let governing, governing.word == triggerLower || triggerIsContraction {
                triggerRange = governing.range
            } else {
                let found = governing.map { "the preposition there is „\($0.word)“" } ?? "no preposition stands next to it"
                issues.append(issue(.triggerMissing, "„\(trigger)“ should govern „\(spec.phrase)“, but \(found)"))
            }
        } else {
            let words = triggerLower.split(whereSeparator: \.isWhitespace).map(String.init)
            let sentenceTokens = tokens.filter { sentence.contains($0.range.lowerBound) }
            let lowered = Set(sentenceTokens.map { $0.text.lowercased() })
            if let head = words.first, words.allSatisfy(lowered.contains) {
                if let token = sentenceTokens.first(where: { $0.text.lowercased() == head }) {
                    triggerRange = NSRange(token.range, in: text)
                }
            } else {
                issues.append(issue(.triggerMissing, "„\(trigger)“ isn't in the sentence of „\(spec.phrase)“"))
            }
        }

        // A fixed-case preposition decides, whatever the label says.
        var prepositionCaseFired = false
        if let effective, !effective.cases.contains(spec.kasus) {
            prepositionCaseFired = true
            let takes = GrammarCase.allCases.filter(effective.cases.contains).map(\.name).joined(separator: " or ")
            issues.append(issue(.triggerPrepositionCase, "„\(effective.word)“ takes the \(takes), but „\(spec.phrase)“ is labelled \(spec.kasus.name)"))
        }

        // liegen/stehen/sitzen answer Wo? (Dativ); legen/stellen/setzen answer Wohin? (Akkusativ).
        var wechselVerb: String?
        if let effective, effective.isTwoWay, effective.position == .before,
           spec.reason != .prepObject, spec.reason != .time {
            let clauseWords = tokens.filter { clause.contains($0.range.lowerBound) && !range.contains($0.range.lowerBound) }
            let found = clauseWords.compactMap { token -> (String, KasusForms.WechselVerbKind)? in
                KasusForms.wechselVerbForms[token.text.lowercased()].map { (token.text, $0.kind) }
            }
            let positions = found.filter { $0.1 == .position }
            let placements = found.filter { $0.1 == .placement }
            if let verb = positions.first, placements.isEmpty {
                wechselVerb = verb.0
                if spec.kasus == .akkusativ {
                    issues.append(issue(.triggerWechselVerb, "„\(verb.0)“ says where something is (Wo?), so „\(effective.word)“ needs the Dativ"))
                }
            } else if let verb = placements.first, positions.isEmpty {
                wechselVerb = verb.0
                if spec.kasus == .dativ {
                    issues.append(issue(.triggerWechselVerb, "„\(verb.0)“ moves something somewhere (Wohin?), so „\(effective.word)“ needs the Akkusativ"))
                }
            } else if found.isEmpty, spec.kasus == .dativ,
                      let motion = clauseWords.first(where: { KasusForms.motionVerbForms.contains($0.text.lowercased()) }) {
                issues.append(KasusIssue(severity: .warning, code: .triggerWechselVerb,
                                         message: "„\(motion.text)“ is a motion verb with a Dativ after „\(effective.word)“: check Wo? against Wohin?",
                                         target: index))
            }
        }

        // The reason must agree with the case. A preposition reason is already covered above.
        if spec.reason != .preposition, !prepositionCaseFired,
           let expected = spec.reason.expectedCases(after: governing), !expected.contains(spec.kasus) {
            let wants = GrammarCase.allCases.filter(expected.contains).map(\.name).joined(separator: " or ")
            issues.append(issue(.reasonCaseMismatch, "reason \(spec.reason.rawValue) means \(wants), but „\(spec.phrase)“ is labelled \(spec.kasus.name)"))
        }

        let located = KasusLocatedTarget(
            index: index,
            spec: spec,
            paragraphIndex: paragraphIndex,
            range: NSRange(range, in: text),
            determinerRange: NSRange(determinerToken.range, in: text),
            nounRange: NSRange(nounToken.range, in: text),
            sentenceRange: NSRange(sentence, in: text),
            triggerRange: triggerRange,
            surface: String(text[range]),
            determiner: determinerToken.text,
            noun: noun,
            parsed: parsed,
            candidates: candidates,
            preposition: effective,
            copulaVerb: copulaVerb,
            wechselVerb: wechselVerb,
            proof: proof,
            genderVerdict: verdict,
            numberAmbiguous: numberAmbiguous,
            gradable: false,
            blankable: false,
            kind: kind,
            contractedArticle: contraction?.article
        )
        return (located, issues)
    }

    /// The copula form in `clause` when sein/werden/bleiben/heißen is its main verb: no Partizip II
    /// or infinitive of another verb closes the clause („ist … gegangen“, „wird … füttern“), and it
    /// isn't „willkommen heißen“.
    private static func mainCopula(in clause: Range<String.Index>, of paragraph: KasusScannedParagraph) -> String? {
        let words = paragraph.tokens.filter { clause.contains($0.range.lowerBound) }
        guard !words.contains(where: { $0.text.lowercased() == "willkommen" }) else { return nil }
        let copula = words.enumerated().first { offset, token in
            guard KasusForms.copulaForms.contains(token.text.lowercased()) else { return false }
            // „sein Hund“ is the possessive, not the verb.
            let next = offset + 1 < words.count ? words[offset + 1] : nil
            return !(token.text.lowercased() == "sein" && next?.text.first?.isUppercase == true)
        }?.element
        guard let copula, let closing = words.last else { return nil }
        let lower = closing.text.lowercased()
        if KasusForms.copulaForms.contains(lower) { return copula.text }
        let lowercaseWord = closing.text.first?.isLowercase == true
        let looksVerbal = lower.hasSuffix("en") || lower.hasSuffix("ern") || lower.hasSuffix("eln")
            || lower.hasSuffix("iert") || (lower.hasPrefix("ge") && lower.hasSuffix("t") && lower.count >= 5)
        return lowercaseWord && looksVerbal ? nil : copula.text
    }
}

// MARK: - Scanning

/// A paragraph cut into words and sentences once, so every target reuses the cut.
nonisolated struct KasusScannedParagraph {
    let text: String
    let tokens: [KasusScanner.Token]
    let sentences: [Range<String.Index>]

    init(_ text: String) {
        self.text = text
        tokens = KasusScanner.words(in: text)
        sentences = KasusScanner.sentences(in: text)
    }

    func sentence(containing index: String.Index) -> Range<String.Index> {
        sentences.first { $0.contains(index) } ?? text.startIndex..<text.endIndex
    }

    /// The stretch of the sentence between commas, colons, semicolons, dashes, brackets and
    /// quotes that holds `range`.
    func clause(containing range: Range<String.Index>, in sentence: Range<String.Index>) -> Range<String.Index> {
        let breaks: Set<Character> = [",", ";", ":", "–", "—", "„", "“", "”", "\"", "(", ")"]
        var lower = range.lowerBound
        while lower > sentence.lowerBound {
            let previous = text.index(before: lower)
            if breaks.contains(text[previous]) { break }
            lower = previous
        }
        var upper = range.upperBound
        while upper < sentence.upperBound, !breaks.contains(text[upper]) {
            upper = text.index(after: upper)
        }
        return lower..<upper
    }

    /// Only whitespace between two tokens: no punctuation, no quote.
    func isWhitespaceGap(_ a: KasusScanner.Token, _ b: KasusScanner.Token) -> Bool {
        guard a.range.upperBound <= b.range.lowerBound else { return false }
        return text[a.range.upperBound..<b.range.lowerBound].allSatisfy(\.isWhitespace)
    }
}

nonisolated enum KasusScanner {
    nonisolated struct Token: Hashable {
        let text: String
        let range: Range<String.Index>
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Runs of letters and digits; a hyphen or apostrophe between two letters stays inside
    /// („E-Mail“, „geht's“).
    static func words(in text: String) -> [Token] {
        var tokens: [Token] = []
        var start: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            let character = text[i]
            let next = text.index(after: i)
            let joiner = "-'’".contains(character) && start != nil && next < text.endIndex && text[next].isLetter
            if isWordCharacter(character) || joiner {
                if start == nil { start = i }
            } else if let s = start {
                tokens.append(Token(text: String(text[s..<i]), range: s..<i))
                start = nil
            }
            i = next
        }
        if let s = start { tokens.append(Token(text: String(text[s...]), range: s..<text.endIndex)) }
        return tokens
    }

    /// Sentences end at . ! ? … (with any closing quotes) followed by a space or the end.
    static func sentences(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            var next = text.index(after: i)
            if ".!?…".contains(text[i]) {
                while next < text.endIndex, ".!?…“”\"'»)".contains(text[next]) { next = text.index(after: next) }
                if next == text.endIndex || text[next].isWhitespace {
                    result.append(start..<next)
                    var resume = next
                    while resume < text.endIndex, text[resume].isWhitespace { resume = text.index(after: resume) }
                    start = resume
                    i = resume
                    continue
                }
            }
            i = next
        }
        if start < text.endIndex { result.append(start..<text.endIndex) }
        return result
    }

    /// The first match of `phrase` at or after `from`: verbatim except the first letter's case,
    /// and on word boundaries at both ends.
    static func find(_ phrase: String, in text: String, from: String.Index) -> Range<String.Index>? {
        guard let head = phrase.first else { return nil }
        let rest = phrase.dropFirst()
        var i = from
        while i < text.endIndex {
            if text[i].lowercased() == head.lowercased() {
                let afterHead = text.index(after: i)
                if text[afterHead...].hasPrefix(rest) {
                    let end = text.index(afterHead, offsetBy: rest.count)
                    let openBoundary = i == text.startIndex || !isWordCharacter(text[text.index(before: i)])
                    let closeBoundary = end == text.endIndex || !isWordCharacter(text[end])
                    if openBoundary && closeBoundary { return i..<end }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    /// Every match of `phrase`, for the notTargets exemptions.
    static func occurrences(of phrase: String, in text: String) -> [Range<String.Index>] {
        let phrase = phrase.trimmingCharacters(in: .whitespaces)
        guard !phrase.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var from = text.startIndex
        while let range = find(phrase, in: text, from: from) {
            found.append(range)
            from = range.upperBound
        }
        return found
    }
}
