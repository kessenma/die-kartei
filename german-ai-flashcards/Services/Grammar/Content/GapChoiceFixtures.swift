//
//  GapChoiceFixtures.swift
//  german-ai-flashcards
//
//  The golden numbers for the bundled gap-choice items, per topic and focus, the planted-error
//  fixtures (one per `gap.*` code, each with exactly one thing wrong), and the verifier
//  `-kasus.debugVerify 1` prints after the Verstehen items (`GapChoiceTests` runs the same). A
//  change to an item or to the rules that moves a number shows up here; a rule that stops
//  catching its planted error shows up here too.
//

#if DEBUG
import Foundation

nonisolated enum GapChoiceFixtures {

    /// What a topic's items of one focus must come out as.
    struct Golden: Hashable {
        let items: Int
        let akk: Int
        let dat: Int
        let inline: Int
    }

    /// Keyed `"<topic>/<focus>"`.
    static let golden: [String: Golden] = [
        "reflexiv/case":   Golden(items: 121, akk: 59, dat: 62, inline: 30),
        "reflexiv/person": Golden(items: 108, akk: 55, dat: 53, inline: 27),
    ]

    // MARK: Planted errors

    /// A good item every planted error starts from.
    static let good = GapChoiceItem(
        id: "rx-h-case-waschen-1sg-haende", topic: "reflexiv", focus: .case, level: "A2",
        sentence: "Ich wasche {1} die Hände.", english: "I wash my hands.",
        gaps: [GapChoiceGap(answer: "mir", options: ["mich", "mir", "dich", "dir"], kasus: .dativ)],
        subject: GapSubject(person: 1, number: .sg, text: "Ich"),
        verb: GapVerb(lemma: "waschen", form: "wasche", takes: .both),
        secondObject: GapObject(text: "die Hände", lemma: "Hand", genus: .die, number: .pl)
    )

    /// One planted error per rejecting code: the name, the item, and the code it must trip.
    struct Planted {
        let name: String
        let item: GapChoiceItem
        let code: GapChoiceCheckCode
    }

    private static func variant(_ edit: (inout GapChoiceItem) -> Void) -> GapChoiceItem {
        var item = good
        edit(&item)
        return item
    }

    private static func rebuilt(id: String = good.id, topic: String = good.topic, focus: GapChoiceFocus = good.focus,
                                level: String = good.level, presentation: GapPresentation = good.presentation,
                                sentence: String = good.sentence, english: String = good.english,
                                gaps: [GapChoiceGap] = good.gaps, subject: GapSubject = good.subject,
                                verb: GapVerb = good.verb, secondObject: GapObject?? = nil, tail: String? = nil) -> GapChoiceItem {
        GapChoiceItem(id: id, topic: topic, focus: focus, level: level, presentation: presentation, sentence: sentence,
                      english: english, gaps: gaps, subject: subject, verb: verb,
                      secondObject: secondObject == nil ? good.secondObject : secondObject!, tail: tail)
    }

    static let planted: [Planted] = [
        Planted(name: "a bare blank instead of a placeholder", item: rebuilt(sentence: "Ich wasche ___ die Hände."), code: .shape),
        Planted(name: "the answer isn't among the options",
                item: rebuilt(gaps: [GapChoiceGap(answer: "mir", options: ["mich", "dich", "dir"], kasus: .dativ)]), code: .options),
        Planted(name: "an id without the rx- prefix", item: rebuilt(id: "kc-case-waschen"), code: .id),
        Planted(name: "an unknown topic", item: rebuilt(topic: "konjunktiv"), code: .topic),
        Planted(name: "an unknown level", item: rebuilt(level: "Z9"), code: .level),
        Planted(name: "a subject the sentence doesn't start with", item: rebuilt(subject: GapSubject(person: 2, number: .sg, text: "Du")), code: .subject),
        Planted(name: "a verb that isn't in the table", item: rebuilt(verb: GapVerb(lemma: "schminken", form: "schminke", takes: .both)), code: .verbUnknown),
        Planted(name: "the wrong verb form for the subject",
                item: rebuilt(sentence: "Ich wäscht {1} die Hände.", verb: GapVerb(lemma: "waschen", form: "wäscht", takes: .both)), code: .verbForm),
        Planted(name: "a separable prefix not at the end",
                item: rebuilt(sentence: "Ich ziehe an {1} die Jacke.", english: "I put on my jacket.",
                              verb: GapVerb(lemma: "anziehen", form: "ziehe", takes: .both, prefix: "an"),
                              secondObject: .some(GapObject(text: "die Jacke", lemma: "Jacke", genus: .die, number: .sg))), code: .prefix),
        Planted(name: "the pronoun of another person as the answer",
                item: rebuilt(gaps: [GapChoiceGap(answer: "dir", options: ["mich", "mir", "dich", "dir"], kasus: .dativ)]), code: .answer),
        Planted(name: "mich with a second object („Ich wasche mich die Hände“)",
                item: rebuilt(sentence: "Ich wasche {1} die Hände.", gaps: [GapChoiceGap(answer: "mich", options: ["mich", "mir", "dich", "dir"], kasus: .akkusativ)]),
                code: .caseRule),
        Planted(name: "a Dativ-only verb without its object („Ich merke mir.“)",
                item: rebuilt(sentence: "Ich merke {1}.", english: "I note.", verb: GapVerb(lemma: "merken", form: "merke", takes: .dat),
                              secondObject: .some(nil)), code: .caseRule),
        Planted(name: "a second object that isn't written after the gap",
                item: rebuilt(secondObject: .some(GapObject(text: "die Füße", lemma: "Fuß", genus: .der, number: .pl))), code: .object),
        Planted(name: "a Dativ article on the second object („Ich wasche mir den Händen“)",
                item: rebuilt(sentence: "Ich wasche {1} den Händen.", secondObject: .some(GapObject(text: "den Händen", lemma: "Hand", genus: .die, number: .pl))),
                code: .objectCase),
        Planted(name: "the wrong gender on the second object",
                item: rebuilt(sentence: "Ich wasche {1} das Gesicht.", english: "I wash my face.",
                              secondObject: .some(GapObject(text: "das Gesicht", lemma: "Gesicht", genus: .der, number: .sg))), code: .objectGender),
        Planted(name: "an article phrase beyond the object („mit der Seife“, no tail declared)",
                item: rebuilt(sentence: "Ich wasche {1} die Hände mit der Seife.", english: "I wash my hands with the soap."), code: .extraPhrase),
        Planted(name: "another pronoun that shows a case",
                item: rebuilt(sentence: "Ich wasche {1} ihm die Hände.", english: "I wash his hands."), code: .extraPronoun),
        Planted(name: "a second clause",
                item: rebuilt(sentence: "Ich wasche {1} die Hände, weil sie schmutzig sind.", english: "I wash my hands because they are dirty."), code: .notSimple),
        Planted(name: "no English", item: rebuilt(english: ""), code: .english),
    ]

    // MARK: Verify

    /// Gates every bundled item, pack by pack, against the golden numbers, checks the pack's
    /// composition, then runs every planted error. The text's lines read like
    /// "gaps reflexiv/case OK · 8 items · Akk 3 · Dat 5 · inline 2 · golden ✓".
    @MainActor
    static func verify(bank: GapChoiceBank, lexicon: some KasusLexicon) -> KasusFixtures.VerifyResult {
        var lines: [String] = []
        var failures: [String] = []

        let packs = Dictionary(grouping: bank.items) { "\($0.topic)/\($0.focus.rawValue)" }
        for key in packs.keys.sorted() {
            let items = packs[key] ?? []
            var problems: [String] = []
            var warnings: [String] = []
            for item in items {
                let result = GapChoiceCheck.run(item, lexicon: lexicon)
                problems += result.errors.map { "\(item.id): \($0)" }
                warnings += result.warnings.map { "\(item.id): \($0)" }
            }
            let akk = items.filter { $0.kasus == .akkusativ }.count
            let dat = items.filter { $0.kasus == .dativ }.count
            let inline = items.filter { $0.presentation == .inline }.count
            var parts = ["gaps \(key) \(problems.isEmpty ? "OK" : "FAIL")", "\(items.count) items", "Akk \(akk)", "Dat \(dat)", "inline \(inline)"]
            var misses: [String] = []
            if let golden = golden[key] {
                if items.count != golden.items { misses.append("items \(items.count) ≠ \(golden.items)") }
                if akk != golden.akk { misses.append("Akk \(akk) ≠ \(golden.akk)") }
                if dat != golden.dat { misses.append("Dat \(dat) ≠ \(golden.dat)") }
                if inline != golden.inline { misses.append("inline \(inline) ≠ \(golden.inline)") }
            } else {
                misses.append("none: add \(key) to GapChoiceFixtures.golden")
            }
            parts.append(misses.isEmpty ? "golden ✓" : "golden ✗ " + misses.joined(separator: ", "))
            lines.append(parts.joined(separator: " · "))
            lines += problems.map { "  " + $0 }
            lines += warnings.map { "  warning " + $0 }
            failures += problems
            failures += misses.map { "\(key) golden: \($0)" }
        }
        let composition = GapChoiceCheck.composition(bank.items)
        lines.append(composition.isEmpty ? "composition OK" : "composition FAIL")
        lines += composition.map { "  \($0.code.rawValue) \($0.detail)" }
        failures += composition.map { "composition: \($0.code.rawValue) \($0.detail)" }
        for topic in Set(bank.items.map(\.topic)).sorted() {
            lines.append("  offered \(topic): " + bank.offered(topic: topic).map(\.rawValue).joined(separator: " · "))
        }

        // The good item passes, and every planted error trips exactly its code.
        let base = GapChoiceCheck.run(good, lexicon: lexicon)
        if !base.passes {
            lines.append("  FAIL the good fixture: " + base.errors.joined(separator: " | "))
            failures.append("the good fixture fails")
        }
        for planted in planted {
            let result = GapChoiceCheck.run(planted.item, lexicon: lexicon)
            let tripped = result.codes.contains(planted.code)
            lines.append("  \(tripped ? "PASS" : "FAIL") \(planted.name) → \(planted.code.rawValue)"
                         + (tripped ? "" : " (got \(result.codes.map(\.rawValue)))"))
            if !tripped { failures.append("planted \(planted.name) didn't trip \(planted.code.rawValue)") }
        }

        lines.append(failures.isEmpty ? "Gaps ALL OK" : "Gaps \(failures.count) FAILED")
        return KasusFixtures.VerifyResult(text: lines.joined(separator: "\n"), failures: failures)
    }
}
#endif
