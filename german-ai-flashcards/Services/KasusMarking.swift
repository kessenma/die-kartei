//
//  KasusMarking.swift
//  german-ai-flashcards
//
//  Markieren, the class worksheet's „Markiere alle Wörter im Dativ“, and the numbered sentences
//  both story exercises show. Foundation only, like the validator, so the host harness runs it.
//
//    sentences   the story cut into numbered sentences (1., 2., … straight across paragraphs),
//                every word a `KasusWord` that knows what it is for marking
//    roles       a word of a gradable target (its case and part), a word that never counts (and
//                why), or a plain word
//    the round   one case per round: the learner's marks, judged word by word and scored like the
//                sheet, max(0, right − wrong) / case words, so marking everything scores low
//    notes       what a tap on a word says after Prüfen
//
//  Word-level: every word of a target in the asked case counts on its own (the article, any
//  adjective, the noun; a pronoun target is one word). Marking a word of another case's target,
//  or an ordinary word (a verb, a preposition, an adverb …), is wrong. Never counted either way:
//  contraction phrases („zum Geburtstag“: the class sheet doesn't count them), pronouns other
//  than mich, mir, dich, dir, ihn and ihm, phrases without an article (names, bare nouns and the
//  quantifier or adjective leading into them, even where its ending shows the case), numbers, an
//  unknown capitalised word at a sentence start, fixed phrases and the superlative „am liebsten“,
//  article words standing alone, and anything the validator couldn't grade. The notes say "not
//  counted here", never that no case shows. Recognition only: Markieren counts for the streak,
//  never for the coach (`KasusService.countsTowardSkill`).
//

import Foundation

// MARK: - Feedback mode

/// When Markieren and Endungen judge the learner's answers. Each exercise remembers its own
/// choice (`markStorageKey`, `endingsStorageKey`).
nonisolated enum KasusFeedbackMode: String, CaseIterable, Identifiable, Hashable {
    /// Every tap or pick is judged the moment it's made, with the `KasusFeedback` signal.
    case sofort
    /// Mark or fill freely; Prüfen judges everything at once, then Lösung zeigen, then Noch mal.
    case amEnde

    var id: String { rawValue }

    var germanLabel: String {
        switch self {
        case .sofort: "Sofort"
        case .amEnde: "Am Ende"
        }
    }

    var englishLabel: String {
        switch self {
        case .sofort: "After each answer"
        case .amEnde: "Check at the end"
        }
    }

    /// `@AppStorage` keys, one per exercise, so choosing one never changes the other.
    static let markStorageKey = "kasus.markFeedback"
    static let endingsStorageKey = "kasus.endingsFeedback"

    /// Markieren checks at the end, like the class sheet: missed words only exist once the
    /// learner says they're done. Endungen judges each pick, which is what the developer tried
    /// first and liked.
    static let markDefault: KasusFeedbackMode = .amEnde
    static let endingsDefault: KasusFeedbackMode = .sofort

    /// The stored choice, or `fallback` when there is none (or it's unreadable).
    static func resolve(stored raw: String, default fallback: KasusFeedbackMode) -> KasusFeedbackMode {
        KasusFeedbackMode(rawValue: raw) ?? fallback
    }

    /// For a launch argument: "sofort", "amEnde" or "amende".
    static func parse(_ raw: String) -> KasusFeedbackMode? {
        allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }
    }
}

// MARK: - Words and sentences

/// Which word of a target phrase a word is.
nonisolated enum KasusWordPart: String, Hashable {
    case determiner, adjective, noun
    /// A lone case-visible pronoun target (mich, mir, dich, dir, ihn, ihm): one word.
    case pronoun
}

/// Why a word never counts in Markieren, marked or not. Stable raw values; `KasusMarking.note`
/// says each one in a short line.
nonisolated enum KasusUngradedReason: String, CaseIterable, Hashable {
    /// A contraction phrase and its noun („zum Geburtstag“, „im Garten“, „Zum Glück“).
    case contraction
    /// A pronoun other than the six that show their case, or one of the six in a story that
    /// doesn't mark pronouns (or lists it as a notTarget).
    case pronoun
    /// A capitalised word inside a sentence with no article (a name or a noun on its own), what
    /// leads into it (a quantifier, an adjective: „viele Leute“, „mit großer Freude“), and any
    /// number word („zwanzig Kisten“, „um sechs“), which never declines. Only phrases with an
    /// article are counted, so these are left out, even where an ending does show the case.
    case noArticle
    /// A capitalised word opening a sentence (or a quote) with no article that isn't a known
    /// function word: probably a name or a bare noun, so it's left out rather than judged.
    case sentenceStart
    /// A fixed phrase the story lists as an idiom („Kein Problem“).
    case idiom
    /// *am* + a word in -sten, the superlative („am liebsten“, „am besten“): a fixed form, not
    /// *an* + *dem*.
    case superlative
    /// An article word with no noun after it: a demonstrative or relative („Das ist …“), or a
    /// pronoun use („meiner“).
    case standalone
    /// A target the validator couldn't grade, or an article phrase that isn't a target.
    case unchecked
}

