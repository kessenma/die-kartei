//
//  KasusConcepts.swift
//  german-ai-flashcards
//
//  The Verstehen exercises between the bank and the screen: an item validated for play, the
//  round (its steps, the learner's picks, grading, the Kasus-Check walk), the explanations that
//  aren't a target's own, the round result for `KasusService.recordRound`, the progress marks and
//  the service entry points.
//
//    KasusConceptPlayable   an item with its validator report, numbered sentences and facts
//    KasusProbeQuestion     the Probe's swap: the phrase, the test noun, the swapped sentence
//    KasusConceptRound      one round: steps in order, `answer` / `answerStep`, `result`
//    KasusConceptExplanation the Wer and Probe lines, the role reveal, the walk's Ja/Nein lines
//
//  Rollen and Wer macht was? are recognition and count for the streak only; the Probe is
//  production and may move the coach like the Schnellrunde (`KasusService.countsTowardSkill`).
//  A lesson read is a round with nothing asked, so the row's ✓ and the hub's dot can see it.
//

import Foundation
import SwiftData

// MARK: - Playable item

/// One item validated for a session: the located targets, the sentences as word chips, and the
/// facts the exercise reads.
struct KasusConceptPlayable: Identifiable {
    let item: KasusConceptItem
    let playable: KasusPlayableStory
    let facts: KasusConceptFacts

    var id: String { item.id }
    var kind: KasusConceptKind { item.kind }
    var story: KasusStory { item.story }
    var targets: [KasusLocatedTarget] { playable.targets }
    var sentences: [KasusSentence] { playable.sentences }

    func target(_ index: Int) -> KasusLocatedTarget? { playable.target(index) }

    /// Rollen: the targets a round asks, in reading order.
    var askedTargets: [KasusLocatedTarget] { facts.asked.compactMap(target) }

    /// Wer …?: the two phrases to pick from, in reading order, and the doer.
    var options: [KasusLocatedTarget] {
        guard case .whoDoesWhat(_, let options, _) = item.detail else { return [] }
        return options.compactMap(target)
    }

    var doer: KasusLocatedTarget? {
        guard case .whoDoesWhat(_, _, let answer) = item.detail else { return nil }
        return target(answer)
    }

    /// Answered by tapping one of two pictures: one per reading, each keyed by its doer.
    var hasPictureChoice: Bool {
        kind == .whoDoesWhat && !options.isEmpty && options.allSatisfy { item.pictures[$0.index] != nil }
    }

    var question: KasusConceptItem.Prompt? {
        guard case .whoDoesWhat(let question, _, _) = item.detail else { return nil }
        return question
    }

    /// Same meaning: the authored answer.
    var same: Bool? {
        guard case .sameMeaning(let same) = item.detail else { return nil }
        return same
    }

    /// The Probe's question, built from the item's target and noun.
    var probe: KasusProbeQuestion? {
        guard case .probe(let index, let noun) = item.detail, let target = target(index) else { return nil }
        return KasusProbeQuestion(target: target, noun: noun, in: story)
    }

    /// The English line of a paragraph, with the target's phrase marked up in its case color
    /// where the item names one („the woman“ → `{dat:the woman}`). Plain when it doesn't.
    func englishLine(paragraph: Int, highlighting targets: [Int: GrammarCase]) -> String {
        guard story.paragraphs.indices.contains(paragraph) else { return "" }
        var line = story.paragraphs[paragraph].en
        for (index, kasus) in targets.sorted(by: { $0.key < $1.key }) {
            guard let phrase = item.english[index], let range = line.range(of: phrase) else { continue }
            line.replaceSubrange(range, with: "{\(kasus.short.lowercased()):\(phrase)}")
        }
        return line
    }
}

/// The Probe's swap: a phrase whose article could be two cases, and the masculine test noun whose
/// article can't.
struct KasusProbeQuestion: Hashable {
    let target: KasusLocatedTarget
    let noun: KasusProbeNoun
    /// The sentence the phrase sits in, trimmed, and where the phrase starts in it (UTF-16).
    let sentence: String
    let phraseStart: Int

    init(target: KasusLocatedTarget, noun: KasusProbeNoun, in story: KasusStory) {
        self.target = target
        self.noun = noun
        var sentence = target.surface
        var start = 0
        if story.paragraphs.indices.contains(target.paragraphIndex) {
            let paragraph = story.paragraphs[target.paragraphIndex].de as NSString
            let range = target.sentenceRange
            if range.location <= target.range.location, NSMaxRange(target.range) <= NSMaxRange(range),
               NSMaxRange(range) <= paragraph.length {
                let raw = paragraph.substring(with: range)
                let leading = raw.prefix(while: \.isWhitespace)
                sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                start = target.range.location - range.location - leading.utf16.count
            }
        }
        self.sentence = sentence
        phraseStart = start
    }

