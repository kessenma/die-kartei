import Foundation
import SwiftData

/// Session-scoped coordinator for **spaced re-encounter** — surfacing SRS-due vocabulary inside a
/// live conversation and advancing a card's real interval when the learner uses the word correctly.
///
/// Built once per session by `ConversationEngine` (gated by the `chatSpacedReview` setting and its
/// `SpacedReviewScope`). It holds live `SavedCard` references, so a correct re-encounter advances
/// the very same card the flashcard decks schedule from — spaced repetition happening in dialogue.
@MainActor
final class ConversationReviewTracker {

    /// Cap on how many due words we steer toward / track — keeps the injected prompt focused.
    nonisolated static let wordCap = 8

    private let modelContext: ModelContext
    /// Due cards still awaiting a correct re-encounter this session, most-overdue first.
    private var pending: [SavedCard]
    /// Words advanced this session (bare `germanWord`), in the order they were reviewed.
    private(set) var reviewedWords: [String] = []

    private init(pending: [SavedCard], in context: ModelContext) {
        self.pending = pending
        self.modelContext = context
    }

    /// Build a tracker for this session, or `nil` if spaced review doesn't apply to this mode (per
    /// `scope`) or nothing is currently due. Deck chats prioritize their own decks, then top up
    /// library-wide when the scope allows it.
    static func make(
        scope: SpacedReviewScope,
        mode: ConversationMode,
        deckIDs: [UUID],
        in context: ModelContext,
        limit: Int = wordCap
    ) -> ConversationReviewTracker? {
        guard scope.applies(to: mode) else { return nil }

        var cards = SpacedRepetitionService.dueCards(forDeckIDs: deckIDs, in: context)
        if scope.allowsLibraryWide(for: mode), cards.count < limit {
            let seen = Set(cards.map(\.id))
            cards += SpacedRepetitionService.allDueCards(in: context).filter { !seen.contains($0.id) }
        }
        cards = Array(cards.prefix(limit))

        guard !cards.isEmpty else { return nil }
        return ConversationReviewTracker(pending: cards, in: context)
    }

    /// German words still due — injected (as `dueDisplayWords`) into the system prompt so the coach
    /// steers the learner toward re-using them.
    var hasDueWords: Bool { !pending.isEmpty }

    /// Article-prefixed display forms for the prompt (nicer than the bare noun).
    var dueDisplayWords: [String] {
        pending.map { $0.germanWord.withArticle($0.article) }
    }

    /// Evaluate one finished user turn. Advances (rating `.good`) every pending due card the learner
    /// used correctly — the word appears in their turn and, if the turn was corrected, still appears
    /// in the corrected sentence (so a word the fix rewrote isn't credited). Returns the words newly
    /// reviewed this turn, for the message chip.
    @discardableResult
    func registerTurn(text: String, correctedText: String?) -> [String] {
        guard !pending.isEmpty else { return [] }

        let targets = pending.map(\.germanWord)
        let used = ConversationPrompts.matchedWords(in: text, targetWords: targets)
        guard !used.isEmpty else { return [] }

        // If the turn was corrected, only credit words the correction left intact.
        let credited: Set<String>
        if let fixed = correctedText, !fixed.isEmpty {
            credited = Set(ConversationPrompts.matchedWords(in: fixed, targetWords: used))
        } else {
            credited = Set(used)
        }
        guard !credited.isEmpty else { return [] }

        var advanced: [String] = []
        pending.removeAll { card in
            guard credited.contains(card.germanWord) else { return false }
            SpacedRepetitionService.apply(rating: .good, to: card)
            advanced.append(card.germanWord)
            return true
        }
        if !advanced.isEmpty {
            reviewedWords.append(contentsOf: advanced)
            try? modelContext.save()
        }
        return advanced
    }
}