/// What a word is for marking.
nonisolated enum KasusTokenRole: Hashable {
    /// A word of gradable target `index` (`KasusLocatedTarget.index`). Right when the round asks
    /// `kasus`, wrong when it asks another case.
    case target(index: Int, kasus: GrammarCase, part: KasusWordPart)
    /// Never counted. `target` is the target it belongs to, when there is one (a contraction
    /// target, an ungradable target), so "Alle Fälle zeigen" can still color it.
    case ungraded(KasusUngradedReason, target: Int?)
    /// An ordinary word: wrong when marked.
    case plain

    /// The target this word belongs to, gradable or not.
    var targetIndex: Int? {
        switch self {
        case .target(let index, _, _):   index
        case .ungraded(_, let target):   target
        case .plain:                     nil
        }
    }

    /// The case of a gradable target's word.
    var kasus: GrammarCase? {
        if case .target(_, let kasus, _) = self { return kasus }
        return nil
    }

    var part: KasusWordPart? {
        if case .target(_, _, let part) = self { return part }
        return nil
    }

    var ungradedReason: KasusUngradedReason? {
        if case .ungraded(let reason, _) = self { return reason }
        return nil
    }

    /// Right or wrong can be decided for it: a target word or a plain word.
    var isGraded: Bool { ungradedReason == nil }
}

/// One word of a numbered sentence. Every word is tappable; punctuation never is on its own, it
/// rides along in `leading` and `trailing`.
nonisolated struct KasusWord: Identifiable, Hashable {
    /// Running index across the whole story, in reading order: what a round's marks hold.
    let id: Int
    let sentenceNumber: Int
    let paragraphIndex: Int
    /// The word alone („Hast“, „E-Mail“).
    let text: String
    /// UTF-16 range in the sentence's `text`.
    let range: NSRange
    /// UTF-16 range in `story.paragraphs[paragraphIndex].de`, the convention target ranges use.
    let paragraphRange: NSRange
    /// Punctuation glued on in front („ in „Hast“) and behind (, . ! ?“ and a free-standing dash
    /// after a space, " –"). `leading + text + trailing`, one space apart, rebuilds the sentence.
    let leading: String
    let trailing: String
    let role: KasusTokenRole

    /// The word with its punctuation, for a word-chip layout.
    var display: String { leading + text + trailing }
}

/// One numbered sentence: what both story exercises show, one per line.
nonisolated struct KasusSentence: Identifiable, Hashable {
    /// From 1, straight across paragraphs.
    let number: Int
    let paragraphIndex: Int
    /// UTF-16 range in the paragraph, without the whitespace around it.
    let range: NSRange
    let text: String
    let words: [KasusWord]

    var id: Int { number }
}