    var kasus: GrammarCase { target.kasus }

    /// „dem Mann“: the form that fits the slot.
    var answer: String { noun.form(kasus) }

    /// The answer capitalised like the phrase it replaces („Dem Mann“ at a sentence start).
    var swappedPhrase: String {
        target.surface.first?.isUppercase == true ? answer.prefix(1).uppercased() + answer.dropFirst() : answer
    }

    /// The article of the swapped phrase, as the round history stores an answer.
    var swappedArticle: String { String(swappedPhrase.split(separator: " ").first ?? "") }

    /// The buttons: der · den · dem Mann, and des Mannes once the Genitiv is in play.
    func options(includeGenitive: Bool) -> [String] {
        noun.options(includeGenitive: includeGenitive || kasus == .genitiv)
    }

    /// The sentence with the phrase swapped: „Ich helfe dem Mann.“
    var swappedSentence: String {
        let ns = sentence as NSString
        let length = target.surface.utf16.count
        guard phraseStart >= 0, phraseStart + length <= ns.length,
              ns.substring(with: NSRange(location: phraseStart, length: length)) == target.surface
        else { return sentence.replacingOccurrences(of: target.surface, with: swappedPhrase) }
        return ns.replacingCharacters(in: NSRange(location: phraseStart, length: length), with: swappedPhrase)
    }

    /// Whether a picked button is the answer, ignoring case.
    func isRight(_ pick: String) -> Bool {
        pick.caseInsensitiveCompare(answer) == .orderedSame
    }

    /// The case a picked form stands for („den Mann“ → Akkusativ). Nil for a stray string.
    func kasus(of pick: String) -> GrammarCase? {
        GrammarCase.allCases.first { noun.form($0).caseInsensitiveCompare(pick) == .orderedSame }
    }
}

// MARK: - Picks and answers

/// What the learner tapped.
enum KasusConceptPick: Hashable {
    /// Rollen, Direkt: a role chip.
    case role(KasusRole)
    /// Rollen, Schritt für Schritt: Ja or Nein to one Kasus-Check question.
    case step(KasusRole, yes: Bool)
    /// Wer …?: a phrase, by target index.
    case option(Int)
    /// Gleich oder anders?
    case same(Bool)
    /// Die Probe: a form of the test noun.
    case form(String)
}

/// One graded phrase, item or swap, as the screen and the round history need it.
struct KasusConceptAnswer: Hashable, Identifiable {
    /// Position in `KasusConceptRound.steps`.
    let step: Int
    let pick: KasusConceptPick
    let outcome: KasusItemOutcome
    /// The case the answer revealed: the phrase's (Rollen, Probe) or the clue's (Wer).
    let kasus: GrammarCase
    /// Why, in the `KasusRich` markup.
    let explanation: String
    let record: KasusRoundItem
    /// What `recordRound` sees.
    let result: KasusItemResult

    var id: Int { step }
    var isRight: Bool { outcome.isRight }
}

/// One thing to answer: an item, and for Rollen the phrase in it.
struct KasusConceptStep: Hashable {
    /// Index into `KasusConceptRound.items`.
    let item: Int
    /// Rollen: the target's index. Nil for the other exercises.
    let target: Int?
}

/// Schritt für Schritt: the Kasus-Check questions for one phrase, asked in order.
struct KasusConceptWalk: Hashable {
    let questions: [KasusRole]
    /// The question being asked.
    var position = 0
    /// Wrong answers so far: the phrase is first-try right only with none.
    var wrong = 0

    var current: KasusRole? { questions.indices.contains(position) ? questions[position] : nil }
    var isOver: Bool { position >= questions.count }
}

/// What one Ja or Nein did: right or not, the line to show, and the phrase's answer once the
/// walk is over.
struct KasusConceptStepResult: Hashable {
    let question: KasusRole
    let yes: Bool
    let right: Bool
    let line: String
    let finished: KasusConceptAnswer?
}

// MARK: - The round

