//
//  JobVocabBasket.swift
//  german-ai-flashcards
//
//  Sammeln · Collect: the words picked while reading a job ad, before they become cards. A tap
//  (in Collect mode), a Pencil mark (always), a selection, or a tick in the word list puts a word
//  here; the tray at the bottom of the reader counts them, and „Add to deck“ turns the lot into
//  cards in one go (`JobVocabSaveSheet`). The double-tap inspector stays what it was — one word,
//  translated now — for the times the learner wants the meaning before deciding.
//

import Foundation

/// One picked word or phrase, with the sentence it came from.
struct JobVocabPick: Identifiable, Hashable {
    var id = UUID()
    var german: String
    var example: String?

    var isPhrase: Bool { CardKind.split(german).isPhrase }
    var key: String { CardKind.matchKey(german) }
}

@Observable
@MainActor
final class JobVocabBasket {
    private(set) var picks: [JobVocabPick] = []

    var isEmpty: Bool { picks.isEmpty }
    var count: Int { picks.count }

    func contains(_ german: String) -> Bool {
        let key = CardKind.matchKey(german)
        return picks.contains { $0.key == key }
    }

    /// A tap: in when it wasn't, out when it was.
    func toggle(_ german: String, example: String?) {
        let key = CardKind.matchKey(german)
        if let index = picks.firstIndex(where: { $0.key == key }) {
            picks.remove(at: index)
        } else {
            add(german, example: example)
        }
    }

    /// Add unless already there. Returns whether it was added.
    @discardableResult
    func add(_ german: String, example: String?) -> Bool {
        let cleaned = german.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !cleaned.isEmpty, !contains(cleaned) else { return false }
        picks.append(JobVocabPick(german: cleaned, example: example))
        return true
    }

    func remove(_ id: JobVocabPick.ID) {
        picks.removeAll { $0.id == id }
    }

    func remove(keys: Set<String>) {
        picks.removeAll { keys.contains($0.key) }
    }

    func clear() { picks.removeAll() }

    /// Lowercased single words, for the reader's marker wash.
    var markedWords: Set<String> {
        Set(picks.filter { !$0.isPhrase }.map { $0.german.lowercased() })
    }

    /// Picked phrases, marked wherever they stand in the text.
    var markedPhrases: [String] {
        picks.filter(\.isPhrase).map(\.german)
    }
}

/// A stretch of several words waiting for the learner's answer: one phrase card, a card per word,
/// or both.
struct JobVocabSpanChoice: Identifiable {
    let id = UUID()
    let span: String
    let words: [String]
    let example: String?
}