/// A story as numbered sentences, every word classified. Built once per session
/// (`KasusPlayableStory.numbered`).
nonisolated struct KasusNumberedStory: Hashable {
    let sentences: [KasusSentence]
    /// The story marks the six case-visible pronouns (mich, mir, dich, dir, ihn, ihm).
    let countsPronouns: Bool

    var words: [KasusWord] { sentences.flatMap(\.words) }

    func word(_ id: Int) -> KasusWord? {
        for sentence in sentences {
            guard let first = sentence.words.first, let last = sentence.words.last,
                  first.id <= id, id <= last.id else { continue }
            return sentence.words.first { $0.id == id }
        }
        return nil
    }

    func sentence(_ number: Int) -> KasusSentence? {
        sentences.indices.contains(number - 1) ? sentences[number - 1] : nil
    }

    /// The words of one target, in order: a gap's stem and noun, a phrase to outline.
    func words(ofTarget index: Int) -> [KasusWord] {
        words.filter { $0.role.targetIndex == index }
    }

    /// The sentence a target sits in.
    func sentenceNumber(ofTarget index: Int) -> Int? {
        words.first { $0.role.targetIndex == index }?.sentenceNumber
    }

    /// Every word that counts when a round asks `kasus`.
    func caseWords(_ kasus: GrammarCase) -> [KasusWord] {
        words.filter { $0.role.kasus == kasus }
    }

    // MARK: Building

    /// Cuts the story into sentences with the validator's own splitter and words
    /// (`KasusScanner`), so every target range lands on whole words, then classifies each word.
    /// `targets` are the validator's located targets; `lexicon` says which words are
    /// prepositions (a capitalised preposition opening a sentence is an ordinary word).
    @MainActor
    static func build(story: KasusStory, targets: [KasusLocatedTarget],
                      lexicon: some KasusLexicon) -> KasusNumberedStory {
        let countsPronouns = targets.contains { $0.kind == .pronoun }
        // A capitalised word at a sentence start that the story also writes in lowercase is no noun.
        var lowercase = Set<String>()
        for paragraph in story.paragraphs {
            for token in KasusScanner.words(in: paragraph.de) where token.text.first?.isLowercase == true {
                lowercase.insert(token.text)
            }
        }

        var sentences: [KasusSentence] = []
        var nextID = 0
        for (p, paragraph) in story.paragraphs.enumerated() {
            let text = paragraph.de
            let tokens = KasusScanner.words(in: text)
            let ranges = KasusScanner.sentences(in: text).compactMap { trimmed($0, in: text) }
            let starts = Set(ranges.compactMap { range in tokens.firstIndex { range.contains($0.range.lowerBound) } })
            let roles = classify(tokens, in: text, story: story,
                                 targets: targets.filter { $0.paragraphIndex == p },
                                 sentenceStarts: starts, countsPronouns: countsPronouns,
                                 lowercase: lowercase, lexicon: lexicon)
            for range in ranges {
                let inside = tokens.indices.filter { range.contains(tokens[$0].range.lowerBound) }
                guard !inside.isEmpty else { continue }
                let number = sentences.count + 1
                let sentenceStart = NSRange(range, in: text).location
                var leading = Array(repeating: "", count: inside.count)
                var trailing = Array(repeating: "", count: inside.count)
                for (k, i) in inside.enumerated() {
                    let gapStart = k == 0 ? range.lowerBound : tokens[inside[k - 1]].range.upperBound
                    let gap = String(text[gapStart..<tokens[i].range.lowerBound])
                    if k == 0 {
                        leading[k] = gap
                        continue
                    }
                    let (after, before) = splitGap(gap)
                    trailing[k - 1] += after
                    leading[k] = before
                }
                if let last = inside.last, tokens[last].range.upperBound < range.upperBound {
                    trailing[inside.count - 1] += String(text[tokens[last].range.upperBound..<range.upperBound])
                }
                let words = inside.enumerated().map { k, i -> KasusWord in
                    let paragraphRange = NSRange(tokens[i].range, in: text)
                    defer { nextID += 1 }
                    return KasusWord(id: nextID, sentenceNumber: number, paragraphIndex: p,
                                     text: tokens[i].text,
                                     range: NSRange(location: paragraphRange.location - sentenceStart,
                                                    length: paragraphRange.length),
                                     paragraphRange: paragraphRange,
                                     leading: leading[k], trailing: trailing[k], role: roles[i])
                }
                sentences.append(KasusSentence(number: number, paragraphIndex: p, range: NSRange(range, in: text),
                                               text: String(text[range]), words: words))
            }
        }
        return KasusNumberedStory(sentences: sentences, countsPronouns: countsPronouns)
    }

    /// A sentence range without the whitespace around it; nil when nothing is left.
    private static func trimmed(_ range: Range<String.Index>, in text: String) -> Range<String.Index>? {
        var lower = range.lowerBound, upper = range.upperBound
        while lower < upper, text[lower].isWhitespace { lower = text.index(after: lower) }
        while upper > lower, text[text.index(before: upper)].isWhitespace { upper = text.index(before: upper) }
        return lower < upper ? lower..<upper : nil
    }

    /// The text between two words: what sticks to the word before (up to the first space), what
    /// sticks to the word after (from the last space), and a free-standing mark in between („ –“),
    /// which goes with the word before. No space at all: it all sticks to the word before.
    private static func splitGap(_ gap: String) -> (after: String, before: String) {
        guard let first = gap.firstIndex(where: \.isWhitespace),
              let last = gap.lastIndex(where: \.isWhitespace) else { return (gap, "") }
        var after = String(gap[..<first])
        let middle = gap[first...last].trimmingCharacters(in: .whitespaces)
        if !middle.isEmpty { after += " " + middle }
        return (after, String(gap[gap.index(after: last)...]))
    }

    // MARK: Classifying

    /// One role per token of a paragraph. In order: the targets' words, the notTargets' words,
    /// then word by word (contraction, pronoun, article word, capitalised word, plain).
    @MainActor
    private static func classify(_ tokens: [KasusScanner.Token], in text: String, story: KasusStory,
                                 targets: [KasusLocatedTarget], sentenceStarts: Set<Int>,
                                 countsPronouns: Bool, lowercase: Set<String>,
                                 lexicon: some KasusLexicon) -> [KasusTokenRole] {
        var roles = [KasusTokenRole?](repeating: nil, count: tokens.count)
        let ranges = tokens.map { NSRange($0.range, in: text) }

        // 1. Target words. Contractions never count; a target the validator couldn't grade
        //    doesn't either.
        for target in targets {
            let inside = ranges.indices.filter {
                ranges[$0].location >= target.range.location && NSMaxRange(ranges[$0]) <= NSMaxRange(target.range)
            }
            for i in inside {
                if target.kind == .contraction {
                    roles[i] = .ungraded(.contraction, target: target.index)
                } else if !target.gradable {
                    roles[i] = .ungraded(.unchecked, target: target.index)
                } else if target.kind == .pronoun {
                    roles[i] = .target(index: target.index, kasus: target.kasus, part: .pronoun)
                } else {
                    let part: KasusWordPart = ranges[i].location == target.determinerRange.location ? .determiner
                        : ranges[i] == target.nounRange ? .noun : .adjective
                    roles[i] = .target(index: target.index, kasus: target.kasus, part: part)
                }
            }
        }

        // 2. notTargets, wherever the phrase appears (the validator's coverage exemptions).
        for notTarget in story.notTargets {
            for occurrence in KasusScanner.occurrences(of: notTarget.phrase, in: text) {
                let inside = tokens.indices.filter {
                    roles[$0] == nil && tokens[$0].range.lowerBound >= occurrence.lowerBound
                        && tokens[$0].range.upperBound <= occurrence.upperBound
                }
                guard let head = inside.first else { continue }
                let reason: KasusUngradedReason = switch notTarget.why {
                case .pronoun:                    .pronoun
                case .relative, .demonstrative:   .standalone
                case .contraction:                .contraction
                case .idiom:
                    // „Am liebsten“ is the superlative; „Zum Glück“ really is zu + dem.
                    superlative(after: head, tokens, in: text) != nil ? .superlative
                        : KasusForms.contraction(tokens[head].text) != nil ? .contraction : .idiom
                }
                for i in inside { roles[i] = .ungraded(reason, target: nil) }
            }
        }

        // 3. Everything else, word by word.
        for i in tokens.indices where roles[i] == nil {
            let word = tokens[i].text
            let lower = word.lowercased()
            if KasusForms.contraction(lower) != nil {
                if let end = superlative(after: i, tokens, in: text) {
                    for j in i...end where roles[j] == nil { roles[j] = .ungraded(.superlative, target: nil) }
                    continue
                }
                // An untargeted contraction and the words up to its noun.
                let end = nounAfter(i, tokens, in: text) ?? i
                for j in i...end where roles[j] == nil { roles[j] = .ungraded(.contraction, target: nil) }
                continue
            }
            if KasusForms.parseDeterminer(lower) != nil, !KasusForms.copulaForms.contains(lower) {
                // An article word that isn't a target: a phrase nobody checked, or a word standing
                // alone („Das ist …“, a relative „die“, „ihr“ as a pronoun).
                if let end = nounAfter(i, tokens, in: text) {
                    for j in i...end where roles[j] == nil { roles[j] = .ungraded(.unchecked, target: nil) }
                } else {
                    roles[i] = .ungraded(isPronoun(lower) ? .pronoun : .standalone, target: nil)
                }
                continue
            }
            if isPronoun(lower) {
                roles[i] = .ungraded(.pronoun, target: nil)
                continue
            }
            if isNumber(lower) {
                // Numbers never decline („um sechs“, „zwanzig Kisten“): nothing to mark either way.
                roles[i] = .ungraded(.noArticle, target: nil)
                continue
            }
            if word.first?.isUppercase == true {
                if isClauseStart(i, tokens, in: text, sentenceStarts: sentenceStarts) {
                    let known = lowercase.contains(lower) || isFunctionWord(lower, lexicon: lexicon)
                    roles[i] = known ? .plain : .ungraded(.sentenceStart, target: nil)
                } else {
                    roles[i] = .ungraded(.noArticle, target: nil)
                    // What leads into it goes with it: a quantifier („viele Leute“), or an
                    // adjective whose ending shows the case („mit großer Freude“), which a learner
                    // is right to mark and mustn't lose a point for.
                    var j = i - 1
                    while j >= 0, i - j <= 3, roles[j] == .plain, isWhitespaceGap(tokens[j], tokens[j + 1], in: text),
                          quantifiers.contains(tokens[j].text.lowercased())
                            || isAdjectiveBeforeBareNoun(j, tokens, in: text, sentenceStarts: sentenceStarts, lexicon: lexicon) {
                        roles[j] = .ungraded(.noArticle, target: nil)
                        j -= 1
                    }
                }
                continue
            }
            roles[i] = .plain
        }
        return roles.map { $0 ?? .plain }
    }

    /// The noun an article word or contraction opens: the next capitalised word, past up to three
    /// adjectives that fit the article, intensifiers, numbers and quantifiers („ein paar
    /// Entwürfe“). The validator's coverage rule, plus the numbers. Nil when no noun follows.
    private static func nounAfter(_ index: Int, _ tokens: [KasusScanner.Token], in text: String) -> Int? {
        let bare = KasusForms.parseDeterminer(tokens[index].text).map { $0.family != .definite && $0.ending.isEmpty } ?? false
        let endings = bare ? ["er", "es"] : ["e", "en"]
        var j = index + 1
        var skipped = 0
        while j < tokens.count, isWhitespaceGap(tokens[j - 1], tokens[j], in: text) {
            let word = tokens[j].text
            if word.first?.isUppercase == true { return j }
            let lower = word.lowercased()
            let adjective = word.count > 3 && endings.contains { lower.hasSuffix($0) }
                && KasusForms.parseDeterminer(lower) == nil && KasusForms.contraction(lower) == nil
            guard skipped < 3, adjective || intensifiers.contains(lower) || isNumberOrQuantifier(lower) else { return nil }
            skipped += 1
            j += 1
        }
        return nil
    }

    private static func isWhitespaceGap(_ a: KasusScanner.Token, _ b: KasusScanner.Token, in text: String) -> Bool {
        a.range.upperBound <= b.range.lowerBound && text[a.range.upperBound..<b.range.lowerBound].allSatisfy(\.isWhitespace)
    }

    /// The first word of a sentence, or of a quote, a bracket or what follows a colon: a place
    /// where any word is capitalised.
    private static func isClauseStart(_ index: Int, _ tokens: [KasusScanner.Token], in text: String,
                                      sentenceStarts: Set<Int>) -> Bool {
        if index == 0 || sentenceStarts.contains(index) { return true }
        let gap = text[tokens[index - 1].range.upperBound..<tokens[index].range.lowerBound]
        return gap.contains { "„«»\"(:".contains($0) }
    }

    private static func isPronoun(_ lower: String) -> Bool {
        KasusForms.pronoun(lower) != nil || otherPronouns.contains(lower)
    }

    /// A word that is never a noun: in the lists below, a preposition, or a verb form the forms
    /// engine knows.
    @MainActor
    private static func isFunctionWord(_ lower: String, lexicon: some KasusLexicon) -> Bool {
        functionWords.contains(lower) || lexicon.prepositionCases(lower) != nil
            || KasusForms.copulaForms.contains(lower) || KasusForms.motionVerbForms.contains(lower)
            || KasusForms.wechselVerbForms[lower] != nil || KasusForms.dativeVerbLemma(for: lower) != nil
    }

    private static func isNumberOrQuantifier(_ lower: String) -> Bool {
        isNumber(lower) || quantifiers.contains(lower)
    }

    /// A number word („sechs“, „zwanzig“) or digits. Never „ein“, which declines.
    static func isNumber(_ lower: String) -> Bool {
        numberWords.contains(lower) || (!lower.isEmpty && lower.allSatisfy(\.isNumber))
    }

    /// „am liebsten“, „am besten“: *am* before a word in -sten is the superlative, a fixed form,
    /// not *an* + *dem*. Returns the -sten word's index. The common superlative adverbs always
    /// are („am liebsten Kaffee“); any other -sten word only when no noun follows, since „am
    /// nächsten Morgen“ and „am ersten Tag“ are an + dem.
    private static func superlative(after index: Int, _ tokens: [KasusScanner.Token], in text: String) -> Int? {
        let next = index + 1
        guard tokens[index].text.lowercased() == "am", next < tokens.count,
              isWhitespaceGap(tokens[index], tokens[next], in: text),
              tokens[next].text.first?.isLowercase == true else { return nil }
        let word = tokens[next].text.lowercased()
        guard word.hasSuffix("sten") else { return nil }
        if superlativeAdverbs.contains(word) { return next }
        if next + 1 < tokens.count, isWhitespaceGap(tokens[next], tokens[next + 1], in: text),
           tokens[next + 1].text.first?.isUppercase == true { return nil }
        return next
    }

    /// A lowercase word right before a noun with no article, whose ending can show the case
    /// („mit großer Freude“, „bei gutem Wetter“, „nächsten Montag“). -em, -er and -es are
    /// adjective endings. -e and -en are verb endings too („Wir trinken Kaffee“), so those count
    /// as an adjective only when the word before couldn't be the verb's subject or a fronted
    /// adverb: not a pronoun, a noun or name, or an adverb opening the clause („Dort spielen
    /// Kinder“). A time word („nächsten“, „letzten“) always does.
    @MainActor
    private static func isAdjectiveBeforeBareNoun(_ j: Int, _ tokens: [KasusScanner.Token], in text: String,
                                                  sentenceStarts: Set<Int>, lexicon: some KasusLexicon) -> Bool {
        let word = tokens[j].text
        let lower = word.lowercased()
        guard word.first?.isLowercase == true, lower.count > 3, !isFunctionWord(lower, lexicon: lexicon),
              !isPronoun(lower), KasusForms.parseDeterminer(lower) == nil,
              KasusForms.contraction(lower) == nil else { return false }
        if ["em", "er", "es"].contains(where: lower.hasSuffix) { return true }
        guard lower.hasSuffix("e") || lower.hasSuffix("en") else { return false }
        if timeAdjectives.contains(lower) { return true }
        guard j > 0, isWhitespaceGap(tokens[j - 1], tokens[j], in: text) else { return false }
        let before = tokens[j - 1].text
        let beforeLower = before.lowercased()
        if before.first?.isUppercase == true || isPronoun(beforeLower) { return false }
        if isClauseStart(j - 1, tokens, in: text, sentenceStarts: sentenceStarts),
           isFunctionWord(beforeLower, lexicon: lexicon) { return false }
        return true
    }

    /// Pronouns other than the six that show their case.
    static let otherPronouns: Set<String> = [
        "ich", "du", "er", "sie", "es", "wir", "ihr", "uns", "euch", "ihnen", "man", "sich", "einander",
        "jemand", "jemanden", "jemandem", "niemand", "niemanden", "niemandem", "nichts", "etwas", "alles",
    ]

    private static let intensifiers: Set<String> = ["sehr", "ganz", "besonders", "ziemlich", "wirklich"]

    private static let numberWords: Set<String> = [
        "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf",
        "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn", "zwanzig",
        "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig", "hundert", "tausend",
    ]

    private static let quantifiers: Set<String> = [
        "viele", "vielen", "wenige", "wenigen", "einige", "einigen", "mehrere", "mehreren", "alle", "allen",
        "beide", "beiden", "paar", "manche", "manchen", "andere", "anderen", "verschiedene", "verschiedenen",
    ]

    /// Time words in -e/-en that open a bare time phrase („nächsten Montag“, „letzte Woche“).
    private static let timeAdjectives: Set<String> = [
        "nächste", "nächsten", "letzte", "letzten", "vergangene", "vergangenen", "kommende", "kommenden",
    ]

    /// The superlative adverbs after *am* („am liebsten“), whatever follows them.
    private static let superlativeAdverbs: Set<String> = [
        "liebsten", "besten", "meisten", "wenigsten", "ehesten", "häufigsten", "schnellsten",
    ]

    /// Words that open sentences and are never nouns: adverbs, conjunctions, question words,
    /// answers, and the verbs that open a question („Hast du …?“). Not exhaustive: a word it
    /// misses is left out of the round (`sentenceStart`), never judged.
    private static let functionWords: Set<String> = [
        "da", "dort", "hier", "dann", "danach", "dabei", "damals", "davor", "daher", "darum", "deshalb",
        "deswegen", "trotzdem", "außerdem", "sonst", "also", "so", "jetzt", "nun", "heute", "gestern",
        "morgen", "bald", "gleich", "sofort", "schon", "noch", "erst", "zuerst", "zuletzt", "endlich",
        "plötzlich", "leider", "hoffentlich", "vielleicht", "natürlich", "wirklich", "zusammen", "allein",
        "links", "rechts", "vorne", "vorn", "hinten", "oben", "unten", "draußen", "drinnen", "überall",
        "lange", "später", "früher", "immer", "nie", "niemals", "oft", "manchmal", "selten", "wieder",
        "abends", "morgens", "mittags", "nachts", "gern", "gerne", "lieber", "sehr", "ganz", "nur", "auch",
        "fast", "kaum", "genau", "eigentlich", "einfach", "schnell", "langsam", "ja", "nein", "doch",
        "nicht", "bitte", "danke", "hallo", "oh", "ach", "na", "okay",
        "und", "oder", "aber", "denn", "sondern", "als", "wenn", "weil", "dass", "ob", "obwohl", "bevor",
        "nachdem", "damit", "sobald", "seitdem", "während", "bis", "wie", "indem", "zudem",
        "wer", "was", "wann", "wo", "wohin", "woher", "warum", "wieso", "weshalb", "wozu",
        "habe", "hast", "hat", "haben", "habt", "hatte", "hattest", "hatten", "hätte", "hättest", "hätten",
        "kann", "kannst", "können", "könnt", "konnte", "konnten", "könnte", "könntest", "könnten",
        "muss", "musst", "müssen", "müsst", "musste", "mussten", "will", "willst", "wollen", "wollt",
        "wollte", "wollten", "darf", "darfst", "dürfen", "durfte", "soll", "sollst", "sollen", "sollte",
        "sollten", "mag", "magst", "mögen", "möchte", "möchtest", "möchten", "weiß", "weißt", "wissen",
    ]
}