struct KasusConceptRound {
    let id = UUID()
    let unit: KasusUnit
    let exercise: KasusConceptExercise
    let rolesMode: KasusRolesMode
    let items: [KasusConceptPlayable]
    let steps: [KasusConceptStep]
    private(set) var answers: [KasusConceptAnswer] = []
    /// Schritt für Schritt: the walk through the current phrase.
    private(set) var walk: KasusConceptWalk?

    init(unit: KasusUnit, exercise: KasusConceptExercise, rolesMode: KasusRolesMode = .direkt,
         items: [KasusConceptPlayable]) {
        self.unit = unit
        self.exercise = exercise
        self.rolesMode = exercise == .roles ? rolesMode : .direkt
        self.items = items
        var steps: [KasusConceptStep] = []
        for (i, item) in items.enumerated() {
            switch exercise {
            case .roles:
                steps += item.facts.asked.map { KasusConceptStep(item: i, target: $0) }
            case .wer, .probe:
                steps.append(KasusConceptStep(item: i, target: nil))
            }
        }
        self.steps = steps
        startWalkIfNeeded()
    }

    var cursor: Int { answers.count }
    var isFinished: Bool { cursor >= steps.count }
    var current: KasusConceptStep? { isFinished ? nil : steps[cursor] }
    var currentItem: KasusConceptPlayable? { current.map { items[$0.item] } }
    var currentTarget: KasusLocatedTarget? {
        guard let step = current, let index = step.target else { return nil }
        return items[step.item].target(index)
    }
    /// The role of the phrase being asked (Rollen).
    var currentRole: KasusRole? {
        guard let step = current, let index = step.target else { return nil }
        return items[step.item].facts.roles[index]
    }

    var firstTryCount: Int { answers.filter(\.isRight).count }

    /// The Kasus-Check questions in play, for Schritt für Schritt.
    var walkQuestions: [KasusRole] { KasusRole.walkSteps(for: unit) }

    private mutating func startWalkIfNeeded() {
        guard rolesMode == .schritt, !isFinished else {
            walk = nil
            return
        }
        walk = KasusConceptWalk(questions: walkQuestions)
    }

    // MARK: Answering

    /// Grades the current step with a chip, phrase, Gleich/Anders or form pick. Nil once the
    /// round is over, or for a pick the exercise doesn't take.
    mutating func answer(_ pick: KasusConceptPick) -> KasusConceptAnswer? {
        guard let step = current else { return nil }
        let item = items[step.item]
        let answer: KasusConceptAnswer?
        switch (exercise, pick) {
        case (.roles, .role(let role)):
            guard let index = step.target, let target = item.target(index), let actual = item.facts.roles[index] else { return nil }
            answer = Self.gradeRole(picked: role, right: role == actual, target: target, actual: actual,
                                    item: item, step: cursor, pick: pick)
        case (.wer, .option(let picked)):
            answer = Self.gradeOption(picked, item: item, step: cursor)
        case (.wer, .same(let picked)):
            answer = Self.gradeSame(picked, item: item, step: cursor)
        case (.probe, .form(let form)):
            answer = Self.gradeForm(form, item: item, step: cursor)
        default:
            answer = nil
        }
        if let answer {
            answers.append(answer)
            startWalkIfNeeded()
        }
        return answer
    }

    /// Schritt für Schritt: Ja or Nein to the question being asked. The first Ja decides, and so
    /// does a Nein to the last question (then it's the direct object). A wrong Ja is explained
    /// and the walk goes on; a wrong Nein at the deciding question ends it with the answer shown.
    mutating func answerStep(yes: Bool) -> KasusConceptStepResult? {
        guard exercise == .roles, var walk, walk.current != nil, let step = current,
              let index = step.target, let target = items[step.item].target(index),
              let actual = items[step.item].facts.roles[index] else { return nil }
        let result = Self.walk(&walk, yes: yes, target: target, actual: actual, item: items[step.item], step: cursor)
        self.walk = walk
        if let finished = result.finished {
            answers.append(finished)
            startWalkIfNeeded()
        }
        return result
    }

