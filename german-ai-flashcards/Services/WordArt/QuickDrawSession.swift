import Foundation
import Observation

/// One Quick Draw run, as a state machine with no UI in it: which word is up, how long it has,
/// what was drawn, and which sketches the learner keeps.
///
/// A turn is: draw → (recall runs) reveal and mark → next. The clock running out ends the drawing
/// part exactly like Next does. The ink is handed in by the screen when a turn ends, since only
/// the canvas holds it.
@Observable
@MainActor
final class QuickDrawSession {
    enum Phase: Equatable {
        case drawing
        /// Recall runs: the meaning and the picture are shown, waiting for "knew it / didn't".
        case reveal
        case finished
    }

    struct Turn: Identifiable {
        let word: ZeichnenWord
        /// The sketch, nil when the page was left blank.
        var ink: Data?
        /// Recall runs: whether the learner knew it. Nil in copy runs.
        var recalled: Bool?
        var seconds: Int

        var id: UUID { word.id }
        var drewSomething: Bool { ink != nil }
    }

    let words: [ZeichnenWord]
    let mode: QuickDrawMode
    let secondsPerWord: Int
    private let now: () -> Date

    private(set) var index = 0
    private(set) var phase: Phase
    private(set) var turns: [Turn] = []
    /// When the current word went up.
    private(set) var turnStartedAt: Date
    /// Bumped every turn, so a view's `.task(id:)` restarts the clock.
    private(set) var turnID = 0
    /// Sketches to keep, by card id.
    var keep: Set<UUID> = []
    let keepByDefault: Bool
    let startedAt: Date

    /// The ink of the turn waiting on its reveal.
    private var pendingInk: Data?
    private var pendingSeconds = 0

    init(words: [ZeichnenWord], mode: QuickDrawMode, secondsPerWord: Int, keepByDefault: Bool,
         now: @escaping () -> Date = Date.init) {
        self.words = words
        self.mode = mode
        self.secondsPerWord = max(5, secondsPerWord)
        self.keepByDefault = keepByDefault
        self.now = now
        let start = now()
        self.startedAt = start
        self.turnStartedAt = start
        self.phase = words.isEmpty ? .finished : .drawing
    }

    var current: ZeichnenWord? { words.indices.contains(index) ? words[index] : nil }
    var deadline: Date { turnStartedAt.addingTimeInterval(TimeInterval(secondsPerWord)) }
    var progressLabel: String { "\(min(index + 1, words.count)) / \(words.count)" }

    func remaining(at date: Date) -> TimeInterval { max(0, deadline.timeIntervalSince(date)) }

    /// Next, or the clock ran out: the drawing part of this turn is over.
    func endDrawing(ink: Data?) {
        guard phase == .drawing, current != nil else { return }
        let seconds = min(secondsPerWord, max(0, Int(now().timeIntervalSince(turnStartedAt).rounded())))
        switch mode {
        case .copy:
            commit(ink: ink, recalled: nil, seconds: seconds)
        case .recall:
            pendingInk = ink
            pendingSeconds = seconds
            phase = .reveal
        }
    }

    /// Recall runs: the learner's own verdict after the reveal.
    func mark(knewIt: Bool) {
        guard phase == .reveal else { return }
        commit(ink: pendingInk, recalled: knewIt, seconds: pendingSeconds)
        pendingInk = nil
        pendingSeconds = 0
    }

    /// The ink of the turn being revealed, for the side-by-side.
    var revealInk: Data? { phase == .reveal ? pendingInk : nil }

    /// Stop early: what was drawn so far goes to the review.
    func finishEarly() {
        if phase == .reveal { mark(knewIt: false) }
        phase = .finished
    }

    private func commit(ink: Data?, recalled: Bool?, seconds: Int) {
        guard let word = current else { return }
        turns.append(Turn(word: word, ink: ink, recalled: recalled, seconds: seconds))
        if keepByDefault, ink != nil { keep.insert(word.id) }
        index += 1
        if index >= words.count {
            phase = .finished
        } else {
            phase = .drawing
            turnStartedAt = now()
            turnID += 1
        }
    }

    // MARK: - The review

    var drawnTurns: [Turn] { turns.filter(\.drewSomething) }
    var missed: [Turn] { turns.filter { $0.recalled == false } }
    var recalledCount: Int { turns.filter { $0.recalled == true }.count }
    var totalSeconds: Int { turns.reduce(0) { $0 + $1.seconds } }

    func toggleKeep(_ id: UUID) {
        guard turns.contains(where: { $0.id == id && $0.drewSomething }) else { return }
        if keep.contains(id) { keep.remove(id) } else { keep.insert(id) }
    }

    func keepAll() { keep = Set(drawnTurns.map(\.id)) }
    func keepNone() { keep = [] }

    var turnsToKeep: [Turn] { turns.filter { keep.contains($0.id) && $0.drewSomething } }
}
