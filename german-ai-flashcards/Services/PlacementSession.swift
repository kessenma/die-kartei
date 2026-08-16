//
//  PlacementSession.swift
//  german-ai-flashcards
//
//  Drives one run of the placement probe. Pure state machine — it hands the UI an item, takes an
//  answer, and decides what to ask next; it never touches storage or SwiftData.
//
//  Six blocks, in order: two A2 anchor items, vocabulary, gender, prepositions, the grammar
//  staircase, and a cloze finale. Two of them adapt. The vocabulary staircase walks the three
//  bundled Goethe lists until it finds the level the learner holds, which then decides how hard
//  the gender block is. The grammar staircase starts where the anchors point (both right → B1,
//  split → A2, both wrong → A1) and climbs or falls in two-item blocks across A1–B2 — the only
//  block with the reach to tell a B1 from a B2. The finale asks one three-gap paragraph at the
//  level the run has estimated so far; the scorer uses it to confirm or demote, never promote.
//

import Foundation
import Observation

@Observable
final class PlacementSession {

    /// Answers given so far, oldest first.
    private(set) var answers: [PlacementAnswer] = []
    /// The single-choice question on screen, or nil once those blocks are done.
    private(set) var current: PlacementItem?
    /// The cloze finale — non-nil only after the single-choice blocks finish, until it's answered.
    private(set) var currentCloze: PlacementClozePrompt?
    /// The finale kept *after* it's answered, so the recorder can rebuild each gap's sentence for
    /// the review screen. The synthesized cloze `PlacementItem`s carry only the paragraph title,
    /// and by the time a run is recorded `currentCloze` has been cleared. Nothing in the scoring
    /// path reads this.
    private(set) var finishedCloze: PlacementClozePrompt?

    /// Where the vocabulary staircase currently stands — also the level the gender block samples.
    private(set) var level: GoetheLevel = PlacementService.startLevel
    private var correctStreak = 0
    private var wrongStreak = 0

    /// Where the grammar staircase stands. Provisional until both anchors are answered.
    private(set) var grammarLevel: CEFRLevel = .a2
    private var grammarBlock: [Bool] = []
    private var awaitingTiebreaker = false
    private var anchorsAnswered = 0
    private var anchorsCorrect = 0

    /// Words already asked about, so the gender block never re-uses a word from the vocab block.
    private var usedWords: Set<String> = []
    /// Bank ids of grammar items already asked — the bank id, not the prompt, is the dedupe key.
    private var usedGrammarIDs: Set<String> = []

    private var anchorsAsked = 0
    private var vocabAsked = 0
    private var genderAsked = 0
    private var prepositionsAsked = 0
    private var grammarAsked = 0
    private var clozeOffered = false

    init() {
        current = nextItem()
    }

    // MARK: - Progress

    var totalItems: Int {
        PlacementService.anchorItems + PlacementService.vocabItems + PlacementService.genderItems
            + PlacementService.prepositionItems + PlacementService.grammarItems
            + PlacementService.clozeGaps
    }

    var progress: Double {
        guard totalItems > 0 else { return 1 }
        return min(1, Double(answers.count) / Double(totalItems))
    }

    var needsCloze: Bool { currentCloze != nil }
    var isFinished: Bool { current == nil && currentCloze == nil }

    // MARK: - Answering

    /// Records an answer for the current item and advances. `index == nil` skips.
    func answer(_ index: Int?) {
        guard let item = current else { return }
        let answer = PlacementAnswer(item: item, chosenIndex: index)
        answers.append(answer)

        switch item.kind {
        case .vocab:
            updateStaircase(correct: answer.isCorrect)
        case .grammar(_, _, let isAnchor):
            updateGrammarStaircase(correct: answer.isCorrect, isAnchor: isAnchor)
        default:
            break
        }

        current = nextItem()
        if current == nil, !clozeOffered {
            clozeOffered = true
            currentCloze = PlacementService.clozePrompt(level: PlacementService.preClozeEstimate(answers))
        }
    }

    /// Records the finale's gap answers (`nil` = left blank, scored as wrong) and ends the run.
    func answerCloze(_ picks: [Int?]) {
        guard let cloze = currentCloze else { return }
        finishedCloze = cloze
        for (index, gap) in cloze.gaps.enumerated() {
            let item = PlacementItem(
                kind: .cloze(level: cloze.level, construct: gap.construct, gap: index),
                prompt: cloze.title,
                subtitle: nil,
                choices: gap.choices,
                correctIndex: gap.correctIndex,
                sourceID: cloze.id
            )
            let pick = picks.indices.contains(index) ? picks[index] : nil
            answers.append(PlacementAnswer(item: item, chosenIndex: pick))
        }
        currentCloze = nil
    }

    /// The estimate this run produced. Safe to call before the end; it scores what's been answered.
    func result(at date: Date = Date()) -> PlacementResult {
        PlacementService.score(answers, at: date)
    }

    // MARK: - Vocabulary staircase

