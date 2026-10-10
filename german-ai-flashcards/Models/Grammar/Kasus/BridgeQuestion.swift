//
//  BridgeQuestion.swift
//  german-ai-flashcards
//
//  Die Pronomen-Brücke: English keeps its cases in its pronouns (he / him), German in its
//  pronouns (er / ihn / ihm) and then in every article (der / den / dem). One sentence frame,
//  three stages on the same job: the English pronoun, the German pronoun, the article on a
//  noun. Nobody says „I see he“, and that intuition is the bridge to „Ich sehe den Hund“.
//
//  Derived from the Schnellrunde's frames (the ones with an English twin) and nouns, so there
//  is no content to gate: the forms come from the tables, and the tests pin them. Foundation
//  only, `nonisolated`.
//

import Foundation

nonisolated struct BridgeQuestion: Identifiable, Hashable {
    let id = UUID()
    let frame: EndingsFrame
    let noun: EndingsNoun
    let isPlural: Bool
    let casesInPlay: [GrammarCase]

    var kasus: GrammarCase { frame.kasus }
    var gender: Gender { isPlural ? .plural : noun.gender }
    var nounForm: String { noun.form(kasus, isPlural: isPlural) }

    // MARK: The three stages

    /// „I see ___.“
    var englishSentence: String { (isPlural ? frame.englishPlural : frame.englishSingular) ?? "" }
    /// „Ich sehe ___.“
    var pronounSentence: String {
        (isPlural ? frame.plural : frame.singular).replacingOccurrences(of: "___ {N}", with: "___")
    }
    /// „Ich sehe ___ Hund.“
    var articleSentence: String {
        (isPlural ? frame.plural : frame.singular).replacingOccurrences(of: "{N}", with: nounForm)
    }

    var englishAnswer: String { Self.english(gender, kasus) }
    var pronounAnswer: String { Self.pronoun(gender, kasus) }
    var articleAnswer: String { kasus.article(gender) }

    /// he / him: the two English forms, subject first.
    var englishOptions: [String] { [Self.english(gender, .nominativ), Self.english(gender, .akkusativ)] }
    /// er · ihn · ihm: the German pronoun's distinct forms over the cases in play, in table order.
    var pronounOptions: [String] { Self.distinct(casesInPlay.map { Self.pronoun(gender, $0) }) }
    /// der · den · dem: the definite article's distinct forms over the cases in play.
    var articleOptions: [String] { Self.distinct(casesInPlay.map { kasus.article(gender) == "" ? "" : $0.article(gender) }) }

    var sentences: [String] { [englishSentence, pronounSentence, articleSentence] }
    var answers: [String] { [englishAnswer, pronounAnswer, articleAnswer] }
    var options: [[String]] { [englishOptions, pronounOptions, articleOptions] }
    static let stageLabels = ["Englisch · English", "Pronomen · Pronoun", "Artikel · Article"]

    /// The article sentence split around its blank.
    var articleParts: (before: String, after: String) {
        let pieces = articleSentence.components(separatedBy: "___")
        return (pieces.first ?? "", pieces.dropFirst().first ?? "")
    }

    /// Why: the three forms as one chain, the frame's Kasus-Check reason, and the letter that
    /// carries over from English where one does.
    var explanation: String {
        let tag = kasus.short.lowercased()
        var text = "*\(englishAnswer)* → {\(tag):\(pronounAnswer)} → {\(tag):\(articleAnswer)}: the same job, shown on the English pronoun, the German pronoun, then the article. \(frame.why)."
        if gender == .der {
            switch kasus {
            case .akkusativ: text += " The **n** of *ihn* is the **n** of *den*."
            case .dativ:     text += " The **m** of *him* is the **m** of *ihm* and of *dem*."
            default:         break
            }
        }
        return text
    }

    // MARK: Forms

    static func english(_ gender: Gender, _ kasus: GrammarCase) -> String {
        let subject = kasus == .nominativ
        switch gender {
        case .der:    return subject ? "he" : "him"
        case .die:    return subject ? "she" : "her"
        case .das:    return "it"
        case .plural: return subject ? "they" : "them"
        }
    }

    static func pronoun(_ gender: Gender, _ kasus: GrammarCase) -> String {
        switch (gender, kasus) {
        case (.der, .nominativ):    return "er"
        case (.der, .akkusativ):    return "ihn"
        case (.der, .dativ):        return "ihm"
        case (.der, .genitiv):      return "seiner"
        case (.die, .nominativ), (.die, .akkusativ): return "sie"
        case (.die, .dativ):        return "ihr"
        case (.die, .genitiv):      return "ihrer"
        case (.das, .nominativ), (.das, .akkusativ): return "es"
        case (.das, .dativ):        return "ihm"
        case (.das, .genitiv):      return "seiner"
        case (.plural, .nominativ), (.plural, .akkusativ): return "sie"
        case (.plural, .dativ):     return "ihnen"
        case (.plural, .genitiv):   return "ihrer"
        }
    }

    private static func distinct(_ forms: [String]) -> [String] {
        var out: [String] = []
        for form in forms where !form.isEmpty && !out.contains(form) { out.append(form) }
        return out
    }

    // MARK: A round

    /// The frames with an English twin for these cases.
    static func frames(for cases: [GrammarCase]) -> [EndingsFrame] {
        EndingsFrame.all.filter { $0.englishSingular != nil && cases.contains($0.kasus) }
    }

    /// Whether the frames span at least two of `cases`, so a round can't turn single-case.
    static func coversCases(_ cases: [GrammarCase]) -> Bool {
        Set(frames(for: cases).map(\.kasus)).count >= 2
    }

    /// A round over `cases`, the unit's own case most, on masculine, feminine and plural nouns
    /// (the neuter *it* shows no case in English). No noun twice in one case.
    static func round(cases: [GrammarCase], emphasis: GrammarCase?, count: Int, rng: inout KasusSeededRandom) -> [BridgeQuestion] {
        let pool = frames(for: cases)
        let nouns = EndingsNoun.all.filter { $0.gender != .das }
        let inPlay = cases.filter { kasus in pool.contains { $0.kasus == kasus } }
        guard !pool.isEmpty, !inPlay.isEmpty else { return [] }
        let quotas = EndingsQuestion.quota(cases: inPlay, emphasis: emphasis, count: count)
        var seen = Set<String>()
        var out: [BridgeQuestion] = []
        for kasus in GrammarCase.allCases {
            guard let share = quotas[kasus] else { continue }
            let frames = pool.filter { $0.kasus == kasus }
            guard !frames.isEmpty else { continue }
            for _ in 0..<share {
                for _ in 0..<50 {
                    let noun = nouns[rng.int(below: nouns.count)]
                    let isPlural = rng.int(below: 4) == 0
                    let key = "\(kasus)|\(noun.singular)|\(isPlural)"
                    guard seen.insert(key).inserted else { continue }
                    out.append(BridgeQuestion(frame: frames[rng.int(below: frames.count)], noun: noun, isPlural: isPlural,
                                              casesInPlay: cases))
                    break
                }
            }
        }
        out.shuffle(using: &rng)
        return out
    }
}
