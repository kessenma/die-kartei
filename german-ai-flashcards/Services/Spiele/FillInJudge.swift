//
//  FillInJudge.swift
//  german-ai-flashcards
//
//  Decides whether a fill-in grid is solved, and why a drop doesn't work.
//
//  The one thing to understand before touching this file: the win check compares **crossings, not
//  the generator's answer**. A clueless crossword can have two same-length slots that no crossing
//  tells apart, and then swapping those two words is just as correct as the arrangement the
//  generator happened to find. Checking against `puzzle.solution` would tell a learner who solved
//  the puzzle that they are wrong — so it isn't done, and a test pins exactly that case.
//

import Foundation

nonisolated enum FillInJudge {

    /// The crossings where `word` in `slot` disagrees with what is already on the board.
    /// Empty means the drop is legal.
    static func conflicts(slot id: Int, word: GameWord, placed: [Int: GameWord],
                          in puzzle: FillInPuzzle) -> [Crossing] {
        guard let slot = puzzle.slot(id: id), slot.length == word.length else { return [] }
        return slot.crossings.filter { crossing in
            guard let neighbour = placed[crossing.otherSlot],
                  crossing.myIndex < word.letters.count,
                  crossing.otherIndex < neighbour.letters.count
            else { return false }
            return !GameLetters.equal(word.letters[crossing.myIndex],
                                      neighbour.letters[crossing.otherIndex])
        }
    }

    /// Whether `word` may be dropped on `slot`: right length, and no crossing says otherwise.
    static func canPlace(word: GameWord, on id: Int, placed: [Int: GameWord],
                         in puzzle: FillInPuzzle) -> Bool {
        guard let slot = puzzle.slot(id: id), slot.length == word.length else { return false }
        return conflicts(slot: id, word: word, placed: placed, in: puzzle).isEmpty
    }

    /// Solved when every slot holds a word, every word was used once, and no crossing disagrees.
    /// Note what is *not* here: any comparison with `puzzle.solution`.
    static func isSolved(_ placed: [Int: GameWord], in puzzle: FillInPuzzle) -> Bool {
        guard placed.count == puzzle.slots.count,
              puzzle.slots.allSatisfy({ placed[$0.id] != nil })
        else { return false }

        // Each word belongs to exactly one slot — otherwise the same tile could satisfy two.
        guard Set(placed.values.map(\.id)).count == placed.count else { return false }

        for slot in puzzle.slots {
            guard let word = placed[slot.id], word.length == slot.length else { return false }
            if !conflicts(slot: slot.id, word: word, placed: placed, in: puzzle).isEmpty { return false }
        }
        return true
    }

    /// The slots a tray word could still legally go into — what the board highlights when a tile
    /// is lifted.
    static func openSlots(for word: GameWord, placed: [Int: GameWord],
                          in puzzle: FillInPuzzle) -> [Int] {
        puzzle.slots
            .filter { placed[$0.id] == nil && $0.length == word.length }
            .filter { conflicts(slot: $0.id, word: word, placed: placed, in: puzzle).isEmpty }
            .map(\.id)
    }
}
