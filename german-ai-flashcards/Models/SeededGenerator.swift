//
//  SeededGenerator.swift
//  german-ai-flashcards
//
//  A tiny seeded PRNG (xorshift), for the places that need "random" to be *reproducible*:
//  a computed card deck whose shuffle must not change on every redraw, the placement debug
//  seeder, where a fixed seed is what makes a repeated question actually repeat, and the Spiele
//  generators, where the seed *is* the puzzle.
//
//  `nonisolated` so the pure generators can use it off the main actor — without that the games
//  would need their own copy, which is how `KasusSeededRandom` came about.
//

import Foundation

nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
