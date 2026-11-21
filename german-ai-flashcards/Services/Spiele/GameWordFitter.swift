//
//  GameWordFitter.swift
//  german-ai-flashcards
//
//  Turns a pile of words into the words one game can actually use, and says *why* about each one
//  it turned down. The why matters: a deck of 40 cards that yields 5 playable words needs to
//  explain itself („zu lang“, „mehrere Wörter“), or the learner reads it as the game being broken.
//
//  Pure and seeded, so a round is reproducible and the whole of it is testable without a bundle.
//

import Foundation

nonisolated enum GameWordFitter {

    /// Why one word can't be played. Ordered as checked, cheapest first.
    enum Rejection: Hashable, Sendable {
        case multiToken
        case tooShort(Int)
        case tooLong(Int)
        case eszett
        case noEnglish
        case outOfAlphabet(Character)
        case duplicate

        /// The reason without its detail. The detail is right for one word („4 Buchstaben“) and
        /// wrong for a summary: tallying `Rejection` itself would report „zwei Wörter mit 3
        /// Buchstaben, eines mit 2“ where the learner needs „drei Wörter sind zu kurz“.
        var kind: Kind {
            switch self {
            case .multiToken:     .multiToken
            case .tooShort:       .tooShort
            case .tooLong:        .tooLong
            case .eszett:         .eszett
            case .noEnglish:      .noEnglish
            case .outOfAlphabet:  .outOfAlphabet
            case .duplicate:      .duplicate
            }
        }
    }

    /// A reason, countable. The labels are learner-facing, in the app's voice: the German
    /// identity word with its English.
    enum Kind: String, Hashable, CaseIterable, Sendable {
        case multiToken, tooShort, tooLong, eszett, noEnglish, outOfAlphabet, duplicate

        /// Completes „<n> Wörter …“ / „<n> words …“.
        var germanReason: String {
            switch self {
            case .multiToken:    "sind mehrere Wörter"
            case .tooShort:      "sind zu kurz"
            case .tooLong:       "sind zu lang"
            case .eszett:        "haben ein ß"
            case .noEnglish:     "haben keine Übersetzung"
            case .outOfAlphabet: "haben ein Zeichen, das nicht aufs Brett passt"
            case .duplicate:     "kommen doppelt vor"
            }
        }

        var englishReason: String {
            switch self {
            case .multiToken:    "are more than one word"
            case .tooShort:      "are too short"
            case .tooLong:       "are too long"
            case .eszett:        "contain ß"
            case .noEnglish:     "have no translation"
            case .outOfAlphabet: "use a character the board can't show"
            case .duplicate:     "are repeats"
            }
        }
    }

    struct Rejected: Hashable, Sendable {
        let word: GameWord
        let reason: Rejection
    }

    struct Fit: Sendable {
        /// Playable words, source order preserved.
        var usable: [GameWord]
        var rejected: [Rejected]
        /// How many more words the game needs before it can run at all.
        var shortfall: Int
        var isEnough: Bool { shortfall == 0 }

        /// The counts the setup screen prints, most common reason first. Tallied by `Kind`, so
        /// three words of three different unusable lengths read as one reason, not three.
        var reasonTally: [(kind: Kind, count: Int)] {
            Dictionary(grouping: rejected, by: \.reason.kind)
                .map { (kind: $0.key, count: $0.value.count) }
                .sorted { ($0.count, $0.kind.rawValue) > ($1.count, $1.kind.rawValue) }
        }
    }

    static func fit(_ words: [GameWord], to requirements: GameWordRequirements) -> Fit {
        var usable: [GameWord] = []
        var rejected: [Rejected] = []
        var seen: Set<String> = []

        for word in words {
            if !seen.insert(word.id).inserted {
                rejected.append(Rejected(word: word, reason: .duplicate))
                continue
            }
            if let reason = reject(word, by: requirements) {
                rejected.append(Rejected(word: word, reason: reason))
                continue
            }
            usable.append(word)
        }

        return Fit(usable: usable, rejected: rejected,
                   shortfall: max(0, requirements.wordCount.lowerBound - usable.count))
    }

    /// The first reason `word` fails `requirements`, or nil when it is playable.
    static func reject(_ word: GameWord, by requirements: GameWordRequirements) -> Rejection? {
        if requirements.singleTokenOnly, !GameLetters.isSingleToken(word.german) { return .multiToken }
        if requirements.needsEnglish, word.english.isEmpty { return .noEnglish }

        // ß is resolved before the length check, because `.expandToSS` makes the word longer.
        guard let letters = GameLetters.applying(requirements.eszett, to: word.letters) else {
            return .eszett
        }
        if letters.count < requirements.lengthRange.lowerBound { return .tooShort(letters.count) }
        if letters.count > requirements.lengthRange.upperBound { return .tooLong(letters.count) }
        if let bad = GameLetters.firstUnplayable(in: letters, alphabet: requirements.alphabet,
                                                 allowsEszett: requirements.allowsEszett) {
            return .outOfAlphabet(bad)
        }
        return nil
    }

    /// The words for one round: a seeded pick the game can actually build.
    ///
    /// Asks the game's `canBuild` and, on a refusal, drops the **longest** word and tries again —
    /// a long word is the one most likely to have no room and the fewest crossings, so dropping it
    /// is what usually turns a refusal into a puzzle. `nil` only when the attempts run out or
    /// there were never enough words.
    static func round<Shape: GameRoundShape>(_ shape: Shape.Type, from fit: Fit, seed: UInt64,
                                             attempts: Int = 12) -> [GameWord]? {
        round(Shape.requirements, canBuild: { Shape.canBuild($0, seed: $1) },
              from: fit, seed: seed, attempts: attempts)
    }

    /// The same, for a caller that only knows which game at runtime. The generic form above is
    /// the one tests and generators use; this is what the setup screen calls.
    static func round(_ requirements: GameWordRequirements,
                      canBuild: ([GameWord], UInt64) -> Bool,
                      from fit: Fit, seed: UInt64, attempts: Int = 12) -> [GameWord]? {
        guard fit.usable.count >= requirements.wordCount.lowerBound else { return nil }

        var generator = SeededGenerator(seed: seed)
        var pool = fit.usable.shuffled(using: &generator)

        for attempt in 0..<max(1, attempts) {
            guard pool.count >= requirements.wordCount.lowerBound else { return nil }
            let pick = Array(pool.prefix(requirements.wordCount.upperBound))
            if canBuild(pick, seed &+ UInt64(attempt)) { return pick }

            guard let longest = pick.indices.max(by: { pick[$0].length < pick[$1].length }) else { return nil }
            let dropped = pick[longest].id
            pool.removeAll { $0.id == dropped }
        }
        return nil
    }
}
