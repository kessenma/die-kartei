//
//  DiktatScorer.swift
//  german-ai-flashcards
//
//  Grades a dictation word by word (docs/HOEREN.md ▸ Diktat). The point, from FSI lesson 8, is
//  that in an inflected language meaning sits at the ends of words, so a miss is split into
//  "ending only" (the stem was heard) and "word". Rules:
//
//  - Punctuation is shown, never scored. Extra words are shown, not counted against the score
//    ("write down everything you do understand", DLI-STRAT 1c).
//  - A missed noun capital counts as heard: capitals are spelling, not hearing. It is listed apart.
//    The first word's case is ignored entirely.
//  - Ä is not A and ß is not ss (the GameLetters rule): an umlaut or ß miss counts wrong, because
//    schon and schön are heard differently.
//

import Foundation

nonisolated enum DiktatClass: String, Codable, Hashable, Sendable, CaseIterable {
    case right
    /// Right word, wrong capital. Counts as right.
    case capital
    /// Right word apart from ä/ö/ü/ß. Counts wrong.
    case umlautEszett
    /// Right stem, wrong ending. Counts wrong.
    case ending
    /// A different word, or a missing one.
    case word
    /// A word the learner wrote that the sentence does not have. Not in the score.
    case extra

    var countsRight: Bool { self == .right || self == .capital }

    /// Worse classes win when two apply.
    var severity: Int {
        switch self {
        case .right: 0
        case .capital: 1
        case .umlautEszett: 2
        case .ending: 3
        case .word, .extra: 4
        }
    }
}

nonisolated struct DiktatToken: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    /// The sentence's word, without its punctuation. Nil for an extra word.
    var reference: String?
    /// What the learner wrote for it. Nil for a missing word.
    var typed: String?
    /// Punctuation after the reference word, for display ("Mann" + ".").
    var trailing: String = ""
    /// Punctuation before it („).
    var leading: String = ""
    var cls: DiktatClass
    /// The grammar point an ending miss belongs to, when one can be named.
    var focusRaw: String? = nil

    var focus: GrammarFocus? { focusRaw.flatMap(GrammarFocus.init(rawValue:)) }
}

nonisolated struct DiktatResult: Codable, Hashable, Sendable {
    var tokens: [DiktatToken]

    var referenceCount: Int { tokens.filter { $0.reference != nil }.count }
    var rightCount: Int { tokens.filter { $0.reference != nil && $0.cls.countsRight }.count }
    var score: Double { referenceCount == 0 ? 0 : Double(rightCount) / Double(referenceCount) }
    var isPerfect: Bool { referenceCount > 0 && rightCount == referenceCount }

    func count(_ cls: DiktatClass) -> Int { tokens.filter { $0.cls == cls }.count }

    /// The misses whose stem was heard, with the grammar point when known.
    var endingMisses: [DiktatToken] { tokens.filter { $0.cls == .ending } }
    var wordMisses: [DiktatToken] { tokens.filter { $0.cls == .word && $0.reference != nil } }
}

