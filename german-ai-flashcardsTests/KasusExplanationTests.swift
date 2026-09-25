//
//  KasusExplanationTests.swift
//  german-ai-flashcardsTests
//
//  Every target of every bundled story explains itself, and every string the case path renders
//  through `Text(kasusRich:)` is well-formed markup: the explanations, the slip notes, the rule
//  lines, the Kasus-Check card and the Schnellrunde's feedback. A few lines are pinned word for
//  word, so a change to the Kasus-Check wording shows up here first.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Kasus explanations and markup")
struct KasusExplanationTests {

    // MARK: Story targets

    @Test("Every target explains itself in clean markup", arguments: BundledStories.ids)
    func storyExplanations(_ id: String) throws {
        let story = try #require(KasusTestData.story(id))
        for target in KasusTestData.report(story).located {
            let label = "#\(target.index + 1) \(target.surface)"
            let explanation = KasusExplanation.explanation(for: target, in: story)
            #expect(!explanation.isEmpty, "\(label)")
            #expect(RichMarkup.problems(explanation).isEmpty, "\(label): \(RichMarkup.problems(explanation)) in \(explanation)")
            #expect(explanation.contains(KasusExplanation.caseName(target.kasus)), "\(label) names its case in the case color")
            #expect(KasusRich.plain(explanation).contains(target.kasus.name), "\(label)")
            #expect(!explanation.contains("—"), "\(label) has an em dash")

            // Finden's note exists exactly for the targets only their role decides.
            let note = KasusExplanation.ambiguityNote(for: target)
            #expect((note != nil) == (target.proof == .label && target.candidates.count > 1), "\(label) ambiguity note")
            if let note {
                #expect(RichMarkup.problems(note).isEmpty, "\(label): \(RichMarkup.problems(note))")
            }
        }
    }

    @Test("Pinned lines from „Der verlorene Schlüssel“")
    func pinnedLines() throws {
        let story = try #require(KasusTestData.story(KasusTestData.schluesselID))
        let located = KasusTestData.report(story).located
        func raw(_ number: Int) -> String { KasusExplanation.explanation(for: located[number - 1], in: story) }
        func plain(_ number: Int) -> String { KasusRich.plain(raw(number)) }

        #expect(raw(11).hasPrefix("*mit* **always** takes the {dat:Dativ}. Masculine {dat:Dativ} in „{m:m}{f:r}{n:m}{pl:n}“ is {m:m}: {m:dem}."))
        #expect(plain(9).hasPrefix("unter + Wohin? (a direction) → Akkusativ."))
        #expect(plain(17).contains("hilft (helfen) is one of the verbs that always take the Dativ."))
        #expect(plain(15).contains("„Das Tier“ is the subject of ist → Nominativ."))
        #expect(raw(6).hasPrefix("By its form, {f:seine} could be {nom:Nominativ} or {akk:Akkusativ}."))
        #expect(plain(6).contains("fragen takes the Akkusativ, even though"))
        #expect(plain(22).contains("the thing liked is the subject"))
    }

