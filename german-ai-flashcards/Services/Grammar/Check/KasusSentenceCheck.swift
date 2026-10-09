//
//  KasusSentenceCheck.swift
//  german-ai-flashcards
//
//  Cheap checks on a tutor's sentences (Phase 3). The validator proves the form of every phrase it
//  grades, not the sentence around it, so a generated story could pass with „Ich ist nach Hause
//  gegangen“ or „auf einen stand“ in it. These catch the kinds of broken German the Mac probe
//  found in stories that passed, and each one rejects the whole story:
//
//    verbAgreement   ich + ist/sind/hat …, er + bin/sind/hast …, and ich or er + an -en verb form
//                    when nothing in the sentence explains an infinitive or participle there (a
//                    modal, werden, haben/sein, zu, or a verb like gehen or lassen)
//    unknownWord     a lowercase word, or the noun of an article phrase, that neither the
//                    dictionary nor the closed word classes know. A compound counts when a part
//                    at its end is known; a capitalised word that also stands bare elsewhere in
//                    the story is taken for a name („die kleine Mia … Mia lacht“).
//    lowercaseNoun   an ein-article in front of a lowercase word the dictionary knows as a noun
//                    and nothing else („kam ich auf einen stand“)
//    repeatedSentence the same sentence three times or more: a tutor caught in a loop
//
//  The validator adds one more per target: a singular Nominativ phrase right before an -en form
//  nothing explains („Der Bruder lachen laut.“), with `unlicensedInfinitive(after:in:lexicon:)`.
//
//  All three need a dictionary (`KasusLexicon.partsOfSpeech`); a lexicon without one skips them.
//  Only generated stories are checked (`KasusValidator.validate`). They are deliberately narrow:
//  a false alarm costs a good story, so anything a correct sentence could also produce is left
//  alone, and the Lab's „reads right / wrong“ tap stays the check on the rest.
//

import Foundation

/// One broken sentence in a tutor's story.
nonisolated struct KasusSentenceProblem: Hashable {
    let code: KasusIssueCode
    /// For the developer, in English, quoting the words.
    let message: String
}

enum KasusSentenceCheck {

    static func problems(in paragraphs: [KasusScannedParagraph], lexicon: some KasusLexicon) -> [KasusSentenceProblem] {
        // No dictionary, no checks: every one of them leans on it.
        guard lexicon.partsOfSpeech("haus") != nil else { return [] }
        var found: [KasusSentenceProblem] = []
        let bareWords = bareCapitalised(in: paragraphs)
        for (p, paragraph) in paragraphs.enumerated() {
            for sentence in paragraph.sentences {
                let indices = paragraph.tokens.indices.filter { sentence.contains(paragraph.tokens[$0].range.lowerBound) }
                found += agreement(indices, in: paragraph, paragraphIndex: p, lexicon: lexicon)
                found += unknownWords(indices, in: paragraph, paragraphIndex: p, bareWords: bareWords, lexicon: lexicon)
                found += lowercaseNouns(indices, in: paragraph, paragraphIndex: p, lexicon: lexicon)
            }
        }
        return found + repeats(in: paragraphs)
    }

    // MARK: - Verb agreement

    /// Finite forms that never go with ich.
    static let notWithIch: Set<String> = ["ist", "sind", "bist", "seid", "hat", "habt", "wird"]
    /// Finite forms that never go with er („er habe“ is reported speech, so it's allowed).
    static let notWithEr: Set<String> = ["bin", "bist", "sind", "seid", "hast", "habt"]
    /// A pronoun right after one of these may share its verb with another subject („Tom und ich
    /// gehen“, „größer als ich“).
    static let sharedSubject: Set<String> = ["und", "oder", "sowie", "als", "wie"]