    /// One Ja or Nein on `walk`'s current question for the phrase `target`, whose role is
    /// `actual`: the line to show, whether it was right, and the phrase's graded answer once the
    /// walk is over. Shared with the drill shell's Rollen module, which keeps the walk itself.
    static func walk(_ walk: inout KasusConceptWalk, yes: Bool, target: KasusLocatedTarget, actual: KasusRole,
                     item: KasusConceptPlayable, step: Int) -> KasusConceptStepResult {
        let question = walk.current ?? walk.questions.last ?? .direktesObjekt
        let decides = actual == question
        let right = yes == decides
        if !right { walk.wrong += 1 }
        var line: String
        if decides {
            // The deciding question: Ja ends the walk right; Nein ends it wrong, answer shown.
            line = (right ? "**Ja.** " : "**Doch** · Yes, it is. ")
                + KasusConceptExplanation.reveal(actual, for: target, in: item.story)
            walk.position = walk.questions.count
        } else {
            let why = KasusConceptExplanation.whyNot(question, for: target, item: item)
            line = yes ? "**Nein.** " + why.prefix(1).uppercased() + why.dropFirst() : "**Nein**, " + why
            walk.position += 1
            if walk.isOver {
                // Every question got its Nein: what's left is the direct object.
                line += " **Nichts davon** · None of these, so: "
                    + KasusConceptExplanation.reveal(actual, for: target, in: item.story)
            }
        }
        var finished: KasusConceptAnswer?
        if walk.isOver {
            finished = gradeRole(picked: nil, right: walk.wrong == 0, target: target, actual: actual,
                                 item: item, step: step, pick: .step(question, yes: yes))
        }
        return KasusConceptStepResult(question: question, yes: yes, right: right, line: line, finished: finished)
    }

    // MARK: Grading

    /// `picked` is the chip (Direkt); nil for a walk, whose lines already said what went wrong.
    static func gradeRole(picked: KasusRole?, right: Bool, target: KasusLocatedTarget, actual: KasusRole,
                                  item: KasusConceptPlayable, step: Int, pick: KasusConceptPick) -> KasusConceptAnswer {
        let kasus = actual.revealedCase(for: target)
        let explanation = KasusConceptExplanation.role(picked: right ? nil : picked, actual: actual,
                                                       for: target, in: item.story)
        let stored = picked?.rawValue ?? (right ? actual.rawValue : KasusRolesMode.schritt.rawValue)
        let record = KasusRoundItem.story(target, in: item.story, pick: stored,
                                          outcome: right ? .right : .wrongPick, explanation: explanation)
        let result = KasusItemResult(kasus: kasus, genus: target.genus, firstTry: right,
                                     targetIndex: target.index, record: record)
        return KasusConceptAnswer(step: step, pick: pick, outcome: right ? .right : .wrongPick,
                                  kasus: kasus, explanation: explanation, record: record, result: result)
    }

    static func gradeOption(_ picked: Int, item: KasusConceptPlayable, step: Int) -> KasusConceptAnswer? {
        guard let doer = item.doer, let clueIndex = item.facts.clue, let clue = item.target(clueIndex),
              let pickedTarget = item.target(picked) else { return nil }
        let right = picked == doer.index
        let explanation = KasusConceptExplanation.whoDoesWhat(item)
        let record = KasusRoundItem(
            sentence: sentence(of: clue, in: item.story), phraseStart: phraseStart(of: clue, in: item.story),
            phrase: clue.surface, answer: clue.determiner, pick: pickedTarget.surface,
            kasus: clue.kasus, genus: clue.genus, outcome: right ? .right : .wrongPick,
            explanation: explanation, hasNounGender: clue.hasNounGender)
        let result = KasusItemResult(kasus: clue.kasus, genus: clue.genus, firstTry: right, record: record)
        return KasusConceptAnswer(step: step, pick: .option(picked), outcome: right ? .right : .wrongPick,
                                  kasus: clue.kasus, explanation: explanation, record: record, result: result)
    }

    static func gradeSame(_ picked: Bool, item: KasusConceptPlayable, step: Int) -> KasusConceptAnswer? {
        guard let same = item.same, let clueIndex = item.facts.clues.last, let clue = item.target(clueIndex)
        else { return nil }
        let right = picked == same
        let explanation = KasusConceptExplanation.sameMeaning(item)
        let text = item.story.paragraphs.enumerated().map { "\($0.offset + 1). \($0.element.de)" }.joined(separator: "  ")
        let record = KasusRoundItem(
            sentence: text, phraseStart: nil, phrase: clue.surface, answer: clue.determiner,
            pick: picked ? "gleich" : "anders", kasus: clue.kasus, genus: clue.genus,
            outcome: right ? .right : .wrongPick, explanation: explanation, hasNounGender: clue.hasNounGender)
        let result = KasusItemResult(kasus: clue.kasus, genus: clue.genus, firstTry: right, record: record)
        return KasusConceptAnswer(step: step, pick: .same(picked), outcome: right ? .right : .wrongPick,
                                  kasus: clue.kasus, explanation: explanation, record: record, result: result)
    }