// MARK: - The round

/// What one word shows, once it's judged.
nonisolated enum KasusMarkVerdict: Hashable {
    /// A word of the asked case, marked: ✓ with a wash in the case color.
    case right
    /// Marked, but a plain word or a word of another case: a grey ✗, struck through.
    case wrong
    /// A word of the asked case left unmarked: a dashed outline in the case color.
    case missed
    /// A missed word after Lösung zeigen: shown as the answer.
    case shown
    /// Marked, but a word that never counts. Neither right nor wrong; its note says why.
    case notCounted(KasusUngradedReason)

    /// Counts against the score (`wrong`) or toward it (`right`).
    var isScored: Bool { self == .right || self == .wrong }
}

/// A marking round's score, the class sheet's way: right minus wrong, never below zero, out of
/// the words there were to find. „6 / 10“ for 8 right and 2 wrong of 10.
nonisolated struct KasusMarkScore: Hashable {
    /// The words of the asked case in the story.
    let caseWords: Int
    let right: Int
    let wrong: Int

    var missed: Int { max(0, caseWords - right) }
    var points: Int { max(0, right - wrong) }
    var fraction: Double { caseWords == 0 ? 0 : Double(points) / Double(caseWords) }

    /// „6 / 10“
    var scoreLabel: String { "\(points) / \(caseWords)" }
    /// „8 richtig · 2 falsch · 2 übersehen“
    var countsLabel: String { "\(right) richtig · \(wrong) falsch · \(missed) übersehen" }
}