    /// Anything in the sentence that can explain an infinitive or a participle after ich or er:
    /// a modal, werden, haben or sein, zu or um, or a verb that takes a bare infinitive.
    static let infinitiveLicensers: Set<String> = [
        "kann", "kannst", "können", "konnte", "konntest", "konnten", "könnte", "könnten",
        "will", "willst", "wollen", "wollte", "wolltest", "wollten",
        "muss", "musst", "müssen", "musste", "musstest", "mussten", "müsste", "müssten",
        "soll", "sollst", "sollen", "sollte", "solltest", "sollten",
        "darf", "darfst", "dürfen", "durfte", "durftest", "durften", "dürfte",
        "mag", "magst", "mögen", "mochte", "möchte", "möchtest", "möchten",
        "werde", "wirst", "wird", "werden", "wurde", "wurdest", "wurden", "würde", "würdest", "würden",
        "habe", "hast", "hat", "haben", "hatte", "hattest", "hatten", "hätte", "hätten",
        "bin", "bist", "ist", "sind", "war", "warst", "waren", "wäre", "wären",
        "zu", "um",
        "gehe", "gehst", "geht", "gehen", "ging", "gingen",
        "lasse", "lässt", "lassen", "ließ", "ließen",
        "sehe", "siehst", "sieht", "sehen", "sah", "sahen",
        "höre", "hörst", "hört", "hören", "hörte", "hörten",
        "bleibe", "bleibst", "bleibt", "bleiben", "blieb", "blieben",
        "lerne", "lernst", "lernt", "lernen", "lernte", "lernten",
        "helfe", "hilfst", "hilft", "helfen", "half", "halfen",
        "fahre", "fährst", "fährt", "fahren", "fuhr", "fuhren",
        "komme", "kommst", "kommt", "kommen", "kam", "kamen",
    ]

    /// Words that end the stretch an infinitive's helper may stand in: a new clause starts.
    static let clauseOpeners: Set<String> = [
        "bis", "weil", "dass", "wenn", "als", "ob", "obwohl", "während", "nachdem", "bevor", "damit",
        "und", "oder", "aber", "denn", "sondern",
    ]

    /// The -en verb form right after the token at `index` („lachen“ in „Der Bruder lachen laut“),
    /// when nothing explains an infinitive or a participle there: no modal, werden, haben or
    /// sein, zu, or bare-infinitive verb in its clause, from the clause's start to the next comma
    /// or clause opener. Nil otherwise, and for anything that isn't clearly a verb form (an
    /// adjective or adverb too, a ge- participle, an article).
    static func unlicensedInfinitive(after index: Int, in paragraph: KasusScannedParagraph,
                                     lexicon: some KasusLexicon) -> String? {
        let tokens = paragraph.tokens
        guard index + 1 < tokens.count, paragraph.isWhitespaceGap(tokens[index], tokens[index + 1]) else { return nil }
        let next = tokens[index + 1]
        let lower = next.text.lowercased()
        guard next.text.first?.isLowercase == true, lower.hasSuffix("en"), lower.count > 3, !lower.hasPrefix("ge"),
              KasusForms.parseDeterminer(lower) == nil, !closedClass.contains(lower),
              let pos = lexicon.partsOfSpeech(lower), pos.contains("verb"),
              pos.isDisjoint(with: ["adj", "adv"]) else { return nil }
        let sentence = paragraph.sentence(containing: next.range.lowerBound)
        let clause = paragraph.clause(containing: tokens[index].range, in: sentence)
        var scope: [String] = []
        for (i, token) in tokens.enumerated() where clause.contains(token.range.lowerBound) {
            let word = token.text.lowercased()
            if i > index + 1, clauseOpeners.contains(word) { break }
            scope.append(word)
        }
        return Set(scope).isDisjoint(with: infinitiveLicensers) ? next.text : nil
    }

