//
//  GapChoicePlanner.swift
//  german-ai-flashcards
//
//  Writes the reflexive packs offline, from the tables in ReflexivForms.swift and nothing else:
//  a verb in the form its subject takes, the pronoun the person and case give, a second object
//  from the verb's own pool or a tail from its own list, the English from the verb's pattern.
//  No model writes any of it. The gate (`GapChoiceCheck`) still checks every item, because the
//  tables are written by hand.
//
//  A pack is reproducible from its seed: `kasus-cli gap-plans case --count 120 --seed 7` gives
//  the same items every time, and an item's id names what it is
//  (rx-s-case-waschen-1sg-haende), not when it was made. A bad item is fixed in the table and
//  the pack regenerated, never patched in the output. Foundation only; the CLI compiles it.
//

import Foundation

nonisolated enum GapChoicePlanner {

    static let level = "A2"

    // MARK: Candidates

    /// Every item the tables can make for a focus, in table order, with its options still to be
    /// drawn (`pack` draws them). Ids are stable: one per (verb, subject, object or tail).
    static func candidates(focus: GapChoiceFocus, prefix: String = "s") -> [GapChoiceItem] {
        guard focus == .case || focus == .person else { return [] }
        // Akkusativ oder Dativ? asks only the persons whose pronoun shows a case.
        let subjects = focus == .case ? ReflexivSubject.all.filter { $0.number == .sg && $0.person < 3 } : ReflexivSubject.all
        var out: [GapChoiceItem] = []
        for verb in ReflexivVerb.table {
            for subject in subjects where verb.numbers.contains(subject.number) {
                guard let form = verb.form(person: subject.person, number: subject.number) else { continue }
                if verb.takes != .dat, let pattern = verb.en.akk {
                    let tails: [ReflexivTail?] = verb.tails.isEmpty ? [nil] : verb.tails
                    for tail in tails {
                        out.append(item(focus: focus, prefix: prefix, verb: verb, form: form, subject: subject,
                                        kasus: .akkusativ, object: nil, tail: tail, pattern: pattern))
                    }
                }
                if verb.takes != .akk, let pattern = verb.en.dat {
                    for object in verb.objects {
                        out.append(item(focus: focus, prefix: prefix, verb: verb, form: form, subject: subject,
                                        kasus: .dativ, object: object, tail: nil, pattern: pattern))
                    }
                }
            }
        }
        return out
    }

    private static func item(focus: GapChoiceFocus, prefix: String, verb: ReflexivVerb, form: String,
                             subject: ReflexivSubject, kasus: GrammarCase, object: ReflexivObject?,
                             tail: ReflexivTail?, pattern: String) -> GapChoiceItem {
        let answer = ReflexivPronoun.form(person: subject.person, number: subject.number, kasus: kasus) ?? "sich"
        var words = [subject.text, form, "{1}"]
        if let object { words.append(object.text) }
        if let tail { words.append(tail.de) }
        if let prefix = verb.prefix { words.append(prefix) }
        let sentence = words.joined(separator: " ") + "."
        let slug = object.map { slugify($0.lemma) } ?? tail.map { "t-" + slugify($0.de) } ?? ""
        let id = ["rx", prefix, focus.rawValue, slugify(verb.lemma), "\(subject.person)\(subject.number.rawValue)", slug]
            .filter { !$0.isEmpty }.joined(separator: "-")
        return GapChoiceItem(
            id: id, topic: GrammarTopicKey.reflexiv, focus: focus, level: level, presentation: .buttons,
            sentence: sentence, english: english(pattern, subject: subject, verb: verb, object: object, tail: tail),
            gaps: [GapChoiceGap(answer: answer, options: [answer], kasus: kasus)],
            subject: GapSubject(person: subject.person, number: subject.number, text: subject.text),
            verb: GapVerb(lemma: verb.lemma, form: form, takes: verb.takes, prefix: verb.prefix),
            secondObject: object.map { GapObject(text: $0.text, lemma: $0.lemma, genus: $0.genus, number: $0.number) },
            tail: tail?.de
        )
    }

    /// The English twin from the verb's pattern: `{S}` the subject, `{V}` the verb (`{V:put|puts}`
    /// picks by person), `{B}` am / are / is, `{R}` myself …, `{P}` my …, `{O}` the object; the
    /// tail goes before the full stop.
    static func english(_ pattern: String, subject: ReflexivSubject, verb: ReflexivVerb,
                        object: ReflexivObject?, tail: ReflexivTail?) -> String {
        let third = subject.person == 3 && subject.number == .sg
        var out = pattern
        if let regex = try? NSRegularExpression(pattern: #"\{V:([^|}]+)\|([^}]+)\}"#) {
            let ns = out as NSString
            for match in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
                let pick = ns.substring(with: match.range(at: third ? 2 : 1))
                out = (out as NSString).replacingCharacters(in: match.range, with: pick)
            }
        }
        out = out.replacingOccurrences(of: "{V}", with: third ? verb.en.third : verb.en.base)
        out = out.replacingOccurrences(of: "{B}", with: third ? "is" : subject.person == 1 && subject.number == .sg ? "am" : "are")
        out = out.replacingOccurrences(of: "{S}", with: subject.en)
        out = out.replacingOccurrences(of: "{R}", with: subject.reflexive)
        out = out.replacingOccurrences(of: "{P}", with: subject.possessive)
        out = out.replacingOccurrences(of: "{O}", with: object?.en ?? "")
        if let tail {
            if out.hasSuffix(".") { out.removeLast() }
            out += " " + tail.en + "."
        }
        out = out.replacingOccurrences(of: "  ", with: " ").replacingOccurrences(of: " .", with: ".")
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    /// ASCII for an id: ä → ae, ß → ss, letters and digits only.
    static func slugify(_ text: String) -> String {
        let folded = text.lowercased()
            .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
        return String(folded.map { $0.isLetter || $0.isNumber ? $0 : "-" }).split(separator: "-").joined(separator: "-")
    }

    // MARK: A pack

    /// `count` items for a focus, drawn from the candidates with the pack's composition built in:
    /// every table verb at least twice (once when the pack is small), both cases at least a
    /// third each for Akkusativ oder Dativ?, every person at least an eighth, no two items alike.
    /// About a quarter of the items play as two chips in the sentence. Sentences in `excluding`
    /// (the bundle's, lowercased) are never drawn, so a merge can't duplicate one.
    static func pack(focus: GapChoiceFocus, count: Int, seed: UInt64, excluding: Set<String> = [],
                     prefix: String = "s") -> [GapChoiceItem] {
        var rng = KasusSeededRandom(seed: seed)
        var pool = candidates(focus: focus, prefix: prefix).filter { !excluding.contains($0.filled.lowercased()) }
        pool.shuffle(using: &rng)
        guard count > 0, !pool.isEmpty else { return [] }

        var chosen: [GapChoiceItem] = []
        var used = Set<String>()
        func take(_ item: GapChoiceItem) {
            guard !used.contains(item.id), chosen.count < count else { return }
            chosen.append(item)
            used.insert(item.id)
        }
        func take(where keep: (GapChoiceItem) -> Bool, upTo wanted: Int) {
            var taken = chosen.filter(keep).count
            for item in pool where taken < wanted && !used.contains(item.id) && keep(item) {
                take(item)
                taken += 1
            }
        }

        // 1. Every verb, once or twice; a verb that takes either case gets one of each.
        let perVerb = count >= 2 * ReflexivVerb.table.count ? 2 : 1
        for verb in ReflexivVerb.table {
            if perVerb == 2, verb.takes == .both {
                take(where: { $0.verb.lemma == verb.lemma && $0.kasus == .akkusativ }, upTo: 1)
                take(where: { $0.verb.lemma == verb.lemma }, upTo: 2)
            } else {
                take(where: { $0.verb.lemma == verb.lemma }, upTo: perVerb)
            }
        }
        // 2. Both cases, constructively.
        if focus == .case {
            let need = Int((Double(count) / 3).rounded(.up))
            for kasus in [GrammarCase.akkusativ, .dativ] { take(where: { $0.kasus == kasus }, upTo: need) }
        }
        // 3. Every person.
        let persons = focus == .case ? ["1sg", "2sg"] : ["1sg", "2sg", "3sg", "1pl", "2pl", "3pl"]
        let perPerson = Int((Double(count) / 8).rounded(.up))
        for person in persons { take(where: { "\($0.subject.person)\($0.subject.number.rawValue)" == person }, upTo: perPerson) }
        // 4. The rest, as shuffled.
        for item in pool where chosen.count < count { take(item) }

        chosen.shuffle(using: &rng)
        // 5. Options and presentation.
        return chosen.enumerated().map { index, item in
            var drawn = item
            let inline = index % 4 == 3
            drawn.presentation = inline ? .inline : .buttons
            let gap = item.gaps[0]
            let kasus = gap.kasus ?? .akkusativ
            var options: [String]
            switch (focus, inline) {
            case (.case, false):
                options = ["mich", "mir", "dich", "dir"]
            case (.case, true):
                options = [ReflexivPronoun.form(person: item.subject.person, number: item.subject.number, kasus: .akkusativ) ?? "mich",
                           ReflexivPronoun.form(person: item.subject.person, number: item.subject.number, kasus: .dativ) ?? "mir"]
                options.shuffle(using: &rng)
            default:
                var others = (kasus == .dativ ? ["mir", "dir", "sich", "uns", "euch"] : ["mich", "dich", "sich", "uns", "euch"])
                    .filter { $0 != gap.answer }
                others.shuffle(using: &rng)
                options = [gap.answer] + others.prefix(inline ? 1 : 3)
                options.shuffle(using: &rng)
            }
            drawn = GapChoiceItem(id: item.id, topic: item.topic, focus: item.focus, level: item.level,
                                  presentation: drawn.presentation, sentence: item.sentence, english: item.english,
                                  gaps: [GapChoiceGap(answer: gap.answer, options: options, kasus: kasus)],
                                  subject: item.subject, verb: item.verb, secondObject: item.secondObject, tail: item.tail)
            return drawn
        }
    }
}

/// The topic keys the planner writes. `GrammarTopic` imports SwiftUI and stays out of the CLI, so
/// the key is spelled here too (`GrammarTopic.reflexivKey` is the same string).
nonisolated enum GrammarTopicKey {
    static let reflexiv = "reflexiv"
}