    static func gradeForm(_ form: String, item: KasusConceptPlayable, step: Int) -> KasusConceptAnswer? {
        guard let probe = item.probe else { return nil }
        let right = probe.isRight(form)
        let explanation = KasusConceptExplanation.probe(probe, in: item.story)
        let picked = String(form.split(separator: " ").first ?? "")
        let record = KasusRoundItem(
            sentence: probe.swappedSentence, phraseStart: probe.phraseStart, phrase: probe.swappedPhrase,
            answer: probe.swappedArticle, pick: picked, kasus: probe.kasus, genus: .der,
            outcome: right ? .right : .caseMiss, explanation: explanation, hasNounGender: true)
        let result = KasusItemResult(kasus: probe.kasus, genus: .der, firstTry: right, record: record)
        return KasusConceptAnswer(step: step, pick: .form(form), outcome: right ? .right : .caseMiss,
                                  kasus: probe.kasus, explanation: explanation, record: record, result: result)
    }

    /// The trimmed sentence a target sits in.
    static func sentence(of target: KasusLocatedTarget, in story: KasusStory) -> String {
        guard story.paragraphs.indices.contains(target.paragraphIndex) else { return target.surface }
        let paragraph = story.paragraphs[target.paragraphIndex].de as NSString
        guard NSMaxRange(target.sentenceRange) <= paragraph.length else { return target.surface }
        return paragraph.substring(with: target.sentenceRange).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where a target starts in its trimmed sentence (UTF-16).
    static func phraseStart(of target: KasusLocatedTarget, in story: KasusStory) -> Int? {
        guard story.paragraphs.indices.contains(target.paragraphIndex) else { return nil }
        let paragraph = story.paragraphs[target.paragraphIndex].de as NSString
        let range = target.sentenceRange
        guard range.location <= target.range.location, NSMaxRange(range) <= paragraph.length else { return nil }
        let leading = paragraph.substring(with: range).prefix(while: \.isWhitespace)
        return target.range.location - range.location - leading.utf16.count
    }

    // MARK: Result

    /// The round for `KasusService.recordRound`, filed under the unit's exercise.
    func result(durationSeconds: Int) -> KasusRoundResult {
        KasusRoundResult(storyID: KasusService.conceptRoundID(unit, exercise), unit: unit,
                         step: exercise.roundStep, items: answers.map(\.result),
                         durationSeconds: durationSeconds, id: id)
    }

    // MARK: Composing

    /// The items for one round, in play order: `count` of them (or every one the unit has), so
    /// that past the Nominativ unit a round covers at least two cases, a Probe round asks at
    /// least two different forms, and a Wer round mixes about half object-first sentences with
    /// three „Gleich oder anders?“ pairs. Seeded, so a seed always gives the same round.
    static func compose(_ pool: [KasusConceptPlayable], exercise: KasusConceptExercise, unit: KasusUnit,
                        count: Int, rng: inout KasusSeededRandom) -> [KasusConceptPlayable] {
        switch exercise {
        case .wer:
            let pairs = rng.shuffled(pool.filter { $0.kind == .sameMeaning })
            let who = pool.filter { $0.kind == .whoDoesWhat }
            let ovs = rng.shuffled(who.filter(\.facts.isOVS))
            let svo = rng.shuffled(who.filter { !$0.facts.isOVS })
            // Three pairs and seven „Wer …?“ items; a unit short of one kind fills up with the other.
            var pairCount = min(3, pairs.count)
            let whoCount = min(who.count, count - pairCount)
            pairCount = min(pairs.count, count - whoCount)
            let ovsCount = min(ovs.count, (whoCount + 1) / 2)
            var picked = Array(ovs.prefix(ovsCount))
            picked += svo.prefix(whoCount - picked.count)
            if picked.count < whoCount { picked += ovs.dropFirst(ovsCount).prefix(whoCount - picked.count) }
            picked += pairs.prefix(pairCount)
            return rng.shuffled(picked)
        case .roles, .probe:
            var best: [KasusConceptPlayable] = []
            for _ in 0..<24 {
                let round = Array(rng.shuffled(pool).prefix(count))
                if coversEnough(round, exercise: exercise, unit: unit) { return round }
                if round.count > best.count { best = round }
            }
            return best
        }
    }

    /// Past the Nominativ unit a Rollen round asks at least two cases, and a Probe round asks at
    /// least two different forms; with one item either is impossible and allowed.
    static func coversEnough(_ round: [KasusConceptPlayable], exercise: KasusConceptExercise, unit: KasusUnit) -> Bool {
        guard unit != .nominativ, round.count > 1 else { return true }
        switch exercise {
        case .roles:
            let cases = Set(round.flatMap { item in item.askedTargets.map { item.facts.roles[$0.index]?.revealedCase(for: $0) ?? $0.kasus } })
            return cases.count >= 2
        case .probe:
            return Set(round.compactMap { $0.probe?.answer }).count >= 2
        case .wer:
            return true
        }
    }
}

// MARK: - Explanations

/// The lines a target's own explanation doesn't give: the role reveal, the walk's Ja/Nein lines,
/// the Wer reading and the Probe's swap. All in the `KasusRich` markup, Foundation only.
enum KasusConceptExplanation {