    private static func agreement(_ indices: [Int], in paragraph: KasusScannedParagraph, paragraphIndex: Int,
                                  lexicon: some KasusLexicon) -> [KasusSentenceProblem] {
        let tokens = paragraph.tokens
        var found: [KasusSentenceProblem] = []
        func word(_ offset: Int, from position: Int) -> String? {
            let other = position + offset
            guard indices.indices.contains(other) else { return nil }
            let (a, b) = offset < 0 ? (indices[other], indices[position]) : (indices[position], indices[other])
            return paragraph.isWhitespaceGap(tokens[a], tokens[b]) ? tokens[indices[other]].text : nil
        }
        for position in indices.indices {
            let pronoun = tokens[indices[position]].text.lowercased()
            guard pronoun == "ich" || pronoun == "er" else { continue }
            let before = word(-1, from: position)
            let after = word(1, from: position)
            let wrong = pronoun == "ich" ? notWithIch : notWithEr
            if let after, wrong.contains(after.lowercased()) {
                found.append(.init(code: .verbAgreement, message: "„\(tokens[indices[position]].text) \(after)“ in paragraph \(paragraphIndex + 1): the verb doesn't go with \(pronoun)"))
                continue
            }
            if let before, wrong.contains(before.lowercased()) {
                found.append(.init(code: .verbAgreement, message: "„\(before) \(tokens[indices[position]].text)“ in paragraph \(paragraphIndex + 1): the verb doesn't go with \(pronoun)"))
                continue
            }
            // ich/er + an -en form: „Ich trinken Saft“, „er lachen laut“.
            guard !(before.map { sharedSubject.contains($0.lowercased()) } ?? false),
                  let verb = unlicensedInfinitive(after: indices[position], in: paragraph, lexicon: lexicon) else { continue }
            found.append(.init(code: .verbAgreement, message: "„\(tokens[indices[position]].text) \(verb)“ in paragraph \(paragraphIndex + 1): an -en form after \(pronoun), with no modal or helper verb"))
        }
        return found
    }

    // MARK: - Repeats

