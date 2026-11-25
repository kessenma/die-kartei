//
//  HangmanMotif.swift
//  german-ai-flashcards
//
//  What stands in for the gallows. Nobody hangs in this game: each motif is six parts that come
//  or go as the misses mount, with die Figur beside or atop them.
//
//  The raw values name the shipped scene assets (`galgen3d-<raw>.usdz`), so they are not renamed.
//

import Foundation

nonisolated enum HangmanMotif: String, CaseIterable, Identifiable, Sendable {
    /// Die Figur stands on a block tower; each miss takes a block and drops it a level.
    case turm
    /// Die Figur rides a balloon that sinks a little with every miss.
    case ballon
    /// An abstract beam structure assembles over six misses while die Figur watches.
    case geruest

    var id: String { rawValue }

    static let `default`: HangmanMotif = .turm

    var germanTitle: String {
        switch self {
        case .turm:    "Der Turm"
        case .ballon:  "Der Ballon"
        case .geruest: "Das Gerüst"
        }
    }

    var englishTitle: String {
        switch self {
        case .turm:    "The tower"
        case .ballon:  "The balloon"
        case .geruest: "The scaffold"
        }
    }

    var blurb: String {
        switch self {
        case .turm:    "Blocks fall away under your feet"
        case .ballon:  "The balloon sinks toward the ground"
        case .geruest: "Beams go up, one per miss"
        }
    }

    /// The bundled scene, and the stills that stand in for it when live graphics are off.
    var asset: String { "galgen3d-\(rawValue)" }

    /// The six parts the runtime hides as misses mount. Authored in Blender under these names;
    /// the runtime matches prims by substring, so they carry no dots.
    static let partNames: [String] = (1...6).map { "teil_\($0)" }

    /// The clips every motif ships, selected by **exact** name at playback.
    enum Clip: String, Sendable {
        case warten
        case jubel
        case kummer
    }
}