    /// „**Empfänger** (the receiver) → {dat:Dativ}. “ + the target's explanation; after a wrong
    /// pick, that pick first.
    static func role(picked: KasusRole?, actual: KasusRole, for target: KasusLocatedTarget, in story: KasusStory) -> String {
        var line = ""
        if let picked, picked != actual {
            line += "Not **\(picked.germanLabel)**. "
        }
        return line + reveal(actual, for: target, in: story)
    }

    /// „**Empfänger** (the receiver) → {dat:Dativ}. “ + the target's explanation.
    static func reveal(_ role: KasusRole, for target: KasusLocatedTarget, in story: KasusStory) -> String {
        let kasus = KasusExplanation.caseName(role.revealedCase(for: target))
        return "**\(role.germanLabel)** (\(role.englishLabel)) → \(kasus). "
            + KasusExplanation.explanation(for: target, in: story)
    }

    /// Why a phrase isn't the step just asked about, for a wrong Ja (or a right Nein).
    static func whyNot(_ question: KasusRole, for target: KasusLocatedTarget, item: KasusConceptPlayable,
                       short: Bool = false) -> String {
        let phrase = "„\(target.surface)“"
        let verb = "*\(target.spec.trigger)*"
        switch question {
        case .praeposition:
            return "no preposition stands in front of \(phrase)."
        case .gehoertZu:
            return "\(phrase) doesn't hang on another noun."
        case .subjekt:
            let subject = item.facts.subjects.compactMap(item.target).first { $0.paragraphIndex == target.paragraphIndex }
            if let subject, subject.index != target.index {
                return "\(phrase) isn't the subject: \(verb) goes with „\(subject.surface)“."
            }
            return "\(phrase) isn't the one doing \(verb)."
        case .gleichSubjekt:
            if target.spec.reason == .subject {
                return "\(phrase) is the subject itself, not what *sein* equates with it."
            }
            return "\(verb) isn't *sein, werden, bleiben* or *heißen*, so nothing is equated here."
        case .empfaenger:
            return "\(phrase) isn't the receiver, and \(verb) is no Dativ verb."
        case .direktesObjekt:
            return "\(phrase) is decided by an earlier step."
        }
    }

    /// „{m:Den} can only be {akk:Akkusativ}: „Den Hund“ is what *jagt* acts on, so „die Katze“ is
    /// the doer, even though it comes second. Word order doesn't decide here; the ending does.“
    static func whoDoesWhat(_ item: KasusConceptPlayable) -> String {
        guard let doer = item.doer, let clueIndex = item.facts.clue, let clue = item.target(clueIndex) else { return "" }
        let doerPhrase = "„\(doer.surface)“"
        let nom = KasusExplanation.caseName(.nominativ)
        var line: String
        if clue.index == doer.index {
            line = "\(formNote(clue)) can only be \(nom): \(doerPhrase) is the doer."
        } else {
            let verb = "*\(clue.spec.trigger)*"
            let job: String = switch clue.spec.reason {
            case .object:     "what \(verb) acts on"
            case .recipient:  "the receiver of \(verb)"
            case .dativeVerb: "the partner of \(verb), a Dativ verb"
            default:          "not the doer"
            }
            line = "\(formNote(clue)) can only be \(KasusExplanation.caseName(clue.kasus)): „\(clue.surface)“ is \(job), so \(doerPhrase) is the doer"
            line += item.facts.isOVS ? ", even though it comes second." : "."
        }
        if item.facts.isOVS {
            line += " Word order doesn't decide here; the ending does."
        }
        return line
    }

