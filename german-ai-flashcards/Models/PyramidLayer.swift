//
//  PyramidLayer.swift
//  german-ai-flashcards
//
//  The six layers of the Lernpyramide — the learning path you build from foundation to peak.
//  Identity and presentation live here; the *fill math* (which real mastery signals drive each
//  layer) lives in `PyramidService`, and the 3D rendering in `PyramidView`.
//
//  The structure mirrors how the app teaches: prepositions are the literal foundation (every
//  sentence stands on its case), vocabulary and stories build on that, the grammar core locks it
//  in, A2 deepens it, and conversation — production, the hardest skill — is the peak.
//

import SwiftUI

enum PyramidLayerID: String, CaseIterable, Identifiable {
    /// Bottom → top, the order they stack.
    case fundament, wortschatzA1, geschichtenA1, grammatikKern, vertiefungA2, spitze

    var id: String { rawValue }

    /// Position from the top (0 = Spitze) — the drawing order for both the 2D glyph and the 3D stack.
    var indexFromTop: Int { Self.allCases.count - 1 - indexFromBottom }

    var indexFromBottom: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var germanTitle: String {
        switch self {
        case .fundament:      "Fundament"
        case .wortschatzA1:   "Wortschatz A1"
        case .geschichtenA1:  "Geschichten A1"
        case .grammatikKern:  "Grammatik-Kern"
        case .vertiefungA2:   "Vertiefung A2"
        case .spitze:         "Spitze"
        }
    }

    var englishSubtitle: String {
        switch self {
        case .fundament:      "Prepositions — every sentence stands on its case"
        case .wortschatzA1:   "A1 words you've proven you know"
        case .geschichtenA1:  "A1 stories read and understood"
        case .grammatikKern:  "Akkusativ · Dativ · Artikel · Präpositionen, solid"
        case .vertiefungA2:   "A2 words and stories, deepening the structure"
        case .spitze:         "Conversation — the peak is speaking"
        }
    }

    var systemImage: String {
        switch self {
        case .fundament:      "arrow.triangle.branch"
        case .wortschatzA1:   "text.book.closed"
        case .geschichtenA1:  "book.pages"
        case .grammatikKern:  "checklist"
        case .vertiefungA2:   "text.book.closed.fill"
        case .spitze:         "bubble.left.and.bubble.right.fill"
        }
    }

    /// Follows the app's activity color language (matching the category tiles and the streak
    /// calendar's timeline), so a layer reads the same wherever it appears.
    var tint: Color {
        switch self {
        case .fundament:      .orange
        case .wortschatzA1:   .blue
        case .geschichtenA1:  .pink
        case .grammatikKern:  .purple
        case .vertiefungA2:   .indigo
        case .spitze:         .green
        }
    }
}

// MARK: - Layer state

/// A layer with its current fill, as computed by `PyramidService` from live data.
///
/// The fill has two channels, and the difference between them is the whole point of the pyramid:
/// `earnedFill` is German the learner has **proven in this app**, `provisionalFill` is German the
/// placement estimate says they already know but haven't re-proven here yet. Solid vs. ghost. A
/// learner who arrives at B2 sees a mostly-outlined pyramid on day one instead of an empty one,
/// and it solidifies as they use the app.
struct PyramidLayerState: Identifiable {
    let id: PyramidLayerID
    /// 0…1 — proven here, in this app.
    let earnedFill: Double
    /// 0…1 — credited by the placement estimate and not yet re-proven. Only ever shrinks: in-app
    /// evidence either converts it to `earnedFill` or refutes it.
    let provisionalFill: Double
    /// The concrete "what's left" line, e.g. "12 of 28 prepositions mastered".
    let detail: String

    init(id: PyramidLayerID, earnedFill: Double, provisionalFill: Double = 0, detail: String) {
        self.id = id
        self.earnedFill = earnedFill
        self.provisionalFill = provisionalFill
        self.detail = detail
    }

    /// Everything the learner is credited with — proven plus estimated. What the bars draw.
    var fill: Double { min(1, earnedFill + provisionalFill) }

    /// Completion means *proven*. Celebrations and badges read this, so answering a placement quiz
    /// can never trigger confetti or earn an Abzeichen.
    var isComplete: Bool { earnedFill >= 1 }

    var hasStarted: Bool { fill > 0 }

    /// Whether any of this layer is standing on an estimate rather than proof — drives the ghost
    /// rendering and the "· N estimated" half of the detail line.
    var hasEstimate: Bool { provisionalFill > 0.0001 }
}