    /// The same sentence three times or more: a tutor caught in a loop („Ich musste noch etwas
    /// für das Kind erledigen.“ over and over).
    private static func repeats(in paragraphs: [KasusScannedParagraph]) -> [KasusSentenceProblem] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for paragraph in paragraphs {
            for sentence in paragraph.sentences {
                let words = paragraph.tokens.filter { sentence.contains($0.range.lowerBound) }.map { $0.text.lowercased() }
                guard words.count >= 3 else { continue }
                let key = words.joined(separator: " ")
                if counts[key] == nil { order.append(key) }
                counts[key, default: 0] += 1
            }
        }
        return order.compactMap { key in
            guard let count = counts[key], count >= 3 else { return nil }
            return KasusSentenceProblem(code: .repeatedSentence, message: "„\(key)“ stands \(count) times")
        }
    }

    // MARK: - Unknown words

    /// Words a dictionary of content words doesn't list: pronouns, conjunctions, articles and the
    /// like. Prepositions, determiners and contractions are recognised on their own.
    static let closedClass: Set<String> = [
        "ich", "du", "er", "sie", "es", "wir", "ihr", "mich", "dich", "sich", "uns", "euch", "mir", "dir",
        "ihm", "ihn", "ihnen", "man", "jemand", "jemanden", "jemandem", "niemand", "niemanden", "nichts",
        "etwas", "alles", "alle", "allem", "allen", "aller", "beide", "beiden", "beides", "viele", "vielen",
        "manche", "manchen", "einige", "einigen", "mehrere", "welche", "solche", "selbst", "selber",
        "und", "oder", "aber", "denn", "sondern", "doch", "weil", "dass", "ob", "wenn", "als", "wie",
        "wo", "was", "wer", "wen", "wem", "wessen", "warum", "wann", "woher", "wohin", "womit", "wofür",
        "damit", "dabei", "dafür", "davon", "dazu", "darauf", "darin", "daran", "darüber", "danach",
        "davor", "dahin", "daher", "deshalb", "deswegen", "trotzdem", "obwohl", "bevor", "nachdem",
        "während", "sobald", "seitdem", "falls", "sodass", "zu", "nicht", "kein", "ja", "nein",
        "noch", "schon", "auch", "nur", "so", "sehr", "mal", "eins", "zwei", "drei", "vier", "fünf",
        "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf", "hundert", "tausend",
        "dessen", "deren", "denen", "jene", "jener", "jenes", "jenen", "jenem",
        "derjenige", "diejenige", "dasjenige", "denjenigen", "demjenigen", "desjenigen", "diejenigen",
        "derselbe", "dieselbe", "dasselbe", "denselben", "demselben", "desselben", "dieselben",
        "solch", "solcher", "solches", "solchen", "solchem", "manch", "manchem", "mancher", "manches",
        "irgendein", "irgendeine", "irgendeinen", "irgendeinem", "irgendeiner", "irgendwas", "irgendwo",
        "irgendwie", "irgendwann", "irgendjemand",
    ]

    /// Suffixes that make a noun of a known word, in their plural too.
    static let nounSuffixes = [
        "ereien", "erei", "ungen", "ung", "heiten", "heit", "keiten", "keit", "schaften", "schaft",
        "chen", "lein", "linge", "ling", "nisse", "nis", "tum",
    ]

    /// Prefixes a verb (or a word made from one) can carry that a dictionary doesn't always list
    /// joined: „anstarrte“ in a subordinate clause, „vertust“.
    static let verbPrefixes = [
        "zurück", "zusammen", "weiter", "herum", "heraus", "herein", "hinaus", "hinein", "wieder",
        "durch", "unter", "über", "nach", "fort", "miss", "auf", "aus", "ein", "mit", "vor", "weg", "los",
        "her", "hin", "ver", "zer", "ent", "be", "er", "ge", "an", "ab", "zu", "um",
    ]

    /// Capitalised words that stand somewhere without an article in front: names, most likely.
    private static func bareCapitalised(in paragraphs: [KasusScannedParagraph]) -> Set<String> {
        var bare = Set<String>()
        for paragraph in paragraphs {
            let tokens = paragraph.tokens
            for (i, token) in tokens.enumerated() where token.text.first?.isUppercase == true {
                let opener = i > 0 && paragraph.isWhitespaceGap(tokens[i - 1], token) ? tokens[i - 1].text.lowercased() : nil
                let afterArticle = opener.map { KasusForms.parseDeterminer($0) != nil || KasusForms.contraction($0) != nil } ?? false
                let afterAdjective = opener.map { $0.first?.isLowercase == true && ($0.hasSuffix("e") || $0.hasSuffix("en")) } ?? false
                if !afterArticle && !afterAdjective { bare.insert(token.text) }
            }
        }
        return bare
    }

    /// Known as written, or through a part at its end („Picknickplatz“ → Platz, „herumgerannt“ →
    /// gerannt). `nounTail` asks the part to be a noun.
    private static func isKnown(_ word: String, nounTail: Bool, lexicon: some KasusLexicon) -> Bool {
        let lower = word.lowercased()
        if closedClass.contains(lower) || KasusForms.parseDeterminer(lower) != nil
            || KasusForms.contraction(lower) != nil || KasusForms.pronoun(lower) != nil
            || lexicon.prepositionCases(lower) != nil {
            return true
        }
        if let pos = lexicon.partsOfSpeech(lower), !pos.isEmpty { return true }
        if !nounTail {
            func verb(_ word: String) -> Bool { lexicon.partsOfSpeech(word)?.contains("verb") == true }
            // A present participle used as an adjective: „klingelnde“ → klingeln.
            if let match = lower.range(of: #"nd(e|en|em|er|es)?$"#, options: .regularExpression),
               verb(String(lower[..<match.lowerBound]) + "n") { return true }
            // A weak verb's forms the dictionary leaves out: „weichte“ → weichen.
            for ending in ["test", "ten", "tet", "te", "st", "t"] where lower.hasSuffix(ending) {
                let stem = String(lower.dropLast(ending.count))
                if stem.count >= 3, verb(stem + "en") || verb(stem + "n") { return true }
            }
            // A prefix in front of a known word: „anstarrte“ → starrte, „vertust“ → tust.
            for prefix in verbPrefixes where lower.hasPrefix(prefix) && lower.count - prefix.count >= 3 {
                if isKnown(String(lower.dropFirst(prefix.count)), nounTail: false, lexicon: lexicon) { return true }
            }
        }
        if nounTail {
            // A noun built with a common suffix on a known stem: „Spielerei“ → spiel.
            for suffix in nounSuffixes where lower.hasSuffix(suffix) && lower.count - suffix.count >= 3 {
                if let pos = lexicon.partsOfSpeech(String(lower.dropLast(suffix.count))), !pos.isEmpty { return true }
            }
        }
        let characters = Array(lower)
        let shortest = nounTail ? 3 : 5
        guard characters.count > shortest + 2 else { return false }
        for start in 3...(characters.count - shortest) {
            let tail = String(characters[start...])
            guard let pos = lexicon.partsOfSpeech(tail), !pos.isEmpty else { continue }
            if !nounTail || pos.contains("noun") { return true }
        }
        return false
    }

    private static func unknownWords(_ indices: [Int], in paragraph: KasusScannedParagraph, paragraphIndex: Int,
                                     bareWords: Set<String>, lexicon: some KasusLexicon) -> [KasusSentenceProblem] {
        let tokens = paragraph.tokens
        var found: [KasusSentenceProblem] = []
        func skip(_ text: String) -> Bool {
            text.count < 3 || text.contains(where: { $0.isNumber || $0 == "-" || $0 == "'" || $0 == "’" })
        }
        for i in indices {
            let text = tokens[i].text
            if !skip(text), text.first?.isLowercase == true, !isKnown(text, nounTail: false, lexicon: lexicon) {
                found.append(.init(code: .unknownWord, message: "„\(text)“ in paragraph \(paragraphIndex + 1) isn't a word the dictionary knows"))
            }
            if KasusForms.parseDeterminer(text) != nil || KasusForms.contraction(text) != nil,
               let noun = KasusValidator.nounAfterDeterminer(at: i, in: paragraph) {
                let word = tokens[noun].text
                guard !skip(word), !bareWords.contains(word),
                      !isKnown(word, nounTail: true, lexicon: lexicon) else { continue }
                found.append(.init(code: .unknownWord, message: "„\(text) \(word)“ in paragraph \(paragraphIndex + 1): no dictionary knows the noun"))
            }
        }
        return found
    }

    // MARK: - Lowercase nouns

    /// Lowercase words an ein-word may stand in front of without a noun: „ein paar“, „ein bisschen“.
    static let einWithoutNoun: Set<String> = [
        "paar", "bisschen", "wenig", "weiteres", "weitere", "weiterer", "anderes", "andere", "anderer",
        "anderen", "einziger", "einzige", "einziges", "mal",
    ]

    private static func lowercaseNouns(_ indices: [Int], in paragraph: KasusScannedParagraph, paragraphIndex: Int,
                                       lexicon: some KasusLexicon) -> [KasusSentenceProblem] {
        let tokens = paragraph.tokens
        var found: [KasusSentenceProblem] = []
        for i in indices where i + 1 < tokens.count && indices.contains(i + 1) {
            guard KasusForms.parseDeterminer(tokens[i].text)?.family == .ein,
                  paragraph.isWhitespaceGap(tokens[i], tokens[i + 1]),
                  KasusValidator.nounAfterDeterminer(at: i, in: paragraph) == nil else { continue }
            let next = tokens[i + 1].text
            let lower = next.lowercased()
            guard next.first?.isLowercase == true, !einWithoutNoun.contains(lower), !closedClass.contains(lower),
                  KasusForms.parseDeterminer(lower) == nil, KasusForms.contraction(lower) == nil,
                  lexicon.prepositionCases(lower) == nil,
                  let pos = lexicon.partsOfSpeech(lower), pos.contains("noun"),
                  pos.isDisjoint(with: ["adj", "adv"]) else { continue }
            found.append(.init(code: .lowercaseNoun, message: "„\(tokens[i].text) \(next)“ in paragraph \(paragraphIndex + 1): a noun is written with a capital"))
        }
        return found
    }
}
