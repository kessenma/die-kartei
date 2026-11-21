//
//  EnglishAnchors.swift
//  german-ai-flashcards
//
//  „Englisch & Fälle“ between the bank and the screen: which spans of the Verstehen items can be
//  asked in English, which question each one answers, and the round each exercise composes from
//  them. No content of its own — every item is a bundled `KasusConceptItem` that already carries
//  an English twin and, per target, that phrase's span in the English line
//  (`KasusConceptItem.english`), verified a verbatim substring of it.
//
//    clean   the four questions work          subject · object · recipient · attribute
//    trap    the English question misleads    dativeVerb („followed the woman“ → der Frau)
//    keine   a preposition decided the case   preposition · wechsel · prepObject · inferred
//
//  The split reads the target's **reason**, never its role: `KasusRole.empfaenger` merges a true
//  receiver with a Dativ verb's one partner, and that merge is precisely the trap. The switch is
//  exhaustive over `KasusReason` so a new reason has to be placed by hand rather than defaulting
//  into the clean pool, and a `keine` span must really have a preposition on it — an inferred
//  phrase proven by its form alone answers nothing a learner could name.
//
//  Excluded by name: `predicate` („ist ein Chef“ answers Wer oder was? as well as the subject
//  does), `time` („jeden Tag“ answers wann?), `dativeOther` („mir ist kalt“ has no question).
//

import Foundation

// MARK: - Buckets

/// Which exercise a span can be asked in.
nonisolated enum EnglishAnchorBucket: String, Hashable {
    /// The anchor question gives the right case.
    case clean
    /// The English reading points at the wrong case.
    case trap
    /// No question applies: Kasus-Check step one decided it.
    case keine
}

/// One askable span: an item, one of its targets, and the question that target answers. Carries a
/// `KasusConceptPlayable`, so it lives on the main actor like the rest of the Verstehen layer.
struct EnglishAnchorItem: Identifiable {
    let playable: KasusConceptPlayable
    let targetIndex: Int
    /// The Kasus-Check step that decides the phrase, which is where the question comes from.
    let role: KasusRole
    let question: KasusQuestion
    let bucket: EnglishAnchorBucket
    /// The phrase as it stands in the English line, which is what the ring is drawn around.
    let english: String
    let paragraph: Int
    /// Which language the sentence is in when the question is asked. Set at compose: the preset is
    /// the ramp (`KasusHelp.pinnedStage`), never a second ask of the same span.
    var stage: EnglishStage = .beide

    var id: String { "\(playable.id)#\(targetIndex)" }
    var target: KasusLocatedTarget? { playable.target(targetIndex) }
    /// The German phrase, for the reveal.
    var german: String { target?.surface ?? "" }
    var kasus: GrammarCase? { target?.kasus }
}

// MARK: - The pool

enum EnglishAnchors {

    /// Where a reason's span belongs. Nil means it is never asked. Pure, so the kasus-cli can
    /// share it.
    nonisolated static func bucket(for reason: KasusReason, hasPreposition: Bool) -> EnglishAnchorBucket? {
        switch reason {
        case .subject, .object, .recipient, .attribute:
            return .clean
        case .dativeVerb:
            return .trap
        case .preposition, .wechselWo, .wechselWohin, .prepObject:
            return hasPreposition ? .keine : nil
        // A harvested phrase whose case came from its form alone has no story to tell; one with a
        // preposition in front is the same lesson as a planned `preposition` target.
        case .inferred:
            return hasPreposition ? .keine : nil
        case .predicate, .time, .dativeOther:
            return nil
        }
    }

    /// Every askable span of one item, in reading order.
    @MainActor
    static func spans(in playable: KasusConceptPlayable) -> [EnglishAnchorItem] {
        var found: [(location: Int, item: EnglishAnchorItem)] = []
        for target in playable.targets where target.gradable {
            guard let english = playable.item.english[target.index], !english.isEmpty else { continue }
            guard let role = playable.facts.roles[target.index] else { continue }
            let hasPreposition = target.preposition != nil
            guard let bucket = bucket(for: target.spec.reason, hasPreposition: hasPreposition) else { continue }
            let item = EnglishAnchorItem(playable: playable, targetIndex: target.index, role: role,
                                         question: KasusQuestion(role: role), bucket: bucket,
                                         english: english, paragraph: target.paragraphIndex)
            found.append((target.range.location, item))
        }
        return found.sorted { $0.location < $1.location }.map(\.item)
    }

