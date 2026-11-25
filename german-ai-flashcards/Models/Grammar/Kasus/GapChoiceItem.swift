//
//  GapChoiceItem.swift
//  german-ai-flashcards
//
//  One bundled gap-choice item (`Resources/gap_choice_items.json`): a sentence with one or more
//  gaps, each with its options and answer, plus the facts the gate checks it against (the
//  subject, the verb and what it takes, the second object if there is one). The format every
//  pack of this kind shares: the reflexive drills (Akkusativ oder Dativ?, Die richtige Person),
//  later the double gap (verb + pronoun) and the Pronomen-Brücke (three chained gaps).
//
//  Nothing here decides a case: the planner writes the items offline from the tables in
//  ReflexivForms.swift, the gate (`GapChoiceCheck`, compiled into training/kasus_cli) refuses
//  anything the tables and the lexicon can't vouch for, and the explanation is derived at play
//  time (`ReflexivExplanation`), never stored. Foundation only, so the CLI compiles it.
//
//  The sentence carries `{1}`, `{2}` … where the gaps go; `gaps[0]` is `{1}`.
//

import Foundation

/// Which question a pack asks. Each maps to the exercise kind that plays it.
nonisolated enum GapChoiceFocus: String, Codable, CaseIterable, Hashable {
    /// Akkusativ oder Dativ?: the same person's two forms among the options (mich / mir).
    case `case` = "case"
    /// Die richtige Person: one case, the pronoun follows the subject (sich / dich / uns).
    case person
    /// The double gap: the verb form and the pronoun (later).
    case multi
    /// Pronomen-Brücke: him → ihn → den, three chained gaps (later).
    case bridge

    /// The kind that plays this focus; nil while its module isn't built.
    var kind: KasusDrillKind? {
        switch self {
        case .case:   .reflexCase
        case .person: .reflexPerson
        case .multi:  nil
        case .bridge: .bridge
        }
    }

    /// Fewer items than this and the topic doesn't offer the drill.
    static let minimumItems = 6
}

/// How the gap is answered: a grid of buttons under the sentence, or the two forms as chips in
/// the sentence itself (the worksheet's „dich / dir“ in brackets).
nonisolated enum GapPresentation: String, Codable, Hashable {
    case buttons, inline
}

/// What fills a gap.
nonisolated enum GapKind: String, Codable, Hashable {
    case pronoun, verb, determiner, englishPronoun
}

nonisolated enum GrammarNumber: String, Codable, Hashable {
    case sg, pl
}

/// Which case a reflexive verb puts its person in.
nonisolated enum ReflexivTakes: String, Codable, Hashable {
    /// Always the Akkusativ: the person is the only object (sich beeilen).
    case akk
    /// Always the Dativ: a thing is the Akkusativ object, the person the receiver (sich etwas merken).
    case dat
    /// Either, decided by a second object (sich waschen · sich die Hände waschen).
    case both
}

/// One gap: its answer, the options offered, and the case the answer shows.
nonisolated struct GapChoiceGap: Codable, Hashable {
    var kind: GapKind = .pronoun
    let answer: String
    let options: [String]
    /// The case the answer is in; the feedback header's colour and the round history's case.
    var kasus: GrammarCase? = nil

    init(kind: GapKind = .pronoun, answer: String, options: [String], kasus: GrammarCase? = nil) {
        self.kind = kind
        self.answer = answer
        self.options = options
        self.kasus = kasus
    }

    private enum CodingKeys: String, CodingKey { case kind, answer, options, kasus }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(GapKind.self, forKey: .kind) ?? .pronoun
        answer = try c.decode(String.self, forKey: .answer)
        options = try c.decode([String].self, forKey: .options)
        kasus = try c.decodeIfPresent(GrammarCase.self, forKey: .kasus)
    }
}

/// The subject: who the pronoun must agree with.
nonisolated struct GapSubject: Codable, Hashable {
    /// 1, 2 or 3.
    let person: Int
    let number: GrammarNumber
    /// As written at the start of the sentence („Ich“, „Du“, „Wir“).
    let text: String
}

/// The verb, in the form the sentence uses.
nonisolated struct GapVerb: Codable, Hashable {
    /// The infinitive without „sich“ („waschen“, „anziehen“).
    let lemma: String
    /// The finite form in the sentence („wasche“, „ziehe“).
    let form: String
    let takes: ReflexivTakes
    /// A separable prefix, which stands at the end („an“).
    var prefix: String? = nil

    init(lemma: String, form: String, takes: ReflexivTakes, prefix: String? = nil) {
        self.lemma = lemma
        self.form = form
        self.takes = takes
        self.prefix = prefix
    }
}

