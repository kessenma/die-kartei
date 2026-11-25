//
//  EndingBlocksState.swift
//  german-ai-flashcards
//
//  What the 3D ending blocks show, and how they move between two shows. A word is two blocks on
//  a plate: the stem in plain ink (d, ein, mein, dies), the ending in its case color (er, em, en),
//  and a thin plate in the noun's gender color. The case is what changes, so the case color sits
//  where the change happens.
//
//  Pure on purpose: the canvas and the flat 2D twin both read these poses, and the tests check
//  them without a renderer. Times are seconds since the state changed.
//

import Foundation

/// One word on the plate.
nonisolated enum EndingBlocksState: Hashable, Sendable {
    /// The stem with an empty grey slot: a question still open. Grey, so the slot never gives the
    /// case away before the pick.
    case open(stem: String, genus: Gender)
    /// The finished word. `rejected` is a wrong pick's ending, which lands grey and bounces off
    /// before the right one snaps in.
    case built(KasusFormParts, kasus: GrammarCase, genus: Gender, rejected: String? = nil)

    var stem: String {
        switch self {
        case .open(let stem, _):        stem
        case .built(let parts, _, _, _): parts.stem
        }
    }

    /// The ending the slot holds: "" both for an open question and for an ein-word with none.
    var ending: String {
        switch self {
        case .open:                      ""
        case .built(let parts, _, _, _): parts.ending
        }
    }

    var genus: Gender {
        switch self {
        case .open(_, let genus), .built(_, _, let genus, _): genus
        }
    }

    /// Nil while the question is open.
    var kasus: GrammarCase? {
        if case .built(_, let kasus, _, _) = self { return kasus }
        return nil
    }

    var rejected: String? {
        if case .built(_, _, _, let rejected) = self { return rejected }
        return nil
    }

    var isOpen: Bool { kasus == nil }

    /// „dem: d plus em. Dativ, masculine.“ One element for VoiceOver, never the pieces.
    var accessibilityLabel: String {
        switch self {
        case .open(let stem, let genus):
            return "\(stem), ending still open. \(genus.genderName.capitalized)."
        case .built(let parts, let kasus, let genus, _):
            let pieces = parts.hasEnding ? "\(parts.stem) plus \(parts.ending)" : "no ending"
            return "\(parts.word): \(pieces). \(kasus.name), \(genus.genderName)."
        }
    }
}

/// How the blocks get from one state to the next.
nonisolated enum EndingBlocksTransition: Hashable, Sendable {
    /// Nothing moves.
    case hold
    /// A new stem: the whole word drops onto the plate.
    case rise
    /// An open slot gets its ending.
    case snap
    /// Same stem, another ending (or back to an open slot): the old one flies off, the new drops in.
    case swap(from: String, wasOpen: Bool)
    /// A wrong ending lands grey, bounces off, and the right one snaps in.
    case bounceThenSnap(wrong: String)
    /// The same ending in another case (die: Nom → Akk): it hops in place and takes the new color.
    /// The form didn't change, and that is the point.
    case recolor

    init(from previous: EndingBlocksState?, to next: EndingBlocksState) {
        guard let previous, previous.stem == next.stem else { self = .rise; return }
        if previous == next { self = .hold; return }
        if let wrong = next.rejected, previous.isOpen { self = .bounceThenSnap(wrong: wrong); return }
        if previous.isOpen && !next.isOpen { self = .snap; return }
        if previous.ending == next.ending && previous.isOpen == next.isOpen {
            // Same blocks: the ending hops and takes its new case color, or, for another gender
            // in the same case (dem: m. and n. Dativ), only the plate changes.
            self = previous.kasus != next.kasus ? .recolor : .hold
            return
        }
        self = .swap(from: previous.ending, wasOpen: previous.isOpen)
    }

    /// Seconds until the last block settles.
    var duration: Double {
        switch self {
        case .hold:           0
        case .rise:           0.55
        case .snap:           0.5
        case .swap:           0.62
        case .bounceThenSnap: 1.0
        case .recolor:        0.4
        }
    }

    /// The incoming ending's drop: when it starts and how long it falls.
    fileprivate var drop: (start: Float, length: Float)? {
        switch self {
        case .hold, .rise, .recolor: nil
        case .snap:            (0, 0.5)
        case .swap:            (0.16, 0.46)
        case .bounceThenSnap:  (0.55, 0.45)
        }
    }
}