    /// A unit's whole pool. Reads the Verstehen items through the same audit every Verstehen
    /// exercise does, so an item that fails it is left out here too.
    @MainActor
    static func pool(unit: KasusUnit, bank: KasusConceptBank? = nil,
                     lexicon: some KasusLexicon = AppKasusLexicon()) -> [EnglishAnchorItem] {
        let bank = bank ?? .bundled
        return KasusConceptExercise.allCases
            .flatMap { KasusService.conceptPlayables(unit: unit, exercise: $0, bank: bank, lexicon: lexicon) }
            .flatMap(spans(in:))
    }

    /// The units an exercise is offered on. Nominativ is never one: with a single case in play the
    /// question grid is one button.
    nonisolated static let units: [KasusUnit] = [.akkusativ, .dativ, .genitiv, .alleFaelle]

    /// Enough spans to fill a round of this kind. „Die englische Falle“ has no pool at all before
    /// the Dativ, which is correct: there is no trap until a Dativ verb can appear.
    @MainActor
    static func offers(_ kind: KasusDrillKind, for unit: KasusUnit,
                       bank: KasusConceptBank? = nil) -> Bool {
        guard units.contains(unit) else { return false }
        let spans = pool(unit: unit, bank: bank)
        switch kind {
        case .frage, .findeFall:
            return spans.filter { $0.bucket != .trap }.count >= minimumSpans
        case .englischeFalle:
            return spans.filter { $0.bucket == .trap }.count >= minimumTraps
                && spans.filter { $0.bucket == .clean }.count >= minimumTraps
        default:
            return false
        }
    }

    /// A round needs this many spans to be worth composing.
    nonisolated static let minimumSpans = 8
    /// „Die englische Falle“ mixes traps with the clean spans they are confused with, so it needs
    /// both halves.
    nonisolated static let minimumTraps = 4

    /// The units an exercise can actually be played on today, for the setup screen's menu.
    @MainActor
    static func playableUnits(_ kind: KasusDrillKind, bank: KasusConceptBank? = nil) -> [KasusUnit] {
        units.filter { offers(kind, for: $0, bank: bank) }
    }

    // MARK: Composing

    /// The spans of one round, in play order.
    ///
    /// „Welche Frage?“ and „Finde den Fall“ draw the clean pool and **always include one `keine`
    /// span** where the unit has one: an exercise that never shows a preposition-governed phrase
    /// teaches that every phrase answers one of the four, when Kasus-Check step one says the
    /// opposite. „Die englische Falle“ draws the traps and mixes in the clean spans they are
    /// confused with, so the answer can never be „always Wem?“.
    @MainActor
    static func items(unit: KasusUnit, kind: KasusDrillKind, help: KasusHelp,
                      count: Int, bank: KasusConceptBank? = nil,
                      rng: inout KasusSeededRandom) -> [EnglishAnchorItem] {
        let spans = pool(unit: unit, bank: bank)
        guard !spans.isEmpty else { return [] }
        let picked: [EnglishAnchorItem]
        switch kind {
        case .englischeFalle:
            picked = fallenRound(spans, count: count, rng: &rng)
        default:
            picked = questionRound(spans, count: count, whole: help.asksWholeSentence, rng: &rng)
        }
        return staged(picked, help: help)
    }

    /// Clean plus one preposition span, by sentence or by span.
    @MainActor
    private static func questionRound(_ spans: [EnglishAnchorItem], count: Int, whole: Bool,
                                      rng: inout KasusSeededRandom) -> [EnglishAnchorItem] {
        let asked = spans.filter { $0.bucket != .trap }
        guard !asked.isEmpty else { return [] }
        var best: [EnglishAnchorItem] = []
        for _ in 0..<24 {
            let round = draw(asked, count: count, whole: whole, rng: &rng)
            if round.contains(where: { $0.bucket == .keine }) || !asked.contains(where: { $0.bucket == .keine }) {
                return round
            }
            if round.count > best.count { best = round }
        }
        return best
    }

