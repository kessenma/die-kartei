//
//  GrammarTaskArt.swift
//  german-ai-flashcards
//
//  What an exercise *asks you to do*, as a drawing: the shape of the task, so „Üben · Practice“ can
//  be read before anything is tapped. One case per task shape, deliberately shared by the kinds
//  that ask the same thing (a confusion pair and „mich oder mir?“ are both „one of these two“),
//  never one per `KasusDrillKind` — two kinds with the same drawing is information, and
//  `GrammarTaskArtTests` pins which shares are intended.
//
//  Abstract on purpose. The delivery table in docs/PREPOSITION_3D.md („Matching tiles | Nothing |
//  Would leak the meaning being tested“) holds here too: bars, blocks, dashes and blank tags —
//  never a real German word, never a form that is somebody's answer. No drawing contains a letter.
//
//  The raw value is the asset slug (`assetName`), so a drawing can later be replaced by a baked
//  Blender still (`tools/blender/`, the way `BauhausIcon` falls back) without touching a screen.
//
//  Foundation only and `nonisolated`: referenced by `KasusDrillMeta`, so it compiles into
//  training/kasus_cli (its row in sources.txt). Drawn by
//  Features/Grammar/Shared/GrammarTaskArtView.swift; it carries no colour of its own — a row
//  passes its own tint, so neither the gender nor the case palette gains a meaning here.
//

import Foundation

nonisolated enum GrammarTaskArt: String, Hashable, CaseIterable {

    // MARK: - Sentences with something missing

    /// A sentence with one whole word slot empty: pick the article that fits.
    case wordGap = "word-gap"
    /// Words whose tails are missing: the word is there, only the ending is yours.
    case endingGap = "ending-gap"
    /// A stem, and the ending block snapping onto its end.
    case snapEnding = "snap-ending"
    /// A gap, and two candidates below it: one of these two.
    case pickOfTwo = "pick-of-two"
    /// The verb is marked, and a bracket reaches from it to the gap: the verb decides.
    case verbDecides = "verb-decides"
    /// One word in the line sits out of true: find it, then fix it.
    case spotTheOddOne = "spot-the-odd-one"
    /// A lead block, an arc, and a gap that has to agree with it.
    case followTheSubject = "follow-the-subject"

    // MARK: - Reading, not writing

    /// A highlighter band laid across two words of three lines.
    case markWords = "mark-words"
    /// Blank tags over the phrases of one sentence: name each phrase's job.
    case tagPhrases = "tag-phrases"
    /// One line, two arrowheads facing each other: which way does it read?
    case twoReadings = "two-readings"
    /// A word, and a second word stepping into its place from above.
    case swapInPlace = "swap-in-place"
    /// Three blocks, two arrows: the same thing carried across three steps.
    case threeStepChain = "three-step-chain"
    /// One part of a line ringed, and the same part marked again in the line beneath: two
    /// languages, one phrase.
    case ringOneSpan = "ring-one-span"
    /// One phrase, two roads out of it, and the road your English would take struck through.
    case forkedPath = "forked-path"
    /// A label given at the top and three candidate phrases below: which one answers it?
    case pickThePhrase = "pick-the-phrase"

    // MARK: - Shapes that aren't a sentence

    /// One word and a row of labels: which label does it take?
    case labelOneWord = "label-one-word"
    /// Four blocks, two of them joined: find the pairs.
    case matchPairs = "match-pairs"
    /// A deck to flip through.
    case cardStack = "card-stack"
    /// A deck with cards coming back round: what's due today.
    case reviewQueue = "review-queue"
    /// A short card with a fold: something to read, not to answer.
    case ideaCard = "idea-card"
    /// Lines against a clock.
    case beatTheClock = "beat-the-clock"
    /// A grid with one cell empty, and a block on its way into it.
    case fillTheGrid = "fill-the-grid"

    /// The image set a baked still would ship as (`task-art-word-gap`). Absent today: the view
    /// draws the vector and only looks for this, so an install is additive and a delete is a full
    /// rollback — the `BauhausIcon` contract.
    var assetName: String { "task-art-\(rawValue)" }
}