    /// „Gleich: in both, „die Katze“ is the doer and „den Hund“ is what *jagt* acts on; only the
    /// order moved. {m:Den} shows the case, not the position.“
    static func sameMeaning(_ item: KasusConceptPlayable) -> String {
        guard let same = item.same, item.story.paragraphs.count == 2 else { return "" }
        func parts(_ paragraph: Int) -> (subject: KasusLocatedTarget?, partner: KasusLocatedTarget?, clue: KasusLocatedTarget?) {
            let here = item.targets.filter { $0.paragraphIndex == paragraph }
            let subject = here.first { $0.spec.reason == .subject }
            let partner = here.first { [.object, .recipient, .dativeVerb].contains($0.spec.reason) }
            let clue = item.facts.clues.indices.contains(paragraph) ? item.target(item.facts.clues[paragraph]) : nil
            return (subject, partner, clue)
        }
        let first = parts(0), second = parts(1)
        guard let s1 = first.subject, let s2 = second.subject else { return "" }
        let nom = KasusExplanation.caseName(.nominativ)
        var line: String
        if same {
            line = "**Gleich** · Same: in both, „\(s1.surface)“ is the doer (\(nom))"
            if let p = first.partner {
                line += " and „\(p.surface)“ is \(job(of: p)) (\(KasusExplanation.caseName(p.kasus)))"
            }
            line += "; only the order moved."
        } else {
            line = "**Anders** · Different: in 1. „\(s1.surface)“ is the doer (\(nom)); in 2. „\(s2.surface)“ is"
            if let p = second.partner {
                line += ", and „\(p.surface)“ is \(job(of: p)) (\(KasusExplanation.caseName(p.kasus)))."
            } else {
                line += "."
            }
        }
        if let clue = second.clue {
            line += " \(formNote(clue)) shows the case, not the position."
        }
        return line
    }

    /// „Swap in *der Mann*: only {m:dem} fits here, and {m:dem} is {dat:Dativ}. By its form, {f:der}
    /// could be … “ + the target's explanation.
    static func probe(_ probe: KasusProbeQuestion, in story: KasusStory) -> String {
        let target = probe.target
        let article = probe.answer.split(separator: " ").first.map(String.init) ?? probe.answer
        let kasus = KasusExplanation.caseName(target.kasus)
        let cases = GrammarCase.allCases.filter(target.candidates.contains).map(KasusExplanation.caseName)
        let could = cases.count > 1
            ? " \(KasusExplanation.form(target.caseForm, target.genus)) could be \(list(cases)); the masculine shows it."
            : ""
        return "Swap in *\(probe.noun.dictionaryForm)*: only \(KasusExplanation.form(article, .der)) fits here, and \(KasusExplanation.form(article, .der)) is \(kasus).\(could) "
            + KasusExplanation.ruleLine(for: target)
    }

    // MARK: Helpers

    /// „{m:Den} + a masculine noun“
    private static func formNote(_ target: KasusLocatedTarget) -> String {
        let noun = target.genus == .plural ? "a plural noun" : "a \(target.genus.genderName) noun"
        return "\(KasusExplanation.form(target.determiner, target.genus)) + \(noun)"
    }

    private static func job(of target: KasusLocatedTarget) -> String {
        let verb = "*\(target.spec.trigger)*"
        return switch target.spec.reason {
        case .object:     "what \(verb) acts on"
        case .recipient:  "the receiver of \(verb)"
        case .dativeVerb: "the partner of \(verb)"
        default:          "the other phrase"
        }
    }

    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + items[items.count - 1]
    }
}

// MARK: - Service

extension KasusService {

    /// Every Verstehen round files under this prefix: `concept-<unit>-<exercise>`, and a read
    /// lesson under `concept-<unit>-lesson`.
    static let conceptIDPrefix = KasusDrillMeta.conceptPrefix

    static func conceptRoundID(_ unit: KasusUnit, _ exercise: KasusConceptExercise) -> String {
        exercise.roundStep.roundID(topicKey: unit.rawValue)
    }

    static func lessonRoundID(_ unit: KasusUnit) -> String {
        KasusRoundStep.lesson.roundID(topicKey: unit.rawValue)
    }

    /// A unit's items for one exercise, validated and read for play. An item that fails its audit
    /// is left out (and asserted on in DEBUG at load, so a bundled one never does).
    static func conceptPlayables(unit: KasusUnit, exercise: KasusConceptExercise,
                                 bank: KasusConceptBank = .bundled,
                                 lexicon: some KasusLexicon = AppKasusLexicon()) -> [KasusConceptPlayable] {
        bank.items(for: unit, exercise: exercise).compactMap { item in
            let audit = KasusConceptBank.audit(item, lexicon: lexicon)
            guard audit.passes else { return nil }
            return KasusConceptPlayable(item: item,
                                        playable: KasusPlayableStory(story: item.story, report: audit.report, lexicon: lexicon),
                                        facts: audit.facts)
        }
    }