    /// Half traps, half the clean spans an English ear confuses them with (a done-to and a true
    /// receiver both read as „whom“).
    @MainActor
    private static func fallenRound(_ spans: [EnglishAnchorItem], count: Int,
                                    rng: inout KasusSeededRandom) -> [EnglishAnchorItem] {
        let traps = rng.shuffled(spans.filter { $0.bucket == .trap })
        let confusable = rng.shuffled(spans.filter { span in
            span.bucket == .clean && (span.question == .wen || span.question == .wem)
        })
        let trapCount = min(traps.count, (count + 1) / 2)
        var picked = Array(traps.prefix(trapCount))
        picked += confusable.prefix(count - picked.count)
        if picked.count < count { picked += traps.dropFirst(trapCount).prefix(count - picked.count) }
        return rng.shuffled(picked)
    }

    /// One span per sentence, or every asked span of as many sentences as the count needs.
    @MainActor
    private static func draw(_ spans: [EnglishAnchorItem], count: Int, whole: Bool,
                             rng: inout KasusSeededRandom) -> [EnglishAnchorItem] {
        var bySentence: [String: [EnglishAnchorItem]] = [:]
        for span in spans { bySentence[span.playable.id, default: []].append(span) }
        let order = rng.shuffled(Array(bySentence.keys))
        var picked: [EnglishAnchorItem] = []
        for id in order {
            guard let group = bySentence[id], !group.isEmpty else { continue }
            if whole {
                picked += group.prefix(count - picked.count)
            } else if let one = rng.shuffled(group).first {
                picked.append(one)
            }
            if picked.count >= count { break }
        }
        return Array(picked.prefix(count))
    }

    // MARK: Explaining

    /// The target's own explanation, with a line in front naming what the picked question would
    /// have asked for. The trap class is named, not just the case: „folgen“ is a list, not a rule.
    @MainActor
    static func explanation(for item: EnglishAnchorItem, picked: KasusQuestion,
                            target: KasusLocatedTarget) -> String {
        let own = KasusConceptExplanation.role(picked: nil, actual: item.role, for: target,
                                               in: item.playable.story)
        guard picked != item.question else {
            return item.bucket == .trap ? "\(trapLine(target)) \(own)" : own
        }
        return "\(wrongLine(picked, actual: item.question, target: target)) \(own)"
    }

    /// „Wen oder was?“ asked where the answer was „Wem?“, and the two ends of the Keine-Frage case.
    nonisolated private static func wrongLine(_ picked: KasusQuestion, actual: KasusQuestion,
                                  target: KasusLocatedTarget) -> String {
        let preposition = target.preposition?.word ?? target.spec.trigger
        switch (picked, actual) {
        case (.keine, _):
            return "No preposition stands in front of this phrase, so one of the four questions does decide it."
        case (_, .keine):
            return "„\(picked.germanLabel)“ never gets asked here: *\(preposition)* stands in front of the phrase and settles the case on its own."
        default:
            let asked = picked.kasus.map { "{\($0.short.lowercased()):\($0.name)}" } ?? picked.germanLabel
            return "„\(picked.germanLabel)“ asks for the \(asked); this phrase answers „\(actual.germanLabel)“."
        }
    }

    /// Right, and worth saying why it felt wrong: the English reading points elsewhere.
    nonisolated private static func trapLine(_ target: KasusLocatedTarget) -> String {
        let verb = target.spec.trigger
        return "Genau, and your English would have said otherwise: *\(verb)* reads as a plain done-to in English („\(verb) the woman“), but it hands its one partner the {dat:Dativ}."
    }

    /// The preset is the ramp: a pinned stage, or Englisch → Beide → Deutsch by thirds.
    @MainActor
    private static func staged(_ items: [EnglishAnchorItem], help: KasusHelp) -> [EnglishAnchorItem] {
        guard !items.isEmpty else { return [] }
        if let pinned = help.pinnedStage {
            return items.map { var item = $0; item.stage = pinned; return item }
        }
        let third = max(1, (items.count + 2) / 3)
        return items.enumerated().map { index, item in
            var item = item
            item.stage = index < third ? .englisch : (index < third * 2 ? .beide : .deutsch)
            return item
        }
    }
}