nonisolated enum DiktatScorer {

    /// Characters stripped off either end of a word and shown, not scored.
    static let punctuation: Set<Character> = Set("„“”\"‚‘’'.,;:!?()[]–—-«»…")

    struct Word: Hashable {
        let core: String
        let leading: String
        let trailing: String
    }

    static func words(_ text: String) -> [Word] {
        text.split(whereSeparator: { $0.isWhitespace }).compactMap { raw in
            var chars = Array(raw)
            var lead = "", trail = ""
            while let f = chars.first, punctuation.contains(f) { lead.append(f); chars.removeFirst() }
            while let l = chars.last, punctuation.contains(l) { trail.insert(l, at: trail.startIndex); chars.removeLast() }
            let core = String(chars)
            // A bare dash or quote between words is punctuation, not a word.
            guard !core.isEmpty else { return nil }
            return Word(core: core, leading: lead, trailing: trail)
        }
    }

    /// Lowercase with ä/ö/ü/ß folded: the key two words align on, so a missed capital or umlaut
    /// still lines up with its word.
    static func foldKey(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            switch ch {
            case "ä": out += "a"
            case "ö": out += "o"
            case "ü": out += "u"
            case "ß": out += "ss"
            default: out.append(ch)
            }
        }
        return out
    }

    /// Folded further for "is this only an umlaut/ß slip": ae/oe/ue and a single s also count.
    private static func umlautKey(_ s: String) -> String {
        foldKey(s).replacingOccurrences(of: "ae", with: "a")
            .replacingOccurrences(of: "oe", with: "o")
            .replacingOccurrences(of: "ue", with: "u")
            .replacingOccurrences(of: "ss", with: "s")
    }

    /// Scores `typed` against `reference`. `focusByWord` maps a lowercased reference word to the
    /// grammar point it carries in this sentence (a Kasus target's case, a Perfekt participle);
    /// other ending misses are tagged from their position when that is safe.
    static func score(reference: String, typed: String, focusByWord: [String: GrammarFocus] = [:]) -> DiktatResult {
        let ref = words(reference)
        let got = words(typed)
        let steps = WritingDiff.alignment(ref.map(\.core), got.map(\.core), key: foldKey)

        var tokens: [DiktatToken] = []
        var pendingRemoved: [Int] = [], pendingInserted: [Int] = []

        func flush() {
            // Removed and inserted words between two matches are substitutions, paired in order.
            let pairs = min(pendingRemoved.count, pendingInserted.count)
            for k in 0..<pairs { tokens.append(token(refIndex: pendingRemoved[k], typedIndex: pendingInserted[k])) }
            for r in pendingRemoved.dropFirst(pairs) { tokens.append(token(refIndex: r, typedIndex: nil)) }
            for t in pendingInserted.dropFirst(pairs) { tokens.append(token(refIndex: nil, typedIndex: t)) }
            pendingRemoved.removeAll(); pendingInserted.removeAll()
        }

        func token(refIndex: Int?, typedIndex: Int?) -> DiktatToken {
            let r = refIndex.map { ref[$0] }
            let t = typedIndex.map { got[$0].core }
            var tok = DiktatToken(id: tokens.count, reference: r?.core, typed: t,
                                  trailing: r?.trailing ?? "", leading: r?.leading ?? "", cls: .word)
            guard let r, let refIndex else { tok.cls = .extra; return tok }
            guard let t else { tok.cls = .word; return tok }
            tok.cls = classify(reference: r.core, typed: t, isFirst: refIndex == 0)
            if tok.cls == .ending {
                tok.focusRaw = focus(at: refIndex, in: ref, focusByWord: focusByWord)?.rawValue
            }
            return tok
        }

        for step in steps {
            switch step {
            case .same(let i, let j):
                flush()
                tokens.append(token(refIndex: i, typedIndex: j))
            case .removed(let i):
                pendingRemoved.append(i)
            case .inserted(let j):
                pendingInserted.append(j)
            }
        }
        flush()
        return DiktatResult(tokens: tokens)
    }

    static func classify(reference r: String, typed t: String, isFirst: Bool) -> DiktatClass {
        if r == t { return .right }
        if r.lowercased() == t.lowercased() { return isFirst ? .right : .capital }
        if umlautKey(r) == umlautKey(t) { return .umlautEszett }
        if isEndingOnly(foldKey(r), foldKey(t)) { return .ending }
        return .word
    }

    // MARK: - Endings

    /// Determiner stems and the endings each takes; the tail after the stem must be one of them.
    private static let determinerStems: [(stem: String, tails: Set<String>)] = [
        ("d", ["er", "ie", "as", "en", "em", "es"]),
        ("kein", ["", "e", "en", "em", "er", "es"]),
        ("ein", ["", "e", "en", "em", "er", "es"]),
        ("mein", ["", "e", "en", "em", "er", "es"]), ("dein", ["", "e", "en", "em", "er", "es"]),
        ("sein", ["", "e", "en", "em", "er", "es"]), ("ihr", ["", "e", "en", "em", "er", "es"]),
        ("unser", ["", "e", "en", "em", "er", "es"]), ("eur", ["e", "en", "em", "er", "es"]),
        ("euer", [""]), ("dies", ["e", "en", "em", "er", "es"]), ("jed", ["e", "en", "em", "er", "es"]),
        ("welch", ["e", "en", "em", "er", "es"]), ("jen", ["e", "en", "em", "er", "es"]),
        ("manch", ["e", "en", "em", "er", "es"]), ("all", ["e", "en", "em", "er", "es"]),
    ]

    /// Pronouns whose case forms differ by their ending.
    private static let pronounSets: [Set<String>] = [
        ["ihn", "ihm"], ["mich", "mir"], ["dich", "dir"], ["er", "ihn", "ihm"], ["sie", "ihr", "ihnen"],
    ]

    private static let endingTails: Set<String> = ["", "e", "en", "em", "er", "es", "n", "s", "st", "t",
                                                   "et", "te", "ten", "est", "ern", "ens"]

    static func determinerStem(_ word: String) -> String? {
        let w = foldKey(word)
        // Longest stem first, so "kein" is not read as "k" + "ein".
        for entry in determinerStems.sorted(by: { $0.stem.count > $1.stem.count }) where w.hasPrefix(entry.stem) {
            let tail = String(w.dropFirst(entry.stem.count))
            if entry.tails.contains(tail) { return entry.stem }
        }
        return nil
    }

    static func isDeterminer(_ word: String) -> Bool { determinerStem(word) != nil }

    /// Same stem, different ending. Both inputs already folded.
    static func isEndingOnly(_ a: String, _ b: String) -> Bool {
        guard a != b else { return false }
        if let sa = determinerStem(a), let sb = determinerStem(b), sa == sb { return true }
        if pronounSets.contains(where: { $0.contains(a) && $0.contains(b) }) { return true }
        let shared = zip(a, b).prefix { $0 == $1 }.count
        guard shared >= 3 else { return false }
        let ta = String(a.dropFirst(shared)), tb = String(b.dropFirst(shared))
        return endingTails.contains(ta) && endingTails.contains(tb)
    }

    /// The grammar point of an ending miss at `index`: what the sentence says the word carries,
    /// else a determiner (Artikel), else an adjective between a determiner and a capitalised noun
    /// (Adjektivendungen). Nil when nothing can be named safely.
    static func focus(at index: Int, in ref: [Word], focusByWord: [String: GrammarFocus]) -> GrammarFocus? {
        let word = ref[index].core
        if let tagged = focusByWord[word.lowercased()] { return tagged }
        if isDeterminer(word) { return .artikel }
        if index > 0, index + 1 < ref.count, isDeterminer(ref[index - 1].core),
           let next = ref[index + 1].core.first, next.isUppercase,
           let own = word.first, own.isLowercase {
            return .adjektivendungen
        }
        return nil
    }
}