/// The second object, the thing that pushes the person into the Dativ.
nonisolated struct GapObject: Codable, Hashable {
    /// As written, article to noun („die Hände“).
    let text: String
    let lemma: String
    let genus: Gender
    let number: GrammarNumber
}

nonisolated struct GapChoiceItem: Codable, Hashable, Identifiable {
    let id: String
    /// The topic key it files under (`GrammarTopic.key`): „reflexiv“, or a unit's raw value.
    let topic: String
    let focus: GapChoiceFocus
    /// A CEFR level label („A2“).
    let level: String
    var presentation: GapPresentation = .buttons
    /// The German with `{1}`, `{2}` … where the gaps go.
    let sentence: String
    let english: String
    let gaps: [GapChoiceGap]
    let subject: GapSubject
    let verb: GapVerb
    var secondObject: GapObject? = nil
    /// A fixed phrase after the verb that is part of the sentence but never asked („am
    /// Wochenende“, „auf die Ferien“). The gate takes it as written and reads nothing into it.
    var tail: String? = nil

    init(id: String, topic: String, focus: GapChoiceFocus, level: String, presentation: GapPresentation = .buttons,
         sentence: String, english: String, gaps: [GapChoiceGap], subject: GapSubject, verb: GapVerb,
         secondObject: GapObject? = nil, tail: String? = nil) {
        self.id = id
        self.topic = topic
        self.focus = focus
        self.level = level
        self.presentation = presentation
        self.sentence = sentence
        self.english = english
        self.gaps = gaps
        self.subject = subject
        self.verb = verb
        self.secondObject = secondObject
        self.tail = tail
    }

    private enum CodingKeys: String, CodingKey {
        case id, topic, focus, level, presentation, sentence, english, gaps, subject, verb, secondObject, tail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        topic = try c.decode(String.self, forKey: .topic)
        focus = try c.decode(GapChoiceFocus.self, forKey: .focus)
        level = try c.decode(String.self, forKey: .level)
        presentation = try c.decodeIfPresent(GapPresentation.self, forKey: .presentation) ?? .buttons
        sentence = try c.decode(String.self, forKey: .sentence)
        english = try c.decode(String.self, forKey: .english)
        gaps = try c.decode([GapChoiceGap].self, forKey: .gaps)
        subject = try c.decode(GapSubject.self, forKey: .subject)
        verb = try c.decode(GapVerb.self, forKey: .verb)
        secondObject = try c.decodeIfPresent(GapObject.self, forKey: .secondObject)
        tail = try c.decodeIfPresent(String.self, forKey: .tail)
    }

    // MARK: The sentence

    /// `{n}` placeholders.
    static let placeholder = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)

    /// The placeholder numbers in the sentence, in reading order.
    var placeholderNumbers: [Int] {
        let ns = sentence as NSString
        return Self.placeholder.matches(in: sentence, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
    }

    /// The sentence with every gap replaced by `fill(gapIndex)` (a blank when it returns nil).
    func sentence(filling fill: (Int) -> String?, blank: String = "___") -> String {
        let ns = sentence as NSString
        var out = ""
        var cursor = 0
        for match in Self.placeholder.matches(in: sentence, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let index = (Int(ns.substring(with: match.range(at: 1))) ?? 1) - 1
            out += fill(index) ?? blank
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// The sentence with every answer in place.
    var filled: String {
        sentence { gaps.indices.contains($0) ? gaps[$0].answer : nil }
    }

    /// Where the gap at `index` starts in `filled`, in UTF-16 units.
    func answerStart(of index: Int) -> Int? {
        let ns = sentence as NSString
        var cursor = 0
        var offset = 0
        for match in Self.placeholder.matches(in: sentence, range: NSRange(location: 0, length: ns.length)) {
            offset += match.range.location - cursor
            let gap = (Int(ns.substring(with: match.range(at: 1))) ?? 1) - 1
            if gap == index { return offset }
            offset += (gaps.indices.contains(gap) ? gaps[gap].answer : "___").utf16.count
            cursor = match.range.location + match.range.length
        }
        return nil
    }

    /// The first gap's case, for the round history and the feedback header.
    var kasus: GrammarCase { gaps.first?.kasus ?? .akkusativ }
}

nonisolated struct GapChoiceFile: Codable {
    let version: Int
    let items: [GapChoiceItem]
}

extension GrammarCase: Codable {}
extension Gender: Codable {}