/// One Markieren round: one case, the learner's marks, and where the round is (marking, checked,
/// answers shown). Value type, so a view can hold it in `@State` and call its mutating methods.
///
/// Am Ende: taps toggle marks, `check()` (Prüfen) judges them all, `showAnswers()` (Lösung
/// zeigen) reveals the missed words, `reset()` (Noch mal) starts over. Sofort: every tap is
/// judged and locked at once, `check()` (Fertig) shows what was missed.
nonisolated struct KasusMarkRound: Identifiable, Hashable {
    /// Kept through Noch mal, so Lösung zeigen after the first Prüfen finds the recorded round
    /// (`KasusService.markAnswersShown(roundID:in:)`).
    let id: UUID
    /// The case this round asks.
    let kasus: GrammarCase
    let mode: KasusFeedbackMode
    let text: KasusNumberedStory

    /// Word ids the learner has marked.
    private(set) var marked: Set<Int> = []
    /// Prüfen (Am Ende) or Fertig (Sofort) has been tapped: every verdict shows.
    private(set) var isChecked = false
    /// Lösung zeigen has been tapped: the missed words show as answers.
    private(set) var answersShown = false
    /// 1 until the first Noch mal. Only the first attempt is recorded.
    private(set) var attempt = 1

    init(kasus: GrammarCase, text: KasusNumberedStory, mode: KasusFeedbackMode, id: UUID = UUID()) {
        self.id = id
        self.kasus = kasus
        self.text = text
        self.mode = mode
    }

    /// The words this round asks for.
    var caseWordIDs: Set<Int> { Set(text.caseWords(kasus).map(\.id)) }

    /// A tap on a word.
    ///   - Am Ende, before Prüfen: toggles the mark; nothing is judged, so nil.
    ///   - Sofort, a word not tapped yet: judged and locked. `.right` or `.wrong` (the word stays
    ///     marked, and the mark can't be taken back), or `.notCounted` (it stays unmarked; show
    ///     its note).
    ///   - Sofort, a word already marked, or any tap after Prüfen/Fertig: nothing changes, nil.
    ///     The view shows that word's explanation instead.
    @discardableResult
    mutating func tap(_ id: Int) -> KasusMarkVerdict? {
        guard !isChecked, let word = text.word(id) else { return nil }
        switch mode {
        case .amEnde:
            if marked.contains(id) { marked.remove(id) } else { marked.insert(id) }
            return nil
        case .sofort:
            guard !marked.contains(id) else { return nil }
            if let reason = word.role.ungradedReason { return .notCounted(reason) }
            marked.insert(id)
            return judge(word, marked: true)
        }
    }

    /// Prüfen (Am Ende) or Fertig (Sofort): every verdict shows, missed words included. Record the
    /// round here on the first attempt.
    mutating func check() {
        isChecked = true
    }

    /// Lösung zeigen: every missed word shows as the answer. Flag the recorded round too.
    mutating func showAnswers() {
        guard isChecked else { return }
        answersShown = true
    }

    /// Noch mal: clears the marks and starts the next attempt, which isn't recorded.
    mutating func reset() {
        marked = []
        isChecked = false
        answersShown = false
        attempt += 1
    }

    /// What a word shows now. Nil when it shows nothing: before Prüfen in Am Ende, a word not
    /// tapped yet in Sofort, and any word that is neither marked nor one to find.
    func verdict(for id: Int) -> KasusMarkVerdict? {
        guard let word = text.word(id) else { return nil }
        let isMarked = marked.contains(id)
        if isChecked { return judge(word, marked: isMarked) }
        if mode == .sofort, isMarked { return judge(word, marked: true) }
        return nil
    }

    /// The score over the current marks. Final once `isChecked`.
    var score: KasusMarkScore {
        var right = 0, wrong = 0
        for id in marked {
            switch judge(text.word(id), marked: true) {
            case .right?: right += 1
            case .wrong?: wrong += 1
            default:      break
            }
        }
        return KasusMarkScore(caseWords: caseWordIDs.count, right: right, wrong: wrong)
    }

    private func judge(_ word: KasusWord?, marked: Bool) -> KasusMarkVerdict? {
        guard let word else { return nil }
        switch word.role {
        case .target(_, let kasus, _) where kasus == self.kasus:
            return marked ? .right : answersShown ? .shown : .missed
        case .target, .plain:
            return marked ? .wrong : nil
        case .ungraded(let reason, _):
            return marked ? .notCounted(reason) : nil
        }
    }
}