    /// Two right in a row moves up, two wrong moves down, and either reset both counters — a
    /// simple up-down staircase, which converges on the level where the learner is around chance
    /// without needing a calibrated item bank.
    private func updateStaircase(correct: Bool) {
        let ladder = GoetheLevel.allCases
        guard let index = ladder.firstIndex(of: level) else { return }

        if correct {
            correctStreak += 1
            wrongStreak = 0
            if correctStreak >= PlacementService.stepUpStreak, index + 1 < ladder.count {
                level = ladder[index + 1]
                correctStreak = 0
            }
        } else {
            wrongStreak += 1
            correctStreak = 0
            if wrongStreak >= PlacementService.stepDownStreak, index > 0 {
                level = ladder[index - 1]
                wrongStreak = 0
            }
        }
    }

    // MARK: - Grammar staircase

    /// Anchors set the start; after that the staircase moves in two-item blocks — 2/2 promotes,
    /// 0/2 demotes, and a split asks one same-level tiebreaker whose miss demotes and whose hit
    /// holds. Blocks instead of streaks because eight items only cover four blocks, and a streak
    /// rule would let one early slip erase a level's worth of signal.
    private func updateGrammarStaircase(correct: Bool, isAnchor: Bool) {
        let ladder = PlacementService.grammarLadder

        if isAnchor {
            anchorsAnswered += 1
            if correct { anchorsCorrect += 1 }
            if anchorsAnswered == PlacementService.anchorItems {
                switch anchorsCorrect {
                case PlacementService.anchorItems: grammarLevel = .b1
                case 0: grammarLevel = .a1
                default: grammarLevel = .a2
                }
            }
            return
        }

        guard let index = ladder.firstIndex(of: grammarLevel) else { return }

        if awaitingTiebreaker {
            awaitingTiebreaker = false
            grammarBlock = []
            if !correct, index > 0 { grammarLevel = ladder[index - 1] }
            return
        }

        grammarBlock.append(correct)
        guard grammarBlock.count == 2 else { return }
        switch grammarBlock.filter({ $0 }).count {
        case 2:
            grammarBlock = []
            if index + 1 < ladder.count { grammarLevel = ladder[index + 1] }
        case 0:
            grammarBlock = []
            if index > 0 { grammarLevel = ladder[index - 1] }
        default:
            awaitingTiebreaker = true
        }
    }

    // MARK: - Item selection

    /// Walks the blocks in order, skipping any whose pool is exhausted rather than stalling.
    private func nextItem() -> PlacementItem? {
        if anchorsAsked < PlacementService.anchorItems,
           let item = PlacementService.anchorItem(index: anchorsAsked) {
            anchorsAsked += 1
            if let id = item.sourceID { usedGrammarIDs.insert(id) }
            return item
        }
        if vocabAsked < PlacementService.vocabItems,
           let item = PlacementService.vocabItem(level: level, used: usedWords) {
            vocabAsked += 1
            usedWords.insert(item.prompt.lowercased())
            return item
        }
        if genderAsked < PlacementService.genderItems, let item = genderItem() {
            genderAsked += 1
            usedWords.insert(item.prompt.lowercased())
            return item
        }
        if prepositionsAsked < PlacementService.prepositionItems,
           let item = PlacementService.prepositionItem(used: usedWords) {
            prepositionsAsked += 1
            usedWords.insert(item.prompt.lowercased())
            return item
        }
        if grammarAsked < PlacementService.grammarItems, let item = grammarItem() {
            grammarAsked += 1
            if let id = item.sourceID { usedGrammarIDs.insert(id) }
            return item
        }
        return nil
    }

    /// Gender at the staircase's level, falling back to the *nearest* list when a pool runs dry —
    /// ties break downward, so a missing item costs a question at the closest easier level, never
    /// a jump to the hardest list.
    private func genderItem() -> PlacementItem? {
        for candidate in nearestFirst(GoetheLevel.allCases, around: level) {
            if let item = PlacementService.genderItem(level: candidate, used: usedWords) { return item }
        }
        return nil
    }

    /// A staircase item at the current grammar level, with the same nearest-first fallback. A
    /// fallback item still counts as evidence at its own level — the kind carries it.
    private func grammarItem() -> PlacementItem? {
        for candidate in nearestFirst(PlacementService.grammarLadder, around: grammarLevel) {
            if let item = PlacementService.grammarItem(level: candidate, used: usedGrammarIDs) { return item }
        }
        return nil
    }

    private func nearestFirst<Level: Equatable>(_ ladder: [Level], around target: Level) -> [Level] {
        guard let index = ladder.firstIndex(of: target) else { return ladder }
        return ladder.enumerated()
            .sorted { lhs, rhs in
                let d0 = abs(lhs.offset - index)
                let d1 = abs(rhs.offset - index)
                return d0 == d1 ? lhs.offset < rhs.offset : d0 < d1
            }
            .map(\.element)
    }
}