    @Test("Pinned lines for contractions, pronouns and der-words")
    func pinnedPhase2Lines() throws {
        func plain(_ id: String, _ number: Int) throws -> String {
            let story = try #require(KasusTestData.story(id))
            let located = KasusTestData.report(story).located
            return KasusRich.plain(KasusExplanation.explanation(for: located[number - 1], in: story))
        }
        #expect(try plain("ks-dat-a2-umzug", 1).hasPrefix("am is short for an dem. an in a time phrase takes the Dativ."))
        #expect(try plain("ks-dat-a2-umzug", 3)
                == "helfen is one of the verbs that always take the Dativ. mir is ich in the Dativ; the Akkusativ is mich.")
        #expect(try plain("ks-dat-a2-umzug", 20).contains("Nachbar is an n-noun, so it adds -n too: Nachbarn."))
        #expect(try plain("ks-gen-b1-grossmutter", 3).contains("Masculine Akkusativ in „nese“ is n: diesen."))
        #expect(try plain("ks-gen-b1-grossmutter", 33)
                .hasPrefix("„jedes Vogels“ hangs on Namen and says whose → Genitiv. Masculine Genitiv in „srsr“ is s: jedes."))
        // es gibt: the thing that is there is the object, not something being given.
        #expect(try plain("ks-akk-a1-picknick", 10)
                .hasPrefix("es gibt always takes the Akkusativ: es is the subject, and „einen Kiosk“, the thing that is there, is the object."))
        // A Genitiv preposition, with the spoken Dativ the rule card mentions.
        #expect(try plain("ks-gen-b1-grossmutter", 26)
                .hasPrefix("während takes the Genitiv (in speech you'll often hear the Dativ)."))
    }

    // MARK: Slip notes

    @Test("The slip notes")
    func slipNotes() {
        // „dem“ is masculine and neuter alike: named both ways, bold rather than one color.
        let gender = KasusExplanation.genderSlipNote(pick: "dem", answer: "der", genus: .die, kasus: .dativ)
        #expect(gender == "Right case, **wrong gender**: **dem** is masculine or neuter {dat:Dativ}. This noun is feminine, so {f:der}.")
        #expect(KasusRich.plain(gender) == "Right case, wrong gender: dem is masculine or neuter Dativ. This noun is feminine, so der.")
        let feminine = KasusExplanation.genderSlipNote(pick: "die", answer: "den", genus: .der, kasus: .akkusativ)
        #expect(feminine.hasPrefix("Right case, **wrong gender**: {f:die} is feminine {akk:Akkusativ}."))

        let number = KasusExplanation.numberSlipNote(pick: "die", answer: "den", kasus: .akkusativ, noun: "Schlüssel")
        #expect(number == "Right case, **wrong number**: {pl:die} is the plural {akk:Akkusativ}. *Schlüssel* looks the same in the plural, but here it's one, so {m:den}.")

        // „dem“ fits masculine and neuter alike, so it stays bold instead of taking a color.
        let dative = KasusExplanation.numberSlipNote(pick: "den", answer: "dem", kasus: .dativ, noun: "Mädchen")
        #expect(dative.hasSuffix("so **dem**."))

        // A plural answer picked in the singular.
        let plural = KasusExplanation.numberSlipNote(pick: "den", answer: "die", kasus: .akkusativ, noun: "Nachbarn",
                                                     answerIsPlural: true)
        #expect(plural == "Right case, **wrong number**: {m:den} is the singular {akk:Akkusativ}. *Nachbarn* looks the same in the singular, but here it's more than one, so {pl:die}.")

        for note in [gender, feminine, number, dative, plural] {
            #expect(RichMarkup.problems(note).isEmpty, "\(note)")
        }
    }

    // MARK: The renderer

    @Test("KasusRich renders tokens bold and strips them for plain text")
    func richRendering() {
        let source = "*mit* **always** takes the {dat:Dativ}. Masculine in **mrmn** is *m*: {m:dem}."
        #expect(KasusRich.plain(source) == "mit always takes the Dativ. Masculine in mrmn is m: dem.")

        let attributed = KasusRich.attributed(source)
        #expect(String(attributed.characters) == KasusRich.plain(source))
        let runs = attributed.runs.map { (text: String(attributed[$0.range].characters), intent: $0.inlinePresentationIntent) }
        #expect(runs.first { $0.text == "dem" }?.intent == .stronglyEmphasized)
        #expect(runs.first { $0.text == "Dativ" }?.intent == .stronglyEmphasized)
        #expect(runs.first { $0.text == "mit" }?.intent == .emphasized)
        #expect(runs.first { $0.text == "always" }?.intent == .stronglyEmphasized)

        // An unknown tag isn't a token: it stays as written, and the checker says so.
        #expect(KasusRich.plain("{xyz:den}") == "{xyz:den}")
        #expect(!RichMarkup.problems("{xyz:den}").isEmpty)
        #expect(!RichMarkup.problems("*{m:den}*").isEmpty, "emphasis may not span a token")
        #expect(!RichMarkup.problems("**always").isEmpty)
    }

    // MARK: Copy in the markup

    @Test("Every unit's rule lines are clean markup", arguments: KasusUnit.allCases)
    func ruleLines(_ unit: KasusUnit) {
        #expect(!unit.ruleLines.isEmpty)
        for line in unit.ruleLines {
            #expect(RichMarkup.problems(line).isEmpty, "\(RichMarkup.problems(line)) in \(line)")
        }
    }

    @Test("The Kasus-Check card is clean markup")
    func kasusCheckSteps() {
        let steps = KasusCheckSheet.steps
        #expect(steps.map(\.id) == Array(1...6), "six steps, in order")
        for step in steps {
            let strings = [step.question, step.short] + step.lines + [step.note].compactMap { $0 }
                + step.answers.compactMap { $0.example }
            for string in strings {
                #expect(RichMarkup.problems(string).isEmpty, "step \(step.id): \(RichMarkup.problems(string)) in \(string)")
            }
        }
    }

    @Test("Every Schnellrunde question explains itself in clean markup", arguments: GrammarCase.allCases)
    func schnellrundeFeedback(_ kasus: GrammarCase) {
        for frame in EndingsFrame.all where frame.kasus == kasus {
            #expect(RichMarkup.problems(frame.why).isEmpty, "\(frame.why)")
            for noun in EndingsNoun.all {
                for isPlural in [false, true] {
                    for determiner in EndingsDeterminer.allCases where !(isPlural && determiner == .ein) {
                        let question = EndingsQuestion(frame: frame, noun: noun, isPlural: isPlural, determiner: determiner,
                                                       options: determiner.options(includesGenitiv: true))
                        let label = "\(question.parts.before)\(question.answer)\(question.parts.after)"
                        #expect(question.options.contains(question.answer), "\(label): the answer is a button")
                        for pick in question.options {
                            let feedback = question.feedback(pick: pick)
                            #expect(RichMarkup.problems(feedback).isEmpty, "\(label), pick \(pick): \(feedback)")
                        }
                    }
                }
            }
        }
    }
}