// MARK: - Cases, instruction, notes

nonisolated enum KasusMarking {

    /// The cases Markieren asks in this story, in the unit's order (`KasusUnit.markCases`),
    /// skipping any case the story has no words of. The first is the round to start with; each
    /// next one is „Nächster Fall · Next case“.
    @MainActor
    static func cases(for unit: KasusUnit, in text: KasusNumberedStory) -> [GrammarCase] {
        unit.markCases.filter { !text.caseWords($0).isEmpty }
    }

    /// The instruction, in the `KasusRich` markup: „Markiere alle Wörter im {dat:Dativ}.“ and
    /// "Tap every word in the Dativ: the article, any adjective and the noun." A story that marks
    /// pronouns names the case's three in the English line („(also mir, dir and ihm)“). The
    /// Nominativ says its subject pronouns aren't counted, since those are the words a learner
    /// reaches for first.
    static func instruction(for kasus: GrammarCase, countsPronouns: Bool) -> (german: String, english: String) {
        let name = KasusExplanation.caseName(kasus)
        let pronouns = ["mich", "dich", "ihn", "mir", "dir", "ihm"].filter { KasusForms.pronoun($0)?.kasus == kasus }
        let also = countsPronouns && !pronouns.isEmpty ? " (also \(list(pronouns.map { "*\($0)*" })))" : ""
        let subjects = kasus == .nominativ ? " Pronouns like *er* and *sie* aren't counted." : ""
        return ("„Markiere alle Wörter im \(name).“",
                "Tap every word in the \(name): the article, any adjective and the noun\(also).\(subjects)")
    }

    /// What a tap on a word says after Prüfen, in the `KasusRich` markup: a target word's
    /// explanation (led by the case it really is when the round asked another), why an ungraded
    /// word doesn't count, or why a plain word isn't part of a phrase in `asked`.
    static func note(for word: KasusWord, asked: GrammarCase, in text: KasusNumberedStory,
                     targets: [KasusLocatedTarget], story: KasusStory) -> String {
        let target = word.role.targetIndex.flatMap { index in targets.first { $0.index == index } }
        switch word.role {
        case .target(_, let kasus, _):
            guard let target else { return "" }
            let explanation = KasusExplanation.explanation(for: target, in: story)
            guard kasus != asked else { return explanation }
            return "„\(target.surface)“ is \(KasusExplanation.caseName(kasus)) here, not \(KasusExplanation.caseName(asked)). " + explanation
        case .plain:
            let only = "Only the article, any adjective and the noun are marked."
            if let decides = targets.first(where: { $0.paragraphIndex == word.paragraphIndex && $0.triggerRange == word.paragraphRange }) {
                return "*\(word.text)* decides the case of „\(decides.surface)“ (\(KasusExplanation.caseName(decides.kasus))), but it isn't part of it. " + only
            }
            return "„\(word.text)“ isn't part of a phrase in the \(KasusExplanation.caseName(asked)). " + only
        case .ungraded(let reason, _):
            if reason == .noArticle || reason == .sentenceStart, let name = genitiveName(word, in: text) {
                return "*\(word.text)* = \(name)'s: a name with *-s* is in the {gen:Genitiv}, but names aren't counted here."
            }
            return ungradedNote(reason, word: word, target: target, countsPronouns: text.countsPronouns)
        }
    }

    /// „Saras Vorstellungsgespräch“: a name with a Genitiv -s in front of a noun. Returns the name
    /// („Sara“) when the word ends in -s, a capitalised word follows it in the sentence, and the
    /// story also has the name without the -s.
    private static func genitiveName(_ word: KasusWord, in text: KasusNumberedStory) -> String? {
        guard word.text.count > 2, word.text.hasSuffix("s"), word.text.first?.isUppercase == true,
              word.trailing.isEmpty, let sentence = text.sentence(word.sentenceNumber),
              let next = sentence.words.first(where: { $0.id == word.id + 1 }),
              next.leading.isEmpty, next.text.first?.isUppercase == true else { return nil }
        let name = String(word.text.dropLast())
        return text.words.contains { $0.text == name } ? name : nil
    }

    /// Why a word never counts, one short line each.
    static func ungradedNote(_ reason: KasusUngradedReason, word: KasusWord, target: KasusLocatedTarget?,
                             countsPronouns: Bool) -> String {
        switch reason {
        case .contraction:
            let head = target?.determiner ?? word.text
            guard let parts = KasusForms.contraction(head) else {
                return "Part of a phrase with a contraction (*im*, *zum* …): not counted here."
            }
            let article = target.map { KasusExplanation.form(parts.article, $0.genus) } ?? "**\(parts.article)**"
            let spelled = "*\(head.lowercased())* = *\(parts.preposition)* + \(article)"
            if let target, word.text != target.determiner {
                return "Part of „\(target.surface)“ (\(spelled)): contractions aren't counted here."
            }
            return KasusForms.contraction(word.text) != nil
                ? "\(spelled): contractions aren't counted here."
                : "Part of a phrase with a contraction (\(spelled)): not counted here."
        case .pronoun:
            if KasusForms.pronoun(word.text) != nil {
                return countsPronouns ? "This „\(word.text)“ isn't counted in this story." : "Pronouns aren't counted in this story."
            }
            return countsPronouns
                ? "Only *mich, mir, dich, dir, ihn* and *ihm* are counted in this exercise."
                : "Pronouns aren't counted in this story."
        case .noArticle:
            if KasusNumberedStory.isNumber(word.text.lowercased()) {
                return "Numbers don't change with the case: not counted here."
            }
            return "No article in front: names and phrases without one aren't counted in this exercise."
        case .sentenceStart:
            return "No article in front: not counted in this exercise."
        case .idiom:
            return "A fixed phrase: not counted here."
        case .superlative:
            return "*am* + *-sten* is the superlative, a fixed form: not counted here."
        case .standalone:
            return "„\(word.text)“ stands alone here, without a noun: not counted."
        case .unchecked:
            return "This phrase isn't checked in this story, so it isn't counted."
        }
    }

    /// "a, b and c".
    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}