    /// A fresh round, or nil when the unit has no items for the exercise.
    static func conceptRound(unit: KasusUnit, exercise: KasusConceptExercise, rolesMode: KasusRolesMode = .direkt,
                             bank: KasusConceptBank = .bundled, lexicon: some KasusLexicon = AppKasusLexicon(),
                             seed: UInt64 = UInt64.random(in: 0...UInt64.max)) -> KasusConceptRound? {
        let pool = conceptPlayables(unit: unit, exercise: exercise, bank: bank, lexicon: lexicon)
        guard !pool.isEmpty else { return nil }
        var rng = KasusSeededRandom(seed: seed)
        let items = KasusConceptRound.compose(pool, exercise: exercise, unit: unit, count: exercise.roundSize, rng: &rng)
        return KasusConceptRound(unit: unit, exercise: exercise, rolesMode: rolesMode, items: items)
    }

    /// The lesson was read through: one `lesson` round per unit (asked 0, answered 0), banking
    /// the reading time and nothing else. Returns false when the unit already has one.
    @discardableResult
    static func recordLessonRead(unit: KasusUnit, seconds: Int, in context: ModelContext) -> Bool {
        recordLessonRead(topicKey: unit.rawValue, seconds: seconds, in: context)
    }

    /// The same for any topic, filed under `concept-<topicKey>-lesson`.
    @discardableResult
    static func recordLessonRead(topicKey: String, seconds: Int, in context: ModelContext) -> Bool {
        let id = KasusRoundStep.lesson.roundID(topicKey: topicKey)
        if progress(in: context).lessonRead(topicKey: topicKey) { return false }
        context.insert(KasusRound(storyID: id, unitRaw: topicKey, stepRaw: KasusRoundStep.lesson.rawValue,
                                  askedCount: 0, firstTryCount: 0, durationSeconds: max(0, seconds),
                                  roundKey: UUID().uuidString))
        if seconds > 0 {
            StudyLogService.recordTime(StudyActivity.grammar(0).timeBucket, seconds: seconds, in: context)
        }
        try? context.save()
        return true
    }

    #if DEBUG
    /// A pick for `-kasus.debugAnswers` in a Verstehen round: the step's right answer, or a
    /// wrong one.
    static func debugConceptPick(for round: KasusConceptRound, step: Int, wrong: Bool) -> KasusConceptPick? {
        guard round.steps.indices.contains(step) else { return nil }
        let item = round.items[round.steps[step].item]
        switch round.exercise {
        case .roles:
            guard let index = round.steps[step].target, let actual = item.facts.roles[index] else { return nil }
            if !wrong { return .role(actual) }
            let other = KasusRole.chips(for: round.unit).first { $0 != actual } ?? actual
            return .role(other)
        case .wer:
            if let doer = item.doer {
                let other = item.options.first { $0.index != doer.index }?.index ?? doer.index
                return .option(wrong ? other : doer.index)
            }
            if let same = item.same { return .same(wrong ? !same : same) }
            return nil
        case .probe:
            guard let probe = item.probe else { return nil }
            let options = probe.options(includeGenitive: round.unit.casesInPlay.contains(.genitiv))
            let miss = options.first { !probe.isRight($0) } ?? probe.answer
            return .form(wrong ? miss : probe.answer)
        }
    }
    #endif
}

// MARK: - Progress

extension KasusProgress {
    /// The unit's lesson has been read through.
    func lessonRead(_ unit: KasusUnit) -> Bool {
        lessonRead(topicKey: unit.rawValue)
    }

    /// The topic's lesson has been read through.
    func lessonRead(topicKey: String) -> Bool {
        drillDone(.lesson, topicKey: topicKey)
    }

    /// A round of the exercise has been played in the unit.
    func conceptDone(_ unit: KasusUnit, _ exercise: KasusConceptExercise) -> Bool {
        drillDone(exercise.roundStep, topicKey: unit.rawValue)
    }

    /// The lesson read and every offered exercise played: the hub's Verstehen dot.
    func verstehenDone(_ unit: KasusUnit, offered: [KasusConceptExercise]) -> Bool {
        lessonRead(unit) && offered.allSatisfy { conceptDone(unit, $0) }
    }
}