/// Where every block is at one moment, as offsets from its seat on the plate. Units are the
/// stem's letter height (1 = the height of a „d“).
nonisolated struct EndingBlocksPose: Equatable, Sendable {
    /// The whole word, on a rise.
    var wordDrop: Float = 0
    var wordScale: Float = 1
    /// The incoming ending (or empty slot) above its seat.
    var endingDrop: Float = 0
    var endingScale: Float = 1
    /// 0 = still grey, 1 = in its case color. The color arrives on contact.
    var endingTint: Float = 1
    /// The old ending on its way out, nil once gone.
    var outgoing: Exit?
    /// The wrong ending, nil when there is none or once it has gone.
    var rejected: Exit?
    /// 0…1: the stem's squash when an ending lands on it.
    var stemSquash: Float = 0

    nonisolated struct Exit: Equatable, Sendable {
        var dx: Float = 0
        var dy: Float = 0
        var roll: Float = 0
        var scale: Float = 1
    }

    /// The resting pose: everything seated, everything in color.
    static let settled = EndingBlocksPose()

    /// How far above its seat a block starts its fall.
    static let dropHeight: Float = 1.6

    static func at(_ transition: EndingBlocksTransition, time t: Float) -> EndingBlocksPose {
        var pose = EndingBlocksPose()
        switch transition {
        case .hold:
            return .settled

        case .rise:
            let p = progress(t, 0, 0.5)
            pose.wordDrop = 1.2 * (1 - easeOutBack(p))
            pose.wordScale = 0.86 + 0.14 * easeOut(p)
            pose.stemSquash = bump(t, at: 0.36)
            return pose

        case .recolor:
            let p = progress(t, 0, 0.36)
            guard p < 1 else { return .settled }
            pose.endingDrop = 0.35 * sin(p * .pi)
            pose.endingTint = p
            return pose

        case .snap, .swap:
            break

        case .bounceThenSnap:
            // In: the wrong block falls onto the seat. Out: it rebounds up and to the right,
            // rolling, and drops out of frame.
            let fall = progress(t, 0, 0.26)
            let off = progress(t, 0.26, 0.4)
            if off < 1 {
                var exit = Exit()
                if fall < 1 {
                    exit.dy = dropHeight * (1 - fall * fall)
                } else {
                    exit.dx = 1.3 * off
                    exit.dy = 1.5 * off - 3.6 * off * off
                    exit.roll = -1.4 * off
                    exit.scale = 1 - 0.3 * off
                }
                pose.rejected = exit
            }
        }

        if case .swap = transition {
            let p = progress(t, 0, 0.3)
            if p < 1 {
                pose.outgoing = Exit(dx: 1.1 * easeIn(p), dy: 1.7 * easeIn(p), roll: -0.9 * p, scale: 1 - 0.55 * p)
            }
        }

        if let drop = transition.drop {
            let p = progress(t, drop.start, drop.length)
            pose.endingDrop = dropHeight * (1 - easeOutBack(p))
            pose.endingScale = p <= 0 ? 0.001 : 1
            let landing = drop.start + drop.length * 0.62
            pose.endingTint = progress(t, landing - 0.02, 0.16)
            pose.stemSquash = bump(t, at: landing)
        }
        if case .bounceThenSnap = transition {
            pose.stemSquash = max(pose.stemSquash, 0.6 * bump(t, at: 0.26))
        }
        return pose
    }

    // MARK: Easing

    private static func progress(_ t: Float, _ start: Float, _ length: Float) -> Float {
        guard length > 0 else { return t >= start ? 1 : 0 }
        return min(1, max(0, (t - start) / length))
    }

    private static func easeOut(_ p: Float) -> Float { 1 - (1 - p) * (1 - p) }
    private static func easeIn(_ p: Float) -> Float { p * p }

    /// Overshoots a little and settles: the snap.
    private static func easeOutBack(_ p: Float) -> Float {
        let c1: Float = 1.3, c3 = c1 + 1
        let q = p - 1
        return 1 + c3 * q * q * q + c1 * q * q
    }

    /// A 0…1…0 tent 0.24 s wide, peaking at `at`.
    private static func bump(_ t: Float, at peak: Float) -> Float {
        max(0, 1 - abs(t - peak) / 0.12)
    }
}

/// Camera framing for a word of a given size.
nonisolated enum EndingBlocksFraming {
    /// How far back the camera has to sit, on the house angle with a 30° vertical field of view,
    /// so a `width` × `height` word fits a canvas of `aspect` (width / height) with a margin.
    static func distance(width: Float, height: Float, depth: Float, aspect: Float,
                         fieldOfView: Float = 30, margin: Float = 1.18) -> Float {
        let tanHalf = tan(fieldOfView * .pi / 360)
        let safeAspect = max(aspect, 0.2)
        let forHeight = (height / 2) / tanHalf
        let forWidth = (width / 2) / (tanHalf * safeAspect)
        return max(forHeight, forWidth) * margin + depth / 2
    }
}
