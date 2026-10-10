//
//  FehlerQuestion.swift
//  german-ai-flashcards
//
//  Finde den Fehler: one article in a sentence is wrong; the learner taps the word, then picks
//  the fix. The sentences are the unit's Rollen items (`KasusConceptBank`), already validated
//  for play; the injector picks a phrase the sentence itself proves (its form or a preposition,
//  never a phrase only its label decides) and swaps its article for another case's form of the
//  same family, one the noun's gender can't read as right. An item whose reading could flip
//  (object first) is left out, so the planted mistake is the only one.
//
//  No new content: the data comes free with the Verstehen items, and the gate that proved them
//  is the gate that proves the sentence without the mistake.
//

import Foundation

nonisolated struct FehlerQuestion: Identifiable {
    let playable: KasusConceptPlayable
    /// The phrase whose article was swapped.
    let target: KasusLocatedTarget
    /// The planted form, capitalised like the word it replaces.
    let wrong: String
    /// The fix: the article as the item has it.
    let answer: String
    /// The fix buttons: the family's forms for this gender over the cases in play, the planted
    /// form among them.
    let options: [String]
    let casesInPlay: [GrammarCase]

    var id: String { "\(playable.id)#\(target.index)" }
    var kasus: GrammarCase { target.kasus }
    var genus: Gender { target.spec.genus }

    /// The sentence with the mistake in it, for the summary and the round history.
    var corruptedSentence: String {
        let ns = sentence as NSString
        let offset = target.determinerRange.location - sentenceStart
        guard offset >= 0, offset + target.determinerRange.length <= ns.length else { return sentence }
        return ns.replacingCharacters(in: NSRange(location: offset, length: target.determinerRange.length), with: wrong)
    }

    /// The sentence the phrase is in, as written.
    var sentence: String {
        guard playable.story.paragraphs.indices.contains(target.paragraphIndex) else { return target.surface }
        let paragraph = playable.story.paragraphs[target.paragraphIndex].de as NSString
        let range = target.sentenceRange
        guard NSMaxRange(range) <= paragraph.length else { return target.surface }
        return paragraph.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sentenceStart: Int {
        guard playable.story.paragraphs.indices.contains(target.paragraphIndex) else { return 0 }
        let paragraph = playable.story.paragraphs[target.paragraphIndex].de as NSString
        let raw = paragraph.substring(with: target.sentenceRange)
        return target.sentenceRange.location + raw.prefix(while: \.isWhitespace).utf16.count
    }

    /// The planted word, by its place in the paragraph: the chip to tap.
    func isPlanted(_ word: KasusWord) -> Bool {
        word.paragraphIndex == target.paragraphIndex && NSEqualRanges(word.paragraphRange, target.determinerRange)
    }

    /// The tapped word is in the phrase with the mistake (the article or its noun).
    func isInPhrase(_ word: KasusWord) -> Bool {
        word.paragraphIndex == target.paragraphIndex && NSLocationInRange(word.paragraphRange.location, target.range)
    }

    /// The fix's own case miss or gender slip, by the forms engine.
    func isGenderSlip(_ pick: String) -> Bool {
        guard let parsed = target.parsed else { return false }
        return KasusForms.isRightCaseWrongGender(pick: pick, answerCase: kasus, genus: genus,
                                                 family: parsed.family, stem: parsed.stem)
    }

    /// Why the fix is right: the item's own explanation for the phrase.
    var explanation: String {
        "The sentence had „*\(wrong)*“ there. " + KasusExplanation.explanation(for: target, in: playable.story)
    }

    // MARK: Planting

    /// A phrase the sentence proves, whose article has another case's form the gender can't read
    /// as right. Nil when the item offers none (one phrase only, a reading that could flip, every
    /// phrase decided by its label).
    static func plant(in playable: KasusConceptPlayable, casesInPlay: [GrammarCase],
                      rng: inout KasusSeededRandom) -> FehlerQuestion? {
        guard !playable.facts.isOVS else { return nil }
        let articles = playable.targets.filter { $0.gradable && $0.kind == .article && $0.parsed != nil }
        guard articles.count >= 2 else { return nil }
        let candidates = articles.filter { $0.proof == .form || $0.proof == .preposition }
            .compactMap { target -> FehlerQuestion? in
                guard let parsed = target.parsed, casesInPlay.contains(target.kasus) else { return nil }
                let genus = target.spec.genus
                // The family's forms for this gender over the cases in play, in table order.
                var forms: [String] = []
                for kasus in GrammarCase.allCases where casesInPlay.contains(kasus) {
                    if let form = KasusForms.form(family: parsed.family, stem: parsed.stem, case: kasus, genus: genus),
                       !forms.contains(form) { forms.append(form) }
                }
                let answer = target.determiner
                let wrongForms = forms.filter { form in
                    form.lowercased() != answer.lowercased()
                        && !KasusForms.compatibleCases(determiner: form, genus: genus).contains(target.kasus)
                }
                guard forms.count >= 2, !wrongForms.isEmpty else { return nil }
                let wrong = KasusForms.matchingCapitalization(wrongForms[rng.int(below: wrongForms.count)], like: answer)
                let options = forms.map { KasusForms.matchingCapitalization($0, like: answer) }
                return FehlerQuestion(playable: playable, target: target, wrong: wrong, answer: answer,
                                      options: options, casesInPlay: casesInPlay)
            }
        guard !candidates.isEmpty else { return nil }
        return candidates[rng.int(below: candidates.count)]
    }

    /// A round over the unit's Rollen items: `count` questions, each item at most once, the
    /// unit's own case asked most where the items allow.
    static func round(playables: [KasusConceptPlayable], casesInPlay: [GrammarCase], emphasis: GrammarCase?,
                      count: Int, rng: inout KasusSeededRandom) -> [FehlerQuestion] {
        var pool = playables.compactMap { plant(in: $0, casesInPlay: casesInPlay, rng: &rng) }
        pool.shuffle(using: &rng)
        guard !pool.isEmpty else { return [] }
        var out: [FehlerQuestion] = []
        if let emphasis {
            let share = Int((Double(count) / 2).rounded(.up))
            out += pool.filter { $0.kasus == emphasis }.prefix(share)
        }
        let used = Set(out.map(\.id))
        out += pool.filter { !used.contains($0.id) }.prefix(max(0, count - out.count))
        out.shuffle(using: &rng)
        return out
    }
}
